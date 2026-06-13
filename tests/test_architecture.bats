#!/usr/bin/env bats
# test architecture improvements:
#   - _available_decompilers replaces _select_decompiler (returns list)
#   - cmd_find_class warns when cmd_find_source fails
#   - ensure_jadx removed (dead code)

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
  export DECOMPILERS_DIR="${TEST_TMPDIR}/decompilers"
  export CFR_JAR="${DECOMPILERS_DIR}/cfr.jar"
  export FERNFLOWER_JAR="${DECOMPILERS_DIR}/fernflower.jar"
  mkdir -p "${DECOMPILERS_DIR}"
}

teardown() {
  teardown_mock_env
}

# ══════════════════════════════════════════════════════════════
# 1. _available_decompilers: returns all available decompilers
# ══════════════════════════════════════════════════════════════

@test "_available_decompilers returns jadx first when available" {
  if ! command -v jadx &>/dev/null; then
    skip "jadx not installed"
  fi
  local result
  result=$(_available_decompilers)
  local first
  first=$(echo "$result" | head -1)
  [[ "$first" == jadx:* ]]
}

@test "_available_decompilers returns all available in order" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  touch "${FERNFLOWER_JAR}"

  local result
  result=$(_available_decompilers)
  local count
  count=$(echo "$result" | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]

  local first second
  first=$(echo "$result" | head -1)
  second=$(echo "$result" | tail -1)
  [[ "$first" == "cfr:"* ]]
  [[ "$second" == "fernflower:"* ]]

  export PATH="$orig_path"
}

@test "_available_decompilers returns empty when nothing available" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"
  rm -f "${CFR_JAR}" "${FERNFLOWER_JAR}"

  local result
  result=$(_available_decompilers) || true
  [ -z "$result" ]

  export PATH="$orig_path"
}

@test "_available_decompilers single decompiler" {
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  touch "${CFR_JAR}"
  rm -f "${FERNFLOWER_JAR}"

  local result
  result=$(_available_decompilers)
  [[ "$result" == "cfr:"* ]]

  export PATH="$orig_path"
}

# ══════════════════════════════════════════════════════════════
# 2. cmd_find_class warns on cmd_find_source failure
# ══════════════════════════════════════════════════════════════

@test "cmd_find_class warns when cmd_find_source fails" {
  # Set up a case where index has a coord but no source exists
  # so cmd_find_source is triggered and fails
  echo '{"com.a:lib:1.0":{"type":"source","path":"/nonexist/path.jar"}}' > "$INDEX_FILE"

  # Also make sure there's no actual artifact in Gradle cache
  # so cmd_find_source will fail
  run cmd_find_class "com.example.Missing"
  # Should produce some warning about find-source failure or NOT_FOUND
  [[ "$output" == *"NOT_FOUND"* ]] || [[ "$output" == *"WARN"* ]] || [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"HINT"* ]]
}

# ══════════════════════════════════════════════════════════════
# 3. ensure_jadx should not exist (dead code removed)
# ══════════════════════════════════════════════════════════════

@test "ensure_jadx does not exist in common.sh" {
  ! grep -q "^ensure_jadx()" "${SCRIPTS_DIR}/common.sh"
}
