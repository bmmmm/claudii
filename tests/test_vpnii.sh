# touches: lib/cmd/vpnii.sh bin/claudii
# test_vpnii.sh — VPN state file management (set/clear/show) lifecycle.
# Drop-priv path (root → user) is not exercised here — needs real sudo
# context; assertion focused on the user-context fast path which is what
# wg-quick triggers via `sudo -u <user>` once the conf is updated.

_vt_run() {
  local home="$1"; shift
  HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    bash "$CLAUDII_HOME/bin/claudii" vpnii "$@"
}

# ── lifecycle: set → show → clear → show ──────────────────────────────────────

_vt_home=$(mktemp -d)

_out=$(_vt_run "$_vt_home" set HomeLab 2>&1)
assert_eq "vpnii set: exit 0" "0" "$?"

_state="$_vt_home/.cache/claudii/vpnii"
assert_file_exists "vpnii set: state file written" "$_state"

_content=$(cat "$_state" 2>/dev/null)
assert_eq "vpnii set: tunnel name persisted" "HomeLab" "$_content"

# Ownership: must be the invoking user (not root, not changed)
if [[ "$(uname -s)" == "Darwin" ]]; then
  _owner=$(stat -f '%Su' "$_state" 2>/dev/null || true)
else
  _owner=$(stat -c '%U' "$_state" 2>/dev/null || true)
fi
assert_eq "vpnii set: file owned by current user" "$(id -un)" "$_owner"

_out=$(_vt_run "$_vt_home" show 2>&1)
assert_eq "vpnii show: prints tunnel name" "HomeLab" "$_out"

_vt_run "$_vt_home" clear >/dev/null 2>&1
assert_eq "vpnii clear: exit 0" "0" "$?"

if [[ -e "$_state" ]]; then
  assert_eq "vpnii clear: state file removed" "no" "yes"
else
  assert_eq "vpnii clear: state file removed" "yes" "yes"
fi

_out=$(_vt_run "$_vt_home" show 2>&1)
assert_eq "vpnii show: no tunnel after clear" "no tunnel" "$_out"

# ── input validation ──────────────────────────────────────────────────────────

# `set` without name should fail with usage hint
_out=$(_vt_run "$_vt_home" set 2>&1; echo "rc=$?")
if echo "$_out" | grep -q "Usage:.*vpnii set"; then
  assert_eq "vpnii set: rejects empty name" "true" "true"
else
  assert_eq "vpnii set: rejects empty name" "Usage: vpnii set <name>" "$_out"
fi
if echo "$_out" | grep -q "rc=2"; then
  assert_eq "vpnii set: empty name returns rc 2" "true" "true"
else
  assert_eq "vpnii set: empty name returns rc 2" "2" "$_out"
fi

# Unknown subcommand
_out=$(_vt_run "$_vt_home" zzzz 2>&1; echo "rc=$?")
if echo "$_out" | grep -q "rc=2"; then
  assert_eq "vpnii: unknown subcommand returns rc 2" "true" "true"
else
  assert_eq "vpnii: unknown subcommand returns rc 2" "2" "$_out"
fi

# ── --user override ───────────────────────────────────────────────────────────

# When invoked as the same user with --user pointing at $USER, the path
# must still resolve via that user's HOME (HOME env may differ from real
# home, but resolver uses dscl/getent — sanity-test only that the flag
# parses without error and writes successfully when target == current user)
_out=$(_vt_run "$_vt_home" set TestPath --user "$(id -un)" 2>&1; echo "rc=$?")
if echo "$_out" | grep -q "rc=0"; then
  assert_eq "vpnii set --user <self>: exit 0" "true" "true"
else
  assert_eq "vpnii set --user <self>: exit 0" "0" "$_out"
fi

_vt_run "$_vt_home" clear --user "$(id -un)" >/dev/null 2>&1

rm -rf "$_vt_home"
