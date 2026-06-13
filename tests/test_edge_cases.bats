#!/usr/bin/env bats
# test edge cases and previously uncovered functions:
#   - find_compiled_artifact (JAR/AAR fallback)
#   - build_class_index_for_coord (directory-based indexing)
#   - _append_compiled_classes / cmd_index_all (full index pipeline)
#   - corrupted JAR / missing classes.jar in AAR
#   - corrupted index.json
#   - paths with spaces

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

# ══════════════════════════════════════════════════════════════
# 1. find_compiled_artifact: JAR/AAR fallback
# ══════════════════════════════════════════════════════════════

@test "find_compiled_artifact finds compiled JAR (not sources)" {
  create_mock_compiled_jar "com.a" "lib" "1.0" "com.example.Foo"
  local result
  result=$(find_compiled_artifact "com.a" "lib" "1.0")
  [ -n "$result" ]
  [[ "$result" == *.jar ]]
  [[ "$result" != *"-sources.jar" ]]
}

@test "find_compiled_artifact falls back to AAR when no JAR" {
  create_mock_aar "com.a" "lib" "1.0" "com.example.Foo"
  local result
  result=$(find_compiled_artifact "com.a" "lib" "1.0")
  [ -n "$result" ]
  [[ "$result" == *.aar ]]
}

@test "find_compiled_artifact prefers JAR over AAR" {
  # Create both compiled JAR and AAR
  create_mock_compiled_jar "com.a" "lib" "1.0" "com.example.Foo"
  create_mock_aar "com.a" "lib" "1.0" "com.example.Bar"
  local result
  result=$(find_compiled_artifact "com.a" "lib" "1.0")
  [[ "$result" == *.jar ]]
  [[ "$result" != *.aar ]]
}

@test "find_compiled_artifact returns empty for missing artifact" {
  local result
  result=$(find_compiled_artifact "com.nonexist" "x" "9.9")
  [ -z "$result" ]
}

# ══════════════════════════════════════════════════════════════
# 2. build_class_index_for_coord: directory-based indexing
# ══════════════════════════════════════════════════════════════

@test "build_class_index_for_coord indexes Java files from directory" {
  local dir="${TEST_TMPDIR}/decompiled/com.a/lib/1.0"
  mkdir -p "$dir/com/example"
  echo "public class Foo {}" > "$dir/com/example/Foo.java"
  echo "public class Bar {}" > "$dir/com/example/Bar.java"

  build_class_index_for_coord "com.a:lib:1.0" "$dir"
  grep -q "com.example.Foo.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
  grep -q "com.example.Bar.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
}

@test "build_class_index_for_coord indexes Kotlin files" {
  local dir="${TEST_TMPDIR}/decompiled/com.a/lib/1.0"
  mkdir -p "$dir/com/example"
  echo "class Foo" > "$dir/com/example/Foo.kt"

  build_class_index_for_coord "com.a:lib:1.0" "$dir"
  grep -q "com.example.Foo.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
}

@test "build_class_index_for_coord skips existing coord" {
  local dir="${TEST_TMPDIR}/decompiled/com.a/lib/1.0"
  mkdir -p "$dir/com/example"
  echo "public class Foo {}" > "$dir/com/example/Foo.java"

  build_class_index_for_coord "com.a:lib:1.0" "$dir"
  build_class_index_for_coord "com.a:lib:1.0" "$dir"
  local count
  count=$(grep -c "com.example.Foo.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE")
  [ "$count" -eq 1 ]
}

@test "build_class_index_for_coord handles empty directory" {
  local dir="${TEST_TMPDIR}/empty_dir"
  mkdir -p "$dir"
  build_class_index_for_coord "com.a:lib:1.0" "$dir"
  # Should not crash, lookup file should be empty or unchanged
  [ ! -s "$CLASS_LOOKUP_FILE" ] || [ "$(wc -l < "$CLASS_LOOKUP_FILE" | tr -d ' ')" -eq 0 ]
}

# ══════════════════════════════════════════════════════════════
# 3. _append_compiled_classes / cmd_index_all
# ══════════════════════════════════════════════════════════════

@test "_append_compiled_classes writes class entries to CLASS_INDEX_FILE" {
  # Create a mock class map file (as produced by xargs jar tf)
  local class_map="${TEST_TMPDIR}/class_map.txt"
  cat > "$class_map" << 'EOF'
/com.a/lib/1.0/com/example/Foo.class	com/example/Foo.class
/com.a/lib/1.0/com/example/Bar.class	com/example/Bar.class
EOF

  # The function expects full paths starting with GRADLE_CACHE
  # Rewrite with actual GRADLE_CACHE prefix
  cat > "$class_map" << EOF
${GRADLE_CACHE}/com.a/lib/1.0/somehash/lib-1.0.jar	com/example/Foo.class
${GRADLE_CACHE}/com.a/lib/1.0/somehash/lib-1.0.jar	com/example/Bar.class
EOF

  _append_compiled_classes "$class_map"
  grep -q "com.example.Foo" "$CLASS_INDEX_FILE"
  grep -q "com.example.Bar" "$CLASS_INDEX_FILE"
}

