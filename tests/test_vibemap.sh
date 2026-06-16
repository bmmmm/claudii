# touches: lib/vibemap.sh lib/cmd/vibemap.sh lib/vibemap-grid.awk lib/vibemap-strip.awk bin/claudii
# test_vibemap.sh — opt-in activity heatmap: append, aggregate, render.
# Covers the lifecycle (status/clear), the awk aggregators (grid + strip),
# and the schema invariants (7 fields per line, weekday/hour ranges).

_vm_home=$(mktemp -d)
_vm_path="$_vm_home/.cache/claudii/vibemap.tsv"
mkdir -p "${_vm_path%/*}"

_vm_run() {
  HOME="$_vm_home" XDG_CACHE_HOME="$_vm_home/.cache" \
    XDG_CONFIG_HOME="$_vm_home/.config" \
    bash "$CLAUDII_HOME/bin/claudii" vibemap "$@"
}

# ── _vibemap_append: schema + format ──────────────────────────────────────────

# Source the appender directly so we can call it without a real cc-statusline run
HOME="$_vm_home" CLAUDII_CACHE_DIR="$_vm_home/.cache/claudii" \
  source "$CLAUDII_HOME/lib/vibemap.sh"

_vibemap_append "$_vm_path" "Opus 4.7 (1M context)" "abcdef1234567890" "12340"
_vibemap_append "$_vm_path" "Sonnet 4.6"            "fedcba0987654321" "850"
_vibemap_append "$_vm_path" ""                      "noop"             "0"   # tolerates empty model

assert_file_exists "vibemap append: file created" "$_vm_path"

_count=$(wc -l < "$_vm_path" | tr -d ' ')
assert_eq "vibemap append: 3 lines written" "3" "$_count"

# Field count per line — must be exactly 7 (TSV)
_bad_lines=$(awk -F'\t' 'NF != 7 { print NR }' "$_vm_path")
assert_eq "vibemap append: every line has exactly 7 fields" "" "$_bad_lines"

# Model-shortening: first word only
_model_field=$(awk -F'\t' 'NR==1 { print $5 }' "$_vm_path")
assert_eq "vibemap append: model truncated to first word" "Opus" "$_model_field"

# sid8 truncation
_sid_field=$(awk -F'\t' 'NR==1 { print $6 }' "$_vm_path")
assert_eq "vibemap append: sid truncated to 8 chars" "abcdef12" "$_sid_field"

# Weekday + hour ranges
_oob=$(awk -F'\t' '$2 < 0 || $2 > 6 || $3 < 0 || $3 > 23 || $4 < 0 || $4 > 59' "$_vm_path")
assert_eq "vibemap append: weekday/hour/minute in valid ranges" "" "$_oob"

# ── grid awk: aggregation correctness ─────────────────────────────────────────

# Hand-craft a deterministic input: 5 entries on Mon (wd=1) hour 9-11 (bin=3),
# 2 entries on Tue (wd=2) hour 0 (bin=0), 1 entry on Sun (wd=0) hour 23 (bin=7)
cat > "$_vm_home/grid-input.tsv" <<EOF
1700000000	1	9	0	Opus	aaaaaaaa	0
1700000001	1	9	30	Opus	aaaaaaaa	1000
1700000002	1	10	0	Opus	aaaaaaaa	2000
1700000003	1	11	0	Opus	aaaaaaaa	3000
1700000004	1	11	45	Opus	aaaaaaaa	4000
1700000005	2	0	5	Sonnet	bbbbbbbb	0
1700000006	2	0	30	Sonnet	bbbbbbbb	5000
1700000007	0	23	30	Opus	cccccccc	0
EOF

_grid_out=$(awk -f "$CLAUDII_HOME/lib/vibemap-grid.awk" "$_vm_home/grid-input.tsv")

# Expect: max=5 (Mon, bin 3), Mon-bin3=5, Tue-bin0=2, Sun-bin7=1
_max=$(echo "$_grid_out" | awk -F'\t' '$1=="max" { print $2 }')
assert_eq "grid awk: reports max=5" "5" "$_max"

