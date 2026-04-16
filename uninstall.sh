#!/bin/bash
# claudii uninstall — removes symlinks, source line, optionally config
# Usage: uninstall.sh [--purge]
set -euo pipefail

CLAUDII_HOME="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${CLAUDII_INSTALL_BIN_DIR:-/usr/local/bin}"
ZSHRC="${CLAUDII_INSTALL_ZSHRC:-${ZDOTDIR:-$HOME}/.zshrc}"
CONFIG_DIR="${CLAUDII_INSTALL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claudii}"

PURGE=false
for arg in "$@"; do [[ "$arg" == "--purge" ]] && PURGE=true; done

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Uninstalling claudii..."
echo ""

# 1. Remove symlinks that point into this repo
for bin in claudii claudii-status claudii-sessionline; do
  target="$BIN_DIR/$bin"
  if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$CLAUDII_HOME/bin/$bin" ]]; then
    rm "$target"
    echo -e "  ${GREEN}removed${NC}: $target"
  fi
done

# 2. Remove source line, PATH entry, and comment markers from .zshrc
if [[ -f "$ZSHRC" ]]; then
  _zshrc_tmp=$(mktemp) || { echo "mktemp failed" >&2; exit 1; }
  grep -v -F "$CLAUDII_HOME" "$ZSHRC" \
    | grep -v "^# claudii — Claude Interaction Intelligence$" \
    | grep -v "^# claudii bin$" > "$_zshrc_tmp" || true
  mv "$_zshrc_tmp" "$ZSHRC"
  echo -e "  ${GREEN}cleaned${NC}: $ZSHRC"
fi

# 3. Config: remove only with --purge
if $PURGE; then
  if [[ -d "$CONFIG_DIR" ]]; then
    rm -rf "$CONFIG_DIR"
    echo -e "  ${GREEN}removed${NC}: $CONFIG_DIR"
  fi
else
  echo -e "  ${YELLOW}kept${NC}: $CONFIG_DIR  (use --purge to remove)"
fi

echo ""
echo -e "${GREEN}✓ claudii uninstalled${NC}"
[[ -f "$ZSHRC" ]] && echo "  Activate: source $ZSHRC"
