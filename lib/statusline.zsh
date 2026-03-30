# claudii statusline — RPROMPT with per-model health + dashboard (OSC2 title)
# shellcheck source=lib/visual.sh
source "${CLAUDII_HOME}/lib/visual.sh"

# Capture the user's original PROMPT once at load time.
# Every precmd cycle restores PROMPT to this value — no above-prompt embedding.
typeset -g _CLAUDII_USER_PROMPT="${PROMPT}"

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
  # Restore PROMPT to the user's original every cycle
  PROMPT="${_CLAUDII_USER_PROMPT}"

  # Single cache-load call — fast mtime check, jq only on config change
  _claudii_cache_load
  [[ "${_CLAUDII_CFG_CACHE[statusline.enabled]:-${_CLAUDII_DEF_CACHE[statusline.enabled]:-true}}" != "true" ]] && { RPROMPT=""; return; }

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

  # Dashboard — writes session info to OSC2 window title, no PROMPT modification
  _claudii_dashboard
}

typeset -ga _CLAUDII_DASH_MODELS _CLAUDII_DASH_CTXS _CLAUDII_DASH_COSTS
typeset -ga _CLAUDII_DASH_5HS _CLAUDII_DASH_7DS _CLAUDII_DASH_R5HS _CLAUDII_DASH_R7DS
typeset -ga _CLAUDII_DASH_WORKTREES _CLAUDII_DASH_AGENTS _CLAUDII_DASH_BURN_ETAS
typeset -ga _CLAUDII_DASH_CACHE_PCTS _CLAUDII_DASH_7D_STARTS
typeset -gi _CLAUDII_DASH_COUNT=0
typeset -g _CLAUDII_LAST_TITLE=""   # change detection cache
typeset -g _CLAUDII_TITLE_BUF=""    # build buffer, avoids subshell/nameref