_mon_b3=$(echo "$_grid_out" | awk -F'\t' '$1==1 && $2==3 { print $3 }')
assert_eq "grid awk: Mon bin-3 (09-12) count=5" "5" "$_mon_b3"

_tue_b0=$(echo "$_grid_out" | awk -F'\t' '$1==2 && $2==0 { print $3 }')
assert_eq "grid awk: Tue bin-0 (00-03) count=2" "2" "$_tue_b0"

_sun_b7=$(echo "$_grid_out" | awk -F'\t' '$1==0 && $2==7 { print $3 }')
assert_eq "grid awk: Sun bin-7 (21-00) count=1" "1" "$_sun_b7"

# ── strip awk: days-ago bucketing ─────────────────────────────────────────────

_strip_now=1700100000  # arbitrary anchor
cat > "$_vm_home/strip-input.tsv" <<EOF
1700100000	1	0	0	Opus	xxxxxxxx	0
1700099999	1	23	59	Opus	xxxxxxxx	0
1700013600	0	0	0	Sonnet	yyyyyyyy	0
1690000000	2	5	30	Haiku	zzzzzzzz	0
EOF

_strip_out=$(awk -v now="$_strip_now" -v maxdays=14 \
  -f "$CLAUDII_HOME/lib/vibemap-strip.awk" "$_vm_home/strip-input.tsv")

# Today (d=0): 2 entries (1700100000 and 1700099999)
_today=$(echo "$_strip_out" | awk -F'\t' '$1==0 { sum+=$3 } END { print sum+0 }')
assert_eq "strip awk: today = 2 entries" "2" "$_today"

# 1700013600 is 86400 seconds before 1700100000 = exactly d=1
_d1=$(echo "$_strip_out" | awk -F'\t' '$1==1 { sum+=$3 } END { print sum+0 }')
assert_eq "strip awk: d=1 = 1 entry" "1" "$_d1"

# 1690000000 is ~1158 days back → outside 14-day window, dropped
_oldold=$(echo "$_strip_out" | awk -F'\t' '$1>14 || $1=="max" { next } $1>0 && $1>1 { sum+=$3 } END { print sum+0 }')
assert_eq "strip awk: ancient entries dropped beyond maxdays" "0" "$_oldold"

# Calendar-day boundary (regression): an entry <24h before `now` but on the
# PREVIOUS local day must bucket as d=1, not d=0. now=1700100000 is 02:00 UTC;
# 1700091000 is 23:30 UTC the day before (2.5h earlier). The old rolling-24h
# math put it at d=0 ("today"); calendar-day math correctly puts it at d=1.
cat > "$_vm_home/strip-boundary.tsv" <<EOF
1700091000	0	23	30	Opus	bbbbbbbb	0
EOF
_strip_b=$(awk -v now="$_strip_now" -v maxdays=14 -v tz_offset=0 \
  -f "$CLAUDII_HOME/lib/vibemap-strip.awk" "$_vm_home/strip-boundary.tsv")
_b_d0=$(echo "$_strip_b" | awk -F'\t' '$1==0 { sum+=$3 } END { print sum+0 }')
_b_d1=$(echo "$_strip_b" | awk -F'\t' '$1==1 { sum+=$3 } END { print sum+0 }')
assert_eq "strip awk: prev-day entry within 24h buckets as d=1 (calendar, not rolling)" "1" "$_b_d1"
assert_eq "strip awk: prev-day entry not counted as today" "0" "$_b_d0"
unset _strip_b _b_d0 _b_d1

# ── CLI lifecycle: status / clear / path ──────────────────────────────────────

# config dir for the CLI to read
mkdir -p "$_vm_home/.config/claudii"
cat > "$_vm_home/.config/claudii/config.json" <<EOF
{ "vibemap": { "enabled": true, "path": "$_vm_path" } }
EOF

