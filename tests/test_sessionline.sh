# touches: bin/claudii-cc-statusline
# test_sessionline.sh — in-session statusline rendering

SL="$CLAUDII_HOME/bin/claudii-cc-statusline"

_SL_TMPDIRS=()
# Isolate from the user's real config so tests never inherit ui.* / statusline.*
# settings (e.g. statusline.rate_display would change all rate-segment expectations).
_SL_ISOLATED_CFG=$(mktemp -d "${TMPDIR:-/tmp}/claudii-sl-cfg.XXXXXX")
_SL_TMPDIRS+=("$_SL_ISOLATED_CFG")
export XDG_CONFIG_HOME="$_SL_ISOLATED_CFG"
# Tests may run inside a Claude Code session that sets the auto-compact window —
# unset it so the context-bar asserts see the default 80% scale.
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
trap 'rm -rf "${_SL_TMPDIRS[@]}" 2>/dev/null' EXIT

# Full data (all fields)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000,"current_usage":{"cache_creation_input_tokens":8000,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | bash "$SL" 2>&1)
assert_contains "shows model name" "Opus" "$output"
assert_contains "shows context %" "52%" "$output"
assert_contains "shows input tokens" "15.2K" "$output"
assert_contains "shows output tokens" "4.5K" "$output"
assert_contains "shows 5h rate" "5h:" "$output"
assert_contains "shows 7d rate" "7d:" "$output"
assert_contains "shows lines added" "+156" "$output"
assert_contains "shows lines removed" "23" "$output"

# High context (90%+)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":95,"total_input_tokens":190000,"total_output_tokens":50000,"context_window_size":200000},"cost":{"total_cost_usd":2.10,"total_duration_ms":3600000}}' | bash "$SL" 2>&1)
assert_contains "high context shows 100%" "100%" "$output"
assert_contains "large tokens formatted" "190.0K" "$output"

# Million tokens
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":1500000,"total_output_tokens":300000,"context_window_size":200000},"cost":{"total_cost_usd":15.00,"total_duration_ms":120000}}' | bash "$SL" 2>&1)
assert_contains "million tokens formatted" "1.5M" "$output"

# Extended context window (1M)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":100000,"total_output_tokens":20000,"context_window_size":1000000},"cost":{"total_cost_usd":1.00,"total_duration_ms":300000}}' | bash "$SL" 2>&1)
assert_contains "1M context indicator" "1M" "$output"

