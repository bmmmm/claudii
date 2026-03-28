# test_dashboard.sh — Dashboard rendering, toggle, multi-session, PID-check, truncation, 7d-delta

CLI="$CLAUDII_HOME/bin/claudii"
SL="$CLAUDII_HOME/bin/claudii-sessionline"

# ── Setup ──
DASH_TMP="$CLAUDII_HOME/tmp/test_dashboard"
rm -rf "$DASH_TMP"
mkdir -p "$DASH_TMP/cache" "$DASH_TMP/config/claudii"
export XDG_CONFIG_HOME="$DASH_TMP/config"
export CLAUDII_CACHE_DIR="$DASH_TMP/cache"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

# ── Toggle: dash on/off/auto ──

# Default mode is auto
val=$(bash "$CLI" config get dashboard.enabled)
assert_eq "default: dashboard.enabled = auto" "auto" "$val"

# dash on
output=$(bash "$CLI" dash on 2>&1)
assert_contains "dash on: shows enabled" "enabled" "$output"
val=$(bash "$CLI" config get dashboard.enabled)
assert_eq "after dash on: enabled = true" "true" "$val"

# dash off
output=$(bash "$CLI" dash off 2>&1)
assert_contains "dash off: shows disabled" "disabled" "$output"
val=$(bash "$CLI" config get dashboard.enabled)
assert_eq "after dash off: enabled = off" "off" "$val"

# dash auto
output=$(bash "$CLI" dash auto 2>&1)
assert_contains "dash auto: shows auto" "auto" "$output"
val=$(bash "$CLI" config get dashboard.enabled)
assert_eq "after dash auto: enabled = auto" "auto" "$val"

# dash (no arg) shows mode
output=$(bash "$CLI" dash 2>&1)
assert_contains "dash shows current mode" "auto" "$output"

# dash invalid arg
output=$(bash "$CLI" dash invalid 2>&1; echo "exit=$?")
assert_contains "dash invalid: shows usage" "Usage" "$output"

# ── Multi-session dashboard rendering (zsh) ──

# Create two fresh session cache files
printf '%s\n' "model=Opus 4.6" "ctx_pct=73" "cost=25.63" "rate_5h=8" "rate_7d=61" \
  "reset_5h=0" "reset_7d=0" "session_id=aaaaaaaa" \
  "worktree=main" "agent=" "cache_pct=42" "ppid=$$" "rate_7d_start=58" \
  > "$CLAUDII_CACHE_DIR/session-aaaaaaaa"

printf '%s\n' "model=Sonnet" "ctx_pct=42" "cost=1.20" "rate_5h=8" "rate_7d=61" \
  "reset_5h=0" "reset_7d=0" "session_id=bbbbbbbb" \
  "worktree=feat-xyz" "agent=" "cache_pct=" "ppid=$$" "rate_7d_start=" \
  > "$CLAUDII_CACHE_DIR/session-bbbbbbbb"

# Touch them to make them "fresh"
touch "$CLAUDII_CACHE_DIR/session-aaaaaaaa" "$CLAUDII_CACHE_DIR/session-bbbbbbbb"

# Also need status-models for RPROMPT
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CLAUDII_CACHE_DIR/status-models"

