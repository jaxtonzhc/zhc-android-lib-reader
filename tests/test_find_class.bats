#!/usr/bin/env bats
# test cmd-find-class.sh: class name lookup with on-demand JAR reading

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

# ── Layer 0: index lookup → read from JAR ──

@test "cmd_find_class reads source from JAR via index" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson" "com.google.gson.GsonBuilder"
  cmd_find_source "com.google.code.gson" "gson" "2.11.0" > /dev/null
  # Sort lookup file for binary search
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  run cmd_find_class "com.google.gson.Gson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FOUND:"* ]]
  [[ "$output" == *".jar"* ]]
  [[ "$output" == *"SOURCE:index"* ]]
  [[ "$output" == *"---SOURCE---"* ]]
}

@test "cmd_find_class outputs source content" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  cmd_find_source "com.a" "lib" "1.0" > /dev/null
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  run cmd_find_class "com.example.Foo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"source of com.example.Foo"* ]]
}

@test "cmd_find_class fuzzy match by simple class name" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson"
  cmd_find_source "com.google.code.gson" "gson" "2.11.0" > /dev/null
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  run cmd_find_class "Gson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FUZZY_MATCH:Gson -> com.google.gson.Gson"* ]]
  [[ "$output" == *"FOUND:"* ]]
}

@test "cmd_find_class fuzzy match multiple candidates returns first result" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson"
  create_mock_source_jar "com.other" "lib" "1.0" \
    "com.other.Gson"
  cmd_find_source "com.google.code.gson" "gson" "2.11.0" > /dev/null
  cmd_find_source "com.other" "lib" "1.0" > /dev/null
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  run cmd_find_class "Gson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FUZZY_MATCH"* ]]
  [[ "$output" == *"FOUND:"* ]]
  [[ "$output" == *"---SOURCE---"* ]]
}

@test "cmd_find_class fuzzy match prefers project version" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.8.5" \
    "com.google.gson.Gson"
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson"
  cmd_find_source "com.google.code.gson" "gson" "2.8.5" > /dev/null
  cmd_find_source "com.google.code.gson" "gson" "2.11.0" > /dev/null
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  # 设置项目使用 2.11.0
  create_mock_build_gradle 'dependencies { implementation "com.google.code.gson:gson:2.11.0" }'
  run cmd_find_class "Gson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.11.0"* ]]
  [[ "$output" == *"FOUND:"* ]]
}
@test "cmd_find_class scans Gradle source JARs and reads content" {
  create_mock_source_jar "com.squareup.okhttp3" "okhttp" "4.12.0" \
    "okhttp3.OkHttpClient" "okhttp3.Request"
  run cmd_find_class "okhttp3.OkHttpClient"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FOUND:"* ]]
  [[ "$output" == *"OkHttpClient.java"* ]]
  [[ "$output" == *"source of okhttp3.OkHttpClient"* ]]
}

# ── Version matching ──

@test "cmd_find_class matches project version" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson"
  create_mock_source_jar "com.google.code.gson" "gson" "2.8.9" \
    "com.google.gson.Gson"
  cat > "${TEST_PROJECT_ROOT}/build.gradle" << 'GRADLE'
dependencies {
    implementation "com.google.code.gson:gson:2.11.0"
}
GRADLE
  run cmd_find_class "com.google.gson.Gson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.11.0"* ]]
}

# ── Not found ──

@test "cmd_find_class NOT_FOUND for missing class" {
  run cmd_find_class "com.nonexist.MissingClass"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT_FOUND"* ]]
}

# ── Kotlin support ──

@test "cmd_find_class finds .kt files" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Bar"
  # Create JAR with .kt file instead
  local dir="${TEST_GRADLE_CACHE}/com.a/lib/1.0"
  rm -f "${dir}/lib-1.0-sources.jar"
  local src_dir="${TEST_TMPDIR}/kt_src"
  rm -rf "$src_dir"
  mkdir -p "$src_dir/com/example"
  echo "class Bar" > "$src_dir/com/example/Bar.kt"
  jar cf "${dir}/lib-1.0-sources.jar" -C "$src_dir" .
  rm -rf "$src_dir"

  run cmd_find_class "com.example.Bar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bar.kt"* ]]
}
