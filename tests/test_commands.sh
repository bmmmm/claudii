# touches: lib/cmd/config.sh lib/cmd/system.sh lib/cmd/display.sh bin/claudii
# test_commands.sh — coverage for config, agents, claudestatus, cc-statusline, explain

# ── helpers ───────────────────────────────────────────────────────────────────
# Create a fresh isolated temp env: XDG_CONFIG_HOME + CLAUDII_CACHE_DIR
# Usage: _make_cfg_tmp <varname>
# Sets <varname>_XDG and <varname>_CACHE, creates dirs, copies defaults.json
_make_cfg_tmp() {
  local _base
  _base=$(mktemp -d)
  eval "${1}_BASE=$_base"
  eval "${1}_XDG=$_base/xdg"
  eval "${1}_CACHE=$_base/cache"
  mkdir -p "$_base/xdg/claudii" "$_base/cache"
  cp "$CLAUDII_HOME/config/defaults.json" "$_base/xdg/claudii/config.json"
}

# ── config get ────────────────────────────────────────────────────────────────

_make_cfg_tmp _CG
_cg_xdg="$_CG_XDG"
_cg_cache="$_CG_CACHE"
_cg_base="$_CG_BASE"

# statusline.enabled → true
_cgv=$(XDG_CONFIG_HOME="$_cg_xdg" bash "$CLAUDII_HOME/bin/claudii" config get statusline.enabled 2>&1)
assert_eq "config get: statusline.enabled = true" "true" "$_cgv"

# session-dashboard.enabled → off (hyphenated key regression)
_cgv=$(XDG_CONFIG_HOME="$_cg_xdg" bash "$CLAUDII_HOME/bin/claudii" config get session-dashboard.enabled 2>&1)
assert_eq "config get: session-dashboard.enabled = off" "off" "$_cgv"

# cost.week_start → monday
_cgv=$(XDG_CONFIG_HOME="$_cg_xdg" bash "$CLAUDII_HOME/bin/claudii" config get cost.week_start 2>&1)
assert_eq "config get: cost.week_start = monday" "monday" "$_cgv"

# nonexistent key → empty output, no crash (exit 0)
_cg_nonexist_exit=$(XDG_CONFIG_HOME="$_cg_xdg" bash "$CLAUDII_HOME/bin/claudii" config get totally.nonexistent.key >/dev/null 2>&1; echo $?)
assert_eq "config get: nonexistent key exits 0" "0" "$_cg_nonexist_exit"
_cgv_nonexist=$(XDG_CONFIG_HOME="$_cg_xdg" bash "$CLAUDII_HOME/bin/claudii" config get totally.nonexistent.key 2>&1)
assert_eq "config get: nonexistent key → empty output" "" "$_cgv_nonexist"

rm -rf "$_cg_base"
unset _CG_BASE _CG_XDG _CG_CACHE _cg_xdg _cg_cache _cg_base _cgv _cg_nonexist_exit _cgv_nonexist

# ── config set ────────────────────────────────────────────────────────────────

_make_cfg_tmp _CS
_cs_xdg="$_CS_XDG"
_cs_base="$_CS_BASE"

# set cost.week_start → sunday, then read back
XDG_CONFIG_HOME="$_cs_xdg" bash "$CLAUDII_HOME/bin/claudii" config set cost.week_start sunday >/dev/null 2>&1
_csv=$(XDG_CONFIG_HOME="$_cs_xdg" bash "$CLAUDII_HOME/bin/claudii" config get cost.week_start 2>&1)
assert_eq "config set: cost.week_start sunday reads back" "sunday" "$_csv"

# set debug.level → verbose, then read back
XDG_CONFIG_HOME="$_cs_xdg" bash "$CLAUDII_HOME/bin/claudii" config set debug.level verbose >/dev/null 2>&1
_csv=$(XDG_CONFIG_HOME="$_cs_xdg" bash "$CLAUDII_HOME/bin/claudii" config get debug.level 2>&1)
assert_eq "config set: debug.level verbose reads back" "verbose" "$_csv"

# set outputs "Set <key> = <value>" confirmation
_cs_out=$(XDG_CONFIG_HOME="$_cs_xdg" bash "$CLAUDII_HOME/bin/claudii" config set cost.week_start monday 2>&1)
assert_contains "config set: prints confirmation" "monday" "$_cs_out"

# config.json must be valid JSON after writes (atomic write via mktemp+mv)
_cs_json_ok=$(jq '.' "$_cs_xdg/claudii/config.json" >/dev/null 2>&1; echo $?)
assert_eq "config set: config.json stays valid JSON" "0" "$_cs_json_ok"

# verify the file is not truncated (at least 100 bytes)
_cs_size=$(wc -c < "$_cs_xdg/claudii/config.json" | tr -d ' ')
assert_eq "config set: config.json not truncated (>100 bytes)" "1" \
  "$([ "$_cs_size" -gt 100 ] && echo 1 || echo 0)"

rm -rf "$_cs_base"
unset _CS_BASE _CS_XDG _cs_xdg _cs_base _csv _cs_out _cs_json_ok _cs_size

