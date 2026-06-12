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
  },
  "attribution_mcp": {
    "mcp__srv__alpha": {
      "calls": 2,
      "in_tok": 50.5,
      "out_tok": 25,
      "cache_read": 10,
      "cache_create": 0
    }
  },
  "attribution_models": {
    "skill|explore|claude-opus-4-7": 2,
    "mcp|mcp__srv__alpha|claude-sonnet-4-6": 2
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
  },
  "attribution_mcp": {
    "mcp__srv__alpha": {
      "calls": 1,
      "in_tok": 24.5,
      "out_tok": 5,
      "cache_read": 0,
      "cache_create": 2
    }
  },
  "attribution_models": {
    "skill|explore|claude-opus-4-7": 1,
    "skill|explore|claude-sonnet-4-6": 1
  }
}
JSON

# Create a third cache in the NEW v5 shape: attribution_models values are
# {calls, tokens} objects. It shares the opus key with sessions 1 & 2 (scalar),
# so the merge must sum a coerced scalar {calls:3} with a real object {calls:2,
# in_tok:600,...} → {calls:5, in_tok:600,...} — the mixed-schema path that
# happens for real once a v5 session lands among orphaned v4 caches.
# attribution_skills is left empty on purpose so the explore aggregate asserts
# above stay isolated from this fixture; this row exercises only add_models.
_session3_cache="$_insights_cache_dir/session-3.json"
cat > "$_session3_cache" <<'JSON'
{
  "schema_version": 5,
  "sessionId": "session-3",
  "first_seen": "2026-06-12T10:00:00Z",
  "last_seen": "2026-06-12T11:00:00Z",
  "messages": 4, "assistant_messages": 2, "sidechain_msgs": 0, "thinking_blocks": 0,
  "limit_hits": [], "snapshots": 0, "days": {}, "models": {}, "tools": {},
  "tool_errors": {}, "stop_reasons": {}, "subagent_types": {}, "permission_modes": {}, "service_tier": {},
  "attribution_skills": {},
  "attribution_plugins": {},
  "attribution_mcp": {},
  "attribution_models": {
    "skill|explore|claude-opus-4-7": { "calls": 2, "in_tok": 600, "out_tok": 300, "cache_read": 40, "cache_create": 10 }
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

# ── attribution_mcp: nested sums incl. fractional token shares ───────────────
mcp_calls=$(printf '%s\n' "$merged_output" | jq -r '.attribution_mcp["mcp__srv__alpha"].calls')
assert_eq "merge: attribution_mcp.alpha.calls == 3" "3" "$mcp_calls"
mcp_in_tok=$(printf '%s\n' "$merged_output" | jq -r '.attribution_mcp["mcp__srv__alpha"].in_tok')
assert_eq "merge: attribution_mcp.alpha.in_tok == 75 (50.5+24.5)" "75" "$mcp_in_tok"

# ── attribution_models: per-model {calls, tokens} objects ────────────────────
# Sessions 1 & 2 carry the pre-v5 SCALAR shape (bare calls count). add_models
# coerces a scalar to {calls: N} before summing, so orphaned v4 caches keep
# contributing their calls. The merged value is therefore an OBJECT here.
am_opus=$(printf '%s\n' "$merged_output" | jq -r '.attribution_models["skill|explore|claude-opus-4-7"].calls')
assert_eq "merge: attribution_models skill|explore|opus calls == 5 (scalar 2+1 coerced + object 2)" "5" "$am_opus"
# Only session-3 (v5) carried per-model tokens for this key; the coerced scalars
# add 0 to in_tok. Mixed-schema sum must surface session-3's tokens intact.
am_opus_in=$(printf '%s\n' "$merged_output" | jq -r '.attribution_models["skill|explore|claude-opus-4-7"].in_tok')
assert_eq "merge: attribution_models opus in_tok == 600 (v5 object only)" "600" "$am_opus_in"
am_opus_cc=$(printf '%s\n' "$merged_output" | jq -r '.attribution_models["skill|explore|claude-opus-4-7"].cache_create')
assert_eq "merge: attribution_models opus cache_create == 10 (v5 object only)" "10" "$am_opus_cc"
am_sonnet=$(printf '%s\n' "$merged_output" | jq -r '.attribution_models["skill|explore|claude-sonnet-4-6"].calls')
assert_eq "merge: attribution_models skill|explore|sonnet calls == 1 (one session)" "1" "$am_sonnet"
am_mcp=$(printf '%s\n' "$merged_output" | jq -r '.attribution_models["mcp|mcp__srv__alpha|claude-sonnet-4-6"].calls')
assert_eq "merge: attribution_models mcp key calls == 2" "2" "$am_mcp"

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

unset _insights_tmp _insights_cache_dir _session1_cache _session2_cache _session3_cache merged_output explore_calls explore_in_tok explore_out_tok explore_cache_read explore_cache_create proxy_calls email_calls email_in_tok email_out_tok email_cache_read email_cache_create is_valid_json mcp_calls mcp_in_tok am_opus am_opus_in am_opus_cc am_sonnet am_mcp
