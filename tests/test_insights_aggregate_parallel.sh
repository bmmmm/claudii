# touches: bin/claudii-insights

_PAR_DIR=$(mktemp -d)
trap 'find "$_PAR_DIR" -delete' EXIT
mkdir -p "$_PAR_DIR/projects/project with spaces" "$_PAR_DIR/cache"
# xargs shim on PATH: logs every aggregate fan-out (the repo-map rebuild uses
# xargs too), and with _PAR_KILL=1 dies before any worker reports — the shape
# of a worker killed by a signal.
mkdir -p "$_PAR_DIR/bin"
_PAR_REAL_XARGS=$(command -v xargs)
cat > "$_PAR_DIR/bin/xargs" <<SHIM
#!/bin/bash
case " \$* " in *" _aggregate-batch "*)
  printf 'fanout %s\n' "\$*" >> "$_PAR_DIR/xargs.log"
  [[ "\${_PAR_KILL:-}" == 1 ]] && exit 125
  # _PAR_PARTIAL=N: hand only the first N sessions on, then die like a crash.
  if [[ -n "\${_PAR_PARTIAL:-}" ]]; then
    tr '\\0' '\\n' | head -n "\$_PAR_PARTIAL" | tr '\\n' '\\0' | "$_PAR_REAL_XARGS" "\$@"
    exit 125
  fi ;;
esac
exec "$_PAR_REAL_XARGS" "\$@"
SHIM
chmod +x "$_PAR_DIR/bin/xargs"; : > "$_PAR_DIR/xargs.log"
_par_run() {
  PATH="$_PAR_DIR/bin:$PATH" \
    CLAUDE_PROJECTS_DIR="$_PAR_DIR/projects" CLAUDII_CACHE_DIR="$_PAR_DIR/cache" \
    CLAUDII_INSIGHTS_JOBS="${_PAR_JOBS-2}" /bin/bash "$CLAUDII_HOME/bin/claudii-insights" aggregate "$@"
}
_par_fanouts() { grep -c fanout "$_PAR_DIR/xargs.log" 2>/dev/null || true; }
printf '{"cwd":"/work/seed"}\n' > "$_PAR_DIR/projects/seed.jsonl"
_PAR_OUT=$(_par_run --force 2>&1)
assert_contains "serial seed is processed" '1 processed · 0 cached · 0 failed' "$_PAR_OUT"
assert_eq "a single stale session stays serial" 0 "$(_par_fanouts)"
# Keep an orphan in the map, then add enough sessions to span three batches.
rm "$_PAR_DIR/projects/seed.jsonl"
for (( _i=0; _i<65; _i++ )); do
  printf '{"cwd":"/work/repo-%d"}\n' "$_i" \
    > "$_PAR_DIR/projects/project with spaces/session $_i.jsonl"
done
# Invalid JSON is tolerated by insights.jq; a non-string cwd causes a real error.
printf '{"cwd":1}\n' > "$_PAR_DIR/projects/broken.jsonl"
_PAR_OUT=$(_PAR_KILL=1 _par_run 2>&1)
assert_contains "unreported sessions count as failed" '0 processed · 1 cached · 66 failed' "$_PAR_OUT"
assert_contains "an incomplete fan-out says so" 'parallel aggregation incomplete' "$_PAR_OUT"
# The scan marker must not have moved: this run finds the same 66 sessions.
_PAR_OUT=$(_par_run 2>&1)
assert_contains "parallel counts successes, cached orphan and failure" \
  '65 processed · 1 cached · 1 failed' "$_PAR_OUT"
assert_eq "66 stale sessions fan out through xargs" 2 "$(_par_fanouts)"
_PAR_COUNT=$(find "$_PAR_DIR/cache/insights" -name '*.json' -type f | wc -l | tr -d ' ')
assert_eq "parallel writes every cache including the last batch" 66 "$_PAR_COUNT"
assert_eq "broken session leaves no cache" no "$(test -f "$_PAR_DIR/cache/insights/broken.json" && echo yes || echo no)"
for (( _i=0; _i<65; _i++ )); do
  assert_eq "parallel cache $_i has its repo" "repo-$_i" \
    "$(jq -r '.project.repo' "$_PAR_DIR/cache/insights/session $_i.json" 2>/dev/null)"
done
printf 'seed\tseed\n' > "$_PAR_DIR/expected.tsv"
for (( _i=0; _i<65; _i++ )); do
  printf 'session %d\trepo-%d\n' "$_i" "$_i" >> "$_PAR_DIR/expected.tsv"
