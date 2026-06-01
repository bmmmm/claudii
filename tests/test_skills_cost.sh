# touches: lib/cmd/sessions.sh bin/claudii completions/_claudii man/man1/claudii.1 CHANGELOG.md

# test_skills_cost.sh — claudii skills-cost command
#
# All tests use fixture cache dirs with hand-built per-session insight JSON files,
# so they do not depend on Agents A or B being merged yet.
# CLAUDII_CACHE_DIR=<parent> causes claudii-insights merge to read from <parent>/insights/*.json

_SC_TMPDIRS=()
trap 'rm -rf "${_SC_TMPDIRS[@]}" 2>/dev/null' EXIT

# Helper: create a per-session JSON fixture with attribution data.
# Args: out_file, skills_json_inline, plugins_json_inline
# Both skill/plugin args are inlined directly into the jq expression (must be valid JSON).
_sc_write_fixture() {
  local out_file="$1"
  local skills_json="${2:-{\}}"
  local plugins_json="${3:-{\}}"
  # Write JSON by constructing it with jq, using heredoc to avoid --argjson multiline issues
  jq -n \
    --argjson s "${skills_json}" \
    --argjson p "${plugins_json}" \
    '{schema_version:3,sessionId:"test-session-01",last_seen:"2026-05-27T12:00:00Z",messages:5,assistant_messages:3,sidechain_msgs:0,thinking_blocks:0,limit_hits:[],snapshots:0,days:{},models:{},tools:{},tool_errors:{},stop_reasons:{},subagent_types:{},permission_modes:{},service_tier:{},attribution_skills:$s,attribution_plugins:$p}' \
    > "$out_file"
}

# ── Test 1: Empty cache dir → "no data" message, exit 0 ─────────────────────
_SC_EMPTY_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_EMPTY_CACHE")
mkdir -p "$_SC_EMPTY_CACHE/insights"

