# touches: lib/cmd/config.sh bin/claudii
# test_config.sh — config system E2E tests

# Setup: use project-local temp config dir
export XDG_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_config.XXXXXX")
mkdir -p "$XDG_CONFIG_HOME/claudii"

# config creates from defaults
output=$(bash "$CLAUDII_HOME/bin/claudii" config 2>&1)
assert_contains "config list shows user config path" "config.json" "$output"
assert_file_exists "config.json created from defaults" "$XDG_CONFIG_HOME/claudii/config.json"

# config get
output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.cl.model 2>&1)
assert_eq "config get aliases.cl.model" "sonnet" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.clo.effort 2>&1)
assert_eq "config get aliases.clo.effort" "high" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.clf.model 2>&1)
assert_eq "config get aliases.clf.model" "fable" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get fallback.enabled 2>&1)
assert_eq "config get fallback.enabled" "true" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get status.cache_ttl 2>&1)
assert_eq "config get status.cache_ttl" "300" "$output"

# config set string
bash "$CLAUDII_HOME/bin/claudii" config set aliases.cl.model opus >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.cl.model 2>&1)
assert_eq "config set string value" "opus" "$output"

# config set number
bash "$CLAUDII_HOME/bin/claudii" config set status.cache_ttl 600 >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get status.cache_ttl 2>&1)
assert_eq "config set number value" "600" "$output"

# config set boolean
bash "$CLAUDII_HOME/bin/claudii" config set fallback.enabled false >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get fallback.enabled 2>&1)
assert_eq "config set boolean value" "false" "$output"

# config set leading-zero string — must preserve padding, not coerce to numeric
bash "$CLAUDII_HOME/bin/claudii" config set aliases.cl.model sonnet >/dev/null 2>&1  # reset first
bash "$CLAUDII_HOME/bin/claudii" config set testkey.zero 007 >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get testkey.zero 2>&1)
assert_eq "config set leading-zero string (007 preserved)" "007" "$output"

bash "$CLAUDII_HOME/bin/claudii" config set testkey.zero 08 >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get testkey.zero 2>&1)
assert_eq "config set leading-zero string (08 preserved)" "08" "$output"

# config set canonical zero — must still be stored as numeric 0
bash "$CLAUDII_HOME/bin/claudii" config set testkey.zero 0 >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get testkey.zero 2>&1)
assert_eq "config set canonical zero stays numeric" "0" "$output"
raw_type=$(jq -r '.testkey.zero | type' "$XDG_CONFIG_HOME/claudii/config.json" 2>/dev/null)
assert_eq "config set canonical zero is JSON number type" "number" "$raw_type"

# config set decimal — must still be numeric
bash "$CLAUDII_HOME/bin/claudii" config set testkey.zero 1.5 >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get testkey.zero 2>&1)
assert_eq "config set decimal (1.5) stays numeric" "1.5" "$output"
raw_type=$(jq -r '.testkey.zero | type' "$XDG_CONFIG_HOME/claudii/config.json" 2>/dev/null)
assert_eq "config set decimal is JSON number type" "number" "$raw_type"

# config get statusline.models
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config get statusline.models default" "opus,sonnet,haiku,fable" "$output"

# config set statusline.models
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus" >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config set statusline.models" "opus" "$output"

# config reset
bash "$CLAUDII_HOME/bin/claudii" config reset >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.cl.model 2>&1)
assert_eq "config reset restores defaults" "sonnet" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get fallback.enabled 2>&1)
assert_eq "config reset restores fallback" "true" "$output"

# config export — stdout
output=$(bash "$CLAUDII_HOME/bin/claudii" config export 2>&1)
assert_contains "config export outputs JSON" "statusline" "$output"
echo "$output" | jq '.' >/dev/null 2>&1 && assert_eq "config export is valid JSON" "true" "true" \
  || assert_eq "config export is valid JSON" "valid" "invalid"

