# insights.jq — aggregates one Claude Code JSONL transcript
# Input: JSONL session file (via -R -n -f, with `--arg sid <session-id>`),
# optionally followed by the session's subagents/*.jsonl files — the parent
# file must come first so the agentId→skill map is complete before subagent
# lines stream in.
# Output: single JSON object with per-day, per-model and global counters
#
# Reads streaming via `inputs | fromjson?` — records are never slurped, the
# state grows only by small per-record/per-message maps (seen_ts, msgs) — and
# silently skips malformed JSON lines.
#
# One API response, several records: Claude Code writes an assistant message
# as one record per content block (thinking, text, each tool_use), each
# carrying the same message.id and a usage object. Summed per record, every
# response counted 2-3× (one machine: 7982 records, 3617 responses). Usage is
# therefore folded per message.id into the transient `msgs` map and charged
# once, after the last record: token counters, latency sample, stop reason,
# service tier and the attribution blocks. Each usage counter takes the
# largest value seen across the message's records — main-thread records
# repeat the final usage, subagent records written mid-stream carry the
# message_start usage (output_tokens 1-8) and only the last one the final
# count; the counters only grow, so the maximum is the final value in any
# record order. A record without message.id counts as its own message.
# Content blocks (tools, thinking_blocks, subagent_types) stay per record —
# each block lives in exactly one record.
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
# (.../<repo>/.claude-worktrees/<wt> — old style — or
#  .../<repo>/.claude/worktrees/<wt> — current harness style) collapse to the
# parent <repo> so a worktree's activity rolls up under its repo rather than a
# throwaway agent-* name.
def reponame($cwd):
  ($cwd | split("/")) as $p
  | ($p | index(".claude-worktrees")) as $w
  | ($p | index(".claude")) as $c
  | (if $w != null and $w > 0 then $p[$w-1]
     elif $c != null and $c > 0 and $p[$c+1] == "worktrees" then $p[$c-1]
     else ($p | last) end) // "";

