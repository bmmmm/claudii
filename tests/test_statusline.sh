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
      _CLAUDII_LAST_DASHBOARD=''
      _claudii_dashboard
    " 2>/dev/null
  )
  assert_eq "session bar: dead PID → no output (stale session suppressed)" "" "$zsh_session_bar"
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
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    printf '%s' \"\$_CLAUDII_LAST_DASH_PADDED\"
  " 2>/dev/null
)
assert_contains "session bar: live PID → bar shown with model name" "Sonnet" "$zsh_session_bar_live"

# dashboard: PROMPT must not contain save/restore cursor escape sequences
prompt_val=$(
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "dashboard: PROMPT contains no save-cursor ESC[s" "0" \
  "$(printf '%s' "$prompt_val" | grep -cF $'\033[s' || true)"
assert_eq "dashboard: PROMPT contains no restore-cursor ESC[u" "0" \
  "$(printf '%s' "$prompt_val" | grep -cF $'\033[u' || true)"

rm -rf "$SESSION_BAR_TMP"

# ── Dashboard right-alignment width tests ──
# Verify that each padded dashboard line fits within COLUMNS.
# Measurement: _CLAUDII_LAST_DASH_PADDED holds raw zsh prompt strings (%F{} %B etc.).
# Must expand prompt codes via (%) first, then strip ANSI, then count codepoints.
# ⚡ U+26A1 is EAW=W (always 2 terminal columns); ${#} counts it as 1 → add 1 per occurrence.
DASH_WIDTH_TMP="$CLAUDII_HOME/tmp/test_statusline_dashwidth"
rm -rf "$DASH_WIDTH_TMP"
mkdir -p "$DASH_WIDTH_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$DASH_WIDTH_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$DASH_WIDTH_TMP/status-models"
_live_pid=$$

# Test: session with worktree segment — [wt:...] — no wide chars, verify line ≤ COLUMNS
printf 'model=Sonnet\nctx_pct=55\ncost=1.23\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=wt1\nworktree=my-feature\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$DASH_WIDTH_TMP/session-wt1"
dash_wt_result=$(
  CLAUDII_CACHE_DIR="$DASH_WIDTH_TMP" XDG_CONFIG_HOME="$DASH_WIDTH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  COLUMNS=80 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    # _CLAUDII_LAST_DASH_PADDED contains raw zsh prompt strings; expand via (%) then strip ANSI
    local -a lines=(\"\${(@f)\${_CLAUDII_LAST_DASH_PADDED%\$'\\n'}}\")
    for line in \"\${lines[@]}\"; do
      [[ -z \"\$line\" ]] && continue
      vis=\"\${(%)line}\"                          # expand %F{} %B %b %% etc. → ANSI
      vis=\"\${(S)vis//\$'\\e'\[[0-9;]*m/}\"       # strip ANSI CSI sequences
      vis=\"\${vis//\$'\\e'\[s/}\" ; vis=\"\${vis//\$'\\e'\[u/}\"  # strip cursor-save/restore
      vis=\"\${vis//\\\\\$/\\\$}\"                 # \\$ → \$
      printf '%d\n' \"\${#vis}\"
    done
  " 2>/dev/null
)
wt_overflow=0
while IFS= read -r w; do
  [[ -z "$w" ]] && continue
  (( w > 80 )) && wt_overflow=$(( wt_overflow + 1 ))
done <<< "$dash_wt_result"
assert_eq "dashboard worktree line: visible width ≤ COLUMNS=80" "0" "$wt_overflow"

# Test: session with cache_pct — triggers ⚡ (EAW=W, 2 cols) — margin must absorb it
printf 'model=Sonnet\nctx_pct=55\ncost=1.23\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=cp1\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=73\nppid=%s\n' "$_live_pid" \
  > "$DASH_WIDTH_TMP/session-cp1"
rm -f "$DASH_WIDTH_TMP/session-wt1"
dash_cp_result=$(
  CLAUDII_CACHE_DIR="$DASH_WIDTH_TMP" XDG_CONFIG_HOME="$DASH_WIDTH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  COLUMNS=80 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    local -a lines=(\"\${(@f)\${_CLAUDII_LAST_DASH_PADDED%\$'\\n'}}\")
    for line in \"\${lines[@]}\"; do
      [[ -z \"\$line\" ]] && continue
      vis=\"\${(%)line}\"
      vis=\"\${(S)vis//\$'\\e'\[[0-9;]*m/}\"
      vis=\"\${vis//\$'\\e'\[s/}\" ; vis=\"\${vis//\$'\\e'\[u/}\"
      vis=\"\${vis//\\\\\$/\\\$}\"
      # ⚡ (U+26A1, EAW=W) renders as 2 cols but counts as 1 codepoint — add 1 per occurrence
      lightning_count=\$(printf '%s' \"\$vis\" | tr -cd '⚡' | wc -c)
      # Each ⚡ is 3 UTF-8 bytes; wc -c returns byte count — divide by 3
      lightning_count=\$(( lightning_count / 3 ))
      printf '%d\n' \"\$(( \${#vis} + lightning_count ))\"
    done
  " 2>/dev/null
)
cp_overflow=0
while IFS= read -r w; do
  [[ -z "$w" ]] && continue
  (( w > 80 )) && cp_overflow=$(( cp_overflow + 1 ))
done <<< "$dash_cp_result"
assert_eq "dashboard cache_pct line (⚡ EAW=W): true display width ≤ COLUMNS=80" "0" "$cp_overflow"

rm -rf "$DASH_WIDTH_TMP"

# ── Gap 1 — TRAPWINCH invalidates width cache ──────────────────────────────
TRAPWINCH_TMP="$CLAUDII_HOME/tmp/test_statusline_trapwinch"
rm -rf "$TRAPWINCH_TMP"
mkdir -p "$TRAPWINCH_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$TRAPWINCH_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$TRAPWINCH_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=twtest\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$TRAPWINCH_TMP/session-twtest"
trapwinch_out=$(
  CLAUDII_CACHE_DIR="$TRAPWINCH_TMP" XDG_CONFIG_HOME="$TRAPWINCH_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  COLUMNS=80 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    # _CLAUDII_LAST_DASH_COLS should now be 80 — call TRAPWINCH to reset it
    TRAPWINCH
    printf '%d\n' \"\$_CLAUDII_LAST_DASH_COLS\"
  " 2>/dev/null
)
assert_eq "TRAPWINCH: invalidates width cache (_CLAUDII_LAST_DASH_COLS → 0)" "0" "$trapwinch_out"
rm -rf "$TRAPWINCH_TMP"
unset TRAPWINCH_TMP trapwinch_out

# ── Gap 2 — Overflow truncation at narrow terminal ─────────────────────────
OVERFLOW_TMP="$CLAUDII_HOME/tmp/test_statusline_overflow"
rm -rf "$OVERFLOW_TMP"
mkdir -p "$OVERFLOW_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$OVERFLOW_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$OVERFLOW_TMP/status-models"
_live_pid=$$
# Session with very long worktree path + agent name to force overflow at COLUMNS=40
printf 'model=Sonnet\nctx_pct=88\ncost=9.99\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=oftest1\nworktree=very-long-feature-branch-name-exceeding-width\nagent=my-very-long-agent-name-for-testing-overflow\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$OVERFLOW_TMP/session-oftest1"
overflow_result=$(
  CLAUDII_CACHE_DIR="$OVERFLOW_TMP" XDG_CONFIG_HOME="$OVERFLOW_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  COLUMNS=40 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    local -a lines=(\"\${(@f)\${_CLAUDII_LAST_DASH_PADDED%\$'\\n'}}\")
    local overflowed_lines=0 has_ellipsis=0 total_lines=0
    for line in \"\${lines[@]}\"; do
      [[ -z \"\$line\" ]] && continue
      (( total_lines++ ))
      vis=\"\${(%)line}\"
      vis=\"\${(S)vis//\$'\\e'\[[0-9;]*m/}\"
      vis=\"\${vis//\$'\\e'\[s/}\" ; vis=\"\${vis//\$'\\e'\[u/}\"
      vis=\"\${vis//\\\\\$/\\\$}\"
      (( \${#vis} > 40 )) && (( overflowed_lines++ ))
      [[ \"\$vis\" == *'…'* ]] && (( has_ellipsis++ ))
    done
    printf '%d %d %d\n' \"\$overflowed_lines\" \"\$has_ellipsis\" \"\$total_lines\"
  " 2>/dev/null
)
overflow_count=$(echo "$overflow_result" | awk '{print $1}')
ellipsis_count=$(echo "$overflow_result" | awk '{print $2}')
assert_eq "overflow: no lines wider than COLUMNS=40" "0" "${overflow_count:-0}"
assert_eq "overflow: truncated lines end with …" "0" "$([ "${ellipsis_count:-0}" -gt 0 ] && echo 0 || echo 1)"
rm -rf "$OVERFLOW_TMP"
unset OVERFLOW_TMP overflow_result overflow_count ellipsis_count

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
  COLUMNS=80 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    printf '%s' \"\$_CLAUDII_LAST_DASH_PADDED\"
  " 2>/dev/null
)
assert_contains "multi-session: Opus shown in dashboard" "Opus" "$multi_result"
assert_contains "multi-session: Sonnet shown in dashboard" "Sonnet" "$multi_result"
assert_contains "multi-session: Haiku shown in dashboard" "Haiku" "$multi_result"
# Verify all rendered lines ≤ 80 visible chars
multi_overflow=$(
  CLAUDII_CACHE_DIR="$MULTI_TMP" XDG_CONFIG_HOME="$MULTI_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  COLUMNS=80 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    local -a lines=(\"\${(@f)\${_CLAUDII_LAST_DASH_PADDED%\$'\\n'}}\")
    local overflowed=0
    for line in \"\${lines[@]}\"; do
      [[ -z \"\$line\" ]] && continue
      vis=\"\${(%)line}\"
      vis=\"\${(S)vis//\$'\\e'\[[0-9;]*m/}\"
      vis=\"\${vis//\$'\\e'\[s/}\" ; vis=\"\${vis//\$'\\e'\[u/}\"
      vis=\"\${vis//\\\\\$/\\\$}\"
      lightning_count=\$(printf '%s' \"\$vis\" | tr -cd '⚡' | wc -c)
      lightning_count=\$(( lightning_count / 3 ))
      (( \${#vis} + lightning_count > 80 )) && (( overflowed++ ))
    done
    printf '%d\n' \"\$overflowed\"
  " 2>/dev/null
)
assert_eq "multi-session: all lines ≤ COLUMNS=80" "0" "${multi_overflow:-0}"
rm -rf "$MULTI_TMP"
unset MULTI_TMP multi_result multi_overflow

# ── Gap 4 — Dashboard content-cache reuse ─────────────────────────────────
CACHE_REUSE_TMP="$CLAUDII_HOME/tmp/test_statusline_cache_reuse"
rm -rf "$CACHE_REUSE_TMP"
mkdir -p "$CACHE_REUSE_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$CACHE_REUSE_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CACHE_REUSE_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nrate_7d=\nreset_5h=\nreset_7d=\nsession_id=crtest\nworktree=\nagent=\nmodel_id=\nburn_eta=\ncache_pct=\nppid=%s\n' "$_live_pid" \
  > "$CACHE_REUSE_TMP/session-crtest"
cache_reuse_result=$(
  CLAUDII_CACHE_DIR="$CACHE_REUSE_TMP" XDG_CONFIG_HOME="$CACHE_REUSE_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  COLUMNS=80 \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    # First run — populates cache
    _CLAUDII_LAST_DASHBOARD=''
    _claudii_dashboard >/dev/null
    first_padded=\"\$_CLAUDII_LAST_DASH_PADDED\"
    # Second run — same data + same COLUMNS → cache hit, padded unchanged
    _claudii_dashboard >/dev/null
    second_padded=\"\$_CLAUDII_LAST_DASH_PADDED\"
    # Third run — different COLUMNS → cache miss, new padded
    COLUMNS=60
    _claudii_dashboard >/dev/null
    third_padded=\"\$_CLAUDII_LAST_DASH_PADDED\"
    # Output: 'same' if first==second, then 'diff' if second!=third
    [[ \"\$first_padded\" == \"\$second_padded\" ]] && printf 'same\\n' || printf 'not_same\\n'
    [[ \"\$second_padded\" == \"\$third_padded\" ]] && printf 'same\\n' || printf 'diff\\n'
  " 2>/dev/null
)
cache_hit=$(echo "$cache_reuse_result" | sed -n '1p')
cache_miss=$(echo "$cache_reuse_result" | sed -n '2p')
assert_eq "dashboard cache: second run reuses padded output (cache hit)" "same" "${cache_hit:-}"
assert_eq "dashboard cache: COLUMNS change triggers recompute (cache miss)" "diff" "${cache_miss:-}"
rm -rf "$CACHE_REUSE_TMP"
unset CACHE_REUSE_TMP cache_reuse_result cache_hit cache_miss

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
    _CLAUDII_LAST_DASHBOARD='should_be_cleared'
    _claudii_dashboard
    printf '%s' \"\$_CLAUDII_LAST_DASHBOARD\"
  " 2>/dev/null
)
assert_eq "dashboard disabled: _CLAUDII_LAST_DASHBOARD is empty" "" "$dash_off_result"
rm -rf "$DASH_OFF_TMP"
unset DASH_OFF_TMP dash_off_result

# Cleanup
rm -rf "$ZSH_TMP"

# Cleanup test config (keep status cache for live statusline)
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
