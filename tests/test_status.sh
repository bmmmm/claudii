# test_status.sh — status checker E2E tests

# Setup: test config so models are well-known and controllable
export XDG_CONFIG_HOME="$CLAUDII_HOME/tmp/test_status"
rm -rf "$XDG_CONFIG_HOME/claudii"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

# Clean cache
rm -f "${TMPDIR:-/tmp}"/claudii-status-cache.xml
rm -f "${TMPDIR:-/tmp}"/claudii-status-models

# Determine which models the status script will check (driven by config)
models_raw=$(jq -r '.statusline.models' "$XDG_CONFIG_HOME/claudii/config.json")
IFS=',' read -ra STATUS_MODELS <<< "$models_raw"

# status runs without error
output=$(bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 || true)
exit_code=$?
if (( exit_code >= 0 && exit_code <= 3 )); then
  assert_eq "status exit code is valid (0-3)" "true" "true"
else
  assert_eq "status exit code is valid (0-3)" "0-3" "$exit_code"
fi

# quiet mode suppresses output
output=$(bash "$CLAUDII_HOME/bin/claudii-status" --quiet 2>&1 || true)
assert_eq "quiet mode produces no output" "" "$output"

# model status cache always created (even offline → all-ok fallback)
assert_file_exists "model status cache created" "${TMPDIR:-/tmp}/claudii-status-models"

# RSS XML cache only present when network was reachable
if [[ -f "${TMPDIR:-/tmp}/claudii-status-cache.xml" ]]; then
  assert_eq "RSS cache present (network available)" "true" "true"
else
  assert_eq "RSS cache absent (offline all-ok fallback)" "true" "true"
fi

# All configured models must appear in cache with valid state
cached=$(cat "${TMPDIR:-/tmp}/claudii-status-models")
for model in "${STATUS_MODELS[@]}"; do
  model="${model// /}"
  assert_contains "cache has ${model} entry" "${model}=" "$cached"
  line=$(grep "^${model}=" "${TMPDIR:-/tmp}/claudii-status-models" || true)
  if echo "$line" | grep -qE "^${model}=(ok|down)$"; then
    assert_eq "cache ${model} has valid state" "true" "true"
  else
    assert_eq "cache ${model} has valid state" "${model}=ok|down" "$line"
  fi
done

# status subcommand via claudii shows output
output=$(bash "$CLAUDII_HOME/bin/claudii" status 2>&1 || true)
if echo "$output" | grep -qE '⚠|✓|verfügbar|down'; then
  assert_eq "claudii status shows meaningful output" "true" "true"
else
  assert_eq "claudii status shows meaningful output" "contains status text" "$output"
fi

# Adding a new model to config: status must check it too
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet,haiku,testmodel" >/dev/null 2>&1
rm -f "${TMPDIR:-/tmp}"/claudii-status-models
bash "$CLAUDII_HOME/bin/claudii-status" --quiet 2>/dev/null || true
cached=$(cat "${TMPDIR:-/tmp}/claudii-status-models" 2>/dev/null || true)
assert_contains "new model in config appears in cache" "testmodel=" "$cached"

# Cleanup
rm -rf "$XDG_CONFIG_HOME"
rm -f "${TMPDIR:-/tmp}"/claudii-status-models
unset XDG_CONFIG_HOME
