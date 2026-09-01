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

# ── week: an early Anthropic reset shortens the window ───────────────────────
# Anthropic sometimes ends a weekly window early for technical reasons. The
# reset it had announced then never fires, so "reset minus 7d" would place the
# start before the window actually opened. The real boundary is where the
# announced reset value changes — recorded in column 11.
#   window A: announced reset RA, seen at T-8d..T-6d  (>=3 sightings)
#   window B: announced reset RB, first seen T-2d     → a 3-day window
_WK5=$(mktemp -d); _WEEK_TMPDIRS+=("$_WK5")
_RA=$(( _NOW - 432000 ))              # T-5d, announced but overtaken
_RB=$(( _NOW + 86400 ))               # T+1d, the reset now in force
_SWITCH=$(( _NOW - 172800 ))          # T-2d, where the value changes
cat > "$_WK5/session-bbbbbbbb" <<EOF
model=Opus 5
rate_7d=50
reset_7d=$_RB
session_id=bbbbbbbb-0000-0000-0000-000000000000
EOF
# Window A sightings (before the switch) — cumulative cost/tokens climb.
hist_row "$_WK5/history.tsv" $(( _NOW - 691200 )) "Opus 5" "1.00" 10 5 "sid-a" 400  100  100 10 "$_RA"
hist_row "$_WK5/history.tsv" $(( _NOW - 604800 )) "Opus 5" "2.00" 10 5 "sid-a" 800  200  100 20 "$_RA"
hist_row "$_WK5/history.tsv" $(( _NOW - 518400 )) "Opus 5" "3.00" 10 5 "sid-a" 1200 300  100 30 "$_RA"
# Window B sightings (after the switch).
hist_row "$_WK5/history.tsv" $(( _SWITCH + 60 ))   "Opus 5" "4.00" 10 5 "sid-b" 1600 400 100 40 "$_RB"
hist_row "$_WK5/history.tsv" $(( _SWITCH + 3600 )) "Opus 5" "5.00" 10 5 "sid-b" 2000 500 100 45 "$_RB"
hist_row "$_WK5/history.tsv" $(( _SWITCH + 7200 )) "Opus 5" "6.00" 10 5 "sid-b" 2400 600 100 50 "$_RB"
_wk5_json=$(CLAUDII_CACHE_DIR="$_WK5" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

# Start is the observed switch (floored to the hour), NOT reset-minus-7d.
_WK5_EXPECT=$(( (_SWITCH + 60) - (_SWITCH + 60) % 3600 ))
assert_eq "week: early reset moves the start to the observed switch" \
  "$_WK5_EXPECT" "$(jq -r '.window_start' <<< "$_wk5_json")"
assert_not_contains "week: early reset does not fall back to the 7-day grid" \
  "$(( _RB - 604800 ))" "$(jq -r '.window_start' <<< "$_wk5_json")"
_wk5_out=$(CLAUDII_CACHE_DIR="$_WK5" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)
assert_contains "week: a shortened window says so" "window is short" "$_wk5_out"

# ── week: a single observed window must NOT move the start ───────────────────
# _WK2 has sightings of exactly one reset value. Its first sighting marks when
# recording began, not when the window opened — trusting it would collapse the
# window to minutes. Must stay on the 7-day grid.
assert_eq "week: one observed window keeps the 7-day grid start" \
  "$(( _RESET - 604800 ))" "$(jq -r '.window_start' <<< "$_wk2_out")"
assert_not_contains "week: single-sighting window is not flagged short" \
  "window is short" "$(CLAUDII_CACHE_DIR="$_WK2" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)"

# ── week --history: per-window bars ──────────────────────────────────────────
_wk_hist=$(CLAUDII_CACHE_DIR="$_WK1" bash "$CLAUDII_HOME/bin/claudii" week --history 4 2>&1)
assert_contains "week --history: names the view" "last 4 windows" "$_wk_hist"
assert_contains "week --history: marks the running window" "current" "$_wk_hist"
assert_contains "week --history: flags reconstructed boundaries" "reconstructed" "$_wk_hist"
assert_no_literal_ansi "week --history: no literal escapes" "$_wk_hist"

# ── week: the quota band, from the spread of the window's own support points ─
# Three support points whose pairwise slopes disagree: (10%,500), (30%,1500),
# (50%,3500) imply quotas of 5000 / 10000 / 7500 tokens. The Theil-Sen median
# 7500 is the estimate, the extremes are the band. A single confident number
# over data spreading 2x would claim a precision the 1%-grained percentages
# cannot carry — and the band width IS the answer to "does Anthropic count
# proportionally to raw tokens?", with no separate probe.
_WK6=$(_week_fixture "$_NOW" "$_RESET" 50)
hist_row "$_WK6/history.tsv" $(( _WSTART + 100 )) "Opus 5" "1.00" 10 5 "sid-band"  400 100 100 10 "$_RESET"
hist_row "$_WK6/history.tsv" $(( _WSTART + 200 )) "Opus 5" "3.00" 10 5 "sid-band" 1200 300 100 30 "$_RESET"
hist_row "$_WK6/history.tsv" $(( _WSTART + 300 )) "Opus 5" "7.00" 10 5 "sid-band" 2800 700 100 50 "$_RESET"
_wk6_out=$(CLAUDII_CACHE_DIR="$_WK6" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: band estimate is the median of the pairwise slopes" \
  "7500" "$(jq -r '.limit_estimate' <<< "$_wk6_out")"
assert_eq "week: band low is the smallest implied quota" \
  "5000" "$(jq -r '.limit_low' <<< "$_wk6_out")"
assert_eq "week: band high is the largest implied quota" \
  "10000" "$(jq -r '.limit_high' <<< "$_wk6_out")"
assert_eq "week: band brackets the estimate" "true" \
  "$(jq -r '.limit_low <= .limit_estimate and .limit_estimate <= .limit_high' <<< "$_wk6_out")"
# 3500 used: the band renders as a range of what is LEFT (1500..6500 -> 2K..7K).
_wk6_pretty=$(CLAUDII_CACHE_DIR="$_WK6" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)
assert_contains "week: a wide band renders as a range, not a point" \
  "2K–7K left" "$_wk6_pretty"
assert_no_literal_ansi "week: band output has no literal escapes" "$_wk6_pretty"

# ── week: a narrow band collapses back to the point estimate ─────────────────
# (10%,1000), (50%,5000), (90%,9200) imply 10000 / 10500 / 10250 — a spread of
# under 10% of the median. Printing "10.0K–10.5K" there would suggest an
# uncertainty the data does not actually show, so the range is suppressed.
_WK7=$(_week_fixture "$_NOW" "$_RESET" 90)
hist_row "$_WK7/history.tsv" $(( _WSTART + 100 )) "Opus 5" "1.00" 10 5 "sid-narrow"  800  200 100 10 "$_RESET"
hist_row "$_WK7/history.tsv" $(( _WSTART + 200 )) "Opus 5" "5.00" 10 5 "sid-narrow" 4000 1000 100 50 "$_RESET"
hist_row "$_WK7/history.tsv" $(( _WSTART + 300 )) "Opus 5" "9.20" 10 5 "sid-narrow" 7360 1840 100 90 "$_RESET"
_wk7_out=$(CLAUDII_CACHE_DIR="$_WK7" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: a narrow band still yields the median estimate" \
  "10250" "$(jq -r '.limit_estimate' <<< "$_wk7_out")"
assert_eq "week: a narrow band reports no low bound" \
  "null" "$(jq -r '.limit_low' <<< "$_wk7_out")"
assert_eq "week: a narrow band reports no high bound" \
  "null" "$(jq -r '.limit_high' <<< "$_wk7_out")"
assert_not_contains "week: a narrow band renders no range" \
  "–" "$(CLAUDII_CACHE_DIR="$_WK7" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)"

# ── week: too few support points keeps the pre-band behaviour ────────────────
# _WK3 has two sightings one point apart: no pair clears the >=10 gate, so
# there is nothing to take a median over and the estimate stays the old
# tokens-over-percent figure, with no band.
assert_eq "week: no usable pair reports no band low" \
  "null" "$(jq -r '.limit_low' <<< "$_wk3_out")"
assert_eq "week: no usable pair reports no band high" \
  "null" "$(jq -r '.limit_high' <<< "$_wk3_out")"


# ── week: sanity guards on the observed window start ─────────────────────────
# The observed boundary is only as good as column 11. A corrupt value there
# would silently rebase every number in the block, so an implausible candidate
# is rejected and the start falls back to the reset-minus-7d grid.

# Guard 1: a start in the future. Column 11 announces the current reset on rows
# stamped AFTER now — the switch point would land ahead of the clock.
_WK8=$(mktemp -d); _WEEK_TMPDIRS+=("$_WK8")
_RA8=$(( _NOW - 432000 ))              # older window, gives the >=1 prior sighting
_RB8=$(( _NOW + 172800 ))              # the reset now in force
cat > "$_WK8/session-cccccccc" <<SESS
model=Opus 5
rate_7d=50
reset_7d=$_RB8
session_id=cccccccc-0000-0000-0000-000000000000
SESS
hist_row "$_WK8/history.tsv" $(( _NOW - 691200 )) "Opus 5" "1.00" 10 5 "sid-a8" 400  100 100 10 "$_RA8"
hist_row "$_WK8/history.tsv" $(( _NOW - 604800 )) "Opus 5" "2.00" 10 5 "sid-a8" 800  200 100 20 "$_RA8"
hist_row "$_WK8/history.tsv" $(( _NOW - 518400 )) "Opus 5" "3.00" 10 5 "sid-a8" 1200 300 100 30 "$_RA8"
hist_row "$_WK8/history.tsv" $(( _NOW + 7200 ))   "Opus 5" "4.00" 10 5 "sid-b8" 1600 400 100 40 "$_RB8"
hist_row "$_WK8/history.tsv" $(( _NOW + 10800 ))  "Opus 5" "5.00" 10 5 "sid-b8" 2000 500 100 45 "$_RB8"
hist_row "$_WK8/history.tsv" $(( _NOW + 14400 ))  "Opus 5" "6.00" 10 5 "sid-b8" 2400 600 100 50 "$_RB8"
_wk8_json=$(CLAUDII_CACHE_DIR="$_WK8" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: a future window start is rejected for the 7-day grid" \
  "$(( _RB8 - 604800 ))" "$(jq -r '.window_start' <<< "$_wk8_json")"
assert_not_contains "week: a rejected future start is not flagged short" \
  "window is short" "$(CLAUDII_CACHE_DIR="$_WK8" bash "$CLAUDII_HOME/bin/claudii" week 2>&1)"

# Guard 2: a reset that has already passed. Claude Code drops seven_day once the
# reset fires, so a session cache still carrying one is stale — refining the
# start off stale data is worse than the grid it would replace.
_WK9=$(mktemp -d); _WEEK_TMPDIRS+=("$_WK9")
_RA9=$(( _NOW - 700000 ))
_RB9=$(( _NOW - 3600 ))                # expired an hour ago
cat > "$_WK9/session-dddddddd" <<SESS
model=Opus 5
rate_7d=50
reset_7d=$_RB9
session_id=dddddddd-0000-0000-0000-000000000000
SESS
hist_row "$_WK9/history.tsv" $(( _NOW - 800000 )) "Opus 5" "1.00" 10 5 "sid-a9" 400  100 100 10 "$_RA9"
hist_row "$_WK9/history.tsv" $(( _NOW - 790000 )) "Opus 5" "2.00" 10 5 "sid-a9" 800  200 100 20 "$_RA9"
hist_row "$_WK9/history.tsv" $(( _NOW - 780000 )) "Opus 5" "3.00" 10 5 "sid-a9" 1200 300 100 30 "$_RA9"
hist_row "$_WK9/history.tsv" $(( _NOW - 300000 )) "Opus 5" "4.00" 10 5 "sid-b9" 1600 400 100 40 "$_RB9"
hist_row "$_WK9/history.tsv" $(( _NOW - 290000 )) "Opus 5" "5.00" 10 5 "sid-b9" 2000 500 100 45 "$_RB9"
hist_row "$_WK9/history.tsv" $(( _NOW - 280000 )) "Opus 5" "6.00" 10 5 "sid-b9" 2400 600 100 50 "$_RB9"
_wk9_json=$(CLAUDII_CACHE_DIR="$_WK9" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: an expired reset keeps the 7-day grid start" \
  "$(( _RB9 - 604800 ))" "$(jq -r '.window_start' <<< "$_wk9_json")"

# ── week: the median, not the mean, carries the outlier ──────────────────────
# Four support points (10%,1000) (30%,3000) (50%,5000) (70%,13000): three pairs
# imply 10000, the ones touching the last point imply 20000/25000/40000. The
# median is 15000, the mean 19166 — this fixture is deliberately skewed so the
# two disagree, which is the entire reason Theil-Sen takes the median: one
# runaway pair must not drag the estimate with it.
_WK10=$(_week_fixture "$_NOW" "$_RESET" 70)
hist_row "$_WK10/history.tsv" $(( _WSTART + 100 )) "Opus 5" "1.00" 10 5 "sid-skew"   800  200 100 10 "$_RESET"
hist_row "$_WK10/history.tsv" $(( _WSTART + 200 )) "Opus 5" "3.00" 10 5 "sid-skew"  2400  600 100 30 "$_RESET"
hist_row "$_WK10/history.tsv" $(( _WSTART + 300 )) "Opus 5" "5.00" 10 5 "sid-skew"  4000 1000 100 50 "$_RESET"
hist_row "$_WK10/history.tsv" $(( _WSTART + 400 )) "Opus 5" "13.00" 10 5 "sid-skew" 10400 2600 100 70 "$_RESET"
_wk10_out=$(CLAUDII_CACHE_DIR="$_WK10" bash "$CLAUDII_HOME/bin/claudii" week --json 2>&1)

assert_eq "week: skewed slopes yield the median, not the mean" \
  "15000" "$(jq -r '.limit_estimate' <<< "$_wk10_out")"
assert_eq "week: skewed slopes keep the outlier only in the band high" \
  "40000" "$(jq -r '.limit_high' <<< "$_wk10_out")"
assert_eq "week: skewed slopes keep the tight pairs as the band low" \
  "10000" "$(jq -r '.limit_low' <<< "$_wk10_out")"
