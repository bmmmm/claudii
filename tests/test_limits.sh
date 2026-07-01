# touches: lib/cmd/insights.sh lib/render.sh lib/timefmt.sh bin/claudii-insights lib/insights.jq

# test_limits.sh — claudii limits (rate-limit hits)
# Three synthetic limit hits (two at 11:xx UTC under Opus, one at 20:00 under
# Haiku) exercise the list, the per-model tally, the hour strip and the
# cluster insight. TZ=UTC pins the hour buckets so the assertions are stable.

_LIM_TMPDIRS=()
trap 'rm -rf "${_LIM_TMPDIRS[@]}" 2>/dev/null' EXIT
_LIM_PROJ="$(mktemp -d)"; _LIM_TMPDIRS+=("$_LIM_PROJ")
_LIM_CACHE="$(mktemp -d)"; _LIM_TMPDIRS+=("$_LIM_CACHE")
mkdir -p "$_LIM_PROJ/-test-project"

_SID="33333333-4444-5555-6666-777777777777"
_JSONL="$_LIM_PROJ/-test-project/$_SID.jsonl"

# A limit hit = a synthetic assistant message (model:"<synthetic>",
# isApiErrorMessage:true, error:"rate_limit", text "hit your session limit");
# its model is the last real assistant model seen. Two hits in hour 11
# (Opus), one in hour 20 (Haiku) → cluster around 11:00, tally 2× Opus ·
# 1× Haiku. A monthly-spend-limit hit is interspersed to confirm it's
# excluded (different budget than the 5h session limit this command reports).
{
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T11:29:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T11:30:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 2am (Europe/Berlin)"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T11:44:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T11:45:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 3am (Europe/Berlin)"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T12:00:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your monthly spend limit · raise it at claude.ai/settings/usage"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-11T19:59:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"claude-haiku-4-5-20251001","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-11T20:00:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 9pm (Europe/Berlin)"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}'
} > "$_JSONL"

_LIM_OUT=$(TZ=UTC CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits --days 60 2>&1)
_LIM_RC=$(TZ=UTC CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits --days 60 >/dev/null 2>&1; echo $?)

assert_eq "limits: exit 0"          "0" "$_LIM_RC"
assert_eq "limits: produces output" "0" "$([ -z "$_LIM_OUT" ] && echo 1 || echo 0)"
assert_no_literal_ansi "limits: no literal \\033 in output" "$_LIM_OUT"

assert_contains "limits: header"          "Rate limits"   "$_LIM_OUT"
assert_contains "limits: account-wide"    "account-wide"  "$_LIM_OUT"
assert_contains "limits: opus in tally"   "Opus 4.8"      "$_LIM_OUT"
assert_contains "limits: haiku in tally"  "Haiku 4.5"     "$_LIM_OUT"
assert_contains "limits: hour strip label" "when"         "$_LIM_OUT"
assert_contains "limits: model tally"     "models"        "$_LIM_OUT"
assert_contains "limits: cluster insight (UTC hour 11)" "11:00" "$_LIM_OUT"
# Per-day distribution: two Opus hits on 2026-06-10 (UTC) collapse into one
# "2×" day row — the old flat list would have printed two separate lines.
assert_contains "limits: by-day section label" "by day"   "$_LIM_OUT"
assert_contains "limits: by-day row shows local date" "10 Jun" "$_LIM_OUT"
assert_contains "limits: same-day hits aggregated to 2×" "2×" "$_LIM_OUT"

# ── No hits → clear-runway line, exit 0 ──
_LIM_NPROJ="$(mktemp -d)"; _LIM_TMPDIRS+=("$_LIM_NPROJ")
_LIM_NCACHE="$(mktemp -d)"; _LIM_TMPDIRS+=("$_LIM_NCACHE")
mkdir -p "$_LIM_NPROJ/-test-project"
printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T11:00:00Z","sessionId":"nolimit-1","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' \
  > "$_LIM_NPROJ/-test-project/nolimit-1.jsonl"