_status=$(_vm_run status 2>&1)
echo "$_status" | grep -q "enabled : true" && _ok=1 || _ok=0
assert_eq "vibemap status: shows enabled=true" "1" "$_ok"

echo "$_status" | grep -q "entries : 3" && _ok=1 || _ok=0
assert_eq "vibemap status: reports correct line count" "1" "$_ok"

_path_out=$(_vm_run path 2>&1)
assert_eq "vibemap path: prints configured path" "$_vm_path" "$_path_out"

_vm_run clear >/dev/null 2>&1
if [[ -e "$_vm_path" ]]; then
  assert_eq "vibemap clear: file removed" "no" "yes"
else
  assert_eq "vibemap clear: file removed" "yes" "yes"
fi

# clear on already-empty: no error
_out=$(_vm_run clear 2>&1; echo "rc=$?")
echo "$_out" | grep -q "rc=0" && _ok=1 || _ok=0
assert_eq "vibemap clear: idempotent (rc=0 when no file)" "1" "$_ok"

# Unknown subcommand returns rc=2
_out=$(_vm_run zzzzzz 2>&1; echo "rc=$?")
echo "$_out" | grep -q "rc=2" && _ok=1 || _ok=0
assert_eq "vibemap: unknown subcommand returns rc=2" "1" "$_ok"

# --days input validation
_out=$(_vm_run strip --days 999 2>&1; echo "rc=$?")
echo "$_out" | grep -q "rc=2" && _ok=1 || _ok=0
assert_eq "vibemap strip: --days bounds-checked (1..90)" "1" "$_ok"

# ── mini-vibemap overview segment ─────────────────────────────────────────────

# Setup: fresh home with vibemap enabled + some data
_vm_home2=$(mktemp -d)
_vm_path2="$_vm_home2/.cache/claudii/vibemap.tsv"
mkdir -p "${_vm_path2%/*}"
mkdir -p "$_vm_home2/.config/claudii"

# Write a small data file (a few recent entries)
_now2=$(date +%s)
printf '%s\t1\t9\t0\tSonnet\taaaaaaaa\t1000\n' "$_now2" >> "$_vm_path2"
printf '%s\t2\t14\t30\tOpus\tbbbbbbbb\t2000\n' "$(( _now2 - 86400 ))" >> "$_vm_path2"

# Config: vibemap enabled
cat > "$_vm_home2/.config/claudii/config.json" <<EOF
{ "vibemap": { "enabled": true, "path": "$_vm_path2" } }
EOF

# Mini-strip renders when vibemap.enabled=true + data exists
_ov_out=$(HOME="$_vm_home2" XDG_CACHE_HOME="$_vm_home2/.cache" \
  XDG_CONFIG_HOME="$_vm_home2/.config" \
  bash "$CLAUDII_HOME/bin/claudii" 2>&1)
echo "$_ov_out" | grep -q "Activity" && _ok=1 || _ok=0
assert_eq "overview: Activity section present when vibemap enabled+data" "1" "$_ok"

# The Activity block must contain a real density char (░▒▓█), not just be non-empty.
# Two ways the old assert passed VACUOUSLY: (a) `tail -n 1` grabbed the "last 43d…"
# FOOTER line, not the strip; (b) when the mini-strip crashed under set -u (cold cache,
# bash 5.x), the caller's 2>/dev/null fell through to the disabled placeholder. Grep the
# whole 2-line block (header + strip) for a density char so the strip itself is asserted.
_act_block=$(echo "$_ov_out" | grep -A2 "Activity")
echo "$_act_block" | grep -qE '[░▒▓█]' && _ok=1 || _ok=0
assert_eq "overview: Activity strip renders density chars (not the disabled placeholder)" "1" "$_ok"

# Config: vibemap disabled → placeholder line
cat > "$_vm_home2/.config/claudii/config.json" <<EOF
{ "vibemap": { "enabled": false, "path": "$_vm_path2" } }
EOF

