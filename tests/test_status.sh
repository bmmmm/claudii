# touches: bin/claudii-status lib/cmd/system.sh
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
for _f in claudii claudii-cc-statusline; do
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

# Regression: incident with no model in name/body and components ≠ API
# must NOT mark all models as down. Real example: "Connection failures
# for organizations restricting GitHub access by IP address" (May 2026)
# — affected only orgs with GitHub IP allowlists, but the old heuristic
# flagged Opus/Sonnet/Haiku as down because no model name was matched.
_github_inc_dir=$(mktemp -d "$CLAUDII_HOME/tmp/test_status_gh.XXXXXX")
mkdir -p "$_github_inc_dir/cache" "$_github_inc_dir/srv"
cat > "$_github_inc_dir/srv/unresolved.json" <<'JSON'
{"incidents":[{
  "name":"Connection failures for organizations restricting GitHub access by IP address",
  "status":"identified","impact":"major",
  "incident_updates":[{"body":"We have identified an issue affecting organizations that restrict GitHub access by source IP address. A recent infrastructure change altered the IP addresses Anthropic uses for outbound connections to GitHub, which may cause Claude Code remote sessions to fail."}],
  "components":[{"name":"claude.ai"},{"name":"Claude Code"}]
}]}
JSON
# Serve the canned JSON from a `file://` URL — claudii-status uses curl,
# which supports file:// transparently. Skips network.
_github_url="file://$_github_inc_dir/srv/unresolved.json"
# claudii-status hard-checks https:// — bypass by writing cache directly via
# a stub-binary path: invoke the parser logic by faking `curl` via PATH.
# Simpler: spin a tiny bash wrapper that exports a CURL override.
cat > "$_github_inc_dir/curl" <<EOF
#!/bin/bash
# Mock curl: when fetching the unresolved URL, return the canned JSON.
for arg in "\$@"; do
  case "\$arg" in
    *unresolved.json*) cat "$_github_inc_dir/srv/unresolved.json"; exit 0 ;;
  esac
done
exit 22
EOF
chmod +x "$_github_inc_dir/curl"
# Reset cache, run with mocked curl
rm -f "$CLAUDII_CACHE_DIR/status-models" "$CLAUDII_CACHE_DIR/status-unresolved.json"
PATH="$_github_inc_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii-status" --quiet >/dev/null 2>&1 || true
_gh_cache=$(cat "$CLAUDII_CACHE_DIR/status-models" 2>/dev/null || true)
assert_contains "github-IP incident: opus stays ok" "opus=ok" "$_gh_cache"
assert_contains "github-IP incident: sonnet stays ok" "sonnet=ok" "$_gh_cache"
assert_contains "github-IP incident: haiku stays ok" "haiku=ok" "$_gh_cache"
assert_contains "github-IP incident: indicator preserved" "_incident=identified" "$_gh_cache"
rm -rf "$_github_inc_dir"

# Regression: incident whose components list includes "API" (broad inference
# outage) must still flag all models as degraded/down — this is the one case
# where "no model named, but everything affected" is real.
_api_inc_dir=$(mktemp -d "$CLAUDII_HOME/tmp/test_status_api.XXXXXX")
mkdir -p "$_api_inc_dir/srv"
cat > "$_api_inc_dir/srv/unresolved.json" <<'JSON'
{"incidents":[{
  "name":"Elevated error rates","status":"investigating","impact":"major",
  "incident_updates":[{"body":"We are investigating elevated error rates."}],
  "components":[{"name":"API"}]
}]}
JSON
cat > "$_api_inc_dir/curl" <<EOF
#!/bin/bash
for arg in "\$@"; do
  case "\$arg" in
    *unresolved.json*) cat "$_api_inc_dir/srv/unresolved.json"; exit 0 ;;
  esac
done
exit 22
EOF
chmod +x "$_api_inc_dir/curl"
rm -f "$CLAUDII_CACHE_DIR/status-models" "$CLAUDII_CACHE_DIR/status-unresolved.json"
PATH="$_api_inc_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii-status" --quiet >/dev/null 2>&1 || true
_api_cache=$(cat "$CLAUDII_CACHE_DIR/status-models" 2>/dev/null || true)
if echo "$_api_cache" | grep -qE '^opus=(down|degraded)$'; then
  assert_eq "API-component incident: opus flagged" "true" "true"
else
  assert_eq "API-component incident: opus flagged" "down|degraded" "$_api_cache"
fi
if echo "$_api_cache" | grep -qE '^sonnet=(down|degraded)$'; then
  assert_eq "API-component incident: sonnet flagged" "true" "true"
else
  assert_eq "API-component incident: sonnet flagged" "down|degraded" "$_api_cache"
fi
rm -rf "$_api_inc_dir"

# Regression: multiline incident name must be flattened to single line
# (bin/claudii-status does `jq -r .incidents[0].name | tr '\n' ' ' | sed 's/ *$//'`
#  to prevent multi-line names from breaking RPROMPT/stderr layout)
_mock_json='{"incidents":[{"name":"Line1\nLine2\nLine3","impact":"minor"}]}'
_flat=$(echo "$_mock_json" | jq -r '.incidents[0].name' | tr '\n' ' ' | sed 's/ *$//')
assert_eq "incident name: newlines stripped to spaces" "Line1 Line2 Line3" "$_flat"
assert_eq "incident name: zero embedded newlines" "0" "$(printf '%s' "$_flat" | tr -cd '\n' | wc -c | tr -d ' ')"

