#!/usr/bin/env bash
# Command: find-class — Find source by class name using index + on-demand JAR reading
# Search strategy:
#   Layer 0: class-lookup.txt binary search → coord → source JAR → unzip -p
#   Layer 1: scan Gradle source JARs (parallel)

# Read source content from an indexed JAR or directory
# Sets: _READ_RESULT (content or file path), _READ_FILE (matched filename), _READ_MODE ("jar" or "dir")
_READ_RESULT=""
_READ_FILE=""
_READ_MODE=""
_read_from_index() {
  local indexed_entry="$1" java_file="$2" kt_file="$3"
  _READ_RESULT=""
  _READ_FILE=""
  _READ_MODE=""

  if [[ "$indexed_entry" == /* && "$indexed_entry" == *.jar ]]; then
    _READ_MODE="jar"
    _READ_RESULT=$(read_source_file "$indexed_entry" "$java_file")
    if [ -z "$_READ_RESULT" ]; then
      _READ_RESULT=$(read_source_file "$indexed_entry" "$kt_file")
      _READ_FILE="$kt_file"
    else
      _READ_FILE="$java_file"
    fi
  elif [ -d "$indexed_entry" ]; then
    _READ_MODE="dir"
    local target_file
    target_file=$(find "$indexed_entry" \( -path "*/${java_file}" -o -path "*/${kt_file}" \) 2>/dev/null | head -1)
    if [ -n "$target_file" ]; then
      _READ_RESULT="$target_file"
      _READ_FILE="$target_file"
    fi
  fi
}

# Output result from _read_from_index in standard format
# Usage: _emit_read_result <indexed_entry> <indexed_coord> [extra_lines...]
_emit_read_result() {
  local indexed_entry="$1" indexed_coord="$2"
  shift 2

  if [ "$_READ_MODE" = "jar" ]; then
    echo "FOUND:${indexed_entry}!${_READ_FILE}"
    echo "COORD:${indexed_coord}"
    # Extra lines (VERSION_MATCH, etc.)
    for line in "$@"; do echo "$line"; done
    echo "SOURCE:index"
    echo "---SOURCE---"
    echo "$_READ_RESULT"
  elif [ "$_READ_MODE" = "dir" ]; then
    echo "FOUND:${_READ_RESULT}"
    echo "COORD:${indexed_coord}"
    for line in "$@"; do echo "$line"; done
    echo "SOURCE:index"
  fi
}

# Fuzzy match class name against class-lookup.txt
# Sets: _FUZZY_ALL (array of "coord|class" pairs, ordered by preference), _FUZZY_COORD, _FUZZY_CLASS, _FUZZY_FILE
# Usage: _fuzzy_match_class <class_name> <java_file> <kt_file>
# After call, iterate _FUZZY_ALL to try all candidates
_FUZZY_COORD=""
_FUZZY_CLASS=""
_FUZZY_FILE=""
_FUZZY_ALL=()
_fuzzy_match_class() {
  local class_name="$1" java_file="$2" kt_file="$3"
  local simple_name="${class_name##*.}"
  _FUZZY_COORD=""
  _FUZZY_CLASS=""
  _FUZZY_FILE=""
  _FUZZY_ALL=()

  local fuzzy_results
  fuzzy_results=$(grep "\.${simple_name}	" "$CLASS_LOOKUP_FILE" 2>/dev/null \
    | head -5 \
    | sed 's/\t/|/' || true)
  [ -z "$fuzzy_results" ] && return 1

  local match_count
  match_count=$(echo "$fuzzy_results" | wc -l | tr -d ' ')

  if [ "$match_count" -eq 1 ]; then
    local real_class real_coord
    IFS='|' read -r real_class real_coord <<< "$fuzzy_results"
    _FUZZY_COORD="$real_coord"
    _FUZZY_CLASS="$real_class"
    _FUZZY_FILE=$(echo "$real_class" | tr '.' '/').java
    _FUZZY_ALL=("${real_coord}|${real_class}")
    return 0
  fi

  # Multiple candidates: prefer project version first, then rest
  local first_class first_coord
  first_class=$(echo "$fuzzy_results" | head -1 | cut -d'|' -f1)
  first_coord=$(echo "$fuzzy_results" | head -1 | cut -d'|' -f2)

  local fuzzy_gid fuzzy_aid
  fuzzy_gid=$(echo "$first_coord" | cut -d: -f1)
  fuzzy_aid=$(echo "$first_coord" | cut -d: -f2)
  local proj_ver
  proj_ver=$(resolve_project_version "$fuzzy_gid" "$fuzzy_aid")

  # Build ordered candidate list: project version match first, then others
  if [ -n "$proj_ver" ]; then
    while IFS='|' read -r cls coord; do
      if [[ "$coord" == *":${proj_ver}" ]]; then
        _FUZZY_ALL=("${coord}|${cls}")
      fi
    done <<< "$fuzzy_results"
  fi
  # Append all candidates (project version entry will be tried first, others as fallback)
  while IFS='|' read -r cls coord; do
    _FUZZY_ALL+=("${coord}|${cls}")
  done <<< "$fuzzy_results"

  # Set primary (first candidate)
  local primary="${_FUZZY_ALL[0]}"
  _FUZZY_COORD="${primary%%|*}"
  _FUZZY_CLASS="${primary#*|}"
  _FUZZY_FILE=$(echo "$_FUZZY_CLASS" | tr '.' '/').java
  return 0
}

# Scan Gradle source JARs in parallel for a class
# Usage: _scan_gradle_for_class <java_file> <kt_file>
# Outputs matching candidates to stdout
_scan_gradle_for_class() {
  local java_file="$1" kt_file="$2"
  local tmp_jar_list tmp_result
  tmp_jar_list=$(mktemp)
  tmp_result=$(mktemp)
  trap "rm -f '$tmp_jar_list' '$tmp_result'" RETURN
  find "${GRADLE_CACHE}" -name "*-sources.jar" -type f > "$tmp_jar_list" 2>/dev/null
  cat "$tmp_jar_list" | xargs -P 8 -I{} sh -c '
    if unzip -Z -1 "$1" 2>/dev/null | grep -qE "'"${java_file}"'$|'"${kt_file}"'$"; then
      echo "$1"
    fi
  ' _ {} > "$tmp_result" 2>/dev/null || true
  cat "$tmp_result"
}

cmd_find_class() {
  local class_name="$1"
  local class_path
  class_path=$(echo "$class_name" | tr '.' '/')
  local java_file="${class_path}.java"
  local kt_file="${class_path}.kt"

  init_cache

  local index_size
  index_size=$( [ -f "$CLASS_LOOKUP_FILE" ] && wc -l < "$CLASS_LOOKUP_FILE" | tr -d ' ' || echo 0 )
  if [ "${index_size:-0}" -lt 200 ]; then
    echo "HINT:Full class index not built. First lookup may be slow (30-60s)."
    echo "HINT:Run 'lib-reader.sh index-all' to build index (~1-3 min, one-time)."
  fi

  # ── Layer 0: Index lookup ──
  local indexed_coord
  indexed_coord=$(lookup_class_index "$class_name")

  # Exact match: single coord, fast path
  if [ -n "$indexed_coord" ]; then
    local indexed_entry
    indexed_entry=$(check_index "$indexed_coord")
    if [ -n "$indexed_entry" ]; then
      _read_from_index "$indexed_entry" "$java_file" "$kt_file"
      if [ -n "$_READ_RESULT" ]; then
        _emit_read_result "$indexed_entry" "$indexed_coord"
        return 0
      fi
    fi
    # Coord in index but source not readable — try find-source
    local idx_gid idx_aid idx_ver
    IFS=: read -r idx_gid idx_aid idx_ver <<< "$indexed_coord"
    local proj_ver
    proj_ver=$(resolve_project_version "$idx_gid" "$idx_aid")
    [ -n "$proj_ver" ] && idx_ver="$proj_ver"
    local _fs_output
    _fs_output=$(cmd_find_source "$idx_gid" "$idx_aid" "$idx_ver" 2>&1) || true
    indexed_entry=$(check_index "$indexed_coord")
    if [ -n "$indexed_entry" ]; then
      _read_from_index "$indexed_entry" "$java_file" "$kt_file"
      if [ -n "$_READ_RESULT" ]; then
        _emit_read_result "$indexed_entry" "$indexed_coord"
        return 0
      fi
    fi
  fi

  # Fuzzy match: try ALL candidates before falling to Layer 1
  if [ -z "$indexed_coord" ] && _fuzzy_match_class "$class_name" "$java_file" "$kt_file"; then
    local proj_ver fuzzy_gid fuzzy_aid
    fuzzy_gid=$(echo "${_FUZZY_ALL[0]}" | cut -d'|' -f1 | cut -d: -f1)
    fuzzy_aid=$(echo "${_FUZZY_ALL[0]}" | cut -d'|' -f1 | cut -d: -f2)
    proj_ver=$(resolve_project_version "$fuzzy_gid" "$fuzzy_aid")
    # Try each candidate: first project version match, then all others
    for candidate in "${_FUZZY_ALL[@]}"; do
      local cand_coord="${candidate%%|*}"
      local cand_class="${candidate#*|}"
      local cand_file cand_kt
      cand_file=$(echo "$cand_class" | tr '.' '/').java
      cand_kt=$(echo "$cand_class" | tr '.' '/').kt

      local indexed_entry
      indexed_entry=$(check_index "$cand_coord")
      [ -z "$indexed_entry" ] && continue

      _read_from_index "$indexed_entry" "$cand_file" "$cand_kt"
      if [ -n "$_READ_RESULT" ]; then
        echo "FUZZY_MATCH:${class_name} -> ${cand_class}"
        if [ -n "$proj_ver" ]; then
          _emit_read_result "$indexed_entry" "$cand_coord" "VERSION_MATCH:project uses ${proj_ver}"
        else
          _emit_read_result "$indexed_entry" "$cand_coord"
        fi
        return 0
      fi
    done
    # All fuzzy candidates failed to read — fall through to Layer 1
  fi

  # ── Layer 1: Scan Gradle source JARs ──
  echo "INFO:Scanning Gradle source JARs..."

  local scan_result
  scan_result=$(_scan_gradle_for_class "$java_file" "$kt_file")

  local candidates=()
  while IFS= read -r jar; do
    [ -z "$jar" ] && continue
    local rel_path="${jar#${GRADLE_CACHE}/}"
    local gid aid ver
    gid=$(echo "$rel_path" | cut -d/ -f1)
    aid=$(echo "$rel_path" | cut -d/ -f2)
    ver=$(echo "$rel_path" | cut -d/ -f3)
    candidates+=("${gid}:${aid}:${ver}")
  done <<< "$scan_result"

  if [ ${#candidates[@]} -eq 0 ]; then
    echo "NOT_FOUND:Class ${class_name} not found in Gradle cache"
    return 1
  fi

  # Select best version
  local chosen=""
  local first_gid first_aid
  IFS=: read -r first_gid first_aid _ <<< "${candidates[0]}"

  local project_ver
  project_ver=$(resolve_project_version "$first_gid" "$first_aid")

  if [ -n "$project_ver" ]; then
    for c in "${candidates[@]}"; do
      if [[ "$c" == *":${project_ver}" ]]; then
        chosen="$c"
        break
      fi
    done
  fi
  [ -z "$chosen" ] && chosen="${candidates[0]}"

  local gid aid ver
  IFS=: read -r gid aid ver <<< "$chosen"

  # Find the source JAR and read directly
  local src_jar
  src_jar=$(find_source_jar "$gid" "$aid" "$ver")

  if [ -n "$src_jar" ]; then
    local content
    content=$(read_source_file "$src_jar" "$java_file")
    if [ -z "$content" ]; then
      content=$(read_source_file "$src_jar" "$kt_file")
      java_file="$kt_file"
    fi
    if [ -n "$content" ]; then
      local found_coord="${gid}:${aid}:${ver}"
      update_index "$found_coord" "source" "$src_jar"
      build_class_index_from_jar "$found_coord" "$src_jar"

      echo "FOUND:${src_jar}!${java_file}"
      echo "COORD:${gid}:${aid}:${ver}"
      [ -n "$project_ver" ] && [ "$ver" = "$project_ver" ] && echo "VERSION_MATCH:project uses ${project_ver}"
      [ -n "$project_ver" ] && [ "$ver" != "$project_ver" ] && echo "VERSION_WARN:project uses ${project_ver}, found ${ver}"
      echo "SOURCE:scan+jar"
      echo "---SOURCE---"
      echo "$content"
      return 0
    fi
  fi

  echo "NOT_FOUND:Class ${class_name} not found in source JARs"
  return 1
}
