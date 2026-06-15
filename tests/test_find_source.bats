#!/usr/bin/env bats
# test cmd-find-source.sh: locate source JAR (no extraction)

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

@test "cmd_find_source returns CACHED on cache hit" {
  update_index "com.a:b:1.0" "source" "/some/path/b-1.0-sources.jar"
  run cmd_find_source "com.a" "b" "1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == CACHED:* ]]
}

@test "cmd_find_source records source JAR path in index" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson" "com.google.gson.GsonBuilder"
  cmd_find_source "com.google.code.gson" "gson" "2.11.0"
  grep -q "com.google.code.gson:gson:2.11.0" "$INDEX_FILE"
  # TSV: type column is "source" (no quotes)
  grep -q "	source	" "$INDEX_FILE"
  # Path should point to the JAR file, not a directory
  grep -q "\.jar" "$INDEX_FILE"
}

@test "cmd_find_source builds class index in lookup file" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo" "com.example.Bar"
  cmd_find_source "com.a" "lib" "1.0"
  grep -q "com.example.Foo.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
  grep -q "com.example.Bar.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
}

@test "cmd_find_source does NOT create sources/ directory" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  cmd_find_source "com.a" "lib" "1.0"
  # sources/ should not be created (or should be empty)
  local src_count
  src_count=$(find "${CACHE_ROOT}/sources" -name "*.java" 2>/dev/null | wc -l | tr -d ' ')
  [ "$src_count" -eq 0 ]
}

@test "cmd_find_source returns SOURCE with JAR path" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  run cmd_find_source "com.a" "lib" "1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == SOURCE:*.jar ]]
}

@test "cmd_find_source errors when no artifacts exist" {
  mkdir -p "${GRADLE_CACHE}/com.a/lib/1.0"
  run cmd_find_source "com.a" "lib" "1.0"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "cmd_find_source errors when cache dir missing" {
  run cmd_find_source "com.nonexist" "missing" "9.9"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}
