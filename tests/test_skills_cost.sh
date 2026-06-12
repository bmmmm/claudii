# touches: lib/cmd/skills-cost.sh bin/claudii completions/_claudii man/man1/claudii.1 CHANGELOG.md

# test_skills_cost.sh — claudii skills-cost command
#
# All tests use fixture cache dirs with hand-built per-session insight JSON files,
# so they do not depend on Agents A or B being merged yet.
# CLAUDII_CACHE_DIR=<parent> causes claudii-insights merge to read from <parent>/insights/*.json

_SC_TMPDIRS=()
trap 'rm -rf "${_SC_TMPDIRS[@]}" 2>/dev/null' EXIT

# Helper: create a per-session JSON fixture with attribution data.
# Args: out_file, skills_json_inline, plugins_json_inline, [mcp_json_inline], [models_json_inline]
# All JSON args are inlined directly into the jq expression (must be valid JSON).
# last_seen is computed at load time (recent) so the --days cutoff window always
# contains the fixture. A hardcoded date (was 2026-05-27) silently went stale: once
# wall-clock passed fixture+7d the `--days 7` cutoff filtered every row out and the
# command returned early before building .meta, flipping the --days-passthrough test.
_SC_LAST_SEEN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
_sc_write_fixture() {
  local out_file="$1"
  local skills_json="${2:-{\}}"
  local plugins_json="${3:-{\}}"
  local mcp_json="${4:-{\}}"
  local models_json="${5:-{\}}"
  # Write JSON by constructing it with jq, using heredoc to avoid --argjson multiline issues
  jq -n \
    --argjson s "${skills_json}" \
    --argjson p "${plugins_json}" \
    --argjson m "${mcp_json}" \
    --argjson am "${models_json}" \
    --arg ls "$_SC_LAST_SEEN" \
    '{schema_version:4,sessionId:"test-session-01",last_seen:$ls,messages:5,assistant_messages:3,sidechain_msgs:0,thinking_blocks:0,limit_hits:[],snapshots:0,days:{},models:{},tools:{},tool_errors:{},stop_reasons:{},subagent_types:{},permission_modes:{},service_tier:{},attribution_skills:$s,attribution_plugins:$p,attribution_mcp:$m,attribution_models:$am}' \
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

# ── Test 3: Outlier flag math (rule: avg ≥ 2× median AND ≥ 10 calls) ──────────
_SC_OUTLIER_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_OUTLIER_CACHE")
mkdir -p "$_SC_OUTLIER_CACHE/insights"

# Only out_tok pricing ($0.000015/tok) for easy math. Five skills:
#   cheap:          calls=10, out_tok=667    → avg $0.0010005
#   mid:            calls=1,  out_tok=1333   → avg $0.019995
#   mid2:           calls=1,  out_tok=1334   → avg $0.02001
#   expensive:      calls=10, out_tok=100000 → avg $0.15
#   rare-expensive: calls=2,  out_tok=40000  → avg $0.30 (over threshold but < 10 calls)
# sorted avgs: 0.0010005, 0.019995, 0.02001, 0.15, 0.30 → median=0.02001,
# threshold (2×)=0.04002 → expensive flagged; rare-expensive blocked by the
# calls floor; cheap/mid/mid2 under threshold. Exactly 1 flag.
_sc_write_fixture "$_SC_OUTLIER_CACHE/insights/sess-outlier.json" \
  '{"cheap-skill":{"calls":10,"in_tok":0,"out_tok":667,"cache_read":0,"cache_create":0},"mid-skill":{"calls":1,"in_tok":0,"out_tok":1333,"cache_read":0,"cache_create":0},"mid2-skill":{"calls":1,"in_tok":0,"out_tok":1334,"cache_read":0,"cache_create":0},"expensive-skill":{"calls":10,"in_tok":0,"out_tok":100000,"cache_read":0,"cache_create":0},"rare-expensive":{"calls":2,"in_tok":0,"out_tok":40000,"cache_read":0,"cache_create":0}}' \
  '{}'

_sc_outlier_out=$(CLAUDII_CACHE_DIR="$_SC_OUTLIER_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
_sc_outlier_rc=$(CLAUDII_CACHE_DIR="$_SC_OUTLIER_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost >/dev/null 2>&1; echo $?)

assert_eq "skills-cost outlier: exit 0" "0" "$_sc_outlier_rc"
assert_contains "skills-cost outlier: expensive-skill present"  "expensive-skill" "$_sc_outlier_out"
assert_contains "skills-cost outlier: flag ! present"           "!"               "$_sc_outlier_out"
assert_contains "skills-cost outlier: footer states calls floor" "10 calls"       "$_sc_outlier_out"
# Only expensive-skill may carry the flag: rare-expensive is over the cost
# threshold but under the calls floor; cheap/mid/mid2 are under the threshold.
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
# Token split per row (judgment signal: out-heavy vs cache_read-heavy) + pricing caveat
_sc_split=$(jq -r '.rows[] | select(.name=="explore") | [.in_tok, .out_tok, .cache_read, .cache_create] | @csv' <<< "$_sc_json_out" 2>/dev/null)
assert_eq "skills-cost --json: row carries token split" "3000,800,40000,5000" "$_sc_split"
_sc_has_pricing=$(jq -e '.meta.pricing | test("per-model rates")' <<< "$_sc_json_out" >/dev/null 2>&1; echo $?)
assert_eq "skills-cost --json: meta.pricing caveat present" "0" "$_sc_has_pricing"

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

# ── Test 9: --mcp flag renders attribution_mcp with stripped prefix ───────────
_SC_MCP_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_MCP_CACHE")
mkdir -p "$_SC_MCP_CACHE/insights"

_sc_write_fixture "$_SC_MCP_CACHE/insights/sess-mcp.json" \
  '{}' '{}' \
  '{"mcp__srv__browser_navigate":{"calls":4,"in_tok":100.5,"out_tok":250,"cache_read":20000,"cache_create":1000}}' \
  '{"mcp|mcp__srv__browser_navigate|claude-sonnet-4-6":4}'

_sc_mcp_out=$(CLAUDII_CACHE_DIR="$_SC_MCP_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --mcp 2>&1)
_sc_mcp_rc=$(CLAUDII_CACHE_DIR="$_SC_MCP_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --mcp >/dev/null 2>&1; echo $?)

assert_eq "skills-cost --mcp: exit 0" "0" "$_sc_mcp_rc"
assert_contains "skills-cost --mcp: shows MCP Tool label" "MCP Tool" "$_sc_mcp_out"
assert_contains "skills-cost --mcp: shows tool name"      "srv__browser_navigate" "$_sc_mcp_out"
# Display drops the mcp__ prefix; the data key keeps it
_sc_mcp_prefix=$(printf '%s\n' "$_sc_mcp_out" | grep -c 'mcp__srv' || true)
assert_eq "skills-cost --mcp: mcp__ prefix stripped in table" "0" "$_sc_mcp_prefix"
# 4/4 calls on sonnet-4-6 → dominant model label rendered
assert_contains "skills-cost --mcp: dominant model label" "Sonnet 4.6" "$_sc_mcp_out"
# skills mode on the same cache → no data (skills block empty)
_sc_mcp_skills=$(CLAUDII_CACHE_DIR="$_SC_MCP_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
assert_contains "skills-cost --mcp cache: skills mode shows no-data" "No skill attribution data" "$_sc_mcp_skills"

# ── Test 10: dominant model column (≥80% of calls → label, else mixed) ────────
_SC_MODEL_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_MODEL_CACHE")
mkdir -p "$_SC_MODEL_CACHE/insights"

# dominant-skill: 9/10 calls opus-4-7 (90% ≥ 80%) → "Opus 4.7"
# split-skill: 5/10 + 5/10 → "mixed"
_sc_write_fixture "$_SC_MODEL_CACHE/insights/sess-model.json" \
  '{"dominant-skill":{"calls":10,"in_tok":1000,"out_tok":500,"cache_read":0,"cache_create":0},"split-skill":{"calls":10,"in_tok":1000,"out_tok":400,"cache_read":0,"cache_create":0}}' \
  '{}' '{}' \
  '{"skill|dominant-skill|claude-opus-4-7":9,"skill|dominant-skill|claude-haiku-4-5":1,"skill|split-skill|claude-opus-4-7":5,"skill|split-skill|claude-sonnet-4-6":5}'

_sc_model_out=$(CLAUDII_CACHE_DIR="$_SC_MODEL_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 2>&1)
assert_contains "skills-cost model: dominant row shows label" "Opus 4.7" "$_sc_model_out"
_sc_model_split=$(printf '%s\n' "$_sc_model_out" | grep 'split-skill' || true)
assert_contains "skills-cost model: split row shows mixed" "mixed" "$_sc_model_split"

# JSON mode carries the raw dominant model id (machine-readable, not the label)
_sc_model_json=$(CLAUDII_CACHE_DIR="$_SC_MODEL_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_model_dom=$(jq -r '.rows[] | select(.name == "dominant-skill") | .model' <<< "$_sc_model_json" 2>/dev/null)
assert_eq "skills-cost --json: dominant model is raw id" "claude-opus-4-7" "$_sc_model_dom"
_sc_model_mix=$(jq -r '.rows[] | select(.name == "split-skill") | .model' <<< "$_sc_model_json" 2>/dev/null)
assert_eq "skills-cost --json: split model is mixed" "mixed" "$_sc_model_mix"

# ── Test 11: per-model pricing (schema v5) — opus costs 5×, haiku ⅓ of sonnet ─
# Each skill runs 1M input tokens on exactly one model. Priced at that model's
# own input rate (Opus $5/M, Sonnet $3/M, Haiku $1/M, Fable $10/M), 1M tokens
# costs exactly the per-MTok price. attribution_models carries the v5 per-model
# token objects; attribution_skills aggregate matches (residual = 0).
_SC_PM_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_PM_CACHE")
mkdir -p "$_SC_PM_CACHE/insights"
_sc_write_fixture "$_SC_PM_CACHE/insights/sess-pm.json" \
  '{"opus-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"sonnet-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"haiku-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"fable-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0}}' \
  '{}' '{}' \
  '{"skill|opus-skill|claude-opus-4-8":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|sonnet-skill|claude-sonnet-4-6":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|haiku-skill|claude-haiku-4-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|fable-skill|claude-fable-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0}}'

_sc_pm_json=$(CLAUDII_CACHE_DIR="$_SC_PM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_pm_opus=$(jq -r '.rows[] | select(.name=="opus-skill")   | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_sonnet=$(jq -r '.rows[] | select(.name=="sonnet-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_haiku=$(jq -r '.rows[] | select(.name=="haiku-skill")  | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_fable=$(jq -r '.rows[] | select(.name=="fable-skill")  | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
# 1M input tokens → exactly the per-MTok input price (compare rounded to cents)
assert_eq "skills-cost per-model: opus-skill priced at \$5/M"   "5.00"  "$(awk -v v="$_sc_pm_opus"   'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: sonnet-skill priced at \$3/M" "3.00"  "$(awk -v v="$_sc_pm_sonnet" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: haiku-skill priced at \$1/M"  "1.00"  "$(awk -v v="$_sc_pm_haiku"  'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: fable-skill priced at \$10/M" "10.00" "$(awk -v v="$_sc_pm_fable"  'BEGIN{printf "%.2f", v}')"

# ── Test 12: residual pricing — pre-v5 tokens (no per-model split) → Sonnet ───
# Aggregate in_tok 1M; attribution_models covers only 600K on opus (v5), leaving
# a 400K residual with no per-model attribution (the orphaned-v4 case). Cost =
# 600K×$5/M (opus) + 400K×$3/M (sonnet residual) = $3.00 + $1.20 = $4.20.
_SC_RES_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_RES_CACHE")
mkdir -p "$_SC_RES_CACHE/insights"
_sc_write_fixture "$_SC_RES_CACHE/insights/sess-res.json" \
  '{"mixed-skill":{"calls":2,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0}}' \
  '{}' '{}' \
  '{"skill|mixed-skill|claude-opus-4-8":{"calls":1,"in_tok":600000,"out_tok":0,"cache_read":0,"cache_create":0}}'

_sc_res_json=$(CLAUDII_CACHE_DIR="$_SC_RES_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_res_tot=$(jq -r '.rows[] | select(.name=="mixed-skill") | .tot_usd' <<< "$_sc_res_json" 2>/dev/null)
assert_eq "skills-cost residual: 600K opus + 400K sonnet residual == \$4.20" "4.20" \
  "$(awk -v v="$_sc_res_tot" 'BEGIN{printf "%.2f", v}')"

# ── Test 13: --compare BEFORE:AFTER trend view (two windows) ──────────────────
# Prior window [now-60, now-30): explore 10 calls @ 1200 out/call. Recent window
# [now-30, now]: explore 10 calls @ 800 out/call. out/call is the headline metric;
# Δ must be -400 (less output after a hypothetical SKILL.md edit).
_SC_CMP_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_CMP_CACHE")
mkdir -p "$_SC_CMP_CACHE/insights"
_sc_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if date -v -1d +%Y-%m-%d >/dev/null 2>&1; then
  _sc_prior_ts=$(date -u -v-45d +%Y-%m-%dT%H:%M:%SZ)
else
  _sc_prior_ts=$(date -u -d "45 days ago" +%Y-%m-%dT%H:%M:%SZ)
fi
_sc_cmp_common='schema_version:5,messages:1,assistant_messages:1,sidechain_msgs:0,thinking_blocks:0,limit_hits:[],snapshots:0,days:{},models:{},tools:{},tool_errors:{},stop_reasons:{},subagent_types:{},permission_modes:{},service_tier:{},attribution_plugins:{},attribution_mcp:{}'
jq -n --arg ls "$_sc_now" "{sessionId:\"r\",last_seen:\$ls,$_sc_cmp_common,attribution_skills:{explore:{calls:10,in_tok:1000,out_tok:8000,cache_read:0,cache_create:0}},attribution_models:{\"skill|explore|claude-opus-4-8\":{calls:10,in_tok:1000,out_tok:8000,cache_read:0,cache_create:0}}}" \
  > "$_SC_CMP_CACHE/insights/r.json"
jq -n --arg ls "$_sc_prior_ts" "{sessionId:\"p\",last_seen:\$ls,$_sc_cmp_common,attribution_skills:{explore:{calls:10,in_tok:1000,out_tok:12000,cache_read:0,cache_create:0}},attribution_models:{\"skill|explore|claude-opus-4-8\":{calls:10,in_tok:1000,out_tok:12000,cache_read:0,cache_create:0}}}" \
  > "$_SC_CMP_CACHE/insights/p.json"

_sc_cmp_out=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 2>&1)
_sc_cmp_rc=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 >/dev/null 2>&1; echo $?)
assert_eq       "skills-cost --compare: exit 0"            "0"              "$_sc_cmp_rc"
assert_contains "skills-cost --compare: header shown"      "prior 30d"      "$_sc_cmp_out"
assert_contains "skills-cost --compare: explore row"       "explore"        "$_sc_cmp_out"
assert_contains "skills-cost --compare: out/call prior→recent" "1200 → 800" "$_sc_cmp_out"
assert_contains "skills-cost --compare: context-robust note" "context-robust" "$_sc_cmp_out"

_sc_cmp_json=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 --json 2>&1)
assert_eq "skills-cost --compare --json: valid JSON" "0" "$(jq -e . <<< "$_sc_cmp_json" >/dev/null 2>&1; echo $?)"
assert_eq "skills-cost --compare --json: out_per_call_prior == 1200" "1200" \
  "$(jq -r '.rows[] | select(.name=="explore") | .out_per_call_prior' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: out_per_call_recent == 800" "800" \
  "$(jq -r '.rows[] | select(.name=="explore") | .out_per_call_recent' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: out_per_call_delta == -400" "-400" \
  "$(jq -r '.rows[] | select(.name=="explore") | .out_per_call_delta' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: before_days == 30" "30" \
  "$(jq -r '.compare.before_days' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: metric documents context-robustness" "0" \
  "$(jq -e '.metric | test("context-robust")' <<< "$_sc_cmp_json" >/dev/null 2>&1; echo $?)"

# Error paths
_sc_cmp_bad=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare foo 2>&1; echo "rc=$?")
assert_contains "skills-cost --compare foo: actionable error" "BEFORE:AFTER" "$_sc_cmp_bad"
assert_contains "skills-cost --compare foo: exit 1" "rc=1" "$_sc_cmp_bad"
_sc_cmp_zero=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 0:30 2>&1; echo "rc=$?")
assert_contains "skills-cost --compare 0:30: rejected (exit 1)" "rc=1" "$_sc_cmp_zero"

# Regression: --compare --json on an empty cache must still be valid JSON with
# rows:[] (session-close Phase 2.7 parses it) — an early text-only return here
# broke the contract.
_SC_CMPE_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_CMPE_CACHE")
mkdir -p "$_SC_CMPE_CACHE/insights"
_sc_cmpe_json=$(CLAUDII_CACHE_DIR="$_SC_CMPE_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 --json 2>&1)
assert_eq "skills-cost --compare --json empty: valid JSON" "0" \
  "$(jq -e . <<< "$_sc_cmpe_json" >/dev/null 2>&1; echo $?)"
assert_eq "skills-cost --compare --json empty: rows is []" "0" \
  "$(jq -e '.rows | length == 0' <<< "$_sc_cmpe_json" >/dev/null 2>&1; echo $?)"
# Text mode on empty windows: friendly line, no crash
_sc_cmpe_txt=$(CLAUDII_CACHE_DIR="$_SC_CMPE_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 2>&1)
assert_contains "skills-cost --compare empty: no-comparable-activity line" "No comparable" "$_sc_cmpe_txt"

unset _sc_now _sc_prior_ts _sc_cmp_common _sc_cmp_out _sc_cmp_rc _sc_cmp_json _sc_cmp_bad _sc_cmp_zero _sc_cmpe_json _sc_cmpe_txt
unset _sc_pm_json _sc_pm_opus _sc_pm_sonnet _sc_pm_haiku _sc_pm_fable _sc_res_json _sc_res_tot
unset _SC_TMPDIRS _sc_empty_out _sc_empty_rc _sc_out _sc_rc _sc_outlier_out _sc_outlier_rc \
      _sc_flag_count _sc_no_skills _sc_plugins_out _sc_plugins_rc _sc_json_out _sc_json_rc \
      _sc_jq_rc _sc_has_median _sc_has_days _sc_json_7d _sc_days_val _sc_dispatch_out _sc_dispatch_rc \
      _sc_bad_out _sc_zero_out _sc_mcp_out _sc_mcp_rc _sc_mcp_prefix _sc_mcp_skills \
      _sc_model_out _sc_model_split _sc_model_json _sc_model_dom _sc_model_mix