# Charge one message's folded usage $m to an attribution bucket {calls,
# in_tok, out_tok, cache_read, cache_create, cache_create_1h}: one call, the
# tokens divided by $n — 1 for a skill or plugin, the number of the message's
# MCP tool_use entries for the MCP split (values may go fractional).
#
# A request whose prompt (input + cache_read + cache_create, cached tokens
# included) is over 100,000 tokens also lands in the long_* counters — the
# part of the totals that Haiku 5.5 bills at its higher per-request rate
# (strictly over; exactly 100,000 is still the lower tier). The sums above
# cannot be split afterwards, so the split has to be taken per message here.
def charge($m; $n):
  .calls             = ((.calls             // 0) + 1)
  | .in_tok          = ((.in_tok          // 0) + $m.in   / $n)
  | .out_tok         = ((.out_tok         // 0) + $m.out  / $n)
  | .cache_read      = ((.cache_read      // 0) + $m.cr   / $n)
  | .cache_create    = ((.cache_create    // 0) + $m.cc   / $n)
  | .cache_create_1h = ((.cache_create_1h // 0) + $m.cc1h / $n)
  | (if ($m.in + $m.cr + $m.cc) > 100000 then
       .long_in_tok          = ((.long_in_tok          // 0) + $m.in   / $n)
       | .long_out_tok         = ((.long_out_tok         // 0) + $m.out  / $n)
       | .long_cache_read      = ((.long_cache_read      // 0) + $m.cr   / $n)
       | .long_cache_create    = ((.long_cache_create    // 0) + $m.cc   / $n)
       | .long_cache_create_1h = ((.long_cache_create_1h // 0) + $m.cc1h / $n)
     else . end);

reduce (inputs | fromjson? // empty | select(type == "object")) as $r ({
  schema_version: 15,
  sessionId: $sid,
  project: null,           # {path, repo, branch} from cwd/gitBranch (last record wins; constant per session)
  first_seen: null,
  last_seen: null,
  active_by_day: {},       # "YYYY-MM-DD" -> active seconds (gap-capped main-thread deltas; gaps > 600s count as idle, matching the latency cap). last_seen - first_seen is wall clock incl. idle/resume — this is the "real" working time.
  messages: 0,             # transcript records of every type
  assistant_messages: 0,   # API responses with usage (distinct message.id — schema v12; earlier caches counted records)
  days: {},                # "YYYY-MM-DD|model" -> {in_tok, out_tok, cache_read, cache_create, cache_create_1h} (each message once, on its first record's day; cache_create_1h since schema v13 — `claudii cost` prices insights-only sessions from it; long_* as in attribution_models since schema v15)
  models: {},              # model -> {in_tok, cache_read, cache_create}
  attribution_skills: {},  # skill_name -> {calls, in_tok, out_tok, cache_read, cache_create, cache_create_1h} (calls = messages)
  attribution_plugins: {}, # plugin_name -> {calls, in_tok, out_tok, cache_read, cache_create, cache_create_1h}
  attribution_mcp: {},     # mcp_tool_name -> {calls, in_tok, out_tok, cache_read, cache_create, cache_create_1h} (cost split evenly across the message's MCP tools — values may be fractional)
  attribution_models: {},  # "kind|name|model" -> {calls, in_tok, out_tok, cache_read, cache_create, cache_create_1h} (kind: skill|plugin|mcp; mcp tokens split evenly across the message's MCP tools, may be fractional) — schema v5; pre-v5 caches stored a bare calls count here. cache_create is every cache write, cache_create_1h (schema v11) the part of it written to the 1-hour cache. long_in_tok/long_out_tok/long_cache_read/long_cache_create/long_cache_create_1h (schema v14, present only once a request qualified) are the part of those totals from requests whose prompt (input + cache_read + cache_create) was over 100,000 tokens
  tools: {},               # tool_name -> count
  tool_errors: {},         # tool_name -> error count
  stop_reasons: {},        # reason -> count (assistant only)
  subagent_types: {},      # type -> count (Agent calls)
  permission_modes: {},    # mode -> count
  service_tier: {},        # tier -> count
  sidechain_msgs: 0,
  thinking_blocks: 0,
  limit_hits: [],          # [{timestamp, model}]
  latency: [],             # [{day, model, dt_ms, out, ctx}] one per main-thread response: its last record's ts - the ts of the record it answers (its first record's parent); sidechains excluded. ctx = context-window occupancy (input + cache_read + cache_creation tokens)
  snapshots: 0,
  msgs: {},                # transient: message.id (else "rec:<record ordinal>") -> {day, model, skill, plugin, t0, t1, in, out, cr, cc, cc1h, mcp, tier, stop} — one API response folded across its records, charged once after the last one
  pending_tools: {},       # transient: tool_use_id -> tool_name
  pending_agent_skill: {}, # transient: tool_use_id -> attributionSkill at Agent spawn
  agent_skill_map: {},     # transient: agentId -> attributionSkill at spawn
  seen_ts: {},             # transient: uuid -> timestamp (resolves parentUuid -> ts for latency deltas)
  last_main_ts: null,      # transient: epoch of the previous main-thread record (active-time deltas)
  last_assistant_model: null
};
  .messages += 1
  | (if $r.uuid and $r.timestamp then .seen_ts[$r.uuid] = $r.timestamp else . end)
  | (if $r.cwd then .project = {path: $r.cwd, repo: reponame($r.cwd), branch: ($r.gitBranch // "")} else . end)
  | (if $r.timestamp and (.first_seen == null or $r.timestamp < .first_seen) then .first_seen = $r.timestamp else . end)
  | (if $r.timestamp and (.last_seen == null or $r.timestamp > .last_seen) then .last_seen = $r.timestamp else . end)
  # Active time: delta between consecutive MAIN-THREAD records, credited to the
  # current record's day. Sidechain/subagent records interleave (subagent files
  # stream after the parent) and would produce negative or double-counted
  # deltas — excluded; their runtime is covered by the main thread's own
  # Agent-call gap anyway. isSnapshotUpdate records (file-watcher snapshots
  # taken while the user is away) are excluded too: they would credit up to the
  # 600s gap-cap of idle time as active work. A truthy-but-unparseable timestamp
  # ("" is TRUTHY in jq) must neither credit time NOR move .last_main_ts — the
  # try-parse yields null and the whole record is skipped for active purposes.
  | (if $r.timestamp and (($r.isSidechain // false) | not) and (($r.isSnapshotUpdate // false) | not) and (($r.agentId // null) == null) then
      (try ($r.timestamp | ts) catch null) as $t
      | (if $t == null then .
         else
           (if .last_main_ts != null and ($t - .last_main_ts) > 0 and ($t - .last_main_ts) <= 600 then
              (($r.timestamp // "")[:10]) as $ad
              | .active_by_day[$ad] = ((.active_by_day[$ad] // 0) + ($t - .last_main_ts))
            else . end)
           | .last_main_ts = $t
         end)
    else . end)
  | (if ($r.isSidechain // false) then .sidechain_msgs += 1 else . end)
  | (if ($r.isSnapshotUpdate // false) then .snapshots += 1 else . end)
  | (if $r.permissionMode then .permission_modes[$r.permissionMode] = ((.permission_modes[$r.permissionMode] // 0) + 1) else . end)
  | (if ($r.message.role // "") == "assistant" and ($r.message.usage // null) != null then
      (($r.timestamp // "")[:10]) as $day
      | ($r.message.model // "unknown") as $model
      # 5h session-limit hits arrive as synthetic assistant messages
      # (model: "<synthetic>", isApiErrorMessage:true, error:"rate_limit"),
      # never as a tool_result. Scope to "hit your session limit" text —
      # "rate_limit" also covers the monthly spend cap and transient
      # server-side throttling ("not your usage limit"), which are a
      # different budget than the one this command reports on. Attribute to
      # .last_assistant_model (still the pre-overwrite value here) since the
      # synthetic record itself carries no real model.
      | (if ($r.isApiErrorMessage // false) and (($r.error // "") == "rate_limit")
            and (($r.message.content // [] | map(select(.type == "text") | (.text // "")) | join(""))
                 | contains("hit your session limit")) then
          .limit_hits += [{timestamp: ($r.timestamp // ""), model: (.last_assistant_model // "unknown")}]
        else . end)
      | .last_assistant_model = $model
      # Effective skill: the record's own attributionSkill wins; subagent
      # records (top-level .agentId) fall back to the skill active when the
      # Agent tool spawned them. "" (spawned outside any skill) → null.
      | (($r.attributionSkill // .agent_skill_map[$r.agentId // ""] // "") | if . == "" then null else . end) as $skill
      # 1-hour share of the cache write: usage.cache_creation splits
      # cache_creation_input_tokens by TTL, and a 1h write bills 2× input where
      # a 5m write bills 1.25× — Claude Code writes the main conversation to
      # the 1h cache, subagents to the 5m one. Only the attribution blocks carry
      # it: skills-cost is the one consumer that prices tokens. A message without
      # the split adds 0 here, so its writes keep the 5m price every write had
      # before schema v11 rather than a guessed TTL.
      | ($r.message.usage.cache_creation // null | if type == "object" then (.ephemeral_1h_input_tokens // 0) else 0 end) as $cc1h
      # Fold this record into its message (see the header). message.id alone
      # is the key: on the transcripts checked it never spanned two requestIds
      # nor two files. The day, model and latency start come from the first
      # record; the start (t0) is the record the response answers, main thread
      # only — sidechain records interleave concurrently, so their deltas are
      # meaningless. t1 runs to the message's last record: the response ends
      # with its last block, which can stream for a while after the first.
      | (($r.message.id // "") | tostring) as $mid
      | (if $mid != "" then $mid else "rec:" + (.messages | tostring) end) as $mk
      | (if .msgs[$mk] == null then
          .msgs[$mk] = {day: $day, model: $model, skill: null, plugin: null,
            t0: (if (($r.isSidechain // false) | not) and $r.parentUuid and (.seen_ts[$r.parentUuid] != null)
                 then (try (.seen_ts[$r.parentUuid] | ts) catch null) else null end),
            t1: null, in: 0, out: 0, cr: 0, cc: 0, cc1h: 0, mcp: [], tier: null, stop: null}
        else . end)
      | ($r.message.usage) as $u
      | .msgs[$mk] |= (
          .skill    = (.skill  // $skill)
          | .plugin = (.plugin // $r.attributionPlugin)
          | .t1     = ([.t1, (try ($r.timestamp | ts) catch null)] | max)
          | .in     = ([.in,   ($u.input_tokens                // 0)] | max)
          | .out    = ([.out,  ($u.output_tokens               // 0)] | max)
          | .cr     = ([.cr,   ($u.cache_read_input_tokens     // 0)] | max)
          | .cc     = ([.cc,   ($u.cache_creation_input_tokens // 0)] | max)
          | .cc1h   = ([.cc1h, $cc1h] | max)
          # every MCP tool_use of the message, whichever record carries it
          | .mcp   += [$r.message.content[]? | select(.type == "tool_use" and ((.name // "") | startswith("mcp__"))) | .name]
          | .tier   = (.tier // $u.service_tier)
          | .stop   = ($r.message.stop_reason // .stop))
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
# Charge every message once (see the header) — after the last record, so the
# MCP split and the latency end see all of a message's records, even where a
# tool_result was written between two of them.
| .msgs as $msgs
| del(.msgs)
| reduce $msgs[] as $m (.;
    .assistant_messages += 1
    | ($m.day + "|" + $m.model) as $key
    | .days[$key].in_tok       = ((.days[$key].in_tok       // 0) + $m.in)
    | .days[$key].out_tok      = ((.days[$key].out_tok      // 0) + $m.out)
    | .days[$key].cache_read   = ((.days[$key].cache_read   // 0) + $m.cr)
    | .days[$key].cache_create = ((.days[$key].cache_create // 0) + $m.cc)
    | .days[$key].cache_create_1h = ((.days[$key].cache_create_1h // 0) + $m.cc1h)
    | (if ($m.in + $m.cr + $m.cc) > 100000 then
         .days[$key].long_in_tok          = ((.days[$key].long_in_tok          // 0) + $m.in)
         | .days[$key].long_out_tok         = ((.days[$key].long_out_tok         // 0) + $m.out)
         | .days[$key].long_cache_read      = ((.days[$key].long_cache_read      // 0) + $m.cr)
         | .days[$key].long_cache_create    = ((.days[$key].long_cache_create    // 0) + $m.cc)
         | .days[$key].long_cache_create_1h = ((.days[$key].long_cache_create_1h // 0) + $m.cc1h)
       else . end)
    | .models[$m.model].in_tok       = ((.models[$m.model].in_tok       // 0) + $m.in)
    | .models[$m.model].cache_read   = ((.models[$m.model].cache_read   // 0) + $m.cr)
    | .models[$m.model].cache_create = ((.models[$m.model].cache_create // 0) + $m.cc)
    # Response latency (main thread only): the response's last record minus
    # the record it answers. The 600s cap drops resume gaps (parent from a
    # prior day). OTEL (phase 2) replaces this estimate with exact
    # api_request.duration_ms.
    | (if $m.t0 != null and $m.t1 != null then
        (($m.t1 - $m.t0) * 1000 | round) as $dt
        | (if $dt >= 0 and $dt <= 600000 then
            .latency += [{day: $m.day, model: $m.model, dt_ms: $dt, out: $m.out, ctx: ($m.in + $m.cr + $m.cc)}]
          else . end)
      else . end)
    | (if $m.skill != null then
        .attribution_skills[$m.skill] |= charge($m; 1)
        | .attribution_models["skill|" + $m.skill + "|" + $m.model] |= charge($m; 1)
      else . end)
    | (if $m.plugin != null then
        .attribution_plugins[$m.plugin] |= charge($m; 1)
        | .attribution_models["plugin|" + $m.plugin + "|" + $m.model] |= charge($m; 1)
      else . end)
    # MCP attribution: the message's usage is split evenly across all MCP
    # tool_use entries in it (values may be fractional). calls counts whole
    # invocations per tool.
    | ($m.mcp | length) as $n
    | reduce $m.mcp[] as $mt (.;
        .attribution_mcp[$mt] |= charge($m; $n)
        | .attribution_models["mcp|" + $mt + "|" + $m.model] |= charge($m; $n))
    | (if $m.tier then .service_tier[$m.tier] = ((.service_tier[$m.tier] // 0) + 1) else . end)
    | (if $m.stop then .stop_reasons[$m.stop] = ((.stop_reasons[$m.stop] // 0) + 1) else . end)
  )
| del(.pending_tools)
| del(.pending_agent_skill)
| del(.agent_skill_map)
| del(.seen_ts)
| del(.last_main_ts)
| del(.last_assistant_model)