_sc_empty_out=$(CLAUDII_CACHE_DIR="$_SC_EMPTY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
_sc_empty_rc=$(CLAUDII_CACHE_DIR="$_SC_EMPTY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost >/dev/null 2>&1; echo $?)

assert_eq "skills-cost empty cache: exit 0" "0" "$_sc_empty_rc"
assert_contains "skills-cost empty cache: no-data hint" "No skill attribution data" "$_sc_empty_out"

# ── Test 2: Fixture with two skills → table prints expected rows ─────────────
_SC_FIXTURE_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_FIXTURE_CACHE")
mkdir -p "$_SC_FIXTURE_CACHE/insights"

_sc_write_fixture "$_SC_FIXTURE_CACHE/insights/sess-01.json" \
  '{"explore":{"calls":17,"in_tok":12000,"out_tok":4200,"cache_read":350000,"cache_create":95000},"scope-permissions":{"calls":4,"in_tok":8000,"out_tok":1100,"cache_read":75000,"cache_create":12000}}' \
  '{}'

_sc_out=$(CLAUDII_CACHE_DIR="$_SC_FIXTURE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
_sc_rc=$(CLAUDII_CACHE_DIR="$_SC_FIXTURE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost >/dev/null 2>&1; echo $?)

assert_eq "skills-cost fixture: exit 0" "0" "$_sc_rc"
assert_contains "skills-cost fixture: shows explore"           "explore"           "$_sc_out"
assert_contains "skills-cost fixture: shows scope-permissions" "scope-permissions" "$_sc_out"
assert_contains "skills-cost fixture: shows calls column"      "17"                "$_sc_out"
assert_contains "skills-cost fixture: shows column header"     "Calls"             "$_sc_out"
assert_contains "skills-cost fixture: shows median line"       "Median cost/call"  "$_sc_out"
assert_contains "skills-cost fixture: shows model mixed"       "mixed"             "$_sc_out"

# ── Test 3: Outlier flag math ─────────────────────────────────────────────────
# 3 skills: cheap (avg ~$0.01), mid (avg ~$0.02), expensive (avg ~$0.10 = 5× median $0.02)
# Median of [0.01, 0.02, 0.10] = 0.02. Threshold = 0.06. expensive triggers !
_SC_OUTLIER_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_OUTLIER_CACHE")
mkdir -p "$_SC_OUTLIER_CACHE/insights"

# To get ~$0.01 avg: calls=10, out_tok=666 → 666 * 0.000015 = ~$0.01
# To get ~$0.02 avg: calls=5, out_tok=667 → 667 * 0.000015 = ~$0.01/call → need bigger toks
# Simplify: use just out_tok pricing ($0.000015/tok)
#   cheap:     calls=10, out_tok=667   → 667*0.000015=$0.010005 total, avg=$0.0010005
#   mid:       calls=1,  out_tok=1333  → 1333*0.000015=$0.019995 total, avg=$0.019995
#   expensive: calls=1,  out_tok=10000 → 10000*0.000015=$0.15 total, avg=$0.15
# sorted avgs: 0.00100, 0.01999, 0.15 → median=0.01999, threshold=0.05997
# expensive (0.15) >= 0.05997 → flagged !
_sc_write_fixture "$_SC_OUTLIER_CACHE/insights/sess-outlier.json" \
  '{"cheap-skill":{"calls":10,"in_tok":0,"out_tok":667,"cache_read":0,"cache_create":0},"mid-skill":{"calls":1,"in_tok":0,"out_tok":1333,"cache_read":0,"cache_create":0},"expensive-skill":{"calls":1,"in_tok":0,"out_tok":10000,"cache_read":0,"cache_create":0}}' \
  '{}'

_sc_outlier_out=$(CLAUDII_CACHE_DIR="$_SC_OUTLIER_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
_sc_outlier_rc=$(CLAUDII_CACHE_DIR="$_SC_OUTLIER_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost >/dev/null 2>&1; echo $?)

assert_eq "skills-cost outlier: exit 0" "0" "$_sc_outlier_rc"
assert_contains "skills-cost outlier: expensive-skill present"  "expensive-skill" "$_sc_outlier_out"
assert_contains "skills-cost outlier: flag ! present"           "!"               "$_sc_outlier_out"
# cheap and mid should NOT have a flag — only 1 data row should carry an outlier flag.
# Count data rows with '!' by excluding header/footer lines (Skill, ──, Median).
_sc_flag_count=$(printf '%s\n' "$_sc_outlier_out" \
  | grep -v 'Skill\|───\|Median\|skills-cost\|days' \
  | grep -c '!' || true)
assert_eq "skills-cost outlier: exactly 1 row flagged" "1" "$_sc_flag_count"

# ── Test 4: --plugins flag switches attribution block ─────────────────────────
_SC_PLUGINS_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_PLUGINS_CACHE")
mkdir -p "$_SC_PLUGINS_CACHE/insights"

_sc_write_fixture "$_SC_PLUGINS_CACHE/insights/sess-plugins.json" \
  '{}' \
  '{"commit-commands":{"calls":6,"in_tok":5000,"out_tok":800,"cache_read":50000,"cache_create":8000}}'

# Default (skills) → no data (skills block empty)
_sc_no_skills=$(CLAUDII_CACHE_DIR="$_SC_PLUGINS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
assert_contains "skills-cost --plugins: skills mode shows no-data" "No skill attribution data" "$_sc_no_skills"

# --plugins mode → shows commit-commands
_sc_plugins_out=$(CLAUDII_CACHE_DIR="$_SC_PLUGINS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --plugins 2>&1)
_sc_plugins_rc=$(CLAUDII_CACHE_DIR="$_SC_PLUGINS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --plugins >/dev/null 2>&1; echo $?)

assert_eq "skills-cost --plugins: exit 0" "0" "$_sc_plugins_rc"
assert_contains "skills-cost --plugins: shows commit-commands" "commit-commands" "$_sc_plugins_out"
assert_contains "skills-cost --plugins: shows Plugin label"    "Plugin"          "$_sc_plugins_out"

# ── Test 5: --json output is parseable with jq ───────────────────────────────
_SC_JSON_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_JSON_CACHE")
mkdir -p "$_SC_JSON_CACHE/insights"

_sc_write_fixture "$_SC_JSON_CACHE/insights/sess-json.json" \
  '{"explore":{"calls":5,"in_tok":3000,"out_tok":800,"cache_read":40000,"cache_create":5000},"proxy":{"calls":2,"in_tok":1000,"out_tok":200,"cache_read":10000,"cache_create":1000}}' \
  '{}'

_sc_json_out=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_json_rc=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json >/dev/null 2>&1; echo $?)

assert_eq "skills-cost --json: exit 0" "0" "$_sc_json_rc"
_sc_jq_rc=$(jq -e . <<< "$_sc_json_out" >/dev/null 2>&1; echo $?)
assert_eq "skills-cost --json: valid JSON" "0" "$_sc_jq_rc"
assert_contains "skills-cost --json: has rows key"     '"rows"'     "$_sc_json_out"
assert_contains "skills-cost --json: has meta key"     '"meta"'     "$_sc_json_out"
assert_contains "skills-cost --json: has name field"   '"name"'     "$_sc_json_out"
assert_contains "skills-cost --json: has outlier field" '"outlier"' "$_sc_json_out"
assert_contains "skills-cost --json: skill name present" "explore"  "$_sc_json_out"
# meta should have median_avg_usd and days
_sc_has_median=$(jq -e '.meta.median_avg_usd' <<< "$_sc_json_out" >/dev/null 2>&1; echo $?)
assert_eq "skills-cost --json: meta has median_avg_usd" "0" "$_sc_has_median"
_sc_has_days=$(jq -e '.meta.days' <<< "$_sc_json_out" >/dev/null 2>&1; echo $?)
assert_eq "skills-cost --json: meta has days" "0" "$_sc_has_days"

# ── Test 6: --days is passed through (reflected in days window) ───────────────
_sc_json_7d=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json --days 7 2>&1)
_sc_days_val=$(jq -r '.meta.days' <<< "$_sc_json_7d" 2>/dev/null)
assert_eq "skills-cost --days 7: meta.days is 7" "7" "$_sc_days_val"

# ── Test 7: command in bin/claudii dispatch (basic smoke) ─────────────────────
_sc_dispatch_out=$(bash "$CLAUDII_HOME/bin/claudii" skills-cost --help 2>&1)
_sc_dispatch_rc=$(bash "$CLAUDII_HOME/bin/claudii" skills-cost --help >/dev/null 2>&1; echo $?)
assert_eq "skills-cost dispatch: exit 0 on --help" "0" "$_sc_dispatch_rc"
assert_contains "skills-cost dispatch: usage shown" "skills-cost" "$_sc_dispatch_out"

# ── Test 8: --days rejects non-positive-integer values (was silently ignored) ─
_sc_bad_out=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --days abc 2>&1; echo "rc=$?")
assert_contains "skills-cost --days abc: actionable error" "positive integer" "$_sc_bad_out"
assert_contains "skills-cost --days abc: exit 1" "rc=1" "$_sc_bad_out"
_sc_zero_out=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --days 0 2>&1; echo "rc=$?")
assert_contains "skills-cost --days 0: rejected (exit 1)" "rc=1" "$_sc_zero_out"

unset _SC_TMPDIRS _sc_empty_out _sc_empty_rc _sc_out _sc_rc _sc_outlier_out _sc_outlier_rc \
      _sc_flag_count _sc_no_skills _sc_plugins_out _sc_plugins_rc _sc_json_out _sc_json_rc \
      _sc_jq_rc _sc_has_median _sc_has_days _sc_json_7d _sc_days_val _sc_dispatch_out _sc_dispatch_rc \
      _sc_bad_out _sc_zero_out
