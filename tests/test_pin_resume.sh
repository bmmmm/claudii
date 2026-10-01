# touches: lib/cmd/sessions.sh
# test_pin_resume.sh — pin/unpin/resume command tests

# ── Shared setup ────────────────────────────────────────────────────────────
_PR_TMP="$(mktemp -d)"
_PR_XDG="$_PR_TMP/xdg"
mkdir -p "$_PR_XDG/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$_PR_XDG/claudii/config.json"
export CLAUDII_CACHE_DIR="$_PR_TMP"
export XDG_CONFIG_HOME="$_PR_XDG"

# Create a valid session file with a known session_id
_pr_sid="abcdef1234567890abcdef1234567890abcdef12"
printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.25\nsession_id=%s\nworktree=\nagent=\n' \
  "$_pr_sid" > "$_PR_TMP/session-${_pr_sid}"

# ── pin: no argument → non-zero exit + usage ────────────────────────────────
_pin_noop=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin 2>&1; echo "exit:$?")
assert_eq "pin no-arg: exits non-zero" "1" \
  "$(echo "$_pin_noop" | grep '^exit:' | cut -d: -f2)"
assert_contains "pin no-arg: shows usage" "Usage:" \
  "$(echo "$_pin_noop" | grep -v '^exit:')"

# ── pin: nonexistent ID → non-zero exit + error ──────────────────────────────
_pin_bad=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin nonexistent-id-xyz 2>&1; echo "exit:$?")
assert_eq "pin nonexistent: exits non-zero" "1" \
  "$(echo "$_pin_bad" | grep '^exit:' | cut -d: -f2)"
assert_contains "pin nonexistent: error message" "No session matching" \
  "$(echo "$_pin_bad" | grep -v '^exit:')"

# ── pin: valid session → session file has pinned=1 ──────────────────────────
CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin "$_pr_sid" >/dev/null 2>&1
assert_eq "pin valid: session file has pinned=1" "1" \
  "$(grep -c '^pinned=1$' "$_PR_TMP/session-${_pr_sid}" || true)"

# ── pin: idempotent — pinning an already-pinned session exits 0, no corruption ─
_pin_idem=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin "$_pr_sid" 2>&1; echo "exit:$?")
assert_eq "pin idempotent: exits 0" "0" \
  "$(echo "$_pin_idem" | grep '^exit:' | cut -d: -f2)"
assert_eq "pin idempotent: still exactly one pinned=1 line" "1" \
  "$(grep -c '^pinned=1$' "$_PR_TMP/session-${_pr_sid}" || true)"
assert_contains "pin idempotent: reports already pinned" "Already pinned" \
  "$(echo "$_pin_idem" | grep -v '^exit:')"

# ── unpin: no argument → non-zero exit + usage ──────────────────────────────
_unpin_noop=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" unpin 2>&1; echo "exit:$?")
assert_eq "unpin no-arg: exits non-zero" "1" \
  "$(echo "$_unpin_noop" | grep '^exit:' | cut -d: -f2)"
assert_contains "unpin no-arg: shows usage" "Usage:" \
  "$(echo "$_unpin_noop" | grep -v '^exit:')"

# ── unpin: nonexistent ID → non-zero exit + error ────────────────────────────
_unpin_bad=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" unpin nonexistent-id-xyz 2>&1; echo "exit:$?")
assert_eq "unpin nonexistent: exits non-zero" "1" \
  "$(echo "$_unpin_bad" | grep '^exit:' | cut -d: -f2)"
assert_contains "unpin nonexistent: error message" "No session matching" \
  "$(echo "$_unpin_bad" | grep -v '^exit:')"

# ── unpin: pinned session → pinned=1 removed from file ──────────────────────
# (session is still pinned from the pin test above)
CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" unpin "$_pr_sid" >/dev/null 2>&1
assert_eq "unpin valid: pinned=1 removed" "0" \
  "$(grep -c '^pinned=1$' "$_PR_TMP/session-${_pr_sid}" || true)"

# ── GC respects pin: pinned session NOT deleted even when old + dead ppid ────
_pr_gc_tmp="$(mktemp -d)"
_pr_pin_sid="deadbeefdeadbeef0000000000000000deadbeef"
printf 'model=Opus\nppid=99999999\nctx_pct=30\ncost=1.00\nsession_id=%s\npinned=1\n' \
  "$_pr_pin_sid" > "$_pr_gc_tmp/session-${_pr_pin_sid}"
# Force mtime to 3 hours ago (well past GC threshold)
_pr_stale_ts=$(date -v-10800S +%Y%m%d%H%M.%S 2>/dev/null || date -d "3 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
[[ -n "$_pr_stale_ts" ]] && touch -t "$_pr_stale_ts" "$_pr_gc_tmp/session-${_pr_pin_sid}"

CLAUDII_CACHE_DIR="$_pr_gc_tmp" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" gc >/dev/null 2>&1
assert_file_exists "gc respects pin: pinned session not deleted" \
  "$_pr_gc_tmp/session-${_pr_pin_sid}"
rm -rf "$_pr_gc_tmp"
unset _pr_gc_tmp _pr_pin_sid _pr_stale_ts

# ── resume: no argument → non-zero exit + usage ─────────────────────────────
_resume_noop=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" resume 2>&1; echo "exit:$?")
assert_eq "resume no-arg: exits non-zero" "1" \
  "$(echo "$_resume_noop" | grep '^exit:' | cut -d: -f2)"
assert_contains "resume no-arg: shows usage" "Usage:" \
  "$(echo "$_resume_noop" | grep -v '^exit:')"

# ── resume: nonexistent ID → exec fails with recognizable error ─────────────
# `exec claude --resume <id>` will fail if claude is not in PATH or rejects the ID.
# We mock claude with a wrapper that exits non-zero and prints the args it received.
_mock_dir="$(mktemp -d)"
cat > "$_mock_dir/claude" <<'MOCKEOF'
#!/bin/bash
echo "mock-claude-called: $*"
exit 42
MOCKEOF
chmod +x "$_mock_dir/claude"

_resume_bad=$(PATH="$_mock_dir:$PATH" CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" resume nonexistent-id-xyz 2>&1; echo "exit:$?")
assert_eq "resume nonexistent: mock claude called and exits non-zero" "42" \
  "$(echo "$_resume_bad" | grep '^exit:' | cut -d: -f2)"
assert_matches "resume nonexistent: --resume flag passed to claude" "\-\-resume" \
  "$(echo "$_resume_bad" | grep -v '^exit:')"

# ── resume: valid ID → exec claude --resume <id> with correct argument ────────
_resume_valid=$(PATH="$_mock_dir:$PATH" CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" resume "$_pr_sid" 2>&1 || true)
assert_matches "resume valid: --resume flag passed" "\-\-resume" "$_resume_valid"
assert_contains "resume valid: session ID forwarded" "$_pr_sid" "$_resume_valid"

rm -rf "$_mock_dir"
unset _mock_dir _resume_bad _resume_valid _resume_noop

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$_PR_TMP"
unset CLAUDII_CACHE_DIR XDG_CONFIG_HOME
unset _PR_TMP _PR_XDG _pr_sid
unset _pin_noop _pin_bad _pin_idem _unpin_noop _unpin_bad