# ── claudestatus on/off ───────────────────────────────────────────────────────

_make_cfg_tmp _CDS
_cds_xdg="$_CDS_XDG"
_cds_base="$_CDS_BASE"

# claudestatus on → exit 0
_cds_exit=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus on >/dev/null 2>&1; echo $?)
assert_eq "claudestatus on: exit 0" "0" "$_cds_exit"

# claudestatus on → produces output with success message
_cds_out=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus on 2>&1)
assert_matches "claudestatus on: success message" "aktiviert|enabled|on" "$_cds_out"
assert_no_literal_ansi "claudestatus on: no literal \\033 in output" "$_cds_out"

# claudestatus on → config.statusline.enabled = true
_cds_val=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" config get statusline.enabled 2>&1)
assert_eq "claudestatus on: sets statusline.enabled=true" "true" "$_cds_val"

# claudestatus off → exit 0
_cds_exit=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus off >/dev/null 2>&1; echo $?)
assert_eq "claudestatus off: exit 0" "0" "$_cds_exit"

# claudestatus off → produces output with disable message
_cds_out=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus off 2>&1)
assert_matches "claudestatus off: success message" "deaktiviert|disabled|off" "$_cds_out"
assert_no_literal_ansi "claudestatus off: no literal \\033 in output" "$_cds_out"

# claudestatus off → config.statusline.enabled = false
_cds_val=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" config get statusline.enabled 2>&1)
assert_eq "claudestatus off: sets statusline.enabled=false" "false" "$_cds_val"

# claudestatus off → the status DISPLAY reports off too. Regression: _cfgget
# read via `// empty`, which treats boolean false as falsy — the explicit
# user false fell through to the defaults' true and the display said "on"
# while config.json said false.
_cds_disp=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus 2>&1)
assert_contains "claudestatus off: display reports off (false survives _cfgget)" "off" "$_cds_disp"
unset _cds_disp

# claudestatus (no arg) → shows current state, no crash
_cds_noarg_exit=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus >/dev/null 2>&1; echo $?)
assert_eq "claudestatus (no arg): exit 0" "0" "$_cds_noarg_exit"
_cds_noarg_out=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus 2>&1)
assert_matches "claudestatus (no arg): mentions ClaudeStatus" "ClaudeStatus|claudestatus" "$_cds_noarg_out"
assert_no_literal_ansi "claudestatus (no arg): no literal \\033 in output" "$_cds_noarg_out"

# claudestatus bad-arg → exit 1 + error to stderr
_cds_bad_exit=$(XDG_CONFIG_HOME="$_cds_xdg" bash "$CLAUDII_HOME/bin/claudii" claudestatus badarg >/dev/null 2>&1; echo $?)
assert_eq "claudestatus bad-arg: exit 1" "1" "$_cds_bad_exit"

rm -rf "$_cds_base"
unset _CDS_BASE _CDS_XDG _cds_xdg _cds_base _cds_exit _cds_out _cds_val _cds_noarg_exit _cds_noarg_out _cds_bad_exit

# ── claudii on/off: presence file ─────────────────────────────────────────────
# off touches presence.file (CLAUDE_CLIENT_PRESENCE_FILE → suppresses CC mobile
# notifications); on removes it. Empty default = disabled (no file ops).
# HOME is isolated because on/off also touch $HOME/.claude/settings.json.
_make_cfg_tmp _PF
mkdir -p "$_PF_BASE/fakehome/.claude"
printf '{}' > "$_PF_BASE/fakehome/.claude/settings.json"
_pf_file="$_PF_BASE/presence-flag"
jq --arg f "$_pf_file" '.presence.file = $f' "$_PF_XDG/claudii/config.json" > "$_PF_XDG/claudii/config.json.tmp" \
  && mv "$_PF_XDG/claudii/config.json.tmp" "$_PF_XDG/claudii/config.json"

# claudii off → presence file is created
HOME="$_PF_BASE/fakehome" XDG_CONFIG_HOME="$_PF_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" off >/dev/null 2>&1 || true
assert_eq "claudii off: presence file created" "1" \
  "$([[ -f "$_pf_file" ]] && echo 1 || echo 0)"

# claudii on → presence file is removed
HOME="$_PF_BASE/fakehome" XDG_CONFIG_HOME="$_PF_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" on >/dev/null 2>&1 || true
assert_eq "claudii on: presence file removed" "0" \
  "$([[ -f "$_pf_file" ]] && echo 1 || echo 0)"

# empty presence.file (default) → no file ops, no crash
_make_cfg_tmp _PFE
mkdir -p "$_PFE_BASE/fakehome/.claude"
printf '{}' > "$_PFE_BASE/fakehome/.claude/settings.json"
_pfe_exit=$(HOME="$_PFE_BASE/fakehome" XDG_CONFIG_HOME="$_PFE_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" off >/dev/null 2>&1; echo $?)
assert_eq "claudii off (empty presence.file): exit 0" "0" "$_pfe_exit"

