# claudii.plugin.zsh — Claude Interaction Intelligence
# Compatible with: oh-my-zsh, zinit, manual source

zmodload zsh/datetime  2>/dev/null  # EPOCHREALTIME — must load before first timestamp
zmodload zsh/mathfunc 2>/dev/null  # int() for float→int truncation
typeset -gA _CLAUDII_METRICS
typeset -g  _claudii_t0=$EPOCHREALTIME  # plugin load start

export CLAUDII_HOME="${0:A:h}"

[[ ":$PATH:" != *":$CLAUDII_HOME/bin:"* ]] && export PATH="$CLAUDII_HOME/bin:$PATH"

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
