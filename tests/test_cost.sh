# touches: lib/cmd/sessions.sh lib/cmd/display.sh

# test_cost.sh — claudii cost token-tracking tests (v0.9.0+)
# Verifies that history.tsv with token columns (input_tok, output_tok)
# is handled correctly: display works and old entries without tokens
# are processed gracefully.

# ── cost: history.tsv with token columns (new v0.9.0+ format) ────────────────
# Format: timestamp<tab>model<tab>cost<tab>session_id<tab>raw_cost<tab>input_tok<tab>output_tok
_COST_TOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"              "claude-opus-4-5"   "0.50" "abc12345" "0.50" "15000" "5000" \
  "$(( _now_ts - 60 ))"  "claude-sonnet-4-5" "0.25" "def67890" "0.25" "8000"  "2000" \
  > "$_COST_TOK_TMP/history.tsv"

cost_tok_out=$(CLAUDII_CACHE_DIR="$_COST_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_tok_err=$(CLAUDII_CACHE_DIR="$_COST_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)

assert_eq "cost (tokens): no errors on stderr" "" "$cost_tok_err"
assert_eq "cost (tokens): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_COST_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "cost (tokens): no literal \\033 in output" "$cost_tok_out"
assert_contains "cost (tokens): shows tok in Total row" "tok" "$cost_tok_out"

rm -rf "$_COST_TOK_TMP"
unset _COST_TOK_TMP _now_ts cost_tok_out cost_tok_err

# ── cost: old history entries WITHOUT token columns → graceful fallback ───────
# Old format: timestamp model cost ctx_pct rate_5h session_id  (6 cols, empty cols 6+7)
# The code should handle this without crashing (awk $6=="" filter skips header rows)
_COST_OLD_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

# Old 6-column format (no token columns)
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"             "claude-opus-4-5"   "0.50" "45" "30" "abc12345" \
  "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "30" "20" "def67890" \
  > "$_COST_OLD_TMP/history.tsv"

cost_old_out=$(CLAUDII_CACHE_DIR="$_COST_OLD_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_old_err=$(CLAUDII_CACHE_DIR="$_COST_OLD_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)

assert_eq "cost (old format): no errors on stderr" "" "$cost_old_err"
assert_eq "cost (old format): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_COST_OLD_TMP" bash "$CLAUDII_HOME/bin/claudii" cost >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "cost (old format): no literal \\033 in output" "$cost_old_out"

rm -rf "$_COST_OLD_TMP"
unset _COST_OLD_TMP _now_ts cost_old_out cost_old_err

# ── cost: mixed old+new format entries → no crash ─────────────────────────────
# A real-world scenario: history.tsv may have old entries (6 cols) followed
# by new entries (7 cols with tokens).
_COST_MIX_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

# Old entry (6 cols) — from before v0.9.0
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(( _now_ts - 86400 ))" "claude-sonnet-4-5" "0.10" "40" "20" "old-session-id" \
  > "$_COST_MIX_TMP/history.tsv"
# New entry (7 cols) — v0.9.0+
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.25" "new-session-id" "0.25" "8000" "2000" \
  >> "$_COST_MIX_TMP/history.tsv"

cost_mix_out=$(CLAUDII_CACHE_DIR="$_COST_MIX_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_mix_err=$(CLAUDII_CACHE_DIR="$_COST_MIX_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)

assert_eq "cost (mixed format): no errors on stderr" "" "$cost_mix_err"
assert_eq "cost (mixed format): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_COST_MIX_TMP" bash "$CLAUDII_HOME/bin/claudii" cost >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "cost (mixed format): no literal \\033 in output" "$cost_mix_out"

rm -rf "$_COST_MIX_TMP"
unset _COST_MIX_TMP _now_ts cost_mix_out cost_mix_err

# ── cost --json: new format → valid JSON, no crash ────────────────────────────
_COST_JSON_TOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"             "claude-opus-4-5"   "0.50" "abc12345" "0.50" "15000" "5000" \
  "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "def67890" "0.25" "8000"  "2000" \
  > "$_COST_JSON_TOK_TMP/history.tsv"

cost_json_tok=$(CLAUDII_CACHE_DIR="$_COST_JSON_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --json 2>&1)
assert_eq "cost --json (tokens): valid JSON output" "0" \
  "$(echo "$cost_json_tok" | jq . >/dev/null 2>&1; echo $?)"

rm -rf "$_COST_JSON_TOK_TMP"
unset _COST_JSON_TOK_TMP _now_ts cost_json_tok

# ── cost: old format entries (empty cols 6+7) → no "tok" bleed ───────────────
# Old entries should not produce "tok" in output — no phantom token display.
_COST_NOTOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.50" "45" "30" "sid-notok" \
  > "$_COST_NOTOK_TMP/history.tsv"

cost_notok_out=$(CLAUDII_CACHE_DIR="$_COST_NOTOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
assert_not_contains "cost (old format): no 'tok' bleed in output" "tok" "$cost_notok_out"

rm -rf "$_COST_NOTOK_TMP"
unset _COST_NOTOK_TMP _now_ts cost_notok_out

# ── cost: explicitly empty cols 6+7 (tab-terminated old entries) → no crash ──
# Entries from the old format with trailing empty fields should be silently skipped.
_COST_EMPTY_TOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

# Two entries with explicit empty cols 6+7 (old format, empty trailing tabs)
printf '%s\tclaude-opus-4-5\t0.50\tabc12345\t0.50\t\t\n' "$_now_ts" \
  > "$_COST_EMPTY_TOK_TMP/history.tsv"
printf '%s\tclaude-sonnet-4-5\t0.25\tdef67890\t0.25\t\t\n' "$(( _now_ts - 60 ))" \
  >> "$_COST_EMPTY_TOK_TMP/history.tsv"

cost_empty_tok_out=$(CLAUDII_CACHE_DIR="$_COST_EMPTY_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_empty_tok_err=$(CLAUDII_CACHE_DIR="$_COST_EMPTY_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)

assert_eq "cost (empty tok cols): no errors on stderr" "" "$cost_empty_tok_err"
assert_not_contains "cost (empty tok cols): no 'tok' in output" "tok" "$cost_empty_tok_out"

rm -rf "$_COST_EMPTY_TOK_TMP"
unset _COST_EMPTY_TOK_TMP _now_ts cost_empty_tok_out cost_empty_tok_err
