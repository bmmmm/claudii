# touches: lib/statusline.zsh lib/visual.sh
# test_statusline.sh — statusline rendering for all scenarios
# Simulates per-model status cache and verifies output

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_statusline.XXXXXX")
mkdir -p "$TEST_TMP/cache" "$TEST_TMP/config/claudii"
# Empty ZDOTDIR prevents loading user's .zshenv/.zshrc in all zsh subprocesses
ZDOTDIR_EMPTY=$(mktemp -d "${TMPDIR:-/tmp}/claudii_zdotdir.XXXXXX")
export XDG_CONFIG_HOME="$TEST_TMP/config"
export CLAUDII_CACHE_DIR="$TEST_TMP/cache"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"
CACHE_STATUS="$CLAUDII_CACHE_DIR/status-models"

# Helper: write per-model cache and simulate statusline output.
# Mirrors the collapsed-health logic in lib/statusline.zsh: all-healthy → a
# single "claude ✓"; only down/degraded models are named; a uniform all-down /
# all-degraded row collapses to one "claude" glyph.
_simulate_statusline() {
  local cache_content=$1
  local models_str=$2

  echo "$cache_content" > "$CACHE_STATUS"

  local total=0 ok=0 down=0 degr=0 problems=""
  IFS=',' read -ra models <<< "$models_str"
  for model in "${models[@]}"; do
    model=$(echo "$model" | tr -d ' ')
    [[ -z "$model" ]] && continue
    label="$(echo "${model:0:1}" | tr '[:lower:]' '[:upper:]')${model:1}"
    total=$((total + 1))

    if grep -q "^${model}=down" "$CACHE_STATUS" 2>/dev/null; then
      down=$((down + 1)); problems+="${label} ↓ "
    elif grep -q "^${model}=degraded" "$CACHE_STATUS" 2>/dev/null; then
      degr=$((degr + 1)); problems+="${label} ~ "
    else
      ok=$((ok + 1))
    fi
  done

  local segments=""
  if (( total > 0 )); then
    if   (( ok   == total )); then segments="claude ✓ "
    elif (( down == total )); then segments="claude ↓ "
    elif (( degr == total )); then segments="claude ~ "
    else                           segments="$problems"
    fi
  fi
  echo "[${segments% }]"
}

# ── Default: all healthy collapses to a single "claude ✓" ──

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3 models, all ok → collapsed claude ✓" "[claude ✓]" "$output"

# 4-model default (incl. the Fable placeholder) all healthy → still collapses.
output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=ok
fable=ok" "opus,sonnet,haiku,fable")
assert_eq "all 4 incl. fable, all ok → collapsed claude ✓" "[claude ✓]" "$output"

# ── Partial outage: only the affected models are named ──

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus down → only Opus named" "[Opus ↓]" "$output"

output=$(_simulate_statusline "opus=ok
sonnet=down
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, sonnet down → only Sonnet named" "[Sonnet ↓]" "$output"

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=down" "opus,sonnet,haiku")
assert_eq "all 3, haiku down → only Haiku named" "[Haiku ↓]" "$output"

# Fable placeholder surfaces by name when its incident scope flips it down.
output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=ok
fable=down" "opus,sonnet,haiku,fable")
assert_eq "fable down while others ok → only Fable named" "[Fable ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus+sonnet down → both named, haiku implied ok" "[Opus ↓ Sonnet ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=down" "opus,sonnet,haiku")
assert_eq "all 3, all down → collapsed claude ↓" "[claude ↓]" "$output"

# ── Degraded (amber) state ──

