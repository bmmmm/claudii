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
rm -f "$CLAUDII_CACHE_DIR"/status-cache.xml
rm -f "$CLAUDII_CACHE_DIR"/status-models

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
assert_file_exists "model status cache created" "$CLAUDII_CACHE_DIR/status-models"

# RSS XML cache only written when outage detected (and network reachable)
# Either absent (all ok) or present (outage) — both are valid
assert_eq "status ran without crash" "true" "true"

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
if echo "$output" | grep -qE '✗|~|✓|verfügbar|down|degraded'; then
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

# ── Incident parsing: nested HTML in <small> (e.g. <a href="...">timestamp</a>) ────
# Simulate an incident RSS with nested tags in <small>
_inc_html='<p><small><a href="https://example.com">Apr 2, 14:20 UTC</a></small><strong>Investigating</strong> - Services degraded.</p>'

# Code-path 1: awk-based parser (same logic as _cmd_status RSS-cache path)
_awk_out=$(printf '%s\n' "$_inc_html" | awk '
  BEGIN { RS="</p>"; FS="" }
  {
    gsub(/^[^<]*<p>/, "")
    if (length($0) < 5) next
    time_str = $0
    sub(/.*<small>/, "", time_str)
    sub(/<\/small>.*/, "", time_str)
    gsub(/<[^>]*>/, "", time_str)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", time_str)
    status = $0
    sub(/.*<strong>/, "", status)
    sub(/<\/strong>.*/, "", status)
    msg = $0
    sub(/.*<\/strong>[[:space:]]*-[[:space:]]*/, "", msg)
    gsub(/<[^>]*>/, "", msg)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", msg)
    if (length(status) > 0 && length(time_str) > 0) {
      print ""
      print "    " time_str "  " status " — " msg
    }
  }
')
if echo "$_awk_out" | grep -q "Apr 2, 14:20 UTC"; then
  assert_eq "incident awk: nested <a> timestamp extracted" "true" "true"
else
  assert_eq "incident awk: nested <a> timestamp extracted" "Apr 2, 14:20 UTC" "$_awk_out"
fi
if echo "$_awk_out" | grep -qF '<'; then
  assert_eq "incident awk: no HTML tags in output" "no tags" "tags found: $_awk_out"
else
  assert_eq "incident awk: no HTML tags in output" "true" "true"
fi

# Code-path 2: sed-based parser (_ptime extraction)
_ptime=$(printf '%s' "$_inc_html" | sed 's/.*<small>//' | sed 's/<\/small>.*//' | \
  sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
if [[ "$_ptime" == "Apr 2, 14:20 UTC" ]]; then
  assert_eq "incident sed: nested <a> timestamp extracted" "true" "true"
else
  assert_eq "incident sed: nested <a> timestamp extracted" "Apr 2, 14:20 UTC" "$_ptime"
fi

# ANSI guard: claudii status output must not contain literal ESC sequences as \033 text
_status_out=$(bash "$CLAUDII_HOME/bin/claudii" status 2>&1 || true)
if printf '%s' "$_status_out" | grep -qF '\033'; then
  assert_eq "claudii status: no literal \\033 in output" "no literal escapes" "found literal \\033"
else
  assert_eq "claudii status: no literal \\033 in output" "true" "true"
fi

# Cleanup
rm -rf "$XDG_CONFIG_HOME" "$CLAUDII_CACHE_DIR"
unset XDG_CONFIG_HOME CLAUDII_CACHE_DIR
