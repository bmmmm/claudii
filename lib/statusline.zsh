# claudii statusline — RPROMPT with per-model health + dashboard
# shellcheck source=lib/visual.sh
source "${CLAUDII_HOME}/lib/visual.sh"

# Capture the user's original PROMPT once at load time.
# Every precmd cycle restores PROMPT to this, then prepends dashboard lines.
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

  # Dashboard — multi-session lines prepended to PROMPT
  _claudii_dashboard
}

typeset -g _CLAUDII_LAST_DASHBOARD=""

function _claudii_dashboard {
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local dash_mode="${_CLAUDII_CFG_CACHE[dashboard.enabled]:-${_CLAUDII_DEF_CACHE[dashboard.enabled]:-auto}}"

  # "off" = never show dashboard
  [[ "$dash_mode" == "off" ]] && { _CLAUDII_LAST_DASHBOARD=""; return; }

  # Collect all active session files (PID alive + mtime < 300s)
  local -a active_files active_contents active_pids
  local -a active_models active_ctxs active_costs active_5hs active_7ds
  local -a active_r5hs active_r7ds active_worktrees active_agents
  local -a active_burn_etas active_cache_pcts active_7d_starts
  local active_count=0
  local total_cost=0

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

    # Check if Claude process is still running via ppid
    local s_ppid=""
    [[ $'\n'"$sc" == *$'\n'ppid=* ]] && s_ppid="${${sc#*ppid=}%%$'\n'*}"
    if [[ -n "$s_ppid" && "$s_ppid" != "0" && "$s_ppid" != "" ]]; then
      kill -0 "$s_ppid" 2>/dev/null || continue
    fi

    # Parse fields
    local s_model="" s_ctx="" s_cost="" s_5h="" s_7d="" s_r5h="" s_r7d=""
    local s_worktree="" s_agent="" s_burn_eta="" s_cache_pct="" s_7d_start=""
    [[ $'\n'"$sc" == *$'\n'model=* ]]      && s_model="${${sc#*model=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'ctx_pct=* ]]    && s_ctx="${${sc#*ctx_pct=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'cost=* ]]       && s_cost="${${sc#*cost=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_5h=* ]]    && s_5h="${${sc#*rate_5h=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_7d=* ]]    && s_7d="${${sc#*rate_7d=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'reset_5h=* ]]   && s_r5h="${${sc#*reset_5h=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'reset_7d=* ]]   && s_r7d="${${sc#*reset_7d=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'worktree=* ]]   && s_worktree="${${sc#*worktree=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'agent=* ]]      && s_agent="${${sc#*agent=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'burn_eta=* ]]   && s_burn_eta="${${sc#*burn_eta=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'cache_pct=* ]]  && s_cache_pct="${${sc#*cache_pct=}%%$'\n'*}"
    [[ $'\n'"$sc" == *$'\n'rate_7d_start=* ]] && s_7d_start="${${sc#*rate_7d_start=}%%$'\n'*}"

    [[ -z "$s_model" ]] && continue

    active_models+=("$s_model")
    active_ctxs+=("$s_ctx")
    active_costs+=("$s_cost")
    active_5hs+=("$s_5h")
    active_7ds+=("$s_7d")
    active_r5hs+=("$s_r5h")
    active_r7ds+=("$s_r7d")
    active_worktrees+=("$s_worktree")
    active_agents+=("$s_agent")
    active_burn_etas+=("$s_burn_eta")
    active_cache_pcts+=("$s_cache_pct")
    active_7d_starts+=("$s_7d_start")

    if [[ -n "$s_cost" && "$s_cost" != "0" ]]; then
      # Simple integer addition for cost (truncated to cents)
      local cost_cents=${s_cost%.*}
      (( total_cost += ${cost_cents:-0} ))
    fi
    (( active_count++ ))
  done

  # "auto" mode: only show when sessions are active
  if [[ "$dash_mode" == "auto" && active_count -eq 0 ]]; then
    _CLAUDII_LAST_DASHBOARD=""
    return
  fi

  # "true" mode but no sessions: show nothing (no empty dashboard)
  if (( active_count == 0 )); then
    _CLAUDII_LAST_DASHBOARD=""
    return
  fi

  # Build dashboard lines
  local dash_lines=""
  local SEP="%F{8} │%f "
  local _cost_fmt _cost_fmt_s

  # ── Global line ──
  # Aggregate: use the freshest (first) session's rate limits as representative
  local g_5h="${active_5hs[1]}" g_7d="${active_7ds[1]}" g_r5h="${active_r5hs[1]}"
  local g_burn_eta="${active_burn_etas[1]}" g_7d_start="${active_7d_starts[1]}"

  local global_line=""
  if [[ -n "$g_5h" && "$g_5h" != "null" ]]; then
    local rl_color="cyan" rl_int=${g_5h%.*}
    (( rl_int >= 70 )) && rl_color="yellow"
    (( rl_int >= 90 )) && rl_color="red"
    global_line+="%F{${rl_color}}5h:${rl_int}%%%f"

    # Reset countdown
    if [[ -n "$g_r5h" && "$g_r5h" != "0" ]]; then
      local remaining=$(( g_r5h - EPOCHSECONDS ))
      if (( remaining > 0 )); then
        global_line+=" %F{8}reset $(( remaining / 60 ))min%f"
      fi
    fi
  fi

  if [[ -n "$g_7d" && "$g_7d" != "null" ]]; then
    [[ -n "$global_line" ]] && global_line+="${SEP}"
    local rl7_color="cyan" rl7_int=${g_7d%.*}
    (( rl7_int >= 70 )) && rl7_color="yellow"
    (( rl7_int >= 90 )) && rl7_color="red"
    global_line+="%F{${rl7_color}}7d:${rl7_int}%%%f"

    # 7d delta
    if [[ -n "$g_7d_start" && "$g_7d_start" != "" ]]; then
      local delta_7d=$(( ${g_7d%.*} - ${g_7d_start%.*} ))
      (( delta_7d > 0 )) && global_line+=" %F{8}(+${delta_7d}%%)%f"
    fi
  fi

  # Today cost + session count
  if (( active_count > 0 )); then
    # Calculate total cost from active sessions (float sum)
    local today_cost="0"
    local _ci
    for (( _ci=1; _ci<=active_count; _ci++ )); do
      if [[ -n "${active_costs[$_ci]}" && "${active_costs[$_ci]}" != "0" ]]; then
        _cost_fmt=$(printf '%.2f' "${active_costs[$_ci]}" 2>/dev/null) || _cost_fmt="0.00"
        # Use awk for float addition — no bc dependency
        today_cost=$(awk "BEGIN { printf \"%.2f\", $today_cost + $_cost_fmt }" 2>/dev/null || echo "$today_cost")
      fi
    done
    [[ -n "$global_line" ]] && global_line+="${SEP}"
    global_line+="%F{cyan}%{\$%}${today_cost}%f %F{8}today (${active_count} session"
    (( active_count != 1 )) && global_line+="s"
    global_line+=")%f"
  fi

  [[ -n "$global_line" ]] && dash_lines="${global_line}"$'\n'

  # ── Session lines ──
  local _si
  for (( _si=1; _si<=active_count; _si++ )); do
    local s_line=""

    # Skip sessions with no context percentage (stale/incomplete)
    [[ -z "${active_ctxs[$_si]}" ]] && continue

    # Model (bold)
    s_line+="%B${active_models[$_si]}%b"

    # Context bar (8 blocks) + percentage
    local _pct=${active_ctxs[$_si]%.*}
    (( _pct < 0 )) && _pct=0; (( _pct > 100 )) && _pct=100
    local _filled=$(( _pct * 8 / 100 )) _empty=$(( 8 - _filled ))
    local _ctx_color="green"
    (( _pct >= 70 )) && _ctx_color="yellow"
    (( _pct >= 90 )) && _ctx_color="red"
    local _ctx_bar=""
    (( _filled > 0 )) && _ctx_bar+="${(l:$_filled::█:)}"
    (( _empty > 0 )) && _ctx_bar+="%F{8}${(l:$_empty::░:)}%f"
    s_line+=" %F{${_ctx_color}}${_ctx_bar}%f %F{8}${_pct}%%%f"

    # Cost
    if [[ -n "${active_costs[$_si]}" && "${active_costs[$_si]}" != "0" ]]; then
      _cost_fmt_s=$(printf '%.2f' "${active_costs[$_si]}" 2>/dev/null) || _cost_fmt_s="${active_costs[$_si]}"
      s_line+="${SEP}%F{cyan}%{\$%}${_cost_fmt_s}%f"
    fi

    # Cache hit ratio
    if [[ -n "${active_cache_pcts[$_si]}" && "${active_cache_pcts[$_si]}" != "0" && "${active_cache_pcts[$_si]}" != "" ]]; then
      s_line+="${SEP}%F{8}⚡${active_cache_pcts[$_si]}%%%f"
    fi

    # Worktree / agent context
    if [[ -n "${active_worktrees[$_si]}" ]]; then
      s_line+="${SEP}%F{8}[wt:${active_worktrees[$_si]}]%f"
    elif [[ -n "${active_agents[$_si]}" ]]; then
      s_line+="${SEP}%F{8}[agent:${active_agents[$_si]}]%f"
    fi

    dash_lines+="${s_line}"$'\n'
  done

  # Deduplicate — only update PROMPT if dashboard changed
  [[ "$dash_lines" == "$_CLAUDII_LAST_DASHBOARD" ]] && {
    # Still need to prepend cached dashboard to PROMPT
    if [[ -n "$_CLAUDII_LAST_DASHBOARD" ]]; then
      PROMPT="${_CLAUDII_LAST_DASHBOARD}${_CLAUDII_USER_PROMPT}"
    fi
    return
  }
  _CLAUDII_LAST_DASHBOARD="$dash_lines"

  # Prepend dashboard to PROMPT
  if [[ -n "$dash_lines" ]]; then
    PROMPT="${dash_lines}${_CLAUDII_USER_PROMPT}"
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claudii_statusline
