# touches: lib/cmd/skills-cost.sh lib/skills-cost-rows.jq lib/skills-cost-compare.jq lib/tier.jq lib/insights.jq bin/claudii-insights bin/claudii completions/_claudii man/man1/claudii.1 CHANGELOG.md

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
  # Defaults must NOT inline a brace in the default-word (${n:-{\}}): macOS
  # /bin/bash 3.2 — what CI macos-latest runs — keeps the backslash literally
  # ({\}), so jq below gets invalid JSON and the fixture comes out empty;
  # homebrew bash 5.x strips it ({}), so it passed locally and only CI went red.
  # Resolve the default as a plain quoted literal instead — unambiguous on 3.2+.
  local skills_json="${2:-}";  [[ -n "$skills_json"  ]] || skills_json='{}'
  local plugins_json="${3:-}"; [[ -n "$plugins_json" ]] || plugins_json='{}'
  local mcp_json="${4:-}";     [[ -n "$mcp_json"     ]] || mcp_json='{}'
  local models_json="${5:-}";  [[ -n "$models_json"  ]] || models_json='{}'
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

# ── bash 3.2 portability guard ───────────────────────────────────────────────
# CI macos-latest runs /bin/bash 3.2; local `bash tests/run.sh` uses homebrew
# bash 5.x. Default-arg quirks (see _sc_write_fixture) therefore pass locally and
# only surface on CI — that exact gap shipped this file red. Re-run the REAL
# helper under /bin/bash with mcp/models omitted (the default path) so a
# 3.2-only regression fails here too. `declare -f` emits portable function text.
if [[ -x /bin/bash ]]; then
  _SC_B32_OUT="$(mktemp)"; _SC_TMPDIRS+=("$_SC_B32_OUT")
  {
    printf '%s\n' '_SC_LAST_SEEN="2026-01-01T00:00:00Z"'
    declare -f _sc_write_fixture
    printf '%s\n' "_sc_write_fixture \"$_SC_B32_OUT\" '{\"x\":{\"calls\":1,\"in_tok\":1,\"out_tok\":1,\"cache_read\":0,\"cache_create\":0}}' '{}'"
  } | /bin/bash 2>/dev/null
  _sc_b32_rc=$(jq -e '.attribution_mcp == {} and .attribution_models == {} and .attribution_skills.x.calls == 1' \
    "$_SC_B32_OUT" >/dev/null 2>&1; echo $?)
  assert_eq "skills-cost fixture: omitted args build valid JSON under /bin/bash 3.2" "0" "$_sc_b32_rc"
  unset _SC_B32_OUT _sc_b32_rc
fi

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

# --json mode computes the outlier flag in jq (not a per-row awk fork). Lock the
# value against the same fixture: expensive-skill true, a sub-threshold skill false.
_sc_outlier_json=$(CLAUDII_CACHE_DIR="$_SC_OUTLIER_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_oj_exp=$(jq -r '.rows[] | select(.name=="expensive-skill") | .outlier' <<< "$_sc_outlier_json" 2>/dev/null)
assert_eq "skills-cost --json: expensive-skill outlier=true" "true" "$_sc_oj_exp"
_sc_oj_cheap=$(jq -r '.rows[] | select(.name=="cheap-skill") | .outlier' <<< "$_sc_outlier_json" 2>/dev/null)
assert_eq "skills-cost --json: cheap-skill outlier=false" "false" "$_sc_oj_cheap"
_sc_oj_rare=$(jq -r '.rows[] | select(.name=="rare-expensive") | .outlier' <<< "$_sc_outlier_json" 2>/dev/null)
assert_eq "skills-cost --json: rare-expensive blocked by calls floor (false)" "false" "$_sc_oj_rare"

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
assert_contains "skills-cost --days abc: exit 2" "rc=2" "$_sc_bad_out"
_sc_zero_out=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --days 0 2>&1; echo "rc=$?")
assert_contains "skills-cost --days 0: rejected (exit 2)" "rc=2" "$_sc_zero_out"

# ── Window vocabulary: skills-cost shares _insights_window with tokens/tools ──
# It used to hand-roll --days only; `skills-cost month` was an "unknown flag".
_sc_win_out=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost month --json 2>&1)
assert_eq "skills-cost month: named window resolves to 30 days" "30" \
  "$(jq -r '.meta.days' <<< "$_sc_win_out" 2>/dev/null)"