# config export — to file
export_file="$XDG_CONFIG_HOME/claudii/export.json"
bash "$CLAUDII_HOME/bin/claudii" config export "$export_file" >/dev/null 2>&1
assert_file_exists "config export creates file" "$export_file"
models_in_export=$(jq -r '.statusline.models' "$export_file")
assert_eq "config export file has correct content" "opus,sonnet,haiku,fable" "$models_in_export"

# config import
import_file="$XDG_CONFIG_HOME/claudii/import.json"
jq '.statusline.models = "opus"' "$CLAUDII_HOME/config/defaults.json" > "$import_file"
bash "$CLAUDII_HOME/bin/claudii" config import "$import_file" >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config import replaces config" "opus" "$output"

# config import creates .bak
assert_file_exists "config import creates backup" "$XDG_CONFIG_HOME/claudii/config.json.bak"

# config import — invalid JSON rejected
echo "not json" > "$XDG_CONFIG_HOME/claudii/bad.json"
output=$(bash "$CLAUDII_HOME/bin/claudii" config import "$XDG_CONFIG_HOME/claudii/bad.json" 2>&1 || true)
assert_contains "config import rejects invalid JSON" "valid JSON" "$output"

# config import — missing file rejected
output=$(bash "$CLAUDII_HOME/bin/claudii" config import /nonexistent/file.json 2>&1 || true)
assert_contains "config import rejects missing file" "not found" "$output"

# config import — unknown top-level key rejected
unknown_key_file="$XDG_CONFIG_HOME/claudii/unknown_key.json"
jq '. + {"__evil_key": "pwned"}' "$CLAUDII_HOME/config/defaults.json" > "$unknown_key_file"
output=$(bash "$CLAUDII_HOME/bin/claudii" config import "$unknown_key_file" 2>&1 || true)
assert_contains "config import rejects unknown top-level key" "unknown keys" "$output"
bash "$CLAUDII_HOME/bin/claudii" config import "$unknown_key_file" >/dev/null 2>&1 && _import_exit=0 || _import_exit=$?
assert_eq "config import unknown key exits non-zero" "1" "$_import_exit"

# config import — invalid agent name rejected
bad_agent_file="$XDG_CONFIG_HOME/claudii/bad_agent.json"
jq '.agents = {"../evil": {"model": "sonnet", "skill": "pwn"}}' "$CLAUDII_HOME/config/defaults.json" > "$bad_agent_file"
output=$(bash "$CLAUDII_HOME/bin/claudii" config import "$bad_agent_file" 2>&1 || true)
assert_contains "config import rejects invalid agent name" "invalid agent name" "$output"
bash "$CLAUDII_HOME/bin/claudii" config import "$bad_agent_file" >/dev/null 2>&1 && _agent_exit=0 || _agent_exit=$?
assert_eq "config import invalid agent exits non-zero" "1" "$_agent_exit"

# config import — reserved agent name rejected (shadow guard)
for _reserved in claudii claude clh; do
  reserved_file="$XDG_CONFIG_HOME/claudii/reserved_${_reserved}.json"
  jq --arg k "$_reserved" '.agents = {($k): {"model": "sonnet", "skill": "x"}}' \
    "$CLAUDII_HOME/config/defaults.json" > "$reserved_file"
  output=$(bash "$CLAUDII_HOME/bin/claudii" config import "$reserved_file" 2>&1 || true)
  assert_contains "config import rejects reserved agent name ($_reserved)" "reserved" "$output"
  bash "$CLAUDII_HOME/bin/claudii" config import "$reserved_file" >/dev/null 2>&1 && _re=0 || _re=$?
  assert_eq "config import reserved ($_reserved) exits non-zero" "1" "$_re"
done

# ── Hyphenated key regression (jq interprets '-' as subtraction without quoting) ──
bash "$CLAUDII_HOME/bin/claudii" config set session-dashboard.enabled on >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get session-dashboard.enabled 2>&1)
assert_eq "config get/set hyphenated key (session-dashboard.enabled)" "on" "$output"

