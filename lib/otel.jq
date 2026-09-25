# otel.jq — OTEL sample rows → the perf-cache shape.
#
# Input (via `jq -n -f`): NDJSON rows from lib/otel-extract.jq — compacted
# rows/DAY.v<N>.ndjson files plus freshly extracted raw days (bin/claudii-otel).
# Args:
#   $repomap   [{sessionId: repo}] built from the insights caches (claudii-otel),
#              via --slurpfile (hence the [0]) — too big for an argument
#   $floor     "YYYY-MM-DD"        inclusive day cutoff (window lower bound)
#
# Output (same .latency shape lib/cmd/perf.sh already renders, plus exact fields
# transcripts can't give — ttft_ms, success, attempt — and an .errors list):
#   { source:"otel",
#     latency:[{day,model,dt_ms,ttft_ms,out,ctx,sessionId,success,attempt,repo}],
#     errors :[{day,model,status_code,sessionId,repo}] }

[ inputs | select(type == "object") ] as $rows
| { source: "otel",
    latency: [ $rows[] | select(.kind == "lat" and .day >= $floor
                                and (.model | startswith("claudii-") | not))
               | { day, model, dt_ms, ttft_ms, out, ctx, sessionId, success, attempt,
                   repo: ($repomap[0][.sessionId] // "?") } ],
    errors:  [ $rows[] | select(.kind == "err" and .day >= $floor
                                and (.model | startswith("claudii-") | not))
               | { day, model, status_code, sessionId,
                   repo: ($repomap[0][.sessionId] // "?") } ] }
