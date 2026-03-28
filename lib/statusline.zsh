# claudii statusline — RPROMPT with per-model health + last-fetch age
# shellcheck source=lib/visual.sh
source "${CLAUDII_HOME}/lib/visual.sh"

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
  [[ "${_CLAUDII_CFG_CACHE[statusline.enabled]:-${_CLAUDII_DEF_CACHE[statusline.enabled]:-true}}" != "true" ]] && { RPROMPT=""; PROMPT="${_CLAUDII_USER_PROMPT}"; return; }

  local status_cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models"
  local ttl="${_CLAUDII_CFG_CACHE[status.cache_ttl]:-${_CLAUDII_DEF_CACHE[status.cache_ttl]:-900}}"

  if [[ ! -f "$status_cache" ]]; then
    ( "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null & )
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
    ( "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null & )
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
      segments+="%F{red}${(C)model} ${CLAUDII_SYM_DOWN}%f "
    elif [[ $'\n'"$cache_content" == *$'\n'"${model}=degraded"* ]]; then
      segments+="%F{yellow}${(C)model} ${CLAUDII_SYM_DEGRADED}%f "
    else
      segments+="%F{green}${(C)model} ${CLAUDII_SYM_OK}%f "
    fi
  done

  local age_str refreshing="" unreachable=""
  if (( age < 60 )); then age_str="${age}s"
  elif (( age < 3600 )); then age_str="$(( age / 60 ))m"
  else age_str="$(( age / 3600 ))h"
  fi
  (( age > ttl )) && refreshing=" %F{8}⟳%f"
  [[ $'\n'"$cache_content" == *$'\n'"_api=unreachable"* ]] && unreachable=" %F{8}?%f"

  RPROMPT="[${segments% }] %F{8}${age_str}%f${refreshing}${unreachable}"

  # Session bar — prepends a line to PROMPT (avoids stdout/command-output confusion)
  _claudii_session_bar
}

typeset -g _CLAUDII_LAST_SESSION_BAR=""

function _claudii_session_bar {
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local session_cache="" best_mtime=0

  # Find freshest session-* file
  for _sf in "$_cache_base"/session-*(N); do
    local _sf_mt=0
    if (( _CLAUDII_HAVE_ZSTAT )); then
      local -A _sfst
      zstat -H _sfst "$_sf" 2>/dev/null && _sf_mt=${_sfst[mtime]:-0}
    else
      _sf_mt=$(stat -c%Y "$_sf" 2>/dev/null || stat -f%m "$_sf" 2>/dev/null || echo 0)
    fi
    (( _sf_mt > best_mtime )) && best_mtime=$_sf_mt && session_cache=$_sf
  done

  if [[ -z "$session_cache" ]]; then
    PROMPT="${_CLAUDII_USER_PROMPT}"
    return
  fi
  local session_age=$(( ${EPOCHSECONDS:-$(date +%s)} - best_mtime ))
  if (( session_age >= 300 )); then
    PROMPT="${_CLAUDII_USER_PROMPT}"
    return
  fi

  local sc=""
  { sc=$(<"$session_cache"); } 2>/dev/null
  if [[ -z "$sc" ]]; then
    PROMPT="${_CLAUDII_USER_PROMPT}"
    return
  fi

  # Parse all fields via pattern matching — zero subprocesses
  local s_model="" s_ctx="" s_cost="" s_5h="" s_7d="" s_r5h="" s_r7d="" s_worktree="" s_agent="" s_burn_eta="" s_ppid=""
  [[ $'\n'"$sc" == *$'\n'model=* ]]    && s_model="${${sc#*model=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'ctx_pct=* ]]  && s_ctx="${${sc#*ctx_pct=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'cost=* ]]     && s_cost="${${sc#*cost=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'rate_5h=* ]]  && s_5h="${${sc#*rate_5h=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'rate_7d=* ]]  && s_7d="${${sc#*rate_7d=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'reset_5h=* ]] && s_r5h="${${sc#*reset_5h=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'reset_7d=* ]] && s_r7d="${${sc#*reset_7d=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'worktree=* ]] && s_worktree="${${sc#*worktree=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'agent=* ]]    && s_agent="${${sc#*agent=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'burn_eta=* ]] && s_burn_eta="${${sc#*burn_eta=}%%$'\n'*}"
  [[ $'\n'"$sc" == *$'\n'ppid=* ]]     && s_ppid="${${sc#*ppid=}%%$'\n'*}"

  if [[ -z "$s_model" ]]; then
    PROMPT="${_CLAUDII_USER_PROMPT}"
    return
  fi

  # Skip session bar if the Claude process is no longer running — prevents stale
  # data from showing in new terminals after a session ends.
  # kill -0 is a no-op signal: just checks if PID exists, no subprocess needed.
  if [[ -n "$s_ppid" && "$s_ppid" =~ ^[0-9]+$ ]]; then
    kill -0 "$s_ppid" 2>/dev/null || return
  fi

  # Build session bar
  local bar=""
  local SEP="%F{8} │%f "

  # Model (bold)
  bar+="%B${s_model}%b"

  # Worktree and agent context (dim brackets)
  [[ -n "$s_worktree" ]] && bar+=" %F{8}[wt:${s_worktree}]%f"
  [[ -n "$s_agent" ]]    && bar+=" %F{8}[agent:${s_agent}]%f"

  # Context bar (10 chars) + percentage
  if [[ -n "$s_ctx" ]]; then
    local pct=${s_ctx%.*}
    (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
    local filled=$(( pct / 10 )) empty=$(( 10 - filled ))
    local ctx_color="green"
    (( pct >= 70 )) && ctx_color="yellow"
    (( pct >= 90 )) && ctx_color="red"
    local ctx_bar=""
    (( filled > 0 )) && ctx_bar+="${(l:$filled::█:)}"
    (( empty > 0 )) && ctx_bar+="%F{8}${(l:$empty::░:)}%f"
    bar+=" %F{${ctx_color}}${ctx_bar}%f %F{8}${pct}%%%f"
  fi

  # Cost — format raw float to 2 decimal places
  if [[ -n "$s_cost" && "$s_cost" != "0" ]]; then
    local cost_fmt
    printf -v cost_fmt '%.2f' "$s_cost" 2>/dev/null || cost_fmt="$s_cost"
    bar+="${SEP}%F{cyan}%{\$%}${cost_fmt}%f"
  fi

  # Rate limits with reset countdown
  if [[ -n "$s_5h" ]]; then
    local rl_color="cyan" rl_int=${s_5h%.*}
    (( rl_int >= 70 )) && rl_color="yellow"
    (( rl_int >= 90 )) && rl_color="red"
    bar+="${SEP}%F{${rl_color}}5h:${rl_int}%%%f"
    # Burn-rate ETA — show when present, > 0, and < 120min
    if [[ -n "$s_burn_eta" && "$s_burn_eta" != "" ]] && (( s_burn_eta > 0 && s_burn_eta < 120 )); then
      local eta_color="8"
      (( s_burn_eta < 10 )) && eta_color="red"
      (( s_burn_eta >= 10 && s_burn_eta < 30 )) && eta_color="yellow"
      bar+=" %F{${eta_color}}~${s_burn_eta}min%f"
    fi
    # Reset countdown
    if [[ -n "$s_r5h" && "$s_r5h" != "0" ]]; then
      local remaining=$(( s_r5h - EPOCHSECONDS ))
      if (( remaining > 0 )); then
        bar+=" %F{8}reset $(( remaining / 60 ))min%f"
      fi
    fi
  fi
  if [[ -n "$s_7d" ]]; then
    local rl7_color="cyan" rl7_int=${s_7d%.*}
    (( rl7_int >= 70 )) && rl7_color="yellow"
    (( rl7_int >= 90 )) && rl7_color="red"
    bar+=" %F{${rl7_color}}7d:${rl7_int}%%%f"
  fi

  # Set session bar as first line of PROMPT — avoids printing to stdout
  # (which would make it appear between command output and the next prompt)
  _CLAUDII_LAST_SESSION_BAR="$bar"
  PROMPT="${bar}"$'\n'"${_CLAUDII_USER_PROMPT}"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claudii_statusline
