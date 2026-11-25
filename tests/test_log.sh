# touches: lib/log.sh lib/config.zsh lib/functions.zsh claudii.plugin.zsh
# test_log.sh — the one _claudii_log (lib/log.sh), in bash and in the zsh plugin
#
# lib/config.zsh used to define its own zsh _claudii_log, which shadowed the
# lib/log.sh the plugin sources first. Now log.sh is the only implementation.

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_log.XXXXXX")
mkdir -p "$TEST_TMP/cache" "$TEST_TMP/config/claudii"
ZDOTDIR_EMPTY=$(mktemp -d "${TMPDIR:-/tmp}/claudii_zdotdir_log.XXXXXX")

# ── bash: explicit level gates by severity ──
_lg_out=$(CLAUDII_LOG_LEVEL=warn bash -c '
  source "$1/lib/log.sh"
  _claudii_log error "E-line"; _claudii_log warn "W-line"
  _claudii_log info "I-line"; _claudii_log debug "D-line"
' _ "$CLAUDII_HOME" 2>&1)
assert_contains     "log bash: warn level prints error" "[claudii:error] E-line" "$_lg_out"
assert_contains     "log bash: warn level prints warn"  "[claudii:warn] W-line"  "$_lg_out"
assert_not_contains "log bash: warn level hides info"   "I-line" "$_lg_out"
assert_not_contains "log bash: warn level hides debug"  "D-line" "$_lg_out"

# ── bash: off prints nothing ──
_lg_out=$(CLAUDII_LOG_LEVEL=off bash -c '
  source "$1/lib/log.sh"; _claudii_log error "E-line"
' _ "$CLAUDII_HOME" 2>&1)
assert_eq "log bash: off is silent" "" "$_lg_out"

# ── bash: no env var → debug.level from the user config ──
jq '.debug.level = "info"' "$CLAUDII_HOME/config/defaults.json" > "$TEST_TMP/config/claudii/config.json"
_lg_out=$(env -u CLAUDII_LOG_LEVEL XDG_CONFIG_HOME="$TEST_TMP/config" bash -c '
  source "$1/lib/log.sh"; _claudii_log info "I-line"; _claudii_log debug "D-line"
' _ "$CLAUDII_HOME" 2>&1)
assert_contains     "log bash: lazy debug.level=info prints info" "I-line" "$_lg_out"
assert_not_contains "log bash: lazy debug.level=info hides debug" "D-line" "$_lg_out"

# ── zsh plugin: log.sh is the active implementation, level synced early ──
# debug.level=debug + one alias: the "registered alias" line is the plugin's
# very first log call (_claudii_register_aliases), so it only shows up if the
# config cache — and with it CLAUDII_LOG_LEVEL — is loaded before it.
if command -v zsh >/dev/null 2>&1; then
  jq '.debug.level = "debug" | .agents = {}' "$CLAUDII_HOME/config/defaults.json" \
    > "$TEST_TMP/config/claudii/config.json"
  # Fresh status cache: keeps the plugin's head-start refresh off the network.
  printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$TEST_TMP/cache/status-models"
  _lg_out=$(env -u CLAUDII_LOG_LEVEL CLAUDII_CACHE_DIR="$TEST_TMP/cache" \
    XDG_CONFIG_HOME="$TEST_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
    zsh -c '
      source "$CLAUDII_HOME/claudii.plugin.zsh"
      print -r -- "WHENCE: $(whence -v _claudii_log)"
    ' </dev/null 2>&1)
  assert_contains "log zsh: _claudii_log comes from lib/log.sh" "lib/log.sh" \
    "$(grep '^WHENCE:' <<< "$_lg_out")"
  assert_contains "log zsh: first log call already honours debug.level" \
    "[claudii:debug] registered alias: cl" "$_lg_out"
fi

rm -rf "$TEST_TMP" "$ZDOTDIR_EMPTY"
unset TEST_TMP ZDOTDIR_EMPTY _lg_out
