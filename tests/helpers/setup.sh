#!/usr/bin/env bash
# Shared test helpers and mock environment

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"

setup_mock_env() {
  TEST_TMPDIR="$(mktemp -d)"
  TEST_CACHE_ROOT="${TEST_TMPDIR}/cache"
  TEST_GRADLE_CACHE="${TEST_TMPDIR}/gradle"
  TEST_PROJECT_ROOT="${TEST_TMPDIR}/project"

  mkdir -p "${TEST_CACHE_ROOT}/sources" "${TEST_CACHE_ROOT}/decompiled"
  mkdir -p "${TEST_GRADLE_CACHE}"
  mkdir -p "${TEST_PROJECT_ROOT}"

  export CACHE_ROOT="${TEST_CACHE_ROOT}"
  export GRADLE_CACHE="${TEST_GRADLE_CACHE}"
  export PROJECT_ROOT="${TEST_PROJECT_ROOT}"
  export INDEX_FILE="${TEST_CACHE_ROOT}/index.tsv"
  export LEGACY_INDEX_FILE="${TEST_CACHE_ROOT}/index.json"
  export CLASS_INDEX_FILE="${TEST_CACHE_ROOT}/class-index.txt"
  export CLASS_LOOKUP_FILE="${TEST_CACHE_ROOT}/class-lookup.txt"
  export LOOKUP_SORTED_FLAG="${TEST_CACHE_ROOT}/.lookup-sorted"
  export INDEXED_COORDS="${TEST_CACHE_ROOT}/indexed-coords.txt"

  touch "${INDEX_FILE}"
  touch "${CLASS_INDEX_FILE}"
  touch "${INDEXED_COORDS}"
}

# Create a mock source JAR in Gradle cache
# Usage: create_mock_source_jar groupId artifactId version [class1 class2 ...]
create_mock_source_jar() {
  local gid="$1" aid="$2" ver="$3"
  shift 3
  # Gradle caches uses groupId as-is (with dots) as directory name
  local dir="${TEST_GRADLE_CACHE}/${gid}/${aid}/${ver}"
  mkdir -p "$dir"
  local src_dir="${TEST_TMPDIR}/src_$$_${RANDOM}"
  rm -rf "$src_dir"
  mkdir -p "$src_dir"

  for cls in "$@"; do
    local cls_path="${cls//\.//}"
    mkdir -p "${src_dir}/$(dirname "$cls_path")"
    echo "// source of ${cls}" > "${src_dir}/${cls_path}.java"
  done

  jar cf "${dir}/${aid}-${ver}-sources.jar" -C "$src_dir" .
  rm -rf "$src_dir"
}

# Create a mock compiled JAR (class files only)
create_mock_compiled_jar() {
  local gid="$1" aid="$2" ver="$3"
  shift 3
  local dir="${TEST_GRADLE_CACHE}/${gid}/${aid}/${ver}"
  mkdir -p "$dir"
  local cls_dir="${TEST_TMPDIR}/cls_$$_${RANDOM}"
  rm -rf "$cls_dir"
  mkdir -p "$cls_dir"

  for cls in "$@"; do
    local cls_path="${cls//\.//}"
    mkdir -p "${cls_dir}/$(dirname "$cls_path")"
    printf '\xCA\xFE\xBA\xBE\x00\x00\x00\x34\x00\x00' > "${cls_dir}/${cls_path}.class"
  done

  jar cf "${dir}/${aid}-${ver}.jar" -C "$cls_dir" .
  rm -rf "$cls_dir"
}

# Create a mock AAR with classes.jar inside
create_mock_aar() {
  local gid="$1" aid="$2" ver="$3"
  shift 3
  local dir="${TEST_GRADLE_CACHE}/${gid}/${aid}/${ver}"
  mkdir -p "$dir"
  local cls_dir="${TEST_TMPDIR}/aar_$$_${RANDOM}"
  rm -rf "$cls_dir"
  mkdir -p "$cls_dir"

  for cls in "$@"; do
    local cls_path="${cls//\.//}"
    mkdir -p "${cls_dir}/$(dirname "$cls_path")"
    printf '\xCA\xFE\xBA\xBE\x00\x00\x00\x34\x00\x00' > "${cls_dir}/${cls_path}.class"
  done

  jar cf "${cls_dir}/classes.jar" -C "$cls_dir" .
  jar cf "${dir}/${aid}-${ver}.aar" -C "$cls_dir" "classes.jar"
  rm -rf "$cls_dir"
}

create_mock_build_gradle() {
  echo "$1" > "${TEST_PROJECT_ROOT}/build.gradle"
}

teardown_mock_env() {
  [ -d "${TEST_TMPDIR:-}" ] && rm -rf "${TEST_TMPDIR}"
}

load_scripts() {
  source "${SCRIPTS_DIR}/common.sh"
  source "${SCRIPTS_DIR}/cache-ops.sh"
  source "${SCRIPTS_DIR}/version.sh"
  source "${SCRIPTS_DIR}/decompile.sh"
  source "${SCRIPTS_DIR}/cmd-find-source.sh"
  source "${SCRIPTS_DIR}/cmd-find-class.sh"
  source "${SCRIPTS_DIR}/cmd-index-all.sh"
  source "${SCRIPTS_DIR}/cmd-utils.sh"
}
