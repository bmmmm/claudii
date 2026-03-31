# claudii shell functions — cl, clo, clm, clq, clh

# Rate-limit warning before launching a model session.
# Usage: _claudii_rl_warn <model_varname> <effort_varname>
# Returns: 0 = proceed, 1 = aborted. Updates model/effort via eval if user switches.
function _claudii_rl_warn {
  local _model_var="$1" _effort_var="$2"
  local _model="${(P)_model_var}"
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local -A _rfst
  local _sf_mt _sf_content _rl_5h _rl_reset _rl_int _reset_str _remaining
  local _color _fb_model _choice _fb_effort

  for _sf in "$_cache_base"/session-*(N); do
    _sf_mt=0
    if (( ${+modules[zsh/stat]} )); then
      _rfst=()
      zstat -H _rfst "$_sf" 2>/dev/null && _sf_mt=${_rfst[mtime]:-0}
    else
      _sf_mt=$(stat -f%m "$_sf" 2>/dev/null || echo 0)
    fi
    (( (EPOCHSECONDS - _sf_mt) > 300 )) && continue

    _sf_content=""
    { _sf_content=$(<"$_sf"); } 2>/dev/null
    [[ -z "$_sf_content" ]] && continue

    _rl_5h="" _rl_reset=""
    [[ $'\n'"$_sf_content" == *$'\n'rate_5h=* ]] && _rl_5h="${${_sf_content#*rate_5h=}%%$'\n'*}"
    [[ $'\n'"$_sf_content" == *$'\n'reset_5h=* ]] && _rl_reset="${${_sf_content#*reset_5h=}%%$'\n'*}"

    [[ -z "$_rl_5h" ]] && continue
    _rl_int=${_rl_5h%.*}
    (( _rl_int < 80 )) && continue

    _reset_str=""
    if [[ -n "$_rl_reset" && "$_rl_reset" != "0" ]]; then
      _remaining=$(( _rl_reset - EPOCHSECONDS ))
      (( _remaining > 0 )) && _reset_str=" Reset in $(( _remaining / 60 ))min"
    fi

    _color="$CLAUDII_CLR_YELLOW"
    (( _rl_int >= 90 )) && _color="$CLAUDII_CLR_RED"

    printf "${_color}⚠ ${(C)_model} 5h bei ${_rl_int}%%${_reset_str}${CLAUDII_CLR_RESET}\n"
    if [[ "$_model" == "opus" ]]; then
      _fb_model=$(claudii_config_get "fallback.opus.model")
      [[ -z "$_fb_model" ]] && _fb_model="sonnet"
      printf "  ${_fb_model} stattdessen? ${CLAUDII_CLR_DIM}[Enter] starten · [s] ${_fb_model} · [w] warten${CLAUDII_CLR_RESET} "
      _choice=""
      read -k1 _choice
      echo ""
      case "$_choice" in
        s|S)
          _fb_effort=$(claudii_config_get "fallback.opus.effort")
          eval "$_model_var=\"\$_fb_model\""
          [[ -n "$_fb_effort" ]] && eval "$_effort_var=\"\$_fb_effort\""
          printf "→ ${CLAUDII_CLR_CYAN}${_fb_model} ${_fb_effort:-$(claudii_config_get aliases.$_model_var.effort)}${CLAUDII_CLR_RESET}\n"
          ;;
        w|W)
          printf "${CLAUDII_CLR_DIM}Abgebrochen.${CLAUDII_CLR_RESET}\n"
          return 1
          ;;
      esac
    fi
    break  # Only warn once (freshest session)
  done
  return 0
}

