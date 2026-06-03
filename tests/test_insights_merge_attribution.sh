# touches: bin/claudii-insights lib/insights.jq
# test_insights_merge_attribution.sh — test merge of attribution_skills and attribution_plugins

_INSIGHTS_TMPDIRS=()
trap 'rm -rf "${_INSIGHTS_TMPDIRS[@]}" 2>/dev/null' EXIT

# ── Test: merge includes attribution_skills and attribution_plugins ────────────────

_insights_tmp="$(mktemp -d)"; _INSIGHTS_TMPDIRS+=("$_insights_tmp")
_insights_cache_dir="$_insights_tmp/insights"
mkdir -p "$_insights_cache_dir"

# Create first per-session cache with attribution data
_session1_cache="$_insights_cache_dir/session-1.json"
cat > "$_session1_cache" <<'JSON'
{
  "schema_version": 3,
  "sessionId": "session-1",
  "first_seen": "2026-05-27T10:00:00Z",
  "last_seen": "2026-05-27T11:00:00Z",
  "messages": 10,
  "assistant_messages": 5,
  "sidechain_msgs": 0,
  "thinking_blocks": 0,
  "limit_hits": [],
  "snapshots": 0,
  "days": {},
  "models": {},
  "tools": {},
  "tool_errors": {},
  "stop_reasons": {},
  "subagent_types": {},
  "permission_modes": {},
  "service_tier": {},
  "attribution_skills": {
    "explore": {
      "calls": 2,
      "in_tok": 100,
      "out_tok": 50,
      "cache_read": 10,
      "cache_create": 5
    }
  },
  "attribution_plugins": {
    "email": {
      "calls": 1,
      "in_tok": 200,
      "out_tok": 100,
      "cache_read": 0,
      "cache_create": 20
    }
  }
}
JSON

# Create second per-session cache with different attribution data
_session2_cache="$_insights_cache_dir/session-2.json"
cat > "$_session2_cache" <<'JSON'
{
  "schema_version": 3,
  "sessionId": "session-2",
  "first_seen": "2026-05-27T12:00:00Z",
  "last_seen": "2026-05-27T13:00:00Z",
  "messages": 8,
  "assistant_messages": 4,
  "sidechain_msgs": 0,
  "thinking_blocks": 0,
  "limit_hits": [],
  "snapshots": 0,
  "days": {},
  "models": {},
  "tools": {},
  "tool_errors": {},
  "stop_reasons": {},
  "subagent_types": {},
  "permission_modes": {},
  "service_tier": {},
  "attribution_skills": {
    "explore": {
      "calls": 2,
      "in_tok": 100,
      "out_tok": 50,
      "cache_read": 10,
      "cache_create": 5
    },
    "proxy": {
      "calls": 1,
      "in_tok": 50,
      "out_tok": 25,
      "cache_read": 0,
      "cache_create": 0
    }
  },
  "attribution_plugins": {
    "email": {
      "calls": 2,
      "in_tok": 150,
      "out_tok": 75,
      "cache_read": 5,
      "cache_create": 10
    }
  }
}
JSON

# Run merge with cache dir override
merged_output=$(CLAUDII_CACHE_DIR="$_insights_tmp" bash "$CLAUDII_HOME/bin/claudii-insights" merge 2>&1)

# Verify attribution_skills.explore.calls = 4 (2+2)
explore_calls=$(printf '%s\n' "$merged_output" | jq -r '.attribution_skills.explore.calls')
assert_eq "merge: attribution_skills.explore.calls == 4" "4" "$explore_calls"

# Verify attribution_skills.explore.in_tok = 200 (100+100)
explore_in_tok=$(printf '%s\n' "$merged_output" | jq -r '.attribution_skills.explore.in_tok')
assert_eq "merge: attribution_skills.explore.in_tok == 200" "200" "$explore_in_tok"

# Verify attribution_skills.explore.out_tok = 100 (50+50)
explore_out_tok=$(printf '%s\n' "$merged_output" | jq -r '.attribution_skills.explore.out_tok')
assert_eq "merge: attribution_skills.explore.out_tok == 100" "100" "$explore_out_tok"

