# claudii statusline — RPROMPT with per-model health + dashboard
# shellcheck source=lib/visual.sh
source "${CLAUDII_HOME}/lib/visual.sh"

# Capture the user's original PROMPT once at load time.
# Every precmd cycle restores PROMPT to this, then appends dashboard lines below it.
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
  # On empty Enter (no command ran): cursor is on the prompt line itself (cursor-up in
  # PROMPT already moved it back). Erase N+1 lines down to clear the old dashboard area
  # before rendering fresh. Only needed while dashboard was active last cycle.
  if (( _CLAUDII_CMD_RAN == 0 && _CLAUDII_LAST_DASH_LINE_COUNT > 0 )); then
    printf '\e[J'
  fi
  _CLAUDII_CMD_RAN=0

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

typeset -ga _CLAUDII_DASH_MODELS _CLAUDII_DASH_CTXS _CLAUDII_DASH_COSTS
typeset -ga _CLAUDII_DASH_5HS _CLAUDII_DASH_7DS _CLAUDII_DASH_R5HS _CLAUDII_DASH_R7DS
typeset -ga _CLAUDII_DASH_WORKTREES _CLAUDII_DASH_AGENTS _CLAUDII_DASH_BURN_ETAS
typeset -ga _CLAUDII_DASH_CACHE_PCTS _CLAUDII_DASH_7D_STARTS
typeset -gi _CLAUDII_DASH_COUNT=0
typeset -g _CLAUDII_DASH_GLOBAL_LINE="" _CLAUDII_DASH_SESSION_LINES=""
typeset -g _CLAUDII_LAST_DASHBOARD="" _CLAUDII_LAST_DASH_PADDED=""
typeset -gi _CLAUDII_LAST_DASH_COLS=0
typeset -gi _CLAUDII_LAST_DASH_LINE_COUNT=0
typeset -gi _CLAUDII_CMD_RAN=0

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

# Builds the aggregate rate/cost header into _CLAUDII_DASH_GLOBAL_LINE.
function _claudii_render_global_line {
  local SEP="%F{8} │%f "
  _CLAUDII_DASH_GLOBAL_LINE=""
  local g_5h="${_CLAUDII_DASH_5HS[1]}"  g_7d="${_CLAUDII_DASH_7DS[1]}"
  local g_r5h="${_CLAUDII_DASH_R5HS[1]}" g_7d_start="${_CLAUDII_DASH_7D_STARTS[1]}"

  if [[ -n "$g_5h" && "$g_5h" != "null" ]]; then
    local rl_color="cyan" rl_int=${g_5h%.*}
    (( rl_int >= 70 )) && rl_color="yellow"
    (( rl_int >= 90 )) && rl_color="red"
    _CLAUDII_DASH_GLOBAL_LINE+="%F{${rl_color}}5h:${rl_int}%%%f"
    if [[ -n "$g_r5h" && "$g_r5h" != "0" ]]; then
      local remaining=$(( g_r5h - EPOCHSECONDS ))
      (( remaining > 0 )) && _CLAUDII_DASH_GLOBAL_LINE+=" %F{8}reset $(( remaining / 60 ))min%f"
    fi
  fi

  if [[ -n "$g_7d" && "$g_7d" != "null" ]]; then
    [[ -n "$_CLAUDII_DASH_GLOBAL_LINE" ]] && _CLAUDII_DASH_GLOBAL_LINE+="${SEP}"
    local rl7_color="cyan" rl7_int=${g_7d%.*}
    (( rl7_int >= 70 )) && rl7_color="yellow"
    (( rl7_int >= 90 )) && rl7_color="red"
    _CLAUDII_DASH_GLOBAL_LINE+="%F{${rl7_color}}7d:${rl7_int}%%%f"
    if [[ -n "$g_7d_start" && "$g_7d_start" != "" ]]; then
      local delta_7d=$(( ${g_7d%.*} - ${g_7d_start%.*} ))
      (( delta_7d > 0 )) && _CLAUDII_DASH_GLOBAL_LINE+=" %F{8}(+${delta_7d}%%)%f"
    fi
  fi

  local today_cost="0" _cost_fmt _ci
  for (( _ci=1; _ci<=_CLAUDII_DASH_COUNT; _ci++ )); do
    if [[ -n "${_CLAUDII_DASH_COSTS[$_ci]}" && "${_CLAUDII_DASH_COSTS[$_ci]}" != "0" ]]; then
      _cost_fmt=$(printf '%.2f' "${_CLAUDII_DASH_COSTS[$_ci]}" 2>/dev/null) || _cost_fmt="0.00"
      today_cost=$(awk "BEGIN { printf \"%.2f\", $today_cost + $_cost_fmt }" 2>/dev/null || echo "$today_cost")
    fi
  done
  [[ -n "$_CLAUDII_DASH_GLOBAL_LINE" ]] && _CLAUDII_DASH_GLOBAL_LINE+="${SEP}"
  _CLAUDII_DASH_GLOBAL_LINE+="%F{cyan}"'\$'"${today_cost}%f %F{8}today (${_CLAUDII_DASH_COUNT} session"
  (( _CLAUDII_DASH_COUNT != 1 )) && _CLAUDII_DASH_GLOBAL_LINE+="s"
  _CLAUDII_DASH_GLOBAL_LINE+=")%f"
}

