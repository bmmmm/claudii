# claudii logging — source this in bash scripts
# Usage: _claudii_log <level> <message>
# Levels: off error warn info debug
# Override via CLAUDII_LOG_LEVEL env var

# Capture home at source-time so the function has it without CLAUDII_HOME being exported
_CLAUDII_LOG_HOME="${CLAUDII_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

_claudii_log_num() {
  case "$1" in
    off)   echo 0 ;;
    error) echo 1 ;;
    warn)  echo 2 ;;
    info)  echo 3 ;;
    debug) echo 4 ;;
    *)     echo 0 ;;
  esac
}

_claudii_log() {
  local level="$1"; shift
  local msg="$*"

  # Resolve current level: env var > config > defaults > off
  local current="${CLAUDII_LOG_LEVEL:-}"
  if [[ -z "$current" ]]; then
    local _cfg="${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json"
    local _def="${_CLAUDII_LOG_HOME}/config/defaults.json"
    current=$(jq -r '.debug.level // empty' "$_cfg" 2>/dev/null)
    [[ -z "$current" ]] && current=$(jq -r '.debug.level // "off"' "$_def" 2>/dev/null)
    current="${current:-off}"
    # Cache for this script run
    CLAUDII_LOG_LEVEL="$current"
  fi

  [[ "$current" == "off" ]] && return 0
  (( $(_claudii_log_num "$level") > $(_claudii_log_num "$current") )) && return 0

  local color
  case "$level" in
    error) color=$'\033[0;31m' ;;
    warn)  color=$'\033[0;33m' ;;
    info)  color=$'\033[0;36m' ;;
    debug) color=$'\033[0;90m' ;;
    *)     color="" ;;
  esac
  printf "%s[claudii:%s] %s"$'\033[0m\n' "$color" "$level" "$msg" >&2
}