rm -rf "$_PF_BASE" "$_PFE_BASE"
unset _PF_BASE _PF_XDG _PF_CACHE _pf_file _PFE_BASE _PFE_XDG _PFE_CACHE _pfe_exit

# ── cc-statusline on/off ──────────────────────────────────────────────────────
# cc-statusline requires HOME/.claude/settings.json to exist.
# We point HOME to a temp dir and create a minimal settings.json there.

_make_cfg_tmp _CSSL
_cssl_xdg="$_CSSL_XDG"
_cssl_base="$_CSSL_BASE"

# Create a fake ~/.claude/settings.json in the temp HOME
mkdir -p "$_cssl_base/home/.claude"
printf '{}' > "$_cssl_base/home/.claude/settings.json"

# Force insomnii=off so this block exercises the plain (non-wrapper) branch
# regardless of whether cc-insomnii is installed on the host. Wrapper-mode
# coverage is in test_cc_statusline_preset.sh (which fakes cc-insomnii on PATH).
jq '.statusline.insomnii = "off"' "$_cssl_xdg/claudii/config.json" > "$_cssl_xdg/claudii/config.json.tmp" \
  && mv "$_cssl_xdg/claudii/config.json.tmp" "$_cssl_xdg/claudii/config.json"

# cc-statusline on → exit 0
_cssl_exit=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on >/dev/null 2>&1; echo $?)
assert_eq "cc-statusline on: exit 0" "0" "$_cssl_exit"

# cc-statusline on → output mentioning claudii-cc-statusline or settings
_cssl_out=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on 2>&1)
assert_matches "cc-statusline on: mentions claudii-cc-statusline or CC-Statusline" \
  "claudii-cc-statusline|CC-Statusline|aktiviert|enabled|aktiv" "$_cssl_out"
assert_no_literal_ansi "cc-statusline on: no literal \\033 in output" "$_cssl_out"

# cc-statusline on → settings.json now has statusLine.command = claudii-cc-statusline
_cssl_cmd=$(jq -r '.statusLine.command // empty' "$_cssl_base/home/.claude/settings.json" 2>/dev/null)
assert_eq "cc-statusline on: settings.json has claudii-cc-statusline" "claudii-cc-statusline" "$_cssl_cmd"

# cc-statusline on (idempotent — already configured) → exit 0
_cssl_idem_exit=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on >/dev/null 2>&1; echo $?)
assert_eq "cc-statusline on (idempotent): exit 0" "0" "$_cssl_idem_exit"

# cc-statusline off → exit 0
_cssl_off_exit=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline off >/dev/null 2>&1; echo $?)
assert_eq "cc-statusline off: exit 0" "0" "$_cssl_off_exit"

# cc-statusline off → output mentions deactivation or not configured
_cssl_off_out=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline off 2>&1)
assert_matches "cc-statusline off: success message" \
  "deaktiviert|disabled|off|CC-Statusline" "$_cssl_off_out"
assert_no_literal_ansi "cc-statusline off: no literal \\033 in output" "$_cssl_off_out"

# cc-statusline off → statusLine removed from settings.json
_cssl_has_sl=$(jq 'has("statusLine")' "$_cssl_base/home/.claude/settings.json" 2>/dev/null)
assert_eq "cc-statusline off: statusLine removed from settings.json" "false" "$_cssl_has_sl"

# cc-statusline off (already off / not configured) → no crash, exit 0
_cssl_off2_exit=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline off >/dev/null 2>&1; echo $?)
assert_eq "cc-statusline off (already off): exit 0" "0" "$_cssl_off2_exit"

# cc-statusline (no settings.json) → reports error, exit 1
rm -f "$_cssl_base/home/.claude/settings.json"
_cssl_missing_exit=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on >/dev/null 2>&1; echo $?)
assert_eq "cc-statusline on (no settings.json): exit 1" "1" "$_cssl_missing_exit"
_cssl_missing_msg=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on 2>&1 || true)
assert_matches "cc-statusline on (no settings.json): actionable error" \
  "Fehler|not found|settings\.json|claudii update" "$_cssl_missing_msg"

rm -rf "$_cssl_base"
unset _CSSL_BASE _CSSL_XDG _cssl_xdg _cssl_base _cssl_exit _cssl_out _cssl_cmd
unset _cssl_idem_exit _cssl_off_exit _cssl_off_out _cssl_has_sl _cssl_off2_exit
unset _cssl_missing_exit _cssl_missing_msg

# ── claudii on must not clobber the cc-insomnii wrapper ───────────────────────
# Regression: _cmd_on compared statusLine.command with == "claudii-cc-statusline";
# the wrapper command installed by `cc-statusline on` (with cc-insomnii present)
# failed that check and got overwritten with the plain command on every
# `claudii on`.
_make_cfg_tmp _CWR
mkdir -p "$_CWR_BASE/fakehome/.claude"
printf '{"statusLine":{"type":"command","command":"cc-insomnii --after=claudii-cc-statusline"}}' \
  > "$_CWR_BASE/fakehome/.claude/settings.json"
