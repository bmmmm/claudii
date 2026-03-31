# test_statusline.sh — statusline rendering for all scenarios
# Simulates per-model status cache and verifies output

TEST_TMP="$CLAUDII_HOME/tmp/test_statusline"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/cache" "$TEST_TMP/config/claudii"
export XDG_CONFIG_HOME="$TEST_TMP/config"
export CLAUDII_CACHE_DIR="$TEST_TMP/cache"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
CACHE_STATUS="$CLAUDII_CACHE_DIR/status-models"

# Helper: write per-model cache and simulate statusline output
_simulate_statusline() {
  local cache_content=$1
  local models_str=$2

  echo "$cache_content" > "$CACHE_STATUS"

  local segments=""
  IFS=',' read -ra models <<< "$models_str"
  for model in "${models[@]}"; do
    model=$(echo "$model" | tr -d ' ')
    label="$(echo "${model:0:1}" | tr '[:lower:]' '[:upper:]')${model:1}"

    if grep -q "^${model}=down" "$CACHE_STATUS" 2>/dev/null; then
      segments+="${label} ↓ "
    elif grep -q "^${model}=degraded" "$CACHE_STATUS" 2>/dev/null; then
      segments+="${label} ~ "
    else
      segments+="${label} ✓ "
    fi
  done
  echo "[${segments% }]"
}

# ── Default: all 3 models ──

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3 models, all ok" "[Opus ✓ Sonnet ✓ Haiku ✓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus down" "[Opus ↓ Sonnet ✓ Haiku ✓]" "$output"

output=$(_simulate_statusline "opus=ok
sonnet=down
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, sonnet down" "[Opus ✓ Sonnet ↓ Haiku ✓]" "$output"

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=down" "opus,sonnet,haiku")
assert_eq "all 3, haiku down" "[Opus ✓ Sonnet ✓ Haiku ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus+sonnet down" "[Opus ↓ Sonnet ↓ Haiku ✓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=down" "opus,sonnet,haiku")
assert_eq "all 3, all down" "[Opus ↓ Sonnet ↓ Haiku ↓]" "$output"

# ── Degraded state ──

output=$(_simulate_statusline "opus=degraded
sonnet=ok
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus degraded" "[Opus ~ Sonnet ✓ Haiku ✓]" "$output"

output=$(_simulate_statusline "opus=degraded
sonnet=down
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus degraded + sonnet down" "[Opus ~ Sonnet ↓ Haiku ✓]" "$output"

# ── Single model: opus only ──

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=ok" "opus")
assert_eq "opus only, ok" "[Opus ✓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "opus")
assert_eq "opus only, down" "[Opus ↓]" "$output"

# ── Two models: opus,sonnet ──

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "opus,sonnet")
assert_eq "opus+sonnet, opus down" "[Opus ↓ Sonnet ✓]" "$output"

output=$(_simulate_statusline "opus=ok
sonnet=down
haiku=ok" "opus,sonnet")
assert_eq "opus+sonnet, sonnet down" "[Opus ✓ Sonnet ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=ok" "opus,sonnet")
assert_eq "opus+sonnet, both down" "[Opus ↓ Sonnet ↓]" "$output"

# ── Reversed order ──

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "sonnet,opus")
assert_eq "reversed order, opus down" "[Sonnet ✓ Opus ↓]" "$output"

# ── Haiku only ──

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=down" "haiku")
assert_eq "haiku only, down" "[Haiku ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=ok" "haiku")
assert_eq "haiku only, others down (haiku ok)" "[Haiku ✓]" "$output"

# ── Config integration ──

bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet" >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config set models to opus,sonnet" "opus,sonnet" "$output"

bash "$CLAUDII_HOME/bin/claudii" config set statusline.enabled false >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.enabled 2>&1)
assert_eq "statusline can be disabled" "false" "$output"

# ── zsh integration: call real _claudii_statusline function ──

ZSH_TMP="$CLAUDII_HOME/tmp/test_statusline_zsh"
rm -rf "$ZSH_TMP"
mkdir -p "$ZSH_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$ZSH_TMP/config/claudii/config.json"

# All ok
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: all ok → Opus in RPROMPT" "Opus" "$zsh_out"
assert_contains "zsh: all ok → Sonnet in RPROMPT" "Sonnet" "$zsh_out"
assert_contains "zsh: all ok → ✓ in RPROMPT" "✓" "$zsh_out"

# Opus down
printf 'opus=down\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: opus down → ↓ in RPROMPT" "↓" "$zsh_out"

# Stale cache → ⟳ indicator
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
touch -t 202001010000 "$ZSH_TMP/status-models"   # set mtime far in the past
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: stale cache → ⟳ in RPROMPT" "⟳" "$zsh_out"

# No cache → […] loading indicator
rm -f "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: no cache → […] in RPROMPT" "…" "$zsh_out"

# Disabled: RPROMPT empty
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    jq '.statusline.enabled = false' \"\$CLAUDII_HOME/config/defaults.json\" \
      > \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_eq "zsh: disabled → RPROMPT empty" "" "$zsh_out"

