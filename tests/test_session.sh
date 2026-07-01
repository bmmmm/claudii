# touches: lib/cmd/insights.sh lib/render.sh lib/timefmt.sh bin/claudii-insights lib/insights.jq

# test_session.sh — claudii session <id> (per-session drilldown)
# A 4-message synthetic transcript exercises every section the command renders:
# the token split, the thinking-block count, tools with an error marker, the
# subagent breakdown, stop reasons, and a rate-limit hit (the one path that real
# sessions rarely produce on demand).

_SESS_TMPDIRS=()
trap 'rm -rf "${_SESS_TMPDIRS[@]}" 2>/dev/null' EXIT

_SESS_PROJ="$(mktemp -d)"; _SESS_TMPDIRS+=("$_SESS_PROJ")
_SESS_CACHE="$(mktemp -d)"; _SESS_TMPDIRS+=("$_SESS_CACHE")
mkdir -p "$_SESS_PROJ/-test-project"

_SID="11111111-2222-3333-4444-555555555555"
_JSONL="$_SESS_PROJ/-test-project/$_SID.jsonl"

# Tokens: in 50+100=150, out 200+100=300, cache_read 900+700=1600,
#         cache_create 50+200=250. work = in+out+cw = 700 →
#         input 21% · output 42% · cache write 35%; cache-read hit 1600/2000 = 80%.
# Tools: Bash(1, 1 error) · Agent(1) · Read(1) = 3 calls, 1 err.
# Subagents: Explore ×1. Stop reasons: end_turn ×1, tool_use ×1.
# Thinking: 2 blocks. Limit hit: 1 (model = last assistant = Opus 4.8).
# Duration: 10:00:00 → 10:30:00 = 30m.
{
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T10:00:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":50,"output_tokens":200,"cache_read_input_tokens":900,"cache_creation_input_tokens":50},"content":[{"type":"thinking","thinking":"x"},{"type":"tool_use","id":"b1","name":"Bash","input":{}},{"type":"tool_use","id":"a1","name":"Agent","input":{"subagent_type":"Explore"}}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-06-10T10:05:00Z","sessionId":"'"$_SID"'","toolUseResult":{"agentId":"sub1","agentType":"Explore"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"boom"},{"type":"tool_result","tool_use_id":"a1","content":"agent done"}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T10:20:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"claude-opus-4-8","stop_reason":"tool_use","usage":{"input_tokens":100,"output_tokens":100,"cache_read_input_tokens":700,"cache_creation_input_tokens":200},"content":[{"type":"thinking","thinking":"y"},{"type":"tool_use","id":"r1","name":"Read","input":{}}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-06-10T10:25:00Z","sessionId":"'"$_SID"'","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r1","content":"file contents"}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-06-10T10:30:00Z","sessionId":"'"$_SID"'","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 2am (Europe/Berlin)"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}'
} > "$_JSONL"

_SESS_OUT=$(CLAUDE_PROJECTS_DIR="$_SESS_PROJ" CLAUDII_CACHE_DIR="$_SESS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" session 11111111 2>&1)
_SESS_RC=$(CLAUDE_PROJECTS_DIR="$_SESS_PROJ" CLAUDII_CACHE_DIR="$_SESS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" session 11111111 >/dev/null 2>&1; echo $?)

assert_eq "session: exit 0"          "0" "$_SESS_RC"
assert_eq "session: produces output" "0" "$([ -z "$_SESS_OUT" ] && echo 1 || echo 0)"
assert_no_literal_ansi "session: no literal \\033 in output" "$_SESS_OUT"

# ── Header + status line ──
assert_contains "session: header"            "claudii session" "$_SESS_OUT"
assert_contains "session: short id"          "11111111"        "$_SESS_OUT"
assert_contains "session: dominant model"    "Opus 4.8"        "$_SESS_OUT"
assert_contains "session: duration"          "30m"             "$_SESS_OUT"

# ── Tokens: 4-way split + shares + cache-read hit ──
assert_contains "session: tokens section"  "Tokens"      "$_SESS_OUT"
assert_contains "session: token input"     "input"       "$_SESS_OUT"
assert_contains "session: token output"    "output"      "$_SESS_OUT"
assert_contains "session: token cache wr"  "cache write" "$_SESS_OUT"
assert_contains "session: token cache rd"  "cache read"  "$_SESS_OUT"
assert_contains "session: input share 21%"  "21%"        "$_SESS_OUT"
assert_contains "session: output share 42%" "42%"        "$_SESS_OUT"
assert_contains "session: cachewr share 35%" "35%"       "$_SESS_OUT"
assert_contains "session: cache-read hit 80%" "80% hit"  "$_SESS_OUT"
assert_contains "session: thinking blocks"  "in 2 blocks" "$_SESS_OUT"