HOME="$_CWR_BASE/fakehome" XDG_CONFIG_HOME="$_CWR_XDG" \
  bash "$CLAUDII_HOME/bin/claudii" on >/dev/null 2>&1
_cwr_cmd=$(jq -r '.statusLine.command' "$_CWR_BASE/fakehome/.claude/settings.json" 2>/dev/null)
assert_eq "claudii on: preserves cc-insomnii wrapper statusLine" \
  "cc-insomnii --after=claudii-cc-statusline" "$_cwr_cmd"
rm -rf "$_CWR_BASE"
unset _CWR_BASE _CWR_XDG _CWR_CACHE _cwr_cmd

# Agents fixture: defaults.json ships none ("agents": {}), so the agent tests
# write their own — the shape the old defaults had (skill-less + skill agents).
_AGENTS_FIXTURE='{"hk": {"model": "haiku", "effort": "high", "description": "Haiku worker"},
  "sn": {"model": "sonnet", "effort": "high", "description": "Sonnet worker"},
  "op": {"model": "opus", "effort": "high", "description": "Opus worker"},
  "orc": {"model": "opus", "effort": "xhigh", "skill": "orchestrate", "description": "Orchestrator"}}'
_with_agents() {   # $1 = config.json to rewrite, $2 = agents JSON object
  jq --argjson a "$2" '.agents = $a' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# ── zsh agent registration: skill-less agents + no field-shift noise ──────────
# Regression 1: agents without a skill (hk/sn/op/…) were skipped entirely —
# advertised by `claudii agents` but never registered (command not found).
# Regression 2: the registration TSV used tab separators; zsh `read` collapses
# runs of IFS-whitespace, so an empty skill field shifted model→skill and
# effort→model, printing "invalid agent effort:" on every shell start.
# Sources lib/config.zsh + lib/functions.zsh directly (no plugin, no PATH
# change), so it also runs where e.g. 1Password's `op` is installed: the
# fixture's `op` would then be a command — see the guard test below.
_zag_zsh() {   # $1 = XDG config dir; prints the registration report
  XDG_CONFIG_HOME="$1" zsh -fc '
    export CLAUDII_HOME="'"$CLAUDII_HOME"'"
    typeset -gA _CLAUDII_METRICS
    zmodload zsh/datetime 2>/dev/null; zmodload zsh/mathfunc 2>/dev/null
    source "$CLAUDII_HOME/lib/visual.sh" 2>/dev/null
    source "$CLAUDII_HOME/lib/log.sh"
    source "$CLAUDII_HOME/lib/config.zsh" 2>/dev/null
    source "$CLAUDII_HOME/lib/functions.zsh"
    for a in hk sn op orc; do
      (( ${+functions[$a]} )) && print "registered: $a" || print "MISSING: $a"
    done
    print "body-hk: ${functions[hk]}"
    print "body-orc: ${functions[orc]}"
  ' 2>&1
}
if command -v zsh >/dev/null 2>&1; then
  _make_cfg_tmp _ZAG
  _with_agents "$_ZAG_XDG/claudii/config.json" "$_AGENTS_FIXTURE"
  _zag_out=$(_zag_zsh "$_ZAG_XDG")
  assert_contains "zsh agents: skill-less hk registered"   "registered: hk"  "$_zag_out"
  assert_contains "zsh agents: skill-less sn registered"   "registered: sn"  "$_zag_out"
  assert_contains "zsh agents: skill agent orc registered" "registered: orc" "$_zag_out"
  assert_contains "zsh agents: hk body is a plain launcher" \
    '_claudii_agent_launch "" "haiku" "high"' "$_zag_out"
  assert_not_contains "zsh agents: no field-shift error noise" "invalid agent" "$_zag_out"

  # ── defaults ship no agents → nothing registered ──
  _make_cfg_tmp _ZAD
  _zag_out=$(_zag_zsh "$_ZAD_XDG")
  assert_contains "zsh agents: defaults register no hk" "MISSING: hk" "$_zag_out"
  assert_contains "zsh agents: defaults register no op" "MISSING: op" "$_zag_out"

  # ── guard: never shadow what the shell already resolves ──
  # The old defaults shipped `sh` (shadowed /bin/sh) and `op` (the 1Password
  # CLI). An agent whose name is a command, builtin, alias, reserved word or a
  # foreign function is skipped — silently at the default debug.level=off.
  _make_cfg_tmp _ZGD
  _zgd_cfg="$_ZGD_XDG/claudii/config.json"
  _with_agents "$_zgd_cfg" '{"sh": {"model": "haiku"}, "echo": {"model": "haiku"},
    "if": {"model": "haiku"}, "myalias": {"model": "haiku"}, "myfn": {"model": "haiku"},
    "hk": {"model": "haiku"}}'
  _zgd_out=$(XDG_CONFIG_HOME="$_ZGD_XDG" zsh -fc '
    export CLAUDII_HOME="'"$CLAUDII_HOME"'"
    typeset -gA _CLAUDII_METRICS
    zmodload zsh/datetime 2>/dev/null; zmodload zsh/mathfunc 2>/dev/null
    source "$CLAUDII_HOME/lib/visual.sh" 2>/dev/null
    source "$CLAUDII_HOME/lib/log.sh"
    source "$CLAUDII_HOME/lib/config.zsh" 2>/dev/null
    alias myalias="print alias-kept"
    function myfn { print fn-kept }
    source "$CLAUDII_HOME/lib/functions.zsh"
    for a in sh echo if myalias myfn; do
      (( ${+functions[$a]} )) && [[ "${functions[$a]}" == *_claudii_agent_launch* ]] \
        && print "SHADOWED: $a" || print "kept: $a"
    done
    (( ${+functions[hk]} )) && print "registered: hk"
    myfn; eval myalias   # eval: an alias only expands in code parsed after it
    # Re-sourcing the plugin replaces our own earlier registration
    source "$CLAUDII_HOME/lib/functions.zsh"
    (( ${+functions[hk]} )) && print "re-registered: hk"
  ' 2>&1)
  for _a in sh echo if myalias myfn; do
    assert_contains "agent guard: $_a not shadowed" "kept: $_a" "$_zgd_out"
  done
  assert_contains "agent guard: a free name still registers" "registered: hk" "$_zgd_out"
  assert_contains "agent guard: foreign function body untouched" "fn-kept" "$_zgd_out"
  assert_contains "agent guard: alias untouched" "alias-kept" "$_zgd_out"
  assert_contains "agent guard: own registration replaceable on re-source" "re-registered: hk" "$_zgd_out"
  assert_not_contains "agent guard: silent at debug.level=off" "not registered" "$_zgd_out"

  # debug.level=warn surfaces the skip, naming what the name already is
  jq '.debug.level = "warn"' "$_zgd_cfg" > "$_zgd_cfg.tmp" && mv "$_zgd_cfg.tmp" "$_zgd_cfg"
  _zgd_out=$(_zag_zsh "$_ZGD_XDG")
  assert_contains "agent guard: warn names the command" "agent alias not registered: sh is already a command" "$_zgd_out"
  assert_contains "agent guard: warn names the builtin" "echo is already a builtin" "$_zgd_out"
  assert_contains "agent guard: warn names the reserved word" "if is already a reserved word" "$_zgd_out"

  rm -rf "$_ZAG_BASE" "$_ZAD_BASE" "$_ZGD_BASE"
  unset _ZAG_BASE _ZAG_XDG _ZAG_CACHE _ZAD_BASE _ZAD_XDG _ZAD_CACHE \
    _ZGD_BASE _ZGD_XDG _ZGD_CACHE _zgd_cfg _zgd_out _zag_out _a
fi
unset -f _zag_zsh

# ── agents ────────────────────────────────────────────────────────────────────

# agents: the shipped defaults have none → onboarding, and --json is []
_make_cfg_tmp _AO
_ao_out=$(XDG_CONFIG_HOME="$_AO_XDG" bash "$CLAUDII_HOME/bin/claudii" agents 2>&1)
assert_contains "agents: defaults show onboarding" "No agents configured" "$_ao_out"
assert_eq "agents --json: defaults give []" "[]" \
  "$(XDG_CONFIG_HOME="$_AO_XDG" bash "$CLAUDII_HOME/bin/claudii" agents --json 2>&1)"

# The onboarding's setup lines must work as printed: three config sets give a
# listed agent (`claudii config set agents.clorch.skill orchestrate` …).
_ao_rc=0
while IFS= read -r _ao_line; do
  # shellcheck disable=SC2086  # the printed line is split on purpose
  set -- ${_ao_line#  claudii }
  XDG_CONFIG_HOME="$_AO_XDG" bash "$CLAUDII_HOME/bin/claudii" "$@" >/dev/null 2>&1 || _ao_rc=1
done < <(grep '^  claudii config set agents\.' <<< "$_ao_out")
set --
assert_eq "agents: onboarding setup lines run cleanly" "0" "$_ao_rc"
assert_eq "agents: onboarding setup yields the agent" "clorch orchestrate opus high" \
  "$(XDG_CONFIG_HOME="$_AO_XDG" bash "$CLAUDII_HOME/bin/claudii" agents --json 2>/dev/null \
     | jq -r '.[] | select(.alias == "clorch") | "\(.alias) \(.skill) \(.model) \(.effort)"')"
rm -rf "$_AO_BASE"
unset _AO_BASE _AO_XDG _AO_CACHE _ao_out _ao_rc _ao_line

_make_cfg_tmp _AG
_ag_xdg="$_AG_XDG"
_ag_base="$_AG_BASE"
_with_agents "$_ag_xdg/claudii/config.json" "$_AGENTS_FIXTURE"

# agents: a configured config lists its aliases
_ag_out=$(XDG_CONFIG_HOME="$_ag_xdg" bash "$CLAUDII_HOME/bin/claudii" agents 2>&1)
assert_contains "agents: configured config shows 'sn' alias" "sn" "$_ag_out"
assert_contains "agents: configured config shows 'op' alias" "op" "$_ag_out"

# agents: output has no literal ANSI escapes
assert_no_literal_ansi "agents: no literal \\033 in output" "$_ag_out"

# agents --json: valid JSON array
_ag_json=$(XDG_CONFIG_HOME="$_ag_xdg" bash "$CLAUDII_HOME/bin/claudii" agents --json 2>&1)
_ag_json_ok=$(printf '%s' "$_ag_json" | jq . >/dev/null 2>&1; echo $?)
assert_eq "agents --json: valid JSON" "0" "$_ag_json_ok"
assert_contains "agents --json: is array with alias" '"alias"' "$_ag_json"

# agents: exit 0
_ag_exit=$(XDG_CONFIG_HOME="$_ag_xdg" bash "$CLAUDII_HOME/bin/claudii" agents >/dev/null 2>&1; echo $?)
assert_eq "agents: exit 0" "0" "$_ag_exit"

# agents: shows model and effort columns
assert_matches "agents: output has model info" "opus|sonnet|haiku" "$_ag_out"
assert_matches "agents: output has effort info" "xhigh|high|medium|low|max" "$_ag_out"

rm -rf "$_ag_base"
unset _AG_BASE _AG_XDG _ag_xdg _ag_base _ag_out _ag_json _ag_json_ok _ag_exit _AGENTS_FIXTURE
unset -f _with_agents

# ── explain ───────────────────────────────────────────────────────────────────

_make_cfg_tmp _LY
_ly_xdg="$_LY_XDG"
_ly_base="$_LY_BASE"

# HOME points at the empty temp base (no ~/.claude/settings.json) so the render
# is deterministic — without it, explain reads the developer's real settings.json
# and a malformed one crashes the command mid-render (regression guard).
_ly_out=$(HOME="$_ly_base" XDG_CONFIG_HOME="$_ly_xdg" CLAUDII_CACHE_DIR="$_LY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" explain 2>&1)

# No literal ANSI escapes
assert_no_literal_ansi "explain: no literal \\033 in output" "$_ly_out"

# Mentions ClaudeStatus and Dashboard (the three layers)
assert_contains "explain: shows ClaudeStatus" "ClaudeStatus" "$_ly_out"
assert_contains "explain: shows Dashboard" "Dashboard" "$_ly_out"
assert_contains "explain: shows CC-Statusline" "CC-Statusline" "$_ly_out"

# Does NOT mention the old 'show model' command (regression)
_ly_show_model=$(printf '%s' "$_ly_out" | grep -c 'show model' || true)
assert_eq "explain: no obsolete 'show model' reference" "0" "$_ly_show_model"

# Exit 0
_ly_exit=$(HOME="$_ly_base" XDG_CONFIG_HOME="$_ly_xdg" CLAUDII_CACHE_DIR="$_LY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" explain >/dev/null 2>&1; echo $?)
assert_eq "explain: exit 0" "0" "$_ly_exit"

# explain: mentions commands to toggle layers
assert_matches "explain: toggle commands shown" "on/off|cc-statusline|claudestatus" "$_ly_out"

# explain: Data Flow section present
assert_contains "explain: Data Flow section" "Data Flow" "$_ly_out"

rm -rf "$_ly_base"
unset _LY_BASE _LY_XDG _LY_CACHE _ly_xdg _ly_base _ly_out _ly_show_model _ly_exit

# ── auto colors: piped pretty output carries no ANSI ──────────────────────────
# bin/claudii blanks CLAUDII_CLR_* when stdout is not a TTY (captured output
# here is a pipe). CLAUDII_FORCE_COLOR=1 must opt back in.

_make_cfg_tmp _AC
# HOME isolated (empty base, no ~/.claude/settings.json) — see the explain note above.
_ac_out=$(HOME="$_AC_BASE" XDG_CONFIG_HOME="$_AC_XDG" CLAUDII_CACHE_DIR="$_AC_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" explain 2>&1)
grep -q $'\033\[' <<< "$_ac_out" && _ac_has=1 || _ac_has=0
assert_eq "auto colors: piped explain output has no ANSI escapes" "0" "$_ac_has"

_ac_out=$(HOME="$_AC_BASE" XDG_CONFIG_HOME="$_AC_XDG" CLAUDII_CACHE_DIR="$_AC_CACHE" CLAUDII_FORCE_COLOR=1 \
  bash "$CLAUDII_HOME/bin/claudii" explain 2>&1)
grep -q $'\033\[' <<< "$_ac_out" && _ac_has=1 || _ac_has=0
assert_eq "auto colors: CLAUDII_FORCE_COLOR=1 restores ANSI" "1" "$_ac_has"

rm -rf "$_AC_BASE"
unset _AC_BASE _AC_XDG _AC_CACHE _ac_out _ac_has

# -- theme reaches commands that never call _cfg_init --------------------------
# _claudii_theme_load only ever ran from inside _cfg_init, and nine commands
# (gc, pin, unpin, vibemap, vpnii — since removed —, cc-statusline, update,
# version, changelog) never reach _cfg_init -- so they painted in the hardcoded default palette no
# matter what theme.name said. bin/claudii now boots the theme centrally
# (_claudii_boot, before the dispatch case). `changelog` stands in for the nine:
# it emits the accent colour and calls no _cfg_init of its own.
#
# Red-verified: delete the `_claudii_boot "${1:-}"` line from bin/claudii and
# this flips to the default accent.

_make_cfg_tmp _TH
jq '.theme.name = "pastel"' "$CLAUDII_HOME/config/defaults.json" > "$_TH_XDG/claudii/config.json"

_th_out=$(HOME="$_TH_BASE" XDG_CONFIG_HOME="$_TH_XDG" CLAUDII_CACHE_DIR="$_TH_CACHE" \
  CLAUDII_FORCE_COLOR=1 bash "$CLAUDII_HOME/bin/claudii" changelog 2>&1)

# Pastel's accent is 38;5;219, the hardcoded default is 38;5;213. Matching the
# themed value alone would stay green if the theme silently stopped applying to
# something else, so both directions are asserted.
case "$_th_out" in *"[38;5;219m"*) _th_pastel=1 ;; *) _th_pastel=0 ;; esac
case "$_th_out" in *"[38;5;213m"*) _th_default=1 ;; *) _th_default=0 ;; esac
assert_eq "theme: changelog honours theme.name=pastel" "1" "$_th_pastel"
assert_eq "theme: changelog no longer paints the default accent" "0" "$_th_default"

