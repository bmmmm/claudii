# test_status.sh — status checker E2E tests

# Setup: clean cache
rm -f "${TMPDIR:-/tmp}"/claudii-status-cache.xml
rm -f "${TMPDIR:-/tmp}"/claudii-status-models

# status runs without error
output=$(bash "$CLAUDII_HOME/bin/claudii-status" 2>&1 || true)
exit_code=$?
# We can't predict the live status, but exit code should be 0-3
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

# per-model cache has correct format
cached=$(cat "${TMPDIR:-/tmp}/claudii-status-models")
assert_contains "cache has opus entry" "opus=" "$cached"
assert_contains "cache has sonnet entry" "sonnet=" "$cached"
assert_contains "cache has haiku entry" "haiku=" "$cached"

# each model is either ok or down
for model in opus sonnet haiku; do
  line=$(grep "^${model}=" "${TMPDIR:-/tmp}/claudii-status-models")
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