function _claudii_launch {
  local alias_name=$1; shift
  local model=$(claudii_config_get "aliases.$alias_name.model")
  local effort=$(claudii_config_get "aliases.$alias_name.effort")
  local dir=$(claudii_config_get "aliases.$alias_name.dir")

  _claudii_log debug "launch: alias=$alias_name model=$model effort=$effort"
  [[ -n "$dir" ]] && cd "${dir/#\~/$HOME}"

  # Check fallback
  if [[ "$(claudii_config_get fallback.enabled)" == "true" ]]; then
    "$CLAUDII_HOME/bin/claudii-status" 2>&1
    local cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models"
    if [[ -f "$cache" ]] && grep -q "^${model}=down" "$cache" 2>/dev/null; then
      local fb_model=$(claudii_config_get "fallback.$model.model")
      local fb_effort=$(claudii_config_get "fallback.$model.effort")
      if [[ -z "$fb_model" ]]; then
        _claudii_log warn "fallback: no fallback configured for $model — using original"
      else
        _claudii_log warn "fallback: $model → $fb_model (model was down)"
        echo "→ Fallback: $fb_model ${fb_effort:-$effort}"
        model="$fb_model"
        [[ -n "$fb_effort" ]] && effort="$fb_effort"
      fi
    fi
  fi

  # Rate-Limit-Intelligence — warn before launching into a near-full window
  _claudii_rl_warn model effort || return 0

  _claudii_log info "starting claude: $model $effort"
  # Export effort for sessionline — workaround until Anthropic adds effort to statusLine JSON
  CLAUDII_EFFORT="$effort" claude --model "$model" --effort "$effort" "$@"
}

function cl  { _claudii_launch cl "$@"; }
function clo { _claudii_launch clo "$@"; }
function clm { _claudii_launch clm "$@"; }
function clq { _claudii_launch clq "$@"; }

