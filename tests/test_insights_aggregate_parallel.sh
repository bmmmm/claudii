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
  printf 'fanout\n' >> "$_PAR_DIR/xargs.log"
  [[ "\${_PAR_KILL:-}" == 1 ]] && exit 125 ;;
esac
exec "$_PAR_REAL_XARGS" "\$@"
SHIM
chmod +x "$_PAR_DIR/bin/xargs"; : > "$_PAR_DIR/xargs.log"
_par_run() {
  PATH="$_PAR_DIR/bin:$PATH" \
    CLAUDE_PROJECTS_DIR="$_PAR_DIR/projects" CLAUDII_CACHE_DIR="$_PAR_DIR/cache" \
    CLAUDII_INSIGHTS_JOBS=2 /bin/bash "$CLAUDII_HOME/bin/claudii-insights" aggregate "$@"
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
