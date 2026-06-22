# insights.jq — aggregates one Claude Code JSONL transcript
# Input: JSONL session file (via -R -n -f, with `--arg sid <session-id>`),
# optionally followed by the session's subagents/*.jsonl files — the parent
# file must come first so the agentId→skill map is complete before subagent
# lines stream in.
# Output: single JSON object with per-day, per-model and global counters
#
# Reads streaming via `inputs | fromjson?` so it handles multi-MB files in
# constant memory and silently skips malformed JSON lines.
#
# Tool error tracking is in-band: `pending_tools[id] = name` is set on every
# `tool_use`, looked up on the matching `tool_result`, then deleted.
# Subagent attribution is two-step in-band: an assistant `Agent` tool_use
# stores the message's attributionSkill under the tool_use id
# (`pending_agent_skill`), the matching tool_result carries
# `toolUseResult.agentId` and promotes it to `agent_skill_map[agentId]`.
# Subagent records (top-level `.agentId`) then attribute their usage to that
# skill. All transient maps are stripped from the final output.
#
# Schema versioning: bump `schema_version` on every breaking change to the
# output shape so `claudii-insights` can detect stale caches and force-rebuild.

# Parse a Claude Code ISO timestamp (may carry millis / offset) to epoch
# seconds: take YYYY-MM-DDTHH:MM:SS and force UTC. fromdateiso8601 rejects the
# fractional ".456Z" form, so the [0:19]+"Z" slice is the robust path.
def ts: .[0:19] + "Z" | fromdateiso8601;

# Repo identity from a working directory: basename, but for git worktrees
# (.../<repo>/.claude-worktrees/<wt>) collapse to the parent <repo> so a
# worktree's perf rolls up under its repo rather than a throwaway wt name.
def reponame($cwd):
  ($cwd | split("/")) as $p
  | ($p | index(".claude-worktrees")) as $w
  | (if $w != null and $w > 0 then $p[$w-1] else ($p | last) end) // "";

