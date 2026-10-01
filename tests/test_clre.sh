# touches: lib/functions.zsh
# test_clre.sh — clre resume alias
#
# Covers: bare invocation opens the picker, an id is forwarded, extra flags
# pass through, and the shared 5h warning fires without offering a model
# switch (a resumed session keeps its own model — see lib/functions.zsh).

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_clre.XXXXXX")
mkdir -p "$TEST_TMP/cache" "$TEST_TMP/config/claudii"
ZDOTDIR_EMPTY=$(mktemp -d "${TMPDIR:-/tmp}/claudii_zdotdir_clre.XXXXXX")
cp "$CLAUDII_HOME/config/defaults.json" "$TEST_TMP/config/claudii/config.json"

_NOW=$(date +%s)

# Run clre with `claude` stubbed out — the stub echoes the argv it was handed.
# </dev/null so an unexpected interactive `read -k1` fails instead of hanging.
_clre_run() {
  CLAUDII_CACHE_DIR="$TEST_TMP/cache" XDG_CONFIG_HOME="$TEST_TMP/config" \
  ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  _CLAUDII_NOW="$_NOW" _CLRE_ARGS="$*" \
  zsh -c '
    source "$CLAUDII_HOME/claudii.plugin.zsh"
    function claude { print -r -- "ARGV: $*" }
    clre ${=_CLRE_ARGS}
  ' </dev/null 2>/dev/null
}

# ── no argument → bare --resume (interactive picker) ──
out=$(_clre_run)
assert_eq "clre: bare call passes --resume only" "ARGV: --resume" "$(echo "$out" | grep '^ARGV:')"

# ── session id → forwarded as the --resume argument ──
out=$(_clre_run "abc123def456")
assert_eq "clre: id is forwarded" "ARGV: --resume abc123def456" "$(echo "$out" | grep '^ARGV:')"

# ── extra flags pass through after the id ──
out=$(_clre_run "abc123def456 --model opus")
assert_eq "clre: extra flags pass through" "ARGV: --resume abc123def456 --model opus" \
  "$(echo "$out" | grep '^ARGV:')"

# ── never injects --model/--effort of its own ──
out=$(_clre_run "abc123def456")
assert_eq "clre: no --effort injected" "" "$(echo "$out" | grep -o '\-\-effort' || true)"

# ── 5h warning fires, but without the opus switch prompt ──
printf 'model=Opus 4.8\nrate_5h=93.0\nreset_5h=%s\n' "$(( _NOW + 3600 ))" \
  > "$TEST_TMP/cache/session-bbbb2222"
out=$(_clre_run "abc123def456")
assert_contains "clre: 5h warning is shown" "5h limit" "$out"
assert_eq "clre: no model-switch prompt on resume" "" "$(echo "$out" | grep -o 'Switch to' || true)"
assert_eq "clre: still launches after the warning" "ARGV: --resume abc123def456" \
  "$(echo "$out" | grep '^ARGV:')"
rm -f "$TEST_TMP/cache/session-bbbb2222"

rm -rf "$TEST_TMP" "$ZDOTDIR_EMPTY"
