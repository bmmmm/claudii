# insights-merge.jq — merge per-session insights caches into one aggregate.
# Called from _cmd_merge (bin/claudii-insights) with:
#   jq -n --arg cutoff <iso|""> --arg until <iso|""> --arg project <path|"">
#      -f lib/insights-merge.jq <cache files...>
# Window filters: cutoff = include sessions with last_seen >= cutoff;
# until = include sessions with last_seen < until (bounded window for
# `skills-cost --compare`'s prior period). Empty string = no bound.
def add_obj(a; b): reduce (b // {} | to_entries[]) as $e (a; .[$e.key] = ((.[$e.key] // 0) + $e.value));
def add_obj_nested(a; b):
  reduce (b // {} | to_entries[]) as $e (a;
    .[$e.key] = (
      reduce ($e.value | to_entries[]) as $f ((.[$e.key] // {}); .[$f.key] = ((.[$f.key] // 0) + $f.value))
    )
  );
# attribution_models merge — tolerant of the pre-v5 shape where each value
# was a bare calls count: coerce a scalar to {calls: N} before summing, so
# orphaned v4 caches (source JSONL gone, can never be re-aggregated) keep
# contributing their call counts alongside the per-model token objects v5
# writes.
def add_models(a; b):
  reduce (b // {} | to_entries[]) as $e (a;
    ($e.value | if type == "object" then . else {calls: .} end) as $v
    | .[$e.key] = (
        reduce ($v | to_entries[]) as $f ((.[$e.key] // {}); .[$f.key] = ((.[$f.key] // 0) + $f.value))
      )
  );

[inputs
  | select(($cutoff == "") or ((.last_seen // "") >= $cutoff))
  | select(($until == "")  or ((.last_seen // "") <  $until))
] as $all
| reduce $all[] as $s (
    {
      sessions: 0,
      messages: 0,
      assistant_messages: 0,
      sidechain_msgs: 0,
      thinking_blocks: 0,
      limit_hits: [],
      snapshots: 0,
      first_seen: null,
      last_seen: null,
      days: {},
      models: {},
      tools: {},
      tool_errors: {},
      stop_reasons: {},
      subagent_types: {},
      permission_modes: {},
      service_tier: {},
      attribution_skills: {},
      attribution_plugins: {},
      attribution_mcp: {},
      attribution_models: {}
    };
    .sessions += 1
    | .messages += ($s.messages // 0)
    | .assistant_messages += ($s.assistant_messages // 0)
    | .sidechain_msgs += ($s.sidechain_msgs // 0)
    | .thinking_blocks += ($s.thinking_blocks // 0)
    | .limit_hits += [ ($s.limit_hits // [])[] | . + {sessionId: $s.sessionId} ]
    | .snapshots += ($s.snapshots // 0)
    | (if $s.first_seen and (.first_seen == null or $s.first_seen < .first_seen) then .first_seen = $s.first_seen else . end)
    | (if $s.last_seen  and (.last_seen  == null or $s.last_seen  > .last_seen)  then .last_seen  = $s.last_seen  else . end)
    | .days = add_obj_nested(.days; $s.days)
    | .models = add_obj_nested(.models; $s.models)
    | .tools = add_obj(.tools; $s.tools)
    | .tool_errors = add_obj(.tool_errors; $s.tool_errors)
    | .stop_reasons = add_obj(.stop_reasons; $s.stop_reasons)
    | .subagent_types = add_obj(.subagent_types; $s.subagent_types)
    | .permission_modes = add_obj(.permission_modes; $s.permission_modes)
    | .service_tier = add_obj(.service_tier; $s.service_tier)
    | .attribution_skills = add_obj_nested(.attribution_skills; $s.attribution_skills)
    | .attribution_plugins = add_obj_nested(.attribution_plugins; $s.attribution_plugins)
    | .attribution_mcp = add_obj_nested(.attribution_mcp; $s.attribution_mcp)
    | .attribution_models = add_models(.attribution_models; $s.attribution_models)
  )
