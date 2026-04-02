# claudii statusline — RPROMPT with per-model health + session dashboard
# shellcheck source=lib/visual.sh
source "${CLAUDII_HOME}/lib/visual.sh"

# _CLAUDII_USER_PROMPT is set by claudii.plugin.zsh before sourcing libs —
# do not set it here, that would overwrite the value captured before config.zsh/functions.zsh ran.

# 0 = no session dashboard until a real command runs (preexec sets it to 1)
typeset -gi _CLAUDII_CMD_RAN=0
# Literal dollar sign for safe PROMPT_SUBST embedding — $0 would be eaten by PROMPT_SUBST
typeset -g _CLAUDII_DOLLAR='$'
# Set to 1 by se/si/sessions commands — suppresses session dashboard for that cycle
typeset -gi _CLAUDII_SHOWED_SESSIONS=0
typeset -g _CLAUDII_LAST_CMD=""
# PID of the last background status-fetch job — used to skip redundant spawns
typeset -g _CLAUDII_STATUS_PID=""
# Set while _claudii_statusline is executing — reentrancy guard
typeset -g _CLAUDII_PRECMD_RUNNING=""

function _claudii_preexec {
  _CLAUDII_CMD_RAN=1
  _CLAUDII_LAST_CMD="${1:-}"
}

function TRAPWINCH {
  _CLAUDII_CMD_RAN=1
  zle reset-prompt 2>/dev/null
}

function _claudii_statusline {
  # Reentrancy guard — skip if already running
  [[ -n "${_CLAUDII_PRECMD_RUNNING:-}" ]] && return
  typeset -g _CLAUDII_PRECMD_RUNNING=1
  local _t=$EPOCHREALTIME
  _claudii_statusline_render
  local _el=$(( int(($EPOCHREALTIME - _t) * 1000000) ))
  _CLAUDII_METRICS[precmd.last_us]=$_el
  _CLAUDII_METRICS[precmd.calls]=$(( ${_CLAUDII_METRICS[precmd.calls]:-0} + 1 ))
  _CLAUDII_METRICS[precmd.total_us]=$(( ${_CLAUDII_METRICS[precmd.total_us]:-0} + _el ))
  _claudii_log debug "precmd: $(_claudii_fmt_us $_el)"
  typeset -g _CLAUDII_PRECMD_RUNNING=
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
    # Skip spawn if a previous fetch is still running
    kill -0 "${_CLAUDII_STATUS_PID:-}" 2>/dev/null || {
      "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null &
      typeset -g _CLAUDII_STATUS_PID=$!
      disown "$_CLAUDII_STATUS_PID" 2>/dev/null
    }
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
    # Skip spawn if a previous fetch is still running
    kill -0 "${_CLAUDII_STATUS_PID:-}" 2>/dev/null || {
      "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null &
      typeset -g _CLAUDII_STATUS_PID=$!
      disown "$_CLAUDII_STATUS_PID" 2>/dev/null
    }
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

  # Session dashboard — session lines prepended to PROMPT (conditional: only after real commands)
  _claudii_session_dashboard
}

typeset -ga _CLAUDII_SDASH_MODELS _CLAUDII_SDASH_CTXS _CLAUDII_SDASH_COSTS
typeset -ga _CLAUDII_SDASH_5HS _CLAUDII_SDASH_R5HS
typeset -gi _CLAUDII_SDASH_COUNT=0

