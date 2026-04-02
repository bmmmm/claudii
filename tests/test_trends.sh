# touches: lib/cmd/sessions.sh lib/cmd/display.sh

# test_trends.sh — claudii trends token-tracking tests (v0.9.0+)
# Verifies that history.tsv with token columns (input_tok, output_tok)
# is handled correctly: trends output works and old entries without
# tokens are processed gracefully.

# ── trends: history.tsv with token columns (new v0.9.0+ format) ──────────────
# Format: timestamp<tab>model<tab>cost<tab>session_id<tab>raw_cost<tab>input_tok<tab>output_tok
_TRENDS_TOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"             "claude-opus-4-5"   "0.50" "abc12345" "0.50" "15000" "5000" \
  "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "def67890" "0.25" "8000"  "2000" \
  > "$_TRENDS_TOK_TMP/history.tsv"

trends_tok_out=$(CLAUDII_CACHE_DIR="$_TRENDS_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
trends_tok_err=$(CLAUDII_CACHE_DIR="$_TRENDS_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 >/dev/null)

assert_eq "trends (tokens): no errors on stderr" "" "$trends_tok_err"
assert_eq "trends (tokens): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_TRENDS_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends >/dev/null 2>&1; echo $?)"
assert_eq "trends (tokens): produces output" "0" "$([ -z "$trends_tok_out" ] && echo 1 || echo 0)"
assert_no_literal_ansi "trends (tokens): no literal \\033 in output" "$trends_tok_out"
assert_contains "trends (tokens): shows tok in Today/Total row" "tok" "$trends_tok_out"

rm -rf "$_TRENDS_TOK_TMP"
unset _TRENDS_TOK_TMP _now_ts trends_tok_out trends_tok_err

# ── trends --json: new format → valid JSON with expected fields ───────────────
_TRENDS_JSON_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"             "claude-opus-4-5"   "0.50" "abc12345" "0.50" "15000" "5000" \
  "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "def67890" "0.25" "8000"  "2000" \
  > "$_TRENDS_JSON_TMP/history.tsv"

trends_json=$(CLAUDII_CACHE_DIR="$_TRENDS_JSON_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)

assert_eq "trends --json (tokens): valid JSON" "0" \
  "$(echo "$trends_json" | jq . >/dev/null 2>&1; echo $?)"
assert_contains "trends --json (tokens): has this_week field" '"this_week"' "$trends_json"
assert_contains "trends --json (tokens): has this_week_total field" '"this_week_total"' "$trends_json"
assert_contains "trends --json (tokens): has last_week field" '"last_week"' "$trends_json"
assert_contains "trends --json (tokens): has model_split_30d field" '"model_split_30d"' "$trends_json"

rm -rf "$_TRENDS_JSON_TMP"
unset _TRENDS_JSON_TMP _now_ts trends_json

# ── trends: old history entries WITHOUT token columns → graceful fallback ──────
# Old format: timestamp model cost ctx_pct rate_5h session_id  (6 cols)
# The code should handle this without crashing.
_TRENDS_OLD_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

# Old 6-column format (no token columns)
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"             "claude-opus-4-5"   "0.50" "45" "30" "abc12345" \
  "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "30" "20" "def67890" \
  > "$_TRENDS_OLD_TMP/history.tsv"

trends_old_out=$(CLAUDII_CACHE_DIR="$_TRENDS_OLD_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
trends_old_err=$(CLAUDII_CACHE_DIR="$_TRENDS_OLD_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 >/dev/null)

assert_eq "trends (old format): no errors on stderr" "" "$trends_old_err"
assert_eq "trends (old format): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_TRENDS_OLD_TMP" bash "$CLAUDII_HOME/bin/claudii" trends >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "trends (old format): no literal \\033 in output" "$trends_old_out"

rm -rf "$_TRENDS_OLD_TMP"
unset _TRENDS_OLD_TMP _now_ts trends_old_out trends_old_err

# ── trends: old format → no "tok" bleed in output ─────────────────────────────
# Old entries should not produce "tok" in output — no phantom token display.
_TRENDS_NOTOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.50" "45" "30" "sid-notok" \
  > "$_TRENDS_NOTOK_TMP/history.tsv"

trends_notok_out=$(CLAUDII_CACHE_DIR="$_TRENDS_NOTOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
assert_not_contains "trends (old format): no 'tok' bleed in output" "tok" "$trends_notok_out"

rm -rf "$_TRENDS_NOTOK_TMP"
unset _TRENDS_NOTOK_TMP _now_ts trends_notok_out

# ── trends --json: old format → valid JSON, no crash ─────────────────────────
_TRENDS_OLD_JSON_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.50" "45" "30" "sid-old" \
  > "$_TRENDS_OLD_JSON_TMP/history.tsv"

trends_old_json=$(CLAUDII_CACHE_DIR="$_TRENDS_OLD_JSON_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)
assert_eq "trends --json (old format): valid JSON" "0" \
  "$(echo "$trends_old_json" | jq . >/dev/null 2>&1; echo $?)"

rm -rf "$_TRENDS_OLD_JSON_TMP"
unset _TRENDS_OLD_JSON_TMP _now_ts trends_old_json

# ── trends: empty history.tsv → actionable message, no crash ─────────────────
_TRENDS_EMPTY_TMP="$(mktemp -d)"
touch "$_TRENDS_EMPTY_TMP/history.tsv"

trends_empty_out=$(CLAUDII_CACHE_DIR="$_TRENDS_EMPTY_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 || true)
assert_matches "trends (empty history): actionable message" "No history|CC-Statusline" "$trends_empty_out"

rm -rf "$_TRENDS_EMPTY_TMP"
unset _TRENDS_EMPTY_TMP trends_empty_out

# ── trends: no history.tsv → actionable message, no crash ────────────────────
_TRENDS_NOHIST_TMP="$(mktemp -d)"

trends_nohist_out=$(CLAUDII_CACHE_DIR="$_TRENDS_NOHIST_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 || true)
assert_matches "trends (no history): actionable message" "No history|CC-Statusline" "$trends_nohist_out"

rm -rf "$_TRENDS_NOHIST_TMP"
unset _TRENDS_NOHIST_TMP trends_nohist_out

# ── trends: explicitly empty cols 6+7 → no crash, no "tok" ───────────────────
# Entries from the planned new format with explicit empty token fields.
_TRENDS_EMPTY_TOK_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\tclaude-opus-4-5\t0.50\tabc12345\t0.50\t\t\n' "$_now_ts" \
  > "$_TRENDS_EMPTY_TOK_TMP/history.tsv"
printf '%s\tclaude-sonnet-4-5\t0.25\tdef67890\t0.25\t\t\n' "$(( _now_ts - 60 ))" \
  >> "$_TRENDS_EMPTY_TOK_TMP/history.tsv"

trends_empty_tok_out=$(CLAUDII_CACHE_DIR="$_TRENDS_EMPTY_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
trends_empty_tok_err=$(CLAUDII_CACHE_DIR="$_TRENDS_EMPTY_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 >/dev/null)

assert_eq "trends (empty tok cols): no errors on stderr" "" "$trends_empty_tok_err"
assert_not_contains "trends (empty tok cols): no 'tok' in output" "tok" "$trends_empty_tok_out"

rm -rf "$_TRENDS_EMPTY_TOK_TMP"
unset _TRENDS_EMPTY_TOK_TMP _now_ts trends_empty_tok_out trends_empty_tok_err
