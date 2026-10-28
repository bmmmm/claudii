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
assert_eq "insights attribution: schema_version == 14" "14" "$_SCHEMA"

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

# ── Per-attribution model tracking (schema v5: {calls, tokens} per model) ─────

_AM_EXPLORE_OPUS=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-opus-4-7"].calls // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|opus-4-7 calls == 1" "1" "$_AM_EXPLORE_OPUS"

# Per-model tokens land on the right model bucket: explore on opus-4-7 is fixture
# row 2 (in 100, out 50, cr 0, cc 10).
_AM_EXPLORE_OPUS_IN=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-opus-4-7"].in_tok // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|opus-4-7 in_tok == 100" "100" "$_AM_EXPLORE_OPUS_IN"
_AM_EXPLORE_OPUS_CC=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-opus-4-7"].cache_create // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|opus-4-7 cache_create == 10" "10" "$_AM_EXPLORE_OPUS_CC"

_AM_EXPLORE_SONNET=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-sonnet-4-6"].calls // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|sonnet-4-6 calls == 1" "1" "$_AM_EXPLORE_SONNET"
# explore on sonnet-4-6 is fixture row 3 (in 80, out 60, cr 20, cc 5)
_AM_EXPLORE_SONNET_OUT=$(echo "$_RESULT" | jq '.attribution_models["skill|explore|claude-sonnet-4-6"].out_tok // empty' 2>/dev/null)
assert_eq "insights attribution: models skill|explore|sonnet-4-6 out_tok == 60" "60" "$_AM_EXPLORE_SONNET_OUT"

# Per-model token sum across models equals the flat aggregate (consistency
# invariant skills-cost relies on for the residual calculation):
# explore in_tok 100 + 80 == attribution_skills.explore.in_tok 180
_AM_EXPLORE_SUM_IN=$(echo "$_RESULT" | jq '[.attribution_models | to_entries[] | select(.key | startswith("skill|explore|")) | .value.in_tok] | add' 2>/dev/null)
assert_eq "insights attribution: per-model in_tok sums to aggregate (180)" "180" "$_AM_EXPLORE_SUM_IN"

_AM_PLUGIN=$(echo "$_RESULT" | jq '.attribution_models["plugin|commit-commands|claude-opus-4-7"].calls // empty' 2>/dev/null)
assert_eq "insights attribution: models plugin|commit-commands|opus-4-7 calls == 1" "1" "$_AM_PLUGIN"

# MCP per-model tokens carry the even-split (in 50, the half of row 6's 100)
_AM_MCP=$(echo "$_RESULT" | jq '.attribution_models["mcp|mcp__srv__alpha|claude-sonnet-4-6"].calls // empty' 2>/dev/null)
assert_eq "insights attribution: models mcp|alpha|sonnet-4-6 calls == 1" "1" "$_AM_MCP"
_AM_MCP_IN=$(echo "$_RESULT" | jq '.attribution_models["mcp|mcp__srv__alpha|claude-sonnet-4-6"].in_tok // empty' 2>/dev/null)
assert_eq "insights attribution: models mcp|alpha|sonnet-4-6 in_tok == 50 (split)" "50" "$_AM_MCP_IN"

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
_AM_DEPLOY_HAIKU=$(echo "$_RESULT_SUB" | jq '.attribution_models["skill|deploy|claude-haiku-4-5"].calls // empty' 2>/dev/null)
assert_eq "insights subagent: models skill|deploy|haiku calls == 1" "1" "$_AM_DEPLOY_HAIKU"

# Subagent usage counts toward session models/days totals
# (fixture row 5 is also haiku with in_tok 50 → 50 + 10 + 5)
_HAIKU_TOTAL=$(echo "$_RESULT_SUB" | jq '.models["claude-haiku-4-5"].in_tok // empty' 2>/dev/null)
assert_eq "insights subagent: haiku in_tok in session models == 65" "65" "$_HAIKU_TOTAL"

