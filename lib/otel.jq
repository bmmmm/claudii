# otel.jq — turn Claude Code's OTLP/JSON export into the perf-cache shape.
#
# Input (via `jq -nR -f`, raw lines so one malformed line skips itself):
#   the concatenated JSONL written by bin/claudii-otel-receiver —
#     /v1/traces batches: {"resourceSpans":[{... "spans":[{name,attributes,..}]}]}
#     /v1/logs   batches: {"resourceLogs":[{... "logRecords":[{body,attributes}]}]}
# Args:
#   $repomap   {sessionId: repo}  built from the insights caches (claudii-otel)
#   $floor     "YYYY-MM-DD"        inclusive day cutoff (window lower bound)
#
# Output (same .latency shape lib/cmd/perf.sh already renders, plus exact fields
# transcripts can't give — ttft_ms, success, attempt — and an .errors list):
#   { source:"otel",
#     latency:[{day,model,dt_ms,ttft_ms,out,ctx,sessionId,success,attempt,repo}],
#     errors :[{day,model,status_code,sessionId,repo}] }
#
# The perf-relevant signal lives in events (logs) and beta traces, NOT metrics:
#   - trace span claude_code.llm_request → duration_ms (exact latency), ttft_ms,
#     output_tokens, success, attempt (retries), session.id  → latency samples
#   - log event claude_code.api_error    → status_code (429/5xx)              → errors

# OTLP attribute value: {key, value:{stringValue|intValue|doubleValue|boolValue}}.
# `//` is wrong for booleans (false is falsy → would fall through), so bools get
# their own extractor that preserves false. Numbers (0 truthy in jq) are fine.
def attr($a; $k):
  (first($a[]? | select(.key == $k) | .value) // null) as $v
  | if $v == null then null
    else ($v.stringValue // $v.intValue // $v.doubleValue) end;
def attrbool($a; $k):
  [$a[]? | select(.key == $k) | .value.boolValue] | if length > 0 then .[0] else null end;
# int64 nanos arrive as JSON strings; small ints as numbers — coerce either way.
def num($x): ($x | if type == "string" then (tonumber? // 0) else (. // 0) end);
def day_of($nano): ((num($nano) / 1000000000) | floor | todate)[0:10];

[ inputs | fromjson?
  | if has("resourceSpans") then
      .resourceSpans[]?.scopeSpans[]?.spans[]?
      | select(.name == "claude_code.llm_request")
      | .attributes as $a
      | { kind: "lat",
          day: day_of(.startTimeUnixNano),
          model: (attr($a; "model") // attr($a; "gen_ai.request.model") // "unknown"),
          dt_ms: num(attr($a; "duration_ms")),
          ttft_ms: (attr($a; "ttft_ms") | if . == null then null else num(.) end),
          out: num(attr($a; "output_tokens")),
          ctx: (num(attr($a; "input_tokens")) + num(attr($a; "cache_read_tokens")) + num(attr($a; "cache_creation_tokens"))),
          sessionId: (attr($a; "session.id") // ""),
          success: (attrbool($a; "success") as $s | if $s == null then true else $s end),
          attempt: num(attr($a; "attempt")) }
    elif has("resourceLogs") then
      .resourceLogs[]?.scopeLogs[]?.logRecords[]?
      | select(.body.stringValue == "claude_code.api_error")
      | .attributes as $a
      | { kind: "err",
          day: day_of(.timeUnixNano),
          model: (attr($a; "model") // "unknown"),
          # field name unverified (no api_error in the capture) — try the likely keys
          status_code: num(attr($a; "status_code") // attr($a; "http.response.status_code") // attr($a; "error.status")),
          sessionId: (attr($a; "session.id") // "") }
    else empty end
] as $rows
| { source: "otel",
    latency: [ $rows[] | select(.kind == "lat" and .day >= $floor
                                and (.model | startswith("claudii-") | not))
               | { day, model, dt_ms, ttft_ms, out, ctx, sessionId, success, attempt,
                   repo: ($repomap[.sessionId] // "?") } ],
    errors:  [ $rows[] | select(.kind == "err" and .day >= $floor
                                and (.model | startswith("claudii-") | not))
               | { day, model, status_code, sessionId,
                   repo: ($repomap[.sessionId] // "?") } ] }