# ── No-argument usage: clean Usage line, not a bash ${N:?} parameter-error leak ──
# get/set/import used ${3:?...}, which leaks "config.sh: line 23: 3: Usage..." to
# stderr. A plain guard prints the Usage line cleanly; the discriminating assert
# is the ABSENCE of the bash "config.sh: line" prefix (the Usage text appeared in
# the broken output too, so asserting only its presence would be vacuous).
for _cmd in get set import; do
  _na_out=$(bash "$CLAUDII_HOME/bin/claudii" config "$_cmd" 2>&1 || true)
  assert_contains "config $_cmd (no arg): prints Usage" "Usage: claudii config $_cmd" "$_na_out"
  assert_not_contains "config $_cmd (no arg): no bash parameter-error leak" "config.sh: line" "$_na_out"
  bash "$CLAUDII_HOME/bin/claudii" config "$_cmd" >/dev/null 2>&1 && _na_rc=0 || _na_rc=$?
  assert_eq "config $_cmd (no arg): exits non-zero" "1" "$_na_rc"
done
unset _cmd _na_out _na_rc

# Reset config to clean state for theme tests
bash "$CLAUDII_HOME/bin/claudii" config reset >/dev/null 2>&1

# config theme — list themes
output=$(bash "$CLAUDII_HOME/bin/claudii" config theme 2>&1)
assert_contains "config theme lists available themes" "default" "$output"
assert_contains "config theme lists pastel theme" "pastel" "$output"

# config theme pastel — set theme
bash "$CLAUDII_HOME/bin/claudii" config theme pastel >/dev/null 2>&1
output=$(jq -r '.theme.name' "$XDG_CONFIG_HOME/claudii/config.json" 2>/dev/null)
assert_eq "config theme pastel sets theme.name" "pastel" "$output"

# config theme list shows active marker after switch
output=$(bash "$CLAUDII_HOME/bin/claudii" config theme 2>&1)
assert_contains "config theme shows active marker for pastel" "* pastel" "$output"

# config theme default — set back to default
bash "$CLAUDII_HOME/bin/claudii" config theme default >/dev/null 2>&1
output=$(jq -r '.theme.name' "$XDG_CONFIG_HOME/claudii/config.json" 2>/dev/null)
assert_eq "config theme default restores default theme" "default" "$output"

# config theme unknown — error + non-zero exit
output=$(bash "$CLAUDII_HOME/bin/claudii" config theme unknown_xyz 2>&1 || true)
assert_contains "config theme unknown gives error" "Unknown theme" "$output"
bash "$CLAUDII_HOME/bin/claudii" config theme unknown_xyz >/dev/null 2>&1 && _theme_exit=0 || _theme_exit=$?
assert_eq "config theme unknown exits non-zero" "1" "$_theme_exit"


# ── Theme loading tests ──────────────────────────────────────────────────────

# Reset config to clean state
bash "$CLAUDII_HOME/bin/claudii" config reset >/dev/null 2>&1

