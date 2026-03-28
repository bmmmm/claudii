# claudii.plugin.zsh — Claude Interaction Intelligence
# Compatible with: oh-my-zsh, zinit, manual source

zmodload zsh/datetime  2>/dev/null  # EPOCHREALTIME — must load before first timestamp
zmodload zsh/mathfunc 2>/dev/null  # int() for float→int truncation
typeset -gA _CLAUDII_METRICS
typeset -g  _claudii_t0=$EPOCHREALTIME  # plugin load start

export CLAUDII_HOME="${0:A:h}"

[[ ":$PATH:" != *":$CLAUDII_HOME/bin:"* ]] && export PATH="$CLAUDII_HOME/bin:$PATH"

# Conflict detection — warn if another claudii is already in PATH from a different install
() {
  local other=${commands[claudii]:-}
  [[ -z "$other" || "$other" == "$CLAUDII_HOME/bin/claudii" ]] && return
  print -P "%F{yellow}claudii: conflict — $other is not from $CLAUDII_HOME%f" >&2
  print -P "%F{yellow}  → check ~/.zshrc for duplicate source lines%f" >&2
}

# Register man pages
[[ -d "$CLAUDII_HOME/man" ]] && export MANPATH="$CLAUDII_HOME/man:${MANPATH:-}"

# Register zsh completions
[[ -d "$CLAUDII_HOME/completions" ]] && fpath=("$CLAUDII_HOME/completions" $fpath)

# Clean up stale hooks on re-source
autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _claudii_rprompt 2>/dev/null
add-zsh-hook -d precmd _claudii_statusline 2>/dev/null
RPROMPT=""

source "$CLAUDII_HOME/lib/config.zsh"
source "$CLAUDII_HOME/lib/functions.zsh"
source "$CLAUDII_HOME/lib/statusline.zsh"

_CLAUDII_METRICS[plugin.load_us]=$(( int(($EPOCHREALTIME - _claudii_t0) * 1000000) ))
unset _claudii_t0

# Head-start: fire status refresh now if cache is absent, so the background
# job has more time to finish before the first prompt renders.
[[ -f "${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models" ]] || \
  ( "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null & )
