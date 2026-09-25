# touches: lib/search_dir.sh lib/cmd/config.sh lib/functions.zsh config/defaults.json

# test_search.sh — the search workspace (claudii search, clq alias).
# The old default ~/claude-search was never created: `search` died on `cd`, and
# `clq` started Claude in whatever directory the shell happened to be in.

_SD_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_search.XXXXXX")
trap 'rm -rf "$_SD_TMP" 2>/dev/null' EXIT
mkdir -p "$_SD_TMP/home"

_SD_LIB="$CLAUDII_HOME/lib/search_dir.sh"
_sd() {  # _sd [configured] → resolved dir, with HOME in the sandbox
  HOME="$_SD_TMP/home" bash -c 'source "$0"; _claudii_search_dir "$1"' "$_SD_LIB" "${1:-}"
}

assert_eq "search dir: default is ~/search" "$_SD_TMP/home/search" "$(_sd)"
assert_eq "search dir: created on use" "0" \
  "$([ -d "$_SD_TMP/home/search" ] && echo 0 || echo 1)"
assert_eq "search dir: @search means the default" "$_SD_TMP/home/search" "$(_sd @search)"
# A literal ~, as stored in config — the resolver expands it, not the shell.
# shellcheck disable=SC2088
assert_eq "search dir: configured value wins, ~ expanded" \
  "$_SD_TMP/home/ws" "$(_sd '~/ws')"
assert_eq "search dir: an absolute path is used as is" "$_SD_TMP/abs" "$(_sd "$_SD_TMP/abs")"
assert_eq "search dir: never inside the claudii checkout" "0" \
  "$([[ "$(_sd)" == "$CLAUDII_HOME"/* ]] && echo 1 || echo 0)"  # no case…) in $(): bash 3.2 closes $( at the )
assert_eq "search dir: defaults select the workspace for search and clq" '"~/search"|"@search"' \
  "$(jq -c '.search.dir' "$CLAUDII_HOME/config/defaults.json")|$(jq -c '.aliases.clq.dir' "$CLAUDII_HOME/config/defaults.json")"

# zsh sources the same file for the clq alias.
if command -v zsh >/dev/null 2>&1; then
  assert_eq "search dir: zsh resolves the same way" "$_SD_TMP/home/search" \
    "$(HOME="$_SD_TMP/home" zsh -fc 'source "$0"; _claudii_search_dir @search' "$_SD_LIB")"
fi

# End to end: `claudii search` starts claude inside the configured directory,
# creating it. The stub records where it was started.
mkdir -p "$_SD_TMP/stub" "$_SD_TMP/cfg/claudii"
printf '#!/bin/bash\npwd -P > "%s/started_in"\n' "$_SD_TMP" > "$_SD_TMP/stub/claude"
chmod +x "$_SD_TMP/stub/claude"
jq --arg d "$_SD_TMP/ws-e2e" '.search.dir = $d' "$CLAUDII_HOME/config/defaults.json" \
  > "$_SD_TMP/cfg/claudii/config.json"
_SD_RC=$(HOME="$_SD_TMP/home" XDG_CONFIG_HOME="$_SD_TMP/cfg" CLAUDII_CACHE_DIR="$_SD_TMP/cache" \
  PATH="$_SD_TMP/stub:$PATH" bash "$CLAUDII_HOME/bin/claudii" search >/dev/null 2>&1; echo $?)
assert_eq "search: exit 0" "0" "$_SD_RC"
assert_eq "search: claude started in the (new) search dir" \
  "$(cd "$_SD_TMP" && pwd -P)/ws-e2e" "$(cat "$_SD_TMP/started_in" 2>/dev/null)"
