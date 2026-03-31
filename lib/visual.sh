# claudii visual language — POSIX-compatible (bash + zsh)
# Symbol and color constants, plus a helper to print colored symbols.
# Source this file; never call it directly.

# ── Symbols ──────────────────────────────────────────────────────────────────
CLAUDII_SYM_ACTIVE="●"     # active session
CLAUDII_SYM_INACTIVE="○"   # ended / inactive
CLAUDII_SYM_WARN="⚠"       # warning (rate limit, stale, etc.)
CLAUDII_SYM_ERROR="✗"      # error / failure
CLAUDII_SYM_OK="✓"         # ok / success
CLAUDII_SYM_DOWN="↓"       # model down
CLAUDII_SYM_DEGRADED="~"   # model degraded
CLAUDII_SYM_SEP="│"        # separator
CLAUDII_SYM_BAR_FULL="█"   # progress bar — filled block
CLAUDII_SYM_BAR_EMPTY="░"  # progress bar — empty block

# ── ANSI colors ───────────────────────────────────────────────────────────────
CLAUDII_CLR_GREEN=$'\033[0;32m'
CLAUDII_CLR_YELLOW=$'\033[0;33m'
CLAUDII_CLR_RED=$'\033[0;31m'
CLAUDII_CLR_CYAN=$'\033[0;36m'
CLAUDII_CLR_DIM=$'\033[2m'
CLAUDII_CLR_BOLD=$'\033[1m'
CLAUDII_CLR_ACCENT=$'\033[38;5;213m'
CLAUDII_CLR_RESET=$'\033[0m'

# ── Helper ────────────────────────────────────────────────────────────────────
# _claudii_sym <name>
# Print a colored symbol to stdout.
# Names: active inactive warn error ok down degraded sep
_claudii_sym() {
  local name="$1"
  local color sym
  case "$name" in
    active)   color="$CLAUDII_CLR_GREEN"  sym="$CLAUDII_SYM_ACTIVE"   ;;
    inactive) color="$CLAUDII_CLR_DIM"    sym="$CLAUDII_SYM_INACTIVE" ;;
    warn)     color="$CLAUDII_CLR_YELLOW" sym="$CLAUDII_SYM_WARN"     ;;
    error)    color="$CLAUDII_CLR_RED"    sym="$CLAUDII_SYM_ERROR"    ;;
    ok)       color="$CLAUDII_CLR_GREEN"  sym="$CLAUDII_SYM_OK"       ;;
    down)     color="$CLAUDII_CLR_RED"    sym="$CLAUDII_SYM_DOWN"     ;;
    degraded) color="$CLAUDII_CLR_YELLOW" sym="$CLAUDII_SYM_DEGRADED" ;;
    sep)      color=""                    sym="$CLAUDII_SYM_SEP"      ;;
    *)        printf '%s\n' "$name"; return 1 ;;
  esac
  printf "${color}${sym}${CLAUDII_CLR_RESET}"
}

# ── Theme loader ──────────────────────────────────────────────────────────────
# Reads theme.name from config and applies preset colors to CLAUDII_CLR_* vars.
# POSIX-compatible (bash + zsh). Requires jq.
# Falls back silently to hardcoded defaults if anything fails.
_claudii_theme_load() {
  local theme_name=""

  # 1. Resolve theme name — zsh plugin cache first, then jq fallback
  if [ -n "${_CLAUDII_CFG_CACHE+x}" ] 2>/dev/null; then
    # zsh associative-array context (plugin loaded)
    theme_name="${_CLAUDII_CFG_CACHE[theme.name]:-${_CLAUDII_DEF_CACHE[theme.name]:-default}}"
  elif [ -n "${CONFIG:-}" ] && [ -f "${CONFIG:-}" ]; then
    # bash bin/claudii context — CONFIG set by _cfg_init
    theme_name=$(jq -r '.theme.name // empty' "$CONFIG" 2>/dev/null)
    [ -z "$theme_name" ] && theme_name=$(jq -r '.theme.name // empty' "${DEFAULTS:-${CLAUDII_HOME}/config/defaults.json}" 2>/dev/null)
  elif [ -n "${CLAUDII_CONFIG:-}" ] && [ -f "${CLAUDII_CONFIG:-}" ]; then
    theme_name=$(jq -r '.theme.name // empty' "$CLAUDII_CONFIG" 2>/dev/null)
  fi

  # Fall back to "default" if still empty
  [ -z "$theme_name" ] && theme_name="default"

  # 2. Handle "auto" — detect light/dark terminal
  if [ "$theme_name" = "auto" ]; then
    local bg_component=""
    if [ -n "${COLORFGBG:-}" ]; then
      # COLORFGBG format: "fg;bg" — extract last component
      bg_component="${COLORFGBG##*;}"
      if [ -n "$bg_component" ] && [ "$bg_component" -le 8 ] 2>/dev/null; then
        theme_name="pastel"  # light terminal
      else
        theme_name="default" # dark terminal or detection failed
      fi
    else
      # No COLORFGBG — try TERM_PROGRAM heuristics
      case "${TERM_PROGRAM:-}" in
        Apple_Terminal) theme_name="pastel"  ;; # often light background
        *)              theme_name="default" ;; # dark is more common
      esac
    fi
  fi

  # 3. "default" theme = hardcoded values (already set at top of file) — skip jq
  [ "$theme_name" = "default" ] && return 0

  # 4. Look up preset colors via jq from defaults file
  local defaults_file="${DEFAULTS:-${CLAUDII_DEFAULTS:-${CLAUDII_HOME:-}/config/defaults.json}}"
  [ ! -f "${defaults_file:-}" ] && return 0

  local colors
  colors=$(jq -r --arg name "$theme_name" \
    '.theme_presets[$name].colors // empty | to_entries[] | "\(.key)=\(.value)"' \
    "$defaults_file" 2>/dev/null) || return 0

  # Empty output means unknown preset — keep defaults
  [ -z "$colors" ] && return 0

  # 5. Apply colors to CLAUDII_CLR_* variables
  local line key code
  while IFS= read -r line; do
    key="${line%%=*}"
    code="${line#*=}"
    [ -z "$code" ] && continue
    case "$key" in
      accent)    CLAUDII_CLR_ACCENT=$'\033['"${code}"'m' ;;
      rate_ok)   CLAUDII_CLR_GREEN=$'\033['"${code}"'m'  ;;
      rate_warn) CLAUDII_CLR_YELLOW=$'\033['"${code}"'m' ;;
      rate_crit) CLAUDII_CLR_RED=$'\033['"${code}"'m'    ;;
      reset_ok)  CLAUDII_CLR_DIM=$'\033['"${code}"'m'    ;;
    esac
  done <<EOF
$colors
EOF

  return 0
}
