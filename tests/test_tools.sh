# touches: lib/cmd/insights.sh lib/render.sh bin/claudii-insights lib/insights.jq

# test_tools.sh — claudii tools (tool / efficiency lens)
# One synthetic assistant turn with 20 Bash + Read + Agent(Explore) + an MCP tool
# (2 Bash errors) exercises the table, per-row + global error markers, the
# subagent section, thinking volume, and MCP name-shortening.

_TLS_TMPDIRS=()
trap 'rm -rf "${_TLS_TMPDIRS[@]}" 2>/dev/null' EXIT
_TLS_PROJ="$(mktemp -d)"; _TLS_TMPDIRS+=("$_TLS_PROJ")
_TLS_CACHE="$(mktemp -d)"; _TLS_TMPDIRS+=("$_TLS_CACHE")
mkdir -p "$_TLS_PROJ/-test-project"

_SID="22222222-3333-4444-5555-666666666666"
_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_JSONL="$_TLS_PROJ/-test-project/$_SID.jsonl"

# 20 Bash tool_use (b1..b20), 2 of them errored, plus Read / Agent(Explore) /
# an MCP tool. Bash → 20 calls, 2 err = 10% (>5% → row ⚠ + worst-tool warning).
_bash_uses=""
for _i in $(seq 1 20); do
  _bash_uses+="{\"type\":\"tool_use\",\"id\":\"b$_i\",\"name\":\"Bash\",\"input\":{}},"
done
{
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"role":"assistant","model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"thinking","thinking":"x"},%s{"type":"tool_use","id":"r1","name":"Read","input":{}},{"type":"tool_use","id":"a1","name":"Agent","input":{"subagent_type":"Explore"}},{"type":"tool_use","id":"m1","name":"mcp__test__do_thing","input":{}}]}}\n' "$_TS" "$_SID" "$_bash_uses"
  printf '{"type":"user","timestamp":"%s","sessionId":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"e"},{"type":"tool_result","tool_use_id":"b2","is_error":true,"content":"e"},{"type":"tool_result","tool_use_id":"r1","content":"ok"}]}}\n' "$_TS" "$_SID"
} > "$_JSONL"

_TLS_OUT=$(CLAUDE_PROJECTS_DIR="$_TLS_PROJ" CLAUDII_CACHE_DIR="$_TLS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tools 2>&1)
_TLS_RC=$(CLAUDE_PROJECTS_DIR="$_TLS_PROJ" CLAUDII_CACHE_DIR="$_TLS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tools >/dev/null 2>&1; echo $?)

assert_eq "tools: exit 0"          "0" "$_TLS_RC"
assert_eq "tools: produces output" "0" "$([ -z "$_TLS_OUT" ] && echo 1 || echo 0)"
assert_no_literal_ansi "tools: no literal \\033 in output" "$_TLS_OUT"

# ── Header + table ──
assert_contains "tools: header"        "claudii tools" "$_TLS_OUT"
assert_contains "tools: total calls"   "23 calls"      "$_TLS_OUT"
assert_contains "tools: Bash row"      "Bash"          "$_TLS_OUT"
assert_contains "tools: Read row"      "Read"          "$_TLS_OUT"
assert_contains "tools: Agent row"     "Agent"         "$_TLS_OUT"
assert_contains "tools: Bash error count" "2 err"      "$_TLS_OUT"
assert_contains "tools: high-rate marker" "⚠"          "$_TLS_OUT"

# ── MCP name shortened to its tool segment ──
assert_contains     "tools: MCP name shortened"      "do_thing"             "$_TLS_OUT"
assert_not_contains "tools: raw MCP prefix not shown" "mcp__test__do_thing" "$_TLS_OUT"

# ── Subagents + thinking + worst-tool callout ──
assert_contains "tools: subagents section" "Subagents"          "$_TLS_OUT"
assert_contains "tools: subagent Explore"  "Explore"            "$_TLS_OUT"
assert_contains "tools: thinking line"     "Thinking"           "$_TLS_OUT"
assert_contains "tools: thinking blocks"   "blocks"             "$_TLS_OUT"
assert_contains "tools: worst-tool callout" "highest error rate" "$_TLS_OUT"

# ── Per-session JSON cache populated ──
assert_eq "tools: per-session JSON cache exists" "1" \
  "$([ -s "$_TLS_CACHE/insights/$_SID.json" ] && echo 1 || echo 0)"

# ── Empty cache → empty-state line ──
_TLS_EPROJ="$(mktemp -d)"; _TLS_TMPDIRS+=("$_TLS_EPROJ")
_TLS_ECACHE="$(mktemp -d)"; _TLS_TMPDIRS+=("$_TLS_ECACHE")
_TLS_EOUT=$(CLAUDE_PROJECTS_DIR="$_TLS_EPROJ" CLAUDII_CACHE_DIR="$_TLS_ECACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tools 2>&1)
assert_contains "tools (empty): empty-state message" "No insight data" "$_TLS_EOUT"

# ── --days validation ──
_TLS_DV=$(CLAUDE_PROJECTS_DIR="$_TLS_PROJ" CLAUDII_CACHE_DIR="$_TLS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tools --days foo 2>&1; echo "rc=$?")
assert_contains "tools --days foo: actionable error" "positive integer" "$_TLS_DV"
assert_contains "tools --days foo: exit 1" "rc=1" "$_TLS_DV"

# ── --help ──
_TLS_HELP=$(bash "$CLAUDII_HOME/bin/claudii" tools --help 2>&1)
assert_contains "tools --help: usage" "Usage: claudii tools" "$_TLS_HELP"

unset _SID _TS _JSONL _bash_uses _i _TLS_OUT _TLS_RC _TLS_EOUT _TLS_DV _TLS_HELP
