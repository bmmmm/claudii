# touches: lib/cmd/insights.sh lib/render.sh bin/claudii-insights lib/insights.jq

# test_tokens.sh — claudii tokens (token breakdown by type / model / day)
# End-to-end against a synthetic project tree, mirroring test_cache.sh. The
# hit-rate denominator (cache_read / (cache_read + cache_create + input)) is the
# load-bearing assertion: a naive cache_read/(cache_read+input) pins at ~100%.

_TOK_TMPDIRS=()
trap 'rm -rf "${_TOK_TMPDIRS[@]}" 2>/dev/null' EXIT

_TOK_PROJ="$(mktemp -d)"; _TOK_TMPDIRS+=("$_TOK_PROJ")
_TOK_CACHE="$(mktemp -d)"; _TOK_TMPDIRS+=("$_TOK_CACHE")

mkdir -p "$_TOK_PROJ/-test-project"

_SID="aaaaaaaa-bbbb-cccc-dddd-ffffffffffff"
_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_JSONL="$_TOK_PROJ/-test-project/$_SID.jsonl"

# Two assistant messages with controlled token counts:
#   Opus   in=50  out=200 cache_read=900 cache_create=50 → hit 900/1000 = 90%
#   Sonnet in=100 out=100 cache_read=700 cache_create=200 → hit 700/1000 = 70%
# Day total (today): in+out = 450, hit = 1600/(1600+150+250) = 80%.
{
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"role":"assistant","model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":50,"output_tokens":200,"cache_read_input_tokens":900,"cache_creation_input_tokens":50}}}\n' "$_TS" "$_SID"
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"role":"assistant","model":"claude-sonnet-4-6","stop_reason":"end_turn","usage":{"input_tokens":100,"output_tokens":100,"cache_read_input_tokens":700,"cache_creation_input_tokens":200}}}\n' "$_TS" "$_SID"
} > "$_JSONL"

_TOK_OUT=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens 2>&1)
_TOK_RC=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens >/dev/null 2>&1; echo $?)

assert_eq "tokens: exit 0"           "0" "$_TOK_RC"
assert_eq "tokens: produces output"  "0" "$([ -z "$_TOK_OUT" ] && echo 1 || echo 0)"
assert_no_literal_ansi "tokens: no literal \\033 in output" "$_TOK_OUT"

# ── Header + section structure ──
assert_contains "tokens: header"          "claudii tokens" "$_TOK_OUT"
assert_contains "tokens: window note"     "last 7 days"    "$_TOK_OUT"
assert_contains "tokens: by-type section" "By type"        "$_TOK_OUT"
assert_contains "tokens: throughput note" "throughput"     "$_TOK_OUT"
assert_contains "tokens: by-model section" "By model"      "$_TOK_OUT"
assert_contains "tokens: by-day section"  "By day"         "$_TOK_OUT"

# ── By type: all four buckets present ──
assert_contains "tokens: type cache read"  "cache read"  "$_TOK_OUT"
assert_contains "tokens: type cache write" "cache write" "$_TOK_OUT"
assert_contains "tokens: type input"       "input"       "$_TOK_OUT"
assert_contains "tokens: type output"      "output"      "$_TOK_OUT"

# ── By model: D-grid separators + labels + column headers ──
assert_contains "tokens: D-grid vertical rule"  "│"          "$_TOK_OUT"
assert_contains "tokens: D-grid cross rule"     "┼"          "$_TOK_OUT"
assert_contains "tokens: model opus label"      "Opus 4.8"   "$_TOK_OUT"
assert_contains "tokens: model sonnet label"    "Sonnet 4.6" "$_TOK_OUT"
assert_contains "tokens: D-grid cache-rd column" "cache rd"  "$_TOK_OUT"
assert_contains "tokens: D-grid cache-wr column" "cache wr"  "$_TOK_OUT"

