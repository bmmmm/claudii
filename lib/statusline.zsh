# claudii statusline — RPROMPT with per-model health + last-fetch age

function _claudii_statusline {
  local _t=$EPOCHREALTIME
  _claudii_statusline_render
  local _el=$(( int(($EPOCHREALTIME - _t) * 1000000) ))
  _CLAUDII_METRICS[precmd.last_us]=$_el
  _CLAUDII_METRICS[precmd.calls]=$(( ${_CLAUDII_METRICS[precmd.calls]:-0} + 1 ))
  _CLAUDII_METRICS[precmd.total_us]=$(( ${_CLAUDII_METRICS[precmd.total_us]:-0} + _el ))
  _claudii_log debug "precmd: $(_claudii_fmt_us $_el)"
}

function _claudii_statusline_render {
  # Single cache-load call — fast mtime check, jq only on config change
  _claudii_cache_load
  [[ "${_CLAUDII_CFG_CACHE[statusline.enabled]:-${_CLAUDII_DEF_CACHE[statusline.enabled]:-true}}" != "true" ]] && { RPROMPT=""; return; }

  local status_cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models"
  local ttl="${_CLAUDII_CFG_CACHE[status.cache_ttl]:-${_CLAUDII_DEF_CACHE[status.cache_ttl]:-900}}"

  if [[ ! -f "$status_cache" ]]; then
    () { setopt local_options no_monitor; "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null & }
    RPROMPT="%F{8}[…]%f"; return
  fi

  # Age calculation — no subprocesses: zstat builtin + $EPOCHSECONDS
  local age=0
  if (( _CLAUDII_HAVE_ZSTAT )); then
    local -A _zst
    zstat -H _zst "$status_cache" 2>/dev/null \
      && age=$(( ${EPOCHSECONDS:-$(date +%s)} - ${_zst[mtime]:-0} ))
  else
    age=$(( $(date +%s) - $(stat -c%Y "$status_cache" 2>/dev/null || stat -f%m "$status_cache" 2>/dev/null || echo 0) ))
  fi

  if (( age > ttl )); then
    _claudii_log debug "statusline: cache stale (${age}s > ${ttl}s), refreshing in background"
    () { setopt local_options no_monitor; "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null & }
  fi

  local models_str="${_CLAUDII_CFG_CACHE[statusline.models]:-${_CLAUDII_DEF_CACHE[statusline.models]:-opus,sonnet,haiku}}"
  local models=(${(s:,:)models_str})

  # Read cache file once — $(<file) is a zsh builtin, no subprocess
  # Guard against TOCTOU: file may be deleted between age check and read
  local cache_content=""
  { cache_content=$(<"$status_cache"); } 2>/dev/null
  [[ -z "$cache_content" ]] && { RPROMPT="%F{8}[…]%f"; return; }

  local segments=""
  for model in "${models[@]}"; do
    model="${model// /}"
    # Pattern match in-process — no grep subprocess
    if [[ $'\n'"$cache_content" == *$'\n'"${model}=down"* ]]; then
      segments+="%F{red}${(C)model} ↓%f "
    elif [[ $'\n'"$cache_content" == *$'\n'"${model}=degraded"* ]]; then
      segments+="%F{yellow}${(C)model} ~%f "
    else
      segments+="%F{green}${(C)model} ✓%f "
    fi
  done

  local age_str refreshing="" unreachable=""
  if (( age < 60 )); then age_str="${age}s"
  elif (( age < 3600 )); then age_str="$(( age / 60 ))m"
  else age_str="$(( age / 3600 ))h"
  fi
  (( age > ttl )) && refreshing=" %F{8}⟳%f"
  [[ $'\n'"$cache_content" == *$'\n'"_api=unreachable"* ]] && unreachable=" %F{8}?%f"

  local rprompt="[${segments% }] %F{8}${age_str}%f${refreshing}${unreachable}"

  # Session data — shown when a Claude Code session is active (cache < 5min old)
  local session_cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/session-data"
  if [[ -f "$session_cache" ]]; then
    local session_age=0
    if (( _CLAUDII_HAVE_ZSTAT )); then
      local -A _szst
      zstat -H _szst "$session_cache" 2>/dev/null \
        && session_age=$(( ${EPOCHSECONDS:-$(date +%s)} - ${_szst[mtime]:-0} ))
    else
      session_age=$(( $(date +%s) - $(stat -c%Y "$session_cache" 2>/dev/null || stat -f%m "$session_cache" 2>/dev/null || echo 0) ))
    fi
    if (( session_age < 300 )); then
      local session_content=""
      { session_content=$(<"$session_cache"); } 2>/dev/null
      if [[ -n "$session_content" ]]; then
        local s_model="" s_ctx="" s_cost="" s_5h="" s_7d=""
        # Pattern matching — same technique as status-models, zero subprocesses
        [[ $'\n'"$session_content" == *$'\n'model=* ]] && s_model="${${session_content#*model=}%%$'\n'*}"
        [[ $'\n'"$session_content" == *$'\n'ctx_pct=* ]] && s_ctx="${${session_content#*ctx_pct=}%%$'\n'*}"
        [[ $'\n'"$session_content" == *$'\n'cost=* ]] && s_cost="${${session_content#*cost=}%%$'\n'*}"
        [[ $'\n'"$session_content" == *$'\n'rate_5h=* ]] && s_5h="${${session_content#*rate_5h=}%%$'\n'*}"
        [[ $'\n'"$session_content" == *$'\n'rate_7d=* ]] && s_7d="${${session_content#*rate_7d=}%%$'\n'*}"
        # Build compact session segment
        local sess=""
        [[ -n "$s_ctx" ]] && sess+="%F{8}${s_ctx}%%%f"
        if [[ -n "$s_cost" && "$s_cost" != "0" ]]; then
          [[ -n "$sess" ]] && sess+=" "
          sess+="%F{cyan}\$${s_cost}%f"
        fi
        if [[ -n "$s_5h" ]]; then
          [[ -n "$sess" ]] && sess+=" "
          sess+="%F{8}5h:${s_5h%.*}%%%f"
        fi
        [[ -n "$sess" ]] && rprompt+=" %F{8}│%f ${sess}"
      fi
    fi
  fi

  RPROMPT="$rprompt"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claudii_statusline
