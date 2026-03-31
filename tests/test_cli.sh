# test_cli.sh — claudii CLI E2E tests

# version — when piped (no TTY) prints bare version number; with --json prints JSON
_bin_version=$(grep '^VERSION=' "$CLAUDII_HOME/bin/claudii" | head -1 | tr -d '"' | cut -d= -f2)
output=$(bash "$CLAUDII_HOME/bin/claudii" version 2>&1)
assert_contains "claudii version shows version" "$_bin_version" "$output"
output_json=$(bash "$CLAUDII_HOME/bin/claudii" version --json 2>&1)
assert_contains "claudii version --json shows version" "$_bin_version" "$output_json"
assert_contains "claudii version --json is valid json" '"version"' "$output_json"
unset _bin_version output_json

# help
output=$(bash "$CLAUDII_HOME/bin/claudii" help 2>&1)
assert_contains "help shows usage" "claudii" "$output"
assert_contains "help lists status command" "status" "$output"
assert_contains "help lists config command" "config" "$output"
assert_contains "help lists search command" "search" "$output"

# unknown command
output=$(bash "$CLAUDII_HOME/bin/claudii" nonexistent 2>&1 || true)
assert_contains "unknown command shows error" "Unknown command" "$output"

# shortcut s → status (must not be unknown command)
s_out=$(bash "$CLAUDII_HOME/bin/claudii" s 2>&1 || true)
assert_eq "shortcut s: not 'Unknown command'" "0" "$(echo "$s_out" | grep -c 'Unknown command' || true)"

# se must be shortcut for sessions (was: ss)
se_out=$(bash "$CLAUDII_HOME/bin/claudii" se 2>&1 || true)
assert_eq "shortcut se: not 'Unknown command'" "0" "$(echo "$se_out" | grep -c 'Unknown command' || true)"

# ss must still work as sessions shortcut
ss_out=$(bash "$CLAUDII_HOME/bin/claudii" ss 2>&1 || true)
assert_eq "shortcut ss: not 'Unknown command'" "0" "$(echo "$ss_out" | grep -c 'Unknown command' || true)"

# sessions: must not produce 'local: can only be used in a function' error
sess_err=$(bash "$CLAUDII_HOME/bin/claudii" sessions 2>&1 >/dev/null)
assert_eq "sessions: no 'local' outside function error" "0" "$(echo "$sess_err" | grep -c 'local: can only be used' || true)"

# doctor: must produce output (was silently empty)
doc_out=$(bash "$CLAUDII_HOME/bin/claudii" doctor 2>&1)
assert_eq "doctor: produces output" "0" "$([ -z "$doc_out" ] && echo 1 || echo 0)"
assert_matches "doctor: mentions claude" "claude|Claude" "$doc_out"

# layers: must not show obsolete 'show model' command
layers_out=$(bash "$CLAUDII_HOME/bin/claudii" layers 2>&1)
assert_eq "layers: no obsolete 'show model' reference" "0" "$(echo "$layers_out" | grep -c 'show model' || true)"
assert_contains "layers: shows ClaudeStatus" "ClaudeStatus" "$layers_out"

# dashboard: on/off only
DASH_CLI_TMP="$(mktemp -d)"
export CLAUDII_CACHE_DIR="$DASH_CLI_TMP"
export XDG_CONFIG_HOME="$DASH_CLI_TMP"
mkdir -p "$DASH_CLI_TMP/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$DASH_CLI_TMP/claudii/config.json"

out=$(bash "$CLAUDII_HOME/bin/claudii" dashboard off 2>&1)
assert_matches "dashboard off: success message" "disabled|off" "$out"
assert_eq "dashboard off: no error exit" "0" "$(bash "$CLAUDII_HOME/bin/claudii" dashboard off >/dev/null 2>&1; echo $?)"

out=$(bash "$CLAUDII_HOME/bin/claudii" dashboard on 2>&1)
assert_matches "dashboard on: success message" "enabled|on" "$out"