# Builds per-session lines into _CLAUDII_DASH_SESSION_LINES.
function _claudii_render_session_lines {
  local SEP="%F{8} │%f "
  _CLAUDII_DASH_SESSION_LINES=""
  local _cost_fmt_s _si

  for (( _si=1; _si<=_CLAUDII_DASH_COUNT; _si++ )); do
    local s_line=""
    [[ -z "${_CLAUDII_DASH_CTXS[$_si]}" ]] && continue

    s_line+="%B${_CLAUDII_DASH_MODELS[$_si]}%b"

    local _pct=${_CLAUDII_DASH_CTXS[$_si]%.*}
    (( _pct < 0 )) && _pct=0; (( _pct > 100 )) && _pct=100
    local _filled=$(( _pct * 8 / 100 )) _empty=$(( 8 - _filled ))
    local _ctx_color="green"
    (( _pct >= 70 )) && _ctx_color="yellow"
    (( _pct >= 90 )) && _ctx_color="red"
    local _ctx_bar=""
    (( _filled > 0 )) && _ctx_bar+="${(l:$_filled::█:)}"
    (( _empty > 0 )) && _ctx_bar+="%F{8}${(l:$_empty::░:)}%f"
    s_line+=" %F{${_ctx_color}}${_ctx_bar}%f %F{8}${_pct}%%%f"

    if [[ -n "${_CLAUDII_DASH_COSTS[$_si]}" && "${_CLAUDII_DASH_COSTS[$_si]}" != "0" ]]; then
      _cost_fmt_s=$(printf '%.2f' "${_CLAUDII_DASH_COSTS[$_si]}" 2>/dev/null) || _cost_fmt_s="${_CLAUDII_DASH_COSTS[$_si]}"
      s_line+="${SEP}%F{cyan}"'\$'"${_cost_fmt_s}%f"
    fi
    if [[ -n "${_CLAUDII_DASH_CACHE_PCTS[$_si]}" && "${_CLAUDII_DASH_CACHE_PCTS[$_si]}" != "0" && "${_CLAUDII_DASH_CACHE_PCTS[$_si]}" != "" ]]; then
      s_line+="${SEP}%F{8}⚡${_CLAUDII_DASH_CACHE_PCTS[$_si]}%%%f"
    fi
    if [[ -n "${_CLAUDII_DASH_WORKTREES[$_si]}" ]]; then
      s_line+="${SEP}%F{8}[wt:${_CLAUDII_DASH_WORKTREES[$_si]}]%f"
    elif [[ -n "${_CLAUDII_DASH_AGENTS[$_si]}" ]]; then
      s_line+="${SEP}%F{8}[agent:${_CLAUDII_DASH_AGENTS[$_si]}]%f"
    fi
    _CLAUDII_DASH_SESSION_LINES+="${s_line}"$'\n'
  done
}