done
sort "$_PAR_DIR/expected.tsv" > "$_PAR_DIR/expected.sorted"
sort "$_PAR_DIR/cache/insights-repomap.tsv" > "$_PAR_DIR/actual.sorted"
assert_eq "parallel rebuilds the complete repo map including orphans" \
  "$(cat "$_PAR_DIR/expected.sorted")" "$(cat "$_PAR_DIR/actual.sorted")"
_PAR_OUT=$(_par_run 2>&1)
assert_contains "warm incremental run retains all caches" '0 processed · 66 cached · 0 failed' "$_PAR_OUT"
# Leftover mktemp files from a killed run: swept once stale, spared while fresh.
: > "$_PAR_DIR/cache/insights/dead.json.AbC123"
touch -t 202001010000 "$_PAR_DIR/cache/insights/dead.json.AbC123"
: > "$_PAR_DIR/cache/insights/live.json.XyZ789"
_par_run >/dev/null 2>&1
assert_eq "a stale aggregate tmp file is swept" no \
  "$(test -f "$_PAR_DIR/cache/insights/dead.json.AbC123" && echo yes || echo no)"
assert_eq "a fresh aggregate tmp file is spared" yes \
  "$(test -f "$_PAR_DIR/cache/insights/live.json.XyZ789" && echo yes || echo no)"

# Interrupted schema-bump rebuild: a crash after the first 10 sessions
# (broken.jsonl sorts first, so 9 caches land), then the next run — still a
# bump, .schema was not written — keeps those 9.
_PAR_INS="$_PAR_DIR/cache/insights"
_par_bump() { printf '0\n' > "$_PAR_INS/.schema"; }
# Explicit times instead of sub-second mtimes, so the test holds on 1-s
# filesystems too: transcripts and old caches 2020, stamp 2021, the caches the
# crash wrote "now".
_par_crash() {
  find "$_PAR_DIR/projects" -name '*.jsonl' -exec touch -t 202001010000 {} +
  find "$_PAR_INS" -name '*.json' -exec touch -t 202001010000 {} +
  _par_bump
  _PAR_OUT=$(_PAR_PARTIAL=10 _par_run 2>&1)
  touch -t 202101010000 "$_PAR_INS/.rebuild"
}
_par_crash
assert_contains "a crashed bump rebuild is incomplete" 'parallel aggregation incomplete' "$_PAR_OUT"
assert_eq "a crashed bump rebuild keeps its stamp" yes "$(test -f "$_PAR_INS/.rebuild" && echo yes || echo no)"
assert_eq "a crashed bump rebuild keeps the old schema" 0 "$(cat "$_PAR_INS/.schema")"
# session 0 was among the 9 — its transcript grows after the crash; session 1
# gains a subagent transcript, which must count against its parent too.
printf '{"cwd":"/work/repo-0"}\n' >> "$_PAR_DIR/projects/project with spaces/session 0.jsonl"
mkdir -p "$_PAR_DIR/projects/project with spaces/session 1/subagents"
printf '{"cwd":"/work/repo-1"}\n' > "$_PAR_DIR/projects/project with spaces/session 1/subagents/agent-a.jsonl"
# session 10 was among the 9 too, but another install rewrote it in an old shape.
printf '{\n  "schema_version": 1,\n  "sessionId": "session 10"\n}\n' > "$_PAR_INS/session 10.json"
# An orphan cache newer than the stamp is no work saved — not counted.
printf '{\n  "schema_version": %s,\n}\n' "$(sed -n 's/^SCHEMA_VERSION=//p' "$CLAUDII_HOME/bin/claudii-insights")" \
  > "$_PAR_INS/gone.json"
_PAR_OUT=$(_par_run 2>&1)
assert_contains "the next run resumes, minus grown and old-shape sessions" '6 caches already current' "$_PAR_OUT"
assert_contains "the next run rebuilds only the rest" '59 processed · 8 cached · 1 failed' "$_PAR_OUT"
assert_eq "an old-shape kept cache is rebuilt" "repo-10" "$(jq -r '.project.repo' "$_PAR_INS/session 10.json" 2>/dev/null)"
assert_eq "the keep list is removed" no "$(test -f "$_PAR_INS/.rebuild.keep" && echo yes || echo no)"
rm -f "$_PAR_INS/gone.json"
assert_eq "a completed rebuild drops its stamp" no "$(test -f "$_PAR_INS/.rebuild" && echo yes || echo no)"