out=$(bash "$CLAUDII_HOME/bin/claudii" dashboard auto 2>&1 || true)
assert_eq "dashboard auto: unknown subcommand error" "1" "$(bash "$CLAUDII_HOME/bin/claudii" dashboard auto >/dev/null 2>&1; echo $?)"

# dash command should be removed (use dashboard instead)
dash_out=$(bash "$CLAUDII_HOME/bin/claudii" dash 2>&1 || true)
assert_matches "dash: removed or redirected to dashboard" "Unknown command|dashboard|Dashboard" "$dash_out"

rm -rf "$DASH_CLI_TMP"
unset CLAUDII_CACHE_DIR XDG_CONFIG_HOME DASH_CLI_TMP out

# about must NOT exist as standalone command — CHANGELOG says removed
# If merged into version, piped output is bare version number (no "Unknown command")
# If truly removed, it would return "Unknown command" + exit 1
about_out=$(bash "$CLAUDII_HOME/bin/claudii" about 2>&1 || true)
about_unknown=$(echo "$about_out" | grep -c "Unknown command" || true)
assert_eq "about: removed or merged (no 'Unknown command' in output)" "0" "$about_unknown"
# about must NOT show a separate standalone about-style block (the old clunky output)
about_has_old_heading=$(echo "$about_out" | grep -c "Claude Interaction Intelligence" || true)
assert_eq "about: old standalone about block is gone" "0" "$about_has_old_heading"

# si: shorthand for sessions-inactive — must not be unknown command
si_out=$(bash "$CLAUDII_HOME/bin/claudii" si 2>&1 || true)
assert_eq "si: not 'Unknown command'" "0" "$(echo "$si_out" | grep -c 'Unknown command' || true)"

# sessions-inactive: must produce output (not empty, not crash)
si_long_out=$(bash "$CLAUDII_HOME/bin/claudii" sessions-inactive 2>&1 || true)
assert_eq "sessions-inactive: produces output" "0" "$([ -z "$si_long_out" ] && echo 1 || echo 0)"

# changelog: must contain the current VERSION number
_changelog_version=$(grep '^VERSION=' "$CLAUDII_HOME/bin/claudii" | head -1 | cut -d'"' -f2)
changelog_out=$(bash "$CLAUDII_HOME/bin/claudii" changelog 2>&1 || true)
assert_contains "changelog: contains version" "$_changelog_version" "$changelog_out"
unset _changelog_version changelog_out si_out si_long_out

# cost: must run without declare -A error (bash 3.2 compat — macOS default shell)
CLI_TMP="$(mktemp -d)"
export CLAUDII_CACHE_DIR="$CLI_TMP"
# Write a minimal session cache so cost has data to process
printf '%s\n' "model=Sonnet 4.6" "ctx_pct=50" "cost=1.23" > "$CLI_TMP/session-costtest"
touch "$CLI_TMP/session-costtest"
cost_out=$(bash "$CLAUDII_HOME/bin/claudii" cost 2>&1)
cost_err=$(bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 >/dev/null)
assert_eq "cost: no declare -A error on bash 3.2" "" "$(echo "$cost_err" | grep 'declare' || true)"
assert_eq "cost: no invalid option error" "0" "$(echo "$cost_err" | grep -c 'invalid option' || true)"
rm -rf "$CLI_TMP"
unset CLAUDII_CACHE_DIR CLI_TMP cost_out cost_err

# bare claudii — ANSI guard + injection guard
bare_out=$(bash "$CLAUDII_HOME/bin/claudii" 2>&1)
assert_no_literal_ansi "bare claudii: no literal \\033 in output" "$bare_out"

_inj_tmp="$(mktemp -d)"
printf 'model=Sonnet 4.6\nctx_pct=50\ncost=0.50\nrate_5h=40\nrate_7d=60\nreset_5h=\nreset_7d=\nsession_id=injtest00\nworktree=\nagent=\nmodel_id=\nburn_eta=\nppid=%s\n' "$$" > "$_inj_tmp/session-injtest"
inj_out=$(CLAUDII_CACHE_DIR="$_inj_tmp" bash "$CLAUDII_HOME/bin/claudii" 2>&1 || true)
assert_no_literal_ansi "bare claudii: no literal \\033 even with injected session" "$inj_out"
assert_eq "bare claudii: no shell source leak" "0" \
  "$(echo "$inj_out" | grep -cF '_cfg_init' || true)"
