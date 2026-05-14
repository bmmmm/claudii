# touches: bin/claudii lib/cmd/system.sh
# test_cc_statusline_preset.sh — `claudii cc-statusline preset` E2E tests

TEST_TMP="$CLAUDII_HOME/tmp/test_cc_statusline_preset"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
export XDG_CONFIG_HOME="$TEST_TMP/config"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

CLI="$CLAUDII_HOME/bin/claudii"
CFG="$XDG_CONFIG_HOME/claudii/config.json"

# ── preset (no args) lists available presets ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline preset 2>&1)
assert_contains "preset (no args): lists focused" "focused" "$output"
assert_contains "preset (no args): lists calm"    "calm"    "$output"
assert_contains "preset (no args): lists default" "default" "$output"

# ── preset focused: writes 3-line layout (no clock — cc-insomnii wraps via --after) ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline preset focused 2>&1)
assert_contains "preset focused: confirms" "focused" "$output"

# Layout should be 3 lines now
line_count=$(jq '.statusline.lines | length' "$CFG")
assert_eq "preset focused: 3 lines written" "3" "$line_count"

# First line: model + dir (identity)
first_line=$(jq -r '.statusline.lines[0] | join(",")' "$CFG")
assert_contains "preset focused: first line has model" "model" "$first_line"
assert_contains "preset focused: first line has dir"   "dir"   "$first_line"

# Second line: context-bar + rates (metrics)
second_line=$(jq -r '.statusline.lines[1] | join(",")' "$CFG")
assert_contains "preset focused: second line has context-bar" "context-bar" "$second_line"
assert_contains "preset focused: second line has rate-5h"     "rate-5h"     "$second_line"
assert_contains "preset focused: second line has rate-7d"     "rate-7d"     "$second_line"

# Third line: claude-status + vpn (env)
third_line=$(jq -r '.statusline.lines[2] | join(",")' "$CFG")
assert_contains "preset focused: third line has claude-status" "claude-status" "$third_line"
assert_contains "preset focused: third line has vpn"           "vpn"           "$third_line"

# Insomnii is NOT a segment in focused — it owns its own first line via the wrapper
all_segs=$(jq -r '.statusline.lines | flatten | join(",")' "$CFG")
[[ "$all_segs" != *clock* ]]
assert_eq "preset focused: clock segment absent (wrapper handles it)" "0" "$?"

# ── preset calm: writes minimal 2-line layout ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline preset calm 2>&1)
assert_contains "preset calm: confirms" "calm" "$output"

line_count=$(jq '.statusline.lines | length' "$CFG")
assert_eq "preset calm: 2 lines written" "2" "$line_count"

first_line=$(jq -r '.statusline.lines[0] | join(",")' "$CFG")
assert_eq "preset calm: first line is just model" "model" "$first_line"

second_line=$(jq -r '.statusline.lines[1] | join(",")' "$CFG")
assert_eq "preset calm: second line is just context-bar" "context-bar" "$second_line"

# ── preset default: restores shipped layout ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline preset default 2>&1)
assert_contains "preset default: confirms" "default" "$output"

line_count=$(jq '.statusline.lines | length' "$CFG")
assert_eq "preset default: 5 lines (shipped layout)" "5" "$line_count"

# ── preset unknown: errors ──

output=$(HOME="$TEST_TMP" bash "$CLI" cc-statusline preset bogus 2>&1 || true)
assert_contains "preset bogus: errors with hint" "Unknown preset" "$output"

# ── preset focused renders without crash ──
# Render a minimal sample JSON through the cc-statusline binary and verify
# no error output. (Insomnii is auto/off here so clock segment is empty.)
HOME="$TEST_TMP" bash "$CLI" cc-statusline preset focused >/dev/null 2>&1
sample='{"model":{"display_name":"Opus 4.7","id":"claude-opus-4-7"},"context_window":{"used_percentage":5},"cost":{"total_cost_usd":0.42},"rate_limits":{"five_hour":{"used_percentage":16},"seven_day":{"used_percentage":2}},"session_id":"preset01","effort":{"level":"high"},"thinking":{"enabled":true},"workspace":{"current_dir":"'"$TEST_TMP"'"}}'
render_out=$(printf '%s' "$sample" | HOME="$TEST_TMP" CLAUDII_CACHE_DIR="$TEST_TMP/cache" bash "$CLAUDII_HOME/bin/claudii-cc-statusline" 2>&1)
assert_contains "preset focused: renders model line" "Opus 4.7" "$render_out"

# ── cc-statusline on: picks wrapper vs plain based on cc-insomnii detection ──
# Two branches:
#   - cc-insomnii on PATH + statusline.insomnii != "off"  → wrapper command
#   - else                                                → plain claudii-cc-statusline
# We can't assume cc-insomnii's install state on the test host, so we synthesize
# a fake cc-insomnii on PATH for the wrapper branch and force-off for the plain.

mkdir -p "$TEST_TMP/.claude"
echo '{}' > "$TEST_TMP/.claude/settings.json"

# (a) Plain branch — insomnii=off → command must be plain claudii-cc-statusline
jq '.statusline.insomnii = "off"' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
HOME="$TEST_TMP" bash "$CLI" cc-statusline on >/dev/null 2>&1
cmd=$(jq -r '.statusLine.command' "$TEST_TMP/.claude/settings.json")
assert_eq "cc-statusline on (insomnii=off): plain command" "claudii-cc-statusline" "$cmd"

# Reset settings for (b)
echo '{}' > "$TEST_TMP/.claude/settings.json"

# (b) Wrapper branch — insomnii=auto + fake cc-insomnii on PATH
mkdir -p "$TEST_TMP/fakebin"
cat > "$TEST_TMP/fakebin/cc-insomnii" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TEST_TMP/fakebin/cc-insomnii"
jq '.statusline.insomnii = "auto"' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
PATH="$TEST_TMP/fakebin:$PATH" HOME="$TEST_TMP" bash "$CLI" cc-statusline on >/dev/null 2>&1
cmd=$(jq -r '.statusLine.command' "$TEST_TMP/.claude/settings.json")
assert_eq "cc-statusline on (cc-insomnii present): wrapper command" \
  "cc-insomnii --after=claudii-cc-statusline" "$cmd"

# status output should label the active mode
status_out=$(PATH="$TEST_TMP/fakebin:$PATH" HOME="$TEST_TMP" bash "$CLI" cc-statusline 2>&1)
assert_contains "cc-statusline status: identifies wrapper mode" "wrapper" "$status_out"

# Cleanup
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
