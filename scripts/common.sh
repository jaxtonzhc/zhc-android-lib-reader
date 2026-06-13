#!/usr/bin/env bash
# 全局变量与基础工具函数
# Note: Module scripts are sourced by lib-reader.sh which sets 'set -euo pipefail'.
# Do NOT set shell options here — they would override the caller's settings.

CACHE_ROOT="${HOME}/.gradle/android-lib-reader"
GRADLE_CACHE="${HOME}/.gradle/caches/modules-2/files-2.1"
INDEX_FILE="${CACHE_ROOT}/index.json"
CLASS_INDEX_FILE="${CACHE_ROOT}/class-index.txt"
CLASS_LOOKUP_FILE="${CACHE_ROOT}/class-lookup.txt"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

init_cache() {
  mkdir -p "${CACHE_ROOT}/sources" "${CACHE_ROOT}/decompiled"
  [ -f "$INDEX_FILE" ] || echo '{}' > "$INDEX_FILE"
  [ -f "$CLASS_INDEX_FILE" ] || touch "$CLASS_INDEX_FILE"
}
