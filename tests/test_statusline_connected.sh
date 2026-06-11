# touches: lib/helpers.sh lib/cmd/system.sh lib/cmd/overview.sh bin/claudii-cc-statusline
# test_statusline_connected.sh — wrapper-chain recognition + ClaudeStatus self-refresh
#
# Regression cover for two bugs:
#   1. A custom statusLine wrapper chain (settings.json command → wrapper script
#      → claudii-cc-statusline) was reported as "other/custom" by doctor,
#      cc-statusline status and overview — and CLOBBERED by `claudii on`.
#   2. claudii-cc-statusline never refreshed the status-models cache, so the
#      ClaudeStatus segment age grew unbounded inside long Claude Code sessions.

TEST_TMP="$CLAUDII_HOME/tmp/test_statusline_connected"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/.claude" "$TEST_TMP/cache"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"
SETTINGS="$TEST_TMP/.claude/settings.json"

# Fake wrapper script on PATH that invokes claudii-cc-statusline (one level
# of indirection — mirrors a user's dotfiles wrapper).
cat > "$TEST_TMP/bin/fake-sl-wrap" <<'EOF'
#!/bin/bash
exec claudii-cc-statusline
EOF
chmod +x "$TEST_TMP/bin/fake-sl-wrap"

# ── _cc_statusline_connected unit tests (sourced helper) ──

# /bin/bash explicitly: production runs lib/helpers.sh under macOS bash 3.2,
# the test runner uses Homebrew bash 5.x which would mask 3.2-only breakage.
_connected() {
  PATH="$TEST_TMP/bin:$PATH" /bin/bash -c "
    CLAUDII_HOME='$CLAUDII_HOME'
    source '$CLAUDII_HOME/lib/helpers.sh'
    _cc_statusline_connected \"\$1\"
  " _ "$1" && echo yes || echo no
}

assert_eq "connected: plain command"          "yes" "$(_connected 'claudii-cc-statusline')"
assert_eq "connected: insomnii wrapper"       "yes" "$(_connected 'cc-insomnii --after=claudii-cc-statusline')"
assert_eq "connected: custom wrapper chain"   "yes" "$(_connected 'cc-insomnii --after=fake-sl-wrap')"
assert_eq "connected: bare wrapper script"    "yes" "$(_connected 'fake-sl-wrap')"
assert_eq "connected: unrelated command"      "no"  "$(_connected 'some-other-statusline')"
assert_eq "connected: empty command"          "no"  "$(_connected '')"
# Glob chars in the command must not expand against the cwd (regression:
# unquoted `for _w in $_cmd` globbed; a `*` arg could match arbitrary files).
assert_eq "connected: glob arg not expanded"  "no"  "$(cd "$TEST_TMP" && _connected 'other-tool --glob=*')"

# ── `claudii on` must NOT clobber a connected wrapper chain ──

printf '{"statusLine":{"type":"command","command":"cc-insomnii --after=fake-sl-wrap"}}\n' > "$SETTINGS"
HOME="$TEST_TMP" PATH="$TEST_TMP/bin:$PATH" bash "$CLI" on >/dev/null 2>&1
after=$(jq -r '.statusLine.command' "$SETTINGS")
assert_eq "claudii on: wrapper chain preserved" "cc-insomnii --after=fake-sl-wrap" "$after"

# ── `claudii on` still installs the plain command over an unrelated one ──

printf '{"statusLine":{"type":"command","command":"some-other-statusline"}}\n' > "$SETTINGS"
HOME="$TEST_TMP" PATH="$TEST_TMP/bin:$PATH" bash "$CLI" on >/dev/null 2>&1
after=$(jq -r '.statusLine.command' "$SETTINGS")
assert_eq "claudii on: unrelated command replaced" "claudii-cc-statusline" "$after"

# ── `claudii cc-statusline` status reports the chain as active ──

printf '{"statusLine":{"type":"command","command":"cc-insomnii --after=fake-sl-wrap"}}\n' > "$SETTINGS"
output=$(HOME="$TEST_TMP" PATH="$TEST_TMP/bin:$PATH" bash "$CLI" cc-statusline 2>&1)
assert_contains "cc-statusline status: wrapper chain active" "active" "$output"

# ── `claudii cc-statusline on` keeps a custom connected chain ──

output=$(HOME="$TEST_TMP" PATH="$TEST_TMP/bin:$PATH" bash "$CLI" cc-statusline on 2>&1)
after=$(jq -r '.statusLine.command' "$SETTINGS")
assert_eq "cc-statusline on: wrapper chain preserved" "cc-insomnii --after=fake-sl-wrap" "$after"
assert_contains "cc-statusline on: reports already active" "already active" "$output"

# ── doctor reports the chain as configured ──

output=$(HOME="$TEST_TMP" PATH="$TEST_TMP/bin:$PATH" bash "$CLI" doctor 2>&1 || true)
assert_contains "doctor: wrapper chain recognized" "CC-Statusline configured" "$output"

# ── ClaudeStatus self-refresh: stale cache triggers a background fetch ──

# Unreachable URLs → claudii-status fails fast and writes the all-ok +
# _api=unreachable fallback. That write (mtime bump) proves the spawn happened.
export CLAUDII_UNRESOLVED_URL="https://127.0.0.1:1/unresolved.json"
export CLAUDII_RSS_URL="https://127.0.0.1:1/history.rss"
SL_CACHE="$TEST_TMP/cache"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$SL_CACHE/status-models"
touch -t 202601010000 "$SL_CACHE/status-models"  # far in the past → stale

printf '{"model":{"display_name":"Opus"},"session_id":"slconn00-0000"}\n' | \
  CLAUDII_CACHE_DIR="$SL_CACHE" bash "$CLAUDII_HOME/bin/claudii-cc-statusline" >/dev/null 2>&1

# Background fetch is async — wait up to 8s for the cache rewrite.
refreshed=no
for _i in 1 2 3 4 5 6 7 8; do
  if grep -q '_api=unreachable' "$SL_CACHE/status-models" 2>/dev/null; then
    refreshed=yes; break
  fi
  sleep 1
done
assert_eq "self-refresh: stale cache rewritten by spawned claudii-status" "yes" "$refreshed"

# ── ClaudeStatus self-refresh: fresh cache spawns nothing ──

rm -f "$SL_CACHE/status.pid"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$SL_CACHE/status-models"  # fresh mtime
printf '{"model":{"display_name":"Opus"},"session_id":"slconn00-0000"}\n' | \
  CLAUDII_CACHE_DIR="$SL_CACHE" bash "$CLAUDII_HOME/bin/claudii-cc-statusline" >/dev/null 2>&1
sleep 1
spawned=no
[[ -f "$SL_CACHE/status.pid" ]] && spawned=yes
assert_eq "self-refresh: fresh cache → no spawn" "no" "$spawned"
assert_eq "self-refresh: fresh cache untouched" "" "$(grep '_api=unreachable' "$SL_CACHE/status-models" || true)"

unset CLAUDII_UNRESOLVED_URL CLAUDII_RSS_URL
