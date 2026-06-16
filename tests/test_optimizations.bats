#!/usr/bin/env bats
# TDD tests for optimization items discovered during code review.
# These tests are written BEFORE the code changes to define expected behavior.
#
# Coverage:
#   P0 #9  — GRADLE_USER_HOME support
#   P1 #4  — _scan_gradle_for_class uses unzip instead of jar tf
#   P1 #5  — find-class Layer 1 does NOT call rebuild_lookup_from_class_index
#   P2 #7  — version.sh limits search depth
#   P2 #10 — CFR/Fernflower decompile output path consistency

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

# ══════════════════════════════════════════════════════════════
# P0 #9: GRADLE_USER_HOME support
# ══════════════════════════════════════════════════════════════

@test "common.sh respects GRADLE_USER_HOME for GRADLE_CACHE path" {
  # When GRADLE_USER_HOME is set, GRADLE_CACHE should derive from it
  local custom_home="${TEST_TMPDIR}/custom-gradle-home"
  mkdir -p "${custom_home}/caches/modules-2/files-2.1"

  # Re-source common.sh with GRADLE_USER_HOME set
  GRADLE_USER_HOME="$custom_home" source "${SCRIPTS_DIR}/common.sh"

  [[ "$GRADLE_CACHE" == "${custom_home}/caches/modules-2/files-2.1" ]]
}

@test "common.sh respects GRADLE_USER_HOME for CACHE_ROOT path" {
  local custom_home="${TEST_TMPDIR}/custom-gradle-home"
  mkdir -p "$custom_home"

  GRADLE_USER_HOME="$custom_home" source "${SCRIPTS_DIR}/common.sh"

  [[ "$CACHE_ROOT" == "${custom_home}/android-lib-reader" ]]
}

@test "common.sh uses default HOME/.gradle when GRADLE_USER_HOME is unset" {
  unset GRADLE_USER_HOME
  source "${SCRIPTS_DIR}/common.sh"

  [[ "$GRADLE_CACHE" == "${HOME}/.gradle/caches/modules-2/files-2.1" ]]
  [[ "$CACHE_ROOT" == "${HOME}/.gradle/android-lib-reader" ]]
}

# ══════════════════════════════════════════════════════════════
# P1 #4: _scan_gradle_for_class should work with unzip -Z -1
# ══════════════════════════════════════════════════════════════

@test "_scan_gradle_for_class finds class in source JAR" {
  create_mock_source_jar "com.squareup.okhttp3" "okhttp" "4.12.0" \
    "okhttp3.OkHttpClient" "okhttp3.Request"

  local result
  result=$(_scan_gradle_for_class "okhttp3/OkHttpClient.java" "okhttp3/OkHttpClient.kt")
  [ -n "$result" ]
  [[ "$result" == *"sources.jar"* ]]
}

@test "_scan_gradle_for_class returns empty for missing class" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"

  local result
  result=$(_scan_gradle_for_class "com/nonexist/Bar.java" "com/nonexist/Bar.kt")
  [ -z "$result" ]
}

# ══════════════════════════════════════════════════════════════
# P1 #5: find-class Layer 1 should NOT rebuild entire lookup
# ══════════════════════════════════════════════════════════════

@test "cmd_find_class Layer 1 does not call full rebuild_lookup" {
  # Create a source JAR that is NOT in the index (forces Layer 1 scan)
  create_mock_source_jar "com.squareup.okhttp3" "okhttp" "4.12.0" \
    "okhttp3.OkHttpClient"

  # Pre-populate class index with some unrelated entries
  echo "########## com.unrelated:lib:1.0" >> "$CLASS_INDEX_FILE"
  echo "com.unrelated.Foo" >> "$CLASS_INDEX_FILE"
  printf 'com.unrelated.Foo\tcom.unrelated:lib:1.0\n' >> "$CLASS_LOOKUP_FILE"
  touch "$LOOKUP_SORTED_FLAG"

  run cmd_find_class "okhttp3.OkHttpClient"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FOUND:"* ]]

  # After finding, the LOOKUP_SORTED_FLAG should be removed (dirty)
  # indicating lazy re-sort, NOT a full rebuild
  [ ! -f "$LOOKUP_SORTED_FLAG" ]

  # The new class should be appended to lookup file
  grep -q "okhttp3.OkHttpClient" "$CLASS_LOOKUP_FILE"
}

