# touches: bin/claudii-cc-statusline bin/claudii-ci-refresh bin/claudii-status bin/claudii-cc-update-refresh bin/claudii-bumpii-refresh
# test_spawn_refresher.sh — _spawn_refresher pre-fork PID-file dedup
#
# Regression cover for the PID-file race: the four background refreshers used
# to check a PID file for freshness and THEN spawn the child in a `( cmd & )`
# subshell — nothing wrote the PID file before the fork, only the child did,
# after it had already started. Two near-simultaneous renders both saw an
# empty/stale PID file and both spawned a refresher.
#
# _spawn_refresher (bin/claudii-cc-statusline) fixes this by writing an INTENT
# marker (its own $$) into the PID file synchronously, BEFORE the fork. This
# test proves that ordering directly — with a deliberately slow stub child (it
# sleeps before writing its own PID) so the pre-fork write is observable on
# its own, and a second call made immediately afterwards must not spawn a
# second child. The stub's start-of-life sleep also widens the window enough
# that this test reliably goes red if the pre-fork write regresses (verified
# by hand: reverting to `child writes only after starting, nothing before the
# fork` reproduces 2 spawns instead of 1 — see the fix's commit for the
# before/after run).

TEST_TMP="$CLAUDII_TEST_TMP/test_spawn_refresher"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

# Extract _spawn_refresher verbatim from the production script (own function,
# clean `^}` close) rather than sourcing the whole ~1800-line statusline
# script, which slurps stdin and expects a live render environment.
_FN_FILE="$TEST_TMP/spawn_refresher.fn.sh"
sed -n '/^_spawn_refresher() {/,/^}/p' "$CLAUDII_HOME/bin/claudii-cc-statusline" > "$_FN_FILE"
assert_contains "extraction found the function" \
  '_spawn_refresher() {' "$(cat "$_FN_FILE")"

# Slow stub child: mimics the real refreshers' shape (records that it was
# invoked, THEN — after a delay — writes its own PID to --pid-file, exactly
# like claudii-status/-ci-refresh/-cc-update-refresh/-bumpii-refresh do on
# their child side). The delay is what makes the "before vs. after fork"
# window observable in a plain, single-process test instead of depending on
# real OS scheduling between two separate processes.
_STUB="$TEST_TMP/stub-child.sh"
_COUNTER="$TEST_TMP/spawn-count.log"
cat > "$_STUB" <<'EOF'
#!/bin/bash
_pid_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid-file) shift; _pid_file="$1" ;;
  esac
  shift
done
echo "spawned" >> "$COUNTER_FILE"
sleep 1
[[ -n "$_pid_file" ]] && printf '%s\n' "$$" > "$_pid_file"
EOF
chmod +x "$_STUB"
export COUNTER_FILE="$_COUNTER"

# ── Fix in place: two near-simultaneous calls spawn exactly one child ──

PIDFILE="$TEST_TMP/refresh.pid"
rm -f "$PIDFILE" "$_COUNTER"

_intent_out=$(/bin/bash -c "
  source '$_FN_FILE'
  _now=\$(date +%s)
  _spawn_refresher '$PIDFILE' 30 '$_STUB' --pid-file '$PIDFILE'

  # Intent marker check: by the time _spawn_refresher RETURNS, the pidfile
  # already names a live PID — even though the stub child is still asleep
  # and has not written anything itself yet. That PID is this process's own
  # \$\$ (the intent marker), not the child's.
  [[ -f '$PIDFILE' ]] || { echo 'INTENT_MISSING'; exit 1; }
  _p=\$(<'$PIDFILE')
  [[ \"\$_p\" == \"\$\$\" ]] || echo \"INTENT_MISMATCH:got=\$_p want=\$\$\"

  # Second near-simultaneous render, immediately after — must see the fresh
  # intent marker and stand down.
  _spawn_refresher '$PIDFILE' 30 '$_STUB' --pid-file '$PIDFILE'
")
assert_eq "fix: intent marker (own \$\$) is in the pidfile before the fork" "" "$_intent_out"

sleep 1.5
_spawn_count=$(wc -l < "$_COUNTER" 2>/dev/null | tr -d ' ')
assert_eq "fix: two near-simultaneous renders spawn exactly one child" "1" "$_spawn_count"

# ── Liveness handoff: the child's own PID ends up in the file afterwards ──

_final_pid=$(<"$PIDFILE")
assert_matches "fix: pidfile ends up holding a real PID after the child ran" \
  '^[0-9]+$' "$_final_pid"

# ── Red check (documented, not run every pass): reverting the pre-fork write
# reproduces the original bug. This block simulates the OLD call pattern —
# check pidfile, then fork, with NOTHING written beforehand — using the same
# slow stub, and confirms it spawns two children for the same two-call
# sequence above (this is the shape verified by hand while building the fix,
# see the task's before/after report).

_OLD_FN_FILE="$TEST_TMP/spawn_refresher_old.fn.sh"
cat > "$_OLD_FN_FILE" <<'EOF'
_spawn_refresher_old() {
  local _sr_pidfile="$1" _sr_ttl="$2"
  shift 2
  local _sr_pid="" _sr_fresh=0
  [[ -f "$_sr_pidfile" ]] && { _sr_pid=$(<"$_sr_pidfile"); } 2>/dev/null
  if [[ "$_sr_pid" =~ ^[0-9]+$ ]] && kill -0 "$_sr_pid" 2>/dev/null; then
    local _sr_mt
    _sr_mt=$(stat -f%m "$_sr_pidfile" 2>/dev/null || stat -c%Y "$_sr_pidfile" 2>/dev/null || echo 0)
    [[ "$_sr_mt" =~ ^[0-9]+$ ]] || _sr_mt=0
    (( _now - _sr_mt < _sr_ttl )) && _sr_fresh=1
  fi
  # BUG: no pre-fork write here — the child is the only thing that ever
  # writes the pidfile, and only after it has already started.
  (( _sr_fresh )) || ( "$@" >/dev/null 2>&1 & )
}
EOF

OLD_PIDFILE="$TEST_TMP/refresh-old.pid"
OLD_COUNTER="$TEST_TMP/spawn-count-old.log"
rm -f "$OLD_PIDFILE" "$OLD_COUNTER"
export COUNTER_FILE="$OLD_COUNTER"

/bin/bash -c "
  source '$_OLD_FN_FILE'
  _now=\$(date +%s)
  _spawn_refresher_old '$OLD_PIDFILE' 30 '$_STUB' --pid-file '$OLD_PIDFILE'
  _spawn_refresher_old '$OLD_PIDFILE' 30 '$_STUB' --pid-file '$OLD_PIDFILE'
"

sleep 1.5
_old_spawn_count=$(wc -l < "$OLD_COUNTER" 2>/dev/null | tr -d ' ')
assert_eq "red check: the pre-fix shape reproduces the double-spawn bug" "2" "$_old_spawn_count"
