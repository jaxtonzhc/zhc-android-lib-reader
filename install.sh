#!/usr/bin/env bash
# zhc-android-lib-reader installer
# Supports two modes:
#   1. Local:  bash install.sh  (from cloned repo)
#   2. Remote: curl -sSL .../install.sh | bash  (auto-clones from GitHub)
set -euo pipefail

REPO_URL="https://github.com/jaxtonzhc/zhc-android-lib-reader.git"
SKILL_NAME="zhc-android-lib-reader"
INSTALL_DIR="${HOME}/.local/share/zhc-android-lib-reader"

# ── Remote mode: if not running from cloned repo, clone first ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
if [ ! -f "${SCRIPT_DIR}/scripts/lib-reader.sh" ]; then
  echo "=== Remote install mode ==="
  if [ -d "$INSTALL_DIR" ]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR" && git pull --ff-only 2>/dev/null || true
  else
    echo "Cloning to ${INSTALL_DIR}..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
  SCRIPT_DIR="$INSTALL_DIR"
fi

SKILL_DIRS=(
  "${HOME}/.cursor/skills"
  "${HOME}/.codex/skills"
  "${HOME}/.claude/skills"
  "${HOME}/.agents/skills"
  "${HOME}/.hermes/skills"
)

echo ""
echo "=== ${SKILL_NAME} installer ==="
echo "Source: ${SCRIPT_DIR}"
echo ""

installed=0
skipped=0

for dir in "${SKILL_DIRS[@]}"; do
  target="${dir}/${SKILL_NAME}"
  agent_name=$(basename "$(dirname "$dir")" | sed 's/^\.//')

  if [ ! -d "$dir" ]; then
    echo "  [SKIP] ${agent_name}: skill dir not found"
    skipped=$((skipped + 1))
    continue
  fi

  if [ -L "$target" ]; then
    existing=$(readlink "$target")
    if [ "$existing" = "$SCRIPT_DIR" ]; then
      echo "  [OK]   ${agent_name}: already installed"
      installed=$((installed + 1))
      continue
    else
      echo "  [UPD]  ${agent_name}: updating link"
      rm -f "$target"
    fi
  elif [ -e "$target" ]; then
    echo "  [WARN] ${agent_name}: ${target} exists and is not a symlink, skipping"
    skipped=$((skipped + 1))
    continue
  fi

  ln -sf "$SCRIPT_DIR" "$target"
  echo "  [OK]   ${agent_name}: installed -> ${target}"
  installed=$((installed + 1))
done

# Set permissions
chmod +x "${SCRIPT_DIR}/scripts/lib-reader.sh"
chmod +x "${SCRIPT_DIR}/scripts/decompile.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/scripts/fetch-decompilers.sh" 2>/dev/null || true

echo ""
echo "=== Done: ${installed} agents, ${skipped} skipped ==="
echo ""
echo "Next steps:"
echo "  1. ${SCRIPT_DIR}/scripts/lib-reader.sh init        # Check environment"
echo "  2. ${SCRIPT_DIR}/scripts/lib-reader.sh index-all   # Build index (~1-3 min, one-time)"
echo ""
echo "Optional: download built-in decompilers (no jadx needed):"
echo "  bash ${SCRIPT_DIR}/scripts/fetch-decompilers.sh"
