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
assert_contains "shows context %" "50%" "$output"
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

# Extended context window (1M) — the constant "1M" window label is gone: it was
# a per-model constant that never told you anything that changed.
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":100000,"total_output_tokens":20000,"context_window_size":1000000},"cost":{"total_cost_usd":1.00,"total_duration_ms":300000}}' | bash "$SL" 2>&1)
assert_eq "1M window label dropped" "0" "$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '1M' || true)"

# Minimal data (no rate limits, no lines, no duration)
output=$(echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":5,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' | bash "$SL" 2>&1)
assert_contains "minimal data shows model" "Haiku" "$output"

# duration segment — not in default layout; test via custom config
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["duration"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01,"total_duration_ms":732000}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "duration segment: 12m" "12m" "$output"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":2.10,"total_duration_ms":3600000}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "duration segment: 1h0m" "1h0m" "$output"

# cost segment — not in default layout; test via custom config
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["cost"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.55}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "cost segment shows value" "0.55" "$output"

# Regression: the cost segment formats $cost via printf '%.2f'. A bare
# "LC_ALL=C printf" is inert on the printf BUILTIN under macOS /bin/bash 3.2 —
# a comma locale makes the builtin reject the dot input ("invalid number") and
# fall back to "$0,00"; the fix routes through external printf (env LC_ALL=C
# printf). Run via /bin/bash explicitly
# under a comma locale so a revert to the builtin form is caught here, not only
# on a German user's machine. Guarded on the locale being installed.
_have_de_sl=$(locale -a 2>/dev/null || true)
if [[ "$_have_de_sl" == *de_DE.UTF-8* || "$_have_de_sl" == *de_DE.utf8* ]]; then
  output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.55}}' \
    | LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 XDG_CONFIG_HOME="$_test_cfg_dir" /bin/bash "$SL" 2>/dev/null)
  assert_contains    "cost segment: dot decimal on /bin/bash 3.2 + de_DE"  "0.55" "$output"
  assert_not_contains "cost segment: no comma-truncated 0,00 on /bin/bash 3.2 + de_DE" "0,00" "$output"
fi
unset _have_de_sl

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
assert_contains "cache hit shows percentage" "50%" "$output"

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
mkdir -p "$CLAUDII_TEST_TMP"
_test_cache_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cache_dir")
output=$(echo '{"session_id":"testworktreeagent","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05},"worktree":{"name":"my-feature-branch","branch":"main"},"agent":{"name":"agent-42"}}' | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" 2>&1)
_test_session_file="$_test_cache_dir/session-testwork"
assert_file_exists "worktree/agent: session cache file created" "$_test_session_file"
_cache_contents="$(cat "$_test_session_file" 2>/dev/null)"
assert_contains "session cache has worktree=" "worktree=my-feature-branch" "$_cache_contents"
assert_contains "session cache has agent=" "agent=agent-42" "$_cache_contents"
# tok= = cumulative input+output (1000 + 200) — read by the token-first dashboard / se.
assert_contains "session cache has tok= (input+output)" "tok=1200" "$_cache_contents"

# Session totals: total_input_tokens/total_output_tokens are the LAST request's
# usage (CC 2.1.330+), so the statusline sums them one request at a time.
_tk_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_tk_dir")
_tk() {  # <total_in> <cache_read> <out>
  printf '{"session_id":"toksum-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":%s,"total_output_tokens":%s,"context_window_size":200000,"current_usage":{"input_tokens":10,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0,"output_tokens":%s}},"cost":{"total_cost_usd":0.05}}' "$1" "$3" "$2" "$3" \
    | CLAUDII_CACHE_DIR="$_tk_dir" bash "$SL" 2>/dev/null
}
_tk_get() { grep "^$1=" "$_tk_dir/session-toksum-0" | cut -d= -f2; }
_tk 50000 40000 300 >/dev/null
assert_eq "tok sum: first request seeds the totals" "50300" "$(_tk_get tok)"
_tk 50000 40000 300 >/dev/null
assert_eq "tok sum: an idle re-render of the same request adds nothing" "50300" "$(_tk_get tok)"
_tk 50000 40000 900 >/dev/null
assert_eq "tok sum: rising output of the same request replaces its share" "50900" "$(_tk_get tok)"
_tk_out=$(_tk 60000 50000 200 | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "tok sum: a new request adds its input and output" "110000:1100" "$(_tk_get tok_in):$(_tk_get tok_out)"
assert_contains "tok sum: tokens segment shows the session input total" "110.0K↑" "$_tk_out"
assert_contains "tok sum: history row carries the running totals" $'\t110000\t1100\t' \
  "$(tail -1 "$_tk_dir"/history-*.tsv)"
unset -f _tk _tk_get; unset _tk_out

# Worktree segment rendered: name + ⎇ branch in output (via custom config with worktree segment)
mkdir -p "$CLAUDII_TEST_TMP"
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","worktree","agent"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"session_id":"testwt99","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05},"worktree":{"name":"feat-login","branch":"main"}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "worktree segment shows name" "feat-login" "$strip"
assert_contains "worktree segment shows branch" "⎇" "$strip"
assert_contains "worktree segment shows branch name" "main" "$strip"

# workspace.git_worktree fallback — shown when worktree.name absent (plain git worktree)
mkdir -p "$CLAUDII_TEST_TMP"
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","worktree"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"session_id":"testwsgwt1","model":{"display_name":"Sonnet"},"workspace":{"git_worktree":"feat-test"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "workspace.git_worktree fallback shown" "feat-test" "$strip"
assert_eq "workspace.git_worktree fallback: no branch arrow" "0" "$(echo "$strip" | grep -c '⎇')"

# ppid — written to session cache file so RPROMPT can detect dead sessions
_test_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir")
echo '{"session_id":"testppid123456","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" >/dev/null 2>&1
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

# Reset text is the shared _fmt_rel: whole minutes rounded down, "<1m" in the
# last minute. The old local formatter rounded below 1h only — 59m40s read
# "60m", and the last 30 s showed no countdown at all.
_rst_json() { printf '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":%s}}}' "$1"; }
strip=$(_rst_json $(( $(date +%s) + 3580 )) | bash "$SL" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "reset 59m40s → ↺59m (rounded down)" "↺59m" "$strip"
assert_not_contains "reset 59m40s → never ↺60m" "↺60m" "$strip"
strip=$(_rst_json $(( $(date +%s) + 20 )) | bash "$SL" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "reset in the last minute → ↺<1m" "↺<1m" "$strip"
unset -f _rst_json

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

# delta-5h/7d baselines restart with the window: a rollover is a new window,
# not a −N% delta, and an unreadable cached baseline must not reach $(( )).
_dl_dir="$(mktemp -d "$CLAUDII_TEST_TMP/dl-XXXXXX")"; _SL_TMPDIRS+=("$_dl_dir")
mkdir -p "$_dl_dir/cfg/claudii" "$_dl_dir/cache"
printf '{"statusline":{"lines":[["delta-5h","delta-7d"]]}}\n' > "$_dl_dir/cfg/claudii/config.json"
_dl() {  # session 5h% 5h-reset 7d% 7d-reset → rendered line (colors stripped); stderr to $_dl_dir/err
  printf '{"session_id":"%s","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$@" \
    | XDG_CONFIG_HOME="$_dl_dir/cfg" CLAUDII_CACHE_DIR="$_dl_dir/cache" bash "$SL" 2>"$_dl_dir/err" \
    | sed 's/\x1b\[[0-9;]*m//g'
}
_dl_r5=$(( $(date +%s) + 9000 )); _dl_r7=$(( $(date +%s) + 300000 ))
_dl deltawin-0001 20 "$_dl_r5" 40 "$_dl_r7" > /dev/null
assert_eq "delta: growth inside the window shows" "Δ5h:+10% │ Δ7d:+2%" \
  "$(_dl deltawin-0001 30 "$_dl_r5" 42 "$_dl_r7" | sed 's/ *$//')"
assert_eq "delta: a 5h rollover restarts the baseline (no −25%)" "Δ7d:+3%" \
  "$(_dl deltawin-0001 5 $(( _dl_r5 + 18000 )) 43 "$_dl_r7" | sed 's/ *$//')"
assert_contains "delta: the new 5h baseline is cached" "rate_5h_start=5" "$(cat "$_dl_dir/cache/session-deltawin")"
assert_eq "delta: growth counts from the new window" "Δ5h:+4% │ Δ7d:+3%" \
  "$(_dl deltawin-0001 9 $(( _dl_r5 + 18000 )) 43 "$_dl_r7" | sed 's/ *$//')"
# A cached reset already in the past is a rollover too (payload without a new reset yet).
printf 'reset_5h=%s\nrate_5h_start=50\nrate_7d_start=40\nreset_7d=%s\n' "$(( $(date +%s) - 100 ))" "$_dl_r7" \
  > "$_dl_dir/cache/session-deltapas"
assert_eq "delta: a passed cached reset restarts the baseline" "Δ7d:+1%" \
  "$(_dl deltapas-0001 3 null 41 "$_dl_r7" | sed 's/ *$//')"
# Garbage baseline: no arithmetic error, baseline re-seeded.
printf 'rate_5h_start=abc\nreset_5h=%s\nrate_7d_start=4x\nreset_7d=%s\n' "$_dl_r5" "$_dl_r7" > "$_dl_dir/cache/session-deltagar"
_dl deltagar-0001 12 "$_dl_r5" 30 "$_dl_r7" > /dev/null
assert_eq "delta: a garbage baseline writes nothing to stderr" "" "$(cat "$_dl_dir/err")"
assert_contains "delta: a garbage baseline is re-seeded" "rate_5h_start=12" "$(cat "$_dl_dir/cache/session-deltagar")"
unset -f _dl; unset _dl_dir _dl_r5 _dl_r7

# burn_eta / pace run on the 5h window's clock (account-wide limit), not on the
# session's duration: elapsed = 18000 − (resets_at − now).
_test_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir")
_be_json() {  # session-id duration-ms 5h-used% [resets_at]
  local _rl='{"used_percentage":'"$3"'}'
  [[ -n "${4:-}" ]] && _rl='{"used_percentage":'"$3"',"resets_at":'"$4"'}'
  printf '{"session_id":"%s","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":%s},"rate_limits":{"five_hour":%s,"seven_day":{"used_percentage":65}}}' "$1" "$2" "$_rl"
}
_be_key() { grep "^$2=" "$_test_cache_dir/session-${1:0:8}" 2>/dev/null | cut -d= -f2; }
# 30 min into the window at 70%: (100 − 70) / (70 / 30) = 12.9 → 13 min.
_be_json testburneta1 1800000 70 $(( $(date +%s) + 16200 )) | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" >/dev/null 2>&1
assert_eq "burn_eta: minutes to the limit at the window's average rate" "13" "$(_be_key testburneta1 burn_eta)"
assert_eq "burn_eta: 70% after 30 of 300 min is behind linear" "behind" "$(_be_key testburneta1 pace)"
# The audit probe: a 4-minute session, 60% used, reset in 1 h. The window is
# 4 h old, so the limit is not near (160 min > 60 min left: no ETA) and 60% is
# under the linear 80% (ahead) — dividing by the session's 4 min said "ETA:3m",
# "behind".
_be_json testburneta2 240000 60 $(( $(date +%s) + 3600 )) | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" >/dev/null 2>&1
assert_eq "burn_eta: an ETA past the reset is dropped" "" "$(_be_key testburneta2 burn_eta)"
assert_eq "burn_eta: pace counts the window's elapsed time, not the session's" "ahead" "$(_be_key testburneta2 pace)"
_be_json testburneta3 1800000 70 | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" >/dev/null 2>&1
assert_eq "burn_eta: no resets_at → no ETA" "" "$(_be_key testburneta3 burn_eta)"
assert_eq "burn_eta: no resets_at → no pace" "" "$(_be_key testburneta3 pace)"
_be_json testburneta4 1800000 70 $(( $(date +%s) - 60 )) | CLAUDII_CACHE_DIR="$_test_cache_dir" bash "$SL" >/dev/null 2>&1
assert_eq "burn_eta: a reset already past → no ETA" "" "$(_be_key testburneta4 burn_eta)"
unset -f _be_json _be_key

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
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
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
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
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

# burn-eta visible: 10 min into the 5h window at 80% → ETA appears on line 2
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":70,"total_input_tokens":50000,"total_output_tokens":10000,"context_window_size":200000},"cost":{"total_cost_usd":2.00,"total_duration_ms":600000},"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":'"$(( $(date +%s) + 17400 ))"'},"seven_day":{"used_percentage":60}}}' \
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
# Deterministic: pre-seed $cache/vpnii-ts with a
# fresh epoch so the ifconfig probe is skipped entirely and the cached
# up/down value drives the segment.
_ts_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ts_cfg_dir")
mkdir -p "$_ts_cfg_dir/claudii"
printf '{"statusline":{"lines":[["tailscale"]]}}\n' > "$_ts_cfg_dir/claudii/config.json"
_ts_cache_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ts_cache_dir")
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

# Layout gate: with no `tailscale` in the layout and no cache to read, the
# ifconfig probe must not run at all. The 30s cache bounded how often it ran,
# never whether — a layout without the segment still paid the fork on every
# expiry. Proven by absence of the cache file the probe writes: if it had run,
# vpnii-ts would exist.
_ts_gate_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ts_gate_cfg")
mkdir -p "$_ts_gate_cfg/claudii"
printf '{"statusline":{"lines":[["model"]]}}\n' > "$_ts_gate_cfg/claudii/config.json"
_ts_gate_cache="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ts_gate_cache")
echo "$_ts_json" | XDG_CONFIG_HOME="$_ts_gate_cfg" CLAUDII_CACHE_DIR="$_ts_gate_cache" \
  bash "$SL" >/dev/null 2>&1
assert_eq "tailscale: gated out of layout → no ifconfig probe" "absent" \
  "$([[ -f "$_ts_gate_cache/vpnii-ts" ]] && echo present || echo absent)"

unset _ts_cfg_dir _ts_cache_dir _ts_json output strip _ts_gate_cfg _ts_gate_cache

# No bc in the script
assert_eq "no bc subprocess in claudii-cc-statusline" "0" "$(grep -c '\bbc\b' "$CLAUDII_HOME/bin/claudii-cc-statusline" || true)"

# Regression: claude-status segment must render Opus + Sonnet + Haiku as
# *distinct* labels. Original bug used `declare -A`, which silently breaks
# on bash 3.2 (macOS /bin/bash) — every key resolved to arr[0], so all
# three slots rendered the last value ("Haiku"). Run via /bin/bash
# explicitly so the test catches future bash-3.2 regressions.
# The collapsed health display only names models when they're impaired (an
# all-ok cache renders a single "claude ✓"), so force a non-uniform impaired
# cache — opus/sonnet down, haiku degraded — which lists all three by name.
_test_cache_dir_b32="$(mktemp -d)"; _SL_TMPDIRS+=("$_test_cache_dir_b32")
printf 'opus=down\nsonnet=down\nhaiku=degraded\n' > "$_test_cache_dir_b32/status-models"
# Use a non-Opus/Sonnet/Haiku display name so the model segment doesn't
# collide with the claude-status labels we are asserting on.
_test_cfg_dir_b32="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir_b32")
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
mkdir -p "$CLAUDII_TEST_TMP"
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","cache-create"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":1200}},"cost":{"total_cost_usd":0.10}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "cache-create segment shows ✎" "✎" "$strip"
assert_contains "cache-create segment shows formatted tokens" "1.2K" "$strip"

