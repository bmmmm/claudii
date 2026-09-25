# otel-extract.jq — Claude Code's raw OTLP/JSON batches → one row per sample.
#
# Input (via `jq -cnR -f`, raw lines so one malformed line skips itself):
#   raw batches as bin/claudii-otel-receiver writes them —
#     /v1/traces batches: {"resourceSpans":[{... "spans":[{name,attributes,..}]}]}
#     /v1/logs   batches: {"resourceLogs":[{... "logRecords":[{body,attributes}]}]}
# Output: NDJSON, one object per sample, no window and no repo (both are applied
# later by lib/otel.jq, so compacted rows stay valid when the window or the
# session->repo map changes):
#   {kind:"lat", day, model, dt_ms, ttft_ms, out, ctx, sessionId, success, attempt}
#   {kind:"err", day, model, status_code, sessionId}
#
# bin/claudii-otel compacts each closed day into rows/DAY.v<N>.ndjson with this
# program. Changing the row shape or the extraction means bumping
# OTEL_ROWS_VERSION there: stale rows are then rebuilt from the gzipped raw days.
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

inputs | fromjson?
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
