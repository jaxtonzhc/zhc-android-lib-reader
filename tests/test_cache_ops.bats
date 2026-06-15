#!/usr/bin/env bats
# test cache-ops.sh: index read/write, class lookup, lookup file generation

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

@test "update_index writes to index.tsv in TSV format" {
  update_index "com.google.code.gson:gson:2.11.0" "source" "/path/to/sources.jar"
  [ -f "$INDEX_FILE" ]
  # TSV row: coord<TAB>type<TAB>path<TAB>timestamp
  grep -q "com.google.code.gson:gson:2.11.0	source	/path/to/sources.jar" "$INDEX_FILE"
}

@test "update_index overwrites existing coord" {
  update_index "com.a:b:1.0" "source" "/path/a.jar"
  update_index "com.a:b:1.0" "decompiled" "/path/b"
  # Read type field (2nd column) for this coord
  local type_val count
  type_val=$(awk -F'\t' -v c="com.a:b:1.0" '$1==c{print $2}' "$INDEX_FILE")
  [ "$type_val" = "decompiled" ]
  # Ensure only one entry exists for this coord (no duplicates)
  count=$(grep -c "^com.a:b:1.0	" "$INDEX_FILE")
  [ "$count" -eq 1 ]
}

@test "check_index returns stored path" {
  local jar_path="/fake/path/gson-2.11.0-sources.jar"
  update_index "com.a:b:1.0" "source" "$jar_path"
  local result
  result=$(check_index "com.a:b:1.0")
  [ "$result" = "$jar_path" ]
}

@test "check_index returns empty for unknown coord" {
  local result
  result=$(check_index "com.nonexist:x:9.9")
  [ -z "$result" ]
}

@test "find_source_jar finds JAR in Gradle cache" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" "com.google.gson.Gson"
  local result
  result=$(find_source_jar "com.google.code.gson" "gson" "2.11.0")
  [ -n "$result" ]
  [[ "$result" == *".jar" ]]
}

@test "find_source_jar returns empty for missing" {
  local result
  result=$(find_source_jar "com.nonexist" "x" "9.9")
  [ -z "$result" ]
}

@test "read_source_file reads file from JAR" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  local jar_path
  jar_path=$(find_source_jar "com.a" "lib" "1.0")
  local content
  content=$(read_source_file "$jar_path" "com/example/Foo.java")
  [[ "$content" == *"source of com.example.Foo"* ]]
}

@test "read_source_file returns empty for missing file" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  local jar_path
  jar_path=$(find_source_jar "com.a" "lib" "1.0")
  local content
  content=$(read_source_file "$jar_path" "com/example/Missing.java")
  [ -z "$content" ]
}

@test "build_class_index_from_jar writes to lookup file" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo" "com.example.Bar"
  local jar_path
  jar_path=$(find_source_jar "com.a" "lib" "1.0")
  build_class_index_from_jar "com.a:lib:1.0" "$jar_path"
  grep -q "com.example.Foo.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
  grep -q "com.example.Bar.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE"
}

@test "build_class_index_from_jar skips existing coord" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  local jar_path
  jar_path=$(find_source_jar "com.a" "lib" "1.0")
  build_class_index_from_jar "com.a:lib:1.0" "$jar_path"
  build_class_index_from_jar "com.a:lib:1.0" "$jar_path"
  local count
  count=$(grep -c "com.example.Foo.*com.a:lib:1.0" "$CLASS_LOOKUP_FILE")
  [ "$count" -eq 1 ]
}

@test "rebuild_lookup_from_class_index generates sorted lookup" {
  # Simulate index-all flow: write to CLASS_INDEX_FILE then rebuild
  cat > "$CLASS_INDEX_FILE" << 'IDXEOF'
########## com.google.code.gson:gson:2.11.0
com.google.gson.Gson
com.google.gson.GsonBuilder
########## com.squareup.okhttp3:okhttp:4.12.0
okhttp3.OkHttpClient
okhttp3.Request
IDXEOF
  rebuild_lookup_from_class_index
  [ -f "$CLASS_LOOKUP_FILE" ]
  local line_count
  line_count=$(wc -l < "$CLASS_LOOKUP_FILE" | tr -d ' ')
  [ "$line_count" -eq 4 ]
}

@test "lookup_class_index exact match" {
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" "com.google.gson.Gson"
  local jar_path
  jar_path=$(find_source_jar "com.google.code.gson" "gson" "2.11.0")
  build_class_index_from_jar "com.google.code.gson:gson:2.11.0" "$jar_path"
  # Sort for binary search
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  local result
  result=$(lookup_class_index "com.google.gson.Gson")
  [ "$result" = "com.google.code.gson:gson:2.11.0" ]
}

@test "lookup_class_index returns empty for missing class" {
  create_mock_source_jar "com.a" "lib" "1.0" "com.example.Foo"
  local jar_path
  jar_path=$(find_source_jar "com.a" "lib" "1.0")
  build_class_index_from_jar "com.a:lib:1.0" "$jar_path"
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  local result
  result=$(lookup_class_index "com.nonexist.Missing")
  [ -z "$result" ]
}

@test "lookup_class_index handles missing lookup file" {
  rm -f "$CLASS_LOOKUP_FILE"
  local result
  result=$(lookup_class_index "com.example.Foo")
  [ -z "$result" ]
}

@test "rebuild_lookup_from_class_index deduplicates class names" {
  cat > "$CLASS_INDEX_FILE" << 'IDXEOF'
########## com.a:lib-a:1.0
com.example.Shared
########## com.b:lib-b:2.0
com.example.Shared
IDXEOF
  rebuild_lookup_from_class_index
  local count
  count=$(grep -c "com.example.Shared" "$CLASS_LOOKUP_FILE")
  [ "$count" -eq 1 ]
}

# ── Auto-sort on lookup (Bug #3: incremental append breaks binary search) ──

@test "lookup_class_index finds entry after incremental append without manual sort" {
  # Bug #3: build_class_index_from_jar appends unsorted, breaking `look` binary
  # search. lookup_class_index must auto-sort first so the fast path works.
  create_mock_source_jar "com.google.code.gson" "gson" "2.11.0" "com.google.gson.Gson"
  local jar_path
  jar_path=$(find_source_jar "com.google.code.gson" "gson" "2.11.0")
  # Deliberately DO NOT call LC_ALL=C sort (as the existing test does at L118)
  build_class_index_from_jar "com.google.code.gson:gson:2.11.0" "$jar_path"
  run lookup_class_index "com.google.gson.Gson"
  [ "$status" -eq 0 ]
  [ "$output" = "com.google.code.gson:gson:2.11.0" ]
  # Verify the fast path (binary search via `look`) actually works now.
  # If lookup file is unsorted, `look` returns nothing even though grep would.
  # The sorted flag file proves auto-sort happened.
  [ -f "$LOOKUP_SORTED_FLAG" ]
}

@test "lookup_class_index auto-resort handles multiple incremental appends" {
  create_mock_source_jar "com.a" "liba" "1.0" "com.example.Foo"
  create_mock_source_jar "com.b" "libb" "2.0" "com.example.Bar"
  build_class_index_from_jar "com.a:liba:1.0" "$(find_source_jar "com.a" "liba" "1.0")"
  build_class_index_from_jar "com.b:libb:2.0" "$(find_source_jar "com.b" "libb" "2.0")"
  # Both classes must be findable despite unordered appends
  [ -n "$(lookup_class_index "com.example.Foo")" ]
  [ -n "$(lookup_class_index "com.example.Bar")" ]
}
