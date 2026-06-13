#!/usr/bin/env bash
# Command: index-all — Build class name index WITHOUT extracting source JARs
# Scans JAR file listings to build class-lookup.txt for binary search.

# Progress bar helper (only refresh every 10%)
_last_pct=-1
_progress_bar() {
  local current="$1" total="$2"
  local pct=$(( current * 100 / total ))
  local bucket=$(( pct / 10 ))
  [ "$bucket" = "$_last_pct" ] && return 0
  _last_pct=$bucket
  local filled=$(( pct / 2 ))
  local empty=$(( 50 - filled ))
  local bar
  bar=$(printf '%*s' "$filled" '' | tr ' ' '█')
  bar+=$(printf '%*s' "$empty" '' | tr ' ' '░')
  printf "  [%s] %d%%\n" "$bar" "$pct"
}

cmd_index_all() {
  # Save and relax shell options for this function (xargs/jar may fail on individual items)
  local _old_opts
  _old_opts=$(set +o)  # captures current option state
  set +e
  set -o pipefail

  init_cache
  echo "=== Building class index (no source extraction) ==="

  # ── Phase 1: Index source JARs (class names only, no extract) ──
  local tmp_jar_list
  tmp_jar_list=$(mktemp)
  find "${GRADLE_CACHE}" -name "*-sources.jar" -type f 2>/dev/null > "$tmp_jar_list"
  local total_jars
  total_jars=$(wc -l < "$tmp_jar_list" | tr -d ' ')
  echo "Phase 1/3: Scanning ${total_jars} source JARs..."

  local processed=0
  while IFS= read -r jar; do
    [ -z "$jar" ] && continue
    local rel_path="${jar#${GRADLE_CACHE}/}"
    local gid aid ver coord
    gid=$(echo "$rel_path" | cut -d/ -f1)
    aid=$(echo "$rel_path" | cut -d/ -f2)
    ver=$(echo "$rel_path" | cut -d/ -f3)
    coord="${gid}:${aid}:${ver}"

    # Skip if already indexed
    if grep -q "^########## ${coord}$" "$CLASS_INDEX_FILE" 2>/dev/null; then
      processed=$((processed + 1))
      _progress_bar "$processed" "$total_jars"
      continue
    fi

    # Record JAR path in index and scan class names into CLASS_INDEX_FILE
    update_index "$coord" "source" "$jar"
    echo "########## ${coord}" >> "$CLASS_INDEX_FILE"
    jar tf "$jar" 2>/dev/null | grep -E '\.(java|kt)$' | sed 's/\.[^.]*$//;s/\//./g' >> "$CLASS_INDEX_FILE"
    processed=$((processed + 1))
    _progress_bar "$processed" "$total_jars"
  done < "$tmp_jar_list"
  rm -f "$tmp_jar_list"
  echo ""

  # ── Phase 2: Index compiled JARs (class name only) ──
  local tmp_compiled_list
  tmp_compiled_list=$(mktemp)
  find "${GRADLE_CACHE}" -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" -type f > "$tmp_compiled_list" 2>/dev/null
  local total_compiled
  total_compiled=$(wc -l < "$tmp_compiled_list" | tr -d ' ')
  echo "Phase 2/3: Indexing ${total_compiled} compiled JARs..."

  local tmp_class_map
  tmp_class_map=$(mktemp)
  cat "$tmp_compiled_list" | xargs -P 8 -I{} sh -c '
    jar tf "$1" 2>/dev/null | grep "\.class$" | grep -v "\\$" | while read -r cls; do
      echo "$1	$cls"
    done
  ' _ {} > "$tmp_class_map" 2>/dev/null || true

  _append_compiled_classes "$tmp_class_map" || true
  rm -f "$tmp_compiled_list" "$tmp_class_map"
  echo ""

  # ── Phase 3: Index AAR classes.jar ──
  local tmp_aar_list
  tmp_aar_list=$(mktemp)
  find "${GRADLE_CACHE}" -name "*.aar" -type f > "$tmp_aar_list" 2>/dev/null
  local total_aars
  total_aars=$(wc -l < "$tmp_aar_list" | tr -d ' ')
  echo "Phase 3/3: Indexing ${total_aars} AARs..."

  local tmp_aar_class_map
  tmp_aar_class_map=$(mktemp)
  cat "$tmp_aar_list" | xargs -P 8 -I{} sh -c '
    tmpd=$(mktemp -d)
    unzip -o -q "$1" classes.jar -d "$tmpd" 2>/dev/null
    if [ -f "$tmpd/classes.jar" ]; then
      jar tf "$tmpd/classes.jar" 2>/dev/null | grep "\.class$" | grep -v "\\$" | while read -r cls; do
        echo "$1	$cls"
      done
    fi
    rm -rf "$tmpd"
  ' _ {} > "$tmp_aar_class_map" 2>/dev/null || true

  _append_compiled_classes "$tmp_aar_class_map" || true
  rm -f "$tmp_aar_list" "$tmp_aar_class_map"
  echo ""

  # Build sorted lookup file
  echo "Building sorted lookup file..."
  rebuild_lookup_from_class_index

  local total_classes
  total_classes=$(wc -l < "$CLASS_LOOKUP_FILE" 2>/dev/null | tr -d ' ')
  local total_libs
  total_libs=$(grep -c '^##########' "$CLASS_INDEX_FILE" 2>/dev/null || echo 0)
  echo "=== Done: ${total_libs} libraries, ${total_classes} classes indexed ==="
  rm -f "$CLASS_INDEX_FILE"  # 构建完成，释放临时文件

  # Restore original shell options
  eval "$_old_opts"
}

_append_compiled_classes() {
  local class_map_file="$1"
  [ ! -s "$class_map_file" ] && return 0

  awk -F'\t' -v gc="${GRADLE_CACHE}/" '{
    sub(gc, "", $1)
    n = split($1, p, "/")
    coord = p[1]":"p[2]":"p[3]
    cls = $2
    gsub(/\//, ".", cls)
    sub(/\.class$/, "", cls)
    if (cls !~ /\$/) print coord"\t"cls
  }' "$class_map_file" \
  | sort -t$'\t' -k1,1 -k2,2 -u \
  | awk -F'\t' -v idxfile="$CLASS_INDEX_FILE" '
  BEGIN {
    while ((getline line < idxfile) > 0) {
      if (substr(line, 1, 10) == "##########") {
        existing[substr(line, 12)] = 1
      }
    }
    close(idxfile)
    added = 0
  }
  {
    if (!($1 in existing)) {
      if ($1 != prev) {
        print "########## "$1
        prev = $1
      }
      print $2
      added++
    }
  }
  END { printf "  Added %d compiled class indexes\n", added > "/dev/stderr" }
  ' >> "$CLASS_INDEX_FILE"
}