@test "_append_compiled_classes skips duplicates" {
  local class_map="${TEST_TMPDIR}/class_map.txt"
  cat > "$class_map" << EOF
${GRADLE_CACHE}/com.a/lib/1.0/somehash/lib-1.0.jar	com/example/Foo.class
EOF

  # Pre-add the coord to CLASS_INDEX_FILE
  echo "########## com.a:lib:1.0" >> "$CLASS_INDEX_FILE"

  _append_compiled_classes "$class_map"
  # Should not duplicate — coord already exists, so no new entries added
  local count
  count=$(grep -c "com.example.Foo" "$CLASS_INDEX_FILE" || true)
  [ "$count" -eq 0 ]
}

@test "_append_compiled_classes handles empty file" {
  local class_map="${TEST_TMPDIR}/empty_map.txt"
  touch "$class_map"
  run _append_compiled_classes "$class_map"
  [ "$status" -eq 0 ]
}

@test "cmd_index_all builds index from mock Gradle cache" {
  # Create mock artifacts in Gradle cache
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" \
    "com.google.gson.Gson" "com.google.gson.GsonBuilder"
  create_mock_source_jar "com.squareup.okhttp3" "okhttp" "4.12.0" \
    "okhttp3.OkHttpClient"

  run cmd_index_all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Done"* ]]

  # Verify lookup file was built
  [ -f "$CLASS_LOOKUP_FILE" ]
  [ -s "$CLASS_LOOKUP_FILE" ]
  grep -q "com.google.gson.Gson" "$CLASS_LOOKUP_FILE"
  grep -q "okhttp3.OkHttpClient" "$CLASS_LOOKUP_FILE"
}

@test "cmd_index_all skips already indexed JARs" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"

  # Run once
  cmd_index_all > /dev/null 2>&1
  local lines_after_first
  lines_after_first=$(wc -l < "$CLASS_LOOKUP_FILE" | tr -d ' ')

  # Run again — should skip
  cmd_index_all > /dev/null 2>&1
  local lines_after_second
  lines_after_second=$(wc -l < "$CLASS_LOOKUP_FILE" | tr -d ' ')

  [ "$lines_after_first" -eq "$lines_after_second" ]
}

# ══════════════════════════════════════════════════════════════
# 4. Corrupted JAR / edge cases
# ══════════════════════════════════════════════════════════════

@test "corrupted source JAR: find, read, and index all handle gracefully" {
  local dir="${TEST_GRADLE_CACHE}/com.a/lib/1.0"
  mkdir -p "$dir"
  echo "not a valid zip" > "$dir/lib-1.0-sources.jar"

  # find_source_jar returns path (file exists)
  local result
  result=$(find_source_jar "com.a" "lib" "1.0")
  [ -n "$result" ]

  # read_source_file returns empty (not crash)
  local content
  content=$(read_source_file "$dir/lib-1.0-sources.jar" "com/example/Foo.java")
  [ -z "$content" ]

  # build_class_index_from_jar produces no entries (not crash)
  run build_class_index_from_jar "com.a:lib:1.0" "$dir/lib-1.0-sources.jar"
  [ "$status" -eq 0 ]
}

@test "cmd_find_source handles AAR without classes.jar" {
  local dir="${TEST_GRADLE_CACHE}/com.a/lib/1.0"
  mkdir -p "$dir"
  # Create an AAR with no classes.jar inside
  local tmp_aar="${TEST_TMPDIR}/empty_aar_content"
  mkdir -p "$tmp_aar"
  echo "not a jar" > "$tmp_aar/AndroidManifest.xml"
  (cd "$tmp_aar" && jar cf "$dir/lib-1.0.aar" .)
  rm -rf "$tmp_aar"

  run cmd_find_source "com.a" "lib" "1.0"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}



# ══════════════════════════════════════════════════════════════
# 5. Corrupted index.json
# ══════════════════════════════════════════════════════════════

@test "corrupted index.json: check_index and update_index handle gracefully" {
  echo "not valid json {{{" > "$INDEX_FILE"

  # check_index returns empty (not crash)
  local result
  result=$(check_index "com.a:lib:1.0")
  [ -z "$result" ]

  # update_index recovers by recreating the file
  run update_index "com.a:lib:1.0" "source" "/some/path"
  [ -f "$INDEX_FILE" ]
}