# Verify attribution_skills.explore.cache_read = 20 (10+10)
explore_cache_read=$(printf '%s\n' "$merged_output" | jq -r '.attribution_skills.explore.cache_read')
assert_eq "merge: attribution_skills.explore.cache_read == 20" "20" "$explore_cache_read"

# Verify attribution_skills.explore.cache_create = 10 (5+5)
explore_cache_create=$(printf '%s\n' "$merged_output" | jq -r '.attribution_skills.explore.cache_create')
assert_eq "merge: attribution_skills.explore.cache_create == 10" "10" "$explore_cache_create"

# Verify attribution_skills.proxy.calls = 1 (only in session 2)
proxy_calls=$(printf '%s\n' "$merged_output" | jq -r '.attribution_skills.proxy.calls')
assert_eq "merge: attribution_skills.proxy.calls == 1" "1" "$proxy_calls"

# Verify attribution_plugins.email.calls = 3 (1+2)
email_calls=$(printf '%s\n' "$merged_output" | jq -r '.attribution_plugins.email.calls')
assert_eq "merge: attribution_plugins.email.calls == 3" "3" "$email_calls"

# Verify attribution_plugins.email.in_tok = 350 (200+150)
email_in_tok=$(printf '%s\n' "$merged_output" | jq -r '.attribution_plugins.email.in_tok')
assert_eq "merge: attribution_plugins.email.in_tok == 350" "350" "$email_in_tok"

# Verify attribution_plugins.email.out_tok = 175 (100+75)
email_out_tok=$(printf '%s\n' "$merged_output" | jq -r '.attribution_plugins.email.out_tok')
assert_eq "merge: attribution_plugins.email.out_tok == 175" "175" "$email_out_tok"

# Verify attribution_plugins.email.cache_read = 5 (0+5)
email_cache_read=$(printf '%s\n' "$merged_output" | jq -r '.attribution_plugins.email.cache_read')
assert_eq "merge: attribution_plugins.email.cache_read == 5" "5" "$email_cache_read"

# Verify attribution_plugins.email.cache_create = 30 (20+10)
email_cache_create=$(printf '%s\n' "$merged_output" | jq -r '.attribution_plugins.email.cache_create')
assert_eq "merge: attribution_plugins.email.cache_create == 30" "30" "$email_cache_create"

# Verify merged output is valid JSON
is_valid_json=$(printf '%s\n' "$merged_output" | jq . >/dev/null 2>&1; echo $?)
assert_eq "merge: output is valid JSON" "0" "$is_valid_json"

# ── --days guard: non-integer / non-positive rejected before any cache work ────
# A non-numeric --days used to make `date -v "-${days}d"` fail → empty cutoff →
# silently "no cutoff" (all sessions). Guard fires regardless of cache state.
_md_abc_out=$(CLAUDII_CACHE_DIR="$_insights_tmp" bash "$CLAUDII_HOME/bin/claudii-insights" merge --days abc 2>&1)
_md_abc_rc=$(CLAUDII_CACHE_DIR="$_insights_tmp" bash "$CLAUDII_HOME/bin/claudii-insights" merge --days abc >/dev/null 2>&1; echo $?)
assert_eq       "merge --days abc: rejected (exit 1)"   "1"                "$_md_abc_rc"
assert_contains "merge --days abc: actionable error"    "positive integer" "$_md_abc_out"
_md_zero_rc=$(CLAUDII_CACHE_DIR="$_insights_tmp" bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 0 >/dev/null 2>&1; echo $?)
assert_eq       "merge --days 0: rejected (exit 1)"     "1"                "$_md_zero_rc"
_md_ok_rc=$(CLAUDII_CACHE_DIR="$_insights_tmp" bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 >/dev/null 2>&1; echo $?)
assert_eq       "merge --days 7: accepted (exit 0)"     "0"                "$_md_ok_rc"

unset _insights_tmp _insights_cache_dir _session1_cache _session2_cache merged_output explore_calls explore_in_tok explore_out_tok explore_cache_read explore_cache_create proxy_calls email_calls email_in_tok email_out_tok email_cache_read email_cache_create is_valid_json