# Test dashboard rendering in zsh — auto mode should show when sessions exist
zsh_out=$(
  CLAUDII_CACHE_DIR="$CLAUDII_CACHE_DIR" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "dashboard: shows Opus 4.6 in PROMPT" "Opus 4.6" "$zsh_out"
assert_contains "dashboard: shows Sonnet in PROMPT" "Sonnet" "$zsh_out"
assert_contains "dashboard: shows context bar block" "█" "$zsh_out"

# Test dashboard: global line has rate limits
assert_contains "dashboard: global line has 5h" "5h:" "$zsh_out"

# Test dashboard: shows today session count
assert_contains "dashboard: shows session count" "session" "$zsh_out"

# Test dashboard: shows worktree context
assert_contains "dashboard: shows wt:main" "wt:main" "$zsh_out"
assert_contains "dashboard: shows wt:feat-xyz" "wt:feat-xyz" "$zsh_out"

# Test dashboard: shows cache hit ratio
assert_contains "dashboard: shows cache hit" "⚡42%" "$zsh_out"

# ── PID-check: stale PID should be excluded ──

# Create a session with a non-existent PID
printf '%s\n' "model=DeadModel" "ctx_pct=10" "cost=0.50" "rate_5h=5" "rate_7d=10" \
  "reset_5h=0" "reset_7d=0" "session_id=deadbeef" \
  "worktree=dead" "agent=" "cache_pct=" "ppid=999999" "rate_7d_start=" \
  > "$CLAUDII_CACHE_DIR/session-deadbeef"
touch "$CLAUDII_CACHE_DIR/session-deadbeef"

zsh_out=$(
  CLAUDII_CACHE_DIR="$CLAUDII_CACHE_DIR" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
# DeadModel should NOT appear (PID 999999 is almost certainly not running)
strip=$(echo "$zsh_out" | sed 's/%[FBfb]{[^}]*}//g')
dead_count=$(echo "$strip" | grep -c "DeadModel" || true)
assert_eq "PID check: dead session excluded from dashboard" "0" "$dead_count"

# ── Dashboard off mode: no dashboard lines ──

# Set dashboard to off
jq '.dashboard.enabled = "off"' "$CLAUDII_HOME/config/defaults.json" \
  > "$XDG_CONFIG_HOME/claudii/config.json"

zsh_off=$(
  CLAUDII_CACHE_DIR="$CLAUDII_CACHE_DIR" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
# When off, PROMPT should NOT contain model names from dashboard
strip_off=$(echo "$zsh_off" | sed 's/%[FBfb]{[^}]*}//g')
off_opus_count=$(echo "$strip_off" | grep -c "Opus 4.6" || true)
assert_eq "dashboard off: no Opus 4.6 in PROMPT" "0" "$off_opus_count"

# ── No active sessions: auto mode should not show dashboard ──
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
rm -f "$CLAUDII_CACHE_DIR"/session-*

zsh_empty=$(
  CLAUDII_CACHE_DIR="$CLAUDII_CACHE_DIR" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
strip_empty=$(echo "$zsh_empty" | sed 's/%[FBfb]{[^}]*}//g')
empty_5h=$(echo "$strip_empty" | grep -c "5h:" || true)
assert_eq "auto mode no sessions: no dashboard in PROMPT" "0" "$empty_5h"

# ── 7d-Delta: sessionline records rate_7d_start ──

_7d_cache="$(mktemp -d)"
output=$(echo '{"session_id":"delta7dtest","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":1.00},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":50}}}' | CLAUDII_CACHE_DIR="$_7d_cache" bash "$SL" 2>&1)
_7d_file="$_7d_cache/session-delta7dt"
assert_file_exists "7d-delta: session cache created" "$_7d_file"
_7d_content="$(cat "$_7d_file" 2>/dev/null)"
assert_contains "7d-delta: rate_7d_start written on first update" "rate_7d_start=50" "$_7d_content"

# Second update with higher rate_7d — start should NOT change
output=$(echo '{"session_id":"delta7dtest","model":{"display_name":"Opus"},"context_window":{"used_percentage":35,"total_input_tokens":6000,"total_output_tokens":1200,"context_window_size":200000},"cost":{"total_cost_usd":1.50},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":55}}}' | CLAUDII_CACHE_DIR="$_7d_cache" bash "$SL" 2>&1)
_7d_content2="$(cat "$_7d_file" 2>/dev/null)"
assert_contains "7d-delta: rate_7d_start preserved on subsequent update" "rate_7d_start=50" "$_7d_content2"

rm -rf "$_7d_cache"

# ── Truncation: COLUMNS controls segment visibility ──

# < 60: only model + context bar (no cost, no rates)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | COLUMNS=50 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "trunc <60: shows model" "Opus" "$strip"
assert_contains "trunc <60: shows context bar" "42%" "$strip"
assert_eq "trunc <60: no cost" "0" "$(echo "$strip" | grep -c '\$0.55')"
assert_eq "trunc <60: no 5h" "0" "$(echo "$strip" | grep -c '5h:')"
assert_eq "trunc <60: no tokens" "0" "$(echo "$strip" | grep -c '15.2K')"

# 60-80: + cost, no rates
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | COLUMNS=70 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "trunc 60-80: shows cost" "0.55" "$strip"
assert_eq "trunc 60-80: no 5h" "0" "$(echo "$strip" | grep -c '5h:')"
assert_eq "trunc 60-80: no tokens" "0" "$(echo "$strip" | grep -c '15.2K')"

# 80-100: + rates, no tokens/lines/duration
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | COLUMNS=90 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "trunc 80-100: shows 5h rate" "5h:" "$strip"
assert_contains "trunc 80-100: shows 7d rate" "7d:" "$strip"
assert_eq "trunc 80-100: no tokens" "0" "$(echo "$strip" | grep -c '15.2K')"

# > 100: everything
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | COLUMNS=120 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "trunc >100: shows tokens" "15.2K" "$strip"
assert_contains "trunc >100: shows lines" "+156" "$strip"
assert_contains "trunc >100: shows duration" "12m" "$strip"

# ── Cache fields: ppid and cache_pct written to session cache ──

_field_cache="$(mktemp -d)"
output=$(echo '{"session_id":"fieldtest1","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":7000,"cache_creation_input_tokens":0}},"cost":{"total_cost_usd":0.20}}' | CLAUDII_CACHE_DIR="$_field_cache" bash "$SL" 2>&1)
_field_file="$_field_cache/session-fieldtes"
_field_content="$(cat "$_field_file" 2>/dev/null)"
assert_contains "cache file has cache_pct field" "cache_pct=" "$_field_content"
assert_contains "cache file has ppid field" "ppid=" "$_field_content"
# cache_pct should be 7000 / (7000+10000) * 100 = 41%
assert_contains "cache_pct calculated correctly (41%)" "cache_pct=41" "$_field_content"

rm -rf "$_field_cache"

# ── Detail view (dash show) ──

# Recreate session files for detail view test
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
printf '%s\n' "model=Opus 4.6" "ctx_pct=73" "cost=25.63" "rate_5h=8" "rate_7d=61" \
  "reset_5h=0" "reset_7d=0" "session_id=aaaaaaaa" \
  "worktree=main" "agent=" "cache_pct=42" "ppid=$$" "rate_7d_start=58" \
  > "$CLAUDII_CACHE_DIR/session-aaaaaaaa"
touch "$CLAUDII_CACHE_DIR/session-aaaaaaaa"

output=$(bash "$CLI" dash show 2>&1)
assert_contains "dash show: shows Opus 4.6" "Opus 4.6" "$output"
assert_contains "dash show: shows context bar" "█" "$output"
assert_contains "dash show: shows cost" "25.63" "$output"
assert_contains "dash show: shows worktree" "wt:main" "$output"
assert_contains "dash show: shows cache hit" "⚡42%" "$output"
assert_contains "dash show: shows 7d delta" "+3%" "$output"
assert_contains "dash show: shows mode" "auto" "$output"

# ── No stdout leak from dashboard render (regression: _cost_fmt=, _cost_fmt_s=) ──

cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
printf '%s\n' "model=Sonnet 4.6" "ctx_pct=56" "cost=1.09" "rate_5h=4" "rate_7d=65" \
  "reset_5h=0" "reset_7d=0" "session_id=leaktest1" \
  "worktree=main" "agent=" "cache_pct=80" "ppid=$$" "rate_7d_start=63" \
  > "$CLAUDII_CACHE_DIR/session-leaktest1"
printf '%s\n' "model=Opus 4.6" "ctx_pct=46" "cost=11.66" "rate_5h=4" "rate_7d=65" \
  "reset_5h=0" "reset_7d=0" "session_id=leaktest2" \
  "worktree=work" "agent=" "cache_pct=58" "ppid=$$" "rate_7d_start=63" \
  > "$CLAUDII_CACHE_DIR/session-leaktest2"
touch "$CLAUDII_CACHE_DIR/session-leaktest1" "$CLAUDII_CACHE_DIR/session-leaktest2"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CLAUDII_CACHE_DIR/status-models"

# _claudii_statusline must print NOTHING to stdout — all output goes to $PROMPT
leaked=$(
  CLAUDII_CACHE_DIR="$CLAUDII_CACHE_DIR" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
  " 2>/dev/null
)
assert_eq "no stdout leak from dashboard render" "" "$leaked"
leak_cost=$(printf '%s' "$leaked" | grep -c "_cost_fmt=" || true)
assert_eq "no _cost_fmt= leak in stdout" "0" "$leak_cost"

# ── Cleanup ──
rm -rf "$DASH_TMP"
unset XDG_CONFIG_HOME CLAUDII_CACHE_DIR
