# vpnii — VPN status segment for claudii RPROMPT
#
# Renders both tunnel types side by side (split-routing is common):
#   ⬡ <tunnel>   WireGuard, via state file written by `claudii vpnii set/clear`
#                from wg-quick PostUp/PreDown. The CLI drops privilege so the
#                cache file is owned by the real user (no sudo for `rm`).
#   ⬢ ts        Tailscale, via ifconfig probe for CGNAT 100.64.0.0/10, cached
#                ~30s so the precmd does not fork ifconfig on every prompt.
#
# wg conf:
#   PostUp  = claudii vpnii set HomeLab
#   PreDown = claudii vpnii clear
#
# Resolves the target user via SUDO_USER → /dev/console owner (GUI) → $USER
# → CLAUDII_USER override. Override with: claudii vpnii set HomeLab --user bma

typeset -g  _VPNII_STATE_FILE="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/vpnii"
typeset -g  _VPNII_TS_CACHE="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/vpnii-ts"
typeset -gi _VPNII_TS_TTL=30

# Tailscale presence — an IPv4 in 100.64.0.0/10 (RFC 6598 CGNAT, what Tailscale
# assigns). The ifconfig probe is a fork + grep, too expensive to run on every
# prompt, so the up/down result is cached ~30s in $_VPNII_TS_CACHE
# ("<epoch> <0|1>", 1 = up). On a cache hit the read is a $(<) param expansion —
# no fork. Returns 0 when Tailscale is up. Cache is shared with
# bin/claudii-cc-statusline (same file + format); torn/garbage reads fall through
# to a re-probe via the numeric guard.
function _vpnii_tailscale_up {
  local _now=${EPOCHSECONDS:-0} _c _ts _val
  if [[ -r "$_VPNII_TS_CACHE" ]]; then
    _c=$(<"$_VPNII_TS_CACHE")
    _ts=${_c%% *}; _val=${_c##* }
    if [[ "$_ts" == <-> ]] && (( _now - _ts < _VPNII_TS_TTL )); then
      [[ "$_val" == 1 ]] && return 0 || return 1
    fi
  fi
  local _up=1
  ifconfig 2>/dev/null | command grep -qE 'inet 100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' && _up=0
  print -r -- "$_now $(( _up == 0 ? 1 : 0 ))" >| "$_VPNII_TS_CACHE" 2>/dev/null
  return $_up
}

function _vpnii_precmd {
  local seg=""
  # WireGuard — state file is the single source of truth (vpnii set/clear).
  if [[ -f "$_VPNII_STATE_FILE" ]]; then
    local tunnel
    tunnel=$(<"$_VPNII_STATE_FILE")
    [[ -n "$tunnel" ]] && seg="%F{green}${CLAUDII_SYM_VPN}%f %F{8}${tunnel}%f"
  fi
  # Tailscale — cached ifconfig probe (see _vpnii_tailscale_up); no per-prompt fork.
  if _vpnii_tailscale_up; then
    [[ -n "$seg" ]] && seg+="  "
    seg+="%F{green}${CLAUDII_SYM_TAILSCALE}%f %F{8}ts%f"
  fi
  [[ -n "$seg" ]] && RPROMPT="${RPROMPT:+${RPROMPT} }${seg}"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
add-zsh-hook    precmd _vpnii_precmd
