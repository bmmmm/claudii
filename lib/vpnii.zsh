# vpnii — VPN status segment for claudii RPROMPT
#
# State file written by wg-quick PostUp/PreDown — no sudo needed in precmd.
# Appends to RPROMPT after claudii's statusline hook (FIFO hook order).
#
# PostUp:  mkdir -p /Users/bma/.cache/claudii && echo "TunnelName" > /Users/bma/.cache/claudii/vpnii
# PreDown: rm -f /Users/bma/.cache/claudii/vpnii

typeset -g _VPNII_STATE_FILE="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/vpnii"

function _vpnii_precmd {
  [[ -f "$_VPNII_STATE_FILE" ]] || return
  local tunnel
  tunnel=$(<"$_VPNII_STATE_FILE")
  [[ -z "$tunnel" ]] && return
  RPROMPT="${RPROMPT:+${RPROMPT} }%F{green}${CLAUDII_SYM_VPN} ${tunnel}%f"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
add-zsh-hook    precmd _vpnii_precmd
