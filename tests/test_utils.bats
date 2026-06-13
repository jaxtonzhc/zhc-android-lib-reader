#!/usr/bin/env bats
# test cmd-utils.sh: init / search / tree / list / rebuild-index / clean

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

@test "cmd_init checks tools" {
  run cmd_init
  [[ "$output" == *"environment check"* ]]
}

@test "cmd_search_libs finds matching libs" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" "com.google.gson.Gson"
  create_mock_source_jar "com.squareup.okhttp3" "okhttp" "4.12.0" "okhttp3.OkHttpClient"
  run cmd_search_libs "gson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.google.code.gson:gson:2.11.0"* ]]
  [[ "$output" != *"okhttp"* ]]
}

@test "cmd_search_libs returns empty for no match" {
  run cmd_search_libs "nonexist"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nonexist"* ]]
}

@test "cmd_tree lists files from source JAR" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo" "com.example.Bar"
  run cmd_tree "com.a" "lib" "1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"com/example/Foo.java"* ]]
  [[ "$output" == *"com/example/Bar.java"* ]]
}

@test "cmd_tree errors when not found" {
  run cmd_tree "com.nonexist" "x" "9.9"
  [ "$status" -ne 0 ]
}

@test "cmd_list_cached lists all indexed libs" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  create_mock_source_jar "com.b" "lib" "2.0" "com.example.Bar"
  cmd_find_source "com.a" "lib" "1.0" > /dev/null
  cmd_find_source "com.b" "lib" "2.0" > /dev/null
  run cmd_list_cached
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.a:lib:1.0"* ]]
  [[ "$output" == *"com.b:lib:2.0"* ]]
}

@test "cmd_list_cached shows empty message" {
  run cmd_list_cached
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cache"* ]]
}

@test "cmd_rebuild_index rebuilds class index" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo" "com.example.Bar"
  cmd_find_source "com.a" "lib" "1.0" > /dev/null
  # Clear lookup to simulate needing rebuild
  : > "$CLASS_LOOKUP_FILE"
  run cmd_rebuild_index
  [ "$status" -eq 0 ]
  [[ "$output" == *"Index rebuilt"* ]]
  grep -q "com.example.Foo" "$CLASS_LOOKUP_FILE"
}

@test "cmd_clean clears all cache" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  cmd_find_source "com.a" "lib" "1.0" > /dev/null
  [ -d "$CACHE_ROOT" ]
  run cmd_clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cache cleared"* ]]
  [ ! -d "$CACHE_ROOT" ]
}