# Transient bookkeeping is stripped
_TRANSIENT=$(echo "$_RESULT_SUB" | jq 'has("pending_agent_skill") or has("agent_skill_map") or has("pending_tools") or has("seen_ts") or has("msgs")' 2>/dev/null)
assert_eq "insights subagent: transient maps stripped" "false" "$_TRANSIENT"

# ── Message count sanity checks ──────────────────────────────────────────────

# 8 messages total (rows 1-8), 6 assistant messages
_TOTAL_MSGS=$(echo "$_RESULT" | jq '.messages' 2>/dev/null)
assert_eq "insights attribution: total messages == 8" "8" "$_TOTAL_MSGS"

_ASST_MSGS=$(echo "$_RESULT" | jq '.assistant_messages' 2>/dev/null)
assert_eq "insights attribution: assistant_messages == 6" "6" "$_ASST_MSGS"

# ── Cache-write TTL split (schema v11) ───────────────────────────────────────
# usage.cache_creation splits cache_creation_input_tokens by TTL; the 1h part
# lands in cache_create_1h next to the unchanged total, so skills-cost can bill
# it at 2× input instead of the 5m rate's 1.25×. A record without the split
# adds 0 — none of the fixture rows above carries one.
_TTL_JSONL=$(mktemp)
cat > "$_TTL_JSONL" <<'JSONL'
{"type":"assistant","timestamp":"2026-05-27T11:00:00Z","attributionSkill":"ttl","message":{"role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1000}},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T11:01:00Z","attributionSkill":"ttl","message":{"role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":400,"cache_creation":{"ephemeral_5m_input_tokens":400,"ephemeral_1h_input_tokens":0}},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T11:02:00Z","attributionSkill":"ttl","message":{"role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":300},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T11:03:00Z","attributionPlugin":"pl","message":{"role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":200,"cache_creation":{"ephemeral_5m_input_tokens":50,"ephemeral_1h_input_tokens":150}},"content":[{"type":"tool_use","id":"m1","name":"mcp__srv__alpha","input":{}},{"type":"tool_use","id":"m2","name":"mcp__srv__beta","input":{}}]}}
JSONL
_TTL=$(jq -R -n --arg sid "ttl-sid" -f "$CLAUDII_HOME/lib/insights.jq" "$_TTL_JSONL" 2>&1)
rm -f "$_TTL_JSONL"
# ttl: 1000 (1h) + 400 (5m) + 300 (no split) → total 1700, 1h part 1000
assert_eq "insights TTL: skill cache_create keeps the total (1700)" "1700" \
  "$(jq '.attribution_skills.ttl.cache_create' <<< "$_TTL" 2>/dev/null)"
assert_eq "insights TTL: skill cache_create_1h counts only 1h writes (1000)" "1000" \
  "$(jq '.attribution_skills.ttl.cache_create_1h' <<< "$_TTL" 2>/dev/null)"
assert_eq "insights TTL: per-model bucket carries the 1h part (1000)" "1000" \
  "$(jq '.attribution_models["skill|ttl|claude-opus-5-5"].cache_create_1h' <<< "$_TTL" 2>/dev/null)"
assert_eq "insights TTL: plugin cache_create_1h == 150" "150" \
  "$(jq '.attribution_plugins.pl.cache_create_1h' <<< "$_TTL" 2>/dev/null)"
# MCP splits usage evenly across the message's tools: 150 / 2 each
assert_eq "insights TTL: mcp cache_create_1h split evenly (75)" "75" \
  "$(jq '.attribution_mcp["mcp__srv__alpha"].cache_create_1h' <<< "$_TTL" 2>/dev/null)"
assert_eq "insights TTL: mcp per-model cache_create_1h split evenly (75)" "75" \
  "$(jq '.attribution_models["mcp|mcp__srv__beta|claude-opus-5-5"].cache_create_1h' <<< "$_TTL" 2>/dev/null)"