# Iterates session cache files, populates _CLAUDII_DASH_* arrays.
# Returns 0 if active sessions found, 1 if none.
function _claudii_collect_sessions {
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _CLAUDII_SDASH_MODELS=() _CLAUDII_SDASH_CTXS=() _CLAUDII_SDASH_COSTS=()
  _CLAUDII_SDASH_5HS=() _CLAUDII_SDASH_R5HS=()
  _CLAUDII_SDASH_COUNT=0

  local -A _sfst
  local _sf_mt _sf_age sc s_ppid
  local s_model s_ctx s_cost s_5h s_r5h _best_r5h=""
  for _sf in "$_cache_base"/session-*(N); do
    _sf_mt=0
    if (( _CLAUDII_HAVE_ZSTAT )); then
      _sfst=()
      zstat -H _sfst "$_sf" 2>/dev/null && _sf_mt=${_sfst[mtime]:-0}
    else
      _sf_mt=$(stat -c%Y "$_sf" 2>/dev/null || stat -f%m "$_sf" 2>/dev/null || echo 0)
    fi
    _sf_age=$(( ${EPOCHSECONDS:-$(date +%s)} - _sf_mt ))

    sc=""
    { sc=$(<"$_sf"); } 2>/dev/null
    [[ -z "$sc" ]] && continue

    s_ppid=""
    [[ $'\n'"$sc" == *$'\n'ppid=* ]] && s_ppid="${${sc#*ppid=}%%$'\n'*}"
    if [[ "$s_ppid" =~ ^[0-9]+$ && "$s_ppid" != "0" ]]; then
      # Authoritative liveness check — show even if file is old (long-running task).
      # 24h cap guards against PID recycling (OS reuses PIDs of long-dead processes).
      (( _sf_age >= 86400 )) && continue
      kill -0 "$s_ppid" 2>/dev/null || continue
    else
      # No ppid → fall back to age-based filter (< 300s)
      (( _sf_age >= 300 )) && continue
    fi

    s_model="" s_ctx="" s_cost="" s_5h="" s_r5h=""
    [[ $'\n'"$sc" == *$'\n'model=* ]]    && s_model="${${sc#*$'\n'model=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'ctx_pct=* ]]  && s_ctx="${${sc#*$'\n'ctx_pct=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'cost=* ]]     && s_cost="${${sc#*$'\n'cost=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_5h=* ]]  && s_5h="${${sc#*$'\n'rate_5h=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'reset_5h=* ]] && s_r5h="${${sc#*$'\n'reset_5h=}%%$'\n'*}"
    [[ -z "$s_model" ]] && continue

    # Fallback: if cost is missing or zero, look up last known cost in history.tsv
    if [[ -z "$s_cost" || "$s_cost" == "0" ]]; then
      local s_sid=""
      [[ $'\n'"$sc" == *$'\n'session_id=* ]] && s_sid="${${sc#*$'\n'session_id=}%%$'\n'*}"
      if [[ -n "$s_sid" ]]; then
        local _hist="$_cache_base/history.tsv"
        if [[ -f "$_hist" ]]; then
          # Find last non-zero cost for this session_id (col 6 = session_id, col 3 = cost)
          local _hcost
          _hcost=$(awk -F'\t' -v sid="$s_sid" '
            $6==sid && $3!="" && $3+0 > 0 { c=$3 }
            END { if (c!="") print c }
          ' "$_hist" 2>/dev/null)
          [[ -n "$_hcost" ]] && s_cost="$_hcost"
        fi
      fi
    fi

    _CLAUDII_SDASH_MODELS+=("$s_model")
    _CLAUDII_SDASH_CTXS+=("$s_ctx")
    _CLAUDII_SDASH_COSTS+=("$s_cost")
    _CLAUDII_SDASH_5HS+=("$s_5h")
    _CLAUDII_SDASH_R5HS+=("$s_r5h")
    [[ -n "$s_r5h" && "$s_r5h" =~ ^[0-9]+$ ]] && _best_r5h="$s_r5h"
    (( ++_CLAUDII_SDASH_COUNT ))
  done
  # Backfill missing reset_5h — all sessions share the same account reset time
  if [[ -n "$_best_r5h" ]]; then
    local _bi
    for (( _bi=1; _bi<=${#_CLAUDII_SDASH_R5HS}; _bi++ )); do
      [[ -z "${_CLAUDII_SDASH_R5HS[$_bi]}" ]] && _CLAUDII_SDASH_R5HS[$_bi]="$_best_r5h"
    done
  fi
  (( _CLAUDII_SDASH_COUNT > 0 ))
}

function _claudii_session_dashboard {
  local _dash_mode="${_CLAUDII_CFG_CACHE[session-dashboard.enabled]:-${_CLAUDII_DEF_CACHE[session-dashboard.enabled]:-${_CLAUDII_CFG_CACHE[dashboard.enabled]:-${_CLAUDII_DEF_CACHE[dashboard.enabled]:-auto}}}}"
  # Any value other than "off" enables the dashboard
  if [[ "$_dash_mode" == "off" ]]; then
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi
  if (( _CLAUDII_CMD_RAN == 0 )); then
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi
  _CLAUDII_CMD_RAN=0

  # Show session dashboard only after claudii commands — skip after ls, git, etc.
  [[ "${_CLAUDII_LAST_CMD}" != claudii* ]] && {
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  }
  # Skip if se/si/sessions already showed session info this cycle
  if (( _CLAUDII_SHOWED_SESSIONS )); then
    _CLAUDII_SHOWED_SESSIONS=0
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  _claudii_collect_sessions
  if (( _CLAUDII_SDASH_COUNT == 0 )); then
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  # Declare all loop-local variables before the loop (avoids zsh local-in-loop stdout leak)
  local _dash_lines="" _now=${EPOCHSECONDS:-$(date +%s)}
  local _di _line _ctx _cost _cf _r5h _r5h_int _r5h_clr _rst _rem
  for (( _di=1; _di<=_CLAUDII_SDASH_COUNT; _di++ )); do
    _line="  %F{8}${_CLAUDII_SDASH_MODELS[$_di]}"
    _ctx="${_CLAUDII_SDASH_CTXS[$_di]%.*}"
    [[ -n "$_ctx" ]] && _line+="  ${_ctx}%%"
    _cost="${_CLAUDII_SDASH_COSTS[$_di]}"
    if [[ -n "$_cost" && "$_cost" != "0" && "$_cost" != "null" ]]; then
      _cf=$(printf '%.2f' "$_cost" 2>/dev/null) && _line+="  \${_CLAUDII_DOLLAR}${_cf}"
    fi
    _r5h="${_CLAUDII_SDASH_5HS[$_di]}"
    if [[ -n "$_r5h" && "$_r5h" != "null" ]]; then
      _r5h_int=${_r5h%.*}
      if (( _r5h_int >= 80 )); then _r5h_clr="%F{red}"
      elif (( _r5h_int >= 50 )); then _r5h_clr="%F{yellow}"
      else _r5h_clr="%F{green}"
      fi
      _line+="%f  ${_r5h_clr}5h:${_r5h_int}%%"
      _rst="${_CLAUDII_SDASH_R5HS[$_di]}"
      if [[ -n "$_rst" && "$_rst" =~ ^[0-9]+$ ]]; then
        _rem=$(( _rst - _now ))
        (( _rem > 0 )) && _line+=" ↺$(( _rem / 60 ))m"
      fi
    fi
    _line+="%f"
    _dash_lines+="${_line}"$'\n'
  done

  PROMPT="${_dash_lines}${_CLAUDII_USER_PROMPT}"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claudii_statusline
add-zsh-hook preexec _claudii_preexec
