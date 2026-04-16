#!/bin/bash
# claudii install — symlinks bins, adds source to .zshrc, creates config
set -euo pipefail

CLAUDII_HOME="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${CLAUDII_INSTALL_BIN_DIR:-/usr/local/bin}"
ZSHRC="${CLAUDII_INSTALL_ZSHRC:-${ZDOTDIR:-$HOME}/.zshrc}"
CONFIG_DIR="${CLAUDII_INSTALL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claudii}"
CONFIG="$CONFIG_DIR/config.json"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Installing claudii from $CLAUDII_HOME"
echo ""

# 0. Detect existing Homebrew install
brew_prefix="$(brew --prefix 2>/dev/null || true)"
if [[ -n "$brew_prefix" && -f "$brew_prefix/opt/claudii/libexec/claudii.plugin.zsh" ]]; then
  echo -e "${YELLOW}⚠ Homebrew version detected at $brew_prefix/opt/claudii${NC}"
  echo "  Manual + Homebrew installs conflict. Choose one:"
  echo "  → brew uninstall claudii   (then re-run this script)"
  echo "  → or skip this script and use the Homebrew version"
  exit 1
fi

# 1. Symlink binaries — fallback to PATH entry if BIN_DIR is not writable
bin_ok=true
for bin in claudii claudii-status claudii-sessionline; do
  src="$CLAUDII_HOME/bin/$bin"
  target="$BIN_DIR/$bin"
  if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$src" ]]; then
    echo "  already linked: $bin"
  elif ln -sf "$src" "$target" 2>/dev/null; then
    echo -e "  ${GREEN}linked${NC}: $bin → $target"
  else
    bin_ok=false
    echo -e "  ${YELLOW}skip${NC}: $bin (no write access to $BIN_DIR)"
  fi
done

if ! $bin_ok; then
  path_line="export PATH=\"\$PATH:$CLAUDII_HOME/bin\""
  if ! grep -qF "$CLAUDII_HOME/bin" "$ZSHRC" 2>/dev/null; then
    _tmp=$(mktemp) || { echo "mktemp failed" >&2; exit 1; }
    trap "rm -f '$_tmp'" EXIT
    [[ -f "$ZSHRC" ]] && cat "$ZSHRC" > "$_tmp"
    { echo ""; echo "# claudii bin"; echo "$path_line"; } >> "$_tmp"
    mv "$_tmp" "$ZSHRC"
    echo -e "  ${GREEN}added${NC}: PATH entry in $ZSHRC"
  else
    echo "  PATH entry already in $ZSHRC"
  fi
fi

# 2. Add source line to .zshrc
source_line="source \"$CLAUDII_HOME/claudii.plugin.zsh\""
if grep -qF "$CLAUDII_HOME/claudii.plugin.zsh" "$ZSHRC" 2>/dev/null; then
  echo "  already in: $(basename "$ZSHRC")"
else
  _tmp=$(mktemp) || { echo "mktemp failed" >&2; exit 1; }
  trap "rm -f '$_tmp'" EXIT
  [[ -f "$ZSHRC" ]] && cat "$ZSHRC" > "$_tmp"
  { echo ""; echo "# claudii — Claude Interaction Intelligence"; echo "$source_line"; } >> "$_tmp"
  mv "$_tmp" "$ZSHRC"
  echo -e "  ${GREEN}added${NC}: source line in $ZSHRC"
fi

# 3. Create config from defaults if absent
mkdir -p "$CONFIG_DIR"
if [[ -f "$CONFIG" ]]; then
  echo "  config exists: $CONFIG"
else
  cp "$CLAUDII_HOME/config/defaults.json" "$CONFIG"
  echo -e "  ${GREEN}created${NC}: $CONFIG"
fi

echo ""
echo -e "${GREEN}✓ claudii installed${NC}"
echo "  Activate: source $ZSHRC"