rm -rf "$_inj_tmp"
unset bare_out _inj_tmp inj_out

# ── Session active detection: live PID + old file (>300s) → shown as active ──
# Regression for long-running tasks that don't update the session file for >5min.
_act_tmp="$(mktemp -d)"
_act_xdg="$_act_tmp/xdg"
mkdir -p "$_act_xdg/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$_act_xdg/claudii/config.json"
printf 'model=Sonnet 4.6\nctx_pct=60\ncost=1.00\nrate_5h=\nreset_5h=\nsession_id=acttest\nworktree=\nagent=\nppid=%s\n' "$$" > "$_act_tmp/session-acttest"
# Make the session file 310 seconds old (simulates idle Claude session)
_act_stale_ts=$(date -v-310S +%Y%m%d%H%M.%S 2>/dev/null || date -d "310 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
[[ -n "$_act_stale_ts" ]] && touch -t "$_act_stale_ts" "$_act_tmp/session-acttest"
act_out=$(CLAUDII_CACHE_DIR="$_act_tmp" XDG_CONFIG_HOME="$_act_xdg" bash "$CLAUDII_HOME/bin/claudii" 2>&1 || true)
# With live PID: sessions section shows "N active session" summary (not individual lines)
assert_contains "active session: live PID + old file → sessions summary shown" "active session" "$act_out"
assert_eq "active session: not counted as inactive" "0" \
  "$(echo "$act_out" | grep -c 'inactive' || true)"
rm -rf "$_act_tmp"
unset _act_tmp _act_xdg _act_stale_ts act_out

# sessions — ANSI guard
sess_out=$(bash "$CLAUDII_HOME/bin/claudii" sessions 2>&1 || true)
assert_no_literal_ansi "sessions: no literal \\033 in output" "$sess_out"
unset sess_out

# cost — ANSI guard + content check
_cost_tmp2="$(mktemp -d)"
cost_out2=$(CLAUDII_CACHE_DIR="$_cost_tmp2" bash "$CLAUDII_HOME/bin/claudii" cost 2>&1 || true)
assert_no_literal_ansi "cost: no literal \\033 in output" "$cost_out2"
assert_matches "cost: shows no-sessions text" "No session|keine" "$cost_out2"
rm -rf "$_cost_tmp2"
unset _cost_tmp2 cost_out2

# trends — ANSI guard
trends_out=$(bash "$CLAUDII_HOME/bin/claudii" trends 2>&1 || true)
assert_eq "trends: produces output" "0" "$([ -z "$trends_out" ] && echo 1 || echo 0)"
assert_no_literal_ansi "trends: no literal \\033 in output" "$trends_out"
unset trends_out

# doctor — ANSI guard
doc_out2=$(bash "$CLAUDII_HOME/bin/claudii" doctor 2>&1 || true)
assert_no_literal_ansi "doctor: no literal \\033 in output" "$doc_out2"
unset doc_out2

# agents — produces output
agents_out=$(bash "$CLAUDII_HOME/bin/claudii" agents 2>&1 || true)
assert_eq "agents: produces output" "0" "$([ -z "$agents_out" ] && echo 1 || echo 0)"
unset agents_out

# ── Gap 6 — Stale session GC hint in default view ─────────────────────────
# Create 6 fake session files with dead PPIDs and mtime 25h ago
STALE_HINT_TMP="$(mktemp -d)"
STALE_XDG="$STALE_HINT_TMP/xdg"
mkdir -p "$STALE_XDG/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$STALE_XDG/claudii/config.json"
export XDG_CONFIG_HOME="$STALE_HINT_TMP/xdg"
export CLAUDII_CACHE_DIR="$STALE_HINT_TMP"
# 25h ago in touch -t format: YYYYMMDDhhmm.ss
_stale_ts=$(date -v-90000S +%Y%m%d%H%M.%S 2>/dev/null || date -d "90000 seconds ago" +%Y%m%d%H%M.%S 2>/dev/null || true)
for i in 1 2 3 4 5 6; do
  printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.10\n' > "$STALE_HINT_TMP/session-stale0${i}"
  [[ -n "$_stale_ts" ]] && touch -t "$_stale_ts" "$STALE_HINT_TMP/session-stale0${i}"
done
stale_hint_out=$(CLAUDII_CACHE_DIR="$STALE_HINT_TMP" XDG_CONFIG_HOME="$STALE_XDG" bash "$CLAUDII_HOME/bin/claudii" 2>&1 || true)
# Hint appears when > 5 stale sessions: should contain "stale" and "si"
assert_contains "default view: stale GC hint with 6 stale sessions" "stale" "$stale_hint_out"
assert_contains "default view: stale GC hint mentions si command" "si" "$stale_hint_out"

# Only 3 stale files → hint should NOT appear (threshold is > 5)
STALE_FEW_TMP="$(mktemp -d)"
STALE_FEW_XDG="$STALE_FEW_TMP/xdg"
mkdir -p "$STALE_FEW_XDG/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$STALE_FEW_XDG/claudii/config.json"
for i in 1 2 3; do
  printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.10\n' > "$STALE_FEW_TMP/session-stale0${i}"
  [[ -n "$_stale_ts" ]] && touch -t "$_stale_ts" "$STALE_FEW_TMP/session-stale0${i}"
done
stale_few_out=$(CLAUDII_CACHE_DIR="$STALE_FEW_TMP" XDG_CONFIG_HOME="$STALE_FEW_XDG" bash "$CLAUDII_HOME/bin/claudii" 2>&1 || true)
# With 3 stale files, the hint line ("> 5" trigger) must not appear
stale_hint_line=$(echo "$stale_few_out" | grep -c "stale sessions" || true)
assert_eq "default view: no stale GC hint with 3 stale sessions" "0" "$stale_hint_line"

rm -rf "$STALE_HINT_TMP" "$STALE_FEW_TMP"
unset CLAUDII_CACHE_DIR XDG_CONFIG_HOME STALE_HINT_TMP STALE_FEW_TMP STALE_XDG STALE_FEW_XDG _stale_ts stale_hint_out stale_few_out stale_hint_line

# ── Gap 8 — claudii si ANSI guard ─────────────────────────────────────────
SI_ANSI_TMP="$(mktemp -d)"
SI_ANSI_XDG="$SI_ANSI_TMP/xdg"
mkdir -p "$SI_ANSI_XDG/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$SI_ANSI_XDG/claudii/config.json"
# Create 2 inactive sessions (dead PPID, fresh mtime — _PSC_is_active=0 because ppid dead)
printf 'model=Sonnet\nppid=99999999\nctx_pct=50\ncost=0.50\nrate_5h=\nrate_7d=\nsession_id=siansi1\nworktree=\nagent=\n' > "$SI_ANSI_TMP/session-siansi1"
printf 'model=Opus\nppid=99999999\nctx_pct=30\ncost=1.20\nrate_5h=\nrate_7d=\nsession_id=siansi2\nworktree=\nagent=\n' > "$SI_ANSI_TMP/session-siansi2"
si_ansi_out=$(CLAUDII_CACHE_DIR="$SI_ANSI_TMP" XDG_CONFIG_HOME="$SI_ANSI_XDG" bash "$CLAUDII_HOME/bin/claudii" si 2>&1 || true)
assert_no_literal_ansi "si: no literal \\033 in output" "$si_ansi_out"
rm -rf "$SI_ANSI_TMP"
unset SI_ANSI_TMP SI_ANSI_XDG si_ansi_out

# _session_name — returns real name, not source code patterns
_SN_TMP="$(mktemp -d)"
_SN_PROJ="$_SN_TMP/.claude/projects/test-project"
mkdir -p "$_SN_PROJ"

# Real rename entry (the name we expect back)
printf '%s\n' \
  '{"type":"message","role":"assistant","content":[{"type":"text","text":"Session renamed to: my-session"}]}' \
  > "$_SN_PROJ/sntest01.jsonl"

# Append a tool-result line that contains the old grep pattern (simulates source code in transcript)
printf '%s\n' \
  '{"type":"tool_result","content":"grep -o '\''Session renamed to: [^<]*'\'' \"$jsonl\""}' \
  >> "$_SN_PROJ/sntest01.jsonl"

