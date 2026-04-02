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

# ── cost: Bug 1 — session spanning 3 days counts as 1 session, not 3 ────────
# A single SID that appears on 3 consecutive days must be counted as 1 session
# in the alltime output, not 3.
_COST_MULTIDAY_TMP="$(mktemp -d)"
_now_ts=$(date +%s)
_day0=$(( _now_ts - 86400 * 10 ))  # 10 days ago
_day1=$(( _day0 + 86400 ))
_day2=$(( _day0 + 86400 * 2 ))

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_day0" "claude-sonnet-4-5" "1.00" "multiday-sid" "1.00" "5000" "1000" \
  "$_day1" "claude-sonnet-4-5" "2.00" "multiday-sid" "2.00" "5000" "1000" \
  "$_day2" "claude-sonnet-4-5" "3.00" "multiday-sid" "3.00" "5000" "1000" \
  > "$_COST_MULTIDAY_TMP/history.tsv"

cost_multiday_out=$(CLAUDII_CACHE_DIR="$_COST_MULTIDAY_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)

assert_contains "cost (multiday): shows 1 session not 3" "1 session" "$cost_multiday_out"
assert_not_contains "cost (multiday): does not show 3 sessions" "3 sessions" "$cost_multiday_out"

rm -rf "$_COST_MULTIDAY_TMP"
unset _COST_MULTIDAY_TMP _now_ts _day0 _day1 _day2 cost_multiday_out

# ── cost: Bug 2 — minor cost fluctuation must not trigger a false reset ───────
# A cost drop of <50% (floating-point noise) should NOT count as extra spend.
# A cost drop of >50% (genuine compaction) SHOULD count as extra spend.
_COST_RESET_TMP="$(mktemp -d)"
_now_ts=$(date +%s)
_base=$(( _now_ts - 3600 ))

# Session A: cost goes 10.00 → 10.002 → 10.001 (minor noise, should not reset)
# Total real spend: ~10.001 (just the initial cost + tiny increment)
# Session B: cost goes 5.00 → 0.10 (genuine compaction drop >50%, should add 0.10)
# Total real spend: ~5.10
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(( _base - 200 ))" "claude-opus-4-5" "10.000" "noise-sid" "10.000" "5000" "1000" \
  "$(( _base - 100 ))" "claude-opus-4-5" "10.002" "noise-sid" "10.002" "5000" "1000" \
  "$(( _base - 50  ))" "claude-opus-4-5" "10.001" "noise-sid" "10.001" "5000" "1000" \
  "$(( _base - 300 ))" "claude-opus-4-5" "5.000"  "reset-sid" "5.000"  "5000" "1000" \
  "$_base"              "claude-opus-4-5" "0.100"  "reset-sid" "0.100"  "5000" "1000" \
  > "$_COST_RESET_TMP/history.tsv"

cost_reset_out=$(CLAUDII_CACHE_DIR="$_COST_RESET_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --tsv 2>&1)

# The noise-sid should contribute ~10.00 total (not ~20.00 from false reset)
# The reset-sid should contribute ~5.10 (5.00 + 0.10 post-compaction)
# Combined alltime Opus should be in 14-16 range, definitely not 25+
_cost_alltime=$(printf '%s\n' "$cost_reset_out" | awk -F'\t' '$1=="alltime" && $2=="Opus" {print $3}')
assert_eq "cost (reset threshold): alltime Opus in range (no false reset)" "1" \
  "$(awk "BEGIN{print (\"$_cost_alltime\"+0 < 17) ? 1 : 0}")"

rm -rf "$_COST_RESET_TMP"
unset _COST_RESET_TMP _now_ts _base cost_reset_out _cost_alltime

# ── cost: Bug 3 — Week header shows date range ────────────────────────────────
# The Week section header must include the date range (week_start – today).
_COST_WEEKHDR_TMP="$(mktemp -d)"
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(( _now_ts - 3600 ))" "claude-sonnet-4-5" "1.00" "wk-sid" "1.00" "5000" "1000" \
  > "$_COST_WEEKHDR_TMP/history.tsv"

cost_weekhdr_out=$(CLAUDII_CACHE_DIR="$_COST_WEEKHDR_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)

# Week header must contain a date range in YYYY-MM-DD format (week_start – today)
_week_line=$(printf '%s\n' "$cost_weekhdr_out" | grep -i 'Week')
assert_contains "cost (week header): Week line shows date range" "(" "$_week_line"
assert_contains "cost (week header): Week line has a year" "20" "$_week_line"

rm -rf "$_COST_WEEKHDR_TMP"
unset _COST_WEEKHDR_TMP _now_ts cost_weekhdr_out _week_line
