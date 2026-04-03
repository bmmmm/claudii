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
assert_contains "trends (tokens): shows Last 7 days header" "Last 7 days" "$trends_tok_out"
assert_contains "trends (tokens): shows Today label" "Today" "$trends_tok_out"
assert_contains "trends (tokens): Total line has sessions" "sessions" "$trends_tok_out"
assert_contains "trends (tokens): Median line present" "Median:" "$trends_tok_out"

# Today should appear before any other weekday name in the output
_tok_today_line=$(echo "$trends_tok_out" | grep -n "Today" | head -1 | cut -d: -f1)
_tok_first_wdline=$(echo "$trends_tok_out" | grep -nE "^    (Mon|Tue|Wed|Thu|Fri|Sat|Sun)" | head -1 | cut -d: -f1)
if [[ -n "$_tok_today_line" && -n "$_tok_first_wdline" ]]; then
  assert_eq "trends (tokens): Today appears before other weekday lines" "0" \
    "$([ "$_tok_today_line" -lt "$_tok_first_wdline" ] && echo 0 || echo 1)"
fi
unset _tok_today_line _tok_first_wdline

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

# ── trends: small cost decrease (< 50% drop) → NOT treated as reset ──────────
# A tiny floating-point decrease (e.g. $10.003 → $10.002) must produce zero
# delta, not attribute the post-decrease value as a new session cost.
# history.tsv format: timestamp model cost ctx_pct rate_5h session_id in_tok out_tok
_TRENDS_NOISE_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

# Two rows for same session (col6=noise-sid): cost 10.003 → 10.002 (noise, <50% drop)
printf '%s\tclaude-sonnet-4-5\t10.003\t45\t0.5\tnoise-sid\t5000\t1000\n' "$(( _now_ts - 120 ))" \
  > "$_TRENDS_NOISE_TMP/history.tsv"
printf '%s\tclaude-sonnet-4-5\t10.002\t45\t0.5\tnoise-sid\t5001\t1001\n' "$(( _now_ts - 60 ))" \
  >> "$_TRENDS_NOISE_TMP/history.tsv"

trends_noise_json=$(CLAUDII_CACHE_DIR="$_TRENDS_NOISE_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)

# Total cost for the day should be ~10.00 (first row only), not ~20.00
_noise_day=$(date +%Y-%m-%d)
_noise_day_cost=$(echo "$trends_noise_json" | jq -r --arg d "$_noise_day" '
  .this_week[] | select(.date == $d) | .cost
')

assert_eq "trends (noise reset): small cost decrease not treated as reset" "0" \
  "$(awk "BEGIN { print (\"$_noise_day_cost\" + 0 > 15) ? 1 : 0 }")"

rm -rf "$_TRENDS_NOISE_TMP"
unset _TRENDS_NOISE_TMP _now_ts trends_noise_json _noise_day _noise_day_cost

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

# ── trends: new features — Last 7 days, reverse order, Total with sessions, Median, Trend ──
_TRENDS_NEW_TMP="$(mktemp -d)"
_now_ts=$(date +%s)
# Two sessions today: one Opus, one Sonnet
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts"              "claude-opus-4-5"   "5.00"  "new-sid1" "5.00"  "50000" "10000" \
  "$(( _now_ts - 300 ))"  "claude-sonnet-4-5" "2.00"  "new-sid2" "2.00"  "20000" "5000"  \
  > "$_TRENDS_NEW_TMP/history.tsv"

trends_new_out=$(CLAUDII_CACHE_DIR="$_TRENDS_NEW_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)

assert_eq    "trends (new features): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_TRENDS_NEW_TMP" bash "$CLAUDII_HOME/bin/claudii" trends >/dev/null 2>&1; echo $?)"
assert_contains "trends (new features): shows Last 7 days header"    "Last 7 days"  "$trends_new_out"
assert_contains "trends (new features): shows Today label"           "Today"        "$trends_new_out"
assert_contains "trends (new features): Total line has sessions"     "sessions"     "$trends_new_out"
assert_contains "trends (new features): Median line present"         "Median:"      "$trends_new_out"
assert_contains "trends (new features): Trend line present"          "Trend:"       "$trends_new_out"
assert_not_contains "trends (new features): no This week header"     "This week"    "$trends_new_out"
assert_no_literal_ansi "trends (new features): no literal ANSI in output" "$trends_new_out"

# Trend line must contain an arrow (↑ ↓ or →)
assert_matches "trends (new features): Trend line has arrow" \
  $'\342\206\221|\342\206\223|\342\206\222' "$trends_new_out"

# Today must be the first day label in the output
_new_today_line=$(echo "$trends_new_out" | grep -n "Today" | head -1 | cut -d: -f1)
_new_first_wdline=$(echo "$trends_new_out" | grep -nE "^    (Mon|Tue|Wed|Thu|Fri|Sat|Sun)" | head -1 | cut -d: -f1)
if [[ -n "$_new_today_line" && -n "$_new_first_wdline" ]]; then
  assert_eq "trends (new features): Today appears before other weekday lines" "0" \
    "$([ "$_new_today_line" -lt "$_new_first_wdline" ] && echo 0 || echo 1)"
fi
unset _new_today_line _new_first_wdline

rm -rf "$_TRENDS_NEW_TMP"
unset _TRENDS_NEW_TMP _now_ts trends_new_out
