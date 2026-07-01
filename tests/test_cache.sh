# touches: lib/cmd/insights.sh bin/claudii-insights lib/insights.jq

# test_cache.sh — claudii cache (prompt-cache hit rate insights)
# Verifies that the JSONL aggregator + cache view work end-to-end against
# a synthetic project tree.

_CACHE_TMPDIRS=()
trap 'rm -rf "${_CACHE_TMPDIRS[@]}" 2>/dev/null' EXIT

_CACHE_PROJ="$(mktemp -d)"; _CACHE_TMPDIRS+=("$_CACHE_PROJ")
_CACHE_CACHE="$(mktemp -d)"; _CACHE_TMPDIRS+=("$_CACHE_CACHE")

mkdir -p "$_CACHE_PROJ/-test-project"

_SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_JSONL="$_CACHE_PROJ/-test-project/$_SID.jsonl"

# Two synthetic assistant messages — one Opus, one Sonnet — with controlled
# token counts. 950 / 1000 = 95% for Opus, 800 / 1000 = 80% for Sonnet.
{
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","permissionMode":"default","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":"tool_use","usage":{"input_tokens":40,"output_tokens":50,"cache_read_input_tokens":950,"cache_creation_input_tokens":10,"service_tier":"standard"},"content":[{"type":"tool_use","id":"x1","name":"Bash","input":{}}]}}\n' "$_TS" "$_SID"
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","permissionMode":"default","message":{"role":"assistant","model":"claude-sonnet-4-6","stop_reason":"end_turn","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":800,"cache_creation_input_tokens":100,"service_tier":"standard"},"content":[]}}\n' "$_TS" "$_SID"
} > "$_JSONL"

# Run claudii cache against the synthetic dirs.
_CACHE_OUT=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache 2>&1)
_CACHE_RC=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache >/dev/null 2>&1; echo $?)

assert_eq "cache: exit 0"            "0"               "$_CACHE_RC"
assert_eq "cache: produces output"   "0"               "$([ -z "$_CACHE_OUT" ] && echo 1 || echo 0)"
assert_no_literal_ansi "cache: no literal \\033 in output" "$_CACHE_OUT"
assert_contains "cache: header"            "claudii cache"      "$_CACHE_OUT"
assert_contains "cache: hit rate section"  "Cache hit rate"     "$_CACHE_OUT"
assert_contains "cache: per-model section" "By model"           "$_CACHE_OUT"
assert_contains "cache: opus label"        "Opus 4.7"           "$_CACHE_OUT"
assert_contains "cache: sonnet label"      "Sonnet 4.6"         "$_CACHE_OUT"
assert_contains "cache: today label"       "Today"              "$_CACHE_OUT"
assert_contains "cache: summary line"      "Saved:"             "$_CACHE_OUT"
assert_contains "cache: hit rate suffix"   "hit rate"           "$_CACHE_OUT"

# 95% Opus + 80% Sonnet weighted by total of 1000 each → 87.5% overall.
# Rounded display is "87.5%" — verify it's printed somewhere in the summary.
assert_contains "cache: overall hit rate ≈ 87.5%" "87.5%" "$_CACHE_OUT"

# Verify cache directory got populated.
assert_eq "cache: per-session JSON cache exists" "1" \
  "$([ -s "$_CACHE_CACHE/insights/$_SID.json" ] && echo 1 || echo 0)"

# ── Custom --days override is honoured ────────────────────────────────────
_CACHE_OUT_30=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache --days 30 2>&1)
assert_contains "cache --days 30: window in section header" "30d" "$_CACHE_OUT_30"

# ── Cycleable named window: `cache 30d` == `cache --days 30` ──────────────
_CACHE_30D=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache 30d 2>&1)
assert_contains "cache 30d: named window resolves to 30-day header" "30d" "$_CACHE_30D"
_CACHE_BAD=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache bogus 2>&1; echo "rc=$?")
assert_contains "cache bogus: actionable unknown-arg error" "unknown cache argument: bogus" "$_CACHE_BAD"
assert_contains "cache bogus: exit 1" "rc=1" "$_CACHE_BAD"
unset _CACHE_30D _CACHE_BAD

