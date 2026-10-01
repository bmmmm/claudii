# otel_doc.jq — OTEL sample rows → the perf-cache shape, as a definition that
# `claudii-otel build` (document mode) and its fused render modes
# (`build --render rows|json`, see bin/claudii-otel) share. Used with
# `jq -L lib`; `include "otel_doc";`.
#
# Input: NDJSON rows from lib/otel_rows.jq — compacted rows/DAY.v<N>.ndjson
# files plus the rows of the still-plain event files.
# Args: $repomap  {sessionId: repo} — the insights-repomap.tsv log, else the caches
#       $floor    "YYYY-MM-DD" inclusive day cutoff (window lower bound)
# Output: { source:"otel",
#           latency:[{kind:"lat",day,model,dt_ms,ttft_ms,out,ctx,sessionId,success,attempt,repo}],
#           errors :[{kind:"err",day,model,status_code,sessionId,repo}] }
# The rows are passed through with .repo assigned in place (their kind key
# stays) instead of rebuilt field by field — 25% less time on 240k rows.

def otel_doc($repomap; $floor):
  [ inputs | select(type == "object") ] as $rows
  | { source: "otel",
      latency: [ $rows[] | select(.kind == "lat" and .day >= $floor
                                  and (.model | startswith("claudii-") | not))
                 | .repo = ($repomap[.sessionId] // "?") ],
      errors:  [ $rows[] | select(.kind == "err" and .day >= $floor
                                  and (.model | startswith("claudii-") | not))
                 | .repo = ($repomap[.sessionId] // "?") ] };