output=$(_simulate_statusline "opus=degraded
sonnet=ok
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus degraded → only Opus ~ named" "[Opus ~]" "$output"

output=$(_simulate_statusline "opus=degraded
sonnet=down
haiku=ok" "opus,sonnet,haiku")
assert_eq "all 3, opus degraded + sonnet down → both named" "[Opus ~ Sonnet ↓]" "$output"

output=$(_simulate_statusline "opus=degraded
sonnet=degraded
haiku=degraded" "opus,sonnet,haiku")
assert_eq "all 3, all degraded → collapsed claude ~" "[claude ~]" "$output"

# ── Single model: opus only ──

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=ok" "opus")
assert_eq "opus only, ok → collapsed claude ✓" "[claude ✓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "opus")
assert_eq "opus only, down → collapsed claude ↓" "[claude ↓]" "$output"

# ── Two models: opus,sonnet ──

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "opus,sonnet")
assert_eq "opus+sonnet, opus down → only Opus named" "[Opus ↓]" "$output"

output=$(_simulate_statusline "opus=ok
sonnet=down
haiku=ok" "opus,sonnet")
assert_eq "opus+sonnet, sonnet down → only Sonnet named" "[Sonnet ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=ok" "opus,sonnet")
assert_eq "opus+sonnet, both down → collapsed claude ↓" "[claude ↓]" "$output"

# ── Reversed order: only the down model shows, so order is moot here ──

output=$(_simulate_statusline "opus=down
sonnet=ok
haiku=ok" "sonnet,opus")
assert_eq "reversed order, opus down → only Opus named" "[Opus ↓]" "$output"

# ── Haiku only ──

output=$(_simulate_statusline "opus=ok
sonnet=ok
haiku=down" "haiku")
assert_eq "haiku only, down → collapsed claude ↓" "[claude ↓]" "$output"

output=$(_simulate_statusline "opus=down
sonnet=down
haiku=ok" "haiku")
assert_eq "haiku only, others down (haiku ok) → collapsed claude ✓" "[claude ✓]" "$output"

# ── Config integration ──

bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet" >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config set models to opus,sonnet" "opus,sonnet" "$output"

bash "$CLAUDII_HOME/bin/claudii" config set statusline.enabled false >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.enabled 2>&1)
assert_eq "statusline can be disabled" "false" "$output"

# ── zsh integration: call real _claudii_statusline function ──

ZSH_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_statusline_zsh.XXXXXX")
mkdir -p "$ZSH_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$ZSH_TMP/config/claudii/config.json"

# All ok
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: all ok → collapsed claude in RPROMPT" "claude" "$zsh_out"
assert_contains "zsh: all ok → ✓ in RPROMPT" "✓" "$zsh_out"
if printf '%s' "$zsh_out" | grep -q "Opus"; then
  assert_eq "zsh: all ok → no per-model name (collapsed)" "no Opus" "Opus found"
else
  assert_eq "zsh: all ok → no per-model name (collapsed)" "no Opus" "no Opus"
fi

# Opus down
printf 'opus=down\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: opus down → ↓ in RPROMPT" "↓" "$zsh_out"

# Incident present but NO tracked model affected → neutral note glyph (ⓘ),
# models stay ✓. Regression for the Mythos/Fable false-cascade: a status note
# about untracked models must not paint Opus/Sonnet/Haiku amber.
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n_incident=monitoring\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: incident, no model affected → ⓘ note glyph" "ⓘ" "$zsh_out"
assert_contains "zsh: incident, no model affected → models still ✓" "✓" "$zsh_out"
if printf '%s' "$zsh_out" | grep -q "◎"; then
  assert_eq "zsh: unaffected incident shows note not stage icon" "note" "stage icon ◎"
else
  assert_eq "zsh: unaffected incident shows note not stage icon" "note" "note"
fi

# Incident WITH a tracked model affected → stage-colored icon (◎), not the note.
printf 'opus=degraded\nsonnet=ok\nhaiku=ok\n_incident=monitoring\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "zsh: incident + model affected → ◎ stage icon" "◎" "$zsh_out"
if printf '%s' "$zsh_out" | grep -q "ⓘ"; then
  assert_eq "zsh: affected incident shows stage not note icon" "stage" "note ⓘ"
else
  assert_eq "zsh: affected incident shows stage not note icon" "stage" "stage"
fi

# Stale cache → ⟳ indicator.
# Fresh tmp dir: an earlier test sharing $ZSH_TMP spawns a background claudii-status
# that can rewrite status-models right after the touch below, resetting its mtime to
# now and masking the stale state (flaky ⟳-missing, seen on slow macOS CI runners).
# Same isolation the no-cache test below relies on.
ZSH_STALE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_stale.XXXXXX")
mkdir -p "$ZSH_STALE_TMP/config/claudii"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ZSH_STALE_TMP/status-models"
touch -t 202001010000 "$ZSH_STALE_TMP/status-models"   # set mtime far in the past
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_STALE_TMP" XDG_CONFIG_HOME="$ZSH_STALE_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
rm -rf "$ZSH_STALE_TMP"
assert_contains "zsh: stale cache → ⟳ in RPROMPT" "⟳" "$zsh_out"

# No cache → […] loading indicator
# Use a fresh tmp dir — avoids race condition where the background claudii-status
# spawned by the stale-cache test above recreates status-models before rm -f completes.
ZSH_NOCACHE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_nocache.XXXXXX")
mkdir -p "$ZSH_NOCACHE_TMP/config/claudii"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_NOCACHE_TMP" XDG_CONFIG_HOME="$ZSH_NOCACHE_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
rm -rf "$ZSH_NOCACHE_TMP"
assert_contains "zsh: no cache → […] in RPROMPT" "…" "$zsh_out"

# Disabled: RPROMPT empty
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ZSH_TMP/status-models"
zsh_out=$(
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
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
  CLAUDII_CACHE_DIR="$ZSH_TMP" XDG_CONFIG_HOME="$ZSH_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -i -c "
    cp \"\$CLAUDII_HOME/config/defaults.json\" \"\$XDG_CONFIG_HOME/claudii/config.json\"
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    # Wait for background job to finish — 'done' notification appears on next
    # prompt after job exit, so we must still be in the shell when it completes
    sleep 1
  " 2>&1 | grep -E '^\[[0-9]+\]' || true
)
assert_eq "zsh -i: no [N] job notification (start or done)" "" "$job_leak"

# ── Session bar: dead PID → bar suppressed ──
# Write a session cache with a PID that no longer exists.
# On any reasonable system, PID 1 is init/launchd — never a Claude process.
# We use a sentinel PID that is guaranteed to be gone: spawn a subshell, grab
# its PID, let it exit, then use that dead PID.
_dead_pid=$(bash -c 'echo $$' 2>/dev/null)
SESSION_BAR_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_statusline_sessionbar.XXXXXX")
mkdir -p "$SESSION_BAR_TMP/config/claudii"
jq '."session-dashboard".enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$SESSION_BAR_TMP/config/claudii/config.json"
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
    CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
    zsh -c "
      source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
      _CLAUDII_CMD_RAN=1
      _claudii_session_dashboard
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
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
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
    CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
    zsh -c "
      source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
      _CLAUDII_CMD_RAN=1
      _CLAUDII_LAST_CMD='claudii'
      _claudii_session_dashboard
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
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
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
  CLAUDII_CACHE_DIR="$SESSION_BAR_TMP" XDG_CONFIG_HOME="$SESSION_BAR_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "dashboard: PROMPT contains no save-cursor ESC[s" "0" \
  "$(printf '%s' "$prompt_val" | grep -cF $'\033[s' || true)"
assert_eq "dashboard: PROMPT contains no restore-cursor ESC[u" "0" \
  "$(printf '%s' "$prompt_val" | grep -cF $'\033[u' || true)"

rm -rf "$SESSION_BAR_TMP"

# ── Conditional rendering tests ──

COND_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_statusline_cond.XXXXXX")
mkdir -p "$COND_TMP/config/claudii"
jq '."session-dashboard".enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$COND_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$COND_TMP/status-models"
_live_pid=$$
printf 'model=Sonnet\nctx_pct=76\ncost=0.66\ntok=1300000\nrate_5h=28\nreset_5h=\nppid=%s\n' "$_live_pid" \
  > "$COND_TMP/session-condtest"

# 1. CMD_RAN=0 → no dashboard, plain PROMPT
cond_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CMD_RAN=0
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "conditional: CMD_RAN=0 → plain PROMPT, no session lines" "TESTPROMPT> " "$cond_out"

# 2. CMD_RAN=1 → dashboard shown, contains model name
cond_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    print -P \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "conditional: CMD_RAN=1 → dashboard shown with model" "Sonnet" "$cond_out"

# 3. Format test: model, ctx%, token throughput, 5h-rate all present
format_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    print -P \"\${(e)PROMPT}\"
  " 2>/dev/null
)
assert_contains "dashboard format: contains model name" "Sonnet" "$format_out"
assert_contains "dashboard format: contains ctx%" "76%" "$format_out"
assert_contains "dashboard format: contains token throughput" "1.3M tok" "$format_out"
assert_contains "dashboard format: contains 5h rate" "5h:28%" "$format_out"

# 4. dashboard off → plain PROMPT
off_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_USER_PROMPT='TESTPROMPT> '
    _CLAUDII_CFG_CACHE[session-dashboard.enabled]=off
    _CLAUDII_CMD_RAN=1
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_eq "dashboard off → plain PROMPT" "TESTPROMPT> " "$off_out"

# 5. TRAPWINCH sets CMD_RAN=1
trapwinch_out=$(
  CLAUDII_CACHE_DIR="$COND_TMP" XDG_CONFIG_HOME="$COND_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
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
jq '."session-dashboard".enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$RATE_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$RATE_TMP/status-models"
_live_pid2=$$

# 5h rate >= 80% → %F{red} in dashboard raw PROMPT (before expansion)
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=85\nreset_5h=\nppid=%s\n' "$_live_pid2" \
  > "$RATE_TMP/session-ratetest1"
zsh_rate_red=$(
  CLAUDII_CACHE_DIR="$RATE_TMP" XDG_CONFIG_HOME="$RATE_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "dashboard: 5h rate >= 80% → %F{red} in PROMPT" "%F{red}" "$zsh_rate_red"

# 5h rate < 50% → %F{green} in dashboard raw PROMPT (before expansion)
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=30\nreset_5h=\nppid=%s\n' "$_live_pid2" \
  > "$RATE_TMP/session-ratetest2"
rm -f "$RATE_TMP/session-ratetest1"
zsh_rate_green=$(
  CLAUDII_CACHE_DIR="$RATE_TMP" XDG_CONFIG_HOME="$RATE_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
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
  CLAUDII_CACHE_DIR="$ESC_TMP" XDG_CONFIG_HOME="$ESC_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
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

# ── Dashboard only after claudii commands ────────────────────────────────────
CMDFILTER_TMP="$CLAUDII_HOME/tmp/test_statusline_cmdfilter"
rm -rf "$CMDFILTER_TMP"
mkdir -p "$CMDFILTER_TMP/config/claudii"
jq '."session-dashboard".enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$CMDFILTER_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CMDFILTER_TMP/status-models"
printf 'model=Sonnet\nctx_pct=42\ncost=0.55\nrate_5h=\nreset_5h=\nppid=%s\n' "$$" \
  > "$CMDFILTER_TMP/session-cmdfilter"

# After non-claudii command (ls) → no dashboard
ls_out=$(
  CLAUDII_CACHE_DIR="$CMDFILTER_TMP" XDG_CONFIG_HOME="$CMDFILTER_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='ls'
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
if printf '%s' "$ls_out" | grep -qF "Sonnet"; then
  assert_eq "dashboard: hidden after non-claudii cmd (ls)" "no Sonnet" "Sonnet found"
else
  assert_eq "dashboard: hidden after non-claudii cmd (ls)" "no Sonnet" "no Sonnet"
fi

# After plain claudii command → dashboard shown
claudii_out=$(
  CLAUDII_CACHE_DIR="$CMDFILTER_TMP" XDG_CONFIG_HOME="$CMDFILTER_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_contains "dashboard: shown after claudii cmd" "Sonnet" "$claudii_out"

# After claudii se/si/sessions → dashboard suppressed (already showed session info)
se_out=$(
  CLAUDII_CACHE_DIR="$CMDFILTER_TMP" XDG_CONFIG_HOME="$CMDFILTER_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii se'
    _CLAUDII_SHOWED_SESSIONS=1
    _claudii_session_dashboard
    printf '%s' \"\$PROMPT\"
  " 2>/dev/null
)
assert_not_contains "session dashboard: suppressed after claudii se (SHOWED_SESSIONS flag)" "Sonnet" "$se_out"

rm -rf "$CMDFILTER_TMP"
unset CMDFILTER_TMP ls_out claudii_out

rm -rf "$ZSH_TMP"

# Cleanup test config (keep status cache for live statusline)
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME

# ── Reentrancy guard: second call while first is running → skipped ────────────
REENT_TMP="$CLAUDII_HOME/tmp/test_statusline_reent"
rm -rf "$REENT_TMP"
mkdir -p "$REENT_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$REENT_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$REENT_TMP/status-models"

reent_out=$(
  CLAUDII_CACHE_DIR="$REENT_TMP" XDG_CONFIG_HOME="$REENT_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    # Simulate reentrancy: guard holds a fresh timestamp (< 5s old)
    _CLAUDII_PRECMD_RUNNING=\$EPOCHSECONDS
    # Call must return immediately without updating RPROMPT
    RPROMPT='ORIGINAL'
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_eq "reentrancy guard: second call skipped, RPROMPT unchanged" "ORIGINAL" "$reent_out"

# Stale guard (older than 5s) is treated as stuck → render proceeds, RPROMPT updates
reent_stuck=$(
  CLAUDII_CACHE_DIR="$REENT_TMP" XDG_CONFIG_HOME="$REENT_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_PRECMD_RUNNING=\$(( EPOCHSECONDS - 60 ))
    RPROMPT='ORIGINAL'
    _claudii_statusline
    [[ \"\$RPROMPT\" == 'ORIGINAL' ]] && printf 'STUCK' || printf 'RECOVERED'
  " 2>/dev/null
)
assert_eq "reentrancy guard: stale guard auto-recovers" "RECOVERED" "$reent_stuck"

# Guard clears after normal call completes
reent_clear=$(
  CLAUDII_CACHE_DIR="$REENT_TMP" XDG_CONFIG_HOME="$REENT_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    # After normal call, guard must be cleared so next call can proceed
    printf '%s' \"\${_CLAUDII_PRECMD_RUNNING:-CLEARED}\"
  " 2>/dev/null
)
assert_eq "reentrancy guard: cleared after normal call completes" "CLEARED" "$reent_clear"

rm -rf "$REENT_TMP"
unset REENT_TMP reent_out reent_clear

# ── Background PID guard: no second spawn while first is running ──────────────
PID_TMP="$CLAUDII_HOME/tmp/test_statusline_pid"
rm -rf "$PID_TMP"
mkdir -p "$PID_TMP/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$PID_TMP/config/claudii/config.json"

# Simulate a still-running background job: write test runner's PID to PID file.
# _claudii_status_spawn checks PID file → kill -0 succeeds → skips spawn.
_TEST_LIVE_PID=$$
echo "$_TEST_LIVE_PID" > "$PID_TMP/status.pid"
pid_guard_out=$(
  CLAUDII_CACHE_DIR="$PID_TMP" XDG_CONFIG_HOME="$PID_TMP/config" CLAUDII_HOME="$CLAUDII_HOME" \
  _TEST_LIVE_PID="$_TEST_LIVE_PID" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    # No cache file → would normally trigger a background spawn
    # But PID file contains a live PID → spawn is suppressed
    _claudii_statusline
    # PID file should still contain the original PID (no new spawn)
    cat \"\$CLAUDII_CACHE_DIR/status.pid\" 2>/dev/null
  " 2>/dev/null
)
# PID file must still contain original PID — no new spawn happened
assert_eq "PID guard: no new spawn when previous fetch still running" "$_TEST_LIVE_PID" "$pid_guard_out"

rm -rf "$PID_TMP"
unset PID_TMP pid_guard_out _TEST_LIVE_PID

# ── Adaptive TTL ──────────────────────────────────────────────────────────────
# Test that effective TTL is adjusted based on cache content:
#   all ok   → effective_ttl = base * 2
#   incident → effective_ttl = max(60, base / 5)
#   unreachable → effective_ttl = base (unchanged)
#
# Each subtest gets its own tmp dir. _claudii_statusline spawns bin/claudii-status
# in the background (which does a network fetch and writes status-models via mv).
# A shared dir causes a race: the background job from the ok-stale subtest can
# write status-models with mtime=now AFTER the degraded subtest's touch -t sets
# it to 2020, making the degraded subprocess see age≈0 and omit ⟳.

_attl_setup() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/config/claudii"
  cp "$CLAUDII_HOME/config/defaults.json" "$dir/config/claudii/config.json"
}

ATTL_OK_FRESH="$CLAUDII_HOME/tmp/test_statusline_attl_ok_fresh"
ATTL_OK_STALE="$CLAUDII_HOME/tmp/test_statusline_attl_ok_stale"
ATTL_DEG="$CLAUDII_HOME/tmp/test_statusline_attl_deg"
ATTL_UNR="$CLAUDII_HOME/tmp/test_statusline_attl_unr"

# Base TTL from defaults (300s). A fresh cache (age ~0) should never show ⟳.
# For ok state (effective_ttl = 600): age 0 → no refresh indicator.
_attl_setup "$ATTL_OK_FRESH"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ATTL_OK_FRESH/status-models"
attl_ok_out=$(
  CLAUDII_CACHE_DIR="$ATTL_OK_FRESH" XDG_CONFIG_HOME="$ATTL_OK_FRESH/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
# Fresh all-ok cache: effective TTL = base*2, so no ⟳
if printf '%s' "$attl_ok_out" | grep -qF '⟳'; then
  assert_eq "adaptive TTL ok state: fresh cache → no refresh indicator" "no refresh" "refresh shown"
else
  assert_eq "adaptive TTL ok state: fresh cache → no refresh indicator" "no refresh" "no refresh"
fi

# For ok state with stale cache (age > base*2): should show ⟳
_attl_setup "$ATTL_OK_STALE"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$ATTL_OK_STALE/status-models"
touch -t 202001010000 "$ATTL_OK_STALE/status-models"
attl_ok_stale=$(
  CLAUDII_CACHE_DIR="$ATTL_OK_STALE" XDG_CONFIG_HOME="$ATTL_OK_STALE/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "adaptive TTL ok state: stale cache → refresh indicator shown" "⟳" "$attl_ok_stale"

# For degraded state: effective_ttl = max(60, base/5) = max(60, 60) = 60.
# A fresh cache (age ~0) → no refresh. A cache slightly older than 60s → refresh.
_attl_setup "$ATTL_DEG"
printf 'opus=degraded\nsonnet=ok\nhaiku=ok\n' > "$ATTL_DEG/status-models"
touch -t 202001010000 "$ATTL_DEG/status-models"
attl_deg_out=$(
  CLAUDII_CACHE_DIR="$ATTL_DEG" XDG_CONFIG_HOME="$ATTL_DEG/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
assert_contains "adaptive TTL incident state: stale degraded cache → refresh indicator shown" "⟳" "$attl_deg_out"

# For unreachable: effective_ttl = base (300). Fresh cache → no ⟳.
_attl_setup "$ATTL_UNR"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n_api=unreachable\n' > "$ATTL_UNR/status-models"
attl_unr_out=$(
  CLAUDII_CACHE_DIR="$ATTL_UNR" XDG_CONFIG_HOME="$ATTL_UNR/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _claudii_statusline
    printf '%s' \"\$RPROMPT\"
  " 2>/dev/null
)
if printf '%s' "$attl_unr_out" | grep -qF '⟳'; then
  assert_eq "adaptive TTL unreachable state: fresh cache → no refresh indicator" "no refresh" "refresh shown"
else
  assert_eq "adaptive TTL unreachable state: fresh cache → no refresh indicator" "no refresh" "no refresh"
fi

rm -rf "$ATTL_OK_FRESH" "$ATTL_OK_STALE" "$ATTL_DEG" "$ATTL_UNR"
unset -f _attl_setup
unset ATTL_OK_FRESH ATTL_OK_STALE ATTL_DEG ATTL_UNR attl_ok_out attl_ok_stale attl_deg_out attl_unr_out

# ── token-throughput display (from the session-* cache tok= field) ───────────

HIST_TMP="$CLAUDII_HOME/tmp/test_statusline_hist"
rm -rf "$HIST_TMP"
mkdir -p "$HIST_TMP/config/claudii"
jq '."session-dashboard".enabled = "on"' "$CLAUDII_HOME/config/defaults.json" > "$HIST_TMP/config/claudii/config.json"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$HIST_TMP/status-models"
_live_pid=$$

# 1. tok=0 in cache → session shown but no token amount
printf 'model=Sonnet\nctx_pct=48\ncost=0\ntok=0\nrate_5h=31\nreset_5h=\nsession_id=histtest1\nppid=%s\n' "$_live_pid" \
  > "$HIST_TMP/session-histtest1"

hist_tok_zero_out=$(
  CLAUDII_CACHE_DIR="$HIST_TMP" XDG_CONFIG_HOME="$HIST_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    print -P \"\${(e)PROMPT}\"
  " 2>/dev/null
)
assert_contains "dashboard: tok=0 → session shown" "Sonnet" "$hist_tok_zero_out"
if printf '%s' "$hist_tok_zero_out" | grep -qF 'tok'; then
  assert_eq "dashboard: tok=0 → no token amount shown" "no tok" "tok found"
else
  assert_eq "dashboard: tok=0 → no token amount shown" "no tok" "no tok"
fi

# 2. tok absent from cache → session shown, no token amount, no crash
printf 'model=Sonnet\nctx_pct=48\ncost=0\nrate_5h=31\nreset_5h=\nsession_id=histtest2\nppid=%s\n' "$_live_pid" \
  > "$HIST_TMP/session-histtest1"

hist_tok_absent_out=$(
  CLAUDII_CACHE_DIR="$HIST_TMP" XDG_CONFIG_HOME="$HIST_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    print -P \"\${(e)PROMPT}\"
  " 2>/dev/null
)
assert_contains "dashboard: tok absent → session shown" "Sonnet" "$hist_tok_absent_out"
if printf '%s' "$hist_tok_absent_out" | grep -qF 'tok'; then
  assert_eq "dashboard: tok absent → no token amount shown" "no tok" "tok found"
else
  assert_eq "dashboard: tok absent → no token amount shown" "no tok" "no tok"
fi

# 3. tok=5.2M in cache → shows formatted throughput directly
rm -f "$HIST_TMP/session-histtest1"
printf 'model=Sonnet\nctx_pct=48\ncost=15.51\ntok=5200000\nrate_5h=31\nreset_5h=\nsession_id=histtest3\nppid=%s\n' "$_live_pid" \
  > "$HIST_TMP/session-histtest3"

hist_tok_out=$(
  CLAUDII_CACHE_DIR="$HIST_TMP" XDG_CONFIG_HOME="$HIST_TMP/config" ZDOTDIR="$ZDOTDIR_EMPTY" CLAUDII_HOME="$CLAUDII_HOME" \
  zsh -c "
    source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
    _CLAUDII_CMD_RAN=1
    _CLAUDII_LAST_CMD='claudii'
    _claudii_session_dashboard
    print -P \"\${(e)PROMPT}\"
  " 2>/dev/null
)
assert_contains "dashboard: tok=5.2M in cache → shows throughput" "5.2M tok" "$hist_tok_out"

rm -rf "$HIST_TMP"
unset HIST_TMP hist_tok_zero_out hist_tok_absent_out hist_tok_out