# cache-create segment: NOT shown when cache_creation_input_tokens = 0
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","cache-create"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":20,"total_input_tokens":5000,"total_output_tokens":1000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"cost":{"total_cost_usd":0.10}}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cache-create absent when zero" "0" "$(echo "$strip" | grep -c '✎' || true)"

# Window / pricing marker — model-aware (exceeds_200k_tokens handling).
# Opus and Sonnet 5+ bill a flat rate across their whole 1M window (no >200k
# premium), so the flag is a non-event there — no marker at all (the constant
# "1M" label these cases used to render was dropped). Legacy-sonnet (4.6 and
# earlier) crossing 200k is a real signal: yellow on a native 1M window
# (sonnet[1m], the paid pricing tier), red on a 200k-class window (genuine
# overflow).
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["context-bar"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
# Opus on its 1M window + exceeds_200k → no marker at all, NEVER >200k (the 28%
# screenshot case: flat pricing, no long-context premium).
_wm=$(echo '{"model":{"display_name":"Opus 4.8","id":"claude-opus-4-8"},"context_window":{"used_percentage":28,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_eq "window marker: opus/1M shows no 1M label" "0" "$(echo "$_wm" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '1M' || true)"
assert_eq "window marker: opus never shows >200k" "0" "$(printf '%s' "$_wm" | grep -cF '>200k' || true)"
# Non-opus 200k-class window + exceeds_200k → genuine overflow → red >200k.
# -F on the count: the needle's '[' is a literal SGR byte, not a regex bracket.
_wm=$(echo '{"model":{"display_name":"Sonnet","id":"claude-sonnet-4-5"},"context_window":{"used_percentage":95,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "window marker: sonnet/200k overflow >200k is red" $'\033[0;31m>200k' "$_wm"
# Non-opus native 1M window (sonnet[1m]) + exceeds_200k → pricing tier → yellow.
_wm=$(echo '{"model":{"display_name":"Sonnet","id":"claude-sonnet-4-5[1m]"},"context_window":{"used_percentage":30,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_contains "window marker: sonnet[1m]/1M >200k is yellow" $'\033[0;33m>200k' "$_wm"
assert_eq "window marker: sonnet[1m] not red" "0" "$(printf '%s' "$_wm" | grep -cF $'\033[0;31m>200k' || true)"
# Sonnet 4.6 bills 1M flat (pricing doc: every model from 4.6 on except Haiku
# 5.5) → no marker, unlike Sonnet 4.5 above.
_wm=$(echo '{"model":{"display_name":"Sonnet 4.6","id":"claude-sonnet-4-6"},"context_window":{"used_percentage":30,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_eq "window marker: sonnet-4-6 never shows >200k" "0" "$(printf '%s' "$_wm" | grep -cF '>200k' || true)"
# Sonnet 5 on its 1M window + exceeds_200k → no marker, NEVER >200k — same
# flat-billing treatment as opus (1M is the default, no [1m] opt-in, confirmed
# 2026-07-01), unlike Sonnet 4.5 and earlier above.
_wm=$(echo '{"model":{"display_name":"Sonnet 5","id":"claude-sonnet-5"},"context_window":{"used_percentage":28,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_eq "window marker: sonnet-5/1M shows no 1M label" "0" "$(echo "$_wm" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '1M' || true)"
assert_eq "window marker: sonnet-5 never shows >200k" "0" "$(printf '%s' "$_wm" | grep -cF '>200k' || true)"
# Fable 5 and Mythos 5 have the same flat-1M-billing shape as opus/sonnet-5.
_wm=$(echo '{"model":{"display_name":"Fable 5","id":"claude-fable-5"},"context_window":{"used_percentage":28,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_eq "window marker: fable-5/1M shows no 1M label" "0" "$(echo "$_wm" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '1M' || true)"
assert_eq "window marker: fable-5 never shows >200k" "0" "$(printf '%s' "$_wm" | grep -cF '>200k' || true)"
_wm=$(echo '{"model":{"display_name":"Mythos 5","id":"claude-mythos-5"},"context_window":{"used_percentage":28,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":1.0},"exceeds_200k_tokens":true}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
assert_eq "window marker: mythos-5/1M shows no 1M label" "0" "$(echo "$_wm" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '1M' || true)"
assert_eq "window marker: mythos-5 never shows >200k" "0" "$(printf '%s' "$_wm" | grep -cF '>200k' || true)"
unset _wm

# ── context (compact) vs context-bar — same number, different width ─────────
# The compact segment replaces the 10-block bar with one ○◔◑◕● fill glyph, so
# the level survives without colour (colour-blind eye, monochrome terminal,
# ANSI-stripped copy-paste) at a tenth of the width.
_cx_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_cx_cfg")
mkdir -p "$_cx_cfg/claudii"
_cx_run() {  # $1 = segment name, $2 = raw used_percentage → stripped output
  printf '{"statusline":{"lines":[["%s"]]}}\n' "$1" > "$_cx_cfg/claudii/config.json"
  echo "{\"model\":{\"display_name\":\"Opus\",\"id\":\"claude-opus-4-8\"},\"context_window\":{\"used_percentage\":$2,\"total_input_tokens\":1,\"total_output_tokens\":1,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.1}}" \
    | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}
# Glyph ramp over the *usable* percentage. 200k window → compact point 167k
# (window − 33k) → scale 83: raw × 100/83 gives 4→4% ○, 20→24% ◔, 40→48% ◑,
# 56→67% ◕, 76→91% ●.
assert_contains "context glyph: 4% → ○"   "○ 4%"   "$(_cx_run context 4)"
assert_contains "context glyph: 24% → ◔"  "◔ 24%"  "$(_cx_run context 20)"
assert_contains "context glyph: 48% → ◑"  "◑ 48%"  "$(_cx_run context 40)"
assert_contains "context glyph: 67% → ◕"  "◕ 67%"  "$(_cx_run context 56)"
assert_contains "context glyph: 91% → ●"  "● 91%"  "$(_cx_run context 76)"
# Colour still keyed on the same thresholds as the bar (green <70, red >=90).
printf '{"statusline":{"lines":[["context"]]}}\n' > "$_cx_cfg/claudii/config.json"
_cx_raw=$(echo '{"model":{"display_name":"Opus","id":"claude-opus-4-8"},"context_window":{"used_percentage":76,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"cost":{"total_cost_usd":0.1}}' \
  | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null)
assert_contains "context 95% is red" $'\033[31m' "$_cx_raw"
# No bar blocks in the compact segment, and no ⚡ glued to it any more.
assert_eq "context: no block bar" "0" "$(_cx_run context 40 | grep -c '█' || true)"
# The bar variant still renders ten blocks for the same input.
assert_contains "context-bar still draws blocks" "████░░░░░░" "$(_cx_run context-bar 40)"
unset -f _cx_run; unset _cx_raw

# ── cache-hit — the ⚡ ratio as its own segment (was glued to context-bar) ────
printf '{"statusline":{"lines":[["context-bar","cache-hit"]]}}\n' > "$_cx_cfg/claudii/config.json"
_ch_json='{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":5000}},"cost":{"total_cost_usd":0.2}}'
_ch=$(echo "$_ch_json" | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "cache-hit segment renders ⚡50%" "⚡50%" "$_ch"
# …and the context-bar next to it no longer carries its own copy.
assert_eq "cache-hit appears exactly once" "1" "$(printf '%s' "$_ch" | grep -o '⚡' | grep -c . || true)"
printf '{"statusline":{"lines":[["context-bar"]]}}\n' > "$_cx_cfg/claudii/config.json"
assert_eq "context-bar alone has no ⚡" "0" \
  "$(echo "$_ch_json" | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | grep -c '⚡' || true)"
unset _ch _ch_json

# ── prompt_cache (CC 2.1.251+): native hit_ratio + cache-ttl segment ─────────
# The native object wins over the context_window derivation, warm renders a
# countdown to expires_at, cold renders the recache price, and an absent
# object leaves cache-ttl empty (older CC) while cache-hit falls back.
printf '{"statusline":{"lines":[["cache-hit","cache-ttl"]]}}\n' > "$_cx_cfg/claudii/config.json"
_pc_now=$(date +%s)
# Native hit_ratio 0.73 beats the derived 50% the context_window values imply
# (total_input_tokens already includes the 5000 cache reads).
_pc_json="{\"model\":{\"display_name\":\"Sonnet\"},\"context_window\":{\"used_percentage\":30,\"total_input_tokens\":10000,\"total_output_tokens\":2000,\"context_window_size\":200000,\"current_usage\":{\"cache_read_input_tokens\":5000}},\"cost\":{\"total_cost_usd\":0.2},\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"hit_ratio\":0.73,\"expires_at\":$(( _pc_now + 250 )),\"recache_tokens_if_cold\":312000}}"
_pc=$(echo "$_pc_json" | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "cache-hit: native hit_ratio wins over derivation" "⚡73%" "$_pc"
assert_contains "cache-ttl: warm renders countdown to expires_at" "♨4m" "$_pc"
# Cold with caching observed → the price of continuing (recache tokens).
_pc_json='{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000},"cost":{"total_cost_usd":0.2},"prompt_cache":{"warm":false,"caching_observed":true,"hit_ratio":0.42,"expires_at":null,"recache_tokens_if_cold":312000}}'
_pc=$(echo "$_pc_json" | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "cache-ttl: cold renders recache price" "♨cold·312.0K" "$_pc"
assert_contains "cache-hit: native ratio works without cache_read" "⚡42%" "$_pc"
# No prompt_cache object (older CC): cache-ttl stays empty, cache-hit derives.
_pc_json='{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":5000}},"cost":{"total_cost_usd":0.2}}'
_pc=$(echo "$_pc_json" | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cache-ttl: absent object renders nothing" "0" "$(printf '%s' "$_pc" | grep -c '♨' || true)"
assert_contains "cache-hit: absent object falls back to derivation" "⚡50%" "$_pc"
# caching never observed (provider without cache reporting) → no cold noise.
_pc_json='{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000},"cost":{"total_cost_usd":0.2},"prompt_cache":{"warm":false,"caching_observed":false,"hit_ratio":0}}'
_pc=$(echo "$_pc_json" | XDG_CONFIG_HOME="$_cx_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cache-ttl: caching_observed=false stays silent" "0" "$(printf '%s' "$_pc" | grep -c '♨' || true)"
unset _pc _pc_json _pc_now

# ── prompt_cache miss attribution (CC 2.1.260+): last_miss_cause on the row ──
# The cause is shown exactly while the CURRENT cached prefix is the one the
# miss produced: the misses counter rose → stamp expires_at (miss_exp= in the
# session cache); a later render with the same expires_at still shows it; the
# next request (new expires_at, misses unchanged) retires it. Each branch is
# a separate render so a dead branch cannot hide behind a live one.
_pm_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_pm_cache")
_pm_now=$(date +%s)
_pm_json() {  # expires_at misses last_miss_cause-json
  printf '{"session_id":"pcmiss01-0000","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":30,"total_input_tokens":10000,"total_output_tokens":2000,"context_window_size":200000},"cost":{"total_cost_usd":0.2},"prompt_cache":{"warm":true,"caching_observed":true,"hit_ratio":0.91,"expires_at":%s,"misses":%s,"last_miss_cause":%s,"miss_causes":{"tools_changed":2,"ttl_expired_5m":1},"recache_tokens_if_cold":45000}}' "$1" "$2" "$3"
}
_pm_run() { XDG_CONFIG_HOME="$_cx_cfg" CLAUDII_CACHE_DIR="$_pm_cache" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }
# Offsets sit ~50s past a minute boundary so a slow runner cannot floor them.
# First render with NO session cache: misses=1 is history, not evidence that
# THIS request missed → no cause (a resumed session must not inherit a lie).
_pm=$(_pm_json $(( _pm_now + 290 )) 1 '{"causes":["likely_server_side"]}' | _pm_run)
assert_contains "cache-ttl: first render still counts down" "♨4m" "$_pm"
assert_not_contains "cache-ttl: first render (no cache history) shows no cause" "miss:" "$_pm"
_pm=$(_pm_json $(( _pm_now + 290 )) 2 '{"causes":["tools_changed"],"tools_added":2}' | _pm_run)
assert_contains "cache-ttl: fresh miss names the cause" "♨4m·miss:tools" "$_pm"
_pm=$(_pm_json $(( _pm_now + 290 )) 2 '{"causes":["tools_changed"],"tools_added":2}' | _pm_run)
assert_contains "cache-ttl: same prefix keeps the cause" "♨4m·miss:tools" "$_pm"
_pm=$(_pm_json $(( _pm_now + 410 )) 2 '{"causes":["tools_changed"],"tools_added":2}' | _pm_run)
assert_contains "cache-ttl: next request (hit) retires the cause" "♨6m" "$_pm"
assert_not_contains "cache-ttl: retired cause is gone" "miss:" "$_pm"
_pm=$(_pm_json $(( _pm_now + 530 )) 3 '{"causes":["system_prompt_changed","ttl_expired_5m"]}' | _pm_run)
assert_contains "cache-ttl: multi-cause miss joins with +" "♨8m·miss:sysprompt+ttl" "$_pm"
_pm_mcs=$(source "$CLAUDII_HOME/lib/helpers.sh"; _miss_cause_short "model_changed+ttl_expired_1h+messages_rewritten"; printf '%s' "$_MCS")
assert_eq "miss cause: model_changed/messages_rewritten shorten" "model+ttl+rewrite" "$_pm_mcs"
unset _pm_mcs
_pm=$(_pm_json "$(( _pm_now + 650 )).5" 4 '{"causes":["likely_server_side","some_future_cause_name"]}' | _pm_run)
assert_contains "cache-ttl: fractional expires_at still stamps; server + unknown clipped to 12" "♨10m·miss:server+some_future_" "$_pm"
_pm=$(_pm_json $(( _pm_now + 770 )) 5 'null' | _pm_run)
assert_not_contains "cache-ttl: undiagnosed miss (null cause) shows no cause" "miss:" "$_pm"
_pm=$(_pm_json $(( _pm_now + 890 )) 6 '"tools_changed"' | _pm_run)
assert_contains "cache-ttl: non-object last_miss_cause does not blank the row" "♨14m" "$_pm"
_pm_file=$(cat "$_pm_cache"/session-pcmiss01)
assert_contains "session cache persists misses=" "misses=6" "$_pm_file"
assert_contains "session cache persists miss_causes=" "miss_causes=tools_changed:2,ttl_expired_5m:1" "$_pm_file"
assert_contains "session cache persists miss_exp= of the last miss" "miss_exp=$(( _pm_now + 890 ))" "$_pm_file"
# `claudii se` detail segment: count + most frequent cause, silent at 0/absent.
_pm_seg=$(
  # run.sh is set -u; the colour vars are normally exported by bin/claudii.
  CLAUDII_CLR_DIM="" CLAUDII_CLR_RESET="" CLAUDII_CLR_CYAN="" CLAUDII_CLR_GREEN="" CLAUDII_CLR_YELLOW="" CLAUDII_SYM_SEP="│"
  source "$CLAUDII_HOME/lib/helpers.sh"; source "$CLAUDII_HOME/lib/render.sh"
  source "$CLAUDII_HOME/lib/cmd/sessions.sh"
  _session_tok_seg 1200 84 3 "ttl_expired_5m:1,tools_changed:2"; printf '\n'
  _session_tok_seg 1200 84 0 "tools_changed:2"; printf '\n'
  _session_tok_seg 1200 84 "" ""; printf '\n'
)
assert_contains "se: misses render count + top cause" "1K tok ⚡84% 3 miss·tools" "$_pm_seg"
assert_eq "se: zero/absent misses stay silent" "1" "$(printf '%s\n' "$_pm_seg" | grep -c 'miss' || true)"
unset -f _pm_json _pm_run; unset _pm _pm_cache _pm_now _pm_file _pm_seg

# ── statusLine.refreshInterval safety: renders every few seconds ────────────
# compact-eta's rate must still be measured (its baseline only moves when a
# sample is taken), and an idle session must not flood the flight recorder.
_rf_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_rf_cfg")
mkdir -p "$_rf_cfg/claudii" "$_rf_cfg/cache"
printf '{"statusline":{"lines":[["context","compact-eta"]]}}\n' > "$_rf_cfg/claudii/config.json"
_rf() {  # duration_ms ctx_pct cost
  printf '{"session_id":"refresh1-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":%s,"context_window_size":1000000},"cost":{"total_duration_ms":%s,"total_cost_usd":%s}}' "$2" "$1" "$3" \
    | XDG_CONFIG_HOME="$_rf_cfg" CLAUDII_CACHE_DIR="$_rf_cfg/cache" bash "$SL" > /dev/null 2>&1
}
for _rf_i in 0 1 2 3 4; do _rf $(( _rf_i * 5000 )) $(( 10 + _rf_i * 2 )) 1.0; done
assert_contains "refresh: a 5 s render cadence still measures the context rate" "ctx_rate=" \
  "$(grep '^ctx_rate=[0-9]' "$_rf_cfg/cache/session-refresh1" 2>/dev/null)"
_rf3() {  # duration_ms ctx_pct api_ms
  printf '{"session_id":"refresh3-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":%s,"context_window_size":1000000},"cost":{"total_duration_ms":%s,"total_api_duration_ms":%s,"total_cost_usd":1.0}}' "$2" "$1" "$3" \
    | XDG_CONFIG_HOME="$_rf_cfg" CLAUDII_CACHE_DIR="$_rf_cfg/cache" bash "$SL" > /dev/null 2>&1
}
_rf3 0 10 1000; _rf3 20000 20 2000
_rf_rate=$(grep '^ctx_rate=' "$_rf_cfg/cache/session-refresh3" | cut -d= -f2)
for _rf_i in 1 2 3 4 5 6 7 8 9 10 11 12; do _rf3 $(( 20000 + _rf_i * 5000 )) 20 2000; done
assert_eq "refresh: idle re-runs (nothing changed) leave the context rate alone" "$_rf_rate" \
  "$(grep '^ctx_rate=' "$_rf_cfg/cache/session-refresh3" | cut -d= -f2)"
_rf3 100000 30 3000
# One sample over the whole 80 s since the last real event (10 points):
# 10 * 60000000 / 80000 = 7500, blended 2:1 with the previous rate.
assert_eq "refresh: the idle gap counts once, measured over its full length" \
  "$(( (_rf_rate * 2 + 7500) / 3 ))" \
  "$(grep '^ctx_rate=' "$_rf_cfg/cache/session-refresh3" | cut -d= -f2)"
unset -f _rf3; unset _rf_rate
_rf_hist() { cat "$_rf_cfg/cache"/history-*.tsv 2>/dev/null | awk -F'\t' '$6=="refresh2-0000"' | wc -l | tr -d ' '; }
_rf2() {  # cost
  printf '{"session_id":"refresh2-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"context_window_size":1000000},"cost":{"total_duration_ms":1000,"total_cost_usd":%s}}' "$1" \
    | XDG_CONFIG_HOME="$_rf_cfg" CLAUDII_CACHE_DIR="$_rf_cfg/cache" bash "$SL" > /dev/null 2>&1
}
_rf2 1.0; _rf2 1.0; _rf2 1.0
assert_eq "refresh: identical renders write one history row" "1" "$(_rf_hist)"
_rf2 1.5
assert_eq "refresh: a changed row is written at once" "2" "$(_rf_hist)"
_rf2 1.5
assert_eq "refresh: an identical row stays skipped (no idle heartbeat)" "2" "$(_rf_hist)"
# The signature is the row itself, so every column counts — pin two that are
# not the cost: the 7d quota (week boundaries) and output tokens.
printf '{"session_id":"refresh2-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"context_window_size":1000000},"cost":{"total_duration_ms":1000,"total_cost_usd":1.5},"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1999999999}}}' \
  | XDG_CONFIG_HOME="$_rf_cfg" CLAUDII_CACHE_DIR="$_rf_cfg/cache" bash "$SL" > /dev/null 2>&1
assert_eq "refresh: a 7d quota change alone writes a row" "3" "$(_rf_hist)"
printf '{"session_id":"refresh2-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"context_window_size":1000000,"total_output_tokens":77},"cost":{"total_duration_ms":1000,"total_cost_usd":1.5},"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1999999999}}}' \
  | XDG_CONFIG_HOME="$_rf_cfg" CLAUDII_CACHE_DIR="$_rf_cfg/cache" bash "$SL" > /dev/null 2>&1
assert_eq "refresh: an output-token change alone writes a row" "4" "$(_rf_hist)"
assert_contains "refresh: the written row carries every column" $'\t41\t1999999999' "$(tail -1 "$_rf_cfg/cache"/history-*.tsv)"
# vibemap rides the same dedup: idle re-renders are not activity.
printf '{"statusline":{"lines":[["model"]]},"vibemap":{"enabled":true}}\n' > "$_rf_cfg/claudii/config.json"
_rf_vm() { grep -c $'\trefresh2\t' "$_rf_cfg/cache/vibemap.tsv" 2>/dev/null || true; }
_rf2 2.0; _rf2 2.0; _rf2 2.0
assert_eq "vibemap: identical renders append one row" "1" "$(_rf_vm)"
_rf2 2.5
assert_eq "vibemap: a changed render appends at once" "2" "$(_rf_vm)"
unset -f _rf_vm
unset -f _rf _rf2 _rf_hist; unset _rf_cfg _rf_i

# ── idle-compact: CC 2.1.332 compacts a 1h-TTL conversation >= 200K tokens at
# 0.9 of the cache lifetime, i.e. expires_at − 6 min — on by default, no flag ─
_ic_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ic_cfg")
mkdir -p "$_ic_cfg/claudii" "$_ic_cfg/cc" "$_ic_cfg/proj/.claude" "$_ic_cfg/managed/managed-settings.d" "$_ic_cfg/home/.claude" "$_ic_cfg/prefs/$(id -un)"
printf '{"statusline":{"lines":[["idle-compact"]]}}\n' > "$_ic_cfg/claudii/config.json"
# expires_at − 360 lands on second :59, so an off-by-one offset (359) flips
# the rendered minute.
_ic_exp=$(( $(date +%s) + 3500 )); _ic_exp=$(( _ic_exp - (_ic_exp - 360) % 60 + 59 ))
_ic_at() { LC_ALL=C date -r $(( _ic_exp - $1 )) +%H:%M 2>/dev/null || LC_ALL=C date -d "@$(( _ic_exp - $1 ))" +%H:%M; }
_ic_want=$(_ic_at 360)
# .claude.json as CC writes it: no trailing newline. $1 = extra top-level
# fields (",k:v"), $2 = the directory.
_ic_global() { printf '{"numStartups":1%s}' "${1:-}" > "${2:-$_ic_cfg/cc}/.claude.json"; }
_ic_json() {  # ttl cache-read-tokens warm [output-tokens] [expires_at] [5h used%] [rate_limits json]
  # Brace-bearing defaults go through a variable: ${7:-{...}} expands
  # differently under /bin/bash 3.2.
  local _rl="${7:-}"
  [[ -n "$_rl" ]] || _rl='{"five_hour":{"used_percentage":'"${6:-10}"'}}'
  printf '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"%s"},"context_window":{"used_percentage":30,"context_window_size":1000000,"current_usage":{"input_tokens":10,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0,"output_tokens":%s}},"prompt_cache":{"warm":%s,"ttl":"%s","expires_at":%s},"rate_limits":%s}' \
    "$_ic_cfg/proj" "$2" "${4:-0}" "$3" "$1" "${5:-$_ic_exp}" "$_rl"
}
_ic_run() { env -u DISABLE_AUTO_COMPACT -u DISABLE_COMPACT -u CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS XDG_CONFIG_HOME="$_ic_cfg" CLAUDE_CONFIG_DIR="$_ic_cfg/cc" CLAUDII_MANAGED_SETTINGS_DIR="$_ic_cfg/managed" CLAUDII_MANAGED_PREFS_DIR="$_ic_cfg/prefs" "$@" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }
_ic_global
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: 1h TTL over 200K shows expires_at − 6 min" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 199989 true | _ic_run)
assert_not_contains "idle-compact: 199999 tokens (one under 200K) shows no compaction" "idle" "$_ic"
_ic=$(_ic_json 1h 199990 true | _ic_run)
assert_contains "idle-compact: exactly 200000 tokens shows" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 5m 250000 true | _ic_run)
assert_not_contains "idle-compact: 5m TTL shows no compaction" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 false | _ic_run)
assert_not_contains "idle-compact: cold cache shows no compaction" "idle" "$_ic"
_ic=$(_ic_json 1h 195000 true 9000 | _ic_run)
assert_contains "idle-compact: output tokens count toward the context" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 300 )) | _ic_run)
assert_not_contains "idle-compact: a time already passed is not shown" "idle" "$_ic"
# No feature flag any more: neither a missing .claude.json nor a stale
# GrowthBook cache from an older CC turns it off.
rm -f "$_ic_cfg/cc/.claude.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: no .claude.json still shows (on by default)" " idle $_ic_want" "$_ic"
_ic_global ',"cachedGrowthBookFeatures":{"tengu_sunny_locket":{"mode":"off"}}'
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: a stale tengu_sunny_locket flag cache is ignored" " idle $_ic_want" "$_ic"
_ic_global
# Threshold: max(100000, CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS ?? 200000).
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=120000)
assert_contains "idle-compact: env threshold lowers the bar" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 160000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=170000)
assert_not_contains "idle-compact: env threshold above the context shows no compaction" "idle" "$_ic"
_ic=$(_ic_json 1h 99989 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=1000)
assert_not_contains "idle-compact: env threshold is floored at 100K (99999 silent)" "idle" "$_ic"
_ic=$(_ic_json 1h 99990 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=1000)
assert_contains "idle-compact: env threshold floor is inclusive (100000 shows)" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=abc)
assert_contains "idle-compact: invalid env threshold falls back to 200K" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 160000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=abc)
assert_not_contains "idle-compact: invalid env threshold falls back to 200K (160K silent)" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=0300000)
assert_not_contains "idle-compact: leading-zero threshold parses as decimal" "idle" "$_ic"
# CC's integer parse: trimmed, +sign, digit groups, integral scientific notation.
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=" +120000 ")
assert_contains "idle-compact: env threshold is trimmed and takes a + sign" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=120_000)
assert_contains "idle-compact: env threshold 120_000 (digit groups)" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=120,000)
assert_contains "idle-compact: env threshold 120,000 (digit groups)" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=120,000_000)
assert_not_contains "idle-compact: mixed group separators are ignored (200K applies)" "idle" "$_ic"
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=1.2e5)
assert_contains "idle-compact: env threshold 1.2e5 (scientific)" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=1.25)
assert_not_contains "idle-compact: a fractional env threshold is ignored (200K applies)" "idle" "$_ic"
_ic=$(_ic_json 1h 150000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=-5)
assert_not_contains "idle-compact: a negative env threshold is ignored (200K applies)" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=99999999999999999999)
assert_not_contains "idle-compact: a huge env threshold never compacts" "idle" "$_ic"
# Env off-switches.
_ic=$(_ic_json 1h 250000 true | _ic_run DISABLE_AUTO_COMPACT=1)
assert_not_contains "idle-compact: DISABLE_AUTO_COMPACT turns compaction off" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run DISABLE_AUTO_COMPACT=false)
assert_contains "idle-compact: DISABLE_AUTO_COMPACT=false is not truthy" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run DISABLE_COMPACT=true)
assert_not_contains "idle-compact: DISABLE_COMPACT turns compaction off" "idle" "$_ic"
# Rate limit: CC skips the fire unless the status is "allowed".
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 100 | _ic_run)
assert_not_contains "idle-compact: a reached rate limit (CC skips: near_limit) shows no compaction" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 100 | sed 's/"five_hour"/"seven_day"/' | _ic_run)
assert_not_contains "idle-compact: a reached 7d limit shows no compaction too" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 99.5 | _ic_run)
assert_contains "idle-compact: below the limit still shows" " idle $_ic_want" "$_ic"
# Legacy autoCompactEnabled in .claude.json — the only key read from there.
_ic_global ',"idleCompaction":false'
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: .claude.json carries only the legacy autoCompactEnabled" " idle $_ic_want" "$_ic"
_ic_global ',"autoCompactEnabled":false'
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: legacy autoCompactEnabled:false in .claude.json turns compaction off" "idle" "$_ic"
printf '{"autoCompactEnabled":true}' > "$_ic_cfg/cc/settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: a settings file overrides the legacy .claude.json value" " idle $_ic_want" "$_ic"
_ic_global
# Settings files — written WITHOUT a trailing newline, like .claude.json, so a
# reader that splits on lines cannot glue two files together unnoticed.
printf '{"idleCompaction":false}' > "$_ic_cfg/cc/settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: idleCompaction:false in user settings turns compaction off (no trailing newline anywhere)" "idle" "$_ic"
printf 'null' > "$_ic_cfg/proj/.claude/settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a null settings file does not reset the merge" "idle" "$_ic"
printf '{"broken":,}' > "$_ic_cfg/proj/.claude/settings.local.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a broken settings file is skipped, not fail-open" "idle" "$_ic"
printf '{"idleCompaction":true}' > "$_ic_cfg/proj/.claude/settings.local.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: local settings override user settings" " idle $_ic_want" "$_ic"
printf '{}' > "$_ic_cfg/cc/settings.json"
printf '{"broken":,}' > "$_ic_cfg/proj/.claude/settings.local.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: a broken settings file alone does not hide the segment" " idle $_ic_want" "$_ic"
rm -f "$_ic_cfg/cc/settings.json" "$_ic_cfg/proj/.claude/settings.local.json"
printf '{"autoCompactEnabled":false}' > "$_ic_cfg/proj/.claude/settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: autoCompactEnabled:false in project settings turns compaction off" "idle" "$_ic"
printf '{"autoCompactEnabled":true}' > "$_ic_cfg/proj/.claude/settings.local.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: local settings override project settings" " idle $_ic_want" "$_ic"
rm -f "$_ic_cfg/proj/.claude/settings.json" "$_ic_cfg/proj/.claude/settings.local.json"
# Managed policy is read last and wins; drop-ins after the main file.
printf '{"idleCompaction":false}' > "$_ic_cfg/cc/settings.json"
printf '{"idleCompaction":true}' > "$_ic_cfg/managed/managed-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: managed policy wins over user settings" " idle $_ic_want" "$_ic"
printf '{"idleCompaction":false}' > "$_ic_cfg/managed/managed-settings.d/10-off.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a managed-settings.d drop-in turns compaction off" "idle" "$_ic"
printf '{"idleCompaction":true}' > "$_ic_cfg/managed/managed-settings.d/20-on.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: a later drop-in wins over an earlier one" " idle $_ic_want" "$_ic"
# CC sorts drop-in names by code unit: "A" < "_" < "b", whatever the locale.
printf '{"idleCompaction":false}' > "$_ic_cfg/managed/managed-settings.d/A.json"
printf '{"idleCompaction":true}' > "$_ic_cfg/managed/managed-settings.d/_z.json"
_ic=$(_ic_json 1h 250000 true | _ic_run LC_ALL=en_US.UTF-8)
assert_contains "idle-compact: drop-ins sort in C order even under LC_ALL" " idle $_ic_want" "$_ic"
rm -f "$_ic_cfg/cc/settings.json" "$_ic_cfg/managed/managed-settings.json" "$_ic_cfg/managed/managed-settings.d/"*.json
# Project dir = $HOME: ~/.claude/settings.json is both the user and the project
# file. The same path twice must not change the outcome.
_ic_global '' "$_ic_cfg/home/.claude"
printf '{"idleCompaction":false}' > "$_ic_cfg/home/.claude/settings.json"
_ic=$(_ic_json 1h 250000 true | sed "s|$_ic_cfg/proj|$_ic_cfg/home|" | _ic_run CLAUDE_CONFIG_DIR="$_ic_cfg/home/.claude")
assert_not_contains "idle-compact: user file = project file keeps its value" "idle" "$_ic"
_ic_global
rm -f "$_ic_cfg/home/.claude/settings.json"
# Managed sources: remote cache > MDM plist > files. "first-wins" (default)
# takes the highest source carrying any policy key — even an unrelated one.
printf '{"idleCompaction":false}' > "$_ic_cfg/managed/managed-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: managed file alone applies" "idle" "$_ic"
printf '{"model":"opus"}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: first-wins — a remote policy key shadows the managed file" " idle $_ic_want" "$_ic"
printf '{"model":"opus","managedSourcesBehavior":"merge"}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: merge set in the top source layers the managed file in" "idle" "$_ic"
printf '{"managedSourcesBehavior":"merge"}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a control-key-only source sets merge but is no policy" "idle" "$_ic"
printf '{"managedSourcesBehavior":"first-wins"}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a managedSourcesBehavior-only source is not selected as the policy" "idle" "$_ic"
printf '{"wslInheritsWindowsSettings":true}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a control-key-only source does not shadow the next one" "idle" "$_ic"
printf '{"idleCompaction":null}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a null value is no policy key" "idle" "$_ic"
rm -f "$_ic_cfg/cc/remote-settings.json"
# MDM plist (macOS configuration profile): same keys as the JSON, per-user
# profile before the device one. Needs plutil to build the fixture.
if command -v plutil >/dev/null 2>&1; then
  _ic_plist() { printf '%s' "$1" > "$_ic_cfg/p.json"; plutil -convert xml1 -o "$2" "$_ic_cfg/p.json"; }
  _ic_plist '{"idleCompaction":true}' "$_ic_cfg/prefs/com.anthropic.claudecode.plist"
  _ic=$(_ic_json 1h 250000 true | _ic_run)
  assert_contains "idle-compact: first-wins — a device MDM profile shadows the managed file" " idle $_ic_want" "$_ic"
  _ic_plist '{"idleCompaction":false}' "$_ic_cfg/prefs/$(id -un)/com.anthropic.claudecode.plist"
  _ic=$(_ic_json 1h 250000 true | _ic_run)
  assert_not_contains "idle-compact: the per-user MDM profile comes before the device one" "idle" "$_ic"
  printf '{"idleCompaction":true}' > "$_ic_cfg/cc/remote-settings.json"
  _ic=$(_ic_json 1h 250000 true | _ic_run)
  assert_contains "idle-compact: the remote cache ranks above MDM" " idle $_ic_want" "$_ic"
  # merge is read from the highest source carrying it, even when that source
  # holds no policy key: remote (merge only) > MDM (unrelated key) > file.
  rm -f "$_ic_cfg/prefs/$(id -un)/com.anthropic.claudecode.plist"
  _ic_plist '{"model":"opus"}' "$_ic_cfg/prefs/com.anthropic.claudecode.plist"
  printf '{"managedSourcesBehavior":"merge"}' > "$_ic_cfg/cc/remote-settings.json"
  _ic=$(_ic_json 1h 250000 true | _ic_run)
  assert_not_contains "idle-compact: merge from a control-only top source still layers MDM and file" "idle" "$_ic"
  rm -f "$_ic_cfg/cc/remote-settings.json" "$_ic_cfg/prefs/com.anthropic.claudecode.plist" "$_ic_cfg/prefs/$(id -un)/com.anthropic.claudecode.plist"
  unset -f _ic_plist
