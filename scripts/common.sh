#!/usr/bin/env bash
# 全局变量与基础工具函数
# Note: Module scripts are sourced by lib-reader.sh which sets 'set -euo pipefail'.
# Do NOT set shell options here — they would override the caller's settings.

CACHE_ROOT="${HOME}/.gradle/android-lib-reader"
GRADLE_CACHE="${HOME}/.gradle/caches/modules-2/files-2.1"
INDEX_FILE="${CACHE_ROOT}/index.tsv"
LEGACY_INDEX_FILE="${CACHE_ROOT}/index.json"
CLASS_INDEX_FILE="${CACHE_ROOT}/class-index.txt"
CLASS_LOOKUP_FILE="${CACHE_ROOT}/class-lookup.txt"
LOOKUP_SORTED_FLAG="${CACHE_ROOT}/.lookup-sorted"
INDEXED_COORDS="${CACHE_ROOT}/indexed-coords.txt"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

init_cache() {
  mkdir -p "${CACHE_ROOT}/sources" "${CACHE_ROOT}/decompiled"
  [ -f "$INDEX_FILE" ] || touch "$INDEX_FILE"
  [ -f "$CLASS_INDEX_FILE" ] || touch "$CLASS_INDEX_FILE"
  [ -f "$INDEXED_COORDS" ] || touch "$INDEXED_COORDS"
  migrate_legacy_index
}

# Migrate legacy index.json → index.tsv (one-time, idempotent)
migrate_legacy_index() {
  [ ! -f "$LEGACY_INDEX_FILE" ] && return 0
  [ -s "$INDEX_FILE" ] && return 0  # already migrated
  python3 -c "
import json, sys
try:
    idx = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)  # corrupted, skip migration
with open(sys.argv[2], 'w') as f:
    for coord, entry in idx.items():
        t = entry.get('type', 'unknown')
        p = entry.get('path', '')
        ts = entry.get('extracted_at', '')
        f.write(f'{coord}\t{t}\t{p}\t{ts}\n')
" "$LEGACY_INDEX_FILE" "$INDEX_FILE" 2>/dev/null || true
  [ -s "$INDEX_FILE" ] && mv "$LEGACY_INDEX_FILE" "${LEGACY_INDEX_FILE}.bak"
}
