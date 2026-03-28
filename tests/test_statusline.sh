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

# Cleanup
rm -rf "$ZSH_TMP"

# Cleanup test config (keep status cache for live statusline)
rm -rf "$TEST_TMP"
unset XDG_CONFIG_HOME