fi
rm -f "$_ic_cfg/managed/managed-settings.json"
# Rate-limit warning band — CC derives allowed_warning itself from
# utilization + resets_at (5h: >= 90% while <= 72% of the window passed; 7d:
# >= 75/50/25% while <= 60/35/15% passed) and then skips the fire; since
# 2.1.332 only when at least 70% is used.
_ic_now=$(date +%s)
_ic_rl() { printf '{"%s":{"used_percentage":%s,"resets_at":%s}}' "$1" "$2" $(( _ic_now + $3 )); }
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl five_hour 92 9000)" | _ic_run)
assert_not_contains "idle-compact: 5h at 92% halfway through the window is a warning (silent)" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl five_hour 92 3600)" | _ic_run)
assert_contains "idle-compact: 5h at 92% late in the window (80% passed) is no warning" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl five_hour 89 9000)" | _ic_run)
assert_contains "idle-compact: 5h at 89% is under the warning threshold" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl seven_day 30 561600)" | _ic_run)
assert_contains "idle-compact: 7d at 30% on day one warns, but below 70% it no longer blocks" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl seven_day 60 423360)" | _ic_run)
assert_contains "idle-compact: 7d at 60% with 30% passed warns, but below 70% it no longer blocks" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl seven_day 72 423360)" | _ic_run)
assert_not_contains "idle-compact: 7d at 72% with 30% passed is a blocking warning (50% tier)" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl seven_day 72 362880)" | _ic_run)
assert_contains "idle-compact: 7d at 72% with 40% passed is no warning" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 "$_ic_exp" 0 "$(_ic_rl seven_day 80 272160)" | _ic_run)
assert_not_contains "idle-compact: 7d at 80% with 55% passed is a warning (75% tier)" "idle" "$_ic"
# precomputeCompactionEnabled gates only a host-less session; the
# interactive REPL always has a host.
printf '{"precomputeCompactionEnabled":false}' > "$_ic_cfg/cc/settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: precomputeCompactionEnabled:false does not stop it" " idle $_ic_want" "$_ic"
rm -f "$_ic_cfg/cc/settings.json"
# Server-managed cache: only while the session talks to Anthropic's API.
printf '{"idleCompaction":false}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: remote cache applies on Anthropic's API" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run ANTHROPIC_BASE_URL=https://api.anthropic.com)
assert_not_contains "idle-compact: the explicit Anthropic base URL keeps the remote cache" "idle" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run ANTHROPIC_BASE_URL=http://localhost:8888)
assert_contains "idle-compact: a foreign ANTHROPIC_BASE_URL ignores the remote cache" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run CLAUDE_CODE_USE_BEDROCK=1)
assert_contains "idle-compact: Bedrock ignores the remote cache" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run CLAUDE_CODE_USE_VERTEX=1)
assert_contains "idle-compact: Vertex ignores the remote cache" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run CLAUDE_CODE_USE_FOUNDRY=1)
assert_contains "idle-compact: Foundry ignores the remote cache" " idle $_ic_want" "$_ic"
rm -f "$_ic_cfg/cc/remote-settings.json"
# Policy keys need content; $-keys never count. Merge: the higher source wins.
printf '{"idleCompaction":false}' > "$_ic_cfg/managed/managed-settings.json"
printf '{"env":{}}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: an empty-object value is no policy key" "idle" "$_ic"
printf '{"$schema":"https://json.schemastore.org/claude-code-settings.json"}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: a \$-key is no policy key" "idle" "$_ic"
printf '{"idleCompaction":true,"managedSourcesBehavior":"merge"}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: under merge the higher-ranked source wins a conflict" " idle $_ic_want" "$_ic"
rm -f "$_ic_cfg/cc/remote-settings.json" "$_ic_cfg/managed/managed-settings.json"
# Remote eligibility: CC compares the base URL's host only; three more
# third-party providers skip the remote cache too.
printf '{"idleCompaction":false}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run ANTHROPIC_BASE_URL=https://api.anthropic.com/v1)
assert_not_contains "idle-compact: a base URL with a path on api.anthropic.com keeps the remote cache" "idle" "$_ic"
for _ic_v in CLAUDE_CODE_USE_ANTHROPIC_AWS CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD CLAUDE_CODE_USE_MANTLE; do
  _ic=$(_ic_json 1h 250000 true | _ic_run "$_ic_v=1")
  assert_contains "idle-compact: $_ic_v ignores the remote cache" " idle $_ic_want" "$_ic"
