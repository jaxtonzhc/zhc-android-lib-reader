#!/usr/bin/env bats
# test multi-decompiler: fallback chain, auto-retry, architecture redesign
# Tests the NEW architecture where:
#   - _select_decompiler returns priority list (no Java version binding)
#   - decompile_jar auto-retries with fallback decompilers
#   - ensure_decompiler only installs, not called in find-source critical path

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
  export DECOMPILERS_DIR="${TEST_TMPDIR}/decompilers"
  export CFR_JAR="${DECOMPILERS_DIR}/cfr.jar"
  export FERNFLOWER_JAR="${DECOMPILERS_DIR}/fernflower.jar"
  mkdir -p "${DECOMPILERS_DIR}"
  _create_test_input_jar
}

teardown() {
  teardown_mock_env
}

# ── Helpers ──

_create_test_input_jar() {
  local cls_dir="${TEST_TMPDIR}/test_cls"
  mkdir -p "$cls_dir/com/example"
  printf '\xCA\xFE\xBA\xBE\x00\x00\x00\x34\x00\x0A\x00\x00\x00\x00\x00\x00' > "$cls_dir/com/example/Dummy.class"
  jar cf "${TEST_TMPDIR}/test-input.jar" -C "$cls_dir" .
  rm -rf "$cls_dir"
}

# Create mock jadx (standalone binary, called directly by jadx command)
_create_mock_jadx() {
  local succeed="${1:-true}"
  local mock_bin="${TEST_TMPDIR}/mock-bin"
  mkdir -p "$mock_bin"
  if [ "$succeed" = "true" ]; then
    cat > "${mock_bin}/jadx" << 'SCRIPT'
#!/usr/bin/env bash
output_dir=""; prev=""
for arg in "$@"; do
  [[ "$prev" == "-d" ]] && output_dir="$arg"
  prev="$arg"
done
mkdir -p "$output_dir/com/example"
echo "// Decompiled by jadx" > "$output_dir/com/example/Dummy.java"
SCRIPT
  else
    cat > "${mock_bin}/jadx" << 'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  fi
  chmod +x "${mock_bin}/jadx"
}

# Create mock java that delegates to mock decompiler scripts
# Usage: _setup_mock_decompiler_env <cfr_mode> <fernflower_mode>
# Modes: "succeed", "fail", "absent"
_setup_mock_decompiler_env() {
  local cfr_mode="${1:-absent}"
  local ff_mode="${2:-absent}"
  local mock_bin="${TEST_TMPDIR}/mock-bin"
  mkdir -p "$mock_bin"

  # Create mock java that handles -jar cfr.jar / fernflower.jar
  cat > "${mock_bin}/java" << JEOF
#!/usr/bin/env bash
# Version query
if [[ "\$1" == "-version" ]]; then
  echo 'openjdk version "17.0.9" 2023-10-17'
  exit 0
fi

# CFR: java -jar <cfr.jar> <input> --outputdir <dir>
if [[ "\$*" == *"cfr"* ]]; then
  if [ "${cfr_mode}" = "succeed" ]; then
    output_dir=""
    next_is_outdir=false
    for arg in "\$@"; do
      if \$next_is_outdir; then output_dir="\$arg"; next_is_outdir=false; fi
      [[ "\$arg" == "--outputdir" ]] && next_is_outdir=true
    done
    mkdir -p "\$output_dir/com/example"
    echo "// Decompiled by cfr" > "\$output_dir/com/example/Dummy.java"
    exit 0
  else
    exit 0  # fail mode: exit 0 but produce nothing
  fi
fi

# Fernflower: java -jar <fernflower.jar> <input> <dir>
if [[ "\$*" == *"fernflower"* ]]; then
  if [ "${ff_mode}" = "succeed" ]; then
    # Last arg is output dir
    output_dir="\${@: -1}"
    mkdir -p "\$output_dir/com/example"
    echo "// Decompiled by fernflower" > "\$output_dir/com/example/Dummy.java"
    exit 0
  else
    exit 0  # fail mode: exit 0 but produce nothing
  fi
fi

echo "Unknown java invocation: \$*" >&2
exit 1
JEOF
  chmod +x "${mock_bin}/java"
}

# ══════════════════════════════════════════════════════════════
# 1. _select_decompiler: 返回优先级列表，不绑定 Java 版本
# ══════════════════════════════════════════════════════════════

@test "_select_decompiler: jadx always first when available" {
  if ! command -v jadx &>/dev/null; then
    skip "jadx not installed"
  fi
  local result
  result=$(_select_decompiler)
  [[ "$result" == jadx:* ]]
}

@test "_select_decompiler: CFR before Fernflower when both available (no Java version check)" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"

  local result
  result=$(_select_decompiler) || true
  [[ "$result" == "cfr:"* ]]

  export PATH="$orig_path"
}

@test "_select_decompiler: no Java version binding — same result regardless of Java version" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"

  # Mock Java 8
  local mock_bin="${TEST_TMPDIR}/mock-bin"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/java" << 'JEOF'
