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
assert_eq "label: opus 4.8 (latest)"  "Opus 4.8"   "$(_insights_model_label claude-opus-4-8)"
assert_eq "label: opus 4.7 (older)"   "Opus 4.7"   "$(_insights_model_label claude-opus-4-7)"
assert_eq "label: opus 4.6 (older)"   "Opus 4.6"   "$(_insights_model_label claude-opus-4-6)"
assert_eq "label: sonnet 4.6"         "Sonnet 4.6" "$(_insights_model_label claude-sonnet-4-6)"
assert_eq "label: haiku 4.5"          "Haiku 4.5"  "$(_insights_model_label claude-haiku-4-5)"
assert_eq "label: unknown opus->tier" "Opus"       "$(_insights_model_label claude-opus-9-9)"

unset _SID _TS _JSONL _CACHE_OUT _CACHE_RC _CACHE_OUT_30 _EMPTY_OUT _BAD_RC