# Agent launcher — starts claude with a skill as system prompt
# Looks in: .claude/skills/<name>/SKILL.md (project) → ~/.claude/agents/<name>.md (global)
function _claudii_agent_launch {
  local agent_name="$1" model="${2:-opus}" effort="${3:-high}"
  shift 3 2>/dev/null || shift $#
  local agent_file=""

  # Project skill first, then global agents
  if [[ -f ".claude/skills/${agent_name}/SKILL.md" ]]; then
    agent_file=".claude/skills/${agent_name}/SKILL.md"
  elif [[ -f "${HOME}/.claude/agents/${agent_name}.md" ]]; then
    agent_file="${HOME}/.claude/agents/${agent_name}.md"
  fi

  if [[ -z "$agent_file" ]]; then
    printf "${CLAUDII_CLR_RED}✗ Agent not found: %s${CLAUDII_CLR_RESET}\n" "$agent_name" >&2
    printf '  Available:\n' >&2
    local found=0
    for f in .claude/skills/*/SKILL.md(N); do
      printf '    %s (skill)\n' "$(basename "$(dirname "$f")")" >&2
      found=1
    done
    for f in "${HOME}/.claude/agents/"*.md(N); do
      printf '    %s (agent)\n' "$(basename "$f" .md)" >&2
      found=1
    done
    (( found == 0 )) && printf '    (none)\n' >&2
    return 1
  fi

  local prompt
  prompt=$(< "$agent_file")
  _claudii_log info "agent launch: $agent_name ($agent_file) model=$model effort=$effort"
  CLAUDII_EFFORT="$effort" claude --model "$model" --effort "$effort" --append-system-prompt "$prompt" "$@"
}

# Register agent aliases from config (agents.*.skill/model/effort)
# Creates shell functions dynamically — no hardcoded aliases
function _claudii_register_agents {
  _claudii_cache_load
  local config="${CLAUDII_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json}"
  [[ -f "$config" ]] || return

  local agents_json
  agents_json=$(jq -r '.agents // {} | to_entries[] | "\(.key)\t\(.value.skill // "")\t\(.value.model // "opus")\t\(.value.effort // "high")"' "$config" 2>/dev/null) || return

  [[ -z "$agents_json" ]] && return

  while IFS=$'\t' read -r name skill model effort; do
    [[ -z "$name" || -z "$skill" ]] && continue
    [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { echo "claudii: invalid agent name: $name" >&2; continue; }
    # Create a shell function with this name
    eval "function $name { _claudii_agent_launch $skill $model $effort \"\$@\"; }"
    _claudii_log debug "registered agent alias: $name → $skill ($model/$effort)"
  done <<< "$agents_json"
}

_claudii_register_agents

# Format microseconds as µs or ms
function _claudii_fmt_us {
  local us=$1
  if (( us < 1000 )); then
    printf '%dµs' $us
  else
    printf '%d.%dms' $(( us / 1000 )) $(( (us % 1000) / 100 ))
  fi
}

function _claudii_show_metrics {
  local calls=${_CLAUDII_METRICS[precmd.calls]:-0}
  local total=${_CLAUDII_METRICS[precmd.total_us]:-0}
  local avg=$(( calls > 0 ? total / calls : 0 ))
  local reloads=${_CLAUDII_METRICS[config.reloads]:-0}

  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii — performance metrics${CLAUDII_CLR_RESET}\n"
  printf '  ──────────────────────────────────────────\n'
  printf '  %-30s  %s\n' "plugin load"           "$(_claudii_fmt_us ${_CLAUDII_METRICS[plugin.load_us]:-0})"
  printf '  %-30s  %s\n' "config defaults (jq)"  "$(_claudii_fmt_us ${_CLAUDII_METRICS[config.defaults_us]:-0})"
  printf '  ──────────────────────────────────────────\n'
  printf '  %-30s  %s\n' "precmd calls this session"  "${calls}x"
  printf '  %-30s  %s\n' "precmd last"           "$(_claudii_fmt_us ${_CLAUDII_METRICS[precmd.last_us]:-0})"
  printf '  %-30s  %s\n' "precmd avg"             "$(_claudii_fmt_us $avg)"
  printf '  %-30s  %s\n' "precmd total"           "$(_claudii_fmt_us $total)"
  printf '  ──────────────────────────────────────────\n'
  printf '  %-30s  %dx\n' "config reloads (jq)"  $reloads
  if (( reloads > 0 )); then
    printf '  %-30s  %s\n' "last reload"          "$(_claudii_fmt_us ${_CLAUDII_METRICS[config.cache_load_us]:-0})"
  fi
  printf '\n'
}

# claudii wrapper: intercepts shell-only commands, delegates rest to binary.
function claudii {
  case "${1:-}" in
    restart)
      local _dir="$PWD"
      printf "${CLAUDII_CLR_CYAN}Reloading claudii...${CLAUDII_CLR_RESET}\n"
      source "$HOME/.zshrc"
      cd "$_dir"
      printf "${CLAUDII_CLR_GREEN}✓ claudii neu geladen  (%s)${CLAUDII_CLR_RESET}\n" "$(basename "$_dir")"
      ;;
    update)
      local _dir="$PWD"
      command claudii update || return $?
      printf "${CLAUDII_CLR_CYAN}Reloading...${CLAUDII_CLR_RESET}\n"
      source "$HOME/.zshrc"
      cd "$_dir"
      printf "${CLAUDII_CLR_GREEN}✓ claudii reloaded  (%s)${CLAUDII_CLR_RESET}\n" "$(basename "$_dir")"
      ;;
    metrics)
      _claudii_show_metrics
      ;;
    "")
      command claudii
      print -z "claudii "
      ;;
    se|si|sessions|sessions-inactive)
      # Signal the session dashboard to suppress — user just saw session info
      _CLAUDII_SHOWED_SESSIONS=1
      command claudii "$@"
      ;;
    *)
      command claudii "$@"
      ;;
  esac
}

function clh {
  printf '  ┌───────┬────────┬────────┬────────────────────────────┐\n'
  printf '  │ Alias │ Modell │ Effort │          Kontext           │\n'
  printf '  ├───────┼────────┼────────┼────────────────────────────┤\n'

  local alias_list=($(jq -r '.aliases | keys[]' "$CLAUDII_CONFIG" 2>/dev/null))
  local total=${#alias_list[@]} i=0
  for a in "${alias_list[@]}"; do
    (( i++ ))
    printf '  │ %-5s │ %-6s │ %-6s │ %-26s │\n' \
      "$a" "$(claudii_config_get aliases.$a.model)" \
      "$(claudii_config_get aliases.$a.effort)" \
      "$(claudii_config_get aliases.$a.description)"
    (( i < total )) && printf '  ├───────┼────────┼────────┼────────────────────────────┤\n'
  done
  printf '  └───────┴────────┴────────┴────────────────────────────┘\n'
  echo ""
  "$CLAUDII_HOME/bin/claudii-status" 2>&1; local _status_exit=$?
  [[ $_status_exit -eq 0 ]] && printf "${CLAUDII_CLR_GREEN}  ✓ Alle Modelle verfügbar${CLAUDII_CLR_RESET}\n"
  return $_status_exit
}
