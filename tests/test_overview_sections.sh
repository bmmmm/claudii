# touches: lib/cmd/overview.sh lib/render.sh lib/usage_spark.awk bin/claudii config/defaults.json
# test_overview_sections.sh — modular, config-driven overview sections

_ovs_tmp=$(mktemp -d)
_ovs_xdg="$_ovs_tmp/xdg"
mkdir -p "$_ovs_xdg/claudii"

_ovs_run() {
  CLAUDII_CACHE_DIR="$_ovs_tmp/cache" XDG_CONFIG_HOME="$_ovs_xdg" \
    bash "$CLAUDII_HOME/bin/claudii" 2>&1
}
_ovs_plain() { _ovs_run | sed 's/\x1b\[[0-9;]*m//g'; }
mkdir -p "$_ovs_tmp/cache"

# ── Default sections (from defaults.json) ────────────────────────────────────
cp "$CLAUDII_HOME/config/defaults.json" "$_ovs_xdg/claudii/config.json"
_ovs_out=$(_ovs_plain)

for _sec in Account Usage Sessions Agents Services Commands; do
  assert_contains "default overview renders section: $_sec" "$_sec" "$_ovs_out"
done

# Agents section: grouped by tier + shell aliases (not a raw per-agent table)
assert_contains "agents: haiku tier line"   "haiku"  "$_ovs_out"
assert_contains "agents: opus tier line"    "opus"   "$_ovs_out"
assert_contains "agents: shell alias line"  "shell"  "$_ovs_out"
assert_contains "agents: alias cl listed"   "cl"     "$_ovs_out"
assert_contains "agents: effort shown per agent" "snmax/max" "$_ovs_out"
assert_contains "agents: hint is an invocable command" "claudii agents" "$_ovs_out"

# Commands section: grouped quick reference, items are real subcommands
assert_contains "commands: vibemap discoverable" "vibemap" "$_ovs_out"
assert_contains "commands: omlx discoverable"    "omlx"    "$_ovs_out"
assert_contains "commands: vpnii discoverable"   "vpnii"   "$_ovs_out"
assert_contains "commands: skills-cost listed"   "skills-cost" "$_ovs_out"
assert_contains "commands: prefix rule stated"   "claudii <command>" "$_ovs_out"
# Unified taxonomy: the `insights` group restores the analytics commands the old
# board silently dropped (tokens/perf/tools/limits). Pin the group label + a
# distinctive slice of its item list so a regrouping regression is caught.
assert_contains "commands: insights group present"     "insights"              "$_ovs_out"
assert_contains "commands: dropped analytics restored" "perf · tools · limits" "$_ovs_out"

# ── Usage section: 30-day token sparkline from history ───────────────────────
# Empty cache (no history) → placeholder; with history token rows → sparkline.
assert_contains "usage: placeholder when no history" "token trends" "$_ovs_out"

# Seed a small history with token rows on two days, then re-render with defaults.
_ovs_now=$(date +%s)
printf '%d\tclaude-opus-4-5\t1.0\t50\t30\tsid-u1\t100000\t50000\t0\n%d\tclaude-opus-4-5\t2.0\t50\t30\tsid-u2\t200000\t80000\t0\n' \
  "$(( _ovs_now - 86400 ))" "$_ovs_now" > "$_ovs_tmp/cache/history.tsv"
cp "$CLAUDII_HOME/config/defaults.json" "$_ovs_xdg/claudii/config.json"
_ovs_usage=$(_ovs_plain)
assert_contains "usage: header + 30d window"      "last 30d"       "$_ovs_usage"
assert_contains "usage: today/avg/peak context"   "avg"            "$_ovs_usage"
assert_contains "usage: peak label"               "peak"           "$_ovs_usage"
# today = sid-u2 first row = 200000+80000 = 280000 → 280K; proves aggregation ran
assert_contains "usage: today token value (280K)" "280K"           "$_ovs_usage"
assert_contains "usage: hint is invocable command" "claudii tokens" "$_ovs_usage"
rm -f "$_ovs_tmp/cache/history.tsv"
unset _ovs_now _ovs_usage

# ── Custom order + subset ────────────────────────────────────────────────────
jq '.overview.sections = ["services", "account"]' "$CLAUDII_HOME/config/defaults.json" \
  > "$_ovs_xdg/claudii/config.json"