done
# Policy content: an array (even []) is content, an object of empty objects
# is not.
printf '{"idleCompaction":false}' > "$_ic_cfg/managed/managed-settings.json"
printf '{"availableModels":[]}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_contains "idle-compact: an empty array is a policy key (remote wins first-wins)" " idle $_ic_want" "$_ic"
printf '{"permissions":{"allow":{}}}' > "$_ic_cfg/cc/remote-settings.json"
_ic=$(_ic_json 1h 250000 true | _ic_run)
assert_not_contains "idle-compact: nested empty objects are no policy key" "idle" "$_ic"
rm -f "$_ic_cfg/cc/remote-settings.json" "$_ic_cfg/managed/managed-settings.json"
# MDM: a per-user profile that lints but will not convert (a date value)
# falls through to the device profile; a corrupt one stops the search.
if command -v plutil >/dev/null 2>&1; then
  printf '{"idleCompaction":false}' > "$_ic_cfg/managed/managed-settings.json"
  printf '{"idleCompaction":true}' > "$_ic_cfg/p.json"
  plutil -convert xml1 -o "$_ic_cfg/prefs/com.anthropic.claudecode.plist" "$_ic_cfg/p.json"
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>idleCompaction</key><false/><key>stamp</key><date>2026-01-01T00:00:00Z</date></dict></plist>' \
    > "$_ic_cfg/prefs/$(id -un)/com.anthropic.claudecode.plist"
  _ic=$(_ic_json 1h 250000 true | _ic_run)
  assert_contains "idle-compact: an unconvertible per-user profile falls through to the device one" " idle $_ic_want" "$_ic"
  printf 'not a plist' > "$_ic_cfg/prefs/$(id -un)/com.anthropic.claudecode.plist"
  _ic=$(_ic_json 1h 250000 true | _ic_run)
  assert_not_contains "idle-compact: a corrupt per-user profile stops the MDM search" "idle" "$_ic"
  rm -f "$_ic_cfg/prefs/com.anthropic.claudecode.plist" "$_ic_cfg/prefs/$(id -un)/com.anthropic.claudecode.plist" "$_ic_cfg/managed/managed-settings.json"
