# touches: lib/cmd/sessions.sh claudii.plugin.zsh bin/claudii-insights bin/claudii
# test_gc.sh — session cache GC function tests

# Setup: isolated cache dir in project tmp/
_gc_cache="$CLAUDII_HOME/tmp/test_gc_cache"
rm -rf "$_gc_cache"
mkdir -p "$_gc_cache"

# Create old fake session file — ppid=99999999 (dead), mtime forced to 2h ago
_gc_old="$_gc_cache/session-olddeadxx"
printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.10\n' > "$_gc_old"
# Force mtime to 2 hours ago (7200s)
_gc_old_ts=$(date -v-7200S +%Y%m%d%H%M.%S 2>/dev/null || date -d "2 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
if [[ -n "$_gc_old_ts" ]]; then
  touch -t "$_gc_old_ts" "$_gc_old"
fi

# Create fresh session file — ppid=$$ (current test process, alive), mtime=now
_gc_fresh="$_gc_cache/session-freshtest"
printf 'model=Opus\nppid=%s\nctx_pct=20\ncost=0.05\n' "$$" > "$_gc_fresh"

# Source only the GC function (not the full plugin — avoids side-effects)
# We define CLAUDII_CACHE_DIR to point at our test dir and source the function inline.
CLAUDII_CACHE_DIR="$_gc_cache"
export CLAUDII_CACHE_DIR

# Define the GC function exactly as it appears in claudii.plugin.zsh (sourced inline)
_claudii_session_gc() {
  local cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local lock="$cache_dir/gc.last"
  local now; now=$(date +%s)
  # Run at most once per hour (lockfile mtime check)
  [[ -f "$lock" ]] && (( now - $(stat -f%m "$lock" 2>/dev/null || stat -c%Y "$lock" 2>/dev/null || echo 0) < 3600 )) && return
  touch "$lock"
  local f ppid mtime
  for f in "$cache_dir"/session-*; do
    [[ -f "$f" ]] || continue
    ppid=$(grep '^ppid=' "$f" 2>/dev/null | cut -d= -f2)
    mtime=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)
    # Safety: never delete files modified < 1h ago
    (( now - mtime < 3600 )) && continue
    # Never delete if ppid alive
    [[ -n "$ppid" ]] && kill -0 "$ppid" 2>/dev/null && continue
    rm -f "$f"
  done
}

# Run GC
_claudii_session_gc

# Assert: old dead session file was deleted
if [[ -f "$_gc_old" ]]; then
  assert_eq "gc: old dead session file deleted" "deleted" "still exists"
else
  assert_eq "gc: old dead session file deleted" "deleted" "deleted"
fi

# Assert: fresh session file (ppid alive) was kept
assert_file_exists "gc: fresh/alive session file kept" "$_gc_fresh"

# Assert: gc.last lockfile created
assert_file_exists "gc: gc.last lockfile created" "$_gc_cache/gc.last"

# Assert: GC respects the hour lockfile — running again immediately must NOT delete the fresh file
# (Lock was just written so it's < 3600s old — GC should return early)
_claudii_session_gc
assert_file_exists "gc: lockfile prevents re-run within 1h (fresh file still there)" "$_gc_fresh"

# ── Gap 7 — GC: fresh file protection boundary ──────────────────────────────
# 59-minute protection: dead PPID but mtime = 59 min ago → must NOT be deleted
_gc_cache2="$CLAUDII_HOME/tmp/test_gc_boundary"
rm -rf "$_gc_cache2"
mkdir -p "$_gc_cache2"
CLAUDII_CACHE_DIR="$_gc_cache2"
export CLAUDII_CACHE_DIR