function _claudii_dashboard {
  local dash_mode="${_CLAUDII_CFG_CACHE[dashboard.enabled]:-${_CLAUDII_DEF_CACHE[dashboard.enabled]:-auto}}"
  if [[ "$dash_mode" == "off" ]]; then
    _CLAUDII_LAST_DASHBOARD=""; _CLAUDII_LAST_DASH_PADDED=""; _CLAUDII_LAST_DASH_LINE_COUNT=0
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  _claudii_collect_sessions
  local active_count=$_CLAUDII_DASH_COUNT

  if [[ "$dash_mode" == "auto" && active_count -eq 0 ]] || (( active_count == 0 )); then
    _CLAUDII_LAST_DASHBOARD=""; _CLAUDII_LAST_DASH_PADDED=""; _CLAUDII_LAST_DASH_LINE_COUNT=0
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  _claudii_render_global_line
  _claudii_render_session_lines

  local dash_raw=""
  [[ -n "$_CLAUDII_DASH_GLOBAL_LINE" ]] && dash_raw="${_CLAUDII_DASH_GLOBAL_LINE}"$'\n'
  dash_raw+="$_CLAUDII_DASH_SESSION_LINES"

  local _cols=${COLUMNS:-80}

  # Reuse padded version if content and terminal width unchanged
  if [[ "$dash_raw" == "$_CLAUDII_LAST_DASHBOARD" && $_cols -eq $_CLAUDII_LAST_DASH_COLS ]]; then
    if [[ -n "$_CLAUDII_LAST_DASH_PADDED" ]]; then
      local _cu_cached=$'\e['"${_CLAUDII_LAST_DASH_LINE_COUNT}A"
      PROMPT="${_CLAUDII_USER_PROMPT}"$'\n'"${_CLAUDII_LAST_DASH_PADDED%$'\n'}%{${_cu_cached}%}"
    else
      PROMPT="${_CLAUDII_USER_PROMPT}"
    fi
    return
  fi

  # Right-align each line: expand prompt codes, strip ANSI, measure visible width.
  # (S) flag = shortest match — prevents greedy glob consuming across sequences.
  #
  # EAW audit (python3 unicodedata.east_asian_width):
  #   ⚡ U+26A1  EAW=W  → always 2 terminal cols; ${#} counts as 1 → counted per line
  #   █ U+2588  EAW=A  → 1 col in non-CJK terminals (no compensation needed)
  #   ░ U+2591  EAW=N  → always 1 col
  #   │ ● ○ …   EAW=A  → 1 col in non-CJK terminals
  #   ✓ ⚠ ✗     EAW=N  → always 1 col
  local dash_padded="" _dl _vis_str _vis _wide _pad
  local -a _dash_lines=("${(@f)${dash_raw%$'\n'}}")
  for _dl in "${_dash_lines[@]}"; do
    [[ -z "$_dl" ]] && continue
    _vis_str="${(%)_dl}"                          # expand %F{} %f %B %b %% etc. → ANSI
    _vis_str="${(S)_vis_str//$'\e'\[[0-9;]*m/}"   # strip ANSI CSI sequences (shortest match)
    _vis_str="${_vis_str//\\\$/\$}"               # \$ → $ (cost display)
    _vis=${#_vis_str}
    _wide=${#${_vis_str//[^⚡]/}}                 # count EAW=W chars (each costs +1 col)
    _pad=$(( _cols - _vis - _wide ))
    if (( _pad < 0 )); then
      # Line overflows terminal width — truncate and escape % for print -P
      local _trunc="${_vis_str[1,$(( _cols - 1 ))]}"
      local _trunc_escaped="${_trunc//%/%%}"
      dash_padded+="${_trunc_escaped}…"$'\n'
    else
      dash_padded+="${(l:$_pad:: :)}${_dl}"$'\n'
    fi
  done

  _CLAUDII_LAST_DASHBOARD="$dash_raw"
  _CLAUDII_LAST_DASH_PADDED="$dash_padded"
  _CLAUDII_LAST_DASH_COLS=$_cols

  # Calculate line count from dash_padded (with trailing \n, wc -l gives correct count).
  local _n_lines
  _n_lines=$(printf '%s' "$dash_padded" | wc -l | tr -d ' ')
  _CLAUDII_LAST_DASH_LINE_COUNT=$(( _n_lines ))

  # Embed dashboard BELOW the prompt: user prompt on line L, dashboard on L+1..L+N,
  # then cursor-up N lines so input appears on line L.
  # Uses relative cursor movement (\e[NA) — safe even when terminal scrolls.
  local _cu=$'\e['"${_n_lines}A"
  PROMPT="${_CLAUDII_USER_PROMPT}"$'\n'"${dash_padded%$'\n'}%{${_cu}%}"
}

# Preexec: fires when a real command is submitted.
# Sets CMD_RAN so precmd skips the empty-Enter erase, and erases the dashboard
# below the prompt so command output starts cleanly on the first dashboard line.
function _claudii_preexec {
  _CLAUDII_CMD_RAN=1
  (( _CLAUDII_LAST_DASH_LINE_COUNT > 0 )) && printf '\e[J'
}

# On terminal resize: invalidate the width cache so the next precmd recomputes
# right-alignment. TRAPWINCH sets CMD_RAN=1 to prevent the empty-Enter erase
# from firing on the resize-triggered precmd cycle.
# Dashboard reflows on next Enter (next precmd cycle).
function TRAPWINCH {
  _CLAUDII_LAST_DASH_COLS=0
  _CLAUDII_CMD_RAN=1
  zle reset-prompt 2>/dev/null
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _claudii_preexec
add-zsh-hook precmd _claudii_statusline
