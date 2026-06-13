#!/usr/bin/env bash
# Cache and index read/write operations

update_index() {
  local coord="$1" type="$2" rel_path="$3"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S")
  local tmp
  tmp=$(mktemp)
  python3 -c "
import json, sys
idx = json.load(open(sys.argv[1]))
idx[sys.argv[2]] = {'type': sys.argv[3], 'path': sys.argv[4], 'extracted_at': sys.argv[5]}
json.dump(idx, open(sys.argv[6], 'w'), indent=2, ensure_ascii=False)
" "$INDEX_FILE" "$coord" "$type" "$rel_path" "$ts" "$tmp"
  mv "$tmp" "$INDEX_FILE"
}

# Find source JAR in Gradle cache for a given coordinate
# Usage: find_source_jar <groupId> <artifactId> <version>
# Returns: path to source JAR, or empty string
find_source_jar() {
  local gid="$1" aid="$2" ver="$3"
  find "${GRADLE_CACHE}/${gid}/${aid}/${ver}" \
    -name "*-sources.jar" -type f 2>/dev/null | head -1
}

# Find compiled JAR or AAR in Gradle cache
# Usage: find_compiled_artifact <groupId> <artifactId> <version>
# Returns: path to artifact, or empty string
find_compiled_artifact() {
  local gid="$1" aid="$2" ver="$3"
  local artifact
  artifact=$(find "${GRADLE_CACHE}/${gid}/${aid}/${ver}" \
    \( -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" \) \
    -type f 2>/dev/null | head -1)
  if [ -z "$artifact" ]; then
    artifact=$(find "${GRADLE_CACHE}/${gid}/${aid}/${ver}" \
      -name "*.aar" -type f 2>/dev/null | head -1)
  fi
  echo "$artifact"
}

# Read a single source file from a JAR without extracting
# Usage: read_source_file <jar_path> <com/example/Foo.java>
# Outputs file content to stdout
read_source_file() {
  local jar_path="$1" file_path="$2"
  unzip -p "$jar_path" "$file_path" 2>/dev/null || true
}

# Build class index entries from a source JAR (without extracting)
# Writes directly to CLASS_LOOKUP_FILE in "class<TAB>coord" format
# Usage: build_class_index_from_jar <coord> <jar_path>
build_class_index_from_jar() {
  local coord="$1" jar_path="$2"
  # Check if already indexed (look for any entry with this coord)
  if grep -q "	${coord}$" "$CLASS_LOOKUP_FILE" 2>/dev/null; then
    return 0
  fi
  # Use process substitution to avoid subshell (preserves local variable scope)
  local f cls
  while IFS= read -r f; do
    cls="${f%.*}"
    cls="${cls//\//.}"
    printf '%s\t%s\n' "$cls" "$coord"
  done < <(jar tf "$jar_path" 2>/dev/null | grep -E '\.(java|kt)$') >> "$CLASS_LOOKUP_FILE"
}

# Build class index from a directory of .java/.kt files (for decompiled sources)
# Usage: build_class_index_for_coord <coord> <dir>
build_class_index_for_coord() {
  local coord="$1" dir="$2"
  if grep -q "	${coord}$" "$CLASS_LOOKUP_FILE" 2>/dev/null; then
    return 0
  fi
  local f rel cls
  while IFS= read -r f; do
    rel="${f#${dir}/}"
    cls="${rel%.*}"
    cls="${cls//\//.}"
    printf '%s\t%s\n' "$cls" "$coord"
  done < <(find "$dir" \( -name "*.java" -o -name "*.kt" \) -type f 2>/dev/null) >> "$CLASS_LOOKUP_FILE"
}

lookup_class_index() {
  local class_name="$1"
  [ ! -f "$CLASS_LOOKUP_FILE" ] && return 0
  # First try binary search (fast, works on sorted portion)
  local result
  result=$(LC_ALL=C look "${class_name}	" "$CLASS_LOOKUP_FILE" 2>/dev/null | head -1 | cut -f2 || true)
  if [ -n "$result" ]; then
    echo "$result"
    return 0
  fi
  # Fallback: grep for unsorted entries (incremental additions)
  result=$(grep "^${class_name}	" "$CLASS_LOOKUP_FILE" 2>/dev/null | head -1 | cut -f2 || true)
  if [ -n "$result" ]; then
    echo "$result"
  fi
  return 0
}

# Rebuild lookup file from class-index.txt (used only during index-all)
rebuild_lookup_from_class_index() {
  awk '/^##########/{lib=substr($0,12); next} NF>0{print $0"\t"lib}' "$CLASS_INDEX_FILE" \
    | LC_ALL=C sort -t$'\t' -k1,1 -u > "$CLASS_LOOKUP_FILE"
}

check_index() {
  local coord="$1"
  local result
  result=$(python3 -c "
import json, sys
idx = json.load(open(sys.argv[1]))
entry = idx.get(sys.argv[2], {})
print(entry.get('path', ''))
" "$INDEX_FILE" "$coord" 2>/dev/null || true)
  if [ -n "$result" ]; then
    echo "$result"
  fi
}