# Helper: source only the _session_name function from bin/claudii and call it
_sn_result=$(bash -c '
  CLAUDII_HOME="$1" HOME="$2"
  source "$CLAUDII_HOME/lib/visual.sh"
  '"$(sed -n '/^# Extract session name/,/^}/p' "$CLAUDII_HOME/bin/claudii")"'
  _session_name sntest01
' _ "$CLAUDII_HOME" "$_SN_TMP" 2>/dev/null)

assert_eq "_session_name: returns real name" "my-session" "$_sn_result"
assert_eq "_session_name: does not leak grep pattern" "0" \
  "$(echo "$_sn_result" | grep -cF '[^<]*' || true)"

# Empty JSONL — must return empty, no crash
printf '' > "$_SN_PROJ/sntest02.jsonl"
_sn_empty=$(bash -c '
  CLAUDII_HOME="$1" HOME="$2"
  source "$CLAUDII_HOME/lib/visual.sh"
  '"$(sed -n '/^# Extract session name/,/^}/p' "$CLAUDII_HOME/bin/claudii")"'
  _session_name sntest02
' _ "$CLAUDII_HOME" "$_SN_TMP" 2>/dev/null)
assert_eq "_session_name: empty JSONL → empty output" "" "$_sn_empty"

rm -rf "$_SN_TMP"
unset _SN_TMP _SN_PROJ _sn_result _sn_empty

# ── claudii sessions regression: grep-no-match must not crash ────────────────
# Scenario: session has a JSONL with "cwd" but no "Session renamed to:" line.
# Before the fix, _session_name's grep pipeline returned exit 1 → pipefail →
# arr[$i]=$(...) aborted the script silently with no output.
_SE_TMP="$(mktemp -d)"
_SE_XDG="$_SE_TMP/xdg"
_SE_CACHE="$_SE_TMP/cache"
_SE_PROJ="$_SE_TMP/.claude/projects/test-project"
mkdir -p "$_SE_XDG/claudii" "$_SE_CACHE" "$_SE_PROJ"
cp "$CLAUDII_HOME/config/defaults.json" "$_SE_XDG/claudii/config.json"
# Active session (ppid=$$), session_id matches a JSONL below
printf 'model=Sonnet\nppid=%s\nctx_pct=42\ncost=1.23\nrate_5h=30\nreset_5h=0\nrate_7d=10\nsession_id=se-regression-test\nworktree=\nagent=\n' \
  "$$" > "$_SE_CACHE/session-se-regression-test"
# JSONL with "cwd" field but NO "Session renamed to:" — triggers the grep-no-match path
printf '%s\n' '{"type":"system","cwd":"/tmp/se-test-project"}' \
  > "$_SE_PROJ/se-regression-test.jsonl"

_se_out=$(HOME="$_SE_TMP" CLAUDII_CACHE_DIR="$_SE_CACHE" XDG_CONFIG_HOME="$_SE_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" sessions 2>&1)
_se_exit=$?

assert_eq "claudii se: exits 0 — grep-no-match regression" "0" "$_se_exit"
assert_contains "claudii se: shows model name" "Sonnet" "$_se_out"
assert_contains "claudii se: shows cost" "1.23" "$_se_out"
assert_contains "claudii se: shows project path" "se-test-project" "$_se_out"

rm -rf "$_SE_TMP"
unset _SE_TMP _SE_XDG _SE_CACHE _SE_PROJ _se_out _se_exit
