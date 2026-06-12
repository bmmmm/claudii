# touches: bin/claudii-stop-hook bin/claudii-session-end-hook config/defaults.json
# test_notifications.sh — terminalSequence notifications from claudii hooks

SH="$CLAUDII_HOME/bin/claudii-stop-hook"
SE="$CLAUDII_HOME/bin/claudii-session-end-hook"

_NT_TMPDIRS=()
trap 'rm -rf "${_NT_TMPDIRS[@]}" 2>/dev/null' EXIT

# Helper: isolated cache + config dirs. Sets _nt_cache and _nt_cfg.
_nt_setup() {
  _nt_cache="$(mktemp -d)"; _NT_TMPDIRS+=("$_nt_cache")
  _nt_cfg="$(mktemp -d)";   _NT_TMPDIRS+=("$_nt_cfg")
  mkdir -p "$_nt_cfg/claudii"
}

_ESC=$'\033'
_BEL=$'\007'

# ── 1. Notifications disabled (default) → empty stdout ──────────────────────
_nt_setup
printf '{"notifications":{"enabled":false}}\n' > "$_nt_cfg/claudii/config.json"
printf 'opus=down\nsonnet=ok\n' > "$_nt_cache/status-models"
_nt_out=$(echo '{"session_id":"notif0001"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SH" 2>/dev/null)
assert_eq "notifications disabled: stop-hook stdout empty" "" "$_nt_out"

# No config file at all → also silent (master switch defaults off)
_nt_out=$(echo '{"session_id":"notif0001"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$(mktemp -d)" bash "$SH" 2>/dev/null)
assert_eq "no config file: stop-hook stdout empty" "" "$_nt_out"

# ── 2. Model down → OSC 0 title sequence, valid JSON ─────────────────────────
_nt_setup
printf '{"notifications":{"enabled":true}}\n' > "$_nt_cfg/claudii/config.json"
printf 'opus=down\nsonnet=ok\nhaiku=ok\n' > "$_nt_cache/status-models"
_nt_out=$(echo '{"session_id":"notif0002"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SH" 2>/dev/null)
_nt_jq_rc=$(jq -e '.terminalSequence' <<< "$_nt_out" >/dev/null 2>&1; echo $?)
assert_eq "model down: output is valid JSON with terminalSequence" "0" "$_nt_jq_rc"
_nt_seq=$(jq -r '.terminalSequence' <<< "$_nt_out" 2>/dev/null)
assert_contains "model down: OSC 0 title with model name" "${_ESC}]0;[!opus down] claude${_BEL}" "$_nt_seq"

# model_down toggled off → silent even though a model is down
printf '{"notifications":{"enabled":true,"model_down":false}}\n' > "$_nt_cfg/claudii/config.json"
_nt_out=$(echo '{"session_id":"notif0002"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SH" 2>/dev/null)
assert_eq "model_down=false: stop-hook stdout empty" "" "$_nt_out"

# ── 3. Burn-ETA below threshold → BEL + title ────────────────────────────────
_nt_setup
printf '{"notifications":{"enabled":true,"burn_eta_threshold_min":30}}\n' > "$_nt_cfg/claudii/config.json"
printf 'cost=1.23\nburn_eta=12\n' > "$_nt_cache/session-notif000"
_nt_out=$(echo '{"session_id":"notif0003xyz"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SH" 2>/dev/null)
_nt_seq=$(jq -r '.terminalSequence' <<< "$_nt_out" 2>/dev/null)
assert_contains "burn-eta critical: BEL present" "$_BEL" "$_nt_seq"
assert_contains "burn-eta critical: minutes in title" "12m to limit" "$_nt_seq"

# ETA above threshold → silent
printf 'cost=1.23\nburn_eta=120\n' > "$_nt_cache/session-notif000"
_nt_out=$(echo '{"session_id":"notif0003xyz"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SH" 2>/dev/null)
assert_eq "burn-eta above threshold: stdout empty" "" "$_nt_out"

# ── 4. Stop-hook cache-write behavior unchanged with notifications on ────────
_nt_setup
printf '{"notifications":{"enabled":true}}\n' > "$_nt_cfg/claudii/config.json"
_nt_future=$(( $(date +%s) + 3600 ))
echo "{\"session_id\":\"notif0004\",\"session_crons\":[{\"next_run_at\":${_nt_future}}],\"background_tasks\":[{\"id\":\"t1\"}]}" \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SH" >/dev/null 2>&1
_nt_cachefile=$(cat "$_nt_cache/session-notif000" 2>/dev/null)
assert_contains "cache write unchanged: next_cron_at" "next_cron_at=${_nt_future}" "$_nt_cachefile"
assert_contains "cache write unchanged: bg_tasks" "bg_tasks=1" "$_nt_cachefile"

# ── 5. Session-end → OSC 777 notification with cost ─────────────────────────
_nt_setup
printf '{"notifications":{"enabled":true}}\n' > "$_nt_cfg/claudii/config.json"
printf 'cost=2.5\nmodel=Opus\n' > "$_nt_cache/session-notif000"
_nt_out=$(echo '{"session_id":"notif0005abc","reason":"logout"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SE" 2>/dev/null)
_nt_jq_rc=$(jq -e '.terminalSequence' <<< "$_nt_out" >/dev/null 2>&1; echo $?)
assert_eq "session-end: output is valid JSON" "0" "$_nt_jq_rc"
_nt_seq=$(jq -r '.terminalSequence' <<< "$_nt_out" 2>/dev/null)
assert_contains "session-end: OSC 777 notify" "${_ESC}]777;notify;claudii;" "$_nt_seq"
assert_contains "session-end: cost formatted" 'cost $2.50' "$_nt_seq"

# OSC 9 flavor
printf '{"notifications":{"enabled":true,"osc":"9"}}\n' > "$_nt_cfg/claudii/config.json"
_nt_out=$(echo '{"session_id":"notif0005abc"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SE" 2>/dev/null)
_nt_seq=$(jq -r '.terminalSequence' <<< "$_nt_out" 2>/dev/null)
assert_contains "session-end: OSC 9 flavor" "${_ESC}]9;claudii:" "$_nt_seq"

# No cached cost → generic body, still valid
printf '{"notifications":{"enabled":true}}\n' > "$_nt_cfg/claudii/config.json"
_nt_out=$(echo '{"session_id":"notifNOCACHE"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SE" 2>/dev/null)
_nt_seq=$(jq -r '.terminalSequence' <<< "$_nt_out" 2>/dev/null)
assert_contains "session-end: no cost → generic body" "session ended" "$_nt_seq"

# session_end toggled off → silent, exit 0
printf '{"notifications":{"enabled":true,"session_end":false}}\n' > "$_nt_cfg/claudii/config.json"
_nt_rc=$(echo '{"session_id":"notif0005abc"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SE" >/dev/null 2>&1; echo $?)
_nt_out=$(echo '{"session_id":"notif0005abc"}' \
  | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" bash "$SE" 2>/dev/null)
assert_eq "session-end disabled: exit 0" "0" "$_nt_rc"
assert_eq "session-end disabled: stdout empty" "" "$_nt_out"

# ── 6. macOS /bin/bash 3.2 regression — scripts run under the system bash ────
if [[ -x /bin/bash ]]; then
  _nt_setup
  printf '{"notifications":{"enabled":true}}\n' > "$_nt_cfg/claudii/config.json"
  printf 'opus=down\n' > "$_nt_cache/status-models"
  _nt_out=$(echo '{"session_id":"notif0006"}' \
    | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" /bin/bash "$SH" 2>/dev/null)
  _nt_jq_rc=$(jq -e '.terminalSequence' <<< "$_nt_out" >/dev/null 2>&1; echo $?)
  assert_eq "system bash 3.2: stop-hook emits valid JSON" "0" "$_nt_jq_rc"
  printf 'cost=0.75\n' > "$_nt_cache/session-notif000"
  _nt_out=$(echo '{"session_id":"notif0006xx"}' \
    | CLAUDII_CACHE_DIR="$_nt_cache" XDG_CONFIG_HOME="$_nt_cfg" /bin/bash "$SE" 2>/dev/null)
  _nt_jq_rc=$(jq -e '.terminalSequence' <<< "$_nt_out" >/dev/null 2>&1; echo $?)
  assert_eq "system bash 3.2: session-end-hook emits valid JSON" "0" "$_nt_jq_rc"
fi

# ── 7. defaults.json ships the notifications block (master off) ─────────────
_nt_def=$(jq -r '.notifications.enabled' "$CLAUDII_HOME/config/defaults.json" 2>/dev/null)
assert_eq "defaults.json: notifications.enabled is false" "false" "$_nt_def"
_nt_def=$(jq -r '.notifications.osc' "$CLAUDII_HOME/config/defaults.json" 2>/dev/null)
assert_eq "defaults.json: notifications.osc default 777" "777" "$_nt_def"

unset _NT_TMPDIRS _nt_cache _nt_cfg _nt_out _nt_seq _nt_jq_rc _nt_rc _nt_def \
      _nt_future _nt_cachefile _ESC _BEL
