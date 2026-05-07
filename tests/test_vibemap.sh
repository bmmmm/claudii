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

rm -rf "$_vm_home"
