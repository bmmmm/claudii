# touches: lib/cmd/week.sh lib/window.awk lib/helpers.sh lib/cmd/cost.sh
#
# claudii week — usage inside Anthropic's rolling 7-day rate-limit window.
# The window boundary sits mid-day, which is exactly what the calendar-week
# path cannot express, so every case here pins sub-day behaviour.

_WEEK_TMPDIRS=()
_week_cleanup() { local d; for d in "${_WEEK_TMPDIRS[@]}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap _week_cleanup EXIT

# Build a cache dir with a session cache announcing a known window plus history
# rows around its boundary. reset is +2d from now, so the window opened 5d ago.
_week_fixture() {
  local _d; _d=$(mktemp -d); _WEEK_TMPDIRS+=("$_d")
  local _now="$1" _reset="$2" _pct="$3"
  cat > "$_d/session-aaaaaaaa" <<EOF
model=Opus 5
rate_7d=$_pct
reset_7d=$_reset
session_id=aaaaaaaa-0000-0000-0000-000000000000
EOF
  printf '%s' "$_d"
}

_NOW=$(date +%s)
_RESET=$(( _NOW + 172800 ))          # +2d
_WSTART=$(( _RESET - 604800 ))       # window opened 5d ago

# ── week: rows before the window boundary do not count ───────────────────────
# One session spans the boundary: cumulative 1000 tok before, 3000 after. Only
# the 2000-token increment is inside the window. A day-granular bucket would
# have to take all 3000 or none.
_WK1=$(_week_fixture "$_NOW" "$_RESET" 40)
hist_row "$_WK1/history.tsv" $(( _WSTART - 3600 )) "Opus 5" "1.00" 10 5 "sid-span" 800 200 100
hist_row "$_WK1/history.tsv" $(( _WSTART + 3600 )) "Opus 5" "3.00" 10 5 "sid-span" 2400 600 100
_wk1_out=$(CLAUDII_CACHE_DIR="$_WK1" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: straddling session counts only its in-window increment" \
  "2000" "$(jq -r '.tokens' <<< "$_wk1_out")"
# Compared numerically: jq 1.7 preserves a number's literal spelling, so the
# awk "%.6f" reaches the consumer as 2.000000 — the same value, not the same string.
assert_eq "week: straddling session counts only its in-window cost" \
  "true" "$(jq -r '.cost == 2' <<< "$_wk1_out")"
assert_eq "week: window start is the reset minus seven days" \
  "$_WSTART" "$(jq -r '.window_start' <<< "$_wk1_out")"

# ── week: quota estimate from tokens-so-far over percent-used ────────────────
# 2000 tokens at 40% used → a 5000-token quota, 3000 left.
assert_eq "week: quota estimated from used percentage" \
  "5000" "$(jq -r '.limit_estimate' <<< "$_wk1_out")"
assert_eq "week: tokens left is quota minus used" \
  "3000" "$(jq -r '.tokens_left' <<< "$_wk1_out")"
assert_eq "week: estimate is labelled as such" \
  "estimated" "$(jq -r '.limit_source' <<< "$_wk1_out")"

# ── week: a wide percentage spread upgrades the estimate to measured ─────────
# Same window, rows carrying rate_7d (col 10): 20% at 1000 tok, 70% at 6000 tok.
# Δ5000 tokens over Δ50% → a 10000-token quota, derived without the window start.
_WK2=$(_week_fixture "$_NOW" "$_RESET" 70)
hist_row "$_WK2/history.tsv" $(( _WSTART + 100 )) "Opus 5" "1.00" 10 5 "sid-cal" 800  200  100 20 "$_RESET"
hist_row "$_WK2/history.tsv" $(( _WSTART + 200 )) "Opus 5" "6.00" 10 5 "sid-cal" 4800 1200 100 70 "$_RESET"
_wk2_out=$(CLAUDII_CACHE_DIR="$_WK2" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: wide percentage spread yields a measured quota" \
  "measured" "$(jq -r '.limit_source' <<< "$_wk2_out")"
assert_eq "week: measured quota from delta tokens over delta percent" \
  "10000" "$(jq -r '.limit_estimate' <<< "$_wk2_out")"

# ── week: a narrow spread falls back to the estimate ─────────────────────────
# 1%-grained percentages: a 2-point spread would amplify rounding wildly, so
# the >=10 gate must keep this on the estimated path.
_WK3=$(_week_fixture "$_NOW" "$_RESET" 50)
hist_row "$_WK3/history.tsv" $(( _WSTART + 100 )) "Opus 5" "1.00" 10 5 "sid-n" 800  200  100 49 "$_RESET"
hist_row "$_WK3/history.tsv" $(( _WSTART + 200 )) "Opus 5" "2.00" 10 5 "sid-n" 1600 400  100 50 "$_RESET"
_wk3_out=$(CLAUDII_CACHE_DIR="$_WK3" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: narrow percentage spread stays on the estimate" \
  "estimated" "$(jq -r '.limit_source' <<< "$_wk3_out")"

# ── week: no known window is a normal state, not an error ────────────────────
_WK4=$(mktemp -d); _WEEK_TMPDIRS+=("$_WK4")
_wk4_out=$(CLAUDII_CACHE_DIR="$_WK4" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)
assert_exit_code "week: empty cache exits 0" 0 \
  "CLAUDII_CACHE_DIR='$_WK4' bash '$CLAUDII_HOME/bin/claudii' week"
assert_contains "week: empty cache explains the absence" \
  "No weekly window known yet" "$_wk4_out"
assert_eq "week: empty cache emits empty JSON object" "{}" \
  "$(CLAUDII_CACHE_DIR="$_WK4" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)"

# ── week: pretty output renders the window and stays ANSI-clean ──────────────
_wk1_pretty=$(CLAUDII_CACHE_DIR="$_WK1" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)
assert_contains "week: pretty output names the window" "Weekly limit" "$_wk1_pretty"
assert_contains "week: pretty output shows the used percentage" "40%" "$_wk1_pretty"
assert_no_literal_ansi "week: pretty output has no literal escapes" "$_wk1_pretty"

# ── cost --window: buckets the Window section on the epoch boundary ──────────
# Same straddling fixture: the Window section must show the 2000-token
# increment, not the session's full 3000.
_cost_win=$(CLAUDII_CACHE_DIR="$_WK1" bash "$CLAUDII_HOME/bin/claudii" cost --window 2>&1)
assert_contains "cost --window: labels the section Window" "Window" "$_cost_win"
assert_contains "cost --window: window bucket holds only in-window tokens" \
  "2K tok" "$_cost_win"
assert_not_contains "cost --window: calendar Week section is replaced" \
  "Week  (" "$_cost_win"

# ── cost --window: without a known window it declines rather than mislabels ──
_cost_nowin=$(CLAUDII_CACHE_DIR="$_WK4" bash "$CLAUDII_HOME/bin/claudii" cost --window 2>&1)
assert_contains "cost --window: says so when no window is known" \
  "No weekly rate-limit window known yet" "$_cost_nowin"

# ── cost: the default calendar-week path is untouched ────────────────────────
_cost_plain=$(CLAUDII_CACHE_DIR="$_WK1" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
assert_contains "cost: default still renders the calendar Week section" \
  "Week  (" "$_cost_plain"
assert_not_contains "cost: default renders no Window section" "Window" "$_cost_plain"

# ── week: a comma locale must not reach the numbers or the weekday ───────────
# The failure signature is specific: bash printf follows LC_NUMERIC, so a
# broken cost renders as "$3206,00" (value truncated at the radix, not merely
# re-punctuated), and a date built with LC_TIME=C — which a set LC_ALL
# overrides — renders "Mi." instead of "Wed". Both were real; this pins them.
# grep on a here-string, not `locale -a | grep -q`: under run.sh's pipefail,
# grep -q exits early, locale takes SIGPIPE, and the pipeline returns 141 — the
# guard then skips itself silently and the whole block reads as a pass (see the
# same note at tests/run.sh:44).
if grep -qi '^de_DE\.UTF-8$' <<< "$(locale -a 2>/dev/null)"; then
  _wk_de=$(LC_ALL=de_DE.UTF-8 CLAUDII_CACHE_DIR="$_WK1" \
    bash "$CLAUDII_HOME/bin/claudii" week 2>&1)
  assert_not_contains "week: comma locale leaves no comma decimal in cost" \
    '$2,' "$_wk_de"
  assert_contains "week: comma locale keeps the cost value intact" \
    '$2.00' "$_wk_de"
  assert_no_literal_ansi "week: comma locale output stays clean" "$_wk_de"
fi