# Interactive mode: no [N] PID job notification (start or done)
rm -f "$ZSH_TMP/status-models"   # force background spawn
job_leak=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -i -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    # Wait for background job to finish — 'done' notification appears on next
    # prompt after job exit, so we must still be in the shell when it completes
    sleep 3
  " 2>&1 | grep -E '^\[[0-9]+\]' || true
)
assert_eq "zsh -i: no [N] job notification (start or done)" "" "$job_leak"

# ── Session bar: dead PID → bar suppressed ──
# Write a session cache with a PID that no longer exists.
# On any reasonable system, PID 1 is init/launchd — never a Claude process.
# We use a sentinel PID that is guaranteed to be gone: spawn a subshell, grab
# its PID, let it exit, then use that dead PID.
_dead_pid=$(bash -c 'echo $$' 2>/dev/null)
SESSION_BAR_TMP="$CLAUDII_HOME/tmp/test_statusline_sessionbar"
rm -rf "$SESSION_BAR_TMP"
mkdir -p "$SESSION_BAR_TMP/config/claudii"
jq '.dashboard.enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$SESSION_BAR_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$SESSION_BAR_TMP/status-models"
# Write session cache with dead PID — mtime is fresh (now)
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=deadtest\nworktree=\nagent=\nmodel_id=\nburn_eta=\nppid=%s\n' "$_dead_pid" \
  > "$SESSION_BAR_TMP/session-deadtest"
# Verify the PID is actually dead before testing
kill -0 "$_dead_pid" 2>/dev/null && _pid_alive=1 || _pid_alive=0
if (( _pid_alive )); then
  echo "  (skipped: dead PID test — PID $_dead_pid was reused)"
else
  zsh_session_bar=$(
    CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
    zsh -c "
      source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
      _CLAUDII_CMD_RAN=1
      _claudii_dashboard
      printf '%s' \"\$PROMPT\"
    " 2>/dev/null
  )
  assert_eq "session bar: dead PID → bar suppressed" "0" \
    "$(printf '%s' "$zsh_session_bar" | grep -cF 'Sonnet' 2>/dev/null)"
fi

# Session bar: live PID → bar shown
# Use $$ (current test runner's PID) as a guaranteed live process
_live_pid=$$
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=livetest\nworktree=\nagent=\nmodel_id=\nburn_eta=\nppid=%s\n' "$_live_pid" \
  > "$SESSION_BAR_TMP/session-livetest"
