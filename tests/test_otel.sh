# touches: bin/claudii-otel lib/otel.jq bin/claudii-otel-receiver lib/cmd/perf.sh

# test_otel.sh — claudii-otel (OTLP/JSON → perf-cache shape) + perf OTEL source
#
# Builds OTLP fixtures matching Claude Code's real wire format (verified against a
# live http/json capture): trace spans claude_code.llm_request carry duration_ms,
# ttft_ms, output_tokens, success, attempt, session.id; log events
# claude_code.api_error carry status_code. Repo is resolved from session.id via
# the insights caches (OTEL events carry no cwd). One malformed line and one
# out-of-window span verify fromjson? skipping and the day floor.

_OTEL_TMPDIRS=()
trap 'rm -rf "${_OTEL_TMPDIRS[@]}" 2>/dev/null' EXIT
_OTEL_CACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_CACHE")
mkdir -p "$_OTEL_CACHE/otel" "$_OTEL_CACHE/insights"

_NOW=$(date -u +%s)
_NANO="${_NOW}000000000"
_OLD=$(( _NOW - 100 * 86400 )); _OLDNANO="${_OLD}000000000"

# session.id → repo map (OTEL has no cwd; perf's transcript path uses the same caches)
printf '%s\n' '{"sessionId":"otelsess-a","project":{"path":"/x/alpha","repo":"alpha","branch":"main"}}' > "$_OTEL_CACHE/insights/otelsess-a.json"
printf '%s\n' '{"sessionId":"otelsess-b","project":{"path":"/x/beta","repo":"beta","branch":"dev"}}'  > "$_OTEL_CACHE/insights/otelsess-b.json"

# emit one llm_request trace batch line: $1=session $2=nano $3=dt_ms $4=ttft $5=out $6=success $7=attempt
_span() {
  printf '%s\n' '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claude-code"}}]},"scopeSpans":[{"scope":{"name":"com.anthropic.claude_code.tracing"},"spans":[{"name":"claude_code.llm_request","startTimeUnixNano":"'"$2"'","endTimeUnixNano":"'"$2"'","attributes":[{"key":"model","value":{"stringValue":"claude-opus-4-8"}},{"key":"duration_ms","value":{"intValue":'"$3"'}},{"key":"ttft_ms","value":{"intValue":'"$4"'}},{"key":"output_tokens","value":{"intValue":'"$5"'}},{"key":"session.id","value":{"stringValue":"'"$1"'"}},{"key":"success","value":{"boolValue":'"$6"'}},{"key":"attempt","value":{"intValue":'"$7"'}}]}]}]}]}'
}
# emit one api_error log batch line: $1=session $2=nano $3=status_code
_err() {
  printf '%s\n' '{"resourceLogs":[{"resource":{"attributes":[]},"scopeLogs":[{"scope":{"name":"com.anthropic.claude_code.events"},"logRecords":[{"timeUnixNano":"'"$2"'","body":{"stringValue":"claude_code.api_error"},"attributes":[{"key":"model","value":{"stringValue":"claude-opus-4-8"}},{"key":"status_code","value":{"intValue":'"$3"'}},{"key":"session.id","value":{"stringValue":"'"$1"'"}}]}]}]}]}'
}

{
  _span otelsess-a "$_NANO" 2000 1000 200 true 1
  _span otelsess-a "$_NANO" 4000 2000 400 true 1
  _span otelsess-a "$_NANO" 6000 3000 600 true 1
  _span otelsess-b "$_NANO" 8000 4000 800 false 2     # failed + a retry
  _span ghostsess  "$_NANO" 5000 2500 500 true 1      # no insights cache → repo "?"
  printf '%s\n' 'this is not json — fromjson? must skip it'
  _span otelsess-a "$_OLDNANO" 9999 9999 9999 true 1  # 100d old → outside a 7d window
} > "$_OTEL_CACHE/otel/traces.jsonl"

{
  _err otelsess-a "$_NANO" 429
  _err otelsess-b "$_NANO" 529
  # an api_request log must NOT be read as an error
  printf '%s\n' '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"'"$_NANO"'","body":{"stringValue":"claude_code.api_request"},"attributes":[{"key":"session.id","value":{"stringValue":"otelsess-a"}}]}]}]}]}'
} > "$_OTEL_CACHE/otel/logs.jsonl"

_build() { CLAUDII_CACHE_DIR="$_OTEL_CACHE" CLAUDII_HOME="$CLAUDII_HOME" bash "$CLAUDII_HOME/bin/claudii-otel" "$@"; }

