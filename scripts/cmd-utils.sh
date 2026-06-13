#!/usr/bin/env bash
# Utility commands: init / search / tree / list / rebuild-index / clean

cmd_init() {
  echo "=== android-lib-reader environment check ==="

  local all_ok=true
  for tool in python3 jar unzip rg; do
    if command -v "$tool" &>/dev/null; then
      echo "  [OK] ${tool}: $(command -v "$tool")"
    else
      echo "  [MISSING] ${tool}: not installed"
      all_ok=false
    fi
  done

  local selected
  selected=$(_select_decompiler 2>/dev/null)
  if [ -n "$selected" ]; then
    local name="${selected%%:*}"
    local path="${selected#*:}"
    echo "  [OK] decompiler: ${name} (${path})"
  else
    echo "  [WARN] No decompiler available"
    echo "         Install jadx: brew install jadx"
    echo "         Or download built-in: bash scripts/fetch-decompilers.sh"
  fi

  if [ ! -d "$GRADLE_CACHE" ]; then
    echo "  [MISSING] Gradle cache: ${GRADLE_CACHE}"
    echo "            Please sync your Android project in Android Studio first"
    return 1
  fi
  local lib_count
  lib_count=$(find "$GRADLE_CACHE" -maxdepth 2 -mindepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo "  [OK] Gradle cache: ${lib_count} libraries"

  init_cache
  echo "  [OK] Cache dir: ${CACHE_ROOT}"

  local index_size
  index_size=$( [ -f "$CLASS_LOOKUP_FILE" ] && wc -l < "$CLASS_LOOKUP_FILE" | tr -d ' ' || echo 0 )
  if [ "${index_size:-0}" -gt 100 ]; then
    echo "  [OK] Class index: ${index_size} classes"
    local cache_size
    cache_size=$(du -sh "$CACHE_ROOT" 2>/dev/null | awk '{print $1}')
    echo "  [OK] Cache size: ${cache_size}"
    echo ""
    echo "Environment ready. Use find-class / find-source commands."
  else
    echo "  [WARN] Class index: ${index_size:-0} classes (not built)"
    echo ""
    echo "Run 'lib-reader.sh index-all' to build full index (~1-3 min, one-time)."
  fi

  if [ "$all_ok" = false ]; then
    return 1
  fi
  return 0
}

cmd_search_libs() {
  local keyword="$1"
  echo "=== Libraries matching '${keyword}' in Gradle cache ==="
  find "${GRADLE_CACHE}" -maxdepth 3 -mindepth 3 -type d \
    -path "*${keyword}*" 2>/dev/null | while IFS= read -r dir; do
    local rel="${dir#${GRADLE_CACHE}/}"
    local gid aid ver
    gid=$(echo "$rel" | cut -d/ -f1)
    aid=$(echo "$rel" | cut -d/ -f2)
    ver=$(echo "$rel" | cut -d/ -f3)
    local has_src="no"
    if find "$dir" -name "*-sources.jar" -type f 2>/dev/null | head -1 | grep -q .; then
      has_src="yes"
    fi
    echo "${gid}:${aid}:${ver}  [sources=${has_src}]"
  done
}

cmd_tree() {
  local group_id="$1" artifact_id="$2" version="$3"
  local coord="${group_id}:${artifact_id}:${version}"

  init_cache

  # Try to find source JAR
  local src_jar
  src_jar=$(find_source_jar "$group_id" "$artifact_id" "$version")

  if [ -n "$src_jar" ]; then
    echo "=== ${coord} (from source JAR) ==="
    jar tf "$src_jar" 2>/dev/null | grep -E '\.(java|kt)$' | sort
    return 0
  fi

  # Fall back to cached index entry
  local indexed
  indexed=$(check_index "$coord")
  if [ -z "$indexed" ]; then
    echo "ERROR:Library ${coord} not indexed. Run find-source first."
    return 1
  fi

  if [ -d "$indexed" ]; then
    find "$indexed" \( -name "*.java" -o -name "*.kt" \) | sort | while IFS= read -r f; do
      echo "${f#${indexed}/}"
    done
  else
    echo "ERROR:Cannot list files for ${coord}"
    return 1
  fi
}

cmd_list_cached() {
  init_cache
  python3 -c '
import json, sys
idx = json.load(open(sys.argv[1]))
if not idx:
    print("(no cache)")
    sys.exit(0)
for coord in sorted(idx.keys()):
    entry = idx[coord]
    t = entry.get("type", "unknown")
    print(coord + "  [" + t + "]")
' "$INDEX_FILE"
}

cmd_rebuild_index() {
  init_cache
  : > "$CLASS_LOOKUP_FILE"
  local coord path_val
  while IFS=$'\t' read -r coord path_val; do
    [ -z "$coord" ] && continue
    # path_val could be a JAR file or a directory
    if [[ "$path_val" == *.jar && -f "$path_val" ]]; then
      build_class_index_from_jar "$coord" "$path_val"
      echo "  Indexed: ${coord} (from JAR)"
    elif [ -d "$path_val" ]; then
      build_class_index_for_coord "$coord" "$path_val"
      echo "  Indexed: ${coord} (from dir)"
    fi
  done < <(python3 -c "
import json, sys
idx = json.load(open(sys.argv[1]))
for coord, entry in idx.items():
    path_val = entry.get('path', '')
    if path_val:
        print(f'{coord}\t{path_val}')
" "$INDEX_FILE")
  # Re-sort the lookup file for binary search
  LC_ALL=C sort -t$'\t' -k1,1 -u -o "$CLASS_LOOKUP_FILE" "$CLASS_LOOKUP_FILE"
  local total
  total=$(wc -l < "$CLASS_LOOKUP_FILE" 2>/dev/null | tr -d ' ')
  echo "Index rebuilt: ${total} classes"
}

cmd_clean() {
  rm -rf "${CACHE_ROOT}"
  echo "Cache cleared: ${CACHE_ROOT}"
}
