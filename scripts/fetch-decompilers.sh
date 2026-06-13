#!/usr/bin/env bash
# Download built-in decompilers (CFR + Fernflower)
# Run this once to enable decompilation without jadx
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECOMPILERS_DIR="${SCRIPT_DIR}/decompilers"

CFR_VERSION="0.152"
CFR_URL="https://github.com/leibnitz27/cfr/releases/download/${CFR_VERSION}/cfr-${CFR_VERSION}.jar"
FERNFLOWER_URL="https://raw.githubusercontent.com/nicokosi/fernflower/main/build/fernflower.jar"

# Fallback: Maven Central
CFR_MAVEN_URL="https://repo1.maven.org/maven2/org/benf/cfr/${CFR_VERSION}/cfr-${CFR_VERSION}.jar"

mkdir -p "$DECOMPILERS_DIR"

echo "=== Downloading decompilers ==="

# Download CFR
if [ ! -f "${DECOMPILERS_DIR}/cfr.jar" ]; then
  echo "Downloading CFR ${CFR_VERSION}..."
  if curl -sSL -o "${DECOMPILERS_DIR}/cfr.jar" "$CFR_URL" 2>/dev/null; then
    echo "  [OK] CFR downloaded"
  elif curl -sSL -o "${DECOMPILERS_DIR}/cfr.jar" "$CFR_MAVEN_URL" 2>/dev/null; then
    echo "  [OK] CFR downloaded (from Maven Central)"
  else
    echo "  [FAIL] CFR download failed. Download manually from:"
    echo "         https://github.com/leibnitz27/cfr/releases"
    rm -f "${DECOMPILERS_DIR}/cfr.jar"
  fi
else
  echo "  [OK] CFR already exists"
fi

# Download Fernflower
if [ ! -f "${DECOMPILERS_DIR}/fernflower.jar" ]; then
  echo "Downloading Fernflower..."
  # Try IDEA's bundled fernflower or build from source
  # For now, check if Android Studio/IDEA has it
  IDEA_FF=$(find /Applications -path "*/plugins/java-decompiler/lib/fernflower.jar" 2>/dev/null | head -1)
  if [ -n "$IDEA_FF" ]; then
    cp "$IDEA_FF" "${DECOMPILERS_DIR}/fernflower.jar"
    echo "  [OK] Fernflower copied from IntelliJ IDEA"
  elif curl -sSL -o "${DECOMPILERS_DIR}/fernflower.jar" "$FERNFLOWER_URL" 2>/dev/null; then
    echo "  [OK] Fernflower downloaded"
  else
    echo "  [WARN] Fernflower not available. CFR will be used for all Java versions."
    echo "         You can also install jadx: brew install jadx"
    rm -f "${DECOMPILERS_DIR}/fernflower.jar"
  fi
else
  echo "  [OK] Fernflower already exists"
fi

echo ""
echo "=== Decompiler status ==="
[ -f "${DECOMPILERS_DIR}/cfr.jar" ] && echo "  CFR: $(ls -lh "${DECOMPILERS_DIR}/cfr.jar" | awk '{print $5}')" || echo "  CFR: not available"
[ -f "${DECOMPILERS_DIR}/fernflower.jar" ] && echo "  Fernflower: $(ls -lh "${DECOMPILERS_DIR}/fernflower.jar" | awk '{print $5}')" || echo "  Fernflower: not available"
echo ""
echo "Done!"