# Minimal data (no rate limits, no lines, no duration)
output=$(echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":5,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' | bash "$SL" 2>&1)
assert_contains "minimal data shows model" "Haiku" "$output"

# duration segment — not in default layout; test via custom config
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["duration"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":732000}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "duration segment: 12m" "12m" "$output"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":2.10,"total_duration_ms":3600000}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "duration segment: 1h0m" "1h0m" "$output"

# cost segment — not in default layout; test via custom config
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["cost"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.55}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "cost segment shows value" "0.55" "$output"

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

# Effort mode — shown when effort.level in JSON is something other than "high"
output=$(echo '{"model":{"display_name":"Opus"},"effort":{"level":"max"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
assert_contains "effort mode max shown" "max" "$output"

output=$(echo '{"model":{"display_name":"Opus"},"effort":{"level":"medium"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
assert_contains "effort mode medium shown" "medium" "$output"

# Effort mode "high" — always shown (all effort levels are displayed)
output=$(echo '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "effort mode high shown" "high" "$strip"

# Effort mode xhigh + ultracode — high-end modes, shown like max/high
output=$(echo '{"model":{"display_name":"Opus"},"effort":{"level":"xhigh"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "effort mode xhigh shown" "xhigh" "$strip"

output=$(echo '{"model":{"display_name":"Opus"},"effort":{"level":"ultracode"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "effort mode ultracode shown" "ultracode" "$strip"

# thinking.enabled — ▲ shown in model segment when true
output=$(echo '{"model":{"display_name":"Opus"},"effort":{"level":"max"},"thinking":{"enabled":true},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "thinking enabled shows ▲" "▲" "$strip"

output=$(echo '{"model":{"display_name":"Opus"},"thinking":{"enabled":false},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.30,"total_duration_ms":30000}}' | bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "thinking disabled: no ▲" "0" "$(echo "$strip" | grep -c '▲')"

# Worktree/Agent — written to session cache file
mkdir -p "$CLAUDII_HOME/tmp"
_test_cache_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cache_dir")
output=$(echo '{"session_id":"testworktreeagent","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05},"worktree":{"name":"my-feature-branch","branch":"main"},"agent":{"name":"agent-42"}}' | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>&1)
_test_session_file="$_test_cache_dir/session-testwork"
assert_file_exists "worktree/agent: session cache file created" "$_test_session_file"
_cache_contents="$(cat "$_test_session_file" 2>/dev/null)"
assert_contains "session cache has worktree=" "worktree=my-feature-branch" "$_cache_contents"
assert_contains "session cache has agent=" "agent=agent-42" "$_cache_contents"

# Worktree segment rendered: name + ⎇ branch in output (via custom config with worktree segment)
mkdir -p "$CLAUDII_HOME/tmp"
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","worktree","agent"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"session_id":"testwt99","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05},"worktree":{"name":"feat-login","branch":"main"}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "worktree segment shows name" "feat-login" "$strip"
assert_contains "worktree segment shows branch" "⎇" "$strip"
assert_contains "worktree segment shows branch name" "main" "$strip"

# workspace.git_worktree fallback — shown when worktree.name absent (plain git worktree)
mkdir -p "$CLAUDII_HOME/tmp"
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","worktree"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"session_id":"testwsgwt1","model":{"display_name":"Sonnet"},"workspace":{"git_worktree":"feat-test"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "workspace.git_worktree fallback shown" "feat-test" "$strip"
assert_eq "workspace.git_worktree fallback: no branch arrow" "0" "$(echo "$strip" | grep -c '⎇')"

# ppid — written to session cache file so RPROMPT can detect dead sessions
_test_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir")
echo '{"session_id":"testppid123456","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>&1 >/dev/null
_test_session_file="$_test_cache_dir/session-testppid"
_cache_contents="$(cat "$_test_session_file" 2>/dev/null)"
assert_contains "session cache has ppid=" "ppid=" "$_cache_contents"
# ppid value must be a non-zero integer (the bash process that ran claudii-cc-statusline)
_ppid_val="$(echo "$_cache_contents" | grep '^ppid=' | cut -d= -f2)"
[[ "$_ppid_val" =~ ^[0-9]+$ ]] \
  && assert_eq "session cache ppid is a valid PID integer" "true" "true" \
  || assert_eq "session cache ppid is a valid PID integer" "true" "false (got: $_ppid_val)"

# Token order: input↑ must appear before output↓ in the rendered line
# (values from real session: 64.9K input, 121.1K output — order matters regardless of magnitude)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":47,"total_input_tokens":64900,"total_output_tokens":121100,"context_window_size":200000},"cost":{"total_cost_usd":12.53,"total_duration_ms":3600000},"rate_limits":{"five_hour":{"used_percentage":11},"seven_day":{"used_percentage":65}}}' | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
up_pos=$(echo "$strip" | grep -bo '↑' | head -1 | cut -d: -f1 || echo "9999")
down_pos=$(echo "$strip" | grep -bo '↓' | head -1 | cut -d: -f1 || echo "9999")
assert_contains "token input shown with ↑" "64.9K↑" "$strip"
assert_contains "token output shown with ↓" "121.1K↓" "$strip"
assert_eq "token order: ↑ (input) appears before ↓ (output)" "true" "$([ "${up_pos:-9999}" -lt "${down_pos:-9999}" ] && echo true || echo false)"

# Reset countdown in sessionline — must show "↺X[mhd]" when resets_at is set.
# ~90 min in the future must render as ↺1hXm. Exact minute is timing-sensitive
# (any 1s delay flips the bucket), so we only assert the 1h prefix + digit minutes.
_reset_ts=$(( $(date +%s) + 5460 ))
output=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":47,\"total_input_tokens\":64900,\"total_output_tokens\":121100,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":12.53,\"total_duration_ms\":3600000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":11,\"resets_at\":${_reset_ts}},\"seven_day\":{\"used_percentage\":65}}}" | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "sessionline shows reset countdown" "1" "$(echo "$strip" | grep -cE '↺[0-9]+[mhd]' || true)"
assert_eq "5h reset ~90min → shows ↺1hXm" "1" "$(echo "$strip" | grep -cE '↺1h[0-9]+m' || true)"

# Reset countdown color: green (\033[32m) when rate_5h >= 50% and < 5min remaining
_reset_soon=$(( $(date +%s) + 180 ))
output_soon=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":47,\"total_input_tokens\":64900,\"total_output_tokens\":121100,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":12.53,\"total_duration_ms\":3600000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":67,\"resets_at\":${_reset_soon}},\"seven_day\":{\"used_percentage\":65}}}" | COLUMNS=150 bash "$SL" 2>&1)
assert_eq "reset countdown < 5min + rate>=50%: green color code present" "1" "$(printf '%s' "$output_soon" | grep -c $'\033\[0;32m↺' || true)"

# Burn-ETA removed — "~Xmin" must NOT appear in output
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":47,"total_input_tokens":64900,"total_output_tokens":121100,"context_window_size":200000},"cost":{"total_cost_usd":12.53,"total_duration_ms":3600000},"rate_limits":{"five_hour":{"used_percentage":67},"seven_day":{"used_percentage":65}}}' | COLUMNS=150 bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "burn-ETA ~Xmin not shown" "0" "$(echo "$strip" | grep -cE '~[0-9]+min' || true)"

# 7d-Delta tracking — rate_7d_start persisted in cache; delta NOT rendered in sessionline output
_test_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir")
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

# burn_eta written to session cache (non-empty when rate > 0 and duration > 0)
_test_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir")
echo '{"session_id":"testburneta1","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":70},"seven_day":{"used_percentage":65}}}' \
  | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>/dev/null >/dev/null
_cache_be="$(cat "$_test_cache_dir/session-testburn" 2>/dev/null)"
assert_contains "burn_eta key present in session cache" "burn_eta=" "$_cache_be"
_burn_val="$(echo "$_cache_be" | grep '^burn_eta=' | cut -d= -f2)"
[[ "$_burn_val" =~ ^[0-9]+$ ]] \
  && assert_eq "burn_eta is a non-empty integer" "true" "true" \
  || assert_eq "burn_eta is a non-empty integer" "true" "false (got: $_burn_val)"

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

# Default output has exactly 5 non-empty lines (line 5 = claude-status — needs status-models cache)
_test_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir")
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$_test_cache_dir/status-models"
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000},"cost":{"total_cost_usd":0.55,"total_duration_ms":732000,"total_api_duration_ms":50000,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71.2}}}' | COLUMNS=80 CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>/dev/null)
_nonempty_lines=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^ ]' || true)
assert_eq "default output has exactly 5 non-empty lines" "5" "$_nonempty_lines"

# Single-line config (statusline.lines with 1 array) → 1 output line
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","context-bar","cost","rate-5h","rate-7d","tokens","lines-changed","duration"]]}}\n' \
  > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.20,"total_duration_ms":60000},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
_single_lines=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^ ]' || true)
assert_eq "single-line config produces 1 output line" "1" "$_single_lines"

# Empty segments skipped: worktree and agent absent when not in JSON input
output=$(echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":30000}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "worktree absent when not in JSON" "0" "$(echo "$strip" | grep -c '@' || true)"

# agent segment: available via custom config — agent.name shown as @name
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["agent"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Opus"},"agent":{"name":"orchestrate"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":30000}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "agent.name shown as @name via custom config" "@orchestrate" "$strip"

# agent segment falls back to session_name when agent.name absent (claudii agent launches use --name)
output=$(echo '{"model":{"display_name":"Opus"},"session_name":"omlx","context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":30000}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "session_name shown as @name fallback" "@omlx" "$strip"

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

# ── Tailscale segment reads the ~30s TTL cache (no per-render ifconfig fork) ──
# Deterministic: pre-seed $cache/vpnii-ts with a fresh epoch so the ifconfig
# probe is skipped entirely and the cached up/down value drives the segment.
_ts_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_ts_cfg_dir")
mkdir -p "$_ts_cfg_dir/claudii"
printf '{"statusline":{"lines":[["vpn"]]}}\n' > "$_ts_cfg_dir/claudii/config.json"
_ts_cache_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_ts_cache_dir")
_ts_json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":30000}}'

# Fresh cache, up=1 → ts shown (cache hit, ifconfig not consulted)
printf '%s 1\n' "$(date +%s)" > "$_ts_cache_dir/vpnii-ts"
output=$(echo "$_ts_json" | XDG_CONFIG_HOME="$_ts_cfg_dir" CLAUDII_CACHE_DIR="$_ts_cache_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "tailscale: fresh cache up=1 → ts shown" "ts" "$strip"

# Fresh cache, up=0 → ts hidden (cache hit, no probe)
printf '%s 0\n' "$(date +%s)" > "$_ts_cache_dir/vpnii-ts"
output=$(echo "$_ts_json" | XDG_CONFIG_HOME="$_ts_cfg_dir" CLAUDII_CACHE_DIR="$_ts_cache_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "tailscale: fresh cache up=0 → ts hidden" "ts" "$strip"

unset _ts_cfg_dir _ts_cache_dir _ts_json output strip

# No bc in the script
assert_eq "no bc subprocess in claudii-cc-statusline" "0" "$(grep -c '\bbc\b' "$CLAUDII_HOME/bin/claudii-cc-statusline" || true)"

# Regression: claude-status segment must render Opus + Sonnet + Haiku as
# *distinct* labels. Original bug used `declare -A`, which silently breaks
# on bash 3.2 (macOS /bin/bash) — every key resolved to arr[0], so all
# three slots rendered the last value ("Haiku"). Run via /bin/bash
# explicitly so the test catches future bash-3.2 regressions.
_test_cache_dir_b32="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir_b32")
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$_test_cache_dir_b32/status-models"
# Use a non-Opus/Sonnet/Haiku display name so the model segment doesn't
# collide with the claude-status labels we are asserting on.
_test_cfg_dir_b32="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir_b32")
mkdir -p "$_test_cfg_dir_b32/claudii"
printf '{"statusline":{"lines":[["claude-status"]]}}\n' > "$_test_cfg_dir_b32/claudii/config.json"
output=$(echo '{"model":{"display_name":"X"},"context_window":{"used_percentage":20,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.10,"total_duration_ms":30000}}' \
  | COLUMNS=120 CLAUDII_CACHE_DIR="$_test_cache_dir_b32" XDG_CONFIG_HOME="$_test_cfg_dir_b32" /bin/bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "bash 3.2: claude-status shows Opus exactly once"   "1" "$(echo "$strip" | grep -oE '\bOpus\b'   | wc -l | tr -d ' ')"
assert_eq "bash 3.2: claude-status shows Sonnet exactly once" "1" "$(echo "$strip" | grep -oE '\bSonnet\b' | wc -l | tr -d ' ')"
assert_eq "bash 3.2: claude-status shows Haiku exactly once"  "1" "$(echo "$strip" | grep -oE '\bHaiku\b'  | wc -l | tr -d ' ')"

# api-duration ratio: shown when both api_duration_ms and duration_ms are present
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":60000,"total_api_duration_ms":44000}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "api-duration ratio: shows api: label" "1" "$(echo "$strip" | grep -c 'api:' || true)"

# api-duration ratio: NOT shown when duration_ms is absent
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_api_duration_ms":44000}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "api-duration ratio absent without duration_ms: no (%)" "0" "$(echo "$strip" | grep -cE '\([0-9]+%\)' || true)"

# api-duration ratio: NOT shown when duration_ms is 0
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":0,"total_api_duration_ms":44000}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "api-duration ratio absent when duration_ms=0: no (%)" "0" "$(echo "$strip" | grep -cE '\([0-9]+%\)' || true)"

# api-duration ratio: capped — api_duration_ms > duration_ms produces no ratio (guard)
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":30000,"total_api_duration_ms":60000}}' \
  | bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "api-duration ratio guard: api > total → no ratio shown" "0" "$(echo "$strip" | grep -cE '\([0-9]+%\)' || true)"

# cache-create segment: ✎N shown when cache_creation_input_tokens > 0
mkdir -p "$CLAUDII_HOME/tmp"
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","cache-create"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":1200}},"cost":{"total_cost_usd":0.10}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "cache-create segment shows ✎" "✎" "$strip"
assert_contains "cache-create segment shows formatted tokens" "1.2K" "$strip"

# cache-create segment: NOT shown when cache_creation_input_tokens = 0
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","cache-create"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"cost":{"total_cost_usd":0.10}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cache-create absent when zero" "0" "$(echo "$strip" | grep -c '✎' || true)"

# exceeds_200k: >200k indicator shown when exceeds_200k_tokens = true
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["context-bar"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":80,"total_input_tokens":180000,"total_output_tokens":30000,"context_window_size":200000},"cost":{"total_cost_usd":1.00},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "exceeds_200k shows >200k" ">200k" "$strip"

# session-name segment: shown when session_name set
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","session-name"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01},"session_name":"my-feature"}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "session-name segment shows name" "my-feature" "$strip"

# dir segment — workspace.project_dir basename shown in default layout
mkdir -p "$CLAUDII_HOME/tmp"
_test_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","dir"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"workspace":{"project_dir":"/Users/alice/projects/my-app","current_dir":"/Users/alice/projects/my-app/src"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "dir segment shows project basename" "my-app" "$strip"
assert_contains "dir segment shows ⌂ symbol" "⌂" "$strip"

# dir segment — worktree.original_cwd takes precedence over project_dir
output=$(echo '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"/home/alice/work"},"worktree":{"original_cwd":"/home/alice/projects/feat-branch","name":"feat"},"context_window":{"used_percentage":5,"total_input_tokens":100,"total_output_tokens":20,"context_window_size":200000},"cost":{"total_cost_usd":0}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "dir segment uses worktree.original_cwd when set" "feat-branch" "$strip"

# _tok awk injection — malicious token string must not execute code
# `awk -v n="$n"` with numeric coercion (n+0) should sanitize, but regression-test anyway
_mal='1000; system("echo PWNED_TOK")'
output=$(jq -n --arg t "$_mal" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":$t,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | bash "$SL" 2>&1)
assert_not_contains "_tok awk injection: no PWNED in output" "PWNED_TOK" "$output"
assert_contains "_tok awk injection: model still renders" "Opus" "$output"

# omlx segment — reads gateii's data/agents/active.json (or env override)
# Empty when path missing or stale (>5 min old). Fresh entries render
# ⚡ task model age. Bench-prefixed task names are passed through verbatim.
_omlx_dir="$(mktemp -d "$CLAUDII_HOME/tmp/omlx-XXXXXX")"; _SL_TMPDIRS+=("$_omlx_dir")
_omlx_cfg="$_omlx_dir/cfg"; mkdir -p "$_omlx_cfg/claudii"
printf '{"statusline":{"lines":[["model","omlx"]],"omlx_active_path":"%s/active.json"}}\n' "$_omlx_dir" > "$_omlx_cfg/claudii/config.json"
_min_json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"context_window_size":200000}}'

# Missing file → no segment
CLAUDII_OMLX_ACTIVE=/nonexistent/x.json output=$(echo "$_min_json" | bash "$SL" 2>&1)
assert_not_contains "omlx: no file → no ⚡" "⚡" "$output"

# Stale file (>5 min) → no segment
_old=$(( $(date +%s) - 1000 ))
printf '{"task":"commit-msg","model":"Qwen3.5-9B-MLX-4bit","started_epoch":%s}\n' "$_old" > "$_omlx_dir/active.json"
output=$(echo "$_min_json" | XDG_CONFIG_HOME="$_omlx_cfg" bash "$SL" 2>&1)
assert_not_contains "omlx: stale file → no ⚡" "⚡" "$output"

# Fresh file → ⚡ + task + short model + age
_now_ts=$(date +%s)
printf '{"task":"commit-msg","model":"Qwen3.5-9B-MLX-4bit","started_epoch":%s}\n' "$_now_ts" > "$_omlx_dir/active.json"
output=$(echo "$_min_json" | XDG_CONFIG_HOME="$_omlx_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "omlx: fresh → ⚡"           "⚡"          "$strip"
assert_contains "omlx: task name shown"      "commit-msg" "$strip"
assert_contains "omlx: model name compacted" "Qwen3.5-9B" "$strip"
assert_not_contains "omlx: MLX-4bit suffix stripped" "MLX-4bit" "$strip"

# Bench-prefixed task → passed through
printf '{"task":"bench:summarize-file (3/3)","model":"gemma-4-e2b-it-4bit","started_epoch":%s}\n' "$_now_ts" > "$_omlx_dir/active.json"
output=$(echo "$_min_json" | XDG_CONFIG_HOME="$_omlx_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "omlx: bench prefix passes through" "bench:summarize-file" "$strip"
assert_contains "omlx: gemma-it-4bit suffix stripped" "gemma-4-e2b" "$strip"
assert_not_contains "omlx: gemma -it-4bit removed"   "-it-4bit"     "$strip"

# github segment — workspace.repo.{owner,name,pr_number} from CC 2.1.145+
_gh_cfg="$(mktemp -d "$CLAUDII_HOME/tmp/gh-XXXXXX")"; _SL_TMPDIRS+=("$_gh_cfg")
mkdir -p "$_gh_cfg/claudii"
printf '{"statusline":{"lines":[["model","github"]]}}\n' > "$_gh_cfg/claudii/config.json"
_gh_base='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"context_window_size":200000}}'

# Repo + PR: shows ◆ owner/name #pr_number
_j=$(jq -cn --argjson w '{"repo":{"host":"github.com","owner":"bmmmm","name":"claudii","pr_number":42}}' '{"model":{"display_name":"Opus"},"workspace":$w,"context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "github: shows owner/name"  "bmmmm/claudii" "$strip"
assert_contains "github: shows ◆ marker"    "◆"             "$strip"
assert_contains "github: shows #pr_number"  "#42"           "$strip"

# Repo without PR: still shows owner/name but no #
_j=$(jq -cn --argjson w '{"repo":{"host":"github.com","owner":"bmmmm","name":"claudii"}}' '{"model":{"display_name":"Opus"},"workspace":$w,"context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains     "github: owner/name without PR" "bmmmm/claudii" "$strip"
assert_not_contains "github: no # when pr absent"   "#"             "$strip"

# Repo block missing entirely: segment omitted, model still rendered
output=$(echo "$_gh_base" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains     "github: model still shows when repo absent" "Opus" "$strip"
assert_not_contains "github: no ◆ marker when repo absent"       "◆"    "$strip"

# Malformed: owner without name → segment omitted (require both)
_j=$(jq -cn --argjson w '{"repo":{"owner":"bmmmm"}}' '{"model":{"display_name":"Opus"},"workspace":$w,"context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "github: owner alone → no ◆"     "◆"      "$strip"
assert_not_contains "github: owner alone → no slash" "bmmmm/" "$strip"

# ── Pace tri-state segment tests ───────────────────────────────────────────────
_pace_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_pace_cfg_dir")
mkdir -p "$_pace_cfg_dir/claudii"
printf '{"statusline":{"lines":[["pace"]]}}\n' > "$_pace_cfg_dir/claudii/config.json"

# ahead: session 30min, linear=10%, actual=5% → 5 < 10×0.85=8.5 → ahead (↑)
# 30min = 1800000ms; linear = 30/300*100 = 10%; rate_5h=5% → 5 < 8.5 → ahead
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":10}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "pace ahead: ↑ shown" "↑" "$strip"

# behind: session 30min, linear=10%, actual=20% → 20 > 10×1.15=11.5 → behind (↓)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":30}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "pace behind: ↓ shown" "↓" "$strip"

# on_pace: session 30min, linear=10%, actual=10% → exactly on-pace (=)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "pace on_pace: = shown" "=" "$strip"

# no data: session < 3min → pace segment empty (below gate)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":60000},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "pace: no glyph when session < 3min" "↑" "$strip"
assert_not_contains "pace: no ↓ when session < 3min"     "↓" "$strip"

# pace persisted in session cache file
_pace_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_pace_cache_dir")
echo '{"session_id":"testpace999","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":10}}}' \
  | CLAUDII_CACHE_DIR="$_pace_cache_dir" bash "$SL" 2>/dev/null >/dev/null
_cache_pace="$(cat "$_pace_cache_dir/session-testpace" 2>/dev/null)"
assert_contains "pace=ahead written to session cache" "pace=ahead" "$_cache_pace"

# ── Cron segment tests ────────────────────────────────────────────────────────
# cron segment: renders ⏰ <relative> when next_cron_at is in the future
# session_id "slcrontest1" → first 8 chars = "slcrontest"[:8] = "slcrontest"
# Actually "slcrontest1"[0:8] = "slcronte" — cache file = session-slcronte
_cron_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_cron_cfg_dir")
mkdir -p "$_cron_cfg_dir/claudii"
printf '{"statusline":{"lines":[["cron"]]}}\n' > "$_cron_cfg_dir/claudii/config.json"
_cron_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_cron_cache_dir")
# Pre-seed session cache with a future next_cron_at (2 hours from now).
# Must stay safely >1h: an exact +3600 raced the render clock — if the wall-clock
# second ticked between this seed and the statusline's own `date +%s`, the delta
# fell to 3599s and the unit flipped from "h" to "59m", flaking the "(h)" assert
# below on CI. +7200 leaves a full hour of slack so a tick can't cross the bound.
# session_id "slcr1111" → 8 chars = "slcr1111" → cache file = session-slcr1111
_cron_future=$(( $(date +%s) + 7200 ))
printf 'model=Sonnet\nnext_cron_at=%s\n' "$_cron_future" > "$_cron_cache_dir/session-slcr1111"
output=$(echo '{"session_id":"slcr1111xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | CLAUDII_CACHE_DIR="$_cron_cache_dir" XDG_CONFIG_HOME="$_cron_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "cron segment: ⏰ shown when next_cron_at in future" "⏰" "$strip"
assert_contains "cron segment: time unit shown (h)" "h" "$strip"

# cron segment: omitted when next_cron_at is in the past
# session_id "slcr2222xxxx" → 8 chars = "slcr2222" → cache file = session-slcr2222
_cron_cache_dir2="$(mktemp -d)"; _SL_TMPDIRS+=("$_cron_cache_dir2")
_cron_past=$(( $(date +%s) - 300 ))
printf 'model=Sonnet\nnext_cron_at=%s\n' "$_cron_past" > "$_cron_cache_dir2/session-slcr2222"
output=$(echo '{"session_id":"slcr2222xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | CLAUDII_CACHE_DIR="$_cron_cache_dir2" XDG_CONFIG_HOME="$_cron_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cron segment: omitted when next_cron_at in past" "0" "$(echo "$strip" | grep -c '⏰' || true)"

# cron segment: omitted when next_cron_at missing from cache
# session_id "slcr3333xxxx" → 8 chars = "slcr3333" → cache file = session-slcr3333
_cron_cache_dir3="$(mktemp -d)"; _SL_TMPDIRS+=("$_cron_cache_dir3")
printf 'model=Sonnet\n' > "$_cron_cache_dir3/session-slcr3333"
output=$(echo '{"session_id":"slcr3333xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | CLAUDII_CACHE_DIR="$_cron_cache_dir3" XDG_CONFIG_HOME="$_cron_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cron segment: omitted when next_cron_at missing" "0" "$(echo "$strip" | grep -c '⏰' || true)"

# cron segment: cc-statusline preserves next_cron_at from stop-hook on cache rewrite
# session_id "slcr4444xxxx" → 8 chars = "slcr4444" → cache file = session-slcr4444
_cron_preserve_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_cron_preserve_cache")
_cron_future_p=$(( $(date +%s) + 7200 ))
printf 'model=Sonnet\nnext_cron_at=%s\nbg_tasks=1\n' "$_cron_future_p" \
  > "$_cron_preserve_cache/session-slcr4444"
echo '{"session_id":"slcr4444xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":20,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' \
  | CLAUDII_CACHE_DIR="$_cron_preserve_cache" bash "$SL" 2>/dev/null >/dev/null
_preserved="$(cat "$_cron_preserve_cache/session-slcr4444" 2>/dev/null)"
assert_contains "cron: cc-statusline preserves next_cron_at on rewrite" "next_cron_at=${_cron_future_p}" "$_preserved"
assert_contains "cron: cc-statusline preserves bg_tasks on rewrite" "bg_tasks=1" "$_preserved"

# ── bg-tasks segment tests ────────────────────────────────────────────────────
# bg-tasks segment: renders ⚙ Nbg when bg_tasks >= 1 in cache
_bgt_cfg_dir="$(mktemp -d "$CLAUDII_HOME/tmp/XXXXXX")"; _SL_TMPDIRS+=("$_bgt_cfg_dir")
mkdir -p "$_bgt_cfg_dir/claudii"
printf '{"statusline":{"lines":[["bg-tasks"]]}}\n' > "$_bgt_cfg_dir/claudii/config.json"
_bgt_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_bgt_cache_dir")
# Pre-seed cache with bg_tasks=2
printf 'model=Sonnet\nbg_tasks=2\n' > "$_bgt_cache_dir/session-bgt11111"
output=$(echo '{"session_id":"bgt11111xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | CLAUDII_CACHE_DIR="$_bgt_cache_dir" XDG_CONFIG_HOME="$_bgt_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "bg-tasks segment: ⚙ shown when bg_tasks=2" "⚙" "$strip"
assert_contains "bg-tasks segment: count shown (2bg)" "2bg" "$strip"

# bg-tasks segment: omitted when bg_tasks=0
_bgt_cache_dir2="$(mktemp -d)"; _SL_TMPDIRS+=("$_bgt_cache_dir2")
printf 'model=Sonnet\nbg_tasks=0\n' > "$_bgt_cache_dir2/session-bgt22222"
output=$(echo '{"session_id":"bgt22222xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | CLAUDII_CACHE_DIR="$_bgt_cache_dir2" XDG_CONFIG_HOME="$_bgt_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "bg-tasks segment: omitted when bg_tasks=0" "0" "$(echo "$strip" | grep -c '⚙' || true)"

# bg-tasks segment: omitted when bg_tasks absent from cache
_bgt_cache_dir3="$(mktemp -d)"; _SL_TMPDIRS+=("$_bgt_cache_dir3")
printf 'model=Sonnet\n' > "$_bgt_cache_dir3/session-bgt33333"
output=$(echo '{"session_id":"bgt33333xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | CLAUDII_CACHE_DIR="$_bgt_cache_dir3" XDG_CONFIG_HOME="$_bgt_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "bg-tasks segment: omitted when bg_tasks absent" "0" "$(echo "$strip" | grep -c '⚙' || true)"

# ── reset countdown color: ≥24h must render dim, not green ───────────────────
# Regression: _fmt_reset left `local _m` unassigned in the ≥24h branch, so the
# color ladder's `(( _m < 5 ))` saw 0 and painted multi-day resets green
# whenever used% was ≥50.
_rst_epoch=$(( $(date +%s) + 200000 ))   # ~2d7h out
output=$(echo '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":60,"resets_at":'"$_rst_epoch"'}}}' \
  | bash "$SL" 2>&1)
assert_contains "reset >24h at 60% used: dim color (not green)" $'\033[2m↺2d' "$output"
unset _rst_epoch

# ── insomnii env forwarding: explicit false survives, corrupt config heals ───
# Regression 1: `.statusline.shame // true` swallowed an explicit false (jq
# treats false as falsy) — opt-out was impossible.
# Regression 2: a corrupt config.json made the jq fail and the read blanked
# the pre-seeded "true" defaults — empty values were forwarded to cc-insomnii.
_ins_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_ins_dir")
mkdir -p "$_ins_dir/bin" "$_ins_dir/cfg/claudii"
cat > "$_ins_dir/bin/cc-insomnii" <<'EOF'
#\!/bin/bash
printf 'shame=%s motivation=%s rainbow=%s\n' \
  "$CC_INSOMNII_SHAME" "$CC_INSOMNII_MOTIVATION" "$CC_INSOMNII_RAINBOW" \
  > "$CLAUDII_TEST_INSOMNII_OUT"
EOF
chmod +x "$_ins_dir/bin/cc-insomnii"

printf '{"statusline":{"shame":false}}\n' > "$_ins_dir/cfg/claudii/config.json"
echo '{"model":{"display_name":"Opus"}}' \
  | CLAUDII_TEST_INSOMNII_OUT="$_ins_dir/env.out" PATH="$_ins_dir/bin:$PATH" \
    XDG_CONFIG_HOME="$_ins_dir/cfg" bash "$SL" >/dev/null 2>&1
_ins_env=$(cat "$_ins_dir/env.out" 2>/dev/null)
assert_contains "insomnii env: explicit shame=false forwarded" "shame=false" "$_ins_env"
assert_contains "insomnii env: motivation defaults to true"    "motivation=true" "$_ins_env"

printf 'NOT JSON\n' > "$_ins_dir/cfg/claudii/config.json"
rm -f "$_ins_dir/env.out"
echo '{"model":{"display_name":"Opus"}}' \
  | CLAUDII_TEST_INSOMNII_OUT="$_ins_dir/env.out" PATH="$_ins_dir/bin:$PATH" \
    XDG_CONFIG_HOME="$_ins_dir/cfg" bash "$SL" >/dev/null 2>&1
_ins_env=$(cat "$_ins_dir/env.out" 2>/dev/null)
assert_contains "insomnii env: corrupt config falls back to shame=true" "shame=true" "$_ins_env"
assert_contains "insomnii env: corrupt config falls back to rainbow=true" "rainbow=true" "$_ins_env"
unset _ins_dir _ins_env

# ── Auto-compact aware context bar (CLAUDE_CODE_AUTO_COMPACT_WINDOW) ─────────
# Default (unset, see top of file): 42% raw → 42*100/80 = 52%.
_ac_json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":40,"total_input_tokens":1000,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.10}}'

# Fraction form: 0.9 → scale 90 → 40*100/90 = 44%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=0.9 bash "$SL" 2>&1)
assert_contains "auto-compact fraction 0.9 scales bar" "44%" "$output"

# Token-count form: 100000 of 200000 → fraction 0.5 → 40*100/50 = 80%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000 bash "$SL" 2>&1)
assert_contains "auto-compact token count scales bar" "80%" "$output"

# Garbage value → default 80% scale → 40*100/80 = 50%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=banana bash "$SL" 2>&1)
assert_contains "auto-compact garbage falls back to 80" "50%" "$output"

# Clamp: fraction 0.2 clamps to 0.5 → 40*100/50 = 80%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=0.2 bash "$SL" 2>&1)
assert_contains "auto-compact low fraction clamps to 0.5" "80%" "$output"

# Token count without window size → default 80% scale → 50%
_ac_nown='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":40,"total_input_tokens":1000,"total_output_tokens":100},"cost":{"total_cost_usd":0.10}}'
output=$(echo "$_ac_nown" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000 bash "$SL" 2>&1)
assert_contains "auto-compact token count w/o window size falls back" "50%" "$output"
unset _ac_json _ac_nown

# ── Compaction counter (context-usage collapse detection) ────────────────────
_cp_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_cp_cache")
_cp_cfg="$(mktemp -d)";   _SL_TMPDIRS+=("$_cp_cfg")
mkdir -p "$_cp_cfg/claudii"
printf '{"statusline":{"lines":[["model","compactions"]]}}\n' > "$_cp_cfg/claudii/config.json"
_cp_json() { # args: used_percentage
  printf '{"model":{"display_name":"Opus"},"session_id":"compactsess01","context_window":{"used_percentage":%s,"total_input_tokens":1000,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.10}}' "$1"
}

# Render 1: high context — counter starts at 0, segment hidden
output=$(_cp_json 85 | CLAUDII_CACHE_DIR="$_cp_cache" XDG_CONFIG_HOME="$_cp_cfg" bash "$SL" 2>&1)
_cp_state=$(cat "$_cp_cache/session-compacts" 2>/dev/null)
assert_contains "compactions: last_ctx_pct cached" "last_ctx_pct=85" "$_cp_state"
assert_contains "compactions: counter starts 0" "compactions=0" "$_cp_state"
if [[ "$output" == *"♻"* ]]; then
  assert_eq "compactions: segment hidden at 0" "no-glyph" "glyph-present"
else
  assert_eq "compactions: segment hidden at 0" "no-glyph" "no-glyph"
fi

# Render 2: context collapses 85 → 20 → counter increments, segment renders
output=$(_cp_json 20 | CLAUDII_CACHE_DIR="$_cp_cache" XDG_CONFIG_HOME="$_cp_cfg" bash "$SL" 2>&1)
_cp_state=$(cat "$_cp_cache/session-compacts" 2>/dev/null)
assert_contains "compactions: collapse detected" "compactions=1" "$_cp_state"
assert_contains "compactions: segment renders count" "♻1" "$output"

# Render 3: small drop (20 → 15) — no increment
output=$(_cp_json 15 | CLAUDII_CACHE_DIR="$_cp_cache" XDG_CONFIG_HOME="$_cp_cfg" bash "$SL" 2>&1)
_cp_state=$(cat "$_cp_cache/session-compacts" 2>/dev/null)
assert_contains "compactions: small drop ignored" "compactions=1" "$_cp_state"

# Render 4: climb back up then collapse again → counter 2
_cp_json 70 | CLAUDII_CACHE_DIR="$_cp_cache" XDG_CONFIG_HOME="$_cp_cfg" bash "$SL" >/dev/null 2>&1
output=$(_cp_json 12 | CLAUDII_CACHE_DIR="$_cp_cache" XDG_CONFIG_HOME="$_cp_cfg" bash "$SL" 2>&1)
_cp_state=$(cat "$_cp_cache/session-compacts" 2>/dev/null)
assert_contains "compactions: second collapse counted" "compactions=2" "$_cp_state"
assert_contains "compactions: segment shows 2" "♻2" "$output"
unset _cp_cache _cp_cfg _cp_state
unset -f _cp_json
