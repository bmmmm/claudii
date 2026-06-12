# touches: lib/insights.jq

# test_insights_attribution.sh — per-skill and per-plugin attribution in insights aggregation

_FIXTURE="$CLAUDII_HOME/tests/fixtures/insights-attribution.jsonl"
_SID="test-sid-001"

# Run the jq aggregator against the fixture
_RESULT=$(jq -R -n --arg sid "$_SID" -f "$CLAUDII_HOME/lib/insights.jq" "$_FIXTURE" 2>&1)
_RC=$?

# Basic checks: file exists, jq succeeds
assert_eq "insights attribution: jq exit code" "0" "$_RC"
assert_eq "insights attribution: produces output" "0" "$([ -z "$_RESULT" ] && echo 1 || echo 0)"

# Schema version bump
_SCHEMA=$(echo "$_RESULT" | jq -r '.schema_version' 2>/dev/null)
assert_eq "insights attribution: schema_version == 4" "4" "$_SCHEMA"

# Session ID preserved
_SESSION=$(echo "$_RESULT" | jq -r '.sessionId' 2>/dev/null)
assert_eq "insights attribution: sessionId preserved" "$_SID" "$_SESSION"

# ── Skill attribution tests ──────────────────────────────────────────────────

# explore skill gets 2 calls (rows 2 and 3 in fixture)
_EXPLORE_CALLS=$(echo "$_RESULT" | jq '.attribution_skills.explore.calls // empty' 2>/dev/null)
assert_eq "insights attribution: explore calls == 2" "2" "$_EXPLORE_CALLS"

# explore input tokens: row2 (100) + row3 (80) = 180
_EXPLORE_IN=$(echo "$_RESULT" | jq '.attribution_skills.explore.in_tok // empty' 2>/dev/null)
assert_eq "insights attribution: explore in_tok == 180" "180" "$_EXPLORE_IN"

# explore output tokens: row2 (50) + row3 (60) = 110
_EXPLORE_OUT=$(echo "$_RESULT" | jq '.attribution_skills.explore.out_tok // empty' 2>/dev/null)
assert_eq "insights attribution: explore out_tok == 110" "110" "$_EXPLORE_OUT"

# explore cache_read tokens: row2 (0) + row3 (20) = 20
_EXPLORE_CACHE_READ=$(echo "$_RESULT" | jq '.attribution_skills.explore.cache_read // empty' 2>/dev/null)
assert_eq "insights attribution: explore cache_read == 20" "20" "$_EXPLORE_CACHE_READ"

# explore cache_create tokens: row2 (10) + row3 (5) = 15
_EXPLORE_CACHE_CREATE=$(echo "$_RESULT" | jq '.attribution_skills.explore.cache_create // empty' 2>/dev/null)
assert_eq "insights attribution: explore cache_create == 15" "15" "$_EXPLORE_CACHE_CREATE"

# ── Plugin attribution tests ─────────────────────────────────────────────────

# commit-commands plugin gets 1 call (row 4)
_COMMIT_CALLS=$(echo "$_RESULT" | jq '.attribution_plugins["commit-commands"].calls // empty' 2>/dev/null)
assert_eq "insights attribution: commit-commands calls == 1" "1" "$_COMMIT_CALLS"

# commit-commands input tokens: 120
_COMMIT_IN=$(echo "$_RESULT" | jq '.attribution_plugins["commit-commands"].in_tok // empty' 2>/dev/null)
assert_eq "insights attribution: commit-commands in_tok == 120" "120" "$_COMMIT_IN"

# commit-commands output tokens: 40
_COMMIT_OUT=$(echo "$_RESULT" | jq '.attribution_plugins["commit-commands"].out_tok // empty' 2>/dev/null)
assert_eq "insights attribution: commit-commands out_tok == 40" "40" "$_COMMIT_OUT"

# commit-commands cache_read tokens: 30
_COMMIT_CACHE_READ=$(echo "$_RESULT" | jq '.attribution_plugins["commit-commands"].cache_read // empty' 2>/dev/null)
assert_eq "insights attribution: commit-commands cache_read == 30" "30" "$_COMMIT_CACHE_READ"