# ── --json: structured output mirrors the rendered numbers ────────────────
# Opus cr=950/cc=10/in=40, Sonnet cr=800/cc=100/in=100 → read 1750, total 2000,
# hit 87.5% (same figure the pretty summary prints).
_CACHE_JSON=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache --json 2>&1)
assert_eq "cache --json: well-formed JSON" "0" \
  "$(printf '%s' "$_CACHE_JSON" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "cache --json: window_days=7" "7" \
  "$(printf '%s' "$_CACHE_JSON" | jq -r '.window_days')"
assert_eq "cache --json: summary.cache_read=1750" "1750" \
  "$(printf '%s' "$_CACHE_JSON" | jq -r '.summary.cache_read')"
assert_eq "cache --json: summary.hit_pct=87.5" "87.5" \
  "$(printf '%s' "$_CACHE_JSON" | jq -r '.summary.hit_pct')"
assert_eq "cache --json: two models (synthetic excluded)" "2" \
  "$(printf '%s' "$_CACHE_JSON" | jq -r '.per_model | length')"
_CACHE_TSV=$(CLAUDE_PROJECTS_DIR="$_CACHE_PROJ" CLAUDII_CACHE_DIR="$_CACHE_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache --tsv 2>&1; echo "rc=$?")
assert_contains "cache --tsv: rejected, points to --json" "use --json" "$_CACHE_TSV"
assert_contains "cache --tsv: exit 1" "rc=1" "$_CACHE_TSV"
unset _CACHE_JSON _CACHE_TSV

# ── Empty cache (no projects) renders the empty-state line ────────────────
_EMPTY_PROJ="$(mktemp -d)"; _CACHE_TMPDIRS+=("$_EMPTY_PROJ")
_EMPTY_CACHE="$(mktemp -d)"; _CACHE_TMPDIRS+=("$_EMPTY_CACHE")
_EMPTY_OUT=$(CLAUDE_PROJECTS_DIR="$_EMPTY_PROJ" CLAUDII_CACHE_DIR="$_EMPTY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache 2>&1)
assert_contains "cache (empty): empty-state message" "No insight data" "$_EMPTY_OUT"

# ── Malformed JSONL line is silently skipped, not fatal ───────────────────
_BAD_PROJ="$(mktemp -d)"; _CACHE_TMPDIRS+=("$_BAD_PROJ")
_BAD_CACHE="$(mktemp -d)"; _CACHE_TMPDIRS+=("$_BAD_CACHE")
mkdir -p "$_BAD_PROJ/-bad-project"
{
  printf 'not valid json{{{\n'                        # invalid JSON — skipped by fromjson?
  printf '%s\n' '"a bare valid-json string line"'      # valid JSON, non-object
  printf '%s\n' '42'                                   # valid JSON, non-object
  printf '%s\n' '[1,2,3]'                              # valid JSON, non-object (array)
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":"end_turn","usage":{"input_tokens":10,"cache_read_input_tokens":90,"cache_creation_input_tokens":0}}}\n' "$_TS" "$_SID"
} > "$_BAD_PROJ/-bad-project/$_SID.jsonl"
_BAD_RC=$(CLAUDE_PROJECTS_DIR="$_BAD_PROJ" CLAUDII_CACHE_DIR="$_BAD_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" cache >/dev/null 2>&1; echo $?)
assert_eq "cache (malformed + non-object lines): still exits 0" "0" "$_BAD_RC"
# The valid assistant line AFTER the non-object lines must still aggregate. A bare
# string/number/array line is valid JSON (fromjson? passes it) but used to abort the
# whole reduce with a type error before insights.jq's select(type=="object") guard.
_BAD_AM=$([ -s "$_BAD_CACHE/insights/$_SID.json" ] && jq -r '.assistant_messages // 0' "$_BAD_CACHE/insights/$_SID.json" 2>/dev/null || echo 0)
assert_eq "cache (non-object lines): assistant message still aggregated" "1" "$_BAD_AM"

# ── Model-label map: new + older versions all resolve (model-update guard) ──
# Source insights.sh (pure function defs, no side effects) to call the label fn
# directly. Adding a new model means adding a case here AND in
# _insights_model_label — keep them in lock-step. NOT a subshell: assert_eq
# increments the run.sh PASS/FAIL counters in the current scope.
source "$CLAUDII_HOME/lib/cmd/insights.sh" 2>/dev/null
assert_eq "label: fable 5 (latest)"   "Fable 5"    "$(_insights_model_label claude-fable-5)"
assert_eq "label: unknown fable->tier" "Fable"     "$(_insights_model_label claude-fable-9)"
assert_eq "label: opus 4.8 (latest)"  "Opus 4.8"   "$(_insights_model_label claude-opus-4-8)"
assert_eq "label: opus 4.7 (older)"   "Opus 4.7"   "$(_insights_model_label claude-opus-4-7)"
assert_eq "label: opus 4.6 (older)"   "Opus 4.6"   "$(_insights_model_label claude-opus-4-6)"
assert_eq "label: sonnet 5 (latest)"  "Sonnet 5"   "$(_insights_model_label claude-sonnet-5)"
assert_eq "label: sonnet 4.6 (older)" "Sonnet 4.6" "$(_insights_model_label claude-sonnet-4-6)"
assert_eq "label: haiku 4.5"          "Haiku 4.5"  "$(_insights_model_label claude-haiku-4-5)"
assert_eq "label: unknown opus->tier" "Opus"       "$(_insights_model_label claude-opus-9-9)"

unset _SID _TS _JSONL _CACHE_OUT _CACHE_RC _CACHE_OUT_30 _EMPTY_OUT _BAD_RC

# ── --days validation: bad value must error, not print "No insight data" ─────
# Regression: claudii-insights merge validates --days but _insights_merged_json
# swallows its stderr (2>/dev/null) — a bad value surfaced as the misleading
# "No insight data yet". _cmd_cache now validates before calling merge.
_dv_base=$(mktemp -d "${TMPDIR:-/tmp}/claudii_cache_days.XXXXXX")
mkdir -p "$_dv_base/xdg/claudii" "$_dv_base/cache" "$_dv_base/proj"
cp "$CLAUDII_HOME/config/defaults.json" "$_dv_base/xdg/claudii/config.json"
_dv_out=$(CLAUDE_PROJECTS_DIR="$_dv_base/proj" CLAUDII_CACHE_DIR="$_dv_base/cache" \
  XDG_CONFIG_HOME="$_dv_base/xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cache --days foo 2>&1; echo "rc=$?")
assert_contains "cache --days foo: actionable error" "positive integer" "$_dv_out"
assert_contains "cache --days foo: exit 1" "rc=1" "$_dv_out"
assert_not_contains "cache --days foo: no misleading no-data message" "No insight data" "$_dv_out"
rm -rf "$_dv_base"
unset _dv_base _dv_out

# ── Schema gate: orphaned old-schema caches must not force eternal rebuilds ──
# Regression: the gate took the min schema_version across ALL cache files;
# orphans (source JSONL deleted) could never be upgraded → every aggregate
# run since the v3 bump force-rebuilt all live sessions. The gate now uses a
# .schema marker written after the last successful rebuild.
_sg_base=$(mktemp -d "${TMPDIR:-/tmp}/claudii_schema_gate.XXXXXX")
mkdir -p "$_sg_base/proj/projA" "$_sg_base/cache/insights"
printf '{"type":"assistant","timestamp":"2026-06-01T10:00:00Z","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
  > "$_sg_base/proj/projA/sess-live.jsonl"
# Orphan: cache entry with an old schema and no source JSONL
printf '{"schema_version":2,"sessionId":"sess-orphan","last_seen":"2026-01-01T00:00:00Z"}\n' \
  > "$_sg_base/cache/insights/sess-orphan.json"

_sg_run1=$(CLAUDE_PROJECTS_DIR="$_sg_base/proj" CLAUDII_CACHE_DIR="$_sg_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate 2>&1)
_sg_run2=$(CLAUDE_PROJECTS_DIR="$_sg_base/proj" CLAUDII_CACHE_DIR="$_sg_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate 2>&1)
assert_contains     "schema gate: first run rebuilds (no marker yet)" "schema bump" "$_sg_run1"
assert_not_contains "schema gate: second run skips rebuild despite orphan" "schema bump" "$_sg_run2"
assert_contains     "schema gate: second run processes 0" "0 processed" "$_sg_run2"
rm -rf "$_sg_base"
unset _sg_base _sg_run1 _sg_run2

# ── Subagent ingestion through the aggregate path ────────────────────────────
# <proj>/<sid>/subagents/agent-*.jsonl must be fed into the parent's cache
# (attribution chain itself is covered in test_insights_attribution.sh) and a
# subagent-only mtime change must re-aggregate the parent.
_sa_base=$(mktemp -d "${TMPDIR:-/tmp}/claudii_subagent.XXXXXX")
mkdir -p "$_sa_base/proj/projA/sess-sub/subagents" "$_sa_base/cache/insights"
printf '%s\n' \
  '{"type":"assistant","timestamp":"2026-06-01T10:00:00Z","attributionSkill":"deploy","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":30,"output_tokens":15,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"tool_use","id":"tu1","name":"Agent","input":{"subagent_type":"Explore"}}]}}' \
  '{"type":"user","timestamp":"2026-06-01T10:01:00Z","toolUseResult":{"agentId":"subX","agentType":"Explore"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"done"}]}}' \
  > "$_sa_base/proj/projA/sess-sub.jsonl"
printf '{"type":"assistant","timestamp":"2026-06-01T10:00:30Z","agentId":"subX","isSidechain":true,"message":{"role":"assistant","model":"claude-haiku-4-5","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}\n' \
  > "$_sa_base/proj/projA/sess-sub/subagents/agent-subX.jsonl"

CLAUDE_PROJECTS_DIR="$_sa_base/proj" CLAUDII_CACHE_DIR="$_sa_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
_sa_deploy_out=$(jq -r '.attribution_skills.deploy.out_tok // "missing"' \
  "$_sa_base/cache/insights/sess-sub.json" 2>/dev/null)
assert_eq "subagent aggregate: deploy includes subagent out_tok (15+20)" "35" "$_sa_deploy_out"

# Subagent-only update → parent must re-aggregate on next run
sleep 1
printf '{"type":"assistant","timestamp":"2026-06-01T10:02:00Z","agentId":"subX","isSidechain":true,"message":{"role":"assistant","model":"claude-haiku-4-5","usage":{"input_tokens":1,"output_tokens":7,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}\n' \
  >> "$_sa_base/proj/projA/sess-sub/subagents/agent-subX.jsonl"
CLAUDE_PROJECTS_DIR="$_sa_base/proj" CLAUDII_CACHE_DIR="$_sa_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
_sa_deploy_out2=$(jq -r '.attribution_skills.deploy.out_tok // "missing"' \
  "$_sa_base/cache/insights/sess-sub.json" 2>/dev/null)
assert_eq "subagent aggregate: subagent-only update re-aggregates parent (35+7)" "42" "$_sa_deploy_out2"
rm -rf "$_sa_base"
unset _sa_base _sa_deploy_out _sa_deploy_out2
