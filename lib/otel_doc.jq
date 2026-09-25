# otel_doc.jq — OTEL sample rows → the perf-cache shape, as a definition that
# lib/otel.jq (plain `claudii-otel build`) and the fused render modes
# (`build --render rows|json`, see bin/claudii-otel) share. Used with
# `jq -L lib`; `include "otel_doc";`.
#
# Input: NDJSON rows from lib/otel-extract.jq — compacted rows/DAY.v<N>.ndjson
# files plus freshly extracted raw days.
# Args: $repomap  {sessionId: repo} — the insights-repomap.tsv log, else the caches
#       $floor    "YYYY-MM-DD" inclusive day cutoff (window lower bound)
# Output: { source:"otel",
#           latency:[{day,model,dt_ms,ttft_ms,out,ctx,sessionId,success,attempt,repo}],
#           errors :[{day,model,status_code,sessionId,repo}] }

def otel_doc($repomap; $floor):
  [ inputs | select(type == "object") ] as $rows
  | { source: "otel",
      latency: [ $rows[] | select(.kind == "lat" and .day >= $floor
                                  and (.model | startswith("claudii-") | not))
                 | { day, model, dt_ms, ttft_ms, out, ctx, sessionId, success, attempt,
                     repo: ($repomap[.sessionId] // "?") } ],
      errors:  [ $rows[] | select(.kind == "err" and .day >= $floor
                                  and (.model | startswith("claudii-") | not))
                 | { day, model, status_code, sessionId,
                     repo: ($repomap[.sessionId] // "?") } ] };
