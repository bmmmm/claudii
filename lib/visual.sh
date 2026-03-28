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
CLAUDII_CLR_GREEN="\033[0;32m"
CLAUDII_CLR_YELLOW="\033[0;33m"
CLAUDII_CLR_RED="\033[0;31m"
CLAUDII_CLR_CYAN="\033[0;36m"
CLAUDII_CLR_DIM="\033[2m"
CLAUDII_CLR_BOLD="\033[1m"
CLAUDII_CLR_RESET="\033[0m"

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
