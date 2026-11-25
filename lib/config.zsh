# claudii config — reads ~/.config/claudii/config.json, falls back to defaults

zmodload -F zsh/stat b:zstat 2>/dev/null && typeset -g _CLAUDII_HAVE_ZSTAT=1 || typeset -g _CLAUDII_HAVE_ZSTAT=0
zmodload zsh/datetime 2>/dev/null  # EPOCHSECONDS

CLAUDII_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claudii"
CLAUDII_CONFIG="$CLAUDII_CONFIG_DIR/config.json"
CLAUDII_DEFAULTS="$CLAUDII_HOME/config/defaults.json"

[[ -d "$CLAUDII_CONFIG_DIR" ]] || mkdir -p "$CLAUDII_CONFIG_DIR"
[[ -f "$CLAUDII_CONFIG" ]] || cp "$CLAUDII_DEFAULTS" "$CLAUDII_CONFIG"

# Config cache — keyed by dot-notation path, e.g. _CLAUDII_CFG_CACHE[statusline.models]
typeset -gA _CLAUDII_CFG_CACHE _CLAUDII_DEF_CACHE
typeset -g  _CLAUDII_CFG_MTIME=0

# Flatten JSON to dot-notation key=value lines (called once per load)
# Note: paths(scalars) skips false/null (falsy) — use type check instead
_claudii_json_flatten() {
  jq -r 'paths as $p | select(getpath($p) | (type != "object") and (type != "array")) | "\($p | join("."))=\(getpath($p))"' "$1" 2>/dev/null
}

# Load defaults into _CLAUDII_DEF_CACHE once at plugin init (defaults never change)
_claudii_defaults_load() {
  local _t=$EPOCHREALTIME
  _CLAUDII_DEF_CACHE=()
  local line
  while IFS= read -r line; do
    _CLAUDII_DEF_CACHE[${line%%=*}]="${line#*=}"
  done < <(_claudii_json_flatten "$CLAUDII_DEFAULTS")
  _CLAUDII_METRICS[config.defaults_us]=$(( int(($EPOCHREALTIME - _t) * 1000000) ))
  _claudii_theme_load
}

# Reload user config only when mtime changed — fast no-op on cache hit
_claudii_cache_load() {
  local mtime=0
  if (( _CLAUDII_HAVE_ZSTAT )); then
    local -A _zst
    zstat -H _zst "$CLAUDII_CONFIG" 2>/dev/null && mtime=${_zst[mtime]:-0}
  else
    mtime=$(stat -f%m "$CLAUDII_CONFIG" 2>/dev/null || stat -c%Y "$CLAUDII_CONFIG" 2>/dev/null || echo 0)
  fi
  [[ "$mtime" == "$_CLAUDII_CFG_MTIME" ]] && return 0
  _CLAUDII_CFG_MTIME=$mtime
  _CLAUDII_METRICS[config.reloads]=$(( ${_CLAUDII_METRICS[config.reloads]:-0} + 1 ))
  local _t=$EPOCHREALTIME
  _CLAUDII_CFG_CACHE=()
  local line
  while IFS= read -r line; do
    _CLAUDII_CFG_CACHE[${line%%=*}]="${line#*=}"
  done < <(_claudii_json_flatten "$CLAUDII_CONFIG")
  _CLAUDII_METRICS[config.cache_load_us]=$(( int(($EPOCHREALTIME - _t) * 1000000) ))
  # Sync debug level to env var so _claudii_log needs no further lookups
  CLAUDII_LOG_LEVEL="${_CLAUDII_CFG_CACHE[debug.level]:-${_CLAUDII_DEF_CACHE[debug.level]:-off}}"
  _claudii_log debug "config: reload ${_CLAUDII_METRICS[config.cache_load_us]}µs"
  _claudii_theme_load
}

function claudii_config_get {
  _claudii_cache_load
  local val="${_CLAUDII_CFG_CACHE[$1]:-}"
  [[ -z "$val" ]] && val="${_CLAUDII_DEF_CACHE[$1]:-}"
  echo "$val"
}

# _claudii_log lives in lib/log.sh (sourced by claudii.plugin.zsh before this
# file); a zsh copy here used to shadow it.

# Boot: load defaults immediately (once), user config on first access
_claudii_defaults_load
