# test_sessionline.sh — in-session statusline rendering

SL="$CLAUDII_HOME/bin/claudii-sessionline"

# Full data (all fields)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | bash "$SL" 2>&1)
assert_contains "shows model name" "Opus" "$output"
assert_contains "shows context %" "42%" "$output"
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
assert_contains "high context shows 95%" "95%" "$output"
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
_test_cache_dir="$(mktemp -d)"
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

# Reset countdown in sessionline — must show "reset Xmin" when resets_at is set
_reset_ts=$(( $(date +%s) + 5400 ))
output=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":47,\"total_input_tokens\":64900,\"total_output_tokens\":121100,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":12.53,\"total_duration_ms\":3600000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":11,\"resets_at\":${_reset_ts}},\"seven_day\":{\"used_percentage\":65}}}" | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "sessionline shows reset countdown" "1" "$(echo "$strip" | grep -cE 'reset [0-9]+min' || true)"

# Reset countdown color: red (\033[31m) when < 10min remaining
_reset_soon=$(( $(date +%s) + 300 ))
output_soon=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":47,\"total_input_tokens\":64900,\"total_output_tokens\":121100,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":12.53,\"total_duration_ms\":3600000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":11,\"resets_at\":${_reset_soon}},\"seven_day\":{\"used_percentage\":65}}}" | COLUMNS=150 bash "$SL" 2>&1)
assert_eq "reset countdown < 10min: red color code present" "1" "$(printf '%s' "$output_soon" | grep -c $'\033\[31m' || true)"
