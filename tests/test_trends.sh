# touches: lib/cmd/cost.sh lib/cmd/display.sh

# test_trends.sh — claudii trends token-tracking tests (v0.9.0+)
# Verifies that history.tsv with token columns (input_tok, output_tok)

_TRENDS_TMPDIRS=()
trap 'rm -rf "${_TRENDS_TMPDIRS[@]}" 2>/dev/null' EXIT
# is handled correctly: trends output works and old entries without
# tokens are processed gracefully.

# ── trends: history.tsv with token columns (current 9-col raw format) ────────
# Raw format the CLI augments (sid is column 6 — matches what cc-statusline writes):
#   timestamp  model  cost  ctx_pct  rate_5h  session_id  in_tok  out_tok  api_ms
_TRENDS_TOK_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_TOK_TMP")
_now_ts=$(date +%s)

hist_row "$_TRENDS_TOK_TMP/history.tsv" "$_now_ts"            "claude-opus-4-5"   "0.50" "45" "30" "abc12345" "15000" "5000" "1200"
hist_row "$_TRENDS_TOK_TMP/history.tsv" "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "30" "20" "def67890" "8000"  "2000" "800"

trends_tok_out=$(CLAUDII_CACHE_DIR="$_TRENDS_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
trends_tok_err=$(CLAUDII_CACHE_DIR="$_TRENDS_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 >/dev/null)

assert_eq "trends (tokens): no errors on stderr" "" "$trends_tok_err"
assert_eq "trends (tokens): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_TRENDS_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends >/dev/null 2>&1; echo $?)"
assert_eq "trends (tokens): produces output" "0" "$([ -z "$trends_tok_out" ] && echo 1 || echo 0)"
assert_no_literal_ansi "trends (tokens): no literal \\033 in output" "$trends_tok_out"
assert_contains "trends (tokens): shows tok" "tok" "$trends_tok_out"
assert_contains "trends (tokens): Daily tokens header" "Daily tokens" "$trends_tok_out"
assert_contains "trends (tokens): shows Today label" "Today" "$trends_tok_out"
assert_contains "trends (tokens): 7d total line" "7d total" "$trends_tok_out"
assert_contains "trends (tokens): sessions column" "sessions" "$trends_tok_out"

# Today should appear before any other weekday name in the output (token-primary
# layout indents daily rows with 2 spaces, was 4)
_tok_today_line=$(echo "$trends_tok_out" | grep -n "Today" | head -1 | cut -d: -f1)
_tok_first_wdline=$(echo "$trends_tok_out" | grep -nE "^  (Mon|Tue|Wed|Thu|Fri|Sat|Sun) " | head -1 | cut -d: -f1)
if [[ -n "$_tok_today_line" && -n "$_tok_first_wdline" ]]; then
  assert_eq "trends (tokens): Today appears before other weekday lines" "0" \
    "$([ "$_tok_today_line" -lt "$_tok_first_wdline" ] && echo 0 || echo 1)"
fi
unset _tok_today_line _tok_first_wdline

unset _TRENDS_TOK_TMP _now_ts trends_tok_out trends_tok_err

# ── trends --json: new format → valid JSON with expected fields ───────────────
_TRENDS_JSON_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_JSON_TMP")
_now_ts=$(date +%s)

hist_row "$_TRENDS_JSON_TMP/history.tsv" "$_now_ts"            "claude-opus-4-5"   "0.50" "45" "30" "abc12345" "15000" "5000" "1200"
hist_row "$_TRENDS_JSON_TMP/history.tsv" "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.25" "30" "20" "def67890" "8000"  "2000" "800"

trends_json=$(CLAUDII_CACHE_DIR="$_TRENDS_JSON_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)

assert_eq "trends --json (tokens): valid JSON" "0" \
  "$(echo "$trends_json" | jq . >/dev/null 2>&1; echo $?)"
assert_contains "trends --json (tokens): has this_week field" '"this_week"' "$trends_json"
assert_contains "trends --json (tokens): has this_week_total field" '"this_week_total"' "$trends_json"
assert_contains "trends --json (tokens): has last_week field" '"last_week"' "$trends_json"
assert_contains "trends --json (tokens): has model_split_30d field" '"model_split_30d"' "$trends_json"

# Value assertion — locks the 9-col layout. Two sessions today: in 15000+8000=23000,
# out 5000+2000=10000 → this_week_tokens 30000. A column shift (e.g. sid read from a
# token field, dropping out_tok) mis-sums; the old stale 7-col fixture yielded 7000.
_tw_tokens=$(echo "$trends_json" | jq -r '.this_week_tokens // 0')
assert_eq "trends --json (tokens): this_week_tokens == 30000 (column layout intact)" "30000" "$_tw_tokens"

unset _TRENDS_JSON_TMP _now_ts trends_json _tw_tokens

# ── trends: old history entries WITHOUT token columns → graceful fallback ──────
# Old format: timestamp model cost ctx_pct rate_5h session_id  (6 cols)
# The code should handle this without crashing.
_TRENDS_OLD_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_OLD_TMP")
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

unset _TRENDS_OLD_TMP _now_ts trends_old_out trends_old_err

# ── trends: old format → no "tok" bleed in output ─────────────────────────────
# Old entries should not produce "tok" in output — no phantom token display.
_TRENDS_NOTOK_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_NOTOK_TMP")
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.50" "45" "30" "sid-notok" \
  > "$_TRENDS_NOTOK_TMP/history.tsv"

trends_notok_out=$(CLAUDII_CACHE_DIR="$_TRENDS_NOTOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
# Token-primary layout always renders the token column; old-format (no token)
# data shows zeros, not a phantom value. Just verify it renders without crashing.
assert_contains "trends (old format): renders token layout (zeros, no crash)" "Daily tokens" "$trends_notok_out"

unset _TRENDS_NOTOK_TMP _now_ts trends_notok_out

# ── trends --json: old format → valid JSON, no crash ─────────────────────────
_TRENDS_OLD_JSON_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_OLD_JSON_TMP")
_now_ts=$(date +%s)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_now_ts" "claude-sonnet-4-5" "0.50" "45" "30" "sid-old" \
  > "$_TRENDS_OLD_JSON_TMP/history.tsv"

trends_old_json=$(CLAUDII_CACHE_DIR="$_TRENDS_OLD_JSON_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)
assert_eq "trends --json (old format): valid JSON" "0" \
  "$(echo "$trends_old_json" | jq . >/dev/null 2>&1; echo $?)"

unset _TRENDS_OLD_JSON_TMP _now_ts trends_old_json

# ── trends: empty history.tsv → actionable message, no crash ─────────────────
_TRENDS_EMPTY_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_EMPTY_TMP")
touch "$_TRENDS_EMPTY_TMP/history.tsv"

trends_empty_out=$(CLAUDII_CACHE_DIR="$_TRENDS_EMPTY_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 || true)
assert_matches "trends (empty history): actionable message" "No history|CC-Statusline" "$trends_empty_out"

unset _TRENDS_EMPTY_TMP trends_empty_out

# ── trends: no history.tsv → actionable message, no crash ────────────────────
_TRENDS_NOHIST_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_NOHIST_TMP")

trends_nohist_out=$(CLAUDII_CACHE_DIR="$_TRENDS_NOHIST_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 || true)
assert_matches "trends (no history): actionable message" "No history|CC-Statusline" "$trends_nohist_out"

unset _TRENDS_NOHIST_TMP trends_nohist_out

# ── trends: small cost decrease (< 50% drop) → NOT treated as reset ──────────
# A tiny floating-point decrease (e.g. $10.003 → $10.002) must produce zero
# delta, not attribute the post-decrease value as a new session cost.
# history.tsv format: timestamp model cost ctx_pct rate_5h session_id in_tok out_tok
_TRENDS_NOISE_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_NOISE_TMP")
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
  "$(LC_ALL=C awk "BEGIN { print (\"$_noise_day_cost\" + 0 > 15) ? 1 : 0 }")"

unset _TRENDS_NOISE_TMP _now_ts trends_noise_json _noise_day _noise_day_cost

# ── trends: explicitly empty cols 6+7 → no crash, no "tok" ───────────────────
# Entries from the planned new format with explicit empty token fields.
_TRENDS_EMPTY_TOK_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_EMPTY_TOK_TMP")
_now_ts=$(date +%s)

printf '%s\tclaude-opus-4-5\t0.50\tabc12345\t0.50\t\t\n' "$_now_ts" \
  > "$_TRENDS_EMPTY_TOK_TMP/history.tsv"
printf '%s\tclaude-sonnet-4-5\t0.25\tdef67890\t0.25\t\t\n' "$(( _now_ts - 60 ))" \
  >> "$_TRENDS_EMPTY_TOK_TMP/history.tsv"

trends_empty_tok_out=$(CLAUDII_CACHE_DIR="$_TRENDS_EMPTY_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
trends_empty_tok_err=$(CLAUDII_CACHE_DIR="$_TRENDS_EMPTY_TOK_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 >/dev/null)

assert_eq "trends (empty tok cols): no errors on stderr" "" "$trends_empty_tok_err"
assert_contains "trends (empty tok cols): renders without crash" "Daily tokens" "$trends_empty_tok_out"

unset _TRENDS_EMPTY_TOK_TMP _now_ts trends_empty_tok_out trends_empty_tok_err

# ── trends: new features — Last 7 days, reverse order, Total with sessions, Median, Trend ──
_TRENDS_NEW_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_NEW_TMP")
_now_ts=$(date +%s)
# Two sessions today (Opus + Sonnet) plus one ~35 days ago, so history spans
# >30 days and the Trend line is shown (it is gated on >=30 days of history).
hist_row "$_TRENDS_NEW_TMP/history.tsv" "$_now_ts"                    "claude-opus-4-5"   "5.00" "45" "30" "new-sid1" "50000" "10000" "2000"
hist_row "$_TRENDS_NEW_TMP/history.tsv" "$(( _now_ts - 300 ))"        "claude-sonnet-4-5" "2.00" "30" "20" "new-sid2" "20000" "5000"  "1000"
hist_row "$_TRENDS_NEW_TMP/history.tsv" "$(( _now_ts - 35 * 86400 ))" "claude-opus-4-5"   "3.00" "45" "30" "new-sid3" "30000" "8000"  "1500"

trends_new_out=$(CLAUDII_CACHE_DIR="$_TRENDS_NEW_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)

assert_eq    "trends (new features): exit 0" "0" \
  "$(CLAUDII_CACHE_DIR="$_TRENDS_NEW_TMP" bash "$CLAUDII_HOME/bin/claudii" trends >/dev/null 2>&1; echo $?)"
assert_contains "trends (new features): Daily tokens header"         "Daily tokens" "$trends_new_out"
assert_contains "trends (new features): shows Today label"           "Today"        "$trends_new_out"
assert_contains "trends (new features): 7d total line"               "7d total"     "$trends_new_out"
assert_contains "trends (new features): Model split header"          "Model split"  "$trends_new_out"
assert_contains "trends (new features): Busiest line present"        "Busiest"      "$trends_new_out"
assert_contains "trends (new features): Trend line present"          "Trend"        "$trends_new_out"
assert_not_contains "trends (new features): no This week header"     "This week"    "$trends_new_out"
assert_no_literal_ansi "trends (new features): no literal ANSI in output" "$trends_new_out"

# Trend line must contain an arrow (↑ ↓ or →)
assert_matches "trends (new features): Trend line has arrow" \
  $'\342\206\221|\342\206\223|\342\206\222' "$trends_new_out"

# Today must be the first day label in the output
_new_today_line=$(echo "$trends_new_out" | grep -n "Today" | head -1 | cut -d: -f1)
_new_first_wdline=$(echo "$trends_new_out" | grep -nE "^  (Mon|Tue|Wed|Thu|Fri|Sat|Sun) " | head -1 | cut -d: -f1)
if [[ -n "$_new_today_line" && -n "$_new_first_wdline" ]]; then
  assert_eq "trends (new features): Today appears before other weekday lines" "0" \
    "$([ "$_new_today_line" -lt "$_new_first_wdline" ] && echo 0 || echo 1)"
fi
unset _new_today_line _new_first_wdline

unset _TRENDS_NEW_TMP _now_ts trends_new_out

# ── trends: Trend line gated on >=30 days of history (sparse → hidden) ────────
# With only a few days of data the fixed-/30 denominator would report a wildly
# misleading swing, so the Trend line is suppressed until history spans 30 days.
_TRENDS_SPARSE_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_SPARSE_TMP")
_now_ts=$(date +%s)
# Only today + 2 days ago → earliest cost day is well under 30 days back.
hist_row "$_TRENDS_SPARSE_TMP/history.tsv" "$_now_ts"                   "claude-opus-4-5"   "5.00" "45" "30" "sp-sid1" "50000" "10000" "2000"
hist_row "$_TRENDS_SPARSE_TMP/history.tsv" "$(( _now_ts - 2 * 86400 ))" "claude-sonnet-4-5" "2.00" "30" "20" "sp-sid2" "20000" "5000"  "1000"
trends_sparse_out=$(CLAUDII_CACHE_DIR="$_TRENDS_SPARSE_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
assert_not_contains "trends (sparse history): Trend line hidden (<30 days)" "Trend" "$trends_sparse_out"
# Daily token layout still renders (only the 30d Trend line is gated)
assert_contains "trends (sparse history): Daily tokens still shown" "Daily tokens" "$trends_sparse_out"
unset _TRENDS_SPARSE_TMP _now_ts trends_sparse_out

# ── trends: CRLF history (cross-platform sync) + short rows → no crash ────────
# Regression: awk used to leak \r into model names and choke on malformed rows.
_TRENDS_CRLF_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_CRLF_TMP")
_now_ts=$(date +%s)
{
  # CRLF-terminated row — common with Windows/Dropbox sync
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\r\n' \
    "$_now_ts" "claude-opus-4-5" "0.30" "45" "30" "abc12345" "1000" "500" "300"
  # Short row (< 6 fields) — must be skipped
  printf '%s\t%s\n' "$_now_ts" "claude-sonnet-4-5"
  # Normal row after short one — must still be processed
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(( _now_ts - 60 ))" "claude-sonnet-4-5" "0.10" "30" "20" "def67890" "800" "200" "150"
} > "$_TRENDS_CRLF_TMP/history.tsv"

trends_crlf_out=$(CLAUDII_CACHE_DIR="$_TRENDS_CRLF_TMP" bash "$CLAUDII_HOME/bin/claudii" trends 2>&1)
trends_crlf_exit=$(CLAUDII_CACHE_DIR="$_TRENDS_CRLF_TMP" bash "$CLAUDII_HOME/bin/claudii" trends >/dev/null 2>&1; echo $?)
assert_eq "trends (CRLF + short row): exit 0" "0" "$trends_crlf_exit"
# No literal CR leaking into output (would appear as ^M if present)
assert_eq "trends (CRLF): no CR in output" "0" "$(printf '%s' "$trends_crlf_out" | grep -c $'\r' || true)"

unset _TRENDS_CRLF_TMP _now_ts trends_crlf_out trends_crlf_exit

# ── trends: model word-anchoring — substring-only must not match ─────────────
# Regression: /[Oo]pus/ substring match would classify "myopusx" as Opus.
# With the word-anchored pattern (^|[^a-z])opus([^a-z]|$), it must NOT match.
# Real model names with hyphen boundaries ("claude-opus-4-5") still match.
_TRENDS_WA_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_WA_TMP")
_now_ts=$(date +%s)
hist_row "$_TRENDS_WA_TMP/history.tsv" "$_now_ts"            "myopusx"         "9.00" "45" "30" "wa000001" "1000" "500" "200"
hist_row "$_TRENDS_WA_TMP/history.tsv" "$(( _now_ts - 60 ))" "claude-opus-4-5" "0.10" "30" "20" "wa000002" "100"  "50"  "100"
trends_wa_json=$(CLAUDII_CACHE_DIR="$_TRENDS_WA_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)
# If "myopusx" were misclassified as Opus, Opus would dominate (9.00 vs 0.10).
# With word-anchoring, only the real Opus row is counted → Opus has 1 session.
_opus_sessions=$(printf '%s' "$trends_wa_json" | jq -r '.model_split_30d.Opus.sessions // 0' 2>/dev/null)
assert_eq "trends: 'myopusx' substring not classified as Opus" "1" "${_opus_sessions:-0}"

unset _TRENDS_WA_TMP _now_ts trends_wa_json _opus_sessions

# ── trends: 7-day window weekday names match `date` (no off-by-one) ───────────
# Regression for the single-awk boundary consolidation (epoch_to_date + a weekday
# table replacing ~21 `date` forks). Each this_week entry's day name must equal
# what `date` produces for that date — guards the (ld+4)%7 weekday formula.
_TRENDS_WD_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_WD_TMP")
_now_ts=$(date +%s)
hist_row "$_TRENDS_WD_TMP/history.tsv" "$_now_ts" "claude-opus-4-8" "1.00" "50" "30" "wd-sid" "5000" "1000" "0"
trends_wd_json=$(CLAUDII_CACHE_DIR="$_TRENDS_WD_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)
_wd_mismatch=0
while IFS=' ' read -r _wd_date _wd_name; do
  [[ -z "$_wd_date" ]] && continue
  # date '+%a' is localized — force C so the reference matches the code's
  # hardcoded English weekday table (CLI output is English by design).
  if LC_ALL=C date -j -f '%Y-%m-%d' "$_wd_date" '+%a' >/dev/null 2>&1; then
    _wd_ref=$(LC_ALL=C date -j -f '%Y-%m-%d' "$_wd_date" '+%a')
  else
    _wd_ref=$(LC_ALL=C date -d "$_wd_date" '+%a' 2>/dev/null)
  fi
  [[ "$_wd_name" != "$_wd_ref" ]] && _wd_mismatch=1
done < <(echo "$trends_wd_json" | jq -r '.this_week[] | "\(.date) \(.day)"')
assert_eq "trends: 7-day window weekday names match date (no off-by-one)" "0" "$_wd_mismatch"
unset _TRENDS_WD_TMP _now_ts trends_wd_json _wd_mismatch _wd_date _wd_name _wd_ref

# ── trends --json: valid under a comma-decimal locale ─────────────────────────
# Regression (locale class): trends.awk prints costs via printf %.2f, which
# honors LC_NUMERIC — a de_DE (comma) locale emitted "cost":0,00 and broke jq.
# The json/tsv awk now runs under LC_ALL=C. Guarded on the locale being present
# (CI runners often lack it) so it skips rather than passing vacuously.
_have_de_locale=$(locale -a 2>/dev/null || true)
if [[ "$_have_de_locale" == *de_DE.UTF-8* || "$_have_de_locale" == *de_DE.utf8* ]]; then
  _TRENDS_LOC_TMP="$(mktemp -d)"; _TRENDS_TMPDIRS+=("$_TRENDS_LOC_TMP")
  _now_ts=$(date +%s)
  hist_row "$_TRENDS_LOC_TMP/history.tsv" "$_now_ts"            "claude-opus-4-8"   "12.3456" "50" "30" "tl1" "1500000" "300000" "0"
  hist_row "$_TRENDS_LOC_TMP/history.tsv" "$(( _now_ts - 60 ))" "claude-sonnet-4-6" "5.6789"  "40" "20" "tl2" "800000"  "160000" "0"
  _trends_loc_json=$(LC_ALL=de_DE.UTF-8 CLAUDII_CACHE_DIR="$_TRENDS_LOC_TMP" bash "$CLAUDII_HOME/bin/claudii" trends --json 2>&1)
  assert_eq "trends --json: valid under de_DE comma locale" "0" \
    "$(echo "$_trends_loc_json" | jq . >/dev/null 2>&1; echo $?)"
  unset _TRENDS_LOC_TMP _now_ts _trends_loc_json
fi
unset _have_de_locale