_LIM_NOUT=$(CLAUDE_PROJECTS_DIR="$_LIM_NPROJ" CLAUDII_CACHE_DIR="$_LIM_NCACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits --days 60 2>&1; echo "rc=$?")
assert_contains "limits (no hits): clear-runway line" "No rate-limit hits" "$_LIM_NOUT"
assert_contains "limits (no hits): exit 0" "rc=0" "$_LIM_NOUT"

# ── Empty cache → empty-state line ──
_LIM_EPROJ="$(mktemp -d)"; _LIM_TMPDIRS+=("$_LIM_EPROJ")
_LIM_ECACHE="$(mktemp -d)"; _LIM_TMPDIRS+=("$_LIM_ECACHE")
_LIM_EOUT=$(CLAUDE_PROJECTS_DIR="$_LIM_EPROJ" CLAUDII_CACHE_DIR="$_LIM_ECACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits 2>&1)
assert_contains "limits (empty): empty-state message" "No insight data" "$_LIM_EOUT"

# ── Cycleable named window: `limits 90d` covers the same hits as --days 60 ──
_LIM_90D=$(TZ=UTC CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits 90d 2>&1)
assert_contains "limits 90d: named window shows the hits" "Rate limits" "$_LIM_90D"
_LIM_BAD=$(CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits bogus 2>&1; echo "rc=$?")
assert_contains "limits bogus: actionable unknown-arg error" "unknown limits argument: bogus" "$_LIM_BAD"
assert_contains "limits bogus: exit 1" "rc=1" "$_LIM_BAD"
unset _LIM_90D _LIM_BAD

# ── --days validation + --help ──
_LIM_DV=$(CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits --days foo 2>&1; echo "rc=$?")
assert_contains "limits --days foo: actionable error" "positive integer" "$_LIM_DV"
assert_contains "limits --days foo: exit 1" "rc=1" "$_LIM_DV"
_LIM_HELP=$(bash "$CLAUDII_HOME/bin/claudii" limits --help 2>&1)
assert_contains "limits --help: usage" "Usage: claudii limits" "$_LIM_HELP"

# ── --json: hits newest-first + per-model tally, well-formed ──
# 3 hits: 2026-06-11 20:00 (Haiku), 2026-06-10 11:45 + 11:29 (Opus). Window 90d
# covers them (same lifespan as the --days 60 run above).
_LIM_JSON=$(TZ=UTC CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits --json --days 90 2>&1)
assert_eq "limits --json: well-formed JSON" "0" \
  "$(printf '%s' "$_LIM_JSON" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "limits --json: total=3" "3" \
  "$(printf '%s' "$_LIM_JSON" | jq -r '.total')"
assert_eq "limits --json: 3 hits listed" "3" \
  "$(printf '%s' "$_LIM_JSON" | jq -r '.hits | length')"
assert_eq "limits --json: newest hit first (2026-06-11 20:00)" "2026-06-11T20:00:00Z" \
  "$(printf '%s' "$_LIM_JSON" | jq -r '.hits[0].timestamp')"
assert_contains "limits --json: by_model top is opus" "opus" \
  "$(printf '%s' "$_LIM_JSON" | jq -r '.by_model[0].model')"
assert_eq "limits --json: opus hit count 2" "2" \
  "$(printf '%s' "$_LIM_JSON" | jq -r '.by_model[] | select(.model|test("opus")) | .count')"
_LIM_TSV=$(CLAUDE_PROJECTS_DIR="$_LIM_PROJ" CLAUDII_CACHE_DIR="$_LIM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" limits --tsv 2>&1; echo "rc=$?")
assert_contains "limits --tsv: rejected, points to --json" "use --json" "$_LIM_TSV"
assert_contains "limits --tsv: exit 1" "rc=1" "$_LIM_TSV"

unset _SID _JSONL _LIM_OUT _LIM_RC _LIM_NOUT _LIM_EOUT _LIM_DV _LIM_HELP
unset _LIM_JSON _LIM_TSV
