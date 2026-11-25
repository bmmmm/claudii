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

# ── pin/unpin: exit-code contract ────────────────────────────────────────────
# `pin -h` used to look for a session named "-h" and answer 1.
for _pc in pin unpin; do
  _pc_out=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
    bash "$CLAUDII_HOME/bin/claudii" "$_pc" -h 2>/dev/null); _pc_rc=$?
  assert_eq "$_pc -h: exit 0" "0" "$_pc_rc"
  assert_contains "$_pc -h: usage on stdout" "Usage: claudii $_pc <session-id>" "$_pc_out"
  _pc_out=$(CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
    bash "$CLAUDII_HOME/bin/claudii" "$_pc" --bogus 2>&1 >/dev/null); _pc_rc=$?
  assert_eq "$_pc --bogus: exit 2" "2" "$_pc_rc"
  assert_contains "$_pc --bogus: contract message" "claudii $_pc: unknown option: --bogus" "$_pc_out"
done
unset _pc _pc_out _pc_rc

# ── pin: valid session → session file has pinned=1 ──────────────────────────
CLAUDII_CACHE_DIR="$_PR_TMP" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin "$_pr_sid" >/dev/null 2>&1
assert_eq "pin valid: session file has pinned=1" "1" \
  "$(grep -c '^pinned=1$' "$_PR_TMP/session-${_pr_sid}" || true)"

# ── pin: matches the session_id line, not only the file name ────────────────
# The file name carries no part of the id, so only the session_id read can match.
_PR_SID_DIR="$(mktemp -d)"
printf 'model=Sonnet\nsession_id=feedface00\n' > "$_PR_SID_DIR/session-unrelated"
CLAUDII_CACHE_DIR="$_PR_SID_DIR" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin feedface >/dev/null 2>&1
assert_eq "pin by session_id: file has pinned=1" "1" \
  "$(grep -c '^pinned=1$' "$_PR_SID_DIR/session-unrelated" || true)"
rm -rf "$_PR_SID_DIR"

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

# ── pin: an interrupted pin leaves a `.tmp.` file, which no reader treats as a session ──
# The old `${f}.pin.PID` temp name was not covered by the `*.tmp.*` filter that
# _session_files and gc apply to atomic-write leftovers. A failing `mv` stands
# in for the interruption: the temp file is what stays behind.
_pt_dir=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_pintmp.XXXXXX")
_pt_stub=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_pintmp_stub.XXXXXX")
printf '#!/bin/bash\nexit 1\n' > "$_pt_stub/mv"; chmod +x "$_pt_stub/mv"
printf 'model=Sonnet\nsession_id=0123456789abcdef\n' > "$_pt_dir/session-pintmp"
PATH="$_pt_stub:$PATH" CLAUDII_CACHE_DIR="$_pt_dir" XDG_CONFIG_HOME="$_PR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" pin 0123456789abcdef >/dev/null 2>&1
_pt_left=""
for _pt_f in "$_pt_dir"/*; do
  [[ "${_pt_f##*/}" == "session-pintmp" ]] || _pt_left+="${_pt_f##*/}"$'\n'
done
assert_contains "pin interrupted: the leftover temp file has a .tmp. name" ".tmp." "$_pt_left"
assert_eq "pin interrupted: every leftover is a .tmp. name" "" \
  "$(printf '%s\n' "$_pt_left" | grep -v '\.tmp\.' || true)"
_pt_list=$(CLAUDII_CACHE_DIR="$_pt_dir" XDG_CONFIG_HOME="$_PR_XDG" bash -c '
  source "$CLAUDII_HOME/lib/helpers.sh"; _session_files "$CLAUDII_CACHE_DIR"
  printf "%s\n" "${_SESSION_FILES[@]}"')
assert_eq "pin interrupted: only the real session is listed" "$_pt_dir/session-pintmp" "$_pt_list"
rm -rf "$_pt_dir" "$_pt_stub"
unset _pt_dir _pt_stub _pt_left _pt_list _pt_f

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$_PR_TMP"
unset CLAUDII_CACHE_DIR XDG_CONFIG_HOME
unset _PR_TMP _PR_XDG _pr_sid
unset _pin_noop _pin_bad _pin_idem _unpin_noop _unpin_bad