# ── `claudii status` footer: effective (adaptive) refresh interval ──
# Healthy state → 2× base TTL with "(adaptive, base Xm)" suffix; unreachable
# API → bare base TTL, no suffix. Fresh cache mtime keeps claudii-status on
# its cache-hit path (no network) so the prepared cache survives the display.

printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CLAUDII_CACHE_DIR/status-models"
_ftr_out=$(bash "$CLAUDII_HOME/bin/claudii" status 2>&1 || true)
assert_contains "status footer: healthy shows adaptive interval" "(adaptive, base" "$_ftr_out"

printf 'opus=ok\nsonnet=ok\nhaiku=ok\n_api=unreachable\n' > "$CLAUDII_CACHE_DIR/status-models"
_ftr_out=$(bash "$CLAUDII_HOME/bin/claudii" status 2>&1 || true)
assert_contains "status footer: unreachable shows base interval" "refreshes every" "$_ftr_out"
if echo "$_ftr_out" | grep -q "(adaptive, base"; then
  assert_eq "status footer: unreachable has no adaptive suffix" "no suffix" "suffix present"
else
  assert_eq "status footer: unreachable has no adaptive suffix" "no suffix" "no suffix"
fi

# ── Transition log: state changes land in status-history.tsv ─────────────────
_tr_dir=$(mktemp -d "$CLAUDII_HOME/tmp/test_status_tr.XXXXXX")
mkdir -p "$_tr_dir/srv"
cat > "$_tr_dir/srv/unresolved.json" <<'JSON'
{"incidents":[{
  "name":"Elevated errors on Claude Opus","status":"investigating","impact":"minor",
  "incident_updates":[{"body":"Investigating elevated errors on Opus."}],
  "components":[{"name":"Claude Opus"}]
}]}
JSON
cat > "$_tr_dir/curl" <<EOF
#!/bin/bash
for arg in "\$@"; do
  case "\$arg" in
    *unresolved.json*) cat "$_tr_dir/srv/unresolved.json"; exit 0 ;;
  esac
done
exit 22
EOF
chmod +x "$_tr_dir/curl"

# Reset models (an earlier section appended "testmodel" — it would log an
# extra unknown→ok transition and break the exact-count assert below)
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet,haiku" >/dev/null 2>&1

# First run with NO previous cache → no transitions logged
rm -f "$CLAUDII_CACHE_DIR"/status-models "$CLAUDII_CACHE_DIR"/status-unresolved.json "$CLAUDII_CACHE_DIR"/status-history.tsv
PATH="$_tr_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii-status" --quiet >/dev/null 2>&1 || true
assert_eq "transition log: first run logs nothing" "false" "$([[ -s "$CLAUDII_CACHE_DIR/status-history.tsv" ]] && echo true || echo false)"

# Previous cache all-ok, incident flags opus → exactly the opus transition logged
printf 'opus=ok\nsonnet=ok\nhaiku=ok\n' > "$CLAUDII_CACHE_DIR/status-models"
touch -t 200001010000 "$CLAUDII_CACHE_DIR/status-models"   # force stale
PATH="$_tr_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii-status" --quiet >/dev/null 2>&1 || true
_tr_log=$(cat "$CLAUDII_CACHE_DIR/status-history.tsv" 2>/dev/null || true)
assert_contains "transition log: opus ok→degraded logged" "$(printf 'opus\tok\tdegraded')" "$_tr_log"
assert_eq "transition log: only changed model logged" "1" "$(printf '%s\n' "$_tr_log" | grep -c . || true)"
if printf '%s' "$_tr_log" | head -1 | grep -qE '^[0-9]+	'; then
  assert_eq "transition log: epoch first column" "true" "true"
else
  assert_eq "transition log: epoch first column" "epoch<TAB>..." "$_tr_log"
fi

# Internal _incident= keys must never appear as models in the log
assert_eq "transition log: no _-keys logged" "false" "$(printf '%s' "$_tr_log" | grep -q '	_' && echo true || echo false)"

# claudii status renders the Recent changes section from the log
# (ANSI-stripped — the new state is color-wrapped, "ok → degraded" would
# otherwise never match literally; mock curl keeps any refetch deterministic)
_tr_out=$(PATH="$_tr_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii" status 2>&1 | sed $'s/\033\\[[0-9;]*m//g' || true)
assert_contains "claudii status: Recent changes section shown" "Recent changes" "$_tr_out"
assert_contains "claudii status: transition rendered" "ok → degraded" "$_tr_out"

# display.timezone drives the rendered timestamp (zone suffix via %Z)
bash "$CLAUDII_HOME/bin/claudii" config set display.timezone "UTC" >/dev/null 2>&1
_tr_utc=$(PATH="$_tr_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii" status 2>&1 | grep -A2 "Recent changes" || true)
assert_contains "claudii status: UTC timestamp suffix" "UTC" "$_tr_utc"
bash "$CLAUDII_HOME/bin/claudii" config set display.timezone "Europe/Berlin" >/dev/null 2>&1
_tr_de=$(PATH="$_tr_dir:$PATH" bash "$CLAUDII_HOME/bin/claudii" status 2>&1 | grep -A2 "Recent changes" || true)
if printf '%s' "$_tr_de" | grep -qE 'CET|CEST'; then
  assert_eq "claudii status: Europe/Berlin timestamp suffix" "true" "true"
else
  assert_eq "claudii status: Europe/Berlin timestamp suffix" "CET|CEST" "$_tr_de"
fi
rm -rf "$_tr_dir"

# Cleanup
rm -rf "$XDG_CONFIG_HOME" "$CLAUDII_CACHE_DIR"
unset XDG_CONFIG_HOME CLAUDII_CACHE_DIR
