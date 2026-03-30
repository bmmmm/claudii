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
    _claudii_dashboard
    print -P \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "session bar: live PID → bar shown with model name" "Sonnet" "$zsh_session_bar_live"
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
    _claudii_dashboard
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
    _claudii_dashboard
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

# Cleanup
rm -rf "$ZSH_TMP"

# Cleanup test config (keep status cache for live statusline)
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
