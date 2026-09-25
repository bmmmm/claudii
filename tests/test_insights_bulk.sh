# touches: bin/claudii-insights lib/cmd/insights.sh lib/insights_stream.sh bin/claudii-otel lib/otel.jq

# test_insights_bulk.sh — the insights cache must scale past ARG_MAX.
# Regression: every consumer passed the whole cache dir to jq as arguments
# ("${files[@]}"). The cache keeps orphans forever, and at ~12k files the path
# list outgrew macOS's 1 MiB ARG_MAX: jq died with "Argument list too long"
# (rc 126) and tokens/cache/limits/tools/skills-cost/repos all broke at once.
# The fixture's long file names push the argv past Linux's 2 MiB default too,
# so the old code fails on both CI platforms. The long session ids do the same
# for the OTEL session->repo map (~1.1 MB), which used to travel as ONE
# `--argjson` argument (Linux caps a single argument at 128 KiB).

_BULK_DIR="$(mktemp -d)"
trap 'rm -rf "$_BULK_DIR" 2>/dev/null' EXIT
mkdir -p "$_BULK_DIR/cache/insights" "$_BULK_DIR/projects"

_BULK_N=10000
_BULK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_BULK_PAD=$(printf '%0200d' 0)
for (( _i = 0; _i < _BULK_N; _i++ )); do
  printf '{"sessionId":"%s-s%d","first_seen":"%s","last_seen":"%s","messages":1,"project":{"repo":"bulk"}}\n' \
    "${_BULK_PAD:0:100}" "$_i" "$_BULK_TS" "$_BULK_TS" > "$_BULK_DIR/cache/insights/${_BULK_PAD}-${_i}.json"
done

_bulk_env() {
  CLAUDII_CACHE_DIR="$_BULK_DIR/cache" CLAUDE_PROJECTS_DIR="$_BULK_DIR/projects" "$@"
}

_BULK_MERGE=$(_bulk_env bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 2>&1)
assert_eq "bulk: merge counts every session past ARG_MAX" "$_BULK_N" \
  "$(jq -r '.sessions' <<< "$_BULK_MERGE" 2>/dev/null)"

_BULK_REPOS=$(_bulk_env bash "$CLAUDII_HOME/bin/claudii" repos 2>&1)
assert_contains "bulk: repos aggregates past ARG_MAX" "bulk" "$_BULK_REPOS"

_BULK_GC=$(_bulk_env bash "$CLAUDII_HOME/bin/claudii-insights" gc --older-than 1 2>&1)
assert_contains "bulk: gc sees every orphan past ARG_MAX" "$_BULK_N recent orphans kept" "$_BULK_GC"

# OTEL repo map: one span of the last session must resolve to its repo.
mkdir -p "$_BULK_DIR/cache/otel"
_BULK_NANO="$(date +%s)000000000"
printf '%s\n' '{"resourceSpans":[{"scopeSpans":[{"spans":[{"name":"claude_code.llm_request","startTimeUnixNano":"'"$_BULK_NANO"'","attributes":[{"key":"model","value":{"stringValue":"claude-opus-4-8"}},{"key":"duration_ms","value":{"intValue":1000}},{"key":"session.id","value":{"stringValue":"'"${_BULK_PAD:0:100}-s$(( _BULK_N - 1 ))"'"}}]}]}]}]}' \
  > "$_BULK_DIR/cache/otel/traces.jsonl"
_BULK_OTEL=$(_bulk_env bash "$CLAUDII_HOME/bin/claudii-otel" build --days 7 2>&1)
assert_eq "bulk: otel repo map resolves past ARG_MAX" "bulk" \
  "$(jq -r '.latency[0].repo' <<< "$_BULK_OTEL" 2>/dev/null)"

# Window-bounded read: a cache whose mtime predates the window is not read, even
# if its (impossible) last_seen claims otherwise — proves the mtime gate in
# lib/insights_stream.sh is active. last_seen <= mtime holds for every cache
# aggregate writes, so nothing real is lost.
printf '{"sessionId":"stale","first_seen":"%s","last_seen":"%s","messages":1}\n' \
  "$_BULK_TS" "$_BULK_TS" > "$_BULK_DIR/cache/insights/stale.json"
touch -t 200001010000 "$_BULK_DIR/cache/insights/stale.json"
_BULK_GATED=$(_bulk_env bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 2>&1)
assert_eq "bulk: merge skips caches older than the window" "$_BULK_N" \
  "$(jq -r '.sessions' <<< "$_BULK_GATED" 2>/dev/null)"
# …and a pinned clock (CLAUDII_NOW) disables the gate: mtimes are real time.
_BULK_PINNED=$(CLAUDII_NOW="$(date +%s)" _bulk_env bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 2>&1)
assert_eq "bulk: pinned clock reads every cache" "$(( _BULK_N + 1 ))" \
  "$(jq -r '.sessions' <<< "$_BULK_PINNED" 2>/dev/null)"
