# insights.jq — aggregates one Claude Code JSONL transcript
# Input: JSONL session file (via -R -n -f, with `--arg sid <session-id>`)
# Output: single JSON object with per-day, per-model and global counters
#
# Reads streaming via `inputs | fromjson?` so it handles multi-MB files in
# constant memory and silently skips malformed JSON lines.
#
# Tool error tracking is in-band: `pending_tools[id] = name` is set on every
# `tool_use`, looked up on the matching `tool_result`, then deleted. Both the
# pending_tools and last_assistant_model fields are transient bookkeeping —
# stripped from the final output.
#
# Schema versioning: bump `schema_version` on every breaking change to the
# output shape so `claudii-insights` can detect stale caches and force-rebuild.

reduce (inputs | fromjson? // empty | select(type == "object")) as $r ({
  schema_version: 3,
  sessionId: $sid,
  first_seen: null,
  last_seen: null,
  messages: 0,
  assistant_messages: 0,
  days: {},                # "YYYY-MM-DD|model" -> {in_tok, out_tok, cache_read, cache_create}
  models: {},              # model -> {in_tok, cache_read, cache_create}
  attribution_skills: {},  # skill_name -> {calls, in_tok, out_tok, cache_read, cache_create}
  attribution_plugins: {}, # plugin_name -> {calls, in_tok, out_tok, cache_read, cache_create}
  tools: {},               # tool_name -> count
  tool_errors: {},         # tool_name -> error count
  stop_reasons: {},        # reason -> count (assistant only)
  subagent_types: {},      # type -> count (Agent calls)
  permission_modes: {},    # mode -> count
  service_tier: {},        # tier -> count
  sidechain_msgs: 0,
  thinking_blocks: 0,
  limit_hits: [],          # [{timestamp, model}]
  snapshots: 0,
  pending_tools: {},       # transient: tool_use_id -> tool_name
  last_assistant_model: null
};
  .messages += 1
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
      | .days[$key].in_tok       = ((.days[$key].in_tok       // 0) + ($r.message.usage.input_tokens               // 0))
      | .days[$key].out_tok      = ((.days[$key].out_tok      // 0) + ($r.message.usage.output_tokens              // 0))
      | .days[$key].cache_read   = ((.days[$key].cache_read   // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
      | .days[$key].cache_create = ((.days[$key].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
      | .models[$model].in_tok       = ((.models[$model].in_tok       // 0) + ($r.message.usage.input_tokens               // 0))
      | .models[$model].cache_read   = ((.models[$model].cache_read   // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
      | .models[$model].cache_create = ((.models[$model].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
      | (if ($r.attributionSkill // null) != null then
          .attribution_skills[$r.attributionSkill].calls       = ((.attribution_skills[$r.attributionSkill].calls       // 0) + 1)
          | .attribution_skills[$r.attributionSkill].in_tok     = ((.attribution_skills[$r.attributionSkill].in_tok     // 0) + ($r.message.usage.input_tokens               // 0))
          | .attribution_skills[$r.attributionSkill].out_tok    = ((.attribution_skills[$r.attributionSkill].out_tok    // 0) + ($r.message.usage.output_tokens              // 0))
          | .attribution_skills[$r.attributionSkill].cache_read = ((.attribution_skills[$r.attributionSkill].cache_read // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
          | .attribution_skills[$r.attributionSkill].cache_create = ((.attribution_skills[$r.attributionSkill].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
        else . end)
      | (if ($r.attributionPlugin // null) != null then
          .attribution_plugins[$r.attributionPlugin].calls       = ((.attribution_plugins[$r.attributionPlugin].calls       // 0) + 1)
          | .attribution_plugins[$r.attributionPlugin].in_tok     = ((.attribution_plugins[$r.attributionPlugin].in_tok     // 0) + ($r.message.usage.input_tokens               // 0))
          | .attribution_plugins[$r.attributionPlugin].out_tok    = ((.attribution_plugins[$r.attributionPlugin].out_tok    // 0) + ($r.message.usage.output_tokens              // 0))
          | .attribution_plugins[$r.attributionPlugin].cache_read = ((.attribution_plugins[$r.attributionPlugin].cache_read // 0) + ($r.message.usage.cache_read_input_tokens    // 0))
          | .attribution_plugins[$r.attributionPlugin].cache_create = ((.attribution_plugins[$r.attributionPlugin].cache_create // 0) + ($r.message.usage.cache_creation_input_tokens // 0))
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
          | (if $tid != "" then del(.pending_tools[$tid]) else . end)
        else . end)
      )
    else . end)
)
| del(.pending_tools)
| del(.last_assistant_model)
