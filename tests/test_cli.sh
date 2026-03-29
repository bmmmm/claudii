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

# dashboard: must support on/off/auto (same as dash)
DASH_CLI_TMP="$(mktemp -d)"
export CLAUDII_CACHE_DIR="$DASH_CLI_TMP"
cp "$CLAUDII_HOME/config/defaults.json" "$DASH_CLI_TMP/config.json"
export XDG_CONFIG_HOME="$DASH_CLI_TMP"
mkdir -p "$DASH_CLI_TMP/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$DASH_CLI_TMP/claudii/config.json"

out=$(bash "$CLAUDII_HOME/bin/claudii" dashboard off 2>&1)
assert_matches "dashboard off: success message" "disabled|off" "$out"
assert_eq "dashboard off: no error exit" "0" "$(bash "$CLAUDII_HOME/bin/claudii" dashboard off >/dev/null 2>&1; echo $?)"

out=$(bash "$CLAUDII_HOME/bin/claudii" dashboard on 2>&1)
assert_matches "dashboard on: success message" "enabled|on" "$out"

out=$(bash "$CLAUDII_HOME/bin/claudii" dashboard auto 2>&1 || true)
assert_eq "dashboard auto: not 'Usage' error" "0" "$(echo "$out" | grep -c 'Usage:' || true)"
assert_contains "dashboard auto: shows auto" "auto" "$out"

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