# ══════════════════════════════════════════════════════════════
# P2 #7: version.sh should handle deeply nested projects
# ══════════════════════════════════════════════════════════════

@test "resolve_project_version finds version in nested build.gradle" {
  mkdir -p "${TEST_PROJECT_ROOT}/app"
  cat > "${TEST_PROJECT_ROOT}/app/build.gradle" << 'GRADLE'
dependencies {
    implementation "com.google.code.gson:gson:2.11.0"
}
GRADLE

  local result
  result=$(resolve_project_version "com.google.code.gson" "gson")
  [ "$result" = "2.11.0" ]
}

@test "resolve_project_version works with version catalog ref" {
  mkdir -p "${TEST_PROJECT_ROOT}/gradle"
  cat > "${TEST_PROJECT_ROOT}/gradle/libs.versions.toml" << 'TOML'
[versions]
gson = "2.11.0"

[libraries]
gson = { module = "com.google.code.gson:gson", version.ref = "gson" }
TOML

  local result
  result=$(resolve_project_version "com.google.code.gson" "gson")
  # Should find "2.11.0" from the version catalog
  [ -n "$result" ]
}

# ══════════════════════════════════════════════════════════════
# P2 #10: Decompile output path handling
# ══════════════════════════════════════════════════════════════

@test "cmd_find_source indexes decompiled dir correctly when no sources/ subdir" {
  # Create a compiled JAR (no source JAR available)
  create_mock_compiled_jar "com.internal" "sdk" "1.0" "com.internal.SdkClass"

  # Mock the decompiler to output directly to dest (like CFR does)
  # Override decompile_jar to simulate CFR behavior
  decompile_jar() {
    local input_jar="$1" output_dir="$2"
    mkdir -p "$output_dir/com/internal"
    echo "public class SdkClass {}" > "$output_dir/com/internal/SdkClass.java"
    return 0
  }

  run cmd_find_source "com.internal" "sdk" "1.0"
  [ "$status" -eq 0 ]

  # Should be indexed — check_index must return a valid path
  local indexed
  indexed=$(check_index "com.internal:sdk:1.0")
  [ -n "$indexed" ]
  [ -d "$indexed" ]
}

@test "cmd_find_source indexes decompiled sources/ subdir correctly (jadx style)" {
  create_mock_compiled_jar "com.internal" "sdk" "2.0" "com.internal.SdkClass2"

  # Mock jadx-style output (creates sources/ subdirectory)
  decompile_jar() {
    local input_jar="$1" output_dir="$2"
    mkdir -p "$output_dir/sources/com/internal"
    echo "public class SdkClass2 {}" > "$output_dir/sources/com/internal/SdkClass2.java"
    return 0
  }

  run cmd_find_source "com.internal" "sdk" "2.0"
  [ "$status" -eq 0 ]

  local indexed
  indexed=$(check_index "com.internal:sdk:2.0")
  [ -n "$indexed" ]
  [[ "$indexed" == *"/sources" ]]
}

# ══════════════════════════════════════════════════════════════
# P1 #6: Temp file cleanup on interruption
# ══════════════════════════════════════════════════════════════

@test "_scan_gradle_for_class cleans up temp files even on empty result" {
  # Run scan with no JARs — should not leave temp files
  local before_count
  before_count=$(ls /tmp/tmp.* 2>/dev/null | wc -l || echo 0)

  _scan_gradle_for_class "com/nonexist/Foo.java" "com/nonexist/Foo.kt" > /dev/null 2>&1 || true

  local after_count
  after_count=$(ls /tmp/tmp.* 2>/dev/null | wc -l || echo 0)

  # Should not leave more temp files than before
  [ "$after_count" -le "$before_count" ]
}