# theme load: pastel theme produces different CLAUDII_CLR_ACCENT than default
bash "$CLAUDII_HOME/bin/claudii" config set theme.name pastel >/dev/null 2>&1
pastel_accent=$(CLAUDII_HOME="$CLAUDII_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" bash -c '
  source "$CLAUDII_HOME/lib/visual.sh"
  CONFIG_DIR="${XDG_CONFIG_HOME}/claudii"
  CONFIG="$CONFIG_DIR/config.json"
  DEFAULTS="$CLAUDII_HOME/config/defaults.json"
  _claudii_theme_load
  printf "%s" "$CLAUDII_CLR_ACCENT" | cat -v
')
assert_contains "theme load pastel: accent differs from default" "219" "$pastel_accent"

# theme load: default theme keeps original CLAUDII_CLR_ACCENT
bash "$CLAUDII_HOME/bin/claudii" config set theme.name default >/dev/null 2>&1
default_accent=$(CLAUDII_HOME="$CLAUDII_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" bash -c '
  source "$CLAUDII_HOME/lib/visual.sh"
  CONFIG_DIR="${XDG_CONFIG_HOME}/claudii"
  CONFIG="$CONFIG_DIR/config.json"
  DEFAULTS="$CLAUDII_HOME/config/defaults.json"
  _claudii_theme_load
  printf "%s" "$CLAUDII_CLR_ACCENT" | cat -v
')
assert_contains "theme load default: accent has 213" "213" "$default_accent"

# theme load: unknown theme name keeps defaults (no crash)
bash "$CLAUDII_HOME/bin/claudii" config set theme.name nonexistent >/dev/null 2>&1
unknown_accent=$(CLAUDII_HOME="$CLAUDII_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" bash -c '
  source "$CLAUDII_HOME/lib/visual.sh"
  CONFIG_DIR="${XDG_CONFIG_HOME}/claudii"
  CONFIG="$CONFIG_DIR/config.json"
  DEFAULTS="$CLAUDII_HOME/config/defaults.json"
  _claudii_theme_load
  printf "%s" "$CLAUDII_CLR_ACCENT" | cat -v
')
assert_contains "theme load unknown: accent keeps default 213" "213" "$unknown_accent"

# theme load: pastel also changes CLAUDII_CLR_GREEN (rate_ok)
bash "$CLAUDII_HOME/bin/claudii" config set theme.name pastel >/dev/null 2>&1
pastel_green=$(CLAUDII_HOME="$CLAUDII_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" bash -c '
  source "$CLAUDII_HOME/lib/visual.sh"
  CONFIG_DIR="${XDG_CONFIG_HOME}/claudii"
  CONFIG="$CONFIG_DIR/config.json"
  DEFAULTS="$CLAUDII_HOME/config/defaults.json"
  _claudii_theme_load
  printf "%s" "$CLAUDII_CLR_GREEN" | cat -v
')
assert_contains "theme load pastel: green uses 114" "114" "$pastel_green"

# ── _cfgget memo: write-then-read in the same process stays fresh ─────────────
# The per-key memo (printf -v dynamic vars) must be invalidated by _jq_update,
# and the whole pattern must work under macOS /bin/bash 3.2 (the test runner
# uses Homebrew bash 5.x, which would hide a 3.2-only substitution failure).
_memo_script='
  set -u
  source "$CLAUDII_HOME/lib/visual.sh"
  source "$CLAUDII_HOME/lib/spinner.sh"
  source "$CLAUDII_HOME/lib/helpers.sh"
  _cfg_init
  v1=$(_cfgget status.cache_ttl)
  v1b=$(_cfgget status.cache_ttl)          # memo hit
  _jq_update "$CONFIG" ".status.cache_ttl = 777"
  v2=$(_cfgget status.cache_ttl)           # must see the new value
  _jq_update "$CONFIG" "del(.fallback)"    # remove key from user config entirely
  f1=$(_cfgget fallback.enabled)           # absent in config -> defaults fallback path
  printf "%s|%s|%s|%s" "$v1" "$v1b" "$v2" "$f1"
'
for _memo_bash in /bin/bash bash; do
  bash "$CLAUDII_HOME/bin/claudii" config reset >/dev/null 2>&1
  _memo_out=$(CLAUDII_HOME="$CLAUDII_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    "$_memo_bash" -c "$_memo_script" 2>&1)
  assert_eq "_cfgget memo ($_memo_bash): fresh after _jq_update, defaults fallback intact" \
    "300|300|777|true" "$_memo_out"
done
unset _memo_script _memo_bash _memo_out

# Cleanup
rm -rf "$XDG_CONFIG_HOME"
unset XDG_CONFIG_HOME
