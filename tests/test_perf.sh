# touches: lib/cmd/perf.sh lib/render.sh bin/claudii-insights lib/insights.jq lib/insights-merge.jq lib/otel.jq bin/claudii-otel

# test_perf.sh — claudii perf (response-time & throughput dashboard)
#
# Latency = assistant.timestamp - parent.timestamp, resolved via parentUuid ->
# seen_ts. Fixture builds known deltas so percentiles and tok/s are exact:
#   repoA (opus): 2s/200tok, 4s/400, 6s/600, 8s/800   -> p50 6s, 100 tok/s
#   repoB (opus): 20s/2000tok                          -> p50 20s, 100 tok/s
# Plus a sidechain record (must be excluded at aggregation) and a <synthetic>
# record (must be excluded at the view) — both keep total_samples at 5.
# The 8s/800 response (a4) carries cache_read 250000 so its ctx lands in the
# 200-400k context-window bucket; the four other responses are tiny (<50k) — the
# By-context-window section therefore shows exactly two buckets.
# All timestamps are stamped "today" so the default 7d window covers them.
# A second block builds an OTEL fixture (traces+logs JSONL) to exercise the
# exact-source path: ctx buckets, [1m] model-merge, claudii-selftest exclusion,
# TTFT, reliability (success/retried) and api_error status codes.

_PERF_TMPDIRS=()
trap 'rm -rf "${_PERF_TMPDIRS[@]}" 2>/dev/null' EXIT
_PERF_PROJ="$(mktemp -d)"; _PERF_TMPDIRS+=("$_PERF_PROJ")
_PERF_CACHE="$(mktemp -d)"; _PERF_TMPDIRS+=("$_PERF_CACHE")
mkdir -p "$_PERF_PROJ/-x-repoA" "$_PERF_PROJ/-x-repoB"

_T=$(date -u +%Y-%m-%d)

# repoA session: 4 main-thread opus responses + 1 sidechain + 1 synthetic.
{
  printf '%s\n' '{"type":"user","uuid":"u1","timestamp":"'"$_T"'T10:00:00Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a1","parentUuid":"u1","timestamp":"'"$_T"'T10:00:02Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":200,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n' '{"type":"user","uuid":"u2","parentUuid":"a1","timestamp":"'"$_T"'T10:01:00Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a2","parentUuid":"u2","timestamp":"'"$_T"'T10:01:04Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":400,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n' '{"type":"user","uuid":"u3","parentUuid":"a2","timestamp":"'"$_T"'T10:02:00Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a3","parentUuid":"u3","timestamp":"'"$_T"'T10:02:06Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":600,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n' '{"type":"user","uuid":"u4","parentUuid":"a3","timestamp":"'"$_T"'T10:03:00Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a4","parentUuid":"u4","timestamp":"'"$_T"'T10:03:08Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":800,"cache_read_input_tokens":250000,"cache_creation_input_tokens":0}}}'
  # sidechain — resolvable parent + huge delta, MUST be excluded
  printf '%s\n' '{"type":"user","uuid":"u5","parentUuid":"a4","timestamp":"'"$_T"'T10:04:00Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a5","parentUuid":"u5","isSidechain":true,"timestamp":"'"$_T"'T10:05:39Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":9999,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  # synthetic model — recorded in cache, MUST be excluded at the view
  printf '%s\n' '{"type":"user","uuid":"u6","parentUuid":"a5","timestamp":"'"$_T"'T10:06:00Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a6","parentUuid":"u6","timestamp":"'"$_T"'T10:06:03Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"<synthetic>","usage":{"input_tokens":10,"output_tokens":123,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
} > "$_PERF_PROJ/-x-repoA/perftest-a.jsonl"

# repoB session: one 20s opus response.
{
  printf '%s\n' '{"type":"user","uuid":"u1b","timestamp":"'"$_T"'T12:00:00Z","cwd":"/x/repoB","gitBranch":"dev","sessionId":"perftest-b","message":{"role":"user","content":[]}}'
  printf '%s\n' '{"type":"assistant","uuid":"a1b","parentUuid":"u1b","timestamp":"'"$_T"'T12:00:20Z","cwd":"/x/repoB","gitBranch":"dev","sessionId":"perftest-b","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":2000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
} > "$_PERF_PROJ/-x-repoB/perftest-b.jsonl"

_perf() { CLAUDE_PROJECTS_DIR="$_PERF_PROJ" CLAUDII_CACHE_DIR="$_PERF_CACHE" bash "$CLAUDII_HOME/bin/claudii" "$@"; }

