# test_debug.sh — debug level via config set + CLAUDII_LOG_LEVEL env var

TEST_TMP="$CLAUDII_HOME/tmp/test_debug"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
export CLAUDII_CACHE_DIR="$TEST_TMP/cache"
mkdir -p "$CLAUDII_CACHE_DIR"

CLI="$CLAUDII_HOME/bin/claudii"
SL="$CLAUDII_HOME/bin/claudii-sessionline"
JSON='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521},"cost":{"total_cost_usd":0.55}}'

# ── debug command is removed ──

output=$(bash "$CLI" debug 2>&1 || true)
assert_contains "debug command removed: shows config redirect" "Unknown command" "$output"

# ── Use config set to manage debug.level ──

val=$(bash "$CLI" config get debug.level)
assert_eq "default debug.level = off" "off" "$val"

for level in error warn info debug off; do
  bash "$CLI" config set debug.level "$level" >/dev/null 2>&1
  val=$(bash "$CLI" config get debug.level)
  assert_eq "config set debug.level = $level" "$level" "$val"
done

# ── CLAUDII_LOG_LEVEL env var: sessionline debug output ──

stderr=$(echo "$JSON" | CLAUDII_LOG_LEVEL=debug bash "$SL" 2>&1 >/dev/null)
assert_contains "sessionline debug: shows parsed model" "model=Opus" "$stderr"
assert_contains "sessionline debug: shows [claudii:debug]" "[claudii:debug]" "$stderr"

# ── CLAUDII_LOG_LEVEL=off: no output ──

stderr=$(echo "$JSON" | CLAUDII_LOG_LEVEL=off bash "$SL" 2>&1 >/dev/null)
assert_eq "sessionline: no debug output when off" "" "$stderr"

# ── claudii-status: info output ──

rm -f "$CLAUDII_CACHE_DIR/status-models"
stderr=$(CLAUDII_LOG_LEVEL=info bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 >/dev/null || true)
assert_contains "status info: shows [claudii:info]" "[claudii:info]" "$stderr"

# ── claudii-status: debug output ──

rm -f "$CLAUDII_CACHE_DIR/status-models"
stderr=$(CLAUDII_LOG_LEVEL=debug bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 >/dev/null || true)
assert_contains "status debug: shows components URL" "Components:" "$stderr"

# ── claudii-status: cache hit with debug ──

# Write a fresh cache (age 0s)
printf "opus=ok\nsonnet=ok\nhaiku=ok\n" > "$CLAUDII_CACHE_DIR/status-models"
stderr=$(CLAUDII_LOG_LEVEL=debug bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 >/dev/null || true)
assert_contains "status debug: cache hit message" "Cache hit" "$stderr"

# Cleanup
bash "$CLI" config set debug.level off >/dev/null 2>&1
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME CLAUDII_CACHE_DIR
