# touches: bin/claudii-sessionline
# test_sessionline.sh — in-session statusline rendering

SL="$CLAUDII_HOME/bin/claudii-sessionline"

# Full data (all fields)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | bash "$SL" 2>&1)
assert_contains "shows model name" "Opus" "$output"
assert_contains "shows context %" "52%" "$output"
assert_contains "shows cost" "0.55" "$output"
assert_contains "shows input tokens" "15.2K" "$output"
assert_contains "shows output tokens" "4.5K" "$output"
assert_contains "shows 5h rate" "5h:" "$output"
assert_contains "shows 7d rate" "7d:" "$output"
assert_contains "shows lines added" "+156" "$output"
assert_contains "shows lines removed" "23" "$output"
assert_contains "shows duration" "12m" "$output"

# High context (90%+)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":95,"total_input_tokens":190000,"total_output_tokens":50000,"context_window_size":200000},"cost":{"total_cost_usd":2.10,"total_duration_ms":3600000}}' | bash "$SL" 2>&1)
assert_contains "high context shows 100%" "100%" "$output"
assert_contains "large tokens formatted" "190.0K" "$output"
assert_contains "duration 1h" "1h 0m" "$output"

# Million tokens
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":1500000,"total_output_tokens":300000,"context_window_size":200000},"cost":{"total_cost_usd":15.00,"total_duration_ms":120000}}' | bash "$SL" 2>&1)
assert_contains "million tokens formatted" "1.5M" "$output"

# Extended context window (1M)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":100000,"total_output_tokens":20000,"context_window_size":1000000},"cost":{"total_cost_usd":1.00,"total_duration_ms":300000}}' | bash "$SL" 2>&1)
assert_contains "1M context indicator" "1M" "$output"

# Minimal data (no rate limits, no lines, no duration)
output=$(echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":5,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' | bash "$SL" 2>&1)
assert_contains "minimal data shows model" "Haiku" "$output"
assert_contains "minimal data shows cost" "0.01" "$output"

# No rate limits — should not leak other fields into rate display
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":50,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000},"cost":{"total_cost_usd":0.10,"total_duration_ms":60000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "no rate limits: no 5h in output" "0" "$(echo "$strip" | grep -c '5h:')"
assert_eq "no rate limits: no 7d in output" "0" "$(echo "$strip" | grep -c '7d:')"

# Empty JSON
output=$(echo '{}' | bash "$SL" 2>&1)
assert_eq "empty json doesn't crash" "0" "$?"

# Cache hit ratio (⚡) — shown when cache_read_input_tokens > 0
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":5000,"cache_creation_input_tokens":0}},"cost":{"total_cost_usd":0.20,"total_duration_ms":60000}}' | bash "$SL" 2>&1)
assert_contains "cache hit shows lightning bolt" "⚡" "$output"
assert_contains "cache hit shows percentage" "33%" "$output"

# Cache hit ratio — NOT shown when cache_read is 0
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":500}},"cost":{"total_cost_usd":0.10,"total_duration_ms":60000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "no cache hit: no lightning bolt" "0" "$(echo "$strip" | grep -c '⚡')"

# Effort mode — shown when CLAUDII_EFFORT is set to something other than "high"
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | CLAUDII_EFFORT=max bash "$SL" 2>&1)
assert_contains "effort mode max shown" "max" "$output"

output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | CLAUDII_EFFORT=medium bash "$SL" 2>&1)
assert_contains "effort mode medium shown" "medium" "$output"

# Effort mode "high" — NOT shown (it's the default)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | CLAUDII_EFFORT=high bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "effort mode high not shown" "0" "$(echo "$strip" | grep -c ' high')"

# Worktree/Agent — written to session cache file
mkdir -p "$CLAUDII_HOME/tmp"
_test_cache_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"
output=$(echo '{"session_id":"testworktreeagent","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05},"workspace":{"name":"my-feature-branch"},"agent":{"name":"agent-42"}}' | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>&1)
_test_session_file="$_test_cache_dir/session-testwork"
assert_file_exists "worktree/agent: session cache file created" "$_test_session_file"
_cache_contents="$(cat "$_test_session_file" 2>/dev/null)"
assert_contains "session cache has worktree=" "worktree=my-feature-branch" "$_cache_contents"
assert_contains "session cache has agent=" "agent=agent-42" "$_cache_contents"
rm -rf "$_test_cache_dir"

