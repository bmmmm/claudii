# test_metrics.sh — claudii metrics display + debug-level logging

TEST_TMP="$CLAUDII_HOME/tmp/test_metrics"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$TEST_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$TEST_TMP/claudii-status-models"

# Helper: source plugin in isolated zsh, run a snippet, capture stdout+stderr
_run_zsh() {
  TMPDIR="$TEST_TMP" XDG_CONFIG_HOME="$TEST_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    $1
  " 2>&1
}

# ── claudii metrics output ──

output=$(_run_zsh '_claudii_show_metrics')
assert_contains "metrics: shows plugin load"          "plugin load"          "$output"
assert_contains "metrics: shows config defaults"      "config defaults"      "$output"
assert_contains "metrics: shows precmd calls"         "precmd calls"         "$output"
assert_contains "metrics: shows precmd last"          "precmd last"          "$output"
assert_contains "metrics: shows precmd avg"           "precmd avg"           "$output"
assert_contains "metrics: shows precmd total"         "precmd total"         "$output"
assert_contains "metrics: shows config reloads"       "config reloads"       "$output"

# plugin.load_us was measured — should show ms or µs (not 0µs)
assert_contains "metrics: plugin load is non-zero"    "ms"                   "$output"

# config defaults was timed — should show ms or µs
assert_contains "metrics: config defaults is non-zero" "ms"                  "$output"

# ── precmd timing increments call counter ──

output=$(_run_zsh '
  _claudii_statusline
  _claudii_statusline
  _claudii_show_metrics
')
assert_contains "metrics: 2 precmd calls after 2 runs"  "2x"                 "$output"

# ── debug level: config reload logged at debug ──

output=$(_run_zsh '
  jq ".debug.level = \"debug\"" "$XDG_CONFIG_HOME/claudii/config.json" \
    > "$XDG_CONFIG_HOME/claudii/config.json.tmp" \
    && mv "$XDG_CONFIG_HOME/claudii/config.json.tmp" "$XDG_CONFIG_HOME/claudii/config.json"
  _claudii_cache_load   # first load after mtime change
  _claudii_cache_load   # second call — cache hit, should NOT log reload
' 2>&1)
assert_contains "debug: config reload logged"         "[claudii:debug]"      "$output"
assert_contains "debug: config reload timing shown"   "config: reload"       "$output"

# ── debug level: precmd timing logged at debug ──

output=$(_run_zsh '
  jq ".debug.level = \"debug\"" "$XDG_CONFIG_HOME/claudii/config.json" \
    > "$XDG_CONFIG_HOME/claudii/config.json.tmp" \
    && mv "$XDG_CONFIG_HOME/claudii/config.json.tmp" "$XDG_CONFIG_HOME/claudii/config.json"
  _claudii_cache_load
  _claudii_statusline
')
assert_contains "debug: precmd timing logged"         "precmd:"              "$output"
assert_contains "debug: precmd uses ms/µs format"     "s"                    "$output"

# ── info level: no timing logs (debug-only) ──

output=$(_run_zsh '
  jq ".debug.level = \"info\"" "$XDG_CONFIG_HOME/claudii/config.json" \
    > "$XDG_CONFIG_HOME/claudii/config.json.tmp" \
    && mv "$XDG_CONFIG_HOME/claudii/config.json.tmp" "$XDG_CONFIG_HOME/claudii/config.json"
  _claudii_cache_load
  _claudii_statusline
')
assert_eq "info: no precmd timing log"  ""  "$(echo "$output" | grep 'precmd:' || true)"
assert_eq "info: no config reload log"  ""  "$(echo "$output" | grep 'config: reload' || true)"

# ── off level: no output at all ──

output=$(_run_zsh '_claudii_statusline')
assert_eq "off: no log output" "" "$(echo "$output" | grep '\[claudii:' || true)"

# Cleanup
rm -rf "$TEST_TMP"
