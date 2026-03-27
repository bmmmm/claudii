# claudii config — reads ~/.config/claudii/config.json, falls back to defaults

CLAUDII_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claudii"
CLAUDII_CONFIG="$CLAUDII_CONFIG_DIR/config.json"
CLAUDII_DEFAULTS="$CLAUDII_HOME/config/defaults.json"

[[ -d "$CLAUDII_CONFIG_DIR" ]] || mkdir -p "$CLAUDII_CONFIG_DIR"
[[ -f "$CLAUDII_CONFIG" ]] || cp "$CLAUDII_DEFAULTS" "$CLAUDII_CONFIG"

function claudii_config_get {
  local jq_expr="if (.$1 | type) != \"null\" then (.$1 | tostring) else empty end"
  local val=$(jq -r "$jq_expr" "$CLAUDII_CONFIG" 2>/dev/null)
  [[ -z "$val" ]] && val=$(jq -r "$jq_expr" "$CLAUDII_DEFAULTS" 2>/dev/null)
  echo "$val"
}

function _claudii_log {
  local level="$1"; shift
  local msg="$*"

  local current="${CLAUDII_LOG_LEVEL:-$(claudii_config_get debug.level)}"
  current="${current:-off}"
  [[ "$current" == "off" ]] && return

  # Level comparison via case
  _claudii_lvl_num() { case "$1" in off) echo 0;; error) echo 1;; warn) echo 2;; info) echo 3;; debug) echo 4;; *) echo 0;; esac }
  (( $(_claudii_lvl_num "$level") > $(_claudii_lvl_num "$current") )) && return

  local color
  case "$level" in
    error) color="\033[0;31m" ;;
    warn)  color="\033[0;33m" ;;
    info)  color="\033[0;36m" ;;
    debug) color="\033[0;90m" ;;
    *)     color="" ;;
  esac
  printf "${color}[claudii:%s] %s\033[0m\n" "$level" "$msg" >&2
}
