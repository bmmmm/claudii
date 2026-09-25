# lib/search_dir.sh — where `claudii search` and the `clq` alias start Claude.
# Sourced by bin/claudii (bash) and claudii.plugin.zsh (zsh), so it is written
# for both shells.
#
# Usage: _claudii_search_dir [configured]
#   configured — search.dir, or an alias's dir set to "@search". Empty or
#                "@search" selects the default, ~/search; "~" is expanded.
# Prints the directory and creates it: it is claudii's own scratch workspace.
# The old default ~/claude-search was never created, so `search` died on `cd`
# and `clq` silently started Claude in whatever directory the shell was in.
#
# The default sits OUTSIDE the claudii checkout on purpose: Claude Code loads
# CLAUDE.md (and .claude/) from the start directory upwards, so a workspace
# inside the repo put claudii's own project rules into every search session.
_claudii_search_dir() {
  local d="${1:-}"
  if [ -z "$d" ] || [ "$d" = "@search" ]; then
    d="$HOME/search"
  fi
  case "$d" in
    "~"|"~/"*) d="$HOME${d#\~}" ;;
  esac
  mkdir -p "$d" 2>/dev/null
  printf '%s\n' "$d"
}
