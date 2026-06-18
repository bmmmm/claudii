# touches: lib/cmd/perf.sh lib/render.sh bin/claudii-insights lib/insights.jq lib/insights-merge.jq

# test_perf.sh — claudii perf (response-time & throughput dashboard)
#
# Latency = assistant.timestamp - parent.timestamp, resolved via parentUuid ->
# seen_ts. Fixture builds known deltas so percentiles and tok/s are exact:
#   repoA (opus): 2s/200tok, 4s/400, 6s/600, 8s/800   -> p50 6s, 100 tok/s
#   repoB (opus): 20s/2000tok                          -> p50 20s, 100 tok/s
# Plus a sidechain record (must be excluded at aggregation) and a <synthetic>
# record (must be excluded at the view) — both keep total_samples at 5.
# All timestamps are stamped "today" so the default 7d window covers them.

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
  printf '%s\n' '{"type":"assistant","uuid":"a4","parentUuid":"u4","timestamp":"'"$_T"'T10:03:08Z","cwd":"/x/repoA","gitBranch":"main","sessionId":"perftest-a","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":800,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
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

unset _T _PERF_OUT _PERF_RC _PERF_REPO _PERF_JSON _PERF_RJSON _PERF_TSV
unset _PERF_HELP _PERF_BAD _PERF_PF _PERF_EOUT
