# touches: bin/claudii lib/cmd/system.sh
# test_sessionline_cmd.sh — claudii sessionline on/off/status E2E tests

TEST_TMP="$CLAUDII_HOME/tmp/test_sessionline_cmd"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"
FAKE_SETTINGS="$TEST_TMP/claude_settings.json"

# ── sessionline status: settings file missing ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline 2>&1)
assert_contains "sessionline: missing settings shows info" "nicht konfiguriert" "$output"

# ── sessionline on: settings file missing → error ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline on 2>&1 || true)
assert_contains "sessionline on: missing settings exits with error" "nicht gefunden" "$output"

# ── prepare fake settings.json ──

mkdir -p "$TEST_TMP/.claude"
echo '{}' > "$TEST_TMP/.claude/settings.json"

# ── sessionline on: adds statusLine ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline on 2>&1)
assert_contains "sessionline on: reports aktiviert" "aktiviert" "$output"

# Verify settings.json now contains statusLine
val=$(jq -r '.statusLine.command' "$TEST_TMP/.claude/settings.json")
assert_eq "sessionline on: settings.json has command" "claudii-sessionline" "$val"

# ── sessionline on: idempotent ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline on 2>&1)
assert_contains "sessionline on: already active → bereits aktiv" "bereits" "$output"

# ── sessionline status: shows active ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline 2>&1)
assert_contains "sessionline: shows aktiv" "aktiv" "$output"

# ── sessionline off: removes statusLine ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline off 2>&1)
assert_contains "sessionline off: reports deaktiviert" "deaktiviert" "$output"

val=$(jq 'has("statusLine")' "$TEST_TMP/.claude/settings.json")
assert_eq "sessionline off: statusLine removed" "false" "$val"

# ── sessionline off: idempotent ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline off 2>&1)
assert_contains "sessionline off: already off → not configured msg" "nicht konfiguriert" "$output"

# ── sessionline status: shows not configured after off ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline 2>&1)
assert_contains "sessionline: not configured after off" "nicht konfiguriert" "$output"

# ── backwards compat: sessionline shim → cc-statusline ──

output=$(HOME="$TEST_TMP" bash "$CLI" sessionline on 2>&1)
assert_contains "sessionline shim: routes to cc-statusline on → aktiviert" "aktiviert" "$output"
val=$(jq -r '.statusLine.command' "$TEST_TMP/.claude/settings.json")
assert_eq "sessionline shim: sets command" "claudii-sessionline" "$val"

# Cleanup
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
