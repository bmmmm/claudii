# otel_rows.jq — flat OTEL event records → one row per perf sample.
#
# Input (via `jq -cnR -f`, raw lines so one half-written line skips itself):
#   the flat records bin/claudii-otel-receiver writes to events/llm-DAY.ndjson
#   (spans claude_code.llm_request) and events/err-DAY.ndjson (log records
#   claude_code.api_error) — one JSON object per line, attributes under their
#   own keys, reserved keys prefixed "_" (see the receiver's docstring).
# Output: NDJSON, one object per sample, no window and no repo (both are applied
# later by lib/otel_doc.jq, so compacted rows stay valid when the window or the
# session->repo map changes):
#   {kind:"lat", day, model, dt_ms, ttft_ms, out, ctx, sessionId, success, attempt}
#   {kind:"err", day, model, status_code, sessionId}
#
# bin/claudii-otel compacts each closed day into rows/DAY.v<N>.ndjson with this
# program. Changing the row shape or the extraction means bumping
# OTEL_ROWS_VERSION there: stale rows are then rebuilt from the gzipped days.

# int64 nanos arrive as JSON strings; small ints as numbers (or, on some
# records, as strings) — coerce either way; anything else (an empty AnyValue
# flattens to {}) counts as 0, as the old extractor did.
def num($x): ($x | if type == "string" then (tonumber? // 0)
                   elif type == "number" then . else 0 end);
def day_of($nano): ((num($nano) / 1000000000) | floor | todate)[0:10];

inputs | fromjson? | select(type == "object")
  | if ._sig == "span" and ._name == "claude_code.llm_request" then
      { kind: "lat",
        day: day_of(._t),
        model: (.model // ."gen_ai.request.model" // "unknown"),
        dt_ms: num(.duration_ms),
        ttft_ms: (.ttft_ms | if . == null then null else num(.) end),
        out: num(.output_tokens),
        ctx: (num(.input_tokens) + num(.cache_read_tokens) + num(.cache_creation_tokens)),
        sessionId: (."session.id" // ""),
        # `//` is wrong for booleans (false would fall through to true); a
        # non-boolean value (absent, or a string on some records) reads as
        # success, as the old extractor did.
        success: (.success | if type == "boolean" then . else true end),
        attempt: num(.attempt) }
    elif ._sig == "log" and ._name == "claude_code.api_error" then
      { kind: "err",
        day: day_of(._t),
        model: (.model // "unknown"),
        status_code: num(.status_code),
        sessionId: (."session.id" // "") }
    else empty end