# commit-commands cache_create tokens: 0
_COMMIT_CACHE_CREATE=$(echo "$_RESULT" | jq '.attribution_plugins["commit-commands"].cache_create // empty' 2>/dev/null)
assert_eq "insights attribution: commit-commands cache_create == 0" "0" "$_COMMIT_CACHE_CREATE"

# ── Non-existent skill returns null ───────────────────────────────────────────

# Accessing a nonexistent skill should return null
_NONEXIST=$(echo "$_RESULT" | jq '.attribution_skills.nonexistent' 2>/dev/null)
assert_eq "insights attribution: nonexistent skill returns null" "null" "$_NONEXIST"

# ── All-null attribution row does not create keys ──────────────────────────────

# Row 5 has null for both attributionSkill and attributionPlugin — should NOT create "null" keys
_NULL_KEY_SKILL=$(echo "$_RESULT" | jq '.attribution_skills | has("null")' 2>/dev/null)
assert_eq "insights attribution: no null key in attribution_skills" "false" "$_NULL_KEY_SKILL"

_NULL_KEY_PLUGIN=$(echo "$_RESULT" | jq '.attribution_plugins | has("null")' 2>/dev/null)
assert_eq "insights attribution: no null key in attribution_plugins" "false" "$_NULL_KEY_PLUGIN"

# ── MCP attribution (schema v4) ──────────────────────────────────────────────

# Row 6 invokes two MCP tools in one message (in 100, out 60, cr 40, cc 20)
# — usage splits evenly: 50/30/20/10 each, calls 1 each.
_MCP_ALPHA_CALLS=$(echo "$_RESULT" | jq '.attribution_mcp["mcp__srv__alpha"].calls // empty' 2>/dev/null)
assert_eq "insights attribution: mcp alpha calls == 1" "1" "$_MCP_ALPHA_CALLS"

_MCP_ALPHA_IN=$(echo "$_RESULT" | jq '.attribution_mcp["mcp__srv__alpha"].in_tok // empty' 2>/dev/null)
assert_eq "insights attribution: mcp alpha in_tok == 50 (split)" "50" "$_MCP_ALPHA_IN"

_MCP_BETA_OUT=$(echo "$_RESULT" | jq '.attribution_mcp["mcp__srv__beta"].out_tok // empty' 2>/dev/null)
assert_eq "insights attribution: mcp beta out_tok == 30 (split)" "30" "$_MCP_BETA_OUT"

# Non-MCP tool_use (Bash in row 3) must not appear in attribution_mcp
_MCP_BASH=$(echo "$_RESULT" | jq '.attribution_mcp | has("Bash")' 2>/dev/null)
assert_eq "insights attribution: Bash not in attribution_mcp" "false" "$_MCP_BASH"

# ── Per-attribution model tracking (schema v4) ───────────────────────────────

_AM_EXPLORE_OPUS=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-opus-4-7"] // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|opus-4-7 == 1" "1" "$_AM_EXPLORE_OPUS"

_AM_EXPLORE_SONNET=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-sonnet-4-6"] // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|sonnet-4-6 == 1" "1" "$_AM_EXPLORE_SONNET"

_AM_PLUGIN=$(echo "$_RESULT" | jq '.attribution_models["plugin|commit-commands|claude-opus-4-7"] // empty' 2>/dev/null)
assert_eq "insights attribution: models plugin|commit-commands|opus-4-7 == 1" "1" "$_AM_PLUGIN"

_AM_MCP=$(echo "$_RESULT" | jq '.attribution_models["mcp|mcp__srv__alpha|claude-sonnet-4-6"] // empty' 2>/dev/null)
assert_eq "insights attribution: models mcp|alpha|sonnet-4-6 == 1" "1" "$_AM_MCP"

# ── Subagent attribution (schema v4) ─────────────────────────────────────────