_sc_win90=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 90d --json 2>&1)
assert_eq "skills-cost 90d: <N>d window resolves to 90 days" "90" \
  "$(jq -r '.meta.days' <<< "$_sc_win90" 2>/dev/null)"
_sc_windef=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
assert_eq "skills-cost (no window): default stays 30, not the shared 7" "30" \
  "$(jq -r '.meta.days' <<< "$_sc_windef" 2>/dev/null)"
_sc_win14=$(CLAUDII_CACHE_DIR="$_SC_JSON_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost 14 2>&1; echo "rc=$?")
assert_contains "skills-cost 14: bare number is a window typo, not an unknown flag" \
  "did you mean 14d" "$_sc_win14"
unset _sc_win_out _sc_win90 _sc_windef _sc_win14

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

# ── Test 11: per-model pricing (schema v5) — every tier at its own rate ───────
# Each skill runs 1M input tokens on exactly one model. Priced at that model's
# own input rate (Opus $5/M, Sonnet 5 $2/M, legacy Sonnet 4.x $3/M, Haiku 4.x $1/M,
# Fable $10/M), 1M tokens costs exactly the per-MTok price. The 4.6-vs-5 pair
# pins the version-aware sonnet split in lib/tier.jq (first in-tier price
# change). attribution_models carries the v5 per-model token objects;
# attribution_skills aggregate matches (residual = 0).
# The two cache-read rows pin the second in-tier split, Fable 5.1: it shares
# Fable 5's $10/$50 in/out, so only a cache_read row tells the rates apart
# ($0.25/M vs $1/M) — priced off in_tok both read $10.00 and a collapsed
# lib/tier.jq branch would pass unnoticed.
# opus55(cr)-skill pin the third in-tier split, Opus 5.5: it's the INVERSE of
# the sonnet/fable pattern — the NEW price ($4/M in, 5% cache read) gets the
# refined "opus-5-5" key while the bare "opus" key keeps pricing every older
# opus id. Both an in_tok row ($4 vs $5/M) and a cache_read row (5% vs 10%,
# i.e. $0.20 vs $0.50/M) are needed — in/out alone wouldn't catch a collapsed
# cache-read column.
_SC_PM_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_PM_CACHE")
mkdir -p "$_SC_PM_CACHE/insights"
_sc_write_fixture "$_SC_PM_CACHE/insights/sess-pm.json" \
  '{"opus-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"opus55-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"opus55cr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"opuscr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"opus55out-skill":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"opus55cc-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000},"sonnet-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"sonnet5-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"haiku-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"fable-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"fable51cr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"fablecr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"haiku55-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"haiku55cr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"sonnet55cr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"sonnet5cr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"haiku55out-skill":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"haiku55cc-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000},"haikuout-skill":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"sonnet55-skill":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"sonnet55out-skill":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"sonnet55cc-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000},"haikucr-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"haikucc-skill":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000}}' \
  '{}' '{}' \
  '{"skill|opus-skill|claude-opus-4-8":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|opus55-skill|claude-opus-5-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|opus55cr-skill|claude-opus-5-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|opuscr-skill|claude-opus-4-8":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|opus55out-skill|claude-opus-5-5":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"skill|opus55cc-skill|claude-opus-5-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000},"skill|sonnet-skill|claude-sonnet-4-6":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|sonnet5-skill|claude-sonnet-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|haiku-skill|claude-haiku-4-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|fable-skill|claude-fable-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|fable51cr-skill|claude-fable-5-1":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|fablecr-skill|claude-fable-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|haiku55-skill|claude-haiku-5-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|haiku55cr-skill|claude-haiku-5-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|sonnet55cr-skill|claude-sonnet-5-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|sonnet5cr-skill|claude-sonnet-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|haiku55out-skill|claude-haiku-5-5":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"skill|haiku55cc-skill|claude-haiku-5-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000},"skill|haikuout-skill|claude-haiku-4-5":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"skill|sonnet55-skill|claude-sonnet-5-5":{"calls":1,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|sonnet55out-skill|claude-sonnet-5-5":{"calls":1,"in_tok":0,"out_tok":1000000,"cache_read":0,"cache_create":0},"skill|sonnet55cc-skill|claude-sonnet-5-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000},"skill|haikucr-skill|claude-haiku-4-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":1000000,"cache_create":0},"skill|haikucc-skill|claude-haiku-4-5":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000}}'

_sc_pm_json=$(CLAUDII_CACHE_DIR="$_SC_PM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_pm_opus=$(jq -r '.rows[] | select(.name=="opus-skill")   | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_opus55=$(jq -r '.rows[] | select(.name=="opus55-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_sonnet=$(jq -r '.rows[] | select(.name=="sonnet-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_sonnet5=$(jq -r '.rows[] | select(.name=="sonnet5-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_haiku=$(jq -r '.rows[] | select(.name=="haiku-skill")  | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_fable=$(jq -r '.rows[] | select(.name=="fable-skill")  | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
# 1M input tokens → exactly the per-MTok input price (compare rounded to cents)
assert_eq "skills-cost per-model: opus-skill priced at \$5/M"   "5.00"  "$(LC_ALL=C awk -v v="$_sc_pm_opus"   'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: opus-5-5 priced at \$4/M"     "4.00"  "$(LC_ALL=C awk -v v="$_sc_pm_opus55" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: sonnet-4-6 priced at legacy \$3/M" "3.00"  "$(LC_ALL=C awk -v v="$_sc_pm_sonnet" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: sonnet-5 priced at \$2/M" "2.00"  "$(LC_ALL=C awk -v v="$_sc_pm_sonnet5" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: haiku-4-5 priced at legacy \$1/M"  "1.00"  "$(LC_ALL=C awk -v v="$_sc_pm_haiku"  'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: fable-skill priced at \$10/M" "10.00" "$(LC_ALL=C awk -v v="$_sc_pm_fable"  'BEGIN{printf "%.2f", v}')"
# 1M cache-read tokens → the tier's cache-read price, which is where Fable 5.1
# and Fable 5 diverge (rounded to cents: $0.25 vs $1.00), and separately where
# Opus 5.5 and older Opus diverge ($0.20 vs $0.50 — 5% vs the usual 10%).
_sc_pm_f51cr=$(jq -r '.rows[] | select(.name=="fable51cr-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_f5cr=$(jq -r '.rows[] | select(.name=="fablecr-skill")   | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_o55cr=$(jq -r '.rows[] | select(.name=="opus55cr-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_ocr=$(jq -r '.rows[] | select(.name=="opuscr-skill")     | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
assert_eq "skills-cost per-model: fable-5-1 cache read at \$0.25/M" "0.25" "$(LC_ALL=C awk -v v="$_sc_pm_f51cr" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: fable-5 cache read at legacy \$1/M" "1.00" "$(LC_ALL=C awk -v v="$_sc_pm_f5cr"  'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: opus-5-5 cache read at \$0.20/M" "0.20" "$(LC_ALL=C awk -v v="$_sc_pm_o55cr" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: opus cache read at \$0.50/M"    "0.50" "$(LC_ALL=C awk -v v="$_sc_pm_ocr"   'BEGIN{printf "%.2f", v}')"
# opus-5-5's "out" and "cc" (cache_create) columns aren't exercised by any row
# above (all use in_tok or cache_read) — pin them directly so a typo in either
# rate ("out":0.00002, "cc":0.000005) doesn't pass silently.
_sc_pm_o55out=$(jq -r '.rows[] | select(.name=="opus55out-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_o55cc=$(jq -r '.rows[] | select(.name=="opus55cc-skill")   | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
assert_eq "skills-cost per-model: opus-5-5 output at \$20/M" "20.00" "$(LC_ALL=C awk -v v="$_sc_pm_o55out" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: opus-5-5 cache create at \$5/M" "5.00" "$(LC_ALL=C awk -v v="$_sc_pm_o55cc" 'BEGIN{printf "%.2f", v}')"
# Haiku 5.5 ($0.10/M in, $0.01/M cache read) vs Haiku 4.5 above ($1/M), and
# Sonnet 5.5's 5% cache read ($0.10/M) vs Sonnet 5's 10% ($0.20/M). %.3f on
# the haiku cache read: at cents it would collapse $0.01 vs a stale $0.10.
_sc_pm_h55=$(jq -r '.rows[] | select(.name=="haiku55-skill")    | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_h55cr=$(jq -r '.rows[] | select(.name=="haiku55cr-skill")  | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_s55cr=$(jq -r '.rows[] | select(.name=="sonnet55cr-skill") | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
_sc_pm_s5cr=$(jq -r '.rows[] | select(.name=="sonnet5cr-skill")   | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null)
assert_eq "skills-cost per-model: haiku-5-5 priced at \$0.10/M" "0.100" "$(LC_ALL=C awk -v v="$_sc_pm_h55" 'BEGIN{printf "%.3f", v}')"
assert_eq "skills-cost per-model: haiku-5-5 cache read at \$0.01/M" "0.010" "$(LC_ALL=C awk -v v="$_sc_pm_h55cr" 'BEGIN{printf "%.3f", v}')"
assert_eq "skills-cost per-model: sonnet-5-5 cache read at \$0.10/M" "0.10" "$(LC_ALL=C awk -v v="$_sc_pm_s55cr" 'BEGIN{printf "%.2f", v}')"
assert_eq "skills-cost per-model: sonnet-5 cache read at \$0.20/M" "0.20" "$(LC_ALL=C awk -v v="$_sc_pm_s5cr" 'BEGIN{printf "%.2f", v}')"
# The remaining columns of both new rates, and haiku-legacy's output — every
# column a typo could hit gets one bucket that differs from its neighbours.
_sc_pm_cell() { jq -r --arg n "$1" '.rows[] | select(.name==$n) | .tot_usd' <<< "$_sc_pm_json" 2>/dev/null | LC_ALL=C awk '{printf "%.4f", $1}'; }
assert_eq "skills-cost per-model: haiku-5-5 output at \$0.50/M"        "0.5000"  "$(_sc_pm_cell haiku55out-skill)"
assert_eq "skills-cost per-model: haiku-5-5 cache create at \$0.125/M" "0.1250"  "$(_sc_pm_cell haiku55cc-skill)"
assert_eq "skills-cost per-model: haiku-4-5 output at legacy \$5/M"    "5.0000"  "$(_sc_pm_cell haikuout-skill)"
assert_eq "skills-cost per-model: haiku-4-5 cache read at legacy \$0.10/M"    "0.1000" "$(_sc_pm_cell haikucr-skill)"
assert_eq "skills-cost per-model: haiku-4-5 cache create at legacy \$1.25/M"  "1.2500" "$(_sc_pm_cell haikucc-skill)"
assert_eq "skills-cost per-model: sonnet-5-5 input at \$2/M"           "2.0000"  "$(_sc_pm_cell sonnet55-skill)"
assert_eq "skills-cost per-model: sonnet-5-5 output at \$10/M"         "10.0000" "$(_sc_pm_cell sonnet55out-skill)"
assert_eq "skills-cost per-model: sonnet-5-5 cache create at \$2.50/M" "2.5000"  "$(_sc_pm_cell sonnet55cc-skill)"
unset -f _sc_pm_cell

# ── Test 12: residual pricing — pre-v5 tokens (no per-model split) → Sonnet ───
# Aggregate in_tok 1M; attribution_models covers only 600K on opus (v5), leaving
# a 400K residual with no per-model attribution (the orphaned-v4 case). Cost =
# 600K×$5/M (opus) + 400K×$3/M (sonnet residual) = $3.00 + $1.20 = $4.20.
# mixed1h-skill: the same shape for 1-hour cache writes (schema v11
# cache_create_1h) — 600K on opus at the 1h rate ($10/M) + a 400K 1h residual
# at the legacy-Sonnet 1h rate ($6/M) = $6.00 + $2.40 = $8.40. Billing the
# residual at the 5m rate would read $7.50, counting it twice $9.90.
_SC_RES_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_RES_CACHE")
mkdir -p "$_SC_RES_CACHE/insights"
_sc_write_fixture "$_SC_RES_CACHE/insights/sess-res.json" \
  '{"mixed-skill":{"calls":2,"in_tok":1000000,"out_tok":0,"cache_read":0,"cache_create":0},"mixed1h-skill":{"calls":2,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":1000000,"cache_create_1h":1000000}}' \
  '{}' '{}' \
  '{"skill|mixed-skill|claude-opus-4-8":{"calls":1,"in_tok":600000,"out_tok":0,"cache_read":0,"cache_create":0},"skill|mixed1h-skill|claude-opus-4-8":{"calls":1,"in_tok":0,"out_tok":0,"cache_read":0,"cache_create":600000,"cache_create_1h":600000}}'

_sc_res_json=$(CLAUDII_CACHE_DIR="$_SC_RES_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_res_tot=$(jq -r '.rows[] | select(.name=="mixed-skill") | .tot_usd' <<< "$_sc_res_json" 2>/dev/null)
assert_eq "skills-cost residual: 600K opus + 400K sonnet residual == \$4.20" "4.20" \
  "$(LC_ALL=C awk -v v="$_sc_res_tot" 'BEGIN{printf "%.2f", v}')"
_sc_res_1h=$(jq -r '.rows[] | select(.name=="mixed1h-skill") | .tot_usd' <<< "$_sc_res_json" 2>/dev/null)
assert_eq "skills-cost residual: 1h writes — 600K opus + 400K sonnet residual, both at 1h rates == \$8.40" "8.40" \
  "$(LC_ALL=C awk -v v="$_sc_res_1h" 'BEGIN{printf "%.2f", v}')"

# ── Test 13: --compare BEFORE:AFTER trend view (two windows) ──────────────────
# Prior window [now-60, now-30): explore 10 calls @ 1200 out/call. Recent window
# [now-30, now]: explore 10 calls @ 800 out/call. out/call is the headline metric;
# Δ must be -400 (less output after a hypothetical SKILL.md edit).
_SC_CMP_CACHE="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_CMP_CACHE")
mkdir -p "$_SC_CMP_CACHE/insights"
# Pin "now" via CLAUDII_NOW (the merge-cutoff seam bin/claudii-insights and
# _window_cutoffs both read — claudii#5 follow-up) instead of the live clock:
# this is the same merge machinery test_limits.sh pins, and the prior/recent
# fixtures below are windowed off "now" the identical way. Anchor value is
# arbitrary (no assertion here cares about the actual calendar date).
_sc_cmp_now=1782388800   # 2026-06-25T12:00:00Z
_sc_now=$(date -u -d "@$_sc_cmp_now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -r "$_sc_cmp_now" +%Y-%m-%dT%H:%M:%SZ)
_sc_prior_ts=$(date -u -d "@$(( _sc_cmp_now - 45 * 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -r "$(( _sc_cmp_now - 45 * 86400 ))" +%Y-%m-%dT%H:%M:%SZ)
_sc_cmp_common='schema_version:5,messages:1,assistant_messages:1,sidechain_msgs:0,thinking_blocks:0,limit_hits:[],snapshots:0,days:{},models:{},tools:{},tool_errors:{},stop_reasons:{},subagent_types:{},permission_modes:{},service_tier:{},attribution_plugins:{},attribution_mcp:{}'
# The recent window also writes 1M tokens to the 1-hour cache (schema v11
# cache_create_1h), so the compare program's pricing is pinned too: 1000 in ×
# $5/M + 8000 out × $25/M + 1M × $10/M (opus 1h write) = $10.205 over 10
# calls. At the 5m write rate it would read $0.6455/call.
jq -n --arg ls "$_sc_now" "{sessionId:\"r\",last_seen:\$ls,$_sc_cmp_common,attribution_skills:{explore:{calls:10,in_tok:1000,out_tok:8000,cache_read:0,cache_create:1000000,cache_create_1h:1000000}},attribution_models:{\"skill|explore|claude-opus-4-8\":{calls:10,in_tok:1000,out_tok:8000,cache_read:0,cache_create:1000000,cache_create_1h:1000000}}}" \
  > "$_SC_CMP_CACHE/insights/r.json"
jq -n --arg ls "$_sc_prior_ts" "{sessionId:\"p\",last_seen:\$ls,$_sc_cmp_common,attribution_skills:{explore:{calls:10,in_tok:1000,out_tok:12000,cache_read:0,cache_create:0}},attribution_models:{\"skill|explore|claude-opus-4-8\":{calls:10,in_tok:1000,out_tok:12000,cache_read:0,cache_create:0}}}" \
  > "$_SC_CMP_CACHE/insights/p.json"

_sc_cmp_out=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" CLAUDII_NOW="$_sc_cmp_now" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 2>&1)
_sc_cmp_rc=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" CLAUDII_NOW="$_sc_cmp_now" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 >/dev/null 2>&1; echo $?)
assert_eq       "skills-cost --compare: exit 0"            "0"              "$_sc_cmp_rc"
assert_contains "skills-cost --compare: header shown"      "prior 30d"      "$_sc_cmp_out"
assert_contains "skills-cost --compare: explore row"       "explore"        "$_sc_cmp_out"
assert_contains "skills-cost --compare: out/call prior→recent" "1200 → 800" "$_sc_cmp_out"
assert_contains "skills-cost --compare: context-robust note" "context-robust" "$_sc_cmp_out"

_sc_cmp_json=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" CLAUDII_NOW="$_sc_cmp_now" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 30:30 --json 2>&1)
assert_eq "skills-cost --compare --json: valid JSON" "0" "$(jq -e . <<< "$_sc_cmp_json" >/dev/null 2>&1; echo $?)"
assert_eq "skills-cost --compare --json: out_per_call_prior == 1200" "1200" \
  "$(jq -r '.rows[] | select(.name=="explore") | .out_per_call_prior' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: out_per_call_recent == 800" "800" \
  "$(jq -r '.rows[] | select(.name=="explore") | .out_per_call_recent' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: out_per_call_delta == -400" "-400" \
  "$(jq -r '.rows[] | select(.name=="explore") | .out_per_call_delta' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: before_days == 30" "30" \
  "$(jq -r '.compare.before_days' <<< "$_sc_cmp_json" 2>/dev/null)"
assert_eq "skills-cost --compare --json: 1h cache writes priced at the 1h rate (avg \$1.0205)" "1.0205" \
  "$(jq -r '.rows[] | select(.name=="explore") | .avg_usd_recent' <<< "$_sc_cmp_json" 2>/dev/null | LC_ALL=C awk '{printf "%.4f", $1}')"
assert_eq "skills-cost --compare --json: metric documents context-robustness" "0" \
  "$(jq -e '.metric | test("context-robust")' <<< "$_sc_cmp_json" >/dev/null 2>&1; echo $?)"

# Error paths
_sc_cmp_bad=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare foo 2>&1; echo "rc=$?")
assert_contains "skills-cost --compare foo: actionable error" "BEFORE:AFTER" "$_sc_cmp_bad"
assert_contains "skills-cost --compare foo: exit 2" "rc=2" "$_sc_cmp_bad"
_sc_cmp_zero=$(CLAUDII_CACHE_DIR="$_SC_CMP_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 0:30 2>&1; echo "rc=$?")
assert_contains "skills-cost --compare 0:30: rejected (exit 2)" "rc=2" "$_sc_cmp_zero"

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

# ── Test 14: cache writes priced by TTL (insights schema v11), end to end ─────
# Claude Code writes the main conversation to the 1-hour prompt cache (2×
# input) and subagents to the 5-minute one (1.25×); usage.cache_creation
# carries the split. Transcript → claudii-insights aggregate → merge →
# skills-cost, so the split has to survive every stage. Opus 5.5 ($4/M in →
# 5m $5/M, 1h $8/M); each skill only writes 1M cache tokens, so its tot_usd
# is the write price alone:
#   ttl1h    1M to the 1h cache                → $8.00 (2×)
#   ttl5m    1M to the 5m cache                → $5.00 (1.25×)
#   ttlmix   250K 5m + 750K 1h                 → $1.25 + $6.00 = $7.25
#   ttlbare  1M total, no cache_creation split → $5.00 (5m rate, as before v11)
_SC_TTL="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_TTL")
mkdir -p "$_SC_TTL/proj/p" "$_SC_TTL/cache"
_sc_ttl_rec() {  # <skill> [cache_creation JSON] → one assistant record
  jq -cn --arg s "$1" --arg ts "$_SC_LAST_SEEN" --argjson cc "${2:-null}" \
    '{type:"assistant", timestamp:$ts, sessionId:"ttl-sess", attributionSkill:$s,
      message:{role:"assistant", model:"claude-opus-5-5", content:[],
        usage:({input_tokens:0, output_tokens:0, cache_read_input_tokens:0,
                cache_creation_input_tokens:1000000}
               + (if $cc == null then {} else {cache_creation:$cc} end))}}'
}
{
  _sc_ttl_rec ttl1h-skill   '{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1000000}'
  _sc_ttl_rec ttl5m-skill   '{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":0}'
  _sc_ttl_rec ttlmix-skill  '{"ephemeral_5m_input_tokens":250000,"ephemeral_1h_input_tokens":750000}'
  _sc_ttl_rec ttlbare-skill
} > "$_SC_TTL/proj/p/ttl-sess.jsonl"
CLAUDE_PROJECTS_DIR="$_SC_TTL/proj" CLAUDII_CACHE_DIR="$_SC_TTL/cache" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
_sc_ttl_json=$(CLAUDII_CACHE_DIR="$_SC_TTL/cache" bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_ttl_cell() { jq -r --arg n "$1" '.rows[] | select(.name==$n) | .tot_usd' <<< "$_sc_ttl_json" 2>/dev/null | LC_ALL=C awk '{printf "%.4f", $1}'; }
assert_eq "skills-cost TTL: 1h-only write bills 2x input (\$8/M on Opus 5.5)"         "8.0000" "$(_sc_ttl_cell ttl1h-skill)"
assert_eq "skills-cost TTL: 5m-only write bills 1.25x input (\$5/M)"                  "5.0000" "$(_sc_ttl_cell ttl5m-skill)"
assert_eq "skills-cost TTL: mixed split bills each part at its own rate (\$7.25)"     "7.2500" "$(_sc_ttl_cell ttlmix-skill)"
assert_eq "skills-cost TTL: total without a split falls back to the 5m rate (\$5/M)"  "5.0000" "$(_sc_ttl_cell ttlbare-skill)"
assert_contains "skills-cost TTL: meta.pricing states the 1h rate" "2x for 1-hour" \
  "$(jq -r '.meta.pricing' <<< "$_sc_ttl_json" 2>/dev/null)"
# The write multipliers have no exceptions — Anthropic's pricing table bills
# 1.25× input (5m) and 2× (1h) on every model; the cache READ is the column
# that varies. Check them on every _rates row, so a typo in one tier's cc or
# cc1h goes red even where no bucket above prices that tier.
_sc_rates=$(sed -n "/^_CLAUDII_RATES='{/,/^}'/p" "$CLAUDII_HOME/lib/cmd/skills-cost.sh" \
  | sed -e "s/^_CLAUDII_RATES='{/{/" -e "s/^}'.*/}/")
assert_eq "skills-cost _rates: every tier writes at 1.25x (cc) and 2x (cc1h) input" "ok" \
  "$(jq -r 'if length == 0 then "no rows parsed"
            else [to_entries[] | select((.value.cc / .value.in - 1.25 | fabs) > 1e-9
                                        or (.value.cc1h / .value.in - 2 | fabs) > 1e-9) | .key]
                 | if length == 0 then "ok" else "off: " + join(", ") end end' <<< "$_sc_rates" 2>&1)"
unset -f _sc_ttl_rec _sc_ttl_cell
unset _SC_TTL _sc_ttl_json _sc_rates

# ── Test 15: one API response over several records bills once (schema v12) ──
# Claude Code writes an assistant message as one record per content block, all
# sharing message.id. Transcript → aggregate → merge → skills-cost, Opus 5.5
# ($4/M in, $20/M out):
#   multi-skill  msg_1, 3 records repeating input 1M → 1 call, $4 (was 3, $12)
#   alpha, beta  msg_2, output 8 then the final 1M, each MCP call in its own
#                record → $20 split in half, $10 each (was $0.00016 and $20)
_SC_MR="$(mktemp -d)"; _SC_TMPDIRS+=("$_SC_MR")
mkdir -p "$_SC_MR/proj/p" "$_SC_MR/cache"
_sc_mr_rec() {  # <msg id> <skill or ""> <in> <out> <content JSON> → one assistant record
  jq -cn --arg id "$1" --arg s "$2" --argjson in "$3" --argjson out "$4" --argjson c "$5" \
    --arg ts "$_SC_LAST_SEEN" \
    '{type:"assistant", timestamp:$ts, sessionId:"mr-sess", requestId:("req-" + $id)}
     + (if $s == "" then {} else {attributionSkill:$s} end)
     + {message:{id:$id, role:"assistant", model:"claude-opus-5-5", content:$c,
         usage:{input_tokens:$in, output_tokens:$out, cache_read_input_tokens:0,
                cache_creation_input_tokens:0}}}'
}
{
  _sc_mr_rec msg_1 multi-skill 1000000 0 '[{"type":"thinking","thinking":""}]'
  _sc_mr_rec msg_1 multi-skill 1000000 0 '[{"type":"text","text":"x"}]'
  _sc_mr_rec msg_1 multi-skill 1000000 0 '[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]'
  _sc_mr_rec msg_2 "" 0 8       '[{"type":"tool_use","id":"t2","name":"mcp__srv__alpha","input":{}}]'
  _sc_mr_rec msg_2 "" 0 1000000 '[{"type":"tool_use","id":"t3","name":"mcp__srv__beta","input":{}}]'
} > "$_SC_MR/proj/p/mr-sess.jsonl"
CLAUDE_PROJECTS_DIR="$_SC_MR/proj" CLAUDII_CACHE_DIR="$_SC_MR/cache" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
_sc_mr_json=$(CLAUDII_CACHE_DIR="$_SC_MR/cache" bash "$CLAUDII_HOME/bin/claudii" skills-cost --json 2>&1)
_sc_mr_mcp=$(CLAUDII_CACHE_DIR="$_SC_MR/cache" bash "$CLAUDII_HOME/bin/claudii" skills-cost --mcp --json 2>&1)
_sc_mr_cell() {  # <row name> <skills-cost JSON> → "calls usd"
  jq -r --arg n "$1" '.rows[] | select(.name==$n) | "\(.calls) \(.tot_usd)"' <<< "$2" 2>/dev/null \
    | LC_ALL=C awk '{printf "%d %.4f", $1, $2}'
}
assert_eq "skills-cost: a response over 3 records is 1 call, billed once (\$4)" "1 4.0000" \
  "$(_sc_mr_cell multi-skill "$_sc_mr_json")"
assert_eq "skills-cost --mcp: the final usage splits across the response's MCP calls (alpha \$10)" "1 10.0000" \
  "$(_sc_mr_cell mcp__srv__alpha "$_sc_mr_mcp")"
assert_eq "skills-cost --mcp: the final usage splits across the response's MCP calls (beta \$10)" "1 10.0000" \
  "$(_sc_mr_cell mcp__srv__beta "$_sc_mr_mcp")"
unset -f _sc_mr_rec _sc_mr_cell
unset _SC_MR _sc_mr_json _sc_mr_mcp

# ── Flag robustness: a value-flag as the LAST arg must not silently exit ──────
# `--compare` with no window consumed $@, then the loop's final `shift` tripped
# exit 1 under set -e — a silent failure with no output. Now: actionable message
# + rc 2 (the usage-error code).
#
# `--days` with no value used to fall back to the 30-day default and exit 0 —
# a silent lie, since the user clearly meant to narrow the window. Since the
# migration onto _insights_window it is the same "needs a value" error every
# other window command gives.
_sc_cmp_noarg=$(bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare 2>&1 || true)
assert_contains "skills-cost --compare (no arg): actionable message" "needs BEFORE:AFTER" "$_sc_cmp_noarg"
bash "$CLAUDII_HOME/bin/claudii" skills-cost --compare >/dev/null 2>&1 && _sc_cmp_narc=0 || _sc_cmp_narc=$?
assert_eq "skills-cost --compare (no arg): exits 2 (not a silent crash)" "2" "$_sc_cmp_narc"
_sc_d_nout=$(CLAUDII_CACHE_DIR="$_SC_CMPE_CACHE" bash "$CLAUDII_HOME/bin/claudii" skills-cost --days 2>&1; echo "rc=$?")
assert_contains "skills-cost --days (no value): actionable error, not a silent 30d fallback" \
  "needs a value" "$_sc_d_nout"
assert_contains "skills-cost --days (no value): exit 2" "rc=2" "$_sc_d_nout"
unset _sc_cmp_noarg _sc_cmp_narc _sc_d_nout

unset _sc_cmp_now _sc_now _sc_prior_ts _sc_cmp_common _sc_cmp_out _sc_cmp_rc _sc_cmp_json _sc_cmp_bad _sc_cmp_zero _sc_cmpe_json _sc_cmpe_txt
unset _sc_pm_json _sc_pm_opus _sc_pm_opus55 _sc_pm_sonnet _sc_pm_sonnet5 _sc_pm_haiku _sc_pm_fable _sc_pm_f51cr _sc_pm_f5cr _sc_pm_o55cr _sc_pm_ocr _sc_pm_o55out _sc_pm_o55cc _sc_pm_h55 _sc_pm_h55cr _sc_pm_s55cr _sc_pm_s5cr _sc_res_json _sc_res_tot _sc_res_1h
unset _SC_TMPDIRS _sc_empty_out _sc_empty_rc _sc_out _sc_rc _sc_outlier_out _sc_outlier_rc \
      _sc_flag_count _sc_no_skills _sc_plugins_out _sc_plugins_rc _sc_json_out _sc_json_rc \
      _sc_jq_rc _sc_has_median _sc_has_days _sc_json_7d _sc_days_val _sc_dispatch_out _sc_dispatch_rc _sc_d_narc \
      _sc_bad_out _sc_zero_out _sc_mcp_out _sc_mcp_rc _sc_mcp_prefix _sc_mcp_skills \
      _sc_model_out _sc_model_split _sc_model_json _sc_model_dom _sc_model_mix