_ov_out2=$(HOME="$_vm_home2" XDG_CACHE_HOME="$_vm_home2/.cache" \
  XDG_CONFIG_HOME="$_vm_home2/.config" \
  bash "$CLAUDII_HOME/bin/claudii" 2>&1)
# Should still show Activity section, but as dim placeholder
echo "$_ov_out2" | grep -q "Activity" && _ok=1 || _ok=0
assert_eq "overview: Activity placeholder present when vibemap disabled" "1" "$_ok"
# Placeholder references enabling command
echo "$_ov_out2" | grep -q "vibemap.enabled true" && _ok=1 || _ok=0
assert_eq "overview: Activity placeholder shows enable command" "1" "$_ok"

rm -rf "$_vm_home2"

# ── strip today-row: ▶ marker + future hours blank ────────────────────────────

_vm_home3=$(mktemp -d)
_vm_path3="$_vm_home3/.cache/claudii/vibemap.tsv"
mkdir -p "${_vm_path3%/*}"
mkdir -p "$_vm_home3/.config/claudii"

# Populate with entries spread across hours 0-5 of today and a past day
_now3=$(date +%s)
printf '%s\t1\t0\t0\tOpus\tcccccccc\t0\n' "$_now3" >> "$_vm_path3"
printf '%s\t1\t1\t0\tOpus\tcccccccc\t0\n' "$_now3" >> "$_vm_path3"
printf '%s\t1\t2\t0\tOpus\tcccccccc\t0\n' "$_now3" >> "$_vm_path3"
printf '%s\t2\t5\t0\tSonnet\tdddddddd\t0\n' "$(( _now3 - 86400 ))" >> "$_vm_path3"

cat > "$_vm_home3/.config/claudii/config.json" <<EOF
{ "vibemap": { "enabled": true, "path": "$_vm_path3" }, "statusline": { "bedtime": "23:00" } }
EOF

_strip_out=$(HOME="$_vm_home3" XDG_CACHE_HOME="$_vm_home3/.cache" \
  XDG_CONFIG_HOME="$_vm_home3/.config" \
  bash "$CLAUDII_HOME/bin/claudii" vibemap strip 2>&1)

# today-row must contain ▶ marker
echo "$_strip_out" | grep -q "▶" && _ok=1 || _ok=0
assert_eq "strip today-row: ▶ marker present" "1" "$_ok"

# today-row must contain the cursor │ character
echo "$_strip_out" | grep "▶" | grep -q "│" && _ok=1 || _ok=0
assert_eq "strip today-row: │ cursor present in today row" "1" "$_ok"

# Determine current hour — if it's before 23, hour 23 should be blank in today-row
_cur_h=$(date '+%H' | sed 's/^0//')
_cur_h="${_cur_h:-0}"
if (( _cur_h < 23 )); then
  # today-row should have trailing spaces (future hours) after the cursor
  _today_row=$(echo "$_strip_out" | grep "▶")
  # Strip ANSI escapes to compare raw characters
  _today_raw=$(printf '%s' "$_today_row" | sed $'s/\033\\[[0-9;]*m//g')
  # Count trailing spaces after the cursor position — at least one future hour
  # if we're not in the last hour of the day.
  _future_spaces=$(printf '%s' "$_today_raw" | grep -o ' *$' | wc -c | tr -d ' ')
  (( _future_spaces > 0 )) && _ok=1 || _ok=0
  assert_eq "strip today-row: future hours rendered as blank spaces" "1" "$_ok"
fi

rm -rf "$_vm_home3"

# ── grid view: today-column accent highlight ───────────────────────────────────

_vm_home4=$(mktemp -d)
_vm_path4="$_vm_home4/.cache/claudii/vibemap.tsv"
mkdir -p "${_vm_path4%/*}"
mkdir -p "$_vm_home4/.config/claudii"

