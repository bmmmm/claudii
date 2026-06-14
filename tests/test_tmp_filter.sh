# touches: lib/cmd/sessions.sh lib/cmd/overview.sh lib/cmd/system.sh lib/cmd/display.sh lib/statusline.zsh lib/functions.zsh
# test_tmp_filter.sh — atomic-write artifacts (session-*.tmp.PID) must never be
# parsed as real sessions, and gc must sweep ones older than 60s.

_tf_cache="$CLAUDII_HOME/tmp/test_tmp_filter_cache"
rm -rf "$_tf_cache"
mkdir -p "$_tf_cache"

# One real session: cost=5.00, tok=5M (in+out), cache_pct=84, fresh mtime, alive ppid
printf 'model=Sonnet\nctx_pct=50\ncost=5.00\ntok=5000000\ncache_pct=84\nrate_5h=10\nrate_7d=20\nreset_5h=0\nreset_7d=0\nsession_id=realtest\nppid=%s\n' "$$" \
  > "$_tf_cache/session-realtest"

# Orphan tmp artifacts: tok=99M each — would inflate today's tokens if parsed
printf 'model=Opus\nctx_pct=80\ncost=99.00\ntok=99000000\n' > "$_tf_cache/session-realtest.tmp.11111"
printf 'model=Opus\nctx_pct=80\ncost=99.00\ntok=99000000\n' > "$_tf_cache/session-unknown.tmp.22222"

# Overview must skip .tmp.* — without the filter the two orphans would be counted
# as inactive sessions and surface a `claudii si` hint, AND their tok=99M would
# inflate today's total to 203.0M instead of 5.0M.
_tf_out=$(CLAUDII_CACHE_DIR="$_tf_cache" bash "$CLAUDII_HOME/bin/claudii" 2>&1)
assert_contains "overview: counts real session as active" "1 active session" "$_tf_out"
assert_not_contains "overview: .tmp.PID artifacts not surfaced as inactive sessions" "inactive" "$_tf_out"
# Strip ANSI before matching — accent color wraps the token amount.
_tf_plain=$(printf '%s' "$_tf_out" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "overview: today's tokens reflect only real sessions" '5.0M tok today (1 session)' "$_tf_plain"
assert_not_contains "overview: today's tokens not inflated by tmp.PID values" '203.0M' "$_tf_plain"

# claudii se must show only the one real row (header lines aside)
_tf_se_out=$(CLAUDII_CACHE_DIR="$_tf_cache" bash "$CLAUDII_HOME/bin/claudii" se 2>&1)
_tf_real_rows=$(grep -c 'realtest' <<<"$_tf_se_out" || true)
assert_eq "sessions: real-session row rendered" "1" "$_tf_real_rows"
_tf_orphan_rows=$(grep -c 'tmp\.' <<<"$_tf_se_out" || true)
assert_eq "sessions: .tmp.PID artifacts not rendered" "0" "$_tf_orphan_rows"
# se shows token throughput + cache-hit (replaces the old $cost in the detail line)
assert_contains "sessions: token throughput shown in se detail" "5.0M tok" "$_tf_se_out"
assert_contains "sessions: cache-hit shown in se detail"        "⚡84%"     "$_tf_se_out"

# gc must sweep .tmp.PID files older than 60s.
# Force one tmp file's mtime to 5 minutes ago, leave the other fresh.
_tf_old_ts=$(date -v-300S +%Y%m%d%H%M.%S 2>/dev/null || date -d "300 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
[[ -n "$_tf_old_ts" ]] && touch -t "$_tf_old_ts" "$_tf_cache/session-realtest.tmp.11111"
CLAUDII_CACHE_DIR="$_tf_cache" bash "$CLAUDII_HOME/bin/claudii" gc >/dev/null 2>&1

if [[ -f "$_tf_cache/session-realtest.tmp.11111" ]]; then
  assert_eq "gc: orphan .tmp.PID (>60s) deleted" "deleted" "still exists"
else
  assert_eq "gc: orphan .tmp.PID (>60s) deleted" "deleted" "deleted"
fi

# Fresh .tmp.PID (<60s) must survive gc — it might be an in-flight atomic write
if [[ -f "$_tf_cache/session-unknown.tmp.22222" ]]; then
  assert_eq "gc: fresh .tmp.PID (<60s) kept (in-flight write protected)" "kept" "kept"
else
  assert_eq "gc: fresh .tmp.PID (<60s) kept (in-flight write protected)" "kept" "deleted"
fi

# Real session survives gc (ppid=$$ alive)
assert_file_exists "gc: real session with alive ppid kept" "$_tf_cache/session-realtest"

rm -rf "$_tf_cache"
unset _tf_cache _tf_out _tf_plain _tf_se_out _tf_real_rows _tf_orphan_rows _tf_old_ts