# ── Pretty default view ──
_PERF_OUT=$(_perf perf 2>&1)
_PERF_RC=$(_perf perf >/dev/null 2>&1; echo $?)
assert_eq "perf: exit 0"          "0" "$_PERF_RC"
assert_eq "perf: produces output" "0" "$([ -z "$_PERF_OUT" ] && echo 1 || echo 0)"
assert_no_literal_ansi "perf: no literal \\033 in output" "$_PERF_OUT"
assert_contains "perf: header"          "claudii perf" "$_PERF_OUT"
assert_contains "perf: summary p50"     "p50"          "$_PERF_OUT"
assert_contains "perf: throughput unit" "tok/s"        "$_PERF_OUT"
assert_contains "perf: by-model section" "By model"    "$_PERF_OUT"
assert_contains "perf: opus labelled"   "Opus 4.8"     "$_PERF_OUT"
assert_contains "perf: by-repo section" "By repo"      "$_PERF_OUT"
assert_contains "perf: repoA listed"    "repoA"        "$_PERF_OUT"
assert_contains "perf: repoB listed"    "repoB"        "$_PERF_OUT"
assert_contains "perf: trend section"   "Latency trend" "$_PERF_OUT"
assert_contains "perf: api health line" "API health"   "$_PERF_OUT"
# Synthetic must not leak into the rendered table.
assert_not_contains "perf: synthetic excluded from view" "synthetic" "$_PERF_OUT"

# Context-window section: ctx = input + cache_read + cache_creation. a4 carries
# cache_read 250000 -> 200-400k bucket; the four small responses -> <50k.
assert_contains "perf: by-context-window section" "By context window" "$_PERF_OUT"
assert_contains "perf: window bucket <50k"        "<50k"              "$_PERF_OUT"
assert_contains "perf: window bucket 200-400k"    "200-400k"          "$_PERF_OUT"

# ── --repo filter: By session replaces By repo ──
_PERF_REPO=$(_perf perf --repo repoA 2>&1)
assert_contains "perf --repo: header shows repo"    "repo: repoA" "$_PERF_REPO"
assert_contains "perf --repo: by-session section"   "By session"  "$_PERF_REPO"
assert_not_contains "perf --repo: no by-repo section" "By repo"    "$_PERF_REPO"

# ── --json shape + exact values ──
_PERF_JSON=$(_perf perf --json 2>&1)
assert_eq "perf --json: well-formed" "0" \
  "$(printf '%s' "$_PERF_JSON" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "perf --json: source transcript" "transcript" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.source')"
assert_eq "perf --json: total_samples=5 (sidechain+synthetic excluded)" "5" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.total_samples')"
assert_eq "perf --json: summary p50=6000ms" "6000" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.summary.p50_ms')"
assert_eq "perf --json: summary tok/s=100" "100" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.summary.tok_s')"
assert_eq "perf --json: one model (opus only)" "1" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_model | length')"
assert_contains "perf --json: model is opus" "opus" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_model[0].model')"
assert_eq "perf --json: two repos" "2" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_repo | length')"
assert_eq "perf --json: repoB p50=20000ms" "20000" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_repo[] | select(.repo=="repoB") | .p50_ms')"
assert_eq "perf --json: by_window two buckets" "2" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_window | length')"
assert_eq "perf --json: <50k bucket 4 samples" "4" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_window[] | select(.bucket=="<50k") | .samples')"
assert_eq "perf --json: 200-400k bucket 1 sample" "1" \
  "$(printf '%s' "$_PERF_JSON" | jq -r '.by_window[] | select(.bucket=="200-400k") | .samples')"

# ── --repo --json: narrowed counts ──
_PERF_RJSON=$(_perf perf --repo repoA --json 2>&1)
assert_eq "perf --repo --json: repo echoed" "repoA" \
  "$(printf '%s' "$_PERF_RJSON" | jq -r '.repo')"
assert_eq "perf --repo --json: total_samples=4" "4" \
  "$(printf '%s' "$_PERF_RJSON" | jq -r '.total_samples')"

# ── --tsv rejection ──
_PERF_TSV=$(_perf perf --tsv 2>&1; echo "rc=$?")
assert_contains "perf --tsv: rejected, points to --json" "use --json" "$_PERF_TSV"
assert_contains "perf --tsv: exit 1" "rc=1" "$_PERF_TSV"

# ── --help ──
_PERF_HELP=$(_perf perf --help 2>&1)
assert_contains "perf --help: usage" "Usage: claudii perf" "$_PERF_HELP"
assert_contains "perf --help: documents --repo" "--repo" "$_PERF_HELP"

