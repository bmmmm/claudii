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
cp "$CLAUDII_HOME/config/defaults.json" "$SESSION_BAR_TMP/config/claudii/config.json"
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
      _claudii_dashboard
      printf '%s' \"\$_CLAUDII_LAST_TITLE\"
    " 2>/dev/null
  )
  assert_eq "session bar: dead PID → title not set" "" "$zsh_session_bar"
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
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_contains "session bar: live PID → bar shown with model name" "Sonnet" "$zsh_session_bar_live"

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

# ── Gap 3 — Multi-session dashboard ───────────────────────────────────────
MULTI_TMP="$CLAUDII_HOME/tmp/test_statusline_multi"
rm -rf "$MULTI_TMP"
mkdir -p "$MULTI_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$MULTI_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$MULTI_TMP/status-models"
_live_pid=$$
# Three live sessions — Opus, Sonnet, Haiku
printf 'model=Opus\nctx_pct=30\ncost=2.10\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=ms1\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$MULTI_TMP/session-ms1"
printf 'model=Sonnet\nctx_pct=55\ncost=0.80\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=ms2\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$MULTI_TMP/session-ms2"
printf 'model=Haiku\nctx_pct=10\ncost=0.05\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=ms3\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$MULTI_TMP/session-ms3"
multi_result=$(
  CLAUDII_CACHE_DIR="$MULTI_TMP" XDG_CONFIG_HOME="$MULTI_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_contains "multi-session: Opus shown in title" "Opus" "$multi_result"
assert_contains "multi-session: Sonnet shown in title" "Sonnet" "$multi_result"
assert_contains "multi-session: Haiku shown in title" "Haiku" "$multi_result"
rm -rf "$MULTI_TMP"
unset MULTI_TMP multi_result

# ── Gap 5 — Dashboard disabled ────────────────────────────────────────────
DASH_OFF_TMP="$CLAUDII_HOME/tmp/test_statusline_dash_off"
rm -rf "$DASH_OFF_TMP"
mkdir -p "$DASH_OFF_TMP/config/claudii"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$DASH_OFF_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=offtest\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$DASH_OFF_TMP/session-offtest"
dash_off_result=$(
  CLAUDII_CACHE_DIR="$DASH_OFF_TMP" XDG_CONFIG_HOME="$DASH_OFF_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    # Create config with dashboard.enabled = \"off\"
    jq '.dashboard.enabled = \"off\"' \"\$CLAUDII_HOME/config/defaults.json\" \
      > \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_eq "dashboard disabled: _CLAUDII_LAST_TITLE is empty" "" "$dash_off_result"
rm -rf "$DASH_OFF_TMP"
unset DASH_OFF_TMP dash_off_result

# ── OSC2 Title rendering tests ─────────────────────────────────────────────
# Shared tmp dir for all title tests.
TITLE_TMP="$CLAUDII_HOME/tmp/test_statusline_title"
rm -rf "$TITLE_TMP"
mkdir -p "$TITLE_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$TITLE_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$TITLE_TMP/status-models"
_live_pid=$$
_now=$(date +%s)
_reset_5h=$(( _now + 10800 ))
_reset_7d=$(( _now + 604800 ))
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=50\nrate_7d=6\nreset_5h=%s\nreset_7d=%s\nsession_id=titletest\ncache_pct=21\nworktree=\nagent=\nmodel_id=\nburn_eta=\nrate_7d_start=\nppid=%s\n' \
  "$_reset_5h" "$_reset_7d" "$_live_pid" \
  > "$TITLE_TMP/session-titletest"

# 1. PROMPT unchanged (no embedding)
title_prompt=$(
  CLAUDII_CACHE_DIR="$TITLE_TMP" XDG_CONFIG_HOME="$TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
title_user_prompt=$(
  CLAUDII_CACHE_DIR="$TITLE_TMP" XDG_CONFIG_HOME="$TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    printf '%s' \"\$_CLAUDII_USER_PROMPT\"
  " 2>/dev/null
)
assert_eq "dashboard: PROMPT unchanged (no embedding)" "$title_user_prompt" "$title_prompt"

# 2. title contains model name
title_val=$(
  CLAUDII_CACHE_DIR="$TITLE_TMP" XDG_CONFIG_HOME="$TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_contains "dashboard: title contains model name" "Sonnet" "$title_val"

# 3. title contains ctx%
assert_contains "dashboard: title contains ctx%" "42%" "$title_val"

# 4. title contains cost
assert_contains "dashboard: title contains cost" "\$0.55" "$title_val"

# 5. title contains cache %
assert_contains "dashboard: title contains cache %" "⚡21%" "$title_val"

# 6. title contains 5h rate
assert_contains "dashboard: title contains 5h rate" "5h:50%" "$title_val"

# 7. title contains reset countdown
assert_contains "dashboard: title contains reset countdown" "↺" "$title_val"

# 8. title contains 7d rate
assert_contains "dashboard: title contains 7d rate" "7d:6%" "$title_val"

# 9. title no ANSI codes — use grep -F for literal match; exit 1 means no match → 0
ansi_count=0
printf '%s' "$title_val" | grep -qF $'\033[' 2>/dev/null && ansi_count=1
assert_eq "dashboard: title no ANSI codes" "0" "$ansi_count"

# 10. title no zsh prompt codes — grep -q returns 1 on no match
zsh_code_count=0
printf '%s' "$title_val" | grep -qF '%F{' 2>/dev/null && zsh_code_count=1
assert_eq "dashboard: title no zsh prompt codes (%F{)" "0" "$zsh_code_count"
zsh_code_f=0
printf '%s' "$title_val" | grep -qF '%f' 2>/dev/null && zsh_code_f=1
assert_eq "dashboard: title no zsh prompt codes (%f)" "0" "$zsh_code_f"
zsh_code_b=0
printf '%s' "$title_val" | grep -qF '%B' 2>/dev/null && zsh_code_b=1
assert_eq "dashboard: title no zsh prompt codes (%B)" "0" "$zsh_code_b"

# 11. disabled → _CLAUDII_LAST_TITLE empty
title_off=$(
  CLAUDII_CACHE_DIR="$TITLE_TMP" XDG_CONFIG_HOME="$TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    jq '.dashboard.enabled = \"off\"' \"\$CLAUDII_HOME/config/defaults.json\" \
      > \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_eq "dashboard: disabled → _CLAUDII_LAST_TITLE empty" "" "$title_off"

# 12. no sessions → _CLAUDII_LAST_TITLE empty
NO_SESSION_TMP="$CLAUDII_HOME/tmp/test_statusline_nosession"
rm -rf "$NO_SESSION_TMP"
mkdir -p "$NO_SESSION_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$NO_SESSION_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$NO_SESSION_TMP/status-models"
title_nosession=$(
  CLAUDII_CACHE_DIR="$NO_SESSION_TMP" XDG_CONFIG_HOME="$NO_SESSION_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_eq "dashboard: no sessions → _CLAUDII_LAST_TITLE empty" "" "$title_nosession"
rm -rf "$NO_SESSION_TMP"

# 13-16. multi-session title tests
MULTI_TITLE_TMP="$CLAUDII_HOME/tmp/test_statusline_multititle"
rm -rf "$MULTI_TITLE_TMP"
mkdir -p "$MULTI_TITLE_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$MULTI_TITLE_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$MULTI_TITLE_TMP/status-models"
_live_pid=$$
printf 'model=Opus\nctx_pct=30\ncost=2.10\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=mst1\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$MULTI_TITLE_TMP/session-mst1"
printf 'model=Sonnet\nctx_pct=55\ncost=0.80\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=mst2\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$MULTI_TITLE_TMP/session-mst2"
printf 'model=Haiku\nctx_pct=10\ncost=0.05\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=mst3\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$MULTI_TITLE_TMP/session-mst3"
multi_title=$(
  CLAUDII_CACHE_DIR="$MULTI_TITLE_TMP" XDG_CONFIG_HOME="$MULTI_TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
assert_contains "multi-session: title contains session count" "3 sessions" "$multi_title"
assert_contains "multi-session: Opus shown in title" "Opus" "$multi_title"
assert_contains "multi-session: Sonnet shown in title" "Sonnet" "$multi_title"
assert_contains "multi-session: Haiku shown in title" "Haiku" "$multi_title"
rm -rf "$MULTI_TITLE_TMP"
unset MULTI_TITLE_TMP multi_title

# 17-18. Cache reuse and data change tests
CACHE_TITLE_TMP="$CLAUDII_HOME/tmp/test_statusline_cache_title"
rm -rf "$CACHE_TITLE_TMP"
mkdir -p "$CACHE_TITLE_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$CACHE_TITLE_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CACHE_TITLE_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=cttest\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$CACHE_TITLE_TMP/session-cttest"
cache_title_result=$(
  CLAUDII_CACHE_DIR="$CACHE_TITLE_TMP" XDG_CONFIG_HOME="$CACHE_TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    # Run 1: title set
    _claudii_dashboard
    run1_title=\"\$_CLAUDII_LAST_TITLE\"
    # Run 2: same session data → title unchanged (same string)
    _claudii_dashboard
    run2_title=\"\$_CLAUDII_LAST_TITLE\"
    [[ \"\$run1_title\" == \"\$run2_title\" ]] && printf 'same\\n' || printf 'not_same\\n'
    printf '%s\\n' \"\$run1_title\"
  " 2>/dev/null
)
cache_same=$(echo "$cache_title_result" | sed -n '1p')
assert_eq "dashboard cache: same data → title unchanged between runs" "same" "${cache_same:-}"

# Now change cost and check title changes
printf 'model=Sonnet\nctx_pct=42\ncost=1.23\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=cttest\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$CACHE_TITLE_TMP/session-cttest"
cache_title_change=$(
  CLAUDII_CACHE_DIR="$CACHE_TITLE_TMP" XDG_CONFIG_HOME="$CACHE_TITLE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    # Populate with old title first
    _CLAUDII_LAST_TITLE='Sonnet · 42% · \$0.55'
    # Run with changed data
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_TITLE\"
  " 2>/dev/null
)
# Title with new cost should differ from title with old cost
if [[ "$cache_title_change" == *"1.23"* ]]; then
  assert_eq "dashboard: data change → title updates" "yes" "yes"
else
  assert_eq "dashboard: data change → title updates" "contains 1.23" "$cache_title_change"
fi
rm -rf "$CACHE_TITLE_TMP"
unset CACHE_TITLE_TMP cache_title_result cache_same cache_title_change

# Cleanup TITLE_TMP and ZSH_TMP
rm -rf "$TITLE_TMP"
rm -rf "$ZSH_TMP"

# Cleanup test config (keep status cache for live statusline)
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