# Populate with entries on multiple weekdays so the grid has something to show
_now4=$(date +%s)
printf '%s\t1\t9\t0\tOpus\teeeeeeee\t0\n' "$_now4" >> "$_vm_path4"
printf '%s\t2\t14\t0\tSonnet\tffffffff\t0\n' "$_now4" >> "$_vm_path4"
printf '%s\t5\t10\t0\tHaiku\tgggggggg\t0\n' "$_now4" >> "$_vm_path4"

cat > "$_vm_home4/.config/claudii/config.json" <<EOF
{ "vibemap": { "enabled": true, "path": "$_vm_path4" }, "statusline": { "bedtime": "23:00" } }
EOF

# CLAUDII_FORCE_COLOR: the assert below checks the accent escape — captured
# output is not a TTY, so auto-colors would blank it.
_grid_out=$(HOME="$_vm_home4" XDG_CACHE_HOME="$_vm_home4/.cache" \
  XDG_CONFIG_HOME="$_vm_home4/.config" CLAUDII_FORCE_COLOR=1 \
  bash "$CLAUDII_HOME/bin/claudii" vibemap grid 2>&1)

# Header must contain ▶ marker (today's column)
echo "$_grid_out" | grep -q "▶" && _ok=1 || _ok=0
assert_eq "grid today-column: header contains ▶ marker" "1" "$_ok"

# Output must contain accent ANSI escape (CLAUDII_CLR_ACCENT = \033[38;5;213m)
printf '%s' "$_grid_out" | grep -q $'\033\[38;5;213m' && _ok=1 || _ok=0
assert_eq "grid today-column: output contains accent ANSI escape" "1" "$_ok"

# Legend line must mention today
assert_contains "grid today-column: legend mentions today" "today" "$_grid_out"

# Default view (no subcommand) now renders the 30-day strip, not the grid.
_def_out=$(HOME="$_vm_home4" XDG_CACHE_HOME="$_vm_home4/.cache" \
  XDG_CONFIG_HOME="$_vm_home4/.config" \
  bash "$CLAUDII_HOME/bin/claudii" vibemap 2>&1)
echo "$_def_out" | grep -q "last 30 days" && _ok=1 || _ok=0
assert_eq "vibemap default: bare 'vibemap' renders the 30-day strip" "1" "$_ok"
# The strip header is "00 03 06 …"; the grid's "00-03" bin labels must be absent.
echo "$_def_out" | grep -qE '00-03|21-00' && _ok=0 || _ok=1
assert_eq "vibemap default: bare 'vibemap' is not the weekday grid" "1" "$_ok"
unset _def_out

rm -rf "$_vm_home4"

# ── mini-strip: today char rendered in accent ──────────────────────────────────

_vm_home5=$(mktemp -d)
_vm_path5="$_vm_home5/.cache/claudii/vibemap.tsv"
mkdir -p "${_vm_path5%/*}"
mkdir -p "$_vm_home5/.config/claudii"

_now5=$(date +%s)
printf '%s\t1\t9\t0\tOpus\thhhhhhHH\t0\n' "$_now5" >> "$_vm_path5"
printf '%s\t2\t14\t0\tSonnet\tiiiiiiii\t0\n' "$(( _now5 - 86400 ))" >> "$_vm_path5"

cat > "$_vm_home5/.config/claudii/config.json" <<EOF
{ "vibemap": { "enabled": true, "path": "$_vm_path5" } }
EOF

# CLAUDII_FORCE_COLOR: see grid today-column test above.
_ov_out5=$(HOME="$_vm_home5" XDG_CACHE_HOME="$_vm_home5/.cache" \
  XDG_CONFIG_HOME="$_vm_home5/.config" CLAUDII_FORCE_COLOR=1 \
  bash "$CLAUDII_HOME/bin/claudii" 2>&1)

# Activity strip must contain the accent ANSI escape for today
printf '%s' "$_ov_out5" | grep -q $'\033\[38;5;213m' && _ok=1 || _ok=0
assert_eq "mini-strip: today char rendered in accent color" "1" "$_ok"

rm -rf "$_vm_home5"