# ── Tools: header counts + rows + error marker ──
assert_contains "session: tools section"  "Tools"      "$_SESS_OUT"
assert_contains "session: tools calls"    "3 calls"    "$_SESS_OUT"
assert_contains "session: tools errors"   "1 err"      "$_SESS_OUT"
assert_contains "session: tool Bash"      "Bash"       "$_SESS_OUT"
assert_contains "session: tool Read"      "Read"       "$_SESS_OUT"
assert_contains "session: Bash error marker" "⚠ 1 err" "$_SESS_OUT"

# ── Subagents / stop reasons / limit hits ──
assert_contains "session: subagents line"  "Subagents"   "$_SESS_OUT"
assert_contains "session: subagent Explore" "Explore"    "$_SESS_OUT"
assert_contains "session: stop reasons"    "Stop reasons" "$_SESS_OUT"
assert_contains "session: stop end_turn"   "end_turn"    "$_SESS_OUT"
assert_contains "session: stop tool_use"   "tool_use"    "$_SESS_OUT"
assert_contains "session: limit hits line" "Limit hits"  "$_SESS_OUT"
assert_contains "session: limit account-wide" "account-wide" "$_SESS_OUT"
assert_contains "session: limit during model" "during Opus 4.8" "$_SESS_OUT"

# ── Per-session JSON cache populated ──
assert_eq "session: per-session JSON cache exists" "1" \
  "$([ -s "$_SESS_CACHE/insights/$_SID.json" ] && echo 1 || echo 0)"

# ── No-match id errors with an actionable hint, exit 1 ──
_SESS_NM=$(CLAUDE_PROJECTS_DIR="$_SESS_PROJ" CLAUDII_CACHE_DIR="$_SESS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" session zzzznomatch 2>&1; echo "rc=$?")
assert_contains "session (no match): actionable error" "no session matching" "$_SESS_NM"
assert_contains "session (no match): exit 1" "rc=1" "$_SESS_NM"

# ── No id → usage, exit 1 ──
_SESS_NA=$(CLAUDE_PROJECTS_DIR="$_SESS_PROJ" CLAUDII_CACHE_DIR="$_SESS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" session 2>&1; echo "rc=$?")
assert_contains "session (no arg): usage" "Usage: claudii session" "$_SESS_NA"
assert_contains "session (no arg): exit 1" "rc=1" "$_SESS_NA"

# ── --help → usage, exit 0 ──
_SESS_HELP=$(bash "$CLAUDII_HOME/bin/claudii" session --help 2>&1; echo "rc=$?")
assert_contains "session --help: usage" "Usage: claudii session" "$_SESS_HELP"
assert_contains "session --help: exit 0" "rc=0" "$_SESS_HELP"

# ── Regression: a cache missing first_seen must not shift the meta fields ──────
# The meta line emits first_seen/last_seen as possibly-"" — joined on a tab they
# collapse under IFS-whitespace and every column shifts left (Tools header would
# read "0 calls", thinking-blocks would be wrong). This orphan cache (no source
# transcript, so aggregate leaves it alone) has last_seen but NO first_seen.
_SESS_ORPH="deadbeef-0000-0000-0000-000000000000"
mkdir -p "$_SESS_CACHE/insights"
printf '%s\n' '{"schema_version":5,"sessionId":"'"$_SESS_ORPH"'","last_seen":"2026-06-10T10:30:00Z","days":{"2026-06-10|claude-opus-4-8":{"in_tok":10,"out_tok":20,"cache_read":100,"cache_create":5}},"models":{"claude-opus-4-8":{"in_tok":10,"cache_read":100,"cache_create":5}},"tools":{"Bash":7},"tool_errors":{},"stop_reasons":{},"subagent_types":{},"thinking_blocks":3,"limit_hits":[]}' \
  > "$_SESS_CACHE/insights/$_SESS_ORPH.json"
_SESS_ORPH_OUT=$(CLAUDE_PROJECTS_DIR="$_SESS_PROJ" CLAUDII_CACHE_DIR="$_SESS_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" session deadbeef 2>&1)
assert_contains "session (no first_seen): tool count not shifted" "7 calls"   "$_SESS_ORPH_OUT"
assert_contains "session (no first_seen): thinking not shifted"   "in 3 blocks" "$_SESS_ORPH_OUT"
assert_not_contains "session (no first_seen): no empty tool count" "0 calls" "$_SESS_ORPH_OUT"

unset _SID _JSONL _SESS_OUT _SESS_RC _SESS_NM _SESS_NA _SESS_HELP _SESS_ORPH _SESS_ORPH_OUT
