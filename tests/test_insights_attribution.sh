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
assert_eq "insights attribution: schema_version == 3" "3" "$_SCHEMA"

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

# ── Message count sanity checks ──────────────────────────────────────────────

# 5 messages total (rows 1-5), 4 assistant messages
_TOTAL_MSGS=$(echo "$_RESULT" | jq '.messages' 2>/dev/null)
assert_eq "insights attribution: total messages == 5" "5" "$_TOTAL_MSGS"

_ASST_MSGS=$(echo "$_RESULT" | jq '.assistant_messages' 2>/dev/null)
assert_eq "insights attribution: assistant_messages == 4" "4" "$_ASST_MSGS"

# Cleanup
unset _FIXTURE _SID _RESULT _RC _SCHEMA _SESSION
unset _EXPLORE_CALLS _EXPLORE_IN _EXPLORE_OUT _EXPLORE_CACHE_READ _EXPLORE_CACHE_CREATE
unset _COMMIT_CALLS _COMMIT_IN _COMMIT_OUT _COMMIT_CACHE_READ _COMMIT_CACHE_CREATE
unset _NONEXIST _NULL_KEY_SKILL _NULL_KEY_PLUGIN _TOTAL_MSGS _ASST_MSGS
