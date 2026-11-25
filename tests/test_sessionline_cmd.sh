# touches: bin/claudii lib/cmd/system.sh
# test_sessionline_cmd.sh — claudii cc-statusline on/off/status E2E tests,
# plus the removed compatibility aliases

TEST_TMP="$CLAUDII_TEST_TMP/test_sessionline_cmd"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
# Force insomnii=off so this test always exercises the plain (non-wrapper)
# branch of `cc-statusline on`, regardless of whether cc-insomnii is installed
# on the host running tests. Wrapper-mode coverage lives in test_cc_statusline_preset.sh.
jq '.statusline.insomnii = "off"' "$XDG_CONFIG_HOME/claudii/config.json" > "$XDG_CONFIG_HOME/claudii/config.json.tmp" \
  && mv "$XDG_CONFIG_HOME/claudii/config.json.tmp" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"

# ── status: settings file missing ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline 2>&1)
assert_contains "cc-statusline: missing settings shows info" "not configured" "$output"

# ── on: settings file missing → error ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline on 2>&1 || true)
assert_contains "cc-statusline on: missing settings exits with error" "not found" "$output"

# ── prepare fake settings.json ──

mkdir -p "$TEST_TMP/.claude"
echo '{}' > "$TEST_TMP/.claude/settings.json"

# ── on: adds statusLine ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline on 2>&1)
assert_contains "cc-statusline on: reports enabled" "enabled" "$output"

val=$(jq -r '.statusLine.command' "$TEST_TMP/.claude/settings.json")
assert_eq "cc-statusline on: settings.json has command" "claudii-cc-statusline" "$val"

# ── on: idempotent ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline on 2>&1)
assert_contains "cc-statusline on: already active" "already" "$output"

# ── status: shows active ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline 2>&1)
assert_contains "cc-statusline: shows active" "active" "$output"
assert_contains "cc-statusline: plain command labelled plain" "plain" "$output"

# ── off: removes statusLine ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline off 2>&1)
assert_contains "cc-statusline off: reports disabled" "disabled" "$output"

val=$(jq 'has("statusLine")' "$TEST_TMP/.claude/settings.json")
assert_eq "cc-statusline off: statusLine removed" "false" "$val"

# ── off: idempotent ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline off 2>&1)
assert_contains "cc-statusline off: already off → not configured msg" "not configured" "$output"

# ── status: shows not configured after off ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline 2>&1)
assert_contains "cc-statusline: not configured after off" "not configured" "$output"

# ── removed compatibility aliases ──
# sessionline / install-sessionline (→ cc-statusline), dashboard
# (→ session-dashboard) and layers / components (→ explain) are gone; each
# must now answer like any unknown command instead of silently routing.
for _alias in sessionline install-sessionline dashboard layers components; do
  _rc=0
  output=$(HOME="$TEST_TMP" bash "$CLI" "$_alias" 2>&1) || _rc=$?
  assert_eq "removed alias $_alias: exit 1" "1" "$_rc"
  assert_contains "removed alias $_alias: unknown command" "Unknown command: $_alias" "$output"
done
unset _alias _rc

# Cleanup
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
