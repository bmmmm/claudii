# test_toggle.sh — claudii status + RPROMPT integration E2E tests

TEST_TMP="$CLAUDII_HOME/tmp/test_toggle"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/cache" "$TEST_TMP/config/claudii"
export XDG_CONFIG_HOME="$TEST_TMP/config"
export CLAUDII_CACHE_DIR="$TEST_TMP/cache"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"

# ── claudii status always fetches live (cache is cleared first) ──

# Write stale cache
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CLAUDII_CACHE_DIR/status-models"
touch -t 202001010000 "$CLAUDII_CACHE_DIR/status-models"

bash "$CLI" status >/dev/null 2>&1 || true

# After status, cache should be fresh (mtime updated by claudii-status)
cache_age=$(( $(date +%s) - $(stat -c%Y "$CLAUDII_CACHE_DIR/status-models" 2>/dev/null || stat -f%m "$CLAUDII_CACHE_DIR/status-models" 2>/dev/null || echo 0) ))
if (( cache_age < 30 )); then
  assert_eq "status: cache is fresh after run" "true" "true"
else
  assert_eq "status: cache is fresh after run" "fresh (<30s)" "${cache_age}s"
fi

# ── claudii on/off (top-level) ──

val=$(bash "$CLI" config get statusline.enabled)
assert_eq "default: statusline.enabled = true" "true" "$val"

output=$(bash "$CLI" off 2>&1)
assert_contains "off: shows disabled" "disabled" "$output"
val=$(bash "$CLI" config get statusline.enabled)
assert_eq "after off: enabled = false" "false" "$val"

output=$(bash "$CLI" on 2>&1)
assert_contains "on: shows enabled" "enabled" "$output"
val=$(bash "$CLI" config get statusline.enabled)
assert_eq "after on: enabled = true" "true" "$val"

# ── status interval ──

output=$(bash "$CLI" status 5m 2>&1)
assert_contains "status 5m: shows interval" "5m" "$output"
val=$(bash "$CLI" config get status.cache_ttl)
assert_eq "status 5m: cache_ttl = 300" "300" "$val"

output=$(bash "$CLI" status 15m 2>&1)
val=$(bash "$CLI" config get status.cache_ttl)
assert_eq "status 15m: cache_ttl = 900" "900" "$val"

assert_exit_code "status invalid interval exits 1" "1" "bash '$CLI' status 20"

# ── zsh integration: RPROMPT empty when disabled ──

printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$TEST_TMP/status-models"

rprompt_disabled=$(
  CLAUDII_CACHE_DIR="$TEST_TMP" XDG_CONFIG_HOME="$TEST_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
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
  CLAUDII_CACHE_DIR="$TEST_TMP" XDG_CONFIG_HOME="$TEST_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
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
unset XDG_CONFIG_HOME CLAUDII_CACHE_DIR