rm -rf "$_TH_BASE"
unset _TH_BASE _TH_XDG _TH_CACHE _th_out _th_pastel _th_default

# -- theme preset schema = what the loader maps ---------------------------------
# defaults.json once shipped a theme.colors block, preset names and
# reset_warn/reset_crit colors that nothing read. The loader's case in
# lib/visual.sh maps exactly these five keys; anything else is dead config.
_th_keys=$(jq -r '[.theme_presets[] | (.colors // {}) | keys[]] | unique | join(",")' \
  "$CLAUDII_HOME/config/defaults.json")
assert_eq "theme presets: only loader-mapped color keys" \
  "accent,rate_crit,rate_ok,rate_warn,reset_ok" "$_th_keys"
assert_eq "theme presets: default stays listable" "true" \
  "$(jq '.theme_presets | has("default")' "$CLAUDII_HOME/config/defaults.json")"
assert_eq "theme: no unread theme.colors block" "null" \
  "$(jq -c '.theme.colors' "$CLAUDII_HOME/config/defaults.json")"
unset _th_keys

# -- a failing handler in a sourced file must not take the shell down ----------
# lib/cmd/*.sh are SOURCED into bin/claudii, so a bare `exit 1` in a _cmd_*
# handler killed the whole process -- skipping _spinner_stop and leaving a
# spinner running on the terminal. Those 33 sites are `return 1` now.
#
# The proof is the line AFTER the failing call: under the old `exit`, the
# subshell died and SURVIVED was never printed.

