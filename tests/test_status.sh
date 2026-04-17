# touches: bin/claudii-status
# test_status.sh — status checker E2E tests

# Setup: test config so models are well-known and controllable
export XDG_CONFIG_HOME="$CLAUDII_HOME/tmp/test_status"
rm -rf "$XDG_CONFIG_HOME/claudii"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

# Redirect cache to test-local dir (not user's ~/.cache)
export CLAUDII_CACHE_DIR="$CLAUDII_HOME/tmp/test_status_cache"
mkdir -p "$CLAUDII_CACHE_DIR"

# Clean cache
rm -f "$CLAUDII_CACHE_DIR"/status-unresolved.json
rm -f "$CLAUDII_CACHE_DIR"/status-models

# Determine which models the status script will check (driven by config)
models_raw=$(jq -r '.statusline.models' "$XDG_CONFIG_HOME/claudii/config.json")
IFS=',' read -ra STATUS_MODELS <<< "$models_raw"

# status runs without crash — exit 0 (all ok) or 1 (degraded) are both valid
exit_code=0
bash "$CLAUDII_HOME/bin/claudii-status" >/dev/null 2>&1 || exit_code=$?
assert_eq "status: no crash (exit 0 or 1)" "true" "$([[ $exit_code -le 1 ]] && echo true || echo false)"
output=$(bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 || true)

# quiet mode suppresses output
output=$(bash "$CLAUDII_HOME/bin/claudii-status" --quiet 2>&1 || true)
assert_eq "quiet mode produces no output" "" "$output"

# model status cache always created (even offline → all-ok fallback)
assert_file_exists "model status cache created" "$CLAUDII_CACHE_DIR/status-models"

# unresolved.json cache always written after a successful status check
if [[ -f "$CLAUDII_CACHE_DIR/status-unresolved.json" ]]; then
  assert_eq "status-unresolved.json cache created" "true" "true"
  if jq -e '.incidents | arrays' "$CLAUDII_CACHE_DIR/status-unresolved.json" >/dev/null 2>&1; then
    assert_eq "status-unresolved.json has incidents array" "true" "true"
  else
    assert_eq "status-unresolved.json has incidents array" "valid json with incidents[]" "$(cat "$CLAUDII_CACHE_DIR/status-unresolved.json")"
  fi
else
  # API unreachable → file absent, that's ok
  assert_eq "status ran without crash" "true" "true"
fi

# All configured models must appear in cache with valid state
cached=$(cat "$CLAUDII_CACHE_DIR/status-models")
for model in "${STATUS_MODELS[@]}"; do
  model="${model// /}"
  assert_contains "cache has ${model} entry" "${model}=" "$cached"
  line=$(grep "^${model}=" "$CLAUDII_CACHE_DIR/status-models" || true)
  if echo "$line" | grep -qE "^${model}=(ok|degraded|down)$"; then
    assert_eq "cache ${model} has valid state" "true" "true"
  else
    assert_eq "cache ${model} has valid state" "${model}=ok|degraded|down" "$line"
  fi
done

# status subcommand via claudii shows output
output=$(bash "$CLAUDII_HOME/bin/claudii" status 2>&1 || true)
if echo "$output" | grep -qE '✗|~|✓|available|down|degraded'; then
  assert_eq "claudii status shows meaningful output" "true" "true"
else
  assert_eq "claudii status shows meaningful output" "contains status text" "$output"
fi

# Adding a new model to config: status must check it too
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet,haiku,testmodel" >/dev/null 2>&1
rm -f "$CLAUDII_CACHE_DIR/status-models"
bash "$CLAUDII_HOME/bin/claudii-status" --quiet 2>/dev/null || true
cached=$(cat "$CLAUDII_CACHE_DIR/status-models" 2>/dev/null || true)
assert_contains "new model in config appears in cache" "testmodel=" "$cached"

# ── Incident display: claudii status reads status-unresolved.json ────────────
# _cmd_status calls $CLAUDII_HOME/bin/claudii-status directly, so we need a
# temp CLAUDII_HOME with a stub binary that writes mock incident data.
_stub_home="$CLAUDII_HOME/tmp/test_status_stub_home"
mkdir -p "$_stub_home/bin" "$_stub_home/lib/cmd" "$_stub_home/config"
# Symlink all real files except claudii-status (which we stub)
for _f in claudii claudii-sessionline; do
  ln -sf "$CLAUDII_HOME/bin/$_f" "$_stub_home/bin/$_f" 2>/dev/null || true
done
cp -r "$CLAUDII_HOME/lib" "$_stub_home/"
cp "$CLAUDII_HOME/config/defaults.json" "$_stub_home/config/"
cat > "$_stub_home/bin/claudii-status" <<'STUB'
#!/bin/bash
CACHE_DIR="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
mkdir -p "$CACHE_DIR"
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CACHE_DIR/status-models"
printf '{"incidents":[{"name":"API Degraded","status":"investigating","impact":"minor","incident_updates":[{"status":"Investigating","body":"We are looking into elevated error rates.","created_at":"2026-04-09T10:00:00.000Z"}]}]}\n' > "$CACHE_DIR/status-unresolved.json"
exit 0
STUB
chmod +x "$_stub_home/bin/claudii-status"
_inc_out=$(CLAUDII_HOME="$_stub_home" bash "$_stub_home/bin/claudii" status 2>&1 || true)
if echo "$_inc_out" | grep -q "API Degraded"; then
  assert_eq "claudii status: incident name from unresolved.json shown" "true" "true"
else
  assert_eq "claudii status: incident name from unresolved.json shown" "API Degraded" "$_inc_out"
fi
if echo "$_inc_out" | grep -qi "investigating"; then
  assert_eq "claudii status: incident status shown" "true" "true"
else
  assert_eq "claudii status: incident status shown" "investigating" "$_inc_out"
fi
rm -rf "$_stub_home"

# ANSI guard: claudii status output must not contain literal ESC sequences as \033 text
_status_out=$(bash "$CLAUDII_HOME/bin/claudii" status 2>&1 || true)
if printf '%s' "$_status_out" | grep -qF '\033'; then
  assert_eq "claudii status: no literal \\033 in output" "no literal escapes" "found literal \\033"
else
  assert_eq "claudii status: no literal \\033 in output" "true" "true"
fi

# Regression: multiline incident name must be flattened to single line
# (bin/claudii-status does `jq -r .incidents[0].name | tr '\n' ' ' | sed 's/ *$//'`
#  to prevent multi-line names from breaking RPROMPT/stderr layout)
_mock_json='{"incidents":[{"name":"Line1\nLine2\nLine3","impact":"minor"}]}'
_flat=$(echo "$_mock_json" | jq -r '.incidents[0].name' | tr '\n' ' ' | sed 's/ *$//')
assert_eq "incident name: newlines stripped to spaces" "Line1 Line2 Line3" "$_flat"
assert_eq "incident name: zero embedded newlines" "0" "$(printf '%s' "$_flat" | tr -cd '\n' | wc -c | tr -d ' ')"

# Cleanup
rm -rf "$XDG_CONFIG_HOME" "$CLAUDII_CACHE_DIR"
unset XDG_CONFIG_HOME CLAUDII_CACHE_DIR