# ── Hit-rate denominator: cache_read/(read+create+input), NOT read/(read+input) ──
# Opus 90%, Sonnet 70%. A naive read/(read+input) would give 947/950 ≈ 95% for
# Opus and ~88% for Sonnet — neither value appears, proving cache_create is in
# the denominator. (Regression guard for the always-100%-hit bug.)
assert_contains "tokens: opus hit 90% (read/(read+create+input))"   "90%" "$_TOK_OUT"
assert_contains "tokens: sonnet hit 70% (read/(read+create+input))" "70%" "$_TOK_OUT"

# ── By day: Today label + day-level hit rate (80%) ──
assert_contains "tokens: today label"   "Today" "$_TOK_OUT"
assert_contains "tokens: by-day hit 80%" "80%"   "$_TOK_OUT"

# ── Per-session JSON cache populated ──
assert_eq "tokens: per-session JSON cache exists" "1" \
  "$([ -s "$_TOK_CACHE/insights/$_SID.json" ] && echo 1 || echo 0)"

# ── Custom --days window note ──
_TOK_OUT_30=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens --days 30 2>&1)
assert_contains "tokens --days 30: window note" "last 30 days" "$_TOK_OUT_30"

# ── Cycleable named windows (today / 7d / 30d / year) resolve without --days ──
# The shared _insights_window helper maps named tokens + <N>d to a day count;
# the header note proves which window was selected.
_TOK_TODAY=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens today 2>&1)
assert_contains "tokens today: 1-day window labelled 'today'" "today"        "$_TOK_TODAY"
assert_not_contains "tokens today: no 'last 1 days' grammar"  "last 1 days"  "$_TOK_TODAY"

_TOK_30D=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens 30d 2>&1)
assert_contains "tokens 30d: resolves to last 30 days"  "last 30 days"  "$_TOK_30D"

_TOK_MONTH=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens month 2>&1)
assert_contains "tokens month: alias for 30 days"  "last 30 days"  "$_TOK_MONTH"

_TOK_YEAR=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens year 2>&1)
assert_contains "tokens year: resolves to 365 days"  "last 365 days"  "$_TOK_YEAR"

# ── Unknown window token → actionable error, not silent fall-through ──
_TOK_BAD=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens lastweek 2>&1; echo "rc=$?")
assert_contains "tokens lastweek: names the bad token"  "unknown tokens argument: lastweek"  "$_TOK_BAD"
assert_contains "tokens lastweek: suggests valid windows" "today|7d|30d|year"  "$_TOK_BAD"
assert_contains "tokens lastweek: exit 1"  "rc=1"  "$_TOK_BAD"

# ── Empty cache renders the empty-state line ──
_TOK_EPROJ="$(mktemp -d)"; _TOK_TMPDIRS+=("$_TOK_EPROJ")
_TOK_ECACHE="$(mktemp -d)"; _TOK_TMPDIRS+=("$_TOK_ECACHE")
_TOK_EOUT=$(CLAUDE_PROJECTS_DIR="$_TOK_EPROJ" CLAUDII_CACHE_DIR="$_TOK_ECACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens 2>&1)
assert_contains "tokens (empty): empty-state message" "No insight data" "$_TOK_EOUT"

# ── --days validation: bad value errors, not "No insight data" ──
_TOK_DV=$(CLAUDE_PROJECTS_DIR="$_TOK_PROJ" CLAUDII_CACHE_DIR="$_TOK_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" tokens --days foo 2>&1; echo "rc=$?")
assert_contains "tokens --days foo: actionable error" "positive integer" "$_TOK_DV"
assert_contains "tokens --days foo: exit 1" "rc=1" "$_TOK_DV"
assert_not_contains "tokens --days foo: no misleading no-data message" "No insight data" "$_TOK_DV"

# ── --help short-circuits before any data access ──
_TOK_HELP=$(bash "$CLAUDII_HOME/bin/claudii" tokens --help 2>&1)
assert_contains "tokens --help: usage line" "Usage: claudii tokens" "$_TOK_HELP"

unset _SID _TS _JSONL _TOK_OUT _TOK_RC _TOK_OUT_30 _TOK_EOUT _TOK_DV _TOK_HELP
unset _TOK_TODAY _TOK_30D _TOK_MONTH _TOK_YEAR _TOK_BAD
