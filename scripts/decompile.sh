#!/usr/bin/env bash
# Multi-decompiler unified module
# Priority: jadx (if installed) > CFR > Fernflower
# Fallback: if a bundled decompiler fails, automatically tries the next one.
# Decompiler JARs stored in scripts/decompilers/ directory

DECOMPILERS_DIR="${SCRIPT_DIR}/decompilers"
CFR_JAR="${DECOMPILERS_DIR}/cfr.jar"
FERNFLOWER_JAR="${DECOMPILERS_DIR}/fernflower.jar"

# Detect Java major version (used only for reporting, not for selection)
_detect_java_version() {
  if ! command -v java &>/dev/null; then
    echo ""
    return
  fi
  local ver_output
  ver_output=$(java -version 2>&1)
  local major minor
  if [[ "$ver_output" =~ version\ \"([0-9]+)\.([0-9]+) ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if [ "$major" -eq 1 ]; then
      echo "$minor"
    else
      echo "$major"
    fi
  fi
}

# List all available decompilers in priority order, one per line "name:path"
# Priority: jadx > CFR > Fernflower (no Java version binding)
_available_decompilers() {
  local found=false

  if command -v jadx &>/dev/null; then
    echo "jadx:$(command -v jadx)"
    found=true
  fi

  if [ -f "$CFR_JAR" ]; then
    echo "cfr:${CFR_JAR}"
    found=true
  fi

  if [ -f "$FERNFLOWER_JAR" ]; then
    echo "fernflower:${FERNFLOWER_JAR}"
    found=true
  fi

  $found && return 0
  return 1
}

# Backward-compatible wrapper: returns first available decompiler
_select_decompiler() {
  _available_decompilers | head -1
}

# Run a single decompiler and validate output
# Usage: _run_decompiler <name> <path> <input_jar> <output_dir>
# Returns: 0=success, 1=execution failed, 2=no output
_run_decompiler() {
  local name="$1" path="$2" input_jar="$3" output_dir="$4"

  mkdir -p "$output_dir"

  case "$name" in
    jadx)
      jadx -d "$output_dir" --no-res --no-debug-info "$input_jar" >/dev/null 2>&1 || return 1
      ;;
    cfr)
      java -jar "$path" "$input_jar" --outputdir "$output_dir" >/dev/null 2>&1 || return 1
      ;;
    fernflower)
      java -jar "$path" "$input_jar" "$output_dir" >/dev/null 2>&1 || return 1
      ;;
    *)
      return 1
      ;;
  esac

  local java_count
  java_count=$(find "$output_dir" -name "*.java" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$java_count" -gt 0 ]; then
    return 0
  fi
  return 2
}

# Unified decompile entry point with automatic fallback
# Usage: decompile_jar <input_jar> <output_dir>
# Returns: 0=success, 1=no decompiler available, 2=all decompilers failed
decompile_jar() {
  local input_jar="$1"
  local output_dir="$2"

  # jadx: highest quality, no fallback on failure (if jadx fails, input is genuinely broken)
  if command -v jadx &>/dev/null; then
    echo "INFO:Decompiling with jadx..."
    if _run_decompiler "jadx" "" "$input_jar" "$output_dir"; then
      local java_count
      java_count=$(find "$output_dir" -name "*.java" -type f 2>/dev/null | wc -l | tr -d ' ')
      echo "INFO:Decompiled ${java_count} Java files"
      return 0
    fi
    echo "WARN:jadx failed on this artifact"
    return 2
  fi

  # Fallback chain: consume _available_decompilers list, skip jadx entries
  local available
  available=$(_available_decompilers 2>/dev/null) || true

  if [ -z "$available" ]; then
    echo "ERROR:No decompiler available. Run scripts/fetch-decompilers.sh or install jadx (brew install jadx)"
    return 1
  fi

  local line
  while IFS= read -r line; do
    local name="${line%%:*}"
    local path="${line#*:}"

    # jadx already handled above, skip
    [ "$name" = "jadx" ] && continue

    # Clean output dir before retry
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    echo "INFO:Decompiling with ${name}..."
    if _run_decompiler "$name" "$path" "$input_jar" "$output_dir"; then
      local java_count
      java_count=$(find "$output_dir" -name "*.java" -type f 2>/dev/null | wc -l | tr -d ' ')
      echo "INFO:Decompiled ${java_count} Java files with ${name}"
      return 0
    fi

    echo "WARN:${name} failed, trying next decompiler..."
  done <<< "$available"

  echo "ERROR:All decompilers failed for ${input_jar}"
  return 2
}

# Ensure a decompiler is available (checks only, no auto-install)
# Use this in init commands or pre-flight checks, NOT in find-source critical path
ensure_decompiler() {
  local available
  available=$(_available_decompilers 2>/dev/null) || true

  if [ -n "$available" ]; then
    local name
    name=$(echo "$available" | head -1 | cut -d: -f1)
    echo "INFO:Decompiler available: ${name}"
    return 0
  fi

  echo "ERROR:No decompiler available. Please install one:"
  echo "  1. brew install jadx          (recommended)"
  echo "  2. bash scripts/fetch-decompilers.sh  (download bundled CFR + Fernflower)"
  return 1
}
