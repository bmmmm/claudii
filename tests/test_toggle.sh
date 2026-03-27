# test_toggle.sh — claudii toggle (force-refresh) + status on/off E2E tests

TEST_TMP="$CLAUDII_HOME/tmp/test_toggle"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"

# ── toggle = force-refresh ──

# Write stale cache
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "${TMPDIR:-/tmp}/claudii-status-models"

output=$(bash "$CLI" toggle 2>&1)
assert_contains "toggle: shows 'Refreshing'" "Refreshing" "$output"

# After toggle, cache should be fresh (stat -f%m gives mtime, age < 30s)
cache_age=$(( $(date +%s) - $(stat -f%m "${TMPDIR:-/tmp}/claudii-status-models") ))
if (( cache_age < 30 )); then
  assert_eq "toggle: cache refreshed" "true" "true"
else
  assert_eq "toggle: cache refreshed" "fresh (<30s)" "${cache_age}s"
fi

# ── status on/off ──

# Default: statusline.enabled = true
val=$(bash "$CLI" config get statusline.enabled)
assert_eq "default: statusline.enabled = true" "true" "$val"

# status off
output=$(bash "$CLI" status off 2>&1)
assert_contains "status off: shows deactivated" "deaktiviert" "$output"
val=$(bash "$CLI" config get statusline.enabled)
assert_eq "after status off: enabled = false" "false" "$val"

# status on
output=$(bash "$CLI" status on 2>&1)
assert_contains "status on: shows aktiviert" "aktiviert" "$output"
val=$(bash "$CLI" config get statusline.enabled)
assert_eq "after status on: enabled = true" "true" "$val"

# ── status interval ──

output=$(bash "$CLI" status 5m 2>&1)
assert_contains "status 5m: shows interval" "5m" "$output"
val=$(bash "$CLI" config get status.cache_ttl)
assert_eq "status 5m: cache_ttl = 300" "300" "$val"

output=$(bash "$CLI" status 15m 2>&1)
val=$(bash "$CLI" config get status.cache_ttl)
assert_eq "status 15m: cache_ttl = 900" "900" "$val"

# Invalid interval
assert_exit_code "status invalid interval exits 1" "1" "bash '$CLI' status 20"

# ── zsh integration: RPROMPT empty when disabled ──

printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$TEST_TMP/claudii-status-models"

rprompt_disabled=$(
  TMPDIR="$TEST_TMP" XDG_CONFIG_HOME="$TEST_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    jq '.statusline.enabled = false' \"\$CLAUDII_HOME/config/defaults.json\" \
      > \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_eq "disabled: RPROMPT is empty" "" "$rprompt_disabled"

# ── zsh integration: RPROMPT shows models when enabled ──

rprompt_enabled=$(
  TMPDIR="$TEST_TMP" XDG_CONFIG_HOME="$TEST_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "enabled: RPROMPT shows Opus" "Opus" "$rprompt_enabled"
assert_contains "enabled: RPROMPT shows Sonnet" "Sonnet" "$rprompt_enabled"

# Cleanup
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