# ── bad window arg ──
_PERF_BAD=$(_perf perf bogus 2>&1; echo "rc=$?")
assert_contains "perf bogus: actionable error" "unknown perf argument: bogus" "$_PERF_BAD"
assert_contains "perf bogus: exit 1" "rc=1" "$_PERF_BAD"

# ── pf shorthand resolves to perf ──
_PERF_PF=$(_perf pf --json 2>&1)
assert_eq "pf: shorthand resolves (total_samples=5)" "5" \
  "$(printf '%s' "$_PERF_PF" | jq -r '.total_samples')"

# ── Empty cache → empty-state message ──
_PERF_EPROJ="$(mktemp -d)"; _PERF_TMPDIRS+=("$_PERF_EPROJ")
_PERF_ECACHE="$(mktemp -d)"; _PERF_TMPDIRS+=("$_PERF_ECACHE")
_PERF_EOUT=$(CLAUDE_PROJECTS_DIR="$_PERF_EPROJ" CLAUDII_CACHE_DIR="$_PERF_ECACHE" \
  bash "$CLAUDII_HOME/bin/claudii" perf 2>&1)
assert_contains "perf (empty): empty-state message" "No insight data" "$_PERF_EOUT"

# ── OTEL source fixture: exact duration_ms + ctx + ttft + errors ─────────────
# Empty projects dir (no transcript samples) + perf.otel.enabled forces the OTEL
# path. Each span is its own OTLP /v1/traces batch line; one /v1/logs batch
# carries an api_error. Spans (model, dur, in, cache_read, cache_create, out,
# ttft, success, attempt) — ctx = in + cache_read + cache_create:
#   opus     4s  ctx   5000  -> <50k     ok
#   opus     5s  ctx   5000  -> <50k     FAIL, attempt 2 (reliability)
#   opus     9s  ctx  85000  -> 50-100k  ok
#   opus    30s  ctx 255000  -> 200-400k ok
#   opus[1m] 20s ctx 260000  -> 200-400k ok  (merges into the bare opus row)
#   claudii-selftest 0s      -> excluded entirely (external OTLP probe pollution)
_OTEL_PROJ="$(mktemp -d)";  _PERF_TMPDIRS+=("$_OTEL_PROJ")
_OTEL_CACHE="$(mktemp -d)"; _PERF_TMPDIRS+=("$_OTEL_CACHE")
_OTEL_XDG="$(mktemp -d)";   _PERF_TMPDIRS+=("$_OTEL_XDG")
mkdir -p "$_OTEL_XDG/claudii" "$_OTEL_CACHE/otel"
jq '.perf.otel.enabled = true' "$CLAUDII_HOME/config/defaults.json" > "$_OTEL_XDG/claudii/config.json"
_NS="$(date -u +%s)000000000"   # today in ns (string-concat; 7d window covers it either side of UTC midnight)

# Build the OTLP span via jq (not printf) — hand-rolled brace-balanced JSON is
# error-prone (one missing `}` makes fromjson? skip the whole line and the OTEL
# source silently falls back to the transcript estimate). intValue is a string
# on the wire (proto3 JSON int64); success is a real bool.
_otel_span() {  # model dur in cread ccreate out ttft success attempt
  jq -cn --arg ns "$_NS" --arg model "$1" --argjson dur "$2" \
     --argjson in "$3" --argjson cr "$4" --argjson cc "$5" --argjson out "$6" \
     --argjson ttft "$7" --argjson success "$8" --argjson attempt "$9" \
    '{resourceSpans:[{scopeSpans:[{spans:[{name:"claude_code.llm_request",startTimeUnixNano:$ns,attributes:[{key:"model",value:{stringValue:$model}},{key:"duration_ms",value:{intValue:($dur|tostring)}},{key:"input_tokens",value:{intValue:($in|tostring)}},{key:"cache_read_tokens",value:{intValue:($cr|tostring)}},{key:"cache_creation_tokens",value:{intValue:($cc|tostring)}},{key:"output_tokens",value:{intValue:($out|tostring)}},{key:"ttft_ms",value:{intValue:($ttft|tostring)}},{key:"success",value:{boolValue:$success}},{key:"attempt",value:{intValue:($attempt|tostring)}},{key:"session.id",value:{stringValue:"otel-s1"}}]}]}]}]}'
}
{
  _otel_span "claude-opus-4-8"      4000 5000      0 0 200  600 true  1
  _otel_span "claude-opus-4-8"      5000 5000      0 0 150  700 false 2
  _otel_span "claude-opus-4-8"      9000 5000  80000 0 300  900 true  1
  _otel_span "claude-opus-4-8"     30000 5000 250000 0 500 3000 true  1
  _otel_span "claude-opus-4-8[1m]" 20000 5000 255000 0 400 2500 true  1
  _otel_span "claudii-selftest"        0    0      0 0   0    0 true  1
} > "$_OTEL_CACHE/otel/traces.jsonl"
jq -cn --arg ns "$_NS" \
  '{resourceLogs:[{scopeLogs:[{logRecords:[{body:{stringValue:"claude_code.api_error"},timeUnixNano:$ns,attributes:[{key:"model",value:{stringValue:"claude-opus-4-8"}},{key:"status_code",value:{intValue:"429"}},{key:"session.id",value:{stringValue:"otel-s1"}}]}]}]}]}' \
  > "$_OTEL_CACHE/otel/logs.jsonl"

