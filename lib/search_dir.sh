# lib/search_dir.sh — where `claudii search` and the `clq` alias start Claude.
# Sourced by bin/claudii (bash) and claudii.plugin.zsh (zsh), so it is written
# for both shells.
#
# Usage: _claudii_search_dir [configured]
#   configured — search.dir, or an alias's dir set to "@search". Empty or
#                "@search" selects the default below; "~" is expanded.
# Prints the directory and creates it: it is claudii's own scratch workspace.
# The old default ~/claude-search was never created, so `search` died on `cd`
# and `clq` silently started Claude in whatever directory the shell was in.
#
# Default: search/ inside the claudii checkout (gitignored) when CLAUDII_HOME
# is a writable git checkout; otherwise (a Homebrew install, whose libexec is
# replaced on every upgrade) ${XDG_DATA_HOME:-~/.local/share}/claudii/search.
_claudii_search_dir() {
  local d="${1:-}"
  if [ -z "$d" ] || [ "$d" = "@search" ]; then
    if [ -e "$CLAUDII_HOME/.git" ] && [ -w "$CLAUDII_HOME" ]; then
      d="$CLAUDII_HOME/search"
    else
      d="${XDG_DATA_HOME:-$HOME/.local/share}/claudii/search"
    fi
  fi
  case "$d" in
    "~"|"~/"*) d="$HOME${d#\~}" ;;
  esac
  mkdir -p "$d" 2>/dev/null
  printf '%s\n' "$d"
}