_ovs_out2=$(_ovs_plain)

assert_contains     "subset: Services renders"        "Services" "$_ovs_out2"
assert_contains     "subset: Account renders"         "Account"  "$_ovs_out2"
assert_not_contains "subset: Commands suppressed"     "Commands" "$_ovs_out2"
assert_not_contains "subset: Agents suppressed"       "Agents"   "$_ovs_out2"
# Services configured before account → must appear first
_ovs_svc_line=$(grep -nF "Services" <<<"$_ovs_out2" | head -1 | cut -d: -f1)
_ovs_acct_line=$(grep -nF "Account" <<<"$_ovs_out2" | head -1 | cut -d: -f1)
_ovs_ordered=0
[[ -n "$_ovs_svc_line" && -n "$_ovs_acct_line" ]] && (( _ovs_svc_line < _ovs_acct_line )) && _ovs_ordered=1
assert_eq "subset: configured order respected (services before account)" "1" "$_ovs_ordered"
# Without the commands section, the global help footer must come back
assert_contains "subset: help footer present when commands section absent" "claudii help" "$_ovs_out2"

# ── Unknown section name → actionable inline warning, no abort ──────────────
jq '.overview.sections = ["account", "bogus"]' "$CLAUDII_HOME/config/defaults.json" \
  > "$_ovs_xdg/claudii/config.json"
_ovs_out3=$(_ovs_plain)
assert_contains "unknown section: warning names the bad value" "unknown overview section 'bogus'" "$_ovs_out3"
assert_contains "unknown section: rest of overview still renders" "Account" "$_ovs_out3"

# ── Account: wall-clock reset time alongside the relative countdown ──────────
# A session cache with future 5h/7d reset epochs makes the account line render
# real rate data (not the "appears after first session" placeholder), so the
# new absolute reset time is exercised. The time is matched as a bare HH:MM
# pattern, not a fixed value — _fmt_abs is timezone-aware, so the wall clock
# varies by machine/CI locale (keeps the de_DE matrix green).
_ovs_rnow=$(date +%s)
printf 'model=Sonnet\nctx_pct=50\ncost=1.00\ntok=1000\ncache_pct=50\nrate_5h=30\nrate_7d=20\nrate_7d_start=15\nreset_5h=%s\nreset_7d=%s\nsession_id=acct\nppid=%s\n' \
  "$(( _ovs_rnow + 3600 ))" "$(( _ovs_rnow + 2 * 86400 ))" "$$" \
  > "$_ovs_tmp/cache/session-acct"
cp "$CLAUDII_HOME/config/defaults.json" "$_ovs_xdg/claudii/config.json"
_ovs_acct=$(_ovs_plain)
# The relative countdown is still there (proves the real rate line rendered).
assert_contains "account: relative reset countdown still present" "↺" "$_ovs_acct"
# Both the 5h and 7d resets append an absolute HH:MM time → at least two matches.
_ovs_times=$(echo "$_ovs_acct" | grep -oE '[0-9][0-9]:[0-9][0-9]' | wc -l | tr -d ' ')
(( _ovs_times >= 2 )) && _ok=1 || _ok=0
assert_eq "account: 5h and 7d resets show a wall-clock time (HH:MM)" "1" "$_ok"
# The 7d reset uses '%a %H:%M', so a weekday word precedes its HH:MM. Matched
# locale-robustly so a regression that drops %a is caught without breaking the
# de_DE CI matrix. The weekday abbrev may carry a trailing '.' — macOS' de_DE
# %a renders "Di. 21:41", not "Di 21:41" — so allow letters+dots before the
# space ([A-Za-z][A-Za-z.]*). The 5h '%H:%M' sits in "(16:30)" with no such
# prefix, so this still pins the 7d entry specifically.
echo "$_ovs_acct" | grep -qE '[A-Za-z][A-Za-z.]* [0-9][0-9]:[0-9][0-9]' && _ok=1 || _ok=0
assert_eq "account: 7d reset wall-clock carries a weekday prefix" "1" "$_ok"
rm -f "$_ovs_tmp/cache/session-acct"
unset _ovs_rnow _ovs_acct _ovs_times _ok

rm -rf "$_ovs_tmp"
unset _ovs_tmp _ovs_xdg _ovs_out _ovs_out2 _ovs_out3 _ovs_svc_line _ovs_acct_line _ovs_ordered _sec
