# touches: tests/run.sh
# test_isolation.sh — the suite must never write into the user's real HOME.
#
# Why this file exists: test_sessionline.sh set no cache override, so most of
# its statusline renders went against the live ~/.cache/claudii and appended
# fixture rows to the real cost history (66,812 of 475,659 rows across all
# months). The fix lives in tests/run.sh (_run_single_test sandboxes HOME and
# the XDG roots per test file); this file is the gate that keeps it fixed.
#
# It goes red without the sandbox: on a pre-fix tree HOME is the real home,
# and the render below lands in the user's live cache.

_iso_real="${_CLAUDII_TEST_REAL_HOME:-}"

assert_eq "run.sh exports the real home for comparison" "0" \
  "$([[ -n "$_iso_real" ]] && echo 0 || echo 1)"

assert_eq "HOME is sandboxed, not the user's real home" "0" \
  "$([[ -n "$_iso_real" && "$HOME" != "$_iso_real" ]] && echo 0 || echo 1)"

assert_eq "XDG_CACHE_HOME is sandboxed" "0" \
  "$([[ -n "${XDG_CACHE_HOME:-}" && "$XDG_CACHE_HOME" != "$_iso_real/.cache" ]] && echo 0 || echo 1)"

assert_eq "XDG_CONFIG_HOME is sandboxed" "0" \
  "$([[ -n "${XDG_CONFIG_HOME:-}" && "$XDG_CONFIG_HOME" != "$_iso_real/.config" ]] && echo 0 || echo 1)"

# CLAUDII_CACHE_DIR must stay UNSET: it outranks HOME/XDG_CACHE_HOME wherever
# it is read, so setting it globally would silently defeat every test that
# varies HOME per invocation (test_vpnii.sh does, deliberately).
assert_eq "CLAUDII_CACHE_DIR is left unset for tests to own" "" \
  "${CLAUDII_CACHE_DIR:-}"

# ── The real proof: an unguarded render must not touch the live cache ────────
# Mirrors what test_sessionline.sh does 96 times without an override. The
# session id is unique per run so a stale file from an earlier (pre-fix) run
# cannot make this pass by accident.
_iso_sid="isolationprobe$$"
printf '{"session_id":"%s","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  "$_iso_sid" | bash "$CLAUDII_HOME/bin/claudii-cc-statusline" >/dev/null 2>&1

# claudii truncates the session id for the cache filename — match on the prefix.
# Globs, not `ls | grep -q`: that pipeline is the SIGPIPE shape the repo's own
# lint in test_docs.sh rejects (and it rejected this file's first draft).
_iso_prefix="${_iso_sid:0:8}"

_iso_seen() {  # <dir> -> echoes 1 when a session-<prefix>* file exists there
  local _d="$1" _f
  for _f in "$_d"/session-"${_iso_prefix}"*; do
    [[ -e "$_f" ]] && { echo 1; return; }
  done
  echo 0
}

assert_eq "unguarded render writes into the sandbox cache" "1" \
  "$(_iso_seen "$XDG_CACHE_HOME/claudii")"

assert_eq "unguarded render leaves the real cache untouched" "0" \
  "$(_iso_seen "$_iso_real/.cache/claudii")"

# The cost history is the file that actually accumulated the damage. grep reads
# the files directly here — no pipe, so no SIGPIPE and no lint violation.
assert_eq "unguarded render appends no row to the real cost history" "1" \
  "$(grep -q "$_iso_sid" "$_iso_real"/.cache/claudii/history-*.tsv 2>/dev/null && echo 0 || echo 1)"

unset _iso_real _iso_sid _iso_prefix
unset -f _iso_seen
