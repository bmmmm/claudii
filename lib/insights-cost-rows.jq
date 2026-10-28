# insights-cost-rows.jq — the insights side of `claudii cost`: every session's
# token buckets priced at the _CLAUDII_RATES table, as rows in the shape stage
# 2 of _cmd_cost_from_history (lib/cmd/cost.sh) reads.
#
# Called with:
#   _insights_stream_tagged <cache>/insights \
#     | jq -rn -L lib --argjson rates "$_CLAUDII_RATES" -f lib/insights-cost-rows.jq
#
# Why: history (the statusline's Flight Recorder) is the cost source, but a
# claudii whose sessions never render a statusline — T3 Code, the Agent SDK,
# `claude -p` — writes no history at all, so a `claudii sync` mirror of such a
# host showed its tokens and no cost. Its insights caches still carry every
# response's usage per day and model, which is enough to price it.
#
# One row per session × day × model, chronological per session, fields as
# stage 2's emit list names them: day model cost sid raw in out ts host src
#   cost/in/out  session-cumulative, like the history columns — stage 2's
#                attr_delta() turns them back into per-row increments
#   day          the UTC day the insights aggregator bucketed on (history days
#                are local; the two differ only for responses near midnight)
#   ts           noon UTC of that day — enough for the --window cut, which is
#                then accurate to the day, not the hour
#   host         "" for this claudii, else the sync mirror name (the marker)
#   src          "i": stage 2 drops the row when history already covers the
#                session, so a session is never counted twice
# Only the four Claude tiers are priced; anything else (a local model routed
# through omlx, "<synthetic>") has no list price and stays out.
include "tier";

def tier_name($m):
  ($m | ascii_downcase) as $l
  | if   ($l | test("(^|[^a-z])(fable|mythos)([^a-z]|$)")) then "Fable"
    elif ($l | test("(^|[^a-z])opus([^a-z]|$)"))   then "Opus"
    elif ($l | test("(^|[^a-z])sonnet([^a-z]|$)")) then "Sonnet"
    elif ($l | test("(^|[^a-z])haiku([^a-z]|$)"))  then "Haiku"
    else "" end;

# "claude-opus-5-5" -> "Opus 5.5", the form the history model column carries
# (the cost legend prefers a versioned name). Mythos bills and labels as Fable,
# without a version (see _insights_model_label in lib/cmd/insights.sh).
def display($m; $t):
  ($m | ascii_downcase) as $l
  | if ($l | test("mythos")) then "Fable"
    else ($l | capture("(fable|opus|sonnet|haiku)-(?<a>[0-9])(-(?<b>[0-9]))?($|[^0-9])") // null) as $c
      | if $c == null then $t
        elif $c.b == null then "\($t) \($c.a)"
        else "\($t) \($c.a).\($c.b)" end
    end;

foreach inputs as $i ({h: "", s: null};
    if ($i | type) == "object" and ($i | has("_claudii_host"))
    then {h: ($i._claudii_host // ""), s: null}
    else {h: .h, s: $i} end;
    select(.s != null) | {h, s})
| .h as $h | .s
| select(type == "object" and (.sessionId // "") != "")
| .sessionId as $sid
| [ (.days // {}) | to_entries[]
    | (.key | split("|")) as $p
    | ($p[1] // "") as $m
    | tier_name($m) as $t
    | select($t != "" and ($p[0] // "") != "")
    | { day: $p[0], model: $m, t: $t,
        b: ({ model: $m } + ({ in_tok: 0, out_tok: 0, cache_read: 0, cache_create: 0,
                               cache_create_1h: 0 } + (.value // {} | map_values(. // 0)))) } ]
| sort_by(.day, .model)
| foreach .[] as $r ({c: 0, i: 0, o: 0};
    .c += ($r.b | model_usd($rates))
    | .i += $r.b.in_tok
    | .o += $r.b.out_tok;
    [ $r.day, $r.t, (.c * 1000000 | round / 1000000), $sid, display($r.model; $r.t),
      .i, .o, ($r.day + "T12:00:00Z" | fromdateiso8601), $h, "i" ] | @tsv)
