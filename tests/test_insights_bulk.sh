# touches: bin/claudii-insights lib/cmd/insights.sh lib/insights_stream.sh bin/claudii-otel lib/otel_rows.jq lib/otel_doc.jq

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

# OTEL repo map: one flat llm_request record of the last session must
# resolve to its repo (events/<kind>-<UTC day>.ndjson, the receiver's layout).
mkdir -p "$_BULK_DIR/cache/otel/events"
_BULK_NANO="$(date +%s)000000000"
printf '{"_sig":"span","_name":"claude_code.llm_request","_t":"%s","model":"claude-opus-4-8","duration_ms":1000,"session.id":"%s"}\n' \
  "$_BULK_NANO" "${_BULK_PAD:0:100}-s$(( _BULK_N - 1 ))" \
  > "$_BULK_DIR/cache/otel/events/llm-$(date -u +%Y-%m-%d).ndjson"
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
# A zero-padded window is decimal, not octal ("08" was a bash arithmetic error).
assert_eq "bulk: --days 08 reads the window" "$_BULK_N" \
  "$(_bulk_env bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 08 2>/dev/null | jq -r '.sessions')"
# A symlinked insights dir is followed, as the old glob did.
mkdir -p "$_BULK_DIR/linked"
ln -s "$_BULK_DIR/cache/insights" "$_BULK_DIR/linked/insights"
assert_eq "bulk: a symlinked insights dir is read" "$_BULK_N" \
  "$(CLAUDII_CACHE_DIR="$_BULK_DIR/linked" CLAUDE_PROJECTS_DIR="$_BULK_DIR/projects" \
     bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 2>/dev/null | jq -r '.sessions')"
# …and a pinned clock (CLAUDII_NOW) disables the gate: mtimes are real time.
_BULK_PINNED=$(CLAUDII_NOW="$(date +%s)" _bulk_env bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 2>&1)
assert_eq "bulk: pinned clock reads every cache" "$(( _BULK_N + 1 ))" \
  "$(jq -r '.sessions' <<< "$_BULK_PINNED" 2>/dev/null)"

# ── a merged aggregate past 128 KiB ─────────────────────────────────────────
# The views get the MERGED JSON, not the file list — and that grows with the
# window too: one limit hit per session (each tagged with its long session id),
# one model and one tool name per session. It used to travel as ONE
# `--argjson m` argument into cache/tokens/tools/limits --json and both
# `skills-cost --compare` windows; past Linux's 128 KiB per-argument cap jq
# never started (rc 126, "Argument list too long").
_BULK_BIG="$_BULK_DIR/big"
mkdir -p "$_BULK_BIG/insights"
_BULK_BIG_N=1500
_BULK_DAY=$(date -u +%Y-%m-%d)
for (( _i = 0; _i < _BULK_BIG_N; _i++ )); do
  printf '{"sessionId":"%s-b%d","first_seen":"%s","last_seen":"%s","messages":1,"limit_hits":[{"timestamp":"%s","model":"claude-opus-4-7"}],"days":{"%s|claude-bulk-%s-%d":{"in_tok":10,"out_tok":5,"cache_read":90,"cache_create":0}},"models":{"claude-bulk-%s-%d":{"in_tok":10,"cache_read":90,"cache_create":0}},"tools":{"tool-%s-%d":1},"attribution_skills":{"bulk-skill":{"calls":1,"in_tok":10,"out_tok":5,"cache_read":90,"cache_create":0}},"attribution_models":{"skill|bulk-skill|claude-sonnet-4-6":{"calls":1,"in_tok":10,"out_tok":5,"cache_read":90,"cache_create":0}}}\n' \
    "${_BULK_PAD:0:100}" "$_i" "$_BULK_TS" "$_BULK_TS" "$_BULK_TS" \
    "$_BULK_DAY" "${_BULK_PAD:0:50}" "$_i" "${_BULK_PAD:0:50}" "$_i" "${_BULK_PAD:0:50}" "$_i" \
    > "$_BULK_BIG/insights/big-${_i}.json"
done
_bulk_big() {
  CLAUDII_CACHE_DIR="$_BULK_BIG" CLAUDE_PROJECTS_DIR="$_BULK_DIR/projects" "$@"
}
_BULK_BIG_BYTES=$(_bulk_big bash "$CLAUDII_HOME/bin/claudii-insights" merge --days 7 2>/dev/null | wc -c)
assert_eq "bulk: the merged fixture really is past 128 KiB" "1" \
  "$(( _BULK_BIG_BYTES > 131072 ? 1 : 0 ))"

_bulk_view() {   # <expected> <jq filter> <claudii args...>
  local _want="$1" _filter="$2"; shift 2
  local _out _rc=0
  _out=$(_bulk_big bash "$CLAUDII_HOME/bin/claudii" "$@" 2>&1) || _rc=$?
  assert_eq "bulk: $* exits 0 on a merge past 128 KiB" "0" "$_rc"
  assert_eq "bulk: $* reads the whole merge ($_filter)" "$_want" \
    "$(jq -r "$_filter" <<< "$_out" 2>/dev/null)"
}
_bulk_view "$_BULK_BIG_N" '.per_model | length' cache --json
_bulk_view "$_BULK_BIG_N" '.by_model | length'  tokens --json
_bulk_view "$_BULK_BIG_N" '.tools | length'     tools --json
_bulk_view "$_BULK_BIG_N" '.total'              limits --json
_bulk_view "$_BULK_BIG_N" '.rows[0].calls_recent' skills-cost --compare 1:1 --json
unset -f _bulk_big _bulk_view