fi
unset _ic_v
unset -f _ic_rl; unset _ic_now
# Animation + cold fallback. Strip colour for the text asserts; colour asserts
# read the raw SGR. The frame flips per render via ic_frame= in the session cache.
_ic_global
_ic_anim() {  # ttl seconds-left [extra env...] → raw segment (session anim0001)
  local _ttl=$1 _left=$2; shift 2
  printf '{"session_id":"anim0001-0000","model":{"display_name":"Opus"},"context_window":{"used_percentage":30,"context_window_size":1000000,"current_usage":{"input_tokens":10,"cache_read_input_tokens":250000,"cache_creation_input_tokens":0,"output_tokens":0}},"prompt_cache":{"warm":true,"ttl":"%s","expires_at":%s}}' \
    "$_ttl" $(( $(date +%s) + _left )) \
    | env -u DISABLE_AUTO_COMPACT -u DISABLE_COMPACT -u CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS XDG_CONFIG_HOME="$_ic_cfg" CLAUDE_CONFIG_DIR="$_ic_cfg/cc" CLAUDII_MANAGED_SETTINGS_DIR="$_ic_cfg/managed" CLAUDII_MANAGED_PREFS_DIR="$_ic_cfg/prefs" CLAUDII_CACHE_DIR="$_ic_cfg/anim" "$@" bash "$SL" 2>/dev/null
}
_ic_plain() { sed 's/\x1b\[[0-9;]*m//g'; }
mkdir -p "$_ic_cfg/anim"
_ic=$(_ic_anim 1h 3500 | _ic_plain)
assert_contains "idle-compact anim: fresh request shows an empty glyph and the time left" "⇲○ idle" "$_ic"
assert_contains "idle-compact anim: countdown to the compaction" "· 52m" "$_ic"
_ic=$(_ic_anim 1h 1900 | _ic_plain)
assert_contains "idle-compact anim: halfway the glyph is half full" "⇲◑ idle" "$_ic"
_ic=$(_ic_anim 1h 3500)
assert_contains "idle-compact anim: < 50% of the wait passed is dim" $'\033[2m⇲○' "$_ic"
_ic=$(_ic_anim 1h 1900)
assert_contains "idle-compact anim: >= 50% passed is white" $'\033[0;97m⇲◑' "$_ic"
_ic=$(_ic_anim 1h 1000)
assert_contains "idle-compact anim: >= 75% passed is yellow" $'\033[0;33m⇲' "$_ic"
_ic_a=$(_ic_anim 1h 600); _ic_b=$(_ic_anim 1h 600)
assert_contains "idle-compact anim: the last 10% blink — one frame red full" $'\033[0;31m⇲●' "$_ic_a$_ic_b"
assert_contains "idle-compact anim: the last 10% blink — the other yellow" $'\033[0;33m⇲◕' "$_ic_a$_ic_b"
assert_eq "idle-compact anim: consecutive renders differ while blinking" "1" "$([[ "$_ic_a" != "$_ic_b" ]] && echo 1 || echo 0)"
# Switched off: the segment shows the cache going cold instead, at expires_at.
printf '{"idleCompaction":false}' > "$_ic_cfg/cc/settings.json"
_ic_cold_at=$(_ic_at 0)
_ic=$(_ic_json 1h 250000 true | _ic_run | _ic_plain)
assert_contains "idle-compact: idleCompaction off shows the cache going cold at expires_at" "♨○ warm $_ic_cold_at" "$_ic"
assert_not_contains "idle-compact: idleCompaction off never claims a compaction" "idle" "$_ic"
_ic=$(_ic_anim 5m 150 | _ic_plain)
assert_contains "idle-compact: a 5m cache scales the glyph to its own lifetime" "♨◑ warm" "$_ic"
_ic=$(_ic_json 1h 250000 false | _ic_run | _ic_plain)
assert_eq "idle-compact: a cold cache shows nothing" "" "$_ic"
rm -f "$_ic_cfg/cc/settings.json"
# The cold fallback appears exactly where no compaction will run …
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 300 )) | _ic_run | _ic_plain)
assert_contains "idle-compact: past the compaction time, a warm cache still shows going cold" " cold " "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run DISABLE_AUTO_COMPACT=1 | _ic_plain)
assert_contains "idle-compact: auto-compact off shows the cache going cold" "♨○ warm $_ic_cold_at" "$_ic"
_ic=$(_ic_json 5m 250000 true | _ic_run | _ic_plain)
assert_contains "idle-compact: a 5m cache shows going cold" "♨○ warm" "$_ic"
_ic=$(_ic_json 1h 199989 true | _ic_run | _ic_plain)
assert_contains "idle-compact: below the threshold shows going cold" "♨○ warm $_ic_cold_at" "$_ic"
# … but not next to cache-ttl, which already counts down to that moment.
_ic_cfg2="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ic_cfg2")
mkdir -p "$_ic_cfg2/claudii"; cp -R "$_ic_cfg/cc" "$_ic_cfg2/cc"
printf '{"statusline":{"lines":[["idle-compact","cache-ttl"]]}}\n' > "$_ic_cfg2/claudii/config.json"
_ic=$(_ic_json 1h 250000 true | _ic_run XDG_CONFIG_HOME="$_ic_cfg2" DISABLE_AUTO_COMPACT=1 | _ic_plain)
assert_not_contains "idle-compact: no cold duplicate when cache-ttl is in the layout" " warm " "$_ic"
assert_not_contains "idle-compact: no cold duplicate when cache-ttl is in the layout (late)" " cold " "$_ic"
_ic=$(_ic_json 1h 250000 true | _ic_run XDG_CONFIG_HOME="$_ic_cfg2" | _ic_plain)
assert_contains "idle-compact: the compaction still shows next to cache-ttl" " idle $_ic_want" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 1700 )) | _ic_run DISABLE_AUTO_COMPACT=1 | _ic_plain)
assert_contains "idle-compact: a 1h cold cache halfway through is half full" "♨◑ warm" "$_ic"
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 1700 )) | sed 's/"ttl":"1h",//' | _ic_run | _ic_plain)
assert_contains "idle-compact: no ttl and > 5 min left scales to a 1h cache" "♨◑ warm" "$_ic"
# A payload without prompt_cache.ttl: the lifetime is inferred from what is left.
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 150 )) | sed 's/"ttl":"1h",//' | _ic_run | _ic_plain)
assert_contains "idle-compact: no ttl and <= 5 min left scales to a 5m cache" "♨◑ warm" "$_ic"
# The label follows the colour: "warm" below 75% of the lifetime, "cold" from it.
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 1000 )) | _ic_run DISABLE_AUTO_COMPACT=1 | _ic_plain)
assert_contains "idle-compact: a 1h cache at 72% is still warm" " warm " "$_ic"
_ic=$(_ic_json 1h 250000 true 0 $(( $(date +%s) + 800 )) | _ic_run DISABLE_AUTO_COMPACT=1 | _ic_plain)
assert_contains "idle-compact: a 1h cache at 77% turns cold" "♨◕ cold" "$_ic"
_ic=$(_ic_anim 5m 60 | _ic_plain)
assert_contains "idle-compact: a 5m cache past 75% turns cold" " cold " "$_ic"
unset _ic_cfg2
unset -f _ic_anim _ic_plain; unset _ic_a _ic_b _ic_cold_at
unset -f _ic_json _ic_run _ic_global _ic_at; unset _ic _ic_cfg _ic_exp _ic_want