# ppid — written to session cache file so RPROMPT can detect dead sessions
_test_cache_dir="$(mktemp -d)"
echo '{"session_id":"testppid123456","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>&1 >/dev/null
_test_session_file="$_test_cache_dir/session-testppid"
_cache_contents="$(cat "$_test_session_file" 2>/dev/null)"
assert_contains "session cache has ppid=" "ppid=" "$_cache_contents"
# ppid value must be a non-zero integer (the bash process that ran claudii-sessionline)
_ppid_val="$(echo "$_cache_contents" | grep '^ppid=' | cut -d= -f2)"
[[ "$_ppid_val" =~ ^[0-9]+$ ]] \
  && assert_eq "session cache ppid is a valid PID integer" "true" "true" \
  || assert_eq "session cache ppid is a valid PID integer" "true" "false (got: $_ppid_val)"
rm -rf "$_test_cache_dir"

# Token order: input↑ must appear before output↓ in the rendered line
# (values from real session: 64.9K input, 121.1K output — order matters regardless of magnitude)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":47,"total_input_tokens":64900,"total_output_tokens":121100,"context_window_size":200000},"cost":{"total_cost_usd":12.53,"total_duration_ms":3600000},"rate_limits":{"five_hour":{"used_percentage":11},"seven_day":{"used_percentage":65}}}' | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
up_pos=$(echo "$strip" | grep -bo '↑' | head -1 | cut -d: -f1 || echo "9999")
down_pos=$(echo "$strip" | grep -bo '↓' | head -1 | cut -d: -f1 || echo "9999")
assert_contains "token input shown with ↑" "64.9K↑" "$strip"
assert_contains "token output shown with ↓" "121.1K↓" "$strip"
assert_eq "token order: ↑ (input) appears before ↓ (output)" "true" "$([ "${up_pos:-9999}" -lt "${down_pos:-9999}" ] && echo true || echo false)"

# Reset countdown in sessionline — must show "↺Xm" symbol when resets_at is set
_reset_ts=$(( $(date +%s) + 5400 ))
output=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":47,\"total_input_tokens\":64900,\"total_output_tokens\":121100,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":12.53,\"total_duration_ms\":3600000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":11,\"resets_at\":${_reset_ts}},\"seven_day\":{\"used_percentage\":65}}}" | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "sessionline shows reset countdown" "1" "$(echo "$strip" | grep -cE '↺[0-9]+m' || true)"

# Reset countdown color: green (\033[32m) when rate_5h >= 50% and < 5min remaining
_reset_soon=$(( $(date +%s) + 180 ))
output_soon=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":47,\"total_input_tokens\":64900,\"total_output_tokens\":121100,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":12.53,\"total_duration_ms\":3600000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":67,\"resets_at\":${_reset_soon}},\"seven_day\":{\"used_percentage\":65}}}" | COLUMNS=150 bash "$SL" 2>&1)
assert_eq "reset countdown < 5min + rate>=50%: green color code present" "1" "$(printf '%s' "$output_soon" | grep -c $'\033\[0;32m' || true)"

# Burn-ETA removed — "~Xmin" must NOT appear in output
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":47,"total_input_tokens":64900,"total_output_tokens":121100,"context_window_size":200000},"cost":{"total_cost_usd":12.53,"total_duration_ms":3600000},"rate_limits":{"five_hour":{"used_percentage":67},"seven_day":{"used_percentage":65}}}' | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "burn-ETA ~Xmin not shown" "0" "$(echo "$strip" | grep -cE '~[0-9]+min' || true)"

# 7d-Delta tracking — rate_7d_start persisted in cache; delta NOT rendered in sessionline output
_test_cache_dir="$(mktemp -d)"
# First call: establishes rate_7d_start=60
echo '{"session_id":"test7ddelta12","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":60}}}' \
  | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>/dev/null >/dev/null