assert_eq "insights TTL: records without the split add 0 (explore)" "0" \
  "$(jq '.attribution_skills.explore.cache_create_1h' <<< "$_RESULT" 2>/dev/null)"

# ── One API response, several records (schema v12) ───────────────────────────
# Claude Code writes an assistant message as one record per content block, all
# sharing message.id; summed per record, every response counted 2-3×. The
# message's usage is charged once, each counter at the largest value seen.
#   msg_A  main thread, 3 records (thinking/text/Bash), usage repeated on each
#          — in 10, out 300, cr 5000, cc 700 (1h), skill "split"
#   msg_B  subagent, written mid-stream: out 8, 8, then the final 440; its two
#          MCP tool_use blocks sit in different records, a tool_result between
#   msg_C  the final usage (out 90) on the FIRST record — max, not "last wins"
#   (none) two records without message.id still count as two messages
_MR_JSONL=$(mktemp)
cat > "$_MR_JSONL" <<'JSONL'
{"type":"user","uuid":"u1","timestamp":"2026-05-27T12:00:00Z","message":{"role":"user","content":"go"}}
{"type":"assistant","uuid":"a1","parentUuid":"u1","timestamp":"2026-05-27T12:00:04Z","requestId":"req_A","attributionSkill":"split","message":{"id":"msg_A","role":"assistant","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":300,"cache_read_input_tokens":5000,"cache_creation_input_tokens":700,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":700},"service_tier":"standard"},"content":[{"type":"thinking","thinking":""}]}}
{"type":"assistant","uuid":"a2","parentUuid":"a1","timestamp":"2026-05-27T12:00:04Z","requestId":"req_A","attributionSkill":"split","message":{"id":"msg_A","role":"assistant","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":300,"cache_read_input_tokens":5000,"cache_creation_input_tokens":700,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":700},"service_tier":"standard"},"content":[{"type":"text","text":"running"}]}}
{"type":"assistant","uuid":"a3","parentUuid":"a2","timestamp":"2026-05-27T12:00:10Z","requestId":"req_A","attributionSkill":"split","message":{"id":"msg_A","role":"assistant","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":300,"cache_read_input_tokens":5000,"cache_creation_input_tokens":700,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":700},"service_tier":"standard"},"content":[{"type":"tool_use","id":"t-bash","name":"Bash","input":{}}]}}
{"type":"user","uuid":"u2","parentUuid":"a3","timestamp":"2026-05-27T12:00:12Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t-bash","content":"ok"}]}}
{"type":"assistant","uuid":"b1","parentUuid":"s0","isSidechain":true,"agentId":"subB","timestamp":"2026-05-27T12:01:00Z","requestId":"req_B","message":{"id":"msg_B","role":"assistant","model":"claude-opus-5-5","stop_reason":null,"usage":{"input_tokens":2,"output_tokens":8,"cache_read_input_tokens":1000,"cache_creation_input_tokens":100,"service_tier":"standard"},"content":[{"type":"thinking","thinking":""}]}}
{"type":"assistant","uuid":"b2","parentUuid":"b1","isSidechain":true,"agentId":"subB","timestamp":"2026-05-27T12:01:02Z","requestId":"req_B","message":{"id":"msg_B","role":"assistant","model":"claude-opus-5-5","stop_reason":null,"usage":{"input_tokens":2,"output_tokens":8,"cache_read_input_tokens":1000,"cache_creation_input_tokens":100,"service_tier":"standard"},"content":[{"type":"tool_use","id":"t-alpha","name":"mcp__srv__alpha","input":{}}]}}
{"type":"user","uuid":"r1","parentUuid":"b2","isSidechain":true,"agentId":"subB","timestamp":"2026-05-27T12:01:05Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t-alpha","content":"ok"}]}}
{"type":"assistant","uuid":"b3","parentUuid":"r1","isSidechain":true,"agentId":"subB","timestamp":"2026-05-27T12:01:09Z","requestId":"req_B","message":{"id":"msg_B","role":"assistant","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":2,"output_tokens":440,"cache_read_input_tokens":1000,"cache_creation_input_tokens":100,"service_tier":"standard"},"content":[{"type":"tool_use","id":"t-beta","name":"mcp__srv__beta","input":{}}]}}
{"type":"assistant","uuid":"c1","timestamp":"2026-05-27T12:02:00Z","requestId":"req_C","message":{"id":"msg_C","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":4,"output_tokens":90,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"final"}]}}
{"type":"assistant","uuid":"c2","timestamp":"2026-05-27T12:02:00Z","requestId":"req_C","message":{"id":"msg_C","role":"assistant","model":"claude-opus-5-5","stop_reason":null,"usage":{"input_tokens":4,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"placeholder"}]}}
{"type":"assistant","timestamp":"2026-05-27T12:03:00Z","message":{"role":"assistant","model":"claude-haiku-4-5","usage":{"input_tokens":7,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T12:03:01Z","message":{"role":"assistant","model":"claude-haiku-4-5","usage":{"input_tokens":7,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}
JSONL
_MR=$(jq -R -n --arg sid "mr-sid" -f "$CLAUDII_HOME/lib/insights.jq" "$_MR_JSONL" 2>&1)
rm -f "$_MR_JSONL"
_mr() { jq -c "$1" <<< "$_MR" 2>/dev/null; }

assert_eq "insights per-message: 13 records, 5 responses (A, B, C + 2 without id)" "13 5" \
  "$(_mr '.messages') $(_mr '.assistant_messages')"
# Opus day: in 10+2+4, out 300+440+90, cr 5000+1000, cc 700+100 — per record
# it was 44 / 1451 / 18000 / 2400. cache_create_1h (schema v13, what `cost`
# prices insights-only sessions from) is the 1h part of the 700 write.
assert_eq "insights per-message: each response's usage counted once" \
  '{"in_tok":16,"out_tok":830,"cache_read":6000,"cache_create":800,"cache_create_1h":700}' \
  "$(_mr '.days["2026-05-27|claude-opus-5-5"]')"
assert_eq "insights per-message: models{} counted once too" \
  '{"in_tok":16,"cache_read":6000,"cache_create":800}' "$(_mr '.models["claude-opus-5-5"]')"
assert_eq "insights per-message: records without message.id stay separate (7+7)" "14" \
  "$(_mr '.days["2026-05-27|claude-haiku-4-5"].in_tok')"
# One stop reason and one service tier per response; msg_B's placeholder
# records carry stop_reason null, msg_C's final record comes first
assert_eq "insights per-message: stop_reasons per response" '{"tool_use":2,"end_turn":1}' "$(_mr '.stop_reasons')"
assert_eq "insights per-message: service_tier per response" '{"standard":2}' "$(_mr '.service_tier')"
# Content blocks are per record — every block lives in exactly one
assert_eq "insights per-message: blocks still counted once each" \
  '{"thinking":2,"tools":{"Bash":1,"mcp__srv__alpha":1,"mcp__srv__beta":1}}' \
  "$(_mr '{thinking: .thinking_blocks, tools}')"

# Skill attribution: one call, the usage once (incl. the 1h write share)
assert_eq "insights per-message: skill charged once per response" \
  '{"calls":1,"in_tok":10,"out_tok":300,"cache_read":5000,"cache_create":700,"cache_create_1h":700}' \
  "$(_mr '.attribution_skills.split')"
assert_eq "insights per-message: per-model skill bucket matches" "1 300" \
  "$(_mr '.attribution_models["skill|split|claude-opus-5-5"] | "\(.calls) \(.out_tok)"' | tr -d '"')"

# msg_B: the final usage (out 440, not 8 or 456) split across BOTH MCP tools,
# though each sits in its own record — half each, one call each
assert_eq "insights per-message: MCP split sees every tool_use of the message (alpha)" \
  '{"calls":1,"in_tok":1,"out_tok":220,"cache_read":500,"cache_create":50,"cache_create_1h":0}' \
  "$(_mr '.attribution_mcp["mcp__srv__alpha"]')"
assert_eq "insights per-message: MCP split sees every tool_use of the message (beta)" \
  '{"calls":1,"in_tok":1,"out_tok":220,"cache_read":500,"cache_create":50,"cache_create_1h":0}' \
  "$(_mr '.attribution_mcp["mcp__srv__beta"]')"
assert_eq "insights per-message: per-model MCP bucket carries the split" "220" \
  "$(_mr '.attribution_models["mcp|mcp__srv__alpha|claude-opus-5-5"].out_tok')"

# Latency: one sample per main-thread response, u1 → msg_A's last block
# (12:00:00 → 12:00:10). Per record it was three: 4s, 0s and 6s, each with
# the full output count. msg_B is a sidechain; msg_C has no parent.
assert_eq "insights per-message: one latency sample, prompt to last block" \
  '[{"day":"2026-05-27","model":"claude-opus-5-5","dt_ms":10000,"out":300,"ctx":5710}]' \
  "$(_mr '.latency')"
assert_eq "insights per-message: transient msgs map stripped" "false" "$(_mr 'has("msgs")')"
unset -f _mr

# ── Requests over 100K prompt tokens (schema v14) ────────────────────────────
# Haiku 5.5 bills a whole request at 5× when its prompt — input + cache_read +
# cache_create, cached tokens included — is over 100,000 tokens. Summed buckets
# cannot be split afterwards, so each message that qualifies also lands in the
# bucket's long_* counters. Haiku 5.5, skill "lg":
#   msg_L1  in 1,   cr 100000        → prompt 100001: long
#   msg_L2  in 0,   cr 100000        → prompt exactly 100000: NOT long (strict)
#   msg_L3  in 500, cc 100000 (60000 on the 1h cache) → prompt 100500: long
#   msg_M   2 records, cr 100001     → long, charged once
# msg_X (no skill): cr 100002 split over two MCP tools → 50001 each.
# "opus-lg" is a 200K Opus request: recorded too — the counters are a fact
# about the request, only the pricing decides which model they matter for.
_LG_JSONL=$(mktemp)
cat > "$_LG_JSONL" <<'JSONL'
{"type":"assistant","timestamp":"2026-05-27T13:00:00Z","attributionSkill":"lg","message":{"id":"msg_L1","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":1,"output_tokens":10,"cache_read_input_tokens":100000,"cache_creation_input_tokens":0},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T13:01:00Z","attributionSkill":"lg","message":{"id":"msg_L2","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":0,"output_tokens":20,"cache_read_input_tokens":100000,"cache_creation_input_tokens":0},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T13:02:00Z","attributionSkill":"lg","message":{"id":"msg_L3","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":500,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":100000,"cache_creation":{"ephemeral_5m_input_tokens":40000,"ephemeral_1h_input_tokens":60000}},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T13:03:00Z","attributionSkill":"lg","message":{"id":"msg_M","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":0,"output_tokens":40,"cache_read_input_tokens":100001,"cache_creation_input_tokens":0},"content":[{"type":"thinking","thinking":""}]}}
{"type":"assistant","timestamp":"2026-05-27T13:03:01Z","attributionSkill":"lg","message":{"id":"msg_M","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":0,"output_tokens":40,"cache_read_input_tokens":100001,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"x"}]}}
{"type":"assistant","timestamp":"2026-05-27T13:04:00Z","attributionSkill":"opus-lg","message":{"id":"msg_O","role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":200000,"output_tokens":7,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T13:05:00Z","attributionSkill":"edge","message":{"id":"msg_E","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":100000,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}
{"type":"assistant","timestamp":"2026-05-27T13:06:00Z","message":{"id":"msg_X","role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":0,"output_tokens":8,"cache_read_input_tokens":100002,"cache_creation_input_tokens":0},"content":[{"type":"tool_use","id":"x1","name":"mcp__srv__alpha","input":{}},{"type":"tool_use","id":"x2","name":"mcp__srv__beta","input":{}}]}}
JSONL
_LG=$(jq -R -n --arg sid "lg-sid" -f "$CLAUDII_HOME/lib/insights.jq" "$_LG_JSONL" 2>&1)
rm -f "$_LG_JSONL"
_lg() { jq -c "$1" <<< "$_LG" 2>/dev/null; }
_LG_LONG='{long_in_tok, long_out_tok, long_cache_read, long_cache_create, long_cache_create_1h}'
assert_eq "insights long: schema_version == 14" "14" "$(_lg '.schema_version')"
assert_eq "insights long: bucket keeps the totals (4 responses)" \
  '{"calls":4,"in_tok":501,"out_tok":100,"cache_read":300001,"cache_create":100000,"cache_create_1h":60000}' \
  "$(_lg '.attribution_models["skill|lg|claude-haiku-5-5"] | {calls, in_tok, out_tok, cache_read, cache_create, cache_create_1h}')"
# L1 + L3 + M are over; L2 (exactly 100,000) is not; the two records of M count once
assert_eq "insights long: only responses over 100,000 prompt tokens, cached tokens included" \
  '{"long_in_tok":501,"long_out_tok":80,"long_cache_read":200001,"long_cache_create":100000,"long_cache_create_1h":60000}' \
  "$(_lg ".attribution_models[\"skill|lg|claude-haiku-5-5\"] | $_LG_LONG")"
assert_eq "insights long: the skill-level bucket carries the same split" '501 200001' \
  "$(_lg '.attribution_skills.lg | "\(.long_in_tok) \(.long_cache_read)"' | tr -d '"')"
assert_eq "insights long: a prompt of exactly 100,000 leaves no long_* counters" "false" \
  "$(_lg '.attribution_models["skill|edge|claude-haiku-5-5"] | has("long_in_tok")')"
assert_eq "insights long: the MCP split divides the long share too (50001 each)" "50001 50001" \
  "$(_lg '"\(.attribution_models["mcp|mcp__srv__alpha|claude-haiku-5-5"].long_cache_read) \(.attribution_mcp["mcp__srv__beta"].long_cache_read)"' | tr -d '"')"
assert_eq "insights long: recorded for any model, not only Haiku" '200000' \
  "$(_lg '.attribution_models["skill|opus-lg|claude-opus-5-5"].long_in_tok')"
unset -f _lg
unset _LG_JSONL _LG _LG_LONG

# Cleanup
unset _MR_JSONL _MR
unset _TTL_JSONL _TTL
unset _FIXTURE _SID _RESULT _RC _SCHEMA _SESSION
unset _EXPLORE_CALLS _EXPLORE_IN _EXPLORE_OUT _EXPLORE_CACHE_READ _EXPLORE_CACHE_CREATE
unset _COMMIT_CALLS _COMMIT_IN _COMMIT_OUT _COMMIT_CACHE_READ _COMMIT_CACHE_CREATE
unset _NONEXIST _NULL_KEY_SKILL _NULL_KEY_PLUGIN _TOTAL_MSGS _ASST_MSGS
unset _MCP_ALPHA_CALLS _MCP_ALPHA_IN _MCP_BETA_OUT _MCP_BASH
unset _AM_EXPLORE_OPUS _AM_EXPLORE_OPUS_IN _AM_EXPLORE_OPUS_CC _AM_EXPLORE_SONNET _AM_EXPLORE_SONNET_OUT _AM_EXPLORE_SUM_IN _AM_PLUGIN _AM_MCP _AM_MCP_IN
unset _RESULT_SUB _DEPLOY_CALLS _DEPLOY_OUT _INNER_OUT _AM_DEPLOY_HAIKU _HAIKU_TOTAL _TRANSIENT
