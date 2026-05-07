# vpnii — VPN status segment for claudii RPROMPT
#
# Renders both tunnel types side by side (split-routing is common):
#   ⬡ <tunnel>   WireGuard, via state file written by `claudii vpnii set/clear`
#                from wg-quick PostUp/PreDown. The CLI drops privilege so the
#                cache file is owned by the real user (no sudo for `rm`).
#   ⬢ ts        Tailscale, via live ifconfig probe for CGNAT 100.64.0.0/10.
#                No daemon dep, no `tailscale status` roundtrip.
#
# wg conf:
#   PostUp  = claudii vpnii set HomeLab
#   PreDown = claudii vpnii clear
#
# Resolves the target user via SUDO_USER → /dev/console owner (GUI) → $USER
# → CLAUDII_USER override. Override with: claudii vpnii set HomeLab --user bma

typeset -g _VPNII_STATE_FILE="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/vpnii"

function _vpnii_precmd {
  local seg=""
  # WireGuard — state file is the single source of truth (vpnii set/clear).
  if [[ -f "$_VPNII_STATE_FILE" ]]; then
    local tunnel
    tunnel=$(<"$_VPNII_STATE_FILE")
    [[ -n "$tunnel" ]] && seg="%F{green}${CLAUDII_SYM_VPN}%f %F{8}${tunnel}%f"
  fi
  # Tailscale — live ifconfig probe for an IPv4 in 100.64.0.0/10 (RFC 6598
  # CGNAT, what Tailscale assigns). No daemon dep, no `tailscale status`
  # roundtrip (too slow for precmd). Mirrors bin/claudii-cc-statusline.
  if ifconfig 2>/dev/null | command grep -qE 'inet 100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'; then
    [[ -n "$seg" ]] && seg+="  "
    seg+="%F{green}${CLAUDII_SYM_TAILSCALE}%f %F{8}ts%f"
  fi
  [[ -n "$seg" ]] && RPROMPT="${RPROMPT:+${RPROMPT} }${seg}"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
add-zsh-hook    precmd _vpnii_precmd