#!/usr/bin/env bash
echo 'openjdk version "1.8.0_362" 2023-10-17'
JEOF
  chmod +x "${mock_bin}/java"
  export PATH="${mock_bin}:${PATH}"
  local result_java8
  result_java8=$(_select_decompiler) || true

  # Mock Java 21
  cat > "${mock_bin}/java" << 'JEOF'
#!/usr/bin/env bash
echo 'openjdk version "21.0.1" 2023-10-17'
JEOF
  local result_java21
  result_java21=$(_select_decompiler) || true

  # Both should return the same decompiler (no version-based switching)
  [ "$result_java8" = "$result_java21" ]

  export PATH="$orig_path"
}

@test "_select_decompiler: Fernflower only" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  rm -f "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"

  local result
  result=$(_select_decompiler) || true
  [[ "$result" == "fernflower:"* ]]

  export PATH="$orig_path"
}

@test "_select_decompiler: CFR only" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  rm -f "${FERNFLOWER_JAR}"

  local result
  result=$(_select_decompiler) || true
  [[ "$result" == "cfr:"* ]]

  export PATH="$orig_path"
}

@test "_select_decompiler: empty when nothing available" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"
  rm -f "${CFR_JAR}" "${FERNFLOWER_JAR}"

  local result
  result=$(_select_decompiler) || true
  [ -z "$result" ]

  export PATH="$orig_path"
}

# ══════════════════════════════════════════════════════════════
# 2. decompile_jar: 自动降级重试
# ══════════════════════════════════════════════════════════════

@test "decompile_jar: jadx succeeds, no fallback needed" {
  local orig_path="$PATH"
  _create_mock_jadx "true"
  export PATH="${TEST_TMPDIR}/mock-bin:/usr/bin:/bin"

  local output_dir="${TEST_TMPDIR}/jadx_out"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jadx"* ]]

  export PATH="$orig_path"
}

@test "decompile_jar: jadx failure does NOT fall back to CFR/Fernflower" {
  local orig_path="$PATH"
  _create_mock_jadx "false"
  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"
  _setup_mock_decompiler_env "succeed" "succeed"
  export PATH="${TEST_TMPDIR}/mock-bin:/usr/bin:/bin"

  local output_dir="${TEST_TMPDIR}/jadx_fail"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  # Should fail — jadx is highest quality, no fallback
  [ "$status" -ne 0 ]

  export PATH="$orig_path"
}

@test "decompile_jar: CFR fails → auto fallback to Fernflower" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"
  _setup_mock_decompiler_env "fail" "succeed"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  local output_dir="${TEST_TMPDIR}/fallback_cf2ff"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fernflower"* ]]
  grep -q "Decompiled by fernflower" "$output_dir/com/example/Dummy.java"

  export PATH="$orig_path"
}

@test "decompile_jar: Fernflower fails → auto fallback to CFR" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"
  _setup_mock_decompiler_env "succeed" "fail"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  local output_dir="${TEST_TMPDIR}/fallback_ff2cf"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cfr"* ]]
  grep -q "Decompiled by cfr" "$output_dir/com/example/Dummy.java"

  export PATH="$orig_path"
}

@test "decompile_jar: all decompilers fail → returns error" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"
  _setup_mock_decompiler_env "fail" "fail"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  local output_dir="${TEST_TMPDIR}/all_fail"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"All decompilers failed"* ]]

  export PATH="$orig_path"
}

@test "decompile_jar: no decompiler available → returns 1" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"
  rm -f "${CFR_JAR}" "${FERNFLOWER_JAR}"

  local output_dir="${TEST_TMPDIR}/no_dc"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No decompiler"* ]]

  export PATH="$orig_path"
}

@test "decompile_jar: CFR only available, succeeds" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  rm -f "${FERNFLOWER_JAR}"
  _setup_mock_decompiler_env "succeed" "absent"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  local output_dir="${TEST_TMPDIR}/cfr_only"
  run decompile_jar "${TEST_TMPDIR}/test-input.jar" "$output_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cfr"* ]]

  export PATH="$orig_path"
}

# ══════════════════════════════════════════════════════════════
# 3. ensure_decompiler: 仅检查，不自动安装
# ══════════════════════════════════════════════════════════════

@test "ensure_decompiler: returns 0 when decompiler already available" {
  if ! command -v jadx &>/dev/null; then
    skip "jadx not installed"
  fi
  run ensure_decompiler
  [ "$status" -eq 0 ]
}

@test "ensure_decompiler: no auto-install, just reports what's missing" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"
  rm -f "${CFR_JAR}" "${FERNFLOWER_JAR}"

  run ensure_decompiler
  [ "$status" -ne 0 ]
  # Should suggest install, not auto-install
  [[ "$output" == *"Please"* ]]
}

# ══════════════════════════════════════════════════════════════
# 4. cmd_find_source: 不再调 ensure_decompiler
# ══════════════════════════════════════════════════════════════

@test "cmd_find_source: decompile path works without calling ensure_decompiler" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  _setup_mock_decompiler_env "succeed" "absent"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  create_mock_compiled_jar "com.a" "lib" "1.0" "com.example.Foo"

  run cmd_find_source "com.a" "lib" "1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DECOMPILED"* ]]
  # Should NOT call brew install
  [[ "$output" != *"brew"* ]]

  export PATH="$orig_path"
}
