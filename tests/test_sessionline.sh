# test_sessionline.sh — in-session statusline rendering

SL="$CLAUDII_HOME/bin/claudii-sessionline"

# Full data
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521},"cost":{"total_cost_usd":0.55},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | bash "$SL" 2>&1)
assert_contains "shows model name" "Opus" "$output"
assert_contains "shows context %" "42%" "$output"
assert_contains "shows cost" "0.55" "$output"
assert_contains "shows input tokens" "15.2K" "$output"
assert_contains "shows output tokens" "4.5K" "$output"
assert_contains "shows 5h rate" "5h:" "$output"
assert_contains "shows 7d rate" "7d:" "$output"

# High context (90%+)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":95,"total_input_tokens":190000,"total_output_tokens":50000},"cost":{"total_cost_usd":2.10}}' | bash "$SL" 2>&1)
assert_contains "high context shows 95%" "95%" "$output"
assert_contains "large tokens formatted" "190.0K" "$output"

# Million tokens
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":1500000,"total_output_tokens":300000},"cost":{"total_cost_usd":15.00}}' | bash "$SL" 2>&1)
assert_contains "million tokens formatted" "1.5M" "$output"

# Minimal data (no rate limits)
output=$(echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":5},"cost":{"total_cost_usd":0.01}}' | bash "$SL" 2>&1)
assert_contains "minimal data shows model" "Haiku" "$output"
assert_contains "minimal data shows cost" "0.01" "$output"

# Empty JSON
output=$(echo '{}' | bash "$SL" 2>&1)
# Should not crash, just output minimal/empty
assert_eq "empty json doesn't crash" "0" "$?"