# A typed --force never resumes, even over a matching stamp.
_par_crash
_PAR_OUT=$(_par_run --force 2>&1)
assert_not_contains "a typed --force ignores the stamp" 'resuming' "$_PAR_OUT"
assert_contains "a typed --force rebuilds every cache" '65 processed · 1 cached · 1 failed' "$_PAR_OUT"
assert_eq "a completed --force drops the stamp" no "$(test -f "$_PAR_INS/.rebuild" && echo yes || echo no)"

# Each key part: other insights.jq, other script → no resume. A copy of the
# tree whose file differs by one comment line runs the second (bump) attempt.
for _part in lib/insights.jq bin/claudii-insights; do
  _par_crash
  _PAR_ALT="$_PAR_DIR/alt"; mkdir -p "$_PAR_ALT"
  cp -R "$CLAUDII_HOME/bin" "$CLAUDII_HOME/lib" "$_PAR_ALT/"
  printf '\n# other code\n' >> "$_PAR_ALT/$_part"
  _PAR_OUT=$(PATH="$_PAR_DIR/bin:$PATH" CLAUDE_PROJECTS_DIR="$_PAR_DIR/projects" \
    CLAUDII_CACHE_DIR="$_PAR_DIR/cache" CLAUDII_HOME="$_PAR_ALT" CLAUDII_INSIGHTS_JOBS=2 \
    /bin/bash "$_PAR_ALT/bin/claudii-insights" aggregate 2>&1)
  assert_not_contains "other $_part does not resume" 'resuming' "$_PAR_OUT"
  assert_contains "other $_part rebuilds every cache" '65 processed · 1 cached · 1 failed' "$_PAR_OUT"
  find "$_PAR_ALT" -delete
done

# Worker count: the cgroup CPU quota caps it — v2 at the root or under this
# process's own cgroup, v1 CFS — rounding a fraction up; "max", v1 -1 and a
# quota above the CPU count leave the CPU count.
_PAR_NCPU=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)
_par_jobs() {   # $1 = description, $2 = expected -P; cgroup files set up by caller
  : > "$_PAR_DIR/xargs.log"
  _PAR_JOBS='' CLAUDII_CGROUP_ROOT="$_PAR_DIR/cg" CLAUDII_CGROUP_SELF="$_PAR_DIR/self" \
    _par_run --force >/dev/null 2>&1
  assert_contains "$1" " -P $2 " "$(cat "$_PAR_DIR/xargs.log")"
}
_par_cg() { find "$_PAR_DIR/cg" -delete 2>/dev/null; mkdir -p "$_PAR_DIR/cg"; : > "$_PAR_DIR/self"; }
_par_cg; printf '100000 100000\n' > "$_PAR_DIR/cg/cpu.max"
_par_jobs "a one-CPU v2 quota runs one worker" 1
_par_cg; printf '150000 100000\n' > "$_PAR_DIR/cg/cpu.max"
(( _PAR_NCPU >= 2 )) && _par_jobs "a 1.5-CPU quota rounds up to two workers" 2
_par_cg; printf 'max 100000\n' > "$_PAR_DIR/cg/cpu.max"
_par_jobs "an unlimited v2 cgroup keeps the CPU count" "$_PAR_NCPU"
_par_cg; printf '%s 100000\n' "$(( (_PAR_NCPU + 5) * 100000 ))" > "$_PAR_DIR/cg/cpu.max"
_par_jobs "a quota above the CPU count keeps the CPU count" "$_PAR_NCPU"
_par_cg; mkdir -p "$_PAR_DIR/cg/app.slice"; printf '100000 100000\n' > "$_PAR_DIR/cg/app.slice/cpu.max"
printf 'max 100000\n' > "$_PAR_DIR/cg/cpu.max"; printf '0::/app.slice\n' > "$_PAR_DIR/self"
_par_jobs "the own cgroup's quota wins over the root's" 1
_par_cg; mkdir -p "$_PAR_DIR/cg/cpu"
printf '100000\n' > "$_PAR_DIR/cg/cpu/cpu.cfs_quota_us"; printf '100000\n' > "$_PAR_DIR/cg/cpu/cpu.cfs_period_us"
_par_jobs "a one-CPU v1 quota runs one worker" 1
printf -- '-1\n' > "$_PAR_DIR/cg/cpu/cpu.cfs_quota_us"
_par_jobs "an unlimited v1 quota keeps the CPU count" "$_PAR_NCPU"