# ── build: shape + windowing ──
_OB=$(_build build --days 7 2>&1)
assert_eq "otel build: well-formed JSON" "0" \
  "$(printf '%s' "$_OB" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "otel build: source otel" "otel" "$(printf '%s' "$_OB" | jq -r '.source')"
assert_eq "otel build: 5 latency samples (old one filtered)" "5" \
  "$(printf '%s' "$_OB" | jq -r '.latency | length')"
assert_eq "otel build: 2 error samples" "2" \
  "$(printf '%s' "$_OB" | jq -r '.errors | length')"

# ── repo resolution via session.id ──
assert_eq "otel build: otelsess-a → alpha" "alpha" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-a")][0].repo')"
assert_eq "otel build: otelsess-b → beta" "beta" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].repo')"
assert_eq "otel build: unknown session → ?" "?" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="ghostsess")][0].repo')"

# ── exact-field extraction (ttft / success / attempt / status_code) ──
assert_eq "otel build: ttft_ms extracted" "4000" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].ttft_ms')"
assert_eq "otel build: success=false preserved (not dropped by //)" "false" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].success')"
assert_eq "otel build: retry attempt=2" "2" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].attempt')"
assert_eq "otel build: 4 successes among the in-window samples" "4" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.success==true)] | length')"
assert_eq "otel build: error 429 present" "429" \
  "$(printf '%s' "$_OB" | jq -r '[.errors[]|select(.status_code==429)][0].status_code')"
assert_eq "otel build: api_request not counted as error" "0" \
  "$(printf '%s' "$_OB" | jq -r '[.errors[]|select(.status_code==0)] | length')"

# ── empty / missing data → empty shape ──
_EMPTY="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_EMPTY")
_OE=$(CLAUDII_CACHE_DIR="$_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" bash "$CLAUDII_HOME/bin/claudii-otel" build 2>&1)
assert_eq "otel build (no data): empty latency" "0" "$(printf '%s' "$_OE" | jq -r '.latency | length')"
assert_eq "otel build (no data): empty errors"  "0" "$(printf '%s' "$_OE" | jq -r '.errors | length')"

# ── bad --days ──
_OBAD=$(_build build --days nope 2>&1; echo "rc=$?")
assert_contains "otel build: rejects non-numeric --days" "positive integer" "$_OBAD"
assert_contains "otel build: exit 1" "rc=1" "$_OBAD"

# ── doctor runs ──
_ODOC=$(_build doctor 2>&1)
assert_contains "otel doctor: reports otel dir" "otel dir" "$_ODOC"
assert_contains "otel doctor: counts samples"  "response" "$_ODOC"

# ── perf renders from the OTEL source when enabled ──
_OTEL_CFG="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_CFG")
_OTEL_EPROJ="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_EPROJ")
mkdir -p "$_OTEL_CFG/claudii"
jq '.perf.otel.enabled = true' "$CLAUDII_HOME/config/defaults.json" > "$_OTEL_CFG/claudii/config.json"
_PO=$(CLAUDII_CACHE_DIR="$_OTEL_CACHE" XDG_CONFIG_HOME="$_OTEL_CFG" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  CLAUDII_HOME="$CLAUDII_HOME" bash "$CLAUDII_HOME/bin/claudii" perf 7d 2>&1)
assert_contains "perf (otel): source otel"        "source: otel" "$_PO"
assert_contains "perf (otel): TTFT section"        "TTFT"         "$_PO"
assert_contains "perf (otel): reliability line"    "success"      "$_PO"
assert_contains "perf (otel): API errors section"  "API errors"   "$_PO"
assert_contains "perf (otel): http error code"     "529"          "$_PO"
assert_no_literal_ansi "perf (otel): no literal \\033" "$_PO"

# ── perf --json carries the OTEL-only blocks ──
_POJ=$(CLAUDII_CACHE_DIR="$_OTEL_CACHE" XDG_CONFIG_HOME="$_OTEL_CFG" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  CLAUDII_HOME="$CLAUDII_HOME" bash "$CLAUDII_HOME/bin/claudii" perf 7d --json 2>&1)
assert_eq "perf --json (otel): source otel" "otel" "$(printf '%s' "$_POJ" | jq -r '.source')"
assert_eq "perf --json (otel): ttft p50 present" "false" \
  "$(printf '%s' "$_POJ" | jq -r '.ttft == null')"
assert_eq "perf --json (otel): reliability total=5" "5" \
  "$(printf '%s' "$_POJ" | jq -r '.reliability.total')"
assert_eq "perf --json (otel): 2 error buckets" "2" \
  "$(printf '%s' "$_POJ" | jq -r '.errors | length')"

unset _NOW _NANO _OLD _OLDNANO _OB _OE _OBAD _ODOC _PO _POJ