reduce (inputs | fromjson? // empty | select(type == "object")) as $r ({
  schema_version: 7,
  sessionId: $sid,
  project: null,           # {path, repo, branch} from cwd/gitBranch (last record wins; constant per session)
  first_seen: null,
  last_seen: null,
  messages: 0,
  assistant_messages: 0,
  days: {},                # "YYYY-MM-DD|model" -> {in_tok, out_tok, cache_read, cache_create}
  models: {},              # model -> {in_tok, cache_read, cache_create}
  attribution_skills: {},  # skill_name -> {calls, in_tok, out_tok, cache_read, cache_create}
  attribution_plugins: {}, # plugin_name -> {calls, in_tok, out_tok, cache_read, cache_create}
  attribution_mcp: {},     # mcp_tool_name -> {calls, in_tok, out_tok, cache_read, cache_create} (cost split evenly across the message's MCP tools — values may be fractional)
  attribution_models: {},  # "kind|name|model" -> {calls, in_tok, out_tok, cache_read, cache_create} (kind: skill|plugin|mcp; mcp tokens split evenly across the message's MCP tools, may be fractional) — schema v5; pre-v5 caches stored a bare calls count here
  tools: {},               # tool_name -> count
  tool_errors: {},         # tool_name -> error count
  stop_reasons: {},        # reason -> count (assistant only)
  subagent_types: {},      # type -> count (Agent calls)
  permission_modes: {},    # mode -> count
  service_tier: {},        # tier -> count
  sidechain_msgs: 0,
  thinking_blocks: 0,
  limit_hits: [],          # [{timestamp, model}]
  latency: [],             # [{day, model, dt_ms, out, ctx}] main-thread response deltas (assistant.ts - parent.ts); sidechains excluded. ctx = context-window occupancy (input + cache_read + cache_creation tokens)
  snapshots: 0,
  pending_tools: {},       # transient: tool_use_id -> tool_name
  pending_agent_skill: {}, # transient: tool_use_id -> attributionSkill at Agent spawn
  agent_skill_map: {},     # transient: agentId -> attributionSkill at spawn
  seen_ts: {},             # transient: uuid -> timestamp (resolves parentUuid -> ts for latency deltas)
  last_assistant_model: null
};
  .messages += 1
  | (if $r.uuid and $r.timestamp then .seen_ts[$r.uuid] = $r.timestamp else . end)
  | (if $r.cwd then .project = {path: $r.cwd, repo: reponame($r.cwd), branch: ($r.gitBranch // "")} else . end)
  | (if $r.timestamp and (.first_seen == null or $r.timestamp < .first_seen) then .first_seen = $r.timestamp else . end)
  | (if $r.timestamp and (.last_seen == null or $r.timestamp > .last_seen) then .last_seen = $r.timestamp else . end)
  | (if ($r.isSidechain // false) then .sidechain_msgs += 1 else . end)
  | (if ($r.isSnapshotUpdate // false) then .snapshots += 1 else . end)
  | (if $r.permissionMode then .permission_modes[$r.permissionMode] = ((.permission_modes[$r.permissionMode] // 0) + 1) else . end)
  | (if ($r.message.role // "") == "assistant" and ($r.message.usage // null) != null then
      .assistant_messages += 1
      | (($r.timestamp // "")[:10]) as $day
      | ($r.message.model // "unknown") as $model
      | .last_assistant_model = $model
      | ($day + "|" + $model) as $key
      # Effective skill: the record's own attributionSkill wins; subagent
      # records (top-level .agentId) fall back to the skill active when the
      # Agent tool spawned them. "" (spawned outside any skill) → null.
      | (($r.attributionSkill // .agent_skill_map[$r.agentId // ""] // "") | if . == "" then null else . end) as $skill
      | .days[$key].in_tok       = ((.days[$key].in_tok       // 0) + ($r.message.usage.input_tokens               // 0))
      | .days[$key].out_tok      = ((.days[$key].out_tok      // 0) + ($r.message.usage.output_tokens              // 0))
      | .days[$key].cache_read   = ((.days[$key].cache_read   // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
      | .days[$key].cache_create = ((.days[$key].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
      | .models[$model].in_tok       = ((.models[$model].in_tok       // 0) + ($r.message.usage.input_tokens               // 0))
      | .models[$model].cache_read   = ((.models[$model].cache_read   // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
      | .models[$model].cache_create = ((.models[$model].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
      # Response latency (main thread only): assistant.ts - parent.ts. Sidechain
      # records interleave concurrently, so their deltas are meaningless -> excluded.
      # The 600s cap drops resume gaps (parent from a prior day). OTEL (phase 2)
      # replaces this estimate with exact api_request.duration_ms.
      | (if (($r.isSidechain // false) | not) and $r.parentUuid and (.seen_ts[$r.parentUuid] != null) and $r.timestamp then
          ((($r.timestamp | ts) - (.seen_ts[$r.parentUuid] | ts)) * 1000 | round) as $dt
          | (if $dt >= 0 and $dt <= 600000 then
              .latency += [{day: $day, model: $model, dt_ms: $dt, out: ($r.message.usage.output_tokens // 0), ctx: (($r.message.usage.input_tokens // 0) + ($r.message.usage.cache_read_input_tokens // 0) + ($r.message.usage.cache_creation_input_tokens // 0))}]
            else . end)
        else . end)
      | (if $skill != null then
          .attribution_skills[$skill].calls       = ((.attribution_skills[$skill].calls       // 0) + 1)
          | .attribution_skills[$skill].in_tok     = ((.attribution_skills[$skill].in_tok     // 0) + ($r.message.usage.input_tokens               // 0))
          | .attribution_skills[$skill].out_tok    = ((.attribution_skills[$skill].out_tok    // 0) + ($r.message.usage.output_tokens              // 0))
          | .attribution_skills[$skill].cache_read = ((.attribution_skills[$skill].cache_read // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
          | .attribution_skills[$skill].cache_create = ((.attribution_skills[$skill].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
          | ("skill|" + $skill + "|" + $model) as $amk
          | .attribution_models[$amk].calls        = ((.attribution_models[$amk].calls        // 0) + 1)
          | .attribution_models[$amk].in_tok       = ((.attribution_models[$amk].in_tok       // 0) + ($r.message.usage.input_tokens               // 0))
          | .attribution_models[$amk].out_tok      = ((.attribution_models[$amk].out_tok      // 0) + ($r.message.usage.output_tokens              // 0))
          | .attribution_models[$amk].cache_read   = ((.attribution_models[$amk].cache_read   // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
          | .attribution_models[$amk].cache_create = ((.attribution_models[$amk].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
        else . end)
      | (if ($r.attributionPlugin // null) != null then
          .attribution_plugins[$r.attributionPlugin].calls       = ((.attribution_plugins[$r.attributionPlugin].calls       // 0) + 1)
          | .attribution_plugins[$r.attributionPlugin].in_tok     = ((.attribution_plugins[$r.attributionPlugin].in_tok     // 0) + ($r.message.usage.input_tokens               // 0))
          | .attribution_plugins[$r.attributionPlugin].out_tok    = ((.attribution_plugins[$r.attributionPlugin].out_tok    // 0) + ($r.message.usage.output_tokens              // 0))
          | .attribution_plugins[$r.attributionPlugin].cache_read = ((.attribution_plugins[$r.attributionPlugin].cache_read // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
          | .attribution_plugins[$r.attributionPlugin].cache_create = ((.attribution_plugins[$r.attributionPlugin].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
          | ("plugin|" + $r.attributionPlugin + "|" + $model) as $amk
          | .attribution_models[$amk].calls        = ((.attribution_models[$amk].calls        // 0) + 1)
          | .attribution_models[$amk].in_tok       = ((.attribution_models[$amk].in_tok       // 0) + ($r.message.usage.input_tokens               // 0))
          | .attribution_models[$amk].out_tok      = ((.attribution_models[$amk].out_tok      // 0) + ($r.message.usage.output_tokens              // 0))
          | .attribution_models[$amk].cache_read   = ((.attribution_models[$amk].cache_read   // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
          | .attribution_models[$amk].cache_create = ((.attribution_models[$amk].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
        else . end)
      # MCP attribution: the message's usage is split evenly across all MCP
      # tool_use entries in it (values may be fractional). calls counts whole
      # invocations per tool.
      | ([$r.message.content[]? | select(.type == "tool_use" and ((.name // "") | startswith("mcp__"))) | .name]) as $mcp
      | (if ($mcp | length) > 0 then
          ($mcp | length) as $n
          | reduce $mcp[] as $mt (.;
              .attribution_mcp[$mt].calls       = ((.attribution_mcp[$mt].calls       // 0) + 1)
              | .attribution_mcp[$mt].in_tok     = ((.attribution_mcp[$mt].in_tok     // 0) + (($r.message.usage.input_tokens               // 0) / $n))
              | .attribution_mcp[$mt].out_tok    = ((.attribution_mcp[$mt].out_tok    // 0) + (($r.message.usage.output_tokens              // 0) / $n))
              | .attribution_mcp[$mt].cache_read = ((.attribution_mcp[$mt].cache_read // 0) + (($r.message.usage.cache_read_input_tokens    // 0) / $n))
              | .attribution_mcp[$mt].cache_create = ((.attribution_mcp[$mt].cache_create // 0) + (($r.message.usage.cache_creation_input_tokens // 0) / $n))
              | ("mcp|" + $mt + "|" + $model) as $amk
              | .attribution_models[$amk].calls        = ((.attribution_models[$amk].calls        // 0) + 1)
              | .attribution_models[$amk].in_tok       = ((.attribution_models[$amk].in_tok       // 0) + (($r.message.usage.input_tokens               // 0) / $n))
              | .attribution_models[$amk].out_tok      = ((.attribution_models[$amk].out_tok      // 0) + (($r.message.usage.output_tokens              // 0) / $n))
              | .attribution_models[$amk].cache_read   = ((.attribution_models[$amk].cache_read   // 0) + (($r.message.usage.cache_read_input_tokens    // 0) / $n))
              | .attribution_models[$amk].cache_create = ((.attribution_models[$amk].cache_create // 0) + (($r.message.usage.cache_creation_input_tokens // 0) / $n))
            )
        else . end)
      | (if $r.message.usage.service_tier then .service_tier[$r.message.usage.service_tier] = ((.service_tier[$r.message.usage.service_tier] // 0) + 1) else . end)
      | (if $r.message.stop_reason then .stop_reasons[$r.message.stop_reason] = ((.stop_reasons[$r.message.stop_reason] // 0) + 1) else . end)
      | (if (($r.message.content // null) | type) == "array" then
          reduce ($r.message.content[]?) as $c (.;
            (if $c.type == "thinking" then .thinking_blocks += 1 else . end)
            | (if $c.type == "tool_use" then
                .tools[$c.name] = ((.tools[$c.name] // 0) + 1)
                | (if ($c.id // "") != "" then .pending_tools[$c.id] = $c.name else . end)
                | (if $c.name == "Agent" then
                    .subagent_types[($c.input.subagent_type // "unknown")] = ((.subagent_types[($c.input.subagent_type // "unknown")] // 0) + 1)
                    | (if ($c.id // "") != "" then .pending_agent_skill[$c.id] = ($r.attributionSkill // "") else . end)
                  else . end)
              else . end)
          )
        else . end)
    else . end)
  | (if ($r.message.role // "") == "user" and (($r.message.content // null) | type) == "array" then
      reduce ($r.message.content[]?) as $c (.;
        (if $c.type == "tool_result" then
          ($c.tool_use_id // "") as $tid
          | (.pending_tools[$tid] // "unknown") as $tname
          | (if ($c.is_error // false) then
              .tool_errors[$tname] = ((.tool_errors[$tname] // 0) + 1)
            else . end)
          | (if (($c.content // "") | tostring | contains("hit your limit")) then
              .limit_hits += [{timestamp: ($r.timestamp // ""), model: (.last_assistant_model // "unknown")}]
            else . end)
          # Agent tool_result: promote the skill recorded at spawn to the
          # agentId so subagent transcript lines can attribute to it.
          | (($r.toolUseResult // null | if type == "object" then (.agentId // null) else null end)) as $aid
          | (if $aid != null then
              .agent_skill_map[$aid] = (.pending_agent_skill[$tid] // "")
              | del(.pending_agent_skill[$tid])
            else . end)
          | (if $tid != "" then del(.pending_tools[$tid]) else . end)
        else . end)
      )
    else . end)
)
| del(.pending_tools)
| del(.pending_agent_skill)
| del(.agent_skill_map)
| del(.seen_ts)
| del(.last_assistant_model)
