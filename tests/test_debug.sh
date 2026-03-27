# test_debug.sh — debug mode E2E tests

TEST_TMP="$CLAUDII_HOME/tmp/test_debug"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"
SL="$CLAUDII_HOME/bin/claudii-sessionline"
JSON='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521},"cost":{"total_cost_usd":0.55}}'

# ── Defaults ──

val=$(bash "$CLI" config get debug.level)
assert_eq "default debug.level = off" "off" "$val"

# ── claudii debug (show current) ──

output=$(bash "$CLI" debug 2>&1)
assert_contains "debug shows current level" "off" "$output"
assert_contains "debug shows valid levels" "error" "$output"

# ── claudii debug <level> ──

for level in error warn info debug off; do
  output=$(bash "$CLI" debug "$level" 2>&1)
  assert_contains "debug set $level: confirmation" "$level" "$output"
  val=$(bash "$CLI" config get debug.level)
  assert_eq "debug.level = $level after set" "$level" "$val"
done

# ── Invalid level ──

assert_exit_code "invalid level exits 1" "1" "bash '$CLI' debug invalid"

# ── CLAUDII_LOG_LEVEL env var: sessionline debug output ──

stderr=$(echo "$JSON" | CLAUDII_LOG_LEVEL=debug bash "$SL" 2>&1 >/dev/null)
assert_contains "sessionline debug: shows parsed model" "model=Opus" "$stderr"
assert_contains "sessionline debug: shows [claudii:debug]" "[claudii:debug]" "$stderr"

# ── CLAUDII_LOG_LEVEL=off: no output ──

stderr=$(echo "$JSON" | CLAUDII_LOG_LEVEL=off bash "$SL" 2>&1 >/dev/null)
assert_eq "sessionline: no debug output when off" "" "$stderr"

# ── claudii-status: info output ──

rm -f "${TMPDIR:-/tmp}/claudii-status-models"
stderr=$(CLAUDII_LOG_LEVEL=info bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 >/dev/null || true)
assert_contains "status info: shows [claudii:info]" "[claudii:info]" "$stderr"

# ── claudii-status: debug output ──

rm -f "${TMPDIR:-/tmp}/claudii-status-models"
stderr=$(CLAUDII_LOG_LEVEL=debug bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 >/dev/null || true)
assert_contains "status debug: shows components URL" "Components URL" "$stderr"

# ── claudii-status: cache hit with debug ──

# Write a fresh cache (age 0s)
printf "opus=ok\nsonnet=ok\nhaiku=ok\n" > "${TMPDIR:-/tmp}/claudii-status-models"
stderr=$(CLAUDII_LOG_LEVEL=debug bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 >/dev/null || true)
assert_contains "status debug: cache hit message" "Cache hit" "$stderr"

# Cleanup
bash "$CLI" debug off >/dev/null 2>&1
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