# Second call: rate_7d is now 62 → delta not in output, but start cached
output=$(echo '{"session_id":"test7ddelta12","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":62}}}' \
  | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "7d delta not shown in sessionline output" "0" "$(echo "$strip" | grep -cE '\(\+[0-9]+%\)' || true)"
_cache_7d="$(cat "$_test_cache_dir/session-test7dde" 2>/dev/null)"
assert_contains "7d_start cached from first call" "rate_7d_start=60" "$_cache_7d"
rm -rf "$_test_cache_dir"

# burn_eta written to session cache (non-empty when rate > 0 and duration > 0)
_test_cache_dir="$(mktemp -d)"
echo '{"session_id":"testburneta1","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":70},"seven_day":{"used_percentage":65}}}' \
  | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>/dev/null >/dev/null
_cache_be="$(cat "$_test_cache_dir/session-testburn" 2>/dev/null)"
assert_contains "burn_eta key present in session cache" "burn_eta=" "$_cache_be"
_burn_val="$(echo "$_cache_be" | grep '^burn_eta=' | cut -d= -f2)"
[[ "$_burn_val" =~ ^[0-9]+$ ]] \
  && assert_eq "burn_eta is a non-empty integer" "true" "true" \
  || assert_eq "burn_eta is a non-empty integer" "true" "false (got: $_burn_val)"
rm -rf "$_test_cache_dir"

# 7d-Countdown — shown when reset_7d is set (< 1h → Xm format)
_reset_7d_soon=$(( $(date +%s) + 2700 ))
output=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":30,\"total_input_tokens\":5000,\"total_output_tokens\":1000,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.50},\"rate_limits\":{\"five_hour\":{\"used_percentage\":20},\"seven_day\":{\"used_percentage\":60,\"resets_at\":${_reset_7d_soon}}}}" | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "7d countdown < 1h shows ↺Xm" "1" "$(echo "$strip" | grep -cE '↺[0-9]+m' || true)"

# 7d-Countdown — 1h–24h range → Xh format
_reset_7d_hours=$(( $(date +%s) + 50400 ))
output=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":30,\"total_input_tokens\":5000,\"total_output_tokens\":1000,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.50},\"rate_limits\":{\"five_hour\":{\"used_percentage\":20},\"seven_day\":{\"used_percentage\":60,\"resets_at\":${_reset_7d_hours}}}}" | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "7d countdown 1h-24h shows ↺Xh" "1" "$(echo "$strip" | grep -cE '↺[0-9]+h' || true)"

# 7d-Countdown — >= 24h → XdYh format
_reset_7d_days=$(( $(date +%s) + 190800 ))
output=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":30,\"total_input_tokens\":5000,\"total_output_tokens\":1000,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.50},\"rate_limits\":{\"five_hour\":{\"used_percentage\":20},\"seven_day\":{\"used_percentage\":60,\"resets_at\":${_reset_7d_days}}}}" | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "7d countdown >= 24h shows ↺XdYh" "1" "$(echo "$strip" | grep -cE '↺[0-9]+d[0-9]*h?' || true)"

# --- new tests (multi-line layout + segment pre-computation) ---

# Default output has exactly 2 non-empty lines
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | bash "$SL" 2>/dev/null)
_nonempty_lines=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^ ]' || true)
assert_eq "default output has exactly 2 non-empty lines" "2" "$_nonempty_lines"

# Single-line config (statusline.lines with 1 array) → 1 output line
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","context-bar","cost","rate-5h","rate-7d","tokens","lines-changed","duration"]]}}\n' \
  > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.20,"total_duration_ms":60000},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
_single_lines=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^ ]' || true)
assert_eq "single-line config produces 1 output line" "1" "$_single_lines"
rm -rf "$_test_cfg_dir"

# Empty segments skipped: worktree and agent absent when not in JSON input
output=$(echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":30000}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "worktree absent when not in JSON" "0" "$(echo "$strip" | grep -c '@' || true)"

# burn-eta visible: session with duration + high rate_5h → ETA appears on line 2
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":70,"total_input_tokens":50000,"total_output_tokens":10000,"context_window_size":200000},"cost":{"total_cost_usd":2.00,"total_duration_ms":600000},"rate_limits":{"five_hour":{"used_percentage":80},"seven_day":{"used_percentage":60}}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "burn-eta ETA visible on line 2" "1" "$(echo "$strip" | grep -c 'ETA:' || true)"

# _tok() correctness: 999→"999", 1000→"1.0K", 1500→"1.5K", 1000000→"1.0M"
# Test via minimal JSON that exercises token formatting
output_999=$(echo '{"model":{"display_name":"T"},"context_window":{"used_percentage":1,"total_input_tokens":999,"total_output_tokens":0,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | bash "$SL" 2>/dev/null)
strip_999=$(echo "$output_999" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "_tok(999) = 999" "999↑" "$strip_999"

output_1k=$(echo '{"model":{"display_name":"T"},"context_window":{"used_percentage":1,"total_input_tokens":1000,"total_output_tokens":0,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | bash "$SL" 2>/dev/null)
strip_1k=$(echo "$output_1k" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "_tok(1000) = 1.0K" "1.0K↑" "$strip_1k"

output_1500=$(echo '{"model":{"display_name":"T"},"context_window":{"used_percentage":1,"total_input_tokens":1500,"total_output_tokens":0,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | bash "$SL" 2>/dev/null)
strip_1500=$(echo "$output_1500" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "_tok(1500) = 1.5K" "1.5K↑" "$strip_1500"

output_1M=$(echo '{"model":{"display_name":"T"},"context_window":{"used_percentage":1,"total_input_tokens":1000000,"total_output_tokens":0,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | bash "$SL" 2>/dev/null)
strip_1M=$(echo "$output_1M" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "_tok(1000000) = 1.0M" "1.0M↑" "$strip_1M"

# No bc in the script
assert_eq "no bc subprocess in claudii-sessionline" "0" "$(grep -c '\bbc\b' "$CLAUDII_HOME/bin/claudii-sessionline" || true)"