# Iterates session cache files, populates _CLAUDII_DASH_* arrays.
# Returns 0 if active sessions found, 1 if none.
function _claudii_collect_sessions {
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _CLAUDII_DASH_MODELS=() _CLAUDII_DASH_CTXS=() _CLAUDII_DASH_COSTS=()
  _CLAUDII_DASH_5HS=() _CLAUDII_DASH_7DS=() _CLAUDII_DASH_R5HS=() _CLAUDII_DASH_R7DS=()
  _CLAUDII_DASH_WORKTREES=() _CLAUDII_DASH_AGENTS=() _CLAUDII_DASH_BURN_ETAS=()
  _CLAUDII_DASH_CACHE_PCTS=() _CLAUDII_DASH_7D_STARTS=()
  _CLAUDII_DASH_COUNT=0

  for _sf in "$_cache_base"/session-*(N); do
    local _sf_mt=0
    if (( _CLAUDII_HAVE_ZSTAT )); then
      local -A _sfst
      zstat -H _sfst "$_sf" 2>/dev/null && _sf_mt=${_sfst[mtime]:-0}
    else
      _sf_mt=$(stat -c%Y "$_sf" 2>/dev/null || stat -f%m "$_sf" 2>/dev/null || echo 0)
    fi
    local _sf_age=$(( ${EPOCHSECONDS:-$(date +%s)} - _sf_mt ))
    (( _sf_age >= 300 )) && continue

    local sc=""
    { sc=$(<"$_sf"); } 2>/dev/null
    [[ -z "$sc" ]] && continue

    local s_ppid=""
    [[ $'\n'"$sc" == *$'\n'ppid=* ]] && s_ppid="${${sc#*ppid=}%%$'\n'*}"
    if [[ -n "$s_ppid" && "$s_ppid" != "0" && "$s_ppid" != "" ]]; then
      kill -0 "$s_ppid" 2>/dev/null || continue
    fi

    local s_model="" s_ctx="" s_cost="" s_5h="" s_7d="" s_r5h="" s_r7d=""
    local s_worktree="" s_agent="" s_burn_eta="" s_cache_pct="" s_7d_start=""
    [[ $'\n'"$sc" == *$'\n'model=* ]]         && s_model="${${sc#*model=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'ctx_pct=* ]]       && s_ctx="${${sc#*ctx_pct=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'cost=* ]]          && s_cost="${${sc#*cost=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_5h=* ]]       && s_5h="${${sc#*rate_5h=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_7d=* ]]       && s_7d="${${sc#*rate_7d=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'reset_5h=* ]]      && s_r5h="${${sc#*reset_5h=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'reset_7d=* ]]      && s_r7d="${${sc#*reset_7d=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'worktree=* ]]      && s_worktree="${${sc#*worktree=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'agent=* ]]         && s_agent="${${sc#*agent=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'burn_eta=* ]]      && s_burn_eta="${${sc#*burn_eta=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'cache_pct=* ]]     && s_cache_pct="${${sc#*cache_pct=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_7d_start=* ]] && s_7d_start="${${sc#*rate_7d_start=}%%$'\n'*}"
    [[ -z "$s_model" ]] && continue

    _CLAUDII_DASH_MODELS+=("$s_model");     _CLAUDII_DASH_CTXS+=("$s_ctx")
    _CLAUDII_DASH_COSTS+=("$s_cost");       _CLAUDII_DASH_5HS+=("$s_5h")
    _CLAUDII_DASH_7DS+=("$s_7d");           _CLAUDII_DASH_R5HS+=("$s_r5h")
    _CLAUDII_DASH_R7DS+=("$s_r7d");         _CLAUDII_DASH_WORKTREES+=("$s_worktree")
    _CLAUDII_DASH_AGENTS+=("$s_agent");     _CLAUDII_DASH_BURN_ETAS+=("$s_burn_eta")
    _CLAUDII_DASH_CACHE_PCTS+=("$s_cache_pct"); _CLAUDII_DASH_7D_STARTS+=("$s_7d_start")
    (( _CLAUDII_DASH_COUNT++ ))
  done
  (( _CLAUDII_DASH_COUNT > 0 ))
}

# Builds plain-text title (no ANSI, no %F{} codes) from _CLAUDII_DASH_* arrays.
# Stores result in _CLAUDII_TITLE_BUF.
function _claudii_build_title {
  _CLAUDII_TITLE_BUF=""
  local _now="${EPOCHSECONDS:-$(date +%s)}"

  if (( _CLAUDII_DASH_COUNT == 1 )); then
    # Single session format: {model} [wt:{wt}|agent:{ag}] · {ctx}% · ${cost} ⚡{cache}%
    local _t_model="${_CLAUDII_DASH_MODELS[1]}"
    local _t_ctx="${_CLAUDII_DASH_CTXS[1]}"
    local _t_cost="${_CLAUDII_DASH_COSTS[1]}"
    local _t_cache="${_CLAUDII_DASH_CACHE_PCTS[1]}"
    local _t_wt="${_CLAUDII_DASH_WORKTREES[1]}"
    local _t_ag="${_CLAUDII_DASH_AGENTS[1]}"

    _CLAUDII_TITLE_BUF="${_t_model}"

    # Optional [wt:...|agent:...] tag
    if [[ -n "$_t_wt" ]]; then
      _CLAUDII_TITLE_BUF+=" [wt:${_t_wt}]"
    elif [[ -n "$_t_ag" ]]; then
      _CLAUDII_TITLE_BUF+=" [agent:${_t_ag}]"
    fi

    # ctx%
    if [[ -n "$_t_ctx" && "$_t_ctx" != "null" ]]; then
      local _t_ctx_int=${_t_ctx%.*}
      _CLAUDII_TITLE_BUF+=" · ${_t_ctx_int}%"
    fi

    # $cost
    if [[ -n "$_t_cost" && "$_t_cost" != "null" && "$_t_cost" != "0" ]]; then
      local _t_cost_fmt
      _t_cost_fmt=$(printf '%.2f' "$_t_cost" 2>/dev/null) || _t_cost_fmt="$_t_cost"
      _CLAUDII_TITLE_BUF+=" · \$${_t_cost_fmt}"
    fi

    # ⚡cache%
    if [[ -n "$_t_cache" && "$_t_cache" != "null" && "$_t_cache" != "0" && "$_t_cache" != "" ]]; then
      local _t_cache_int=${_t_cache%.*}
      _CLAUDII_TITLE_BUF+=" ⚡${_t_cache_int}%"
    fi

  else
    # Multi-session format: {N} sessions [{m1},{m2},...] · ${total_cost}
    local _t_total_cost="0"
    local _t_models_list="" _mi
    local _c_fmt=""  # declared outside loop — re-declaring local inside a loop leaks assignment to stdout in zsh
    for (( _mi=1; _mi<=_CLAUDII_DASH_COUNT; _mi++ )); do
      [[ -n "$_t_models_list" ]] && _t_models_list+=","
      _t_models_list+="${_CLAUDII_DASH_MODELS[$_mi]}"
      if [[ -n "${_CLAUDII_DASH_COSTS[$_mi]}" && "${_CLAUDII_DASH_COSTS[$_mi]}" != "null" && "${_CLAUDII_DASH_COSTS[$_mi]}" != "0" ]]; then
        _c_fmt=$(printf '%.2f' "${_CLAUDII_DASH_COSTS[$_mi]}" 2>/dev/null) || _c_fmt="0.00"
        _t_total_cost=$(awk "BEGIN { printf \"%.2f\", ${_t_total_cost} + ${_c_fmt} }" 2>/dev/null || echo "$_t_total_cost")
      fi
    done
    _CLAUDII_TITLE_BUF="${_CLAUDII_DASH_COUNT} sessions [${_t_models_list}] · \$${_t_total_cost}"
  fi

  # Rate limits (appended for both, from first session = account-level)
  local _gr5h="${_CLAUDII_DASH_5HS[1]}"
  local _gr7d="${_CLAUDII_DASH_7DS[1]}"
  local _gr5h_reset="${_CLAUDII_DASH_R5HS[1]}"
  local _g7ds="${_CLAUDII_DASH_7D_STARTS[1]}"

  if [[ -n "$_gr5h" && "$_gr5h" != "null" && "$_gr5h" != "" ]]; then
    local _rl5h_int=${_gr5h%.*}
    _CLAUDII_TITLE_BUF+=" · 5h:${_rl5h_int}%"
    if [[ -n "$_gr5h_reset" && "$_gr5h_reset" != "null" && "$_gr5h_reset" != "0" && "$_gr5h_reset" != "" ]]; then
      if [[ "$_gr5h_reset" =~ ^[0-9]+$ ]]; then
        local _rem=$(( _gr5h_reset - _now ))
        if (( _rem > 0 )); then
          _CLAUDII_TITLE_BUF+=" ↺$(( _rem / 60 ))min"
        fi
      fi
    fi
  fi

  if [[ -n "$_gr7d" && "$_gr7d" != "null" && "$_gr7d" != "" ]]; then
    local _rl7d_int=${_gr7d%.*}
    _CLAUDII_TITLE_BUF+=" · 7d:${_rl7d_int}%"
    if [[ -n "$_g7ds" && "$_g7ds" != "null" && "$_g7ds" != "" ]]; then
      if [[ "$_g7ds" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local _delta7d=$(( ${_gr7d%.*} - ${_g7ds%.*} ))
        (( _delta7d > 0 )) && _CLAUDII_TITLE_BUF+=" (+${_delta7d}%)"
      fi
    fi
  fi
}

function _claudii_dashboard {
  local _dash_mode="${_CLAUDII_CFG_CACHE[dashboard.enabled]:-${_CLAUDII_DEF_CACHE[dashboard.enabled]:-auto}}"

  if [[ "$_dash_mode" == "off" ]]; then
    # Only clear title if we previously set one
    if [[ -n "$_CLAUDII_LAST_TITLE" ]]; then
      [[ -t 1 ]] && printf '\033]2;\007'
      _CLAUDII_LAST_TITLE=""
    fi
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  _claudii_collect_sessions
  local _active=$_CLAUDII_DASH_COUNT

  if [[ "$_dash_mode" == "auto" && _active -eq 0 ]] || (( _active == 0 )); then
    if [[ -n "$_CLAUDII_LAST_TITLE" ]]; then
      [[ -t 1 ]] && printf '\033]2;\007'
      _CLAUDII_LAST_TITLE=""
    fi
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  _claudii_build_title  # populates _CLAUDII_TITLE_BUF

  if [[ "$_CLAUDII_TITLE_BUF" != "$_CLAUDII_LAST_TITLE" ]]; then
    [[ -t 1 ]] && printf '\033]2;%s\007' "$_CLAUDII_TITLE_BUF"
    _CLAUDII_LAST_TITLE="$_CLAUDII_TITLE_BUF"
  fi

  # No PROMPT modification — title only
  PROMPT="${_CLAUDII_USER_PROMPT}"
}

# On terminal resize: redraw the prompt immediately if ZLE is active.
# No width cache needed for title rendering.
function TRAPWINCH {
  zle reset-prompt 2>/dev/null
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claudii_statusline