_er_out=$(bash -c '
  source "$CLAUDII_HOME/lib/visual.sh"
  source "$CLAUDII_HOME/lib/spinner.sh"
  source "$CLAUDII_HOME/lib/helpers.sh"
  source "$CLAUDII_HOME/lib/render.sh"
  source "$CLAUDII_HOME/lib/cmd/system.sh"
  _cmd_claudestatus claudestatus bogus >/dev/null 2>&1
  printf "SURVIVED rc=%s\\n" "$?"
' 2>&1)
assert_contains "sourced handler: a bad subcommand returns instead of killing the shell" \
  "SURVIVED rc=1" "$_er_out"

# ...and the failure still reaches the caller as a non-zero exit status: turning
# `exit 1` into `return 1` is only correct while the dispatcher propagates it.
_make_cfg_tmp _ER
HOME="$_ER_BASE" XDG_CONFIG_HOME="$_ER_XDG" CLAUDII_CACHE_DIR="$_ER_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" claudestatus bogus >/dev/null 2>&1
assert_eq "sourced handler: the dispatcher still exits non-zero on a bad subcommand" "1" "$?"

rm -rf "$_ER_BASE"
unset _ER_BASE _ER_XDG _ER_CACHE _er_out

# ── explain: separator rules are valid UTF-8 under LC_ALL=C ───────────────────
# `%.56s` truncated the multibyte ─ rule at byte 56 (mid-codepoint) under the C
# locale CI runs the suite in; _rep '─' 56 builds it char-aware. A raw grep for
# U+FFFD misses it (the broken stream carries partial E2 94 bytes, not FFFD),
# so iconv is the correct detector — it rejects the truncated codepoint.
if command -v iconv >/dev/null 2>&1; then
  _make_cfg_tmp _EX
  LC_ALL=C HOME="$_EX_BASE" XDG_CONFIG_HOME="$_EX_XDG" CLAUDII_CACHE_DIR="$_EX_CACHE" \
    bash "$CLAUDII_HOME/bin/claudii" explain 2>/dev/null \
    | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && _ex_valid=0 || _ex_valid=$?
  assert_eq "explain: rules are valid UTF-8 under LC_ALL=C (no mid-codepoint cut)" "0" "$_ex_valid"
  rm -rf "$_EX_BASE"
  unset _EX_BASE _EX_XDG _EX_CACHE _ex_valid
fi

# ── explain: malformed ~/.claude/settings.json must not crash the render ───────
# The CC-Statusline section reads $HOME/.claude/settings.json via jq. jq 1.7
# exits non-zero (5) on unparseable JSON; under bin/claudii's set -e a bare
# `sl_cmd=$(jq …)` aborted the whole command mid-render (exit 5, output cut off
# before the Data Flow section). Guarded with `|| sl_cmd=""` in display.sh so a
# bad settings file degrades to the "not configured" branch. Point HOME at a
# temp with a deliberately broken settings.json and assert explain still exits 0
# and renders to completion.
_make_cfg_tmp _EM
mkdir -p "$_EM_BASE/.claude"
printf '{ "statusLine": { not valid json\n' > "$_EM_BASE/.claude/settings.json"
_em_exit=$(HOME="$_EM_BASE" XDG_CONFIG_HOME="$_EM_XDG" CLAUDII_CACHE_DIR="$_EM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" explain >/dev/null 2>&1; echo $?)
assert_eq "explain: malformed settings.json does not crash (exit 0)" "0" "$_em_exit"
_em_out=$(HOME="$_EM_BASE" XDG_CONFIG_HOME="$_EM_XDG" CLAUDII_CACHE_DIR="$_EM_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" explain 2>&1)
assert_contains "explain: renders to completion despite bad settings.json" "Data Flow" "$_em_out"
rm -rf "$_EM_BASE"
unset _EM_BASE _EM_XDG _EM_CACHE _em_exit _em_out

# ── doctor: "plugin loaded" means the calling shell exported CLAUDII_HOME ─────
# bin/claudii exports CLAUDII_HOME for itself, so the old check — is it set? —
# reported ok even when no shell had ever sourced claudii.plugin.zsh. Now it
# asks whether the caller already had it (the plugin exports it).
_make_cfg_tmp _DP
_dp_status() {
  jq -r '.[] | select(.check == "plugin") | .status' <<< "$1" 2>/dev/null
}
_dp_out=$(env -u CLAUDII_HOME HOME="$_DP_BASE" XDG_CONFIG_HOME="$_DP_XDG" CLAUDII_CACHE_DIR="$_DP_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" doctor --json 2>/dev/null)
assert_eq "doctor: plugin warn when the caller has no CLAUDII_HOME" "warn" "$(_dp_status "$_dp_out")"
_dp_out=$(env HOME="$_DP_BASE" XDG_CONFIG_HOME="$_DP_XDG" CLAUDII_CACHE_DIR="$_DP_CACHE" \
  CLAUDII_HOME="$CLAUDII_HOME" bash "$CLAUDII_HOME/bin/claudii" doctor --json 2>/dev/null)
assert_eq "doctor: plugin ok when the caller exported CLAUDII_HOME" "ok" "$(_dp_status "$_dp_out")"
rm -rf "$_DP_BASE"
unset _DP_BASE _DP_XDG _DP_CACHE _dp_out
unset -f _dp_status

# ── status --json: claudii-status bookkeeping keys are not models ─────────────
# The status cache carries _incident / _incident_started / _api next to the
# model lines; --json used to emit them as models ({"model":"_incident",…}).
# A stub claudii-status (bin/claudii calls it before rendering) writes the
# cache, so no network is involved.
_make_cfg_tmp _SJ
mkdir -p "$_SJ_BASE/home/bin"
for _sj_d in lib config completions; do ln -s "$CLAUDII_HOME/$_sj_d" "$_SJ_BASE/home/$_sj_d"; done
ln -s "$CLAUDII_HOME/bin/claudii" "$_SJ_BASE/home/bin/claudii"
cat > "$_SJ_BASE/home/bin/claudii-status" <<'STUB'
#!/bin/bash
printf 'opus=ok\nsonnet=degraded\n_incident=investigating\n_incident_started=1700000000\n_api=ok\n' \
  > "$CLAUDII_CACHE_DIR/status-models"
STUB
chmod +x "$_SJ_BASE/home/bin/claudii-status"
_sj_out=$(CLAUDII_HOME="$_SJ_BASE/home" HOME="$_SJ_BASE" XDG_CONFIG_HOME="$_SJ_XDG" \
  CLAUDII_CACHE_DIR="$_SJ_CACHE" bash "$_SJ_BASE/home/bin/claudii" status --json 2>&1)
assert_eq "status --json: only model entries" \
  '[{"model":"opus","status":"ok"},{"model":"sonnet","status":"degraded"}]' \
  "$(jq -c . <<< "$_sj_out" 2>&1)"
rm -rf "$_SJ_BASE"
unset _SJ_BASE _SJ_XDG _SJ_CACHE _sj_out _sj_d