# Parent fixture spawns Agent (id agent-tu-1) under skill "deploy"; the
# tool_result promotes agentId sub123. The subagent fixture's lines then
# attribute to deploy — except the one carrying its own attributionSkill.
_RESULT_SUB=$(jq -R -n --arg sid "$_SID" -f "$CLAUDII_HOME/lib/insights.jq" \
  "$_FIXTURE" "$CLAUDII_HOME/tests/fixtures/insights-attribution-subagent.jsonl" 2>&1)

# deploy: 1 spawn message (in 30, out 15) + subagent line 1 (in 10, out 20)
_DEPLOY_CALLS=$(echo "$_RESULT_SUB" | jq '.attribution_skills.deploy.calls // empty' 2>/dev/null)
assert_eq "insights subagent: deploy calls == 2 (spawn + subagent msg)" "2" "$_DEPLOY_CALLS"

_DEPLOY_OUT=$(echo "$_RESULT_SUB" | jq '.attribution_skills.deploy.out_tok // empty' 2>/dev/null)
assert_eq "insights subagent: deploy out_tok == 35" "35" "$_DEPLOY_OUT"

# Subagent line 2 carries its own attributionSkill "inner" — wins over the map
_INNER_OUT=$(echo "$_RESULT_SUB" | jq '.attribution_skills.inner.out_tok // empty' 2>/dev/null)
assert_eq "insights subagent: own attributionSkill wins (inner out_tok == 10)" "10" "$_INNER_OUT"

# Subagent model lands in attribution_models under the spawning skill
_AM_DEPLOY_HAIKU=$(echo "$_RESULT_SUB" | jq '.attribution_models["skill|deploy|claude-haiku-4-5"] // empty' 2>/dev/null)
assert_eq "insights subagent: models skill|deploy|haiku == 1" "1" "$_AM_DEPLOY_HAIKU"

# Subagent usage counts toward session models/days totals
# (fixture row 5 is also haiku with in_tok 50 → 50 + 10 + 5)
_HAIKU_TOTAL=$(echo "$_RESULT_SUB" | jq '.models["claude-haiku-4-5"].in_tok // empty' 2>/dev/null)
assert_eq "insights subagent: haiku in_tok in session models == 65" "65" "$_HAIKU_TOTAL"

# Transient bookkeeping is stripped
_TRANSIENT=$(echo "$_RESULT_SUB" | jq 'has("pending_agent_skill") or has("agent_skill_map") or has("pending_tools")' 2>/dev/null)
assert_eq "insights subagent: transient maps stripped" "false" "$_TRANSIENT"

# ── Message count sanity checks ──────────────────────────────────────────────

# 8 messages total (rows 1-8), 6 assistant messages
_TOTAL_MSGS=$(echo "$_RESULT" | jq '.messages' 2>/dev/null)
assert_eq "insights attribution: total messages == 8" "8" "$_TOTAL_MSGS"

_ASST_MSGS=$(echo "$_RESULT" | jq '.assistant_messages' 2>/dev/null)
assert_eq "insights attribution: assistant_messages == 6" "6" "$_ASST_MSGS"

# Cleanup
unset _FIXTURE _SID _RESULT _RC _SCHEMA _SESSION
unset _EXPLORE_CALLS _EXPLORE_IN _EXPLORE_OUT _EXPLORE_CACHE_READ _EXPLORE_CACHE_CREATE
unset _COMMIT_CALLS _COMMIT_IN _COMMIT_OUT _COMMIT_CACHE_READ _COMMIT_CACHE_CREATE
unset _NONEXIST _NULL_KEY_SKILL _NULL_KEY_PLUGIN _TOTAL_MSGS _ASST_MSGS
unset _MCP_ALPHA_CALLS _MCP_ALPHA_IN _MCP_BETA_OUT _MCP_BASH
unset _AM_EXPLORE_OPUS _AM_EXPLORE_SONNET _AM_PLUGIN _AM_MCP
unset _RESULT_SUB _DEPLOY_CALLS _DEPLOY_OUT _INNER_OUT _AM_DEPLOY_HAIKU _HAIKU_TOTAL _TRANSIENT
