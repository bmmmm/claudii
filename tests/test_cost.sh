# touches: lib/cmd/cost.sh lib/cmd/display.sh

# test_cost.sh — claudii cost token-tracking tests (v0.9.0+)
# Verifies that history.tsv with token columns (input_tok, output_tok)

_COST_TMPDIRS=()
trap 'rm -rf "${_COST_TMPDIRS[@]}" 2>/dev/null' EXIT
# is handled correctly: display works and old entries without tokens
# are processed gracefully.

# ── cost: history.tsv with token columns (current 9-col raw format) ──────────
# Raw format the CLI augments (sid is column 6 — matches what cc-statusline writes):
#   timestamp  model  cost  ctx_pct  rate_5h  session_id  in_tok  out_tok  api_ms
_COST_TOK_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_TOK_TMP")
_now_ts=$(date +%s)

hist_row "$_COST_TOK_TMP/history.tsv" "$_now_ts"            "claude-opus-4-5"   "0.50" "45" "30" "abc12345" "15000" "5000" "1200"
hist_row "$_COST_TOK_TMP/history.tsv" "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "30" "20" "def67890" "8000"  "2000" "800"

cost_tok_out=$(CLAUDII_CACHE_DIR="$_COST_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_tok_err=$(CLAUDII_CACHE_DIR="$_COST_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)

assert_eq "cost (tokens): no errors on stderr" "" "$cost_tok_err"
assert_eq "cost (tokens): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_COST_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "cost (tokens): no literal \\033 in output" "$cost_tok_out"
assert_contains "cost (tokens): shows dollar amount" "$" "$cost_tok_out"

unset _COST_TOK_TMP _now_ts cost_tok_out cost_tok_err

# ── cost: old history entries WITHOUT token columns → graceful fallback ───────
# Old format: timestamp model cost ctx_pct rate_5h session_id  (6 cols, empty cols 6+7)
# The code should handle this without crashing (awk $6=="" filter skips header rows)
_COST_OLD_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_OLD_TMP")
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

unset _COST_OLD_TMP _now_ts cost_old_out cost_old_err

# ── cost: mixed old+new format entries → no crash ─────────────────────────────
# A real-world scenario: history.tsv may have old entries (6 cols) followed
# by new entries (7 cols with tokens).
_COST_MIX_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_MIX_TMP")
_now_ts=$(date +%s)

# Old entry (6 cols) — from before v0.9.0
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(( _now_ts - 86400 ))" "claude-sonnet-4-5" "0.10" "40" "20" "old-session-id" \
  > "$_COST_MIX_TMP/history.tsv"
# New entry (9 cols) — current format (sid in col 6)
hist_row "$_COST_MIX_TMP/history.tsv" "$_now_ts" "claude-sonnet-4-5" "0.25" "50" "30" "new-session-id" "8000" "2000" "0"

cost_mix_out=$(CLAUDII_CACHE_DIR="$_COST_MIX_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_mix_err=$(CLAUDII_CACHE_DIR="$_COST_MIX_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)

assert_eq "cost (mixed format): no errors on stderr" "" "$cost_mix_err"
assert_eq "cost (mixed format): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_COST_MIX_TMP" bash "$CLAUDII_HOME/bin/claudii" cost >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "cost (mixed format): no literal \\033 in output" "$cost_mix_out"

unset _COST_MIX_TMP _now_ts cost_mix_out cost_mix_err

# ── cost --json: new format → valid JSON, no crash ────────────────────────────
_COST_JSON_TOK_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_JSON_TOK_TMP")
_now_ts=$(date +%s)

hist_row "$_COST_JSON_TOK_TMP/history.tsv" "$_now_ts"            "claude-opus-4-5"   "0.50" "45" "30" "abc12345" "15000" "5000" "1200"
hist_row "$_COST_JSON_TOK_TMP/history.tsv" "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "30" "20" "def67890" "8000"  "2000" "800"