_operf() { CLAUDE_PROJECTS_DIR="$_OTEL_PROJ" CLAUDII_CACHE_DIR="$_OTEL_CACHE" XDG_CONFIG_HOME="$_OTEL_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" "$@"; }

_OTEL_JSON=$(_operf perf --json 2>&1)
assert_eq "perf otel: well-formed json" "0" \
  "$(printf '%s' "$_OTEL_JSON" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "perf otel: source is otel" "otel" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.source')"
assert_eq "perf otel: total_samples=5 (selftest excluded)" "5" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.total_samples')"
assert_eq "perf otel: by_window 3 buckets" "3" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.by_window | length')"
assert_eq "perf otel: 200-400k bucket 2 samples (incl [1m])" "2" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.by_window[] | select(.bucket=="200-400k") | .samples')"
assert_eq "perf otel: <50k bucket 2 samples (pins 50k cut)" "2" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.by_window[] | select(.bucket=="<50k") | .samples')"
assert_eq "perf otel: 50-100k bucket 1 sample (pins 50k/100k cut)" "1" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.by_window[] | select(.bucket=="50-100k") | .samples')"
assert_eq "perf otel: [1m] merges into one opus row" "1" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '[.by_model[] | select(.model|test("opus"))] | length')"
# Positive value assert (not a negative test("1m")==0 that would also pass on an
# empty by_model): the single merged row's id must be the bare normalized model.
assert_eq "perf otel: opus model id normalized to bare id" "claude-opus-4-8" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.by_model[0].model')"
assert_eq "perf otel: selftest excluded from models" "0" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '[.by_model[] | select(.model|test("selftest"))] | length')"
assert_eq "perf otel: reliability total 5" "5" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.reliability.total')"
assert_eq "perf otel: reliability ok 4" "4" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.reliability.ok')"
assert_eq "perf otel: reliability retried 1" "1" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.reliability.retried')"
assert_eq "perf otel: ttft 5 samples" "5" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.ttft.samples')"
assert_eq "perf otel: api_error 429 count 1" "1" \
  "$(printf '%s' "$_OTEL_JSON" | jq -r '.errors[] | select(.status_code==429) | .count')"

_OTEL_OUT=$(_operf perf 2>&1)
assert_contains "perf otel: source badge"             "source: otel"      "$_OTEL_OUT"
assert_contains "perf otel: by-context-window section" "By context window" "$_OTEL_OUT"
assert_contains "perf otel: 200-400k bucket rendered"  "200-400k"          "$_OTEL_OUT"
assert_contains "perf otel: TTFT line rendered"        "TTFT"              "$_OTEL_OUT"
assert_contains "perf otel: API errors section"        "API errors"        "$_OTEL_OUT"
assert_contains "perf otel: 429 rendered"              "429"               "$_OTEL_OUT"
assert_not_contains "perf otel: selftest not rendered" "selftest"          "$_OTEL_OUT"

# json/render boundary parity: the ctx-bucket set is encoded twice (numeric wk +
# label map in _perf_json, string keys in the render W-rows), so pin that every
# --json bucket label also appears in the rendered output for one fixture — a
# boundary/label edit to only one block then trips this.
_OTEL_WMISS=0
while IFS= read -r _wb; do
  [[ -z "$_wb" ]] && continue
  printf '%s' "$_OTEL_OUT" | grep -qF "$_wb" || _OTEL_WMISS=1
done <<< "$(printf '%s' "$_OTEL_JSON" | jq -r '.by_window[].bucket')"
assert_eq "perf otel: every --json bucket label also renders (json/render parity)" "0" "$_OTEL_WMISS"

unset _T _PERF_OUT _PERF_RC _PERF_REPO _PERF_JSON _PERF_RJSON _PERF_TSV
unset _PERF_HELP _PERF_BAD _PERF_PF _PERF_EOUT _NS _OTEL_JSON _OTEL_OUT _OTEL_WMISS _wb
unset -f _otel_span