# Remove the dead session so only the live one is found
rm -f "$SESSION_BAR_TMP/session-deadtest"
zsh_session_bar_live=$(
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "session bar: live PID → bar shown with model name" "Sonnet" "$zsh_session_bar_live"

# Session bar: live PID with OLD file (>300s) → bar still shown
# Regression for long-running tasks that don't update the session file frequently
_stale_ts=$(date -v-310S +%Y%m%d%H%M.%S 2>/dev/null || date -d "310 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
if [[ -n "$_stale_ts" ]]; then
  printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=staletest\nworktree=\nagent=\nmodel_id=\nburn_eta=\nppid=%s\n' "$_live_pid" \
    > "$SESSION_BAR_TMP/session-staletest"
  touch -t "$_stale_ts" "$SESSION_BAR_TMP/session-staletest"
  rm -f "$SESSION_BAR_TMP/session-livetest"
  zsh_session_stale=$(
    CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
    zsh -c "
      source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
      _CLAUDII_CMD_RAN=1
      _claudii_dashboard
      print -P \"\${(e)PROMPT}\"
    " 2>/dev/null
  )
  assert_contains "session bar: live PID + old file (>300s) → bar still shown" "Sonnet" "$zsh_session_stale"
  rm -f "$SESSION_BAR_TMP/session-staletest"
fi

# reset_5h backfill: session with missing reset_5h gets countdown from sibling session
_live_pid=$$
_reset_future=$(( ${EPOCHSECONDS:-$(date +%s)} + 3360 ))  # 56min from now
printf 'model=Sonnet\nctx_pct=73\ncost=0.50\nrate_5h=83\nreset_5h=\nppid=%s\n' "$_live_pid" \
  > "$SESSION_BAR_TMP/session-noreset"
printf 'model=Sonnet\nctx_pct=17\ncost=0.30\nrate_5h=63\nreset_5h=%s\nppid=%s\n' "$_reset_future" "$_live_pid" \
  > "$SESSION_BAR_TMP/session-withreset"
zsh_reset_backfill=$(
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    print -P \"\${(e)PROMPT}\"
  " 2>/dev/null
)
# Both sessions should show ↺Xm (backfill gives the missing session its sibling's reset time)
_reset_count=$(printf '%s' "$zsh_reset_backfill" | grep -o '↺[0-9]*m' | wc -l | tr -d ' ')
assert_eq "reset_5h backfill: session without reset gets sibling countdown" "2" "$_reset_count"
rm -f "$SESSION_BAR_TMP/session-noreset" "$SESSION_BAR_TMP/session-withreset"
unset _reset_future _reset_count zsh_reset_backfill

# dashboard: PROMPT must not contain save/restore cursor escape sequences
prompt_val=$(
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "dashboard: PROMPT contains no save-cursor ESC[s" "0" \
  "$(printf '%s' "$prompt_val" | grep -cF $'\033[s' || true)"
assert_eq "dashboard: PROMPT contains no restore-cursor ESC[u" "0" \
  "$(printf '%s' "$prompt_val" | grep -cF $'\033[u' || true)"

rm -rf "$SESSION_BAR_TMP"

# ── Conditional rendering tests ──

COND_TMP="$CLAUDII_HOME/tmp/test_statusline_cond"
rm -rf "$COND_TMP"
mkdir -p "$COND_TMP/config/claudii"
jq '.dashboard.enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$COND_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$COND_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=76\ncost=0.66\nrate_5h=28\nreset_5h=\nppid=%s\n' "$_live_pid" \
  > "$COND_TMP/session-condtest"

# 1. CMD_RAN=0 → no dashboard, plain PROMPT
cond_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CMD_RAN=0
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "conditional: CMD_RAN=0 → plain PROMPT, no session lines" "TESTPROMPT> " "$cond_out"

# 2. CMD_RAN=1 → dashboard shown, contains model name
cond_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    print -P \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "conditional: CMD_RAN=1 → dashboard shown with model" "Sonnet" "$cond_out"

# 3. Format test: model, ctx%, cost, 5h-rate all present
format_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    print -P \"\${(e)PROMPT}\"
  " 2>/dev/null
)
assert_contains "dashboard format: contains model name" "Sonnet" "$format_out"
assert_contains "dashboard format: contains ctx%" "76%" "$format_out"
assert_contains "dashboard format: contains cost" "\$0.66" "$format_out"
assert_contains "dashboard format: contains 5h rate" "5h:28%" "$format_out"

# 4. dashboard off → plain PROMPT
off_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CFG_CACHE[dashboard.enabled]=off
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "dashboard off → plain PROMPT" "TESTPROMPT> " "$off_out"

# 5. TRAPWINCH sets CMD_RAN=1
trapwinch_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=0
    TRAPWINCH
    printf '%d' \"\$_CLAUDII_CMD_RAN\"
  " 2>/dev/null
)
assert_eq "TRAPWINCH sets _CLAUDII_CMD_RAN=1" "1" "$trapwinch_out"

rm -rf "$COND_TMP"

# ── Dashboard rate urgency colors ──

RATE_TMP="$CLAUDII_HOME/tmp/test_statusline_rate"
rm -rf "$RATE_TMP"
mkdir -p "$RATE_TMP/config/claudii"
jq '.dashboard.enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$RATE_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$RATE_TMP/status-models"
_live_pid2=$$

# 5h rate >= 80% → %F{red} in dashboard raw PROMPT (before expansion)
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=85\nreset_5h=\nppid=%s\n' "$_live_pid2" \
  > "$RATE_TMP/session-ratetest1"
zsh_rate_red=$(
  CLAUDII_CACHE_DIR="$RATE_TMP" XDG_CONFIG_HOME="$RATE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "dashboard: 5h rate >= 80% → %F{red} in PROMPT" "%F{red}" "$zsh_rate_red"

# 5h rate < 50% → %F{green} in dashboard raw PROMPT (before expansion)
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=30\nreset_5h=\nppid=%s\n' "$_live_pid2" \
  > "$RATE_TMP/session-ratetest2"
rm -f "$RATE_TMP/session-ratetest1"
zsh_rate_green=$(
  CLAUDII_CACHE_DIR="$RATE_TMP" XDG_CONFIG_HOME="$RATE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "dashboard: 5h rate < 50% → %F{green} in PROMPT" "%F{green}" "$zsh_rate_green"

rm -rf "$RATE_TMP"
unset RATE_TMP _live_pid2 zsh_rate_red zsh_rate_green

# ── PROMPT must not contain literal ESC[s (cursor save) ──
ESC_TMP="$CLAUDII_HOME/tmp/test_statusline_esc"
rm -rf "$ESC_TMP"
mkdir -p "$ESC_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$ESC_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ESC_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=50\ncost=0.10\nrate_5h=\nreset_5h=\nppid=%s\n' "$_live_pid" \
  > "$ESC_TMP/session-esctest"
esc_prompt=$(
  CLAUDII_CACHE_DIR="$ESC_TMP" XDG_CONFIG_HOME="$ESC_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
# ESC[s = \033[s — cursor save must not appear in new minimal dashboard
if printf '%s' "$esc_prompt" | grep -qF $'\033[s'; then
  assert_eq "PROMPT must not contain ESC[s (cursor save)" "no ESC[s" "found ESC[s"
else
  assert_eq "PROMPT must not contain ESC[s (cursor save)" "no ESC[s" "no ESC[s"
fi
rm -rf "$ESC_TMP"

rm -rf "$ZSH_TMP"

# Cleanup test config (keep status cache for live statusline)
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
