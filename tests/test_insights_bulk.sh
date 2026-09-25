# touches: bin/claudii-insights lib/cmd/insights.sh

# test_insights_bulk.sh — the insights cache must scale past ARG_MAX.
# Regression: every consumer passed the whole cache dir to jq as arguments
# ("${files[@]}"). The cache keeps orphans forever, and at ~12k files the path
# list outgrew macOS's 1 MiB ARG_MAX: jq died with "Argument list too long"
# (rc 126) and tokens/cache/limits/tools/skills-cost/repos all broke at once.
# The fixture's long file names push the argv past Linux's 2 MiB default too,
# so the old code fails on both CI platforms.

_BULK_DIR="$(mktemp -d)"
trap 'rm -rf "$_BULK_DIR" 2>/dev/null' EXIT
mkdir -p "$_BULK_DIR/cache/insights" "$_BULK_DIR/projects"

_BULK_N=10000
_BULK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_BULK_PAD=$(printf '%0200d' 0)
for (( _i = 0; _i < _BULK_N; _i++ )); do
  printf '{"sessionId":"s%d","first_seen":"%s","last_seen":"%s","messages":1,"project":{"repo":"bulk"}}\n' \
    "$_i" "$_BULK_TS" "$_BULK_TS" > "$_BULK_DIR/cache/insights/${_BULK_PAD}-${_i}.json"
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
