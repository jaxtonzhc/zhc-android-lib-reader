#!/usr/bin/env bash
# Phase 1 worker: scan one source JAR, emit "########## coord" header + class lines.
# Invoked by xargs -P 8 in cmd-index-all.sh Phase 1.
# Usage: _scan-jar-worker.sh <jar_path> <gradle_cache_root>
# Output (stdout): one block per JAR, compatible with CLASS_INDEX_FILE format.
set -euo pipefail

jar_path="$1"
gradle_cache_root="$2"

rel="${jar_path#${gradle_cache_root}/}"
gid=$(echo "$rel" | cut -d/ -f1)
aid=$(echo "$rel" | cut -d/ -f2)
ver=$(echo "$rel" | cut -d/ -f3)
coord="${gid}:${aid}:${ver}"

printf '########## %s\n' "$coord"
# unzip -Z -1 is pure C (no JVM startup); ~10-50x faster than `jar tf`
unzip -Z -1 "$jar_path" 2>/dev/null \
  | grep -E '\.(java|kt)$' \
  | sed 's/\.[^.]*$//; s/\//./g' \
  || true