_gc_59min="$_gc_cache2/session-59mintest"
printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.10\n' > "$_gc_59min"
# Force mtime to 59 minutes ago (3540s)
_gc_59_ts=$(date -v-3540S +%Y%m%d%H%M.%S 2>/dev/null || date -d "3540 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
if [[ -n "$_gc_59_ts" ]]; then
  touch -t "$_gc_59_ts" "$_gc_59min"
fi

# Remove lockfile so GC runs (otherwise hourly lock from first test could interfere)
rm -f "$_gc_cache2/gc.last"
_claudii_session_gc
# 59 min < 3600 → must be kept
if [[ -f "$_gc_59min" ]]; then
  assert_eq "gc: 59-min-old dead session kept (< 1h protection)" "kept" "kept"
else
  assert_eq "gc: 59-min-old dead session kept (< 1h protection)" "kept" "deleted"
fi

# 61-minute boundary: dead PPID and mtime = 61 min ago → must be deleted
_gc_61min="$_gc_cache2/session-61mintest"
printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.10\n' > "$_gc_61min"
# Force mtime to 61 minutes ago (3660s)
_gc_61_ts=$(date -v-3660S +%Y%m%d%H%M.%S 2>/dev/null || date -d "3660 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
if [[ -n "$_gc_61_ts" ]]; then
  touch -t "$_gc_61_ts" "$_gc_61min"
fi

rm -f "$_gc_cache2/gc.last"
_claudii_session_gc
# 61 min > 3600 → must be deleted
if [[ -f "$_gc_61min" ]]; then
  assert_eq "gc: 61-min-old dead session deleted (> 1h)" "deleted" "still exists"
else
  assert_eq "gc: 61-min-old dead session deleted (> 1h)" "deleted" "deleted"
fi

# Cleanup boundary tests
rm -rf "$_gc_cache2"
unset _gc_cache2 _gc_59min _gc_61min _gc_59_ts _gc_61_ts

# Cleanup
rm -rf "$_gc_cache"
unset CLAUDII_CACHE_DIR _gc_cache _gc_old _gc_fresh _gc_old_ts

# ── insights gc: orphaned-cache pruning (bin/claudii-insights gc) ───────────
_igc_base="$CLAUDII_HOME/tmp/test_gc_insights"
rm -rf "$_igc_base"
mkdir -p "$_igc_base/cache/insights" "$_igc_base/projects/-fake-proj"
_igc_cache="$_igc_base/cache/insights"

# ISO timestamps: 100 days ago and now
_igc_old_iso=$(date -u -v-100d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "100 days ago" +%Y-%m-%dT%H:%M:%SZ)
_igc_now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# live: source JSONL exists, old last_seen → must NEVER be touched
printf '{"sessionId":"live-sid","last_seen":"%s"}\n' "$_igc_old_iso" > "$_igc_cache/live-sid.json"
printf '{"type":"summary"}\n' > "$_igc_base/projects/-fake-proj/live-sid.jsonl"
# orphan, old last_seen → prune at 30d
printf '{"sessionId":"orphan-old","last_seen":"%s"}\n' "$_igc_old_iso" > "$_igc_cache/orphan-old.json"
# orphan, recent last_seen → keep at 30d
printf '{"sessionId":"orphan-recent","last_seen":"%s"}\n' "$_igc_now_iso" > "$_igc_cache/orphan-recent.json"
# orphan, no last_seen, mtime 100d ago → prune at 30d via mtime fallback
printf '{"sessionId":"orphan-nots","last_seen":null}\n' > "$_igc_cache/orphan-nots.json"
_igc_old_ts=$(date -v-100d +%Y%m%d%H%M.%S 2>/dev/null || date -d "100 days ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
[[ -n "$_igc_old_ts" ]] && touch -t "$_igc_old_ts" "$_igc_cache/orphan-nots.json"

_igc_env=(env CLAUDII_CACHE_DIR="$_igc_base/cache" CLAUDE_PROJECTS_DIR="$_igc_base/projects")

# --older-than is required
"${_igc_env[@]}" "$CLAUDII_HOME/bin/claudii-insights" gc >/dev/null 2>&1
assert_eq "insights gc: missing --older-than exits 1" "1" "$?"

# Dry-run: reports 2 prunable, deletes nothing
_igc_out=$("${_igc_env[@]}" "$CLAUDII_HOME/bin/claudii-insights" gc --older-than 30 2>&1)
assert_contains "insights gc: dry-run reports 2 prunable" "2 orphaned cache(s) older than 30d would be pruned" "$_igc_out"
assert_contains "insights gc: dry-run hints --yes" "re-run with --yes" "$_igc_out"
assert_file_exists "insights gc: dry-run keeps old orphan" "$_igc_cache/orphan-old.json"
assert_file_exists "insights gc: dry-run keeps no-ts orphan" "$_igc_cache/orphan-nots.json"

# --yes: prunes the two old orphans, keeps live + recent orphan
_igc_out=$("${_igc_env[@]}" "$CLAUDII_HOME/bin/claudii-insights" gc --older-than 30 --yes 2>&1)
assert_contains "insights gc: --yes reports pruned" "pruned 2 orphaned cache(s)" "$_igc_out"
[[ -f "$_igc_cache/orphan-old.json" ]] && _igc_r="still exists" || _igc_r="deleted"
assert_eq "insights gc: --yes deletes old orphan" "deleted" "$_igc_r"
[[ -f "$_igc_cache/orphan-nots.json" ]] && _igc_r="still exists" || _igc_r="deleted"
assert_eq "insights gc: --yes deletes no-ts orphan (mtime fallback)" "deleted" "$_igc_r"
assert_file_exists "insights gc: live cache never touched" "$_igc_cache/live-sid.json"
assert_file_exists "insights gc: recent orphan kept" "$_igc_cache/orphan-recent.json"

# CLI surface: claudii gc --insights DAYS delegates (dry-run)
printf '{"sessionId":"orphan-old","last_seen":"%s"}\n' "$_igc_old_iso" > "$_igc_cache/orphan-old.json"
_igc_out=$("${_igc_env[@]}" "$CLAUDII_HOME/bin/claudii" gc --insights 30 2>&1)
assert_contains "claudii gc --insights: delegates to insights gc" "would be pruned" "$_igc_out"
assert_file_exists "claudii gc --insights: dry-run by default" "$_igc_cache/orphan-old.json"

# /bin/bash 3.2 regression: macOS system bash must produce the same dry-run result
if [[ -x /bin/bash ]]; then
  _igc_out=$("${_igc_env[@]}" /bin/bash "$CLAUDII_HOME/bin/claudii-insights" gc --older-than 30 2>&1)
  assert_contains "insights gc: /bin/bash 3.2 dry-run works" "1 orphaned cache(s) older than 30d would be pruned" "$_igc_out"
fi

rm -rf "$_igc_base"
unset _igc_base _igc_cache _igc_old_iso _igc_now_iso _igc_old_ts _igc_env _igc_out _igc_r
