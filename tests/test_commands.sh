# touches: lib/cmd/config.sh lib/cmd/system.sh bin/claudii
# test_commands.sh — coverage for config, agents, claudestatus, cc-statusline, layers

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

# ── cc-statusline on/off ──────────────────────────────────────────────────────
# cc-statusline requires HOME/.claude/settings.json to exist.
# We point HOME to a temp dir and create a minimal settings.json there.

_make_cfg_tmp _CSSL
_cssl_xdg="$_CSSL_XDG"
_cssl_base="$_CSSL_BASE"

# Create a fake ~/.claude/settings.json in the temp HOME
mkdir -p "$_cssl_base/home/.claude"
printf '{}' > "$_cssl_base/home/.claude/settings.json"

# cc-statusline on → exit 0
_cssl_exit=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on >/dev/null 2>&1; echo $?)
assert_eq "cc-statusline on: exit 0" "0" "$_cssl_exit"

# cc-statusline on → output mentioning claudii-sessionline or settings
_cssl_out=$(HOME="$_cssl_base/home" XDG_CONFIG_HOME="$_cssl_xdg" \
  bash "$CLAUDII_HOME/bin/claudii" cc-statusline on 2>&1)
assert_matches "cc-statusline on: mentions claudii-sessionline or CC-Statusline" \
  "claudii-sessionline|CC-Statusline|aktiviert|enabled|aktiv" "$_cssl_out"
assert_no_literal_ansi "cc-statusline on: no literal \\033 in output" "$_cssl_out"

# cc-statusline on → settings.json now has statusLine.command = claudii-sessionline
_cssl_cmd=$(jq -r '.statusLine.command // empty' "$_cssl_base/home/.claude/settings.json" 2>/dev/null)
assert_eq "cc-statusline on: settings.json has claudii-sessionline" "claudii-sessionline" "$_cssl_cmd"

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

# ── agents ────────────────────────────────────────────────────────────────────

_make_cfg_tmp _AG
_ag_xdg="$_AG_XDG"
_ag_base="$_AG_BASE"

# agents: default config has at least sn and op aliases
_ag_out=$(XDG_CONFIG_HOME="$_ag_xdg" bash "$CLAUDII_HOME/bin/claudii" agents 2>&1)
assert_contains "agents: default config shows 'sn' alias" "sn" "$_ag_out"
assert_contains "agents: default config shows 'op' alias" "op" "$_ag_out"

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
assert_matches "agents: output has effort info" "high|medium|max" "$_ag_out"

rm -rf "$_ag_base"
unset _AG_BASE _AG_XDG _ag_xdg _ag_base _ag_out _ag_json _ag_json_ok _ag_exit

# ── layers ────────────────────────────────────────────────────────────────────

_make_cfg_tmp _LY
_ly_xdg="$_LY_XDG"
_ly_base="$_LY_BASE"

_ly_out=$(XDG_CONFIG_HOME="$_ly_xdg" CLAUDII_CACHE_DIR="$_LY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" layers 2>&1)

# No literal ANSI escapes
assert_no_literal_ansi "layers: no literal \\033 in output" "$_ly_out"

# Mentions ClaudeStatus and Dashboard (the three layers)
assert_contains "layers: shows ClaudeStatus" "ClaudeStatus" "$_ly_out"
assert_contains "layers: shows Dashboard" "Dashboard" "$_ly_out"
assert_contains "layers: shows CC-Statusline" "CC-Statusline" "$_ly_out"

# Does NOT mention the old 'show model' command (regression)
_ly_show_model=$(printf '%s' "$_ly_out" | grep -c 'show model' || true)
assert_eq "layers: no obsolete 'show model' reference" "0" "$_ly_show_model"

# Exit 0
_ly_exit=$(XDG_CONFIG_HOME="$_ly_xdg" CLAUDII_CACHE_DIR="$_LY_CACHE" \
  bash "$CLAUDII_HOME/bin/claudii" layers >/dev/null 2>&1; echo $?)
assert_eq "layers: exit 0" "0" "$_ly_exit"

# layers: mentions commands to toggle layers
assert_matches "layers: toggle commands shown" "on/off|cc-statusline|claudestatus" "$_ly_out"

# layers: Data Flow section present
assert_contains "layers: Data Flow section" "Data Flow" "$_ly_out"

rm -rf "$_ly_base"
unset _LY_BASE _LY_XDG _LY_CACHE _ly_xdg _ly_base _ly_out _ly_show_model _ly_exit
