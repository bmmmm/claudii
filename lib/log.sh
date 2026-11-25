# claudii logging — the one _claudii_log, shared by bash (bin/*) and zsh
# (claudii.plugin.zsh sources it before lib/config.zsh).
# Usage: _claudii_log <level> <message>
# Levels: off error warn info debug
# Level source: CLAUDII_LOG_LEVEL if set (the zsh plugin syncs it from
# debug.level on every config reload), else debug.level resolved lazily via jq
# once per process.

# Capture home at source-time so the function has it without CLAUDII_HOME being exported
_CLAUDII_LOG_HOME="${CLAUDII_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Level name → number in _CLAUDII_LOG_N. Sets a variable instead of echoing:
# a $(...) per comparison forked twice per log line, and the zsh plugin logs
# from precmd.
_claudii_log_num() {
  case "$1" in
    error) _CLAUDII_LOG_N=1 ;;
    warn)  _CLAUDII_LOG_N=2 ;;
    info)  _CLAUDII_LOG_N=3 ;;
    debug) _CLAUDII_LOG_N=4 ;;
    *)     _CLAUDII_LOG_N=0 ;;
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
  local _want
  _claudii_log_num "$level";   _want=$_CLAUDII_LOG_N
  _claudii_log_num "$current"
  (( _want > _CLAUDII_LOG_N )) && return 0

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