# ── multi-line stdin payload (read -r used to take only the first line) ─────
# A pretty-printed payload must parse like the compact one, not fall through
# to the empty-field fallback (which renders no model and no context).
_ml_json='{
  "model": {"display_name": "Opus"},
  "context_window": {
    "used_percentage": 40,
    "total_input_tokens": 1000,
    "total_output_tokens": 100,
    "context_window_size": 200000
  },
  "cost": {"total_cost_usd": 0.10}
}'
_ml=$(echo "$_ml_json" | bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "multi-line JSON: model parsed" "Opus" "$_ml"
assert_contains "multi-line JSON: context parsed (40 raw → 48%)" "48%" "$_ml"
unset _ml _ml_json

# ── proxy segment: ANTHROPIC_BASE_URL's host:port, environment first ─────────
_px_dir="$(mktemp -d "$CLAUDII_TEST_TMP/px-XXXXXX")"; _SL_TMPDIRS+=("$_px_dir")
mkdir -p "$_px_dir/cfg/claudii" "$_px_dir/proj/.claude" "$_px_dir/bare/.claude"
printf '{"statusline":{"lines":[["proxy"]]}}\n' > "$_px_dir/cfg/claudii/config.json"
printf '{"env":{"ANTHROPIC_BASE_URL":"https://settings.example:9443/v1"}}\n' > "$_px_dir/proj/.claude/settings.local.json"
printf '{"permissions":{}}\n' > "$_px_dir/bare/.claude/settings.local.json"
_px() {  # project-dir [VAR=value…] → rendered line, colors stripped
  local _d="$1"; shift
  printf '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"%s"}}' "$_d" \
    | env -u ANTHROPIC_BASE_URL "$@" XDG_CONFIG_HOME="$_px_dir/cfg" bash "$SL" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g'
}
assert_eq "proxy: localhost shows host:port, no gateii special case" "⇄ localhost:8888" \
  "$(_px "$_px_dir/bare" ANTHROPIC_BASE_URL=http://localhost:8888)"
assert_eq "proxy: credentials and path never render" "⇄ proxy.example:8443" \
  "$(_px "$_px_dir/bare" ANTHROPIC_BASE_URL=https://user:s3cret@proxy.example:8443/v1)"
assert_eq "proxy: the environment wins over settings.local.json" "⇄ env.example" \
  "$(_px "$_px_dir/proj" ANTHROPIC_BASE_URL=https://env.example)"
assert_eq "proxy: settings.local.json is the fallback" "⇄ settings.example:9443" \
  "$(_px "$_px_dir/proj")"
assert_eq "proxy: no base URL anywhere → empty (no → api)" "" "$(_px "$_px_dir/bare")"
printf '{"statusline":{"lines":[["model"]]}}\n' > "$_px_dir/cfg/claudii/config.json"
assert_not_contains "proxy: gated out of layout" "⇄" \
  "$(_px "$_px_dir/proj" ANTHROPIC_BASE_URL=https://env.example)"
unset -f _px; unset _px_dir

# ── worktrees segment — linked worktrees of the current repo (⑂N ⌫P) ─────────
# Same throwaway-repo discipline as the remotes/git-sync blocks: the repo lives
# in the SYSTEM temp dir (a repo under $CLAUDII_HOME would let git's upward
# .git discovery resolve to claudii's own tree) with an empty --template.
_wt_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_wt_cfg")
mkdir -p "$_wt_cfg/claudii"
printf '{"statusline":{"lines":[["worktrees"]]}}\n' > "$_wt_cfg/claudii/config.json"
_wt_tpl="$(mktemp -d)"; _SL_TMPDIRS+=("$_wt_tpl")
_wt_base="$(mktemp -d)"; _SL_TMPDIRS+=("$_wt_base")
_wt_repo="$_wt_base/repo"
git init -q --template="$_wt_tpl" -b main "$_wt_repo"
git -C "$_wt_repo" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m A
_wt_run() {  # $1 = cwd → stripped statusline output
  echo "{\"model\":{\"display_name\":\"Opus\"},\"cwd\":\"$1\",\"context_window\":{\"used_percentage\":10}}" \
    | XDG_CONFIG_HOME="$_wt_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}
# Main working tree alone → not counted → segment empty → no output line.
assert_eq "worktrees: none → empty output" "" "$(_wt_run "$_wt_repo")"
git -C "$_wt_repo" worktree add -q -b wt1 "$_wt_base/wt1"
git -C "$_wt_repo" worktree add -q -b wt2 "$_wt_base/wt2"
assert_contains "worktrees: two linked → ⑂2" "⑂2" "$(_wt_run "$_wt_repo")"
# A worktree whose directory is gone stays counted but is flagged prunable.
mv "$_wt_base/wt2" "$_wt_base/wt2-gone"
assert_contains "worktrees: prunable → ⌫1" "⑂2 ⌫1" "$(_wt_run "$_wt_repo")"
# Seen from inside a linked worktree the count is the same (repo-wide, not relative).
assert_contains "worktrees: same count from inside a worktree" "⑂2" "$(_wt_run "$_wt_base/wt1")"
# Non-git directory → segment omitted entirely.
assert_eq "worktrees: non-git → empty output" "" "$(_wt_run "$_wt_tpl")"
# Layout gate: no `worktrees` in the layout → no ⑂ anywhere (and no git fork).
printf '{"statusline":{"lines":[["model"]]}}\n' > "$_wt_cfg/claudii/config.json"
assert_eq "worktrees: gated out of layout" "0" "$(_wt_run "$_wt_repo" | grep -c '⑂' || true)"

# ── branch segment — the branch nothing else showed (⎇ name) ─────────────────
# Reuses the worktree test repo (main + wt1/wt2 branches, main is clean here).
printf '{"statusline":{"lines":[["branch"]]}}\n' > "$_wt_cfg/claudii/config.json"
assert_contains "branch: names the current branch" "⎇ main" "$(_wt_run "$_wt_repo")"
# Clean trunk is dim; uncommitted work sitting on the trunk turns it yellow.
_br_raw() { echo "{\"model\":{\"display_name\":\"O\"},\"cwd\":\"$1\",\"context_window\":{\"used_percentage\":10}}" \
    | XDG_CONFIG_HOME="$_wt_cfg" bash "$SL" 2>/dev/null; }
assert_contains "branch: clean main is dim" $'\033[2m⎇ main' "$(_br_raw "$_wt_repo")"
printf 'x\n' > "$_wt_repo/dirty-file"
assert_contains "branch: dirty main is yellow" $'\033[0;33m⎇ main' "$(_br_raw "$_wt_repo")"
# A feature branch stays dim even when dirty — the nudge is about the trunk.
assert_contains "branch: dirty feature branch stays dim" $'\033[2m⎇ wt1' "$(_br_raw "$_wt_base/wt1")"
# Detached HEAD → the branch.head line reads "(detached)".
git -C "$_wt_repo" checkout -q --detach HEAD
assert_contains "branch: detached HEAD says so" "⎇ detached" "$(_wt_run "$_wt_repo")"
git -C "$_wt_repo" checkout -q main
# Non-git directory → segment omitted entirely.
assert_eq "branch: non-git → empty output" "" "$(_wt_run "$_wt_tpl")"
unset -f _wt_run _br_raw

# ── compact-eta + response — both derive from deltas between two renders ────
# One session id rendered twice against the same cache dir: the first render
# only seeds the baseline (no rate yet, no api delta), the second produces both.
_dl_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_dl_cfg")
mkdir -p "$_dl_cfg/claudii"
printf '{"statusline":{"lines":[["context","compact-eta","response"]]}}\n' > "$_dl_cfg/claudii/config.json"
_dl_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_dl_cache")
_dl_run() {  # $1 = raw ctx%, $2 = duration_ms, $3 = api_duration_ms
  printf '{"model":{"display_name":"Opus","id":"claude-opus-4-8"},"session_id":"deltasess001","context_window":{"used_percentage":%s,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"cost":{"total_cost_usd":0.1,"total_duration_ms":%s,"total_api_duration_ms":%s}}' "$1" "$2" "$3" \
    | XDG_CONFIG_HOME="$_dl_cfg" CLAUDII_CACHE_DIR="$_dl_cache" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}
_dl_first=$(_dl_run 20 60000 20000)
assert_eq "compact-eta: no rate on the first render" "0" "$(printf '%s' "$_dl_first" | grep -c '⇲' || true)"
assert_eq "response: no delta on the first render"   "0" "$(printf '%s' "$_dl_first" | grep -c '↯' || true)"
# +6 raw points in 120s on the 200k window's 83% scale = 3.61 usable-%/min;
# usable is 31%, so 69 points remain → 19 min. The response delta is
# 64500-20000 = 44.5s → "45s".
_dl_second=$(_dl_run 26 180000 64500)
assert_contains "compact-eta: 6%/2min → ⇲19m" "⇲19m" "$_dl_second"
assert_contains "response: api delta renders as 45s" "↯45s" "$_dl_second"
# The rate is persisted, not recomputed from scratch each render.
assert_contains "compact-eta: ctx_rate cached" "ctx_rate=3000" "$(cat "$_dl_cache/session-deltases")"
# A render with no new API time keeps showing the last response's duration
# instead of blanking the segment.
assert_contains "response: survives a render with no new API time" "↯45s" "$(_dl_run 26 200000 64500)"
# Sub-10s deltas get one decimal; a compaction (ctx drop) must not produce a
# negative rate — the ETA either holds or disappears, it never inverts.
assert_contains "response: sub-10s delta has one decimal" "↯4.1s" "$(_dl_run 27 260000 68600)"
_dl_compact=$(_dl_run 3 320000 68600)
assert_eq "compact-eta: compaction produces no negative ETA" "0" "$(printf '%s' "$_dl_compact" | grep -c -- '-' || true)"

# The same deltas, kept as a window, because one of them is the wrong number
# for anything asking how slow the API was *while a piece of work happened*.
# Two calls landed in this session, 44.5s and 4.1s: the mean is 24.3s while the
# last delta is 4.1s, and a consumer reading from inside a tool call gets the
# 4.1s kind every single time.
_dl_cached="$(cat "$_dl_cache/session-deltases")"
assert_contains "api window: the mean spans the window, not the last call" "api_mean_ms=24300" "$_dl_cached"
assert_contains "api window: it says how many calls it averaged" "api_mean_n=2" "$_dl_cached"
assert_contains "api window: the last call stays beside it" "last_api_delta=4100" "$_dl_cached"
unset -f _dl_run; unset _dl_first _dl_second _dl_compact _dl_cached

# An entry older than the window leaves it: what the API cost an hour ago is
# not what things are like now, and a mean that never forgets would report a
# recovered API as still broken.
_aw_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_aw_cache")
_aw_now=$(date +%s)
printf 'session_id=agedsess001\nlast_api_duration_ms=10000\nlast_api_delta=5000\napi_recent=%s:99000,%s:6000\n' \
  "$(( _aw_now - 3600 ))" "$(( _aw_now - 60 ))" > "$_aw_cache/session-agedsess"
printf '{"model":{"display_name":"Opus"},"session_id":"agedsess001","context_window":{"used_percentage":10},"cost":{"total_cost_usd":0.1,"total_duration_ms":60000,"total_api_duration_ms":18000}}' \
  | CLAUDII_CACHE_DIR="$_aw_cache" bash "$SL" >/dev/null 2>&1
_aw_cached="$(cat "$_aw_cache/session-agedsess")"
# the 6s from a minute ago and the fresh 8s survive; the hour-old 99s does not
assert_contains "api window: stale entries are dropped" "api_mean_ms=7000" "$_aw_cached"
assert_contains "api window: only the fresh entries are counted" "api_mean_n=2" "$_aw_cached"
assert_not_contains "api window: the hour-old reading is gone" ":99000" "$_aw_cached"
unset _aw_now _aw_cached

# ── ci segment — reads the cache claudii-ci-refresh maintains ────────────────
# Every seed below is written fresh, so its mtime is younger than the TTL and
# the render never spawns the (network-touching) refresher.
_ci_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ci_cfg")
mkdir -p "$_ci_cfg/claudii"
printf '{"statusline":{"lines":[["ci"]]}}\n' > "$_ci_cfg/claudii/config.json"
_ci_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_ci_cache")
_ci_tpl="$(mktemp -d)"; _SL_TMPDIRS+=("$_ci_tpl")
_ci_repo="$(mktemp -d)"; _SL_TMPDIRS+=("$_ci_repo")
git init -q --template="$_ci_tpl" -b main "$_ci_repo"
git -C "$_ci_repo" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m A
# The cache filename is _str_hash(dir\nbranch) — sourced from lib/helpers.sh
# rather than reimplemented, so a change to the hash breaks this test loudly
# instead of silently seeding a file nothing reads.
# shellcheck source=lib/timefmt.sh
source "$CLAUDII_HOME/lib/timefmt.sh"
# shellcheck source=lib/helpers.sh
source "$CLAUDII_HOME/lib/helpers.sh"
_str_hash "${_ci_repo}"$'\n'"main"
_ci_file="$_ci_cache/ci-${_ci_repo##*/}-${_HASH}"
_ci_seed() {  # $1 = state, $2 = checked epoch offset (default now)
  printf 'state=%s\nurl=u\nrepo=%s\nbranch=main\nchecked=%s\n' \
    "$1" "$_ci_repo" "$(( $(date +%s) - ${2:-0} ))" > "$_ci_file"
}
_ci_run() {
  echo "{\"model\":{\"display_name\":\"O\"},\"cwd\":\"$_ci_repo\",\"context_window\":{\"used_percentage\":10}}" \
    | XDG_CONFIG_HOME="$_ci_cfg" CLAUDII_CACHE_DIR="$_ci_cache" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}
_ci_seed success; assert_contains "ci: success → CI ✓" "CI ✓" "$(_ci_run)"
_ci_seed failure; assert_contains "ci: failure → CI ✗" "CI ✗" "$(_ci_run)"
_ci_seed running; assert_contains "ci: running → CI ●" "CI ●" "$(_ci_run)"
_ci_seed queued;  assert_contains "ci: queued → CI ◌"  "CI ◌" "$(_ci_run)"
_ci_seed other;   assert_contains "ci: other → CI ⊘"   "CI ⊘" "$(_ci_run)"
# A broken refresh is rendered as broken — never as a green tick.
_ci_seed error;   assert_contains "ci: error → CI ?"   "CI ?" "$(_ci_run)"
# Permanent states render nothing: no runs yet, and no GitHub remote at all.
_ci_seed none;        assert_eq "ci: none → empty output"        "" "$(_ci_run)"
_ci_seed unavailable; assert_eq "ci: unavailable → empty output" "" "$(_ci_run)"
# An hour-old verdict is a claim about a push that may have been superseded.
_ci_seed success 7200; assert_contains "ci: hour-old cache → CI stale" "CI stale" "$(_ci_run)"
# No cache file at all → nothing rendered (and the refresher spawn is the only
# thing that happens, in the background).
rm -f "$_ci_file"
assert_eq "ci: no cache → empty output" "" "$(_ci_run)"
unset -f _ci_seed _ci_run

# ── Width discipline — max_label / separator / max_width ────────────────────
# Lengths go through _wd_len, not bare ${#…}: under LC_ALL=C (a CI matrix leg)
# ${#…} counts bytes, and every glyph here is a 3-byte sequence — measuring
# bytes against a column budget reports overflows that do not exist. Dropping
# UTF-8 continuation bytes first counts characters in either locale, which is
# the same thing the statusline itself does (_clen).
_wd_len() { local _s=${1//[$'\x80'-$'\xbf']/}; printf '%s' "${#_s}"; }
_wd_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_wd_cfg")
mkdir -p "$_wd_cfg/claudii"
_wd_json='{"model":{"display_name":"Sonnet 5","id":"claude-sonnet-5"},"session_id":"widthsess001","session_name":"a-rather-long-session-name","worktree":{"name":"toasty-petting-moler-cat","branch":"worktree-toasty-petting-moler-cat"},"context_window":{"used_percentage":12},"cost":{"total_cost_usd":0.1}}'
_wd_run() {  # $1 = extra jq filter over the config → stripped output
  jq -cn --argjson l '[["model","worktree","session-name"]]' \
    "{statusline:{lines:\$l}} | ${1:-.}" > "$_wd_cfg/claudii/config.json"
  printf '%s' "$_wd_json" | XDG_CONFIG_HOME="$_wd_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}

# max_label: the worktree- prefix Claude Code puts on worktree branches is
# stripped (the worktree segment beside it already says what this is), and
# what's left is capped with an ellipsis.
_wd_out=$(_wd_run)
assert_eq "max_label: worktree- prefix stripped" "0" "$(printf '%s' "$_wd_out" | grep -c 'worktree-' || true)"
assert_contains "max_label: long name truncated at 20" "toasty-petting-mole…" "$_wd_out"
assert_contains "max_label: session-name truncated too" "a-rather-long-sessi…" "$_wd_out"
# 0 turns truncation off — the full name comes back (the prefix strip does not,
# it is not part of the budget).
_wd_full=$(_wd_run '.statusline.max_label = 0')
assert_contains "max_label 0: full name kept" "a-rather-long-session-name" "$_wd_full"
# A tiny cap still leaves room for content plus the ellipsis.
assert_contains "max_label 8: capped to 8 columns" "toasty-…" "$(_wd_run '.statusline.max_label = 8')"

# separator: tight by default, wide restores the historical 5-column gap.
assert_contains "separator: tight is the default" "5 │ toasty" "$(_wd_run)"
assert_contains "separator: wide restores 5 columns" "5  │  toasty" "$(_wd_run '.statusline.separator = "wide"')"

# max_width: off by default, and never exceeded once set. The sweep is the
# actual contract — a single spot check would miss the give-back case, where
# the ellipsis only fits after handing the last segment back.
# The drop marker is a LONE ellipsis behind a separator; matching a bare "…"
# would also hit a max_label-truncated name and pass for the wrong reason.
assert_eq "max_width: off by default (no drop marker)" "0" \
  "$(printf '%s' "$_wd_out" | grep -c '│ …' || true)"
_wd_over=0; _wd_capped=0
for _wd_m in 20 24 28 32 36 40 44 48 52 56 60 64 68 72; do
  _wd_line=$(_wd_run ".statusline.max_width = $_wd_m")
  (( $(_wd_len "$_wd_line") > _wd_m )) && _wd_over=$(( _wd_over + 1 ))
  [[ "$_wd_line" == *"│ …" ]] && _wd_capped=$(( _wd_capped + 1 ))
done
assert_eq "max_width: budget never exceeded across the sweep" "0" "$_wd_over"
# …and the sweep really did exercise the capping path (a green "never
# exceeded" on a sweep that never capped anything would prove nothing).
assert_eq "max_width: sweep actually hit the cap" "14" "$_wd_capped"
# The first segment always renders, even when it alone blows the budget —
# that is the documented exception, and it must still show the marker.
_wd_tiny=$(_wd_run '.statusline.max_width = 5')
assert_contains "max_width: first segment survives an impossible budget" "Sonnet 5" "$_wd_tiny"
assert_contains "max_width: impossible budget still marks the cut" "…" "$_wd_tiny"
# One over-budget segment must not take the cheaper ones behind it down with
# it. At 40 columns the 43-column worktree segment cannot fit at all, but the
# 20-column session-name behind it can — and does.
_wd_skip=$(_wd_run '.statusline.max_width = 40')
assert_contains "max_width: segment behind a skipped one survives" "a-rather-long-sessi…" "$_wd_skip"
assert_eq "max_width: the wide segment is the one dropped" "0" \
  "$(printf '%s' "$_wd_skip" | grep -c 'toasty' || true)"
assert_contains "max_width: the skip is marked" "│ …" "$_wd_skip"
# A non-ASCII name must never be cut mid-sequence. The name is built so the
# naive cut lands INSIDE a character: max_label 10 cuts after 9 units, and the
# two-byte "ä" occupies bytes 9-10 — so in byte mode a cut without the boundary
# back-off emits a lone lead byte. Picking a name that happens to break on a
# boundary would pass with the back-off removed (it did, on the first try).
_wd_json='{"model":{"display_name":"S"},"session_id":"widthsess002","session_name":"abcdefghähnlich-lang-genug","context_window":{"used_percentage":12},"cost":{"total_cost_usd":0.1}}'
# The two locales legitimately land on different cuts — character mode keeps
# 9 characters ("abcdefghä"), byte mode keeps 8 after backing off the split
# "ä" — so the assert is the invariant both must satisfy, not one exact string:
# valid UTF-8 out, the intact prefix in, and never longer than the cap.
_wd_uml=$(_wd_run '.statusline.max_label = 10')
assert_eq "max_label: truncated output stays valid UTF-8" "0" \
  "$(printf '%s' "$_wd_uml" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; echo $?)"
assert_contains "max_label: intact prefix survives the cut" "abcdefgh" "$_wd_uml"
assert_contains "max_label: multibyte name is marked as cut" "…" "$_wd_uml"
# "S" + " │ " + at most 10 label characters.
assert_eq "max_label: never exceeds the cap in either locale" "1" \
  "$(( $(_wd_len "$_wd_uml") <= 14 ))"
unset -f _wd_run _wd_len; unset _wd_out _wd_full _wd_line _wd_over _wd_capped _wd_tiny _wd_skip _wd_uml _wd_json

# session-name segment: shown when session_name set
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
mkdir -p "$_test_cfg_dir/claudii"
printf '{"statusline":{"lines":[["model","session-name"]]}}\n' > "$_test_cfg_dir/claudii/config.json"
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01},"session_name":"my-feature"}' \
  | XDG_CONFIG_HOME="$_test_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "session-name segment shows name" "my-feature" "$strip"

# dir segment — workspace.project_dir basename shown in default layout
mkdir -p "$CLAUDII_TEST_TMP"
_test_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_test_cfg_dir")
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
# `awk -v n="$n"` with numeric coercion (n+0) should sanitize, but regression-test anyway.
# Pin a claude-status + tokens layout: the injection lands in the tokens segment (so the
# _tok path is exercised), and the health line is the deterministic "statusline still
# rendered" sentinel — it's independent of the token math (a malformed tokens value
# blanks the token-consuming segments) and, all-ok, collapses to "claude ✓".
_inj_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_inj_cfg_dir")
mkdir -p "$_inj_cfg_dir/claudii"
printf '{"statusline":{"lines":[["claude-status"],["tokens"]]}}\n' > "$_inj_cfg_dir/claudii/config.json"
_inj_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_inj_cache_dir")
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$_inj_cache_dir/status-models"
_mal='1000; system("echo PWNED_TOK")'
output=$(jq -n --arg t "$_mal" '{"session_id":"injtest","model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":$t,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}' \
  | XDG_CONFIG_HOME="$_inj_cfg_dir" CLAUDII_CACHE_DIR="$_inj_cache_dir" bash "$SL" 2>&1)
assert_not_contains "_tok awk injection: no PWNED in output" "PWNED_TOK" "$output"
assert_contains "_tok awk injection: statusline still renders" "claude" "$output"
unset _inj_cfg_dir _inj_cache_dir

# github segment — workspace.repo.{owner,name} from CC 2.1.145+; the PR is the
# top-level pr.number (CC 2.1.332), older builds put it in workspace.repo.pr_number
_gh_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/gh-XXXXXX")"; _SL_TMPDIRS+=("$_gh_cfg")
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

# CC 2.1.332 shape: workspace.repo = {host,owner,name}, the PR at top-level pr
_j=$(jq -cn --argjson w '{"repo":{"host":"github.com","owner":"bmmmm","name":"claudii"}}' '{"model":{"display_name":"Opus"},"workspace":$w,"pr":{"number":7,"url":"https://github.com/bmmmm/claudii/pull/7","review_state":"approved"},"context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "github: shows the top-level pr.number (CC 2.1.332)" "bmmmm/claudii #7" "$strip"
_j=$(jq -cn --argjson w '{"repo":{"host":"github.com","owner":"bmmmm","name":"claudii","pr_number":42}}' '{"model":{"display_name":"Opus"},"workspace":$w,"pr":{"number":7},"context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains     "github: pr.number wins over workspace.repo.pr_number" "#7"  "$strip"
assert_not_contains "github: the older field is only a fallback"           "#42" "$strip"
# pr.kind "mr" (GitLab merge request) renders as !N, not as a PR's #N
_j=$(jq -cn --argjson w '{"repo":{"host":"gitlab.com","owner":"bmmmm","name":"claudii"}}' '{"model":{"display_name":"Opus"},"workspace":$w,"pr":{"number":12,"kind":"mr"},"context_window":{"used_percentage":10,"context_window_size":200000}}')
strip=$(echo "$_j" | XDG_CONFIG_HOME="$_gh_cfg" bash "$SL" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
assert_contains     "github: a merge request renders as !N" "bmmmm/claudii !12" "$strip"
assert_not_contains "github: a merge request is no #N"      "#12"               "$strip"

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

# cc-version segment — top-level .version from the statusLine payload, plus
# the red "+N releases behind" annotation sourced from status-cc-version
# (written by claudii-cc-update-refresh). Cache dir is isolated per case: this
# segment now touches a real shared cache file, and the real machine's cache
# (if any) must never leak into the assertions.
_ccv_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cfg")
mkdir -p "$_ccv_cfg/claudii"
printf '{"statusline":{"lines":[["cc-version"]]}}\n' > "$_ccv_cfg/claudii/config.json"

# No update-cache yet: plain, dim — never a false "behind" before there is data.
_ccv_cache_none="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-cache-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cache_none")
_j=$(jq -cn '{"model":{"display_name":"Opus"},"version":"2.1.90","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_none" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cc-version: no update-cache yet → plain version" "v2.1.90" "$strip"
assert_not_contains "cc-version: no update-cache yet → not red" $'\033[0;31m' "$output"

# version absent entirely: line renders nothing
output=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"context_window_size":200000}}' \
  | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_none" bash "$SL" 2>&1)
assert_eq "cc-version: empty when version absent" "" "$output"

# Up to date (installed == latest): plain, dim, no red, no +N.
_ccv_cache_uptodate="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-cache-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cache_uptodate")
printf 'latest=2.1.90\ntags=2.1.90,2.1.89,2.1.88\nchecked=9999999999\n' > "$_ccv_cache_uptodate/status-cc-version"
output=$(echo "$_j" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_uptodate" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cc-version: up to date → plain version" "v2.1.90" "$strip"
assert_not_contains "cc-version: up to date → not red" $'\033[0;31m' "$output"

# One release behind: red, "+1".
_ccv_cache_1behind="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-cache-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cache_1behind")
printf 'latest=2.1.91\ntags=2.1.91,2.1.90,2.1.89\nchecked=9999999999\n' > "$_ccv_cache_1behind/status-cc-version"
output=$(echo "$_j" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_1behind" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cc-version: 1 behind → red +1" "v2.1.90 +1" "$strip"
assert_contains "cc-version: 1 behind → red color code" $'\033[0;31m' "$output"

# Several releases behind, with a skipped tag in between: the count is the
# number of ACTUAL releases, not a numeric version diff (91 - 88 = 3 would be
# wrong here — 2.1.89 was skipped, so only 2 releases are newer than 2.1.88).
_ccv_cache_2behind="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-cache-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cache_2behind")
printf 'latest=2.1.91\ntags=2.1.91,2.1.90,2.1.88\nchecked=9999999999\n' > "$_ccv_cache_2behind/status-cc-version"
_j88=$(jq -cn '{"model":{"display_name":"Opus"},"version":"2.1.88","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j88" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_2behind" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cc-version: skipped tag → correct release count, not a version diff" "v2.1.88 +2" "$strip"

# Installed version fell off the cached window: red, "+?" — never a fabricated count.
_ccv_cache_unknown="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-cache-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cache_unknown")
printf 'latest=2.1.91\ntags=2.1.91,2.1.90,2.1.89\nchecked=9999999999\n' > "$_ccv_cache_unknown/status-cc-version"
_jold=$(jq -cn '{"model":{"display_name":"Opus"},"version":"1.0.0","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_jold" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_unknown" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cc-version: fell off cached window → red +?" "v1.0.0 +?" "$strip"

# Installed newer than the cached latest (a release the cache has not seen
# yet): current, not "+?" — the cache is what is behind.
_jnew=$(jq -cn '{"model":{"display_name":"Opus"},"version":"2.1.92","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_jnew" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_unknown" bash "$SL" 2>&1)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "cc-version: newer than cached latest → plain version" "v2.1.92" "$strip"
assert_not_contains "cc-version: newer than cached latest → not red" $'\033[0;31m' "$output"
# Numeric, not lexical: 2.1.100 is newer than 2.1.91.
_j100=$(jq -cn '{"model":{"display_name":"Opus"},"version":"2.1.100","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j100" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_unknown" bash "$SL" 2>&1)
assert_eq "cc-version: 2.1.100 vs latest 2.1.91 → current (numeric compare)" "v2.1.100" \
  "$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')"
# Not comparable (pre-release suffix): no claim either way.
_jpre=$(jq -cn '{"model":{"display_name":"Opus"},"version":"2.1.92-beta.1","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_jpre" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_unknown" bash "$SL" 2>&1)
assert_eq "cc-version: unparsable version → plain, no +?" "v2.1.92-beta.1" \
  "$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')"
# Older and inside the window but not listed (a yanked tag): count the listed
# releases newer than it.
_j89=$(jq -cn '{"model":{"display_name":"Opus"},"version":"2.1.89","context_window":{"used_percentage":10,"context_window_size":200000}}')
output=$(echo "$_j89" | XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_2behind" bash "$SL" 2>&1)
assert_eq "cc-version: unlisted version inside the window → count of newer releases" "v2.1.89 +2" \
  "$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')"

# A newer install re-checks after 5 min, past the refresher's own TTL. Stub
# refresher in a scratch CLAUDII_HOME, so nothing touches the network.
_ccv_home="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-home-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_home")
mkdir -p "$_ccv_home/bin"
ln -s "$CLAUDII_HOME/lib" "$_ccv_home/lib"; ln -s "$CLAUDII_HOME/config" "$_ccv_home/config"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/args"\n' "$_ccv_home" > "$_ccv_home/bin/claudii-cc-update-refresh"
chmod +x "$_ccv_home/bin/claudii-cc-update-refresh"
_ccv_cache_stale="$(mktemp -d "$CLAUDII_TEST_TMP/ccv-cache-XXXXXX")"; _SL_TMPDIRS+=("$_ccv_cache_stale")
printf 'latest=2.1.91\ntags=2.1.91,2.1.90,2.1.89\nchecked=1\n' > "$_ccv_cache_stale/status-cc-version"
_ccv_ts=$(date -v-600S +%Y%m%d%H%M.%S 2>/dev/null || date -d "600 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
if [[ -n "$_ccv_ts" ]]; then
  touch -t "$_ccv_ts" "$_ccv_cache_stale/status-cc-version"
  _ccv_wait() { local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [[ -s "$_ccv_home/args" ]] && return; sleep 0.1; done; }
  # A listed version with a 10-min-old cache: inside the 1h TTL → no refresh.
  echo "$_j" | CLAUDII_HOME="$_ccv_home" XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_stale" bash "$SL" > /dev/null 2>&1
  echo "$_jnew" | CLAUDII_HOME="$_ccv_home" XDG_CONFIG_HOME="$_ccv_cfg" CLAUDII_CACHE_DIR="$_ccv_cache_stale" bash "$SL" > /dev/null 2>&1
  _ccv_wait
  assert_eq "cc-version: newer install → exactly one forced refresh" "1" \
    "$(grep -c -- '--force' "$_ccv_home/args" 2>/dev/null || echo 0)"
  assert_eq "cc-version: the older install never spawned a refresh" "1" \
    "$(wc -l < "$_ccv_home/args" 2>/dev/null | tr -d ' ')"
  unset -f _ccv_wait
fi
unset _jnew _j100 _jpre _j89 _ccv_home _ccv_cache_stale _ccv_ts

# ── Pace tri-state segment tests ───────────────────────────────────────────────
_pace_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_pace_cfg_dir")
mkdir -p "$_pace_cfg_dir/claudii"
printf '{"statusline":{"lines":[["pace"]]}}\n' > "$_pace_cfg_dir/claudii/config.json"
# 30 min into the 5h window (linear = 10%); the session's own duration is irrelevant.
_pace_r30=$(( $(date +%s) + 16200 )); _pace_r1=$(( $(date +%s) + 17940 ))

# ahead: window 30min, linear=10%, actual=5% → 5 < 10×0.85=8.5 → ahead (↑)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":'"$_pace_r30"'},"seven_day":{"used_percentage":10}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "pace ahead: ↑ shown" "↑" "$strip"

# behind: window 30min, linear=10%, actual=20% → 20 > 10×1.15=11.5 → behind (↓)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":'"$_pace_r30"'},"seven_day":{"used_percentage":30}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "pace behind: ↓ shown" "↓" "$strip"

# on_pace: window 30min, linear=10%, actual=10% → exactly on-pace (=)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$_pace_r30"'},"seven_day":{"used_percentage":20}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "pace on_pace: = shown" "=" "$strip"

# no data: window < 3min old → pace segment empty (below gate)
output=$(echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$_pace_r1"'},"seven_day":{"used_percentage":20}}}' \
  | XDG_CONFIG_HOME="$_pace_cfg_dir" bash "$SL" 2>/dev/null)
strip=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "pace: no glyph when the window is < 3min old" "↑" "$strip"
assert_not_contains "pace: no ↓ when the window is < 3min old"     "↓" "$strip"

# pace persisted in session cache file
_pace_cache_dir="$(mktemp -d)"; _SL_TMPDIRS+=("$_pace_cache_dir")
echo '{"session_id":"testpace999","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10,"total_input_tokens":500,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.05,"total_duration_ms":1800000},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":'"$_pace_r30"'},"seven_day":{"used_percentage":10}}}' \
  | CLAUDII_CACHE_DIR="$_pace_cache_dir" bash "$SL" 2>/dev/null >/dev/null
_cache_pace="$(cat "$_pace_cache_dir/session-testpace" 2>/dev/null)"
assert_contains "pace=ahead written to session cache" "pace=ahead" "$_cache_pace"
unset _pace_r30 _pace_r1

# ── Cron segment tests ────────────────────────────────────────────────────────
# cron segment: renders ⏰ <relative> when next_cron_at is in the future
# session_id "slcrontest1" → first 8 chars = "slcrontest"[:8] = "slcrontest"
# Actually "slcrontest1"[0:8] = "slcronte" — cache file = session-slcronte
_cron_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_cron_cfg_dir")
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

# ── lost-update race: a stop-hook write MID-RENDER must survive ──────────────
# The old read-modify-write clobbered next_cron_at/bg_tasks written between the
# early cache snapshot and the mv (the FIXME(race) this replaces). The test
# seam injects a foreign write at exactly that point; merge-on-write must pick
# the fresh values up instead of writing back the stale snapshot.
_race_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_race_cache")
_race_stale=$(( $(date +%s) + 100 ))
_race_fresh=$(( $(date +%s) + 9000 ))
printf 'model=Sonnet\nnext_cron_at=%s\nbg_tasks=1\n' "$_race_stale" \
  > "$_race_cache/session-slrace11"
_race_inject="printf 'model=Sonnet\nnext_cron_at=${_race_fresh}\nbg_tasks=7\n' > '$_race_cache/session-slrace11'"
echo '{"session_id":"slrace11xxxx","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":20,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"cost":{"total_cost_usd":0.05}}' \
  | CLAUDII_CACHE_DIR="$_race_cache" CLAUDII_TEST_MID_RENDER_CMD="$_race_inject" bash "$SL" 2>/dev/null >/dev/null
_race_after="$(cat "$_race_cache/session-slrace11" 2>/dev/null)"
assert_contains "race: mid-render hook write of next_cron_at survives" "next_cron_at=${_race_fresh}" "$_race_after"
assert_contains "race: mid-render hook write of bg_tasks survives" "bg_tasks=7" "$_race_after"
assert_not_contains "race: stale snapshot value is gone" "next_cron_at=${_race_stale}" "$_race_after"
unset _race_cache _race_stale _race_fresh _race_inject _race_after
assert_contains "cron: cc-statusline preserves bg_tasks on rewrite" "bg_tasks=1" "$_preserved"

# ── bg-tasks segment tests ────────────────────────────────────────────────────
# bg-tasks segment: renders ⚙ Nbg when bg_tasks >= 1 in cache
_bgt_cfg_dir="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_bgt_cfg_dir")
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

# Every config here puts `clock` in the layout, because that is now what makes
# the delegation happen at all: cc-insomnii is a ~20-fork child whose output is
# only ever read by the clock segment, so it is layout-gated like every other
# fork owner. No shipped layout or preset contains `clock` (the focused preset
# says so explicitly — cc-insomnii prepends its own line via the --after
# wrapper), which is exactly why the ungated version was pure waste for
# everyone who had cc-insomnii on PATH.
printf '{"statusline":{"shame":false,"lines":[["clock"]]}}\n' > "$_ins_dir/cfg/claudii/config.json"
echo '{"model":{"display_name":"Opus"}}' \
  | CLAUDII_TEST_INSOMNII_OUT="$_ins_dir/env.out" PATH="$_ins_dir/bin:$PATH" \
    XDG_CONFIG_HOME="$_ins_dir/cfg" bash "$SL" >/dev/null 2>&1
_ins_env=$(cat "$_ins_dir/env.out" 2>/dev/null)
assert_contains "insomnii env: explicit shame=false forwarded" "shame=false" "$_ins_env"
assert_contains "insomnii env: motivation defaults to true"    "motivation=true" "$_ins_env"

# Regression 2, reachable half: a valid layout that simply omits the three
# keys must forward the pre-seeded "true" defaults, not empty strings.
printf '{"statusline":{"lines":[["clock"]]}}\n' > "$_ins_dir/cfg/claudii/config.json"
rm -f "$_ins_dir/env.out"
echo '{"model":{"display_name":"Opus"}}' \
  | CLAUDII_TEST_INSOMNII_OUT="$_ins_dir/env.out" PATH="$_ins_dir/bin:$PATH" \
    XDG_CONFIG_HOME="$_ins_dir/cfg" bash "$SL" >/dev/null 2>&1
_ins_env=$(cat "$_ins_dir/env.out" 2>/dev/null)
assert_contains "insomnii env: absent keys fall back to shame=true"   "shame=true" "$_ins_env"
assert_contains "insomnii env: absent keys fall back to rainbow=true" "rainbow=true" "$_ins_env"
# The same three switches are declared in config/defaults.json, so
# `claudii config get` reports what the renderer forwards instead of nothing.
assert_eq "insomnii switches: defaults.json declares all three as true" "true true true" \
  "$(jq -r '.statusline | "\(.shame) \(.motivation) \(.rainbow)"' "$CLAUDII_HOME/config/defaults.json")"
assert_eq "insomnii switches: config get falls back to the default" "true" \
  "$(HOME="$_ins_dir" XDG_CONFIG_HOME="$_ins_dir/cfg" CLAUDII_CACHE_DIR="$_ins_dir/cache" \
     bash "$CLAUDII_HOME/bin/claudii" config get statusline.motivation 2>/dev/null)"

# Regression 2, other half: a corrupt config no longer reaches cc-insomnii at
# all. The failed jq leaves the layout at the shipped default, which has no
# `clock`, so the gate skips the child rather than forwarding blanked defaults
# to it. Asserting the absence keeps the coupling visible — if `clock` ever
# joins the default layout, this goes red and the blanked-defaults regression
# needs its old guard back.
printf 'NOT JSON\n' > "$_ins_dir/cfg/claudii/config.json"
rm -f "$_ins_dir/env.out"
echo '{"model":{"display_name":"Opus"}}' \
  | CLAUDII_TEST_INSOMNII_OUT="$_ins_dir/env.out" PATH="$_ins_dir/bin:$PATH" \
    XDG_CONFIG_HOME="$_ins_dir/cfg" bash "$SL" >/dev/null 2>&1
assert_eq "insomnii: corrupt config → default layout → no delegation" "absent" \
  "$([[ -f "$_ins_dir/env.out" ]] && echo present || echo absent)"
unset _ins_dir _ins_env

# ── Auto-compact aware context bar (CLAUDE_CODE_AUTO_COMPACT_WINDOW) ─────────
# Default (unset, see top of file): 200k window → scale 83, override wins below.
_ac_json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":40,"total_input_tokens":1000,"total_output_tokens":100,"context_window_size":200000},"cost":{"total_cost_usd":0.10}}'

# Fraction form: 0.9 → scale 90 → 40*100/90 = 44%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=0.9 bash "$SL" 2>&1)
assert_contains "auto-compact fraction 0.9 scales bar" "44%" "$output"

# Token-count form: 100000 of 200000 → fraction 0.5 → 40*100/50 = 80%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000 bash "$SL" 2>&1)
assert_contains "auto-compact token count scales bar" "80%" "$output"

# Garbage value → model default (200k → scale 83) → 40*100/83 = 48%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=banana bash "$SL" 2>&1)
assert_contains "auto-compact garbage falls back to model default" "48%" "$output"

# Clamp: fraction 0.2 clamps to 0.5 → 40*100/50 = 80%
output=$(echo "$_ac_json" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=0.2 bash "$SL" 2>&1)
assert_contains "auto-compact low fraction clamps to 0.5" "80%" "$output"

# Token count without window size → inferred 1M window (opus) → scale 96 → 41%
_ac_nown='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":40,"total_input_tokens":1000,"total_output_tokens":100},"cost":{"total_cost_usd":0.10}}'
output=$(echo "$_ac_nown" | CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000 bash "$SL" 2>&1)
assert_contains "auto-compact token count w/o window size falls back" "41%" "$output"
unset _ac_json _ac_nown

# ── Model-aware practical-window scale (mirrors reflect-nudge FLOOR rule) ─────
# The compact point is window − 33k (measured; see the scale comment in the
# binary): 1M → 967k → scale 96, 200k → 167k → scale 83. Only the legacy
# 195k FLOOR (sonnet[1m]) undercuts it.
output=$(echo '{"model":{"display_name":"Opus","id":"claude-opus-4-8"},"context_window":{"used_percentage":40,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: opus/1M uses 96% scale (40%→41%)" "41%" "$output"
# Sonnet 5 and Fable 5 ship 1M as their default, flat-billed window — same
# full-window floor as opus, not the legacy sonnet[1m] 195k habit ceiling.
# (CC v2.1.247 aligned Sonnet 5's auto-compact with the other 1M models at
# ~967K — the same window − 33k edge.)
output=$(echo '{"model":{"display_name":"Sonnet 5","id":"claude-sonnet-5"},"context_window":{"used_percentage":40,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet-5/1M uses 96% scale (40%→41%)" "41%" "$output"
# …and at the real edge the bar reads full: raw 96% → 96*100/96 = 100%.
output=$(echo '{"model":{"display_name":"Sonnet 5","id":"claude-sonnet-5"},"context_window":{"used_percentage":96,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet-5 at raw 96% reads full (100%)" "100%" "$output"
output=$(echo '{"model":{"display_name":"Fable 5","id":"claude-fable-5"},"context_window":{"used_percentage":40,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: fable-5/1M uses 96% scale (40%→41%)" "41%" "$output"
output=$(echo '{"model":{"display_name":"Sonnet","id":"claude-sonnet-4-6"},"context_window":{"used_percentage":40,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet/200k uses 83% scale (40%→48%)" "48%" "$output"
# Sonnet 4.6 bills flat but opens at 200k: with no context_window_size the
# window is inferred as 200k (83% scale), not 1M — both by id and by name.
output=$(echo '{"model":{"display_name":"Sonnet 4.6","id":"claude-sonnet-4-6"},"context_window":{"used_percentage":40,"total_input_tokens":1,"total_output_tokens":1},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet-4-6 without window size infers 200k (40%→48%)" "48%" "$output"
output=$(echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":40,"total_input_tokens":1,"total_output_tokens":1},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: display name Sonnet 4.6 infers 200k (40%→48%)" "48%" "$output"
# On its 1M window Sonnet 4.6 gets the full-window floor, not the 195k ceiling:
# raw 20% → 20*100/96 = 20%, not the clamped 100% of a legacy sonnet[1m].
output=$(echo '{"model":{"display_name":"Sonnet 4.6","id":"claude-sonnet-4-6[1m]"},"context_window":{"used_percentage":20,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet-4-6[1m] skips the 195k floor (20%→20%)" "20%" "$output"
assert_not_contains "model-aware: sonnet-4-6[1m] does not read full" "100%" "$output"

# The only changed case: a non-opus 1M window (sonnet[1m]) hits the 195k FLOOR,
# so scale = 195000/1000000 = 19.5 → 19. The bar fills near 195k, not 800k.
#   raw 5% (=50k of 1M) → 5*100/19 = 26% (still room; well before the floor)
output=$(echo '{"model":{"display_name":"Sonnet","id":"claude-sonnet-4-5[1m]"},"context_window":{"used_percentage":5,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet[1m] raw 5% scales to 26%" "26%" "$output"
#   raw 20% (=200k of 1M, past the 195k floor) → 20*100/19 = 105 → clamped 100%
output=$(echo '{"model":{"display_name":"Sonnet","id":"claude-sonnet-4-5[1m]"},"context_window":{"used_percentage":20,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: sonnet[1m] past 195k floor reads full (100%)" "100%" "$output"
# Contrast: opus/1M at the same raw 20% is still early (20*100/96 = 20%).
output=$(echo '{"model":{"display_name":"Opus","id":"claude-opus-4-8[1m]"},"context_window":{"used_percentage":20,"total_input_tokens":1,"total_output_tokens":1,"context_window_size":1000000},"cost":{"total_cost_usd":0.1}}' | bash "$SL" 2>&1)
assert_contains "model-aware: opus/1M at raw 20% stays early (20%)" "20%" "$output"

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

# ── remotes segment — git remote classification (fj / gh / local) ───────────
# Each case builds a throwaway git repo with specific remotes, points the
# statusline at it via cwd, and checks the rendered fj/gh/local tags. The
# segment forks `git remote -v` against cwd, so a real repo is required.
# Repos live in the SYSTEM temp dir, never under $CLAUDII_HOME — a repo nested
# inside claudii's own tree would let git's upward .git discovery resolve to
# claudii's remotes (fj+gh) and mask every assertion. An empty --template dir
# skips the sample-hook copy that the macOS sandbox denies (clonefile EPERM).
_rm_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_rm_cfg")
mkdir -p "$_rm_cfg/claudii"
printf '{"statusline":{"lines":[["remotes"]]}}\n' > "$_rm_cfg/claudii/config.json"
_rm_tpl="$(mktemp -d)"; _SL_TMPDIRS+=("$_rm_tpl")  # empty git template (no hooks)

_rm_init() { _SL_TMPDIRS+=("$1"); git init -q --template="$_rm_tpl" "$1"; }
_rm_run() {  # $1 = repo dir → echoes stripped statusline output
  echo "{\"model\":{\"display_name\":\"Opus\"},\"cwd\":\"$1\",\"context_window\":{\"used_percentage\":10,\"total_input_tokens\":1000,\"total_output_tokens\":200,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.05}}" \
    | XDG_CONFIG_HOME="$_rm_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}

# Both forgejo (self-hosted) origin + github mirror → fj·gh
_rm_both="$(mktemp -d)"; _rm_init "$_rm_both"
git -C "$_rm_both" remote add origin https://git.example.com/acme/claudii.git
git -C "$_rm_both" remote add github https://github.com/bmmmm/claudii.git
_rm_strip="$(_rm_run "$_rm_both")"
assert_contains "remotes both: joined fj·gh" "fj·gh" "$_rm_strip"

# GitHub only → gh, no fj
_rm_gh="$(mktemp -d)"; _rm_init "$_rm_gh"
git -C "$_rm_gh" remote add origin git@github.com:bmmmm/claudii.git
_rm_strip="$(_rm_run "$_rm_gh")"
assert_contains "remotes github-only: gh tag" "gh" "$_rm_strip"
assert_eq "remotes github-only: no fj tag" "0" "$(echo "$_rm_strip" | grep -c 'fj' || true)"

# Forgejo / self-hosted only → fj, no gh
_rm_fj="$(mktemp -d)"; _rm_init "$_rm_fj"
git -C "$_rm_fj" remote add origin https://git.example.com/acme/claudii.git
_rm_strip="$(_rm_run "$_rm_fj")"
assert_contains "remotes forgejo-only: fj tag" "fj" "$_rm_strip"
assert_eq "remotes forgejo-only: no gh tag" "0" "$(echo "$_rm_strip" | grep -c 'gh' || true)"

# No remotes → local
_rm_local="$(mktemp -d)"; _rm_init "$_rm_local"
_rm_strip="$(_rm_run "$_rm_local")"
assert_contains "remotes none: local tag" "local" "$_rm_strip"

# Non-git directory → segment omitted (no fj/gh/local)
_rm_plain="$(mktemp -d)"; _SL_TMPDIRS+=("$_rm_plain")
_rm_strip="$(_rm_run "$_rm_plain")"
assert_eq "remotes non-git: no local tag" "0" "$(echo "$_rm_strip" | grep -c 'local' || true)"
unset -f _rm_init _rm_run; unset _rm_strip

# ── git-sync segment — working-copy sync state (dirty / ahead / behind) ──────
# Same throwaway-repo discipline as the remotes block: repos live in the SYSTEM
# temp dir (a repo under $CLAUDII_HOME would let git's upward .git discovery
# resolve to claudii's own tree), with an empty --template to skip sample hooks.
# Upstream tracking is faked with remote="." (the repo as its own remote) +
# branch.main.merge → a local 'up' branch, so ahead/behind need no network/clone.
_gs_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_gs_cfg")
mkdir -p "$_gs_cfg/claudii"
printf '{"statusline":{"lines":[["git-sync"]]}}\n' > "$_gs_cfg/claudii/config.json"
_gs_tpl="$(mktemp -d)"; _SL_TMPDIRS+=("$_gs_tpl")
_gs_ci() { git -C "$1" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m "$2"; }
_gs_mkrepo() {  # $1 = dir → repo with 1 commit on main + a tracked 'up' upstream
  _SL_TMPDIRS+=("$1")
  git init -q --template="$_gs_tpl" -b main "$1"
  _gs_ci "$1" A
  git -C "$1" branch up
  git -C "$1" config branch.main.remote .
  git -C "$1" config branch.main.merge refs/heads/up
}
_gs_run() {  # $1 = repo dir → echoes stripped statusline output
  echo "{\"model\":{\"display_name\":\"Opus\"},\"cwd\":\"$1\",\"context_window\":{\"used_percentage\":10,\"total_input_tokens\":1000,\"total_output_tokens\":200,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.05}}" \
    | XDG_CONFIG_HOME="$_gs_cfg" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}

# Clean + in sync → green ✓
_gs_clean="$(mktemp -d)"; _gs_mkrepo "$_gs_clean"
assert_contains "git-sync clean+synced → ✓" "✓" "$(_gs_run "$_gs_clean")"

# Uncommitted change (untracked file) → ●1, no ✓
_gs_dirty="$(mktemp -d)"; _gs_mkrepo "$_gs_dirty"
printf 'x\n' > "$_gs_dirty/newfile"
_gs_d_strip="$(_gs_run "$_gs_dirty")"
assert_contains "git-sync dirty → ●1" "●1" "$_gs_d_strip"
assert_eq "git-sync dirty → no ✓" "0" "$(echo "$_gs_d_strip" | grep -c '✓' || true)"

# One unpushed commit (main ahead of up) → ↑1
_gs_ahead="$(mktemp -d)"; _gs_mkrepo "$_gs_ahead"; _gs_ci "$_gs_ahead" B
assert_contains "git-sync ahead → ↑1" "↑1" "$(_gs_run "$_gs_ahead")"

# One unpulled commit (up ahead of main) → ↓1
_gs_behind="$(mktemp -d)"; _gs_mkrepo "$_gs_behind"
git -C "$_gs_behind" checkout -q up; _gs_ci "$_gs_behind" B; git -C "$_gs_behind" checkout -q main
assert_contains "git-sync behind → ↓1" "↓1" "$(_gs_run "$_gs_behind")"

# Non-git directory → segment empty → no output line at all
_gs_plain="$(mktemp -d)"; _SL_TMPDIRS+=("$_gs_plain")
assert_eq "git-sync non-git → empty output" "" "$(_gs_run "$_gs_plain")"
unset -f _gs_ci _gs_mkrepo _gs_run; unset _gs_d_strip

# ── sessions segment — concurrent same-repo live sessions (⚠N) ───────────────
# The segment scans the per-session cache for OTHER active sessions whose
# project_path resolves to the same repo root as this render's cwd. Each case
# pre-seeds a sibling session-* cache file (a live ppid = the test's own $$, a
# matching ppid_lstart, a project_path) and asserts the ⚠ count. The current
# render's own row is written under a distinct session id and skipped.
_ss_cfg="$(mktemp -d "$CLAUDII_TEST_TMP/XXXXXX")"; _SL_TMPDIRS+=("$_ss_cfg")
mkdir -p "$_ss_cfg/claudii"
printf '{"statusline":{"lines":[["model","sessions"]]}}\n' > "$_ss_cfg/claudii/config.json"
# Trimmed lstart of a live pid — mirrors the write-side trim in the statusline
# and the compare-side trim in _parse_session_cache.
_ss_lstart() { local _l; _l=$(ps -o lstart= -p "$1" 2>/dev/null); _l="${_l#"${_l%%[![:space:]]*}"}"; printf '%s' "$_l"; }
# Write a sibling session cache file. Args: cachedir, name, project_path, ppid, lstart
_ss_sib() {
  printf 'model=Sonnet\nsession_id=%s\nproject_path=%s\nppid=%s\nppid_lstart=%s\n' \
    "$2" "$3" "$4" "$5" > "$1/session-$2"
}
# Run the statusline against a cwd + cache dir; echoes stripped output.
_ss_run() {  # $1 = cwd, $2 = cachedir
  echo "{\"session_id\":\"selfrender0001\",\"model\":{\"display_name\":\"Opus\"},\"cwd\":\"$1\",\"context_window\":{\"used_percentage\":10,\"total_input_tokens\":1000,\"total_output_tokens\":200,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0.05}}" \
    | XDG_CONFIG_HOME="$_ss_cfg" CLAUDII_CACHE_DIR="$2" bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}
_ss_live_lstart="$(_ss_lstart "$$")"

# (a) sibling with same project_path + live ppid → ⚠1
_ss_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_cache")
_ss_proj="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_proj")
_ss_sib "$_ss_cache" "sibsame1" "$_ss_proj" "$$" "$_ss_live_lstart"
assert_contains "sessions: same-project live sibling → ⚠1" "⚠1" "$(_ss_run "$_ss_proj" "$_ss_cache")"

# (b) sibling in a worktree UNDER the same repo → counted (normalized match)
_ss_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_cache")
_ss_proj="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_proj")
_ss_sib "$_ss_cache" "sibwt1" "$_ss_proj/.claude/worktrees/agent-x" "$$" "$_ss_live_lstart"
assert_contains "sessions: worktree sibling under same repo → ⚠1" "⚠1" "$(_ss_run "$_ss_proj" "$_ss_cache")"

# (c) sibling from a DIFFERENT project → not counted
_ss_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_cache")
_ss_proj="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_proj")
_ss_other="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_other")
_ss_sib "$_ss_cache" "sibother1" "$_ss_other" "$$" "$_ss_live_lstart"
assert_not_contains "sessions: different project → no ⚠" "⚠" "$(_ss_run "$_ss_proj" "$_ss_cache")"

# (d) sibling with a dead ppid → not counted
_ss_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_cache")
_ss_proj="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_proj")
_ss_sib "$_ss_cache" "sibdead1" "$_ss_proj" "999999" ""
assert_not_contains "sessions: dead-pid sibling → no ⚠" "⚠" "$(_ss_run "$_ss_proj" "$_ss_cache")"

# (e) recycled-pid: live ppid but a MISMATCHED ppid_lstart → not counted (F4)
_ss_cache="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_cache")
_ss_proj="$(mktemp -d)"; _SL_TMPDIRS+=("$_ss_proj")
_ss_sib "$_ss_cache" "sibrecyc1" "$_ss_proj" "$$" "Wed Jan  1 00:00:00 2000"
assert_not_contains "sessions: recycled pid (lstart mismatch) → no ⚠" "⚠" "$(_ss_run "$_ss_proj" "$_ss_cache")"

unset -f _ss_lstart _ss_sib _ss_run; unset _ss_cfg _ss_cache _ss_proj _ss_other _ss_live_lstart
