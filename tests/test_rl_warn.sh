# touches: lib/functions.zsh
# test_rl_warn.sh — pre-launch rate-limit warning (_claudii_rl_warn)
#
# Regression cover: the warning attributed the account-wide 5h window to the
# model being launched ("Sonnet 5h at 86%"), printed raw minutes ("150min")
# instead of the shared _fmt_rel format, ignored statusline.rate_display, and
# took the first fresh session sample in glob order instead of the newest.

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_rl_warn.XXXXXX")
mkdir -p "$TEST_TMP/cache" "$TEST_TMP/config/claudii"
ZDOTDIR_EMPTY=$(mktemp -d "${TMPDIR:-/tmp}/claudii_zdotdir_rl.XXXXXX")
cp "$CLAUDII_HOME/config/defaults.json" "$TEST_TMP/config/claudii/config.json"
CFG="$TEST_TMP/config/claudii/config.json"

_NOW=$(date +%s)

# Run _claudii_rl_warn for a non-opus model (no interactive switch prompt).
_rl_out() {
  CLAUDII_CACHE_DIR="$TEST_TMP/cache" XDG_CONFIG_HOME="$TEST_TMP/config" \
  ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  _CLAUDII_NOW="$_NOW" \
  zsh -c '
    source "$CLAUDII_HOME/claudii.plugin.zsh"
    model=sonnet; effort=high
    _claudii_rl_warn model effort
  ' 2>/dev/null
}

# ── 86% used, reset in 150min → window-scoped wording + _fmt_rel ──

printf 'model=Opus 4.8\nrate_5h=86.0\nreset_5h=%s\n' "$(( _NOW + 9000 ))" \
  > "$TEST_TMP/cache/session-aaaa1111"
out=$(_rl_out)
assert_contains "rl_warn: names the 5h window, not the model" "5h limit" "$out"
assert_eq "rl_warn: no model attribution" "" "$(echo "$out" | grep -o 'Sonnet\|Opus' || true)"
assert_contains "rl_warn: used wording (default display)" "86% used" "$out"
assert_contains "rl_warn: reset via _fmt_rel" "resets in 2h30m" "$out"
assert_eq "rl_warn: no raw minutes" "" "$(echo "$out" | grep -o '150min' || true)"

# ── rate_display=remaining flips the displayed number ──

jq '.statusline.rate_display = "remaining"' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
out=$(_rl_out)
assert_contains "rl_warn: remaining mode shows % left" "14% left" "$out"
jq '.statusline.rate_display = "used"' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"

# ── newest sample wins (account-wide limit, stalest file must not warn) ──

printf 'model=Opus 4.8\nrate_5h=95.0\nreset_5h=%s\n' "$(( _NOW + 9000 ))" \
  > "$TEST_TMP/cache/session-bbbb2222"
sleep 1
printf 'model=Opus 4.8\nrate_5h=86.0\nreset_5h=%s\n' "$(( _NOW + 9000 ))" \
  > "$TEST_TMP/cache/session-aaaa1111"
out=$(_rl_out)
assert_contains "rl_warn: newest sample wins" "86% used" "$out"
assert_eq "rl_warn: older sample ignored" "" "$(echo "$out" | grep -o '95% used' || true)"

# ── below 80% → silent ──

rm -f "$TEST_TMP/cache"/session-*
printf 'model=Opus 4.8\nrate_5h=42.0\nreset_5h=%s\n' "$(( _NOW + 9000 ))" \
  > "$TEST_TMP/cache/session-aaaa1111"
out=$(_rl_out)
assert_eq "rl_warn: below threshold is silent" "" "$out"

# Cleanup
rm -rf "$TEST_TMP" "$ZDOTDIR_EMPTY"