cost_json_tok=$(CLAUDII_CACHE_DIR="$_COST_JSON_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --json 2>&1)
assert_eq "cost --json (tokens): valid JSON output" "0" \
  "$(echo "$cost_json_tok" | jq . >/dev/null 2>&1; echo $?)"

unset _COST_JSON_TOK_TMP _now_ts cost_json_tok

# ── cost: old format entries (empty cols 6+7) → no "tok" bleed ───────────────
# Old entries should not produce "tok" in output — no phantom token display.
_COST_NOTOK_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_NOTOK_TMP")
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.50" "45" "30" "sid-notok" \
  > "$_COST_NOTOK_TMP/history.tsv"

cost_notok_out=$(CLAUDII_CACHE_DIR="$_COST_NOTOK_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
assert_not_contains "cost (old format): no 'tok' bleed in output" "tok" "$cost_notok_out"

unset _COST_NOTOK_TMP _now_ts cost_notok_out

# ── cost: explicitly empty cols 6+7 (tab-terminated old entries) → no crash ──
# Entries from the old format with trailing empty fields should be silently skipped.
_COST_EMPTY_TOK_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_EMPTY_TOK_TMP")
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

unset _COST_EMPTY_TOK_TMP _now_ts cost_empty_tok_out cost_empty_tok_err

# ── cost: Bug 1 — session spanning 3 days counts as 1 session, not 3 ────────
# A single SID that appears on 3 consecutive days must be counted as 1 session
# in the alltime output, not 3.
_COST_MULTIDAY_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_MULTIDAY_TMP")
_now_ts=$(date +%s)
_day0=$(( _now_ts - 86400 * 10 ))  # 10 days ago
_day1=$(( _day0 + 86400 ))
_day2=$(( _day0 + 86400 * 2 ))

hist_row "$_COST_MULTIDAY_TMP/history.tsv" "$_day0" "claude-sonnet-4-5" "1.00" "50" "30" "multiday-sid" "5000" "1000" "0"
hist_row "$_COST_MULTIDAY_TMP/history.tsv" "$_day1" "claude-sonnet-4-5" "2.00" "50" "30" "multiday-sid" "6000" "1200" "0"
hist_row "$_COST_MULTIDAY_TMP/history.tsv" "$_day2" "claude-sonnet-4-5" "3.00" "50" "30" "multiday-sid" "7000" "1400" "0"

# Assert on --tsv (period model cost sessions). The old test ran the PRETTY format and
# assert_not_contains "session" — vacuous, since pretty output never prints that word.
# One SID across 3 days = 1 session; cumulative cost delta (1+1+1) = 3.00.
cost_multiday_out=$(CLAUDII_CACHE_DIR="$_COST_MULTIDAY_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --tsv 2>&1)

assert_contains "cost (multiday): shows Sonnet" "Sonnet" "$cost_multiday_out"
_md_sessions=$(printf '%s\n' "$cost_multiday_out" | awk -F'\t' '$1=="alltime" && $2=="Sonnet" {print $4}')
assert_eq "cost (multiday): 1 SID across 3 days counts as 1 session (not 3)" "1" "$_md_sessions"
_md_cost=$(printf '%s\n' "$cost_multiday_out" | awk -F'\t' '$1=="alltime" && $2=="Sonnet" {print $3}')
assert_eq "cost (multiday): cumulative cost delta = 3.00 (1+1+1)" "1" \
  "$(awk "BEGIN{print (\"$_md_cost\"+0 > 2.99 && \"$_md_cost\"+0 < 3.01) ? 1 : 0}")"

unset _COST_MULTIDAY_TMP _now_ts _day0 _day1 _day2 cost_multiday_out _md_sessions _md_cost

# ── cost: Bug 2 — minor cost fluctuation must not trigger a false reset ───────
# A cost drop of <50% (floating-point noise) should NOT count as extra spend.
# A cost drop of >50% (genuine compaction) SHOULD count as extra spend.
_COST_RESET_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_RESET_TMP")
_now_ts=$(date +%s)
_base=$(( _now_ts - 3600 ))

# Session A: cost goes 10.00 → 10.002 → 10.001 (minor noise, should not reset)
# Total real spend: ~10.001 (just the initial cost + tiny increment)
# Session B: cost goes 5.00 → 0.10 (genuine compaction drop >50%, should add 0.10)
# Total real spend: ~5.10
hist_row "$_COST_RESET_TMP/history.tsv" "$(( _base - 200 ))" "claude-opus-4-5" "10.000" "50" "30" "noise-sid" "5000" "1000" "0"
hist_row "$_COST_RESET_TMP/history.tsv" "$(( _base - 100 ))" "claude-opus-4-5" "10.002" "50" "30" "noise-sid" "5000" "1000" "0"
hist_row "$_COST_RESET_TMP/history.tsv" "$(( _base - 50  ))" "claude-opus-4-5" "10.001" "50" "30" "noise-sid" "5000" "1000" "0"
hist_row "$_COST_RESET_TMP/history.tsv" "$(( _base - 300 ))" "claude-opus-4-5" "5.000"  "50" "30" "reset-sid" "5000" "1000" "0"
hist_row "$_COST_RESET_TMP/history.tsv" "$_base"             "claude-opus-4-5" "0.100"  "50" "30" "reset-sid" "5000" "1000" "0"

cost_reset_out=$(CLAUDII_CACHE_DIR="$_COST_RESET_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --tsv 2>&1)

# The noise-sid should contribute ~10.00 total (not ~20.00 from false reset)
# The reset-sid should contribute ~5.10 (5.00 + 0.10 post-compaction)
# Combined alltime Opus should be in 14-16 range, definitely not 25+
_cost_alltime=$(printf '%s\n' "$cost_reset_out" | awk -F'\t' '$1=="alltime" && $2=="Opus" {print $3}')
assert_eq "cost (reset threshold): alltime Opus in range (no false reset)" "1" \
  "$(awk "BEGIN{print (\"$_cost_alltime\"+0 < 17) ? 1 : 0}")"

unset _COST_RESET_TMP _now_ts _base cost_reset_out _cost_alltime

# ── cost: Bug 3 — Week header shows date range ────────────────────────────────
# The Week section header must include the date range (week_start – today).
_COST_WEEKHDR_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_WEEKHDR_TMP")
_now_ts=$(date +%s)

hist_row "$_COST_WEEKHDR_TMP/history.tsv" "$(( _now_ts - 3600 ))" "claude-sonnet-4-5" "1.00" "50" "30" "wk-sid" "5000" "1000" "0"

cost_weekhdr_out=$(CLAUDII_CACHE_DIR="$_COST_WEEKHDR_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)

# Week header must contain a date range in YYYY-MM-DD format (week_start – today)
_week_line=$(printf '%s\n' "$cost_weekhdr_out" | grep -i 'Week')
assert_contains "cost (week header): Week line shows date range" "(" "$_week_line"
assert_contains "cost (week header): Week line has a year" "20" "$_week_line"

unset _COST_WEEKHDR_TMP _now_ts cost_weekhdr_out _week_line

# ── cost: mixed-model day attributes each increment to the active model ───────
# Regression: a single session that switches model mid-day must split the day's
# spend by the model active at each increment, not credit the whole day to the
# last model seen (Opus work + Sonnet cleanup must NOT show all spend as Sonnet).
# Uses the real 9-col history format written by cc-statusline (sid in col 6).
_COST_MIXMODEL_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_MIXMODEL_TMP")
_now_ts=$(date +%s)

hist_row "$_COST_MIXMODEL_TMP/history.tsv" "$(( _now_ts - 300 ))" "claude-opus-4-8"   "1.00" "50" "30" "mixmodel-sid" "5000" "1000" "0"
hist_row "$_COST_MIXMODEL_TMP/history.tsv" "$(( _now_ts - 100 ))" "claude-sonnet-4-6" "1.50" "50" "30" "mixmodel-sid" "6000" "1500" "0"

cost_mixmodel_out=$(CLAUDII_CACHE_DIR="$_COST_MIXMODEL_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --tsv 2>&1)
_mm_opus=$(printf '%s\n' "$cost_mixmodel_out" | awk -F'\t' '$1=="alltime" && $2=="Opus"   {print $3}')
_mm_sonnet=$(printf '%s\n' "$cost_mixmodel_out" | awk -F'\t' '$1=="alltime" && $2=="Sonnet" {print $3}')

assert_eq "cost (mixed-model day): Opus credited its 1.00 increment" "1" \
  "$(awk "BEGIN{print (\"$_mm_opus\"+0 > 0.99 && \"$_mm_opus\"+0 < 1.01) ? 1 : 0}")"
assert_eq "cost (mixed-model day): Sonnet credited only its 0.50 increment (not 1.50)" "1" \
  "$(awk "BEGIN{print (\"$_mm_sonnet\"+0 > 0.49 && \"$_mm_sonnet\"+0 < 0.51) ? 1 : 0}")"

unset _COST_MIXMODEL_TMP _now_ts cost_mixmodel_out _mm_opus _mm_sonnet

# ── cost --forecast: live 5h burn block + month projection ───────────────────
# Session cache supplies the live account-wide 5h state (rate + future reset);
# climbing rate_5h history rows give the burn slope; older cost deltas drive the
# month projection.
_FC_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_FC_TMP")
_now_ts=$(date +%s)
_fc_reset=$(( _now_ts + 10000 ))   # 5h window resets in ~2h47m (in the future)

printf 'model=Opus 4.8\nctx_pct=50\ncost=12.00\nrate_5h=64\nrate_7d=22\nreset_5h=%d\nreset_7d=%d\nsession_id=fcast001\ntok=1500000\ncache_pct=80\nppid=%s\n' \
  "$_fc_reset" "$(( _now_ts + 200000 ))" "$$" > "$_FC_TMP/session-fcast001"

# rate_5h 58→60→62→64 across ~18 min within the current cycle (burn ~0.34%/min).
hist_row "$_FC_TMP/history.tsv" "$(( _now_ts - 1080 ))" "claude-opus-4-8" "9.00"  "40" "58" "fcast001" "1000000" "200000" "0"
hist_row "$_FC_TMP/history.tsv" "$(( _now_ts - 720 ))"  "claude-opus-4-8" "10.00" "44" "60" "fcast001" "1200000" "240000" "0"
hist_row "$_FC_TMP/history.tsv" "$(( _now_ts - 360 ))"  "claude-opus-4-8" "11.00" "47" "62" "fcast001" "1350000" "270000" "0"
hist_row "$_FC_TMP/history.tsv" "$(( _now_ts - 30 ))"   "claude-opus-4-8" "12.00" "50" "64" "fcast001" "1500000" "300000" "0"
# Earlier spend this month (distinct sessions → first-seen counts as spend).
hist_row "$_FC_TMP/history.tsv" "$(( _now_ts - 6*86400 ))" "claude-opus-4-8"   "40.00" "50" "10" "older-a" "5000000" "1000000" "0"
hist_row "$_FC_TMP/history.tsv" "$(( _now_ts - 9*86400 ))" "claude-sonnet-4-6" "25.00" "50" "10" "older-b" "3000000" "600000"  "0"

fc_out=$(CLAUDII_CACHE_DIR="$_FC_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast 2>&1)
fc_err=$(CLAUDII_CACHE_DIR="$_FC_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast 2>&1 >/dev/null)

assert_eq "cost --forecast: no errors on stderr" "" "$fc_err"
assert_eq "cost --forecast: exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_FC_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast >/dev/null 2>&1; echo $?)"
assert_no_literal_ansi "cost --forecast: no literal \\033 in output" "$fc_out"
assert_contains "cost --forecast: 5h budget block" "5h budget" "$fc_out"
assert_contains "cost --forecast: Used now line" "Used now" "$fc_out"
assert_contains "cost --forecast: shows current used %" "64%" "$fc_out"
assert_contains "cost --forecast: Burn rate line" "Burn rate" "$fc_out"
assert_contains "cost --forecast: Resets countdown" "Resets" "$fc_out"
assert_contains "cost --forecast: This month block" "This month" "$fc_out"
assert_contains "cost --forecast: Pace line" "Pace" "$fc_out"
# Month spend = 12 (fcast first-seen delta) + 40 + 25 = 77.
assert_contains "cost --forecast: month spent total" "\$77.00" "$fc_out"

# JSON shape
fc_json=$(CLAUDII_CACHE_DIR="$_FC_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast --json 2>&1)
assert_eq "cost --forecast --json: valid JSON" "0" \
  "$(echo "$fc_json" | jq . >/dev/null 2>&1; echo $?)"
assert_eq "cost --forecast --json: 5h available" "true" \
  "$(echo "$fc_json" | jq -r '.five_hour.available')"
assert_eq "cost --forecast --json: used_pct = 64" "64" \
  "$(echo "$fc_json" | jq -r '.five_hour.used_pct | floor')"
assert_eq "cost --forecast --json: burn rate is positive" "1" \
  "$(echo "$fc_json" | jq -r 'if .five_hour.burn_pct_per_min > 0 then 1 else 0 end')"
assert_eq "cost --forecast --json: month spent = 77" "77" \
  "$(echo "$fc_json" | jq -r '.month.spent | floor')"
assert_eq "cost --forecast --json: days_in_month is 28..31" "1" \
  "$(echo "$fc_json" | jq -r 'if .month.days_in_month >= 28 and .month.days_in_month <= 31 then 1 else 0 end')"

unset _FC_TMP _now_ts _fc_reset fc_out fc_err fc_json

# ── cost --forecast: no live session → 5h block degrades, month still renders ─
# History only (no session-* cache) → no future reset to anchor the 5h state.
_FC_NO5H_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_FC_NO5H_TMP")
_now_ts=$(date +%s)
hist_row "$_FC_NO5H_TMP/history.tsv" "$(( _now_ts - 3600 ))" "claude-opus-4-8" "30.00" "50" "10" "lonely-sid" "5000000" "1000000" "0"

fc_no5h_out=$(CLAUDII_CACHE_DIR="$_FC_NO5H_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast 2>&1)
assert_eq "cost --forecast (no session): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_FC_NO5H_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast >/dev/null 2>&1; echo $?)"
assert_contains "cost --forecast (no session): 5h state unavailable" "unavailable" "$fc_no5h_out"
assert_contains "cost --forecast (no session): month block still renders" "This month" "$fc_no5h_out"
assert_eq "cost --forecast (no session): 5h not available in JSON" "false" \
  "$(CLAUDII_CACHE_DIR="$_FC_NO5H_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast --json 2>&1 | jq -r '.five_hour.available')"

unset _FC_NO5H_TMP _now_ts fc_no5h_out

# ── cost --forecast: empty cache → friendly no-data message, exit 0 ───────────
_FC_EMPTY_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_FC_EMPTY_TMP")
fc_empty_out=$(CLAUDII_CACHE_DIR="$_FC_EMPTY_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast 2>&1)
assert_eq "cost --forecast (empty): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_FC_EMPTY_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast >/dev/null 2>&1; echo $?)"
assert_contains "cost --forecast (empty): no-data hint" "No forecast data" "$fc_empty_out"

unset _FC_EMPTY_TMP fc_empty_out

# ── cost --forecast: JSON stays valid under a comma-decimal locale ────────────
# Regression: awk %.Nf honors LC_NUMERIC — a de_DE (comma) locale would emit
# "0,5" and break jq. The JSON/TSV path forces LC_ALL=C. Guarded on the locale
# being installed (CI runners often lack it) so it skips rather than passes
# vacuously where a comma can never be produced anyway.
_have_de_locale=$(locale -a 2>/dev/null || true)
if [[ "$_have_de_locale" == *de_DE.UTF-8* || "$_have_de_locale" == *de_DE.utf8* ]]; then
  _FC_LOC_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_FC_LOC_TMP")
  _now_ts=$(date +%s)
  printf 'model=Opus 4.8\nctx_pct=50\ncost=12.00\nrate_5h=64\nrate_7d=22\nreset_5h=%d\nreset_7d=%d\nsession_id=floc0001\ntok=1500000\nppid=%s\n' \
    "$(( _now_ts + 10000 ))" "$(( _now_ts + 200000 ))" "$$" > "$_FC_LOC_TMP/session-floc0001"
  hist_row "$_FC_LOC_TMP/history.tsv" "$(( _now_ts - 600 ))" "claude-opus-4-8" "9.00"  "40" "60" "floc0001" "1000000" "200000" "0"
  hist_row "$_FC_LOC_TMP/history.tsv" "$(( _now_ts - 30 ))"  "claude-opus-4-8" "12.00" "50" "64" "floc0001" "1500000" "300000" "0"
  _fc_loc_json=$(LC_NUMERIC=de_DE.UTF-8 LANG=de_DE.UTF-8 CLAUDII_CACHE_DIR="$_FC_LOC_TMP" bash "$CLAUDII_HOME/bin/claudii" cost --forecast --json 2>&1)
  assert_eq "cost --forecast --json: valid under de_DE comma locale" "0" \
    "$(echo "$_fc_loc_json" | jq . >/dev/null 2>&1; echo $?)"
  assert_contains "cost --forecast --json: dot decimal under comma locale" '64.0' "$_fc_loc_json"
  unset _FC_LOC_TMP _now_ts _fc_loc_json
fi
unset _have_de_locale

# ── cost: Months render as a D-grid (period rows, model columns split by │) ──
# Each calendar month is its OWN row; the │/┼ separators delimit per-tier MODEL
# columns (not side-by-side month tiles). Column widths track the widest value
# via fmt_usd, so alignment survives ANSI color codes.
_COST_GRID_TMP="$(mktemp -d)"; _COST_TMPDIRS+=("$_COST_GRID_TMP")
_now_ts=$(date +%s)

# One session ~5 days ago (this month) and one ~40 days ago (a prior month).
hist_row "$_COST_GRID_TMP/history.tsv" "$(( _now_ts - 5*86400 ))"  "claude-opus-4-6" "12.00" "0" "0" "tile-a" "5000" "1000" "0"
hist_row "$_COST_GRID_TMP/history.tsv" "$(( _now_ts - 40*86400 ))" "claude-opus-4-6" "34.00" "0" "0" "tile-b" "5000" "1000" "0"

cost_grid_out=$(COLUMNS=120 CLAUDII_CACHE_DIR="$_COST_GRID_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
_grid_plain=$(printf '%s\n' "$cost_grid_out" | sed $'s/\033\\[[0-9;]*m//g')
assert_contains "cost (D-grid): Month column header" "Month" "$_grid_plain"
assert_contains "cost (D-grid): header rule has ┼ crossing" $'\342\224\274' "$_grid_plain"
assert_contains "cost (D-grid): rows carry the │ column separator" $'\342\224\202' "$_grid_plain"
# Two distinct months each render as their own data row.
_grid_month_rows=$(printf '%s\n' "$_grid_plain" | grep -cE '^  20[0-9][0-9]-[0-9][0-9] ')
assert_eq "cost (D-grid): two months render as separate rows" "1" \
  "$([ "${_grid_month_rows:-0}" -ge 2 ] && echo 1 || echo 0)"
assert_no_literal_ansi "cost (D-grid): no literal \\033 in output" "$cost_grid_out"

# Narrow terminal still renders the section (fixed-width table, no reflow).
cost_grid_narrow=$(COLUMNS=20 CLAUDII_CACHE_DIR="$_COST_GRID_TMP" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
assert_contains "cost (D-grid): narrow terminal still shows Months" "Months" "$cost_grid_narrow"

unset _COST_GRID_TMP _now_ts cost_grid_out _grid_plain _grid_month_rows cost_grid_narrow
