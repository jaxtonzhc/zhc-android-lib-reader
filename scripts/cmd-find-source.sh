#!/usr/bin/env bash
# Command: find-source — Locate source JAR by Maven coordinate
# No longer extracts source to disk. Records JAR path in index for on-demand reading.

cmd_find_source() {
  local group_id="$1" artifact_id="$2" version="$3"
  local coord="${group_id}:${artifact_id}:${version}"

  init_cache

  # Check if already indexed
  local indexed
  indexed=$(check_index "$coord")
  if [ -n "$indexed" ]; then
    echo "CACHED:${coord}"
    return 0
  fi

  # Layer 1: Source JAR
  local src_jar
  src_jar=$(find_source_jar "$group_id" "$artifact_id" "$version")

  if [ -n "$src_jar" ]; then
    update_index "$coord" "source" "$src_jar"
    build_class_index_from_jar "$coord" "$src_jar"
    echo "SOURCE:${src_jar}"
    return 0
  fi

  # Layer 2: Decompile compiled artifact

  local artifact
  artifact=$(find_compiled_artifact "$group_id" "$artifact_id" "$version")

  if [ -z "$artifact" ]; then
    echo "ERROR:No artifact found in Gradle cache for ${coord}"
    return 1
  fi

  local input_jar="$artifact"
  if [[ "$artifact" == *.aar ]]; then
    local tmp_dir
    tmp_dir=$(mktemp -d)
    unzip -o -q "$artifact" classes.jar -d "$tmp_dir" 2>/dev/null
    if [ -f "${tmp_dir}/classes.jar" ]; then
      input_jar="${tmp_dir}/classes.jar"
    else
      echo "ERROR:No classes.jar found in AAR"
      rm -rf "$tmp_dir"
      return 1
    fi
  fi

  local dest="${CACHE_ROOT}/decompiled/${group_id}/${artifact_id}/${version}"
  mkdir -p "$dest"
  decompile_jar "$input_jar" "$dest"

  if [ -d "${dest}/sources" ]; then
    update_index "$coord" "decompiled" "${dest}/sources"
    build_class_index_for_coord "$coord" "${dest}/sources"
    echo "DECOMPILED:${dest}/sources"
  else
    update_index "$coord" "decompiled" "$dest"
    build_class_index_for_coord "$coord" "$dest"
    echo "DECOMPILED:${dest}"
  fi

  [[ "$artifact" == *.aar ]] && rm -rf "$(dirname "$input_jar")" 2>/dev/null || true
  return 0
}
