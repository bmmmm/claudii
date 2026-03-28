# claudii shell functions — cl, clo, clm, clq, clh

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
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local _rl_warned=0
  for _sf in "$_cache_base"/session-*(N); do
    # Only consider fresh sessions (< 5min old)
    local _sf_mt=0
    if (( ${+modules[zsh/stat]} )); then
      local -A _rfst
      zstat -H _rfst "$_sf" 2>/dev/null && _sf_mt=${_rfst[mtime]:-0}
    else
      _sf_mt=$(stat -f%m "$_sf" 2>/dev/null || echo 0)
    fi
    (( (EPOCHSECONDS - _sf_mt) > 300 )) && continue

    local _sf_content=""
    { _sf_content=$(<"$_sf"); } 2>/dev/null
    [[ -z "$_sf_content" ]] && continue

    local _rl_5h="" _rl_reset=""
    [[ $'\n'"$_sf_content" == *$'\n'rate_5h=* ]] && _rl_5h="${${_sf_content#*rate_5h=}%%$'\n'*}"
    [[ $'\n'"$_sf_content" == *$'\n'reset_5h=* ]] && _rl_reset="${${_sf_content#*reset_5h=}%%$'\n'*}"

    [[ -z "$_rl_5h" ]] && continue
    local _rl_int=${_rl_5h%.*}
    (( _rl_int < 80 )) && continue

    # Rate limit is high — build warning
    local _reset_str=""
    if [[ -n "$_rl_reset" && "$_rl_reset" != "0" ]]; then
      local _remaining=$(( _rl_reset - EPOCHSECONDS ))
      if (( _remaining > 0 )); then
        _reset_str=" Reset in $(( _remaining / 60 ))min"
      fi
    fi

    local _color="\033[33m"  # yellow
    (( _rl_int >= 90 )) && _color="\033[31m"  # red

    printf "${_color}⚠ ${(C)model} 5h bei ${_rl_int}%%${_reset_str}\033[0m\n"
    # Suggest alternative if launching opus
    if [[ "$model" == "opus" ]]; then
      local _fb_model=$(claudii_config_get "fallback.opus.model")
      [[ -z "$_fb_model" ]] && _fb_model="sonnet"
      printf "  ${_fb_model} stattdessen? \033[2m[Enter] starten · [s] ${_fb_model} · [w] warten\033[0m "
      local _choice=""
      read -k1 _choice
      echo ""
      case "$_choice" in
        s|S)
          model="$_fb_model"
          local _fb_effort=$(claudii_config_get "fallback.opus.effort")
          [[ -n "$_fb_effort" ]] && effort="$_fb_effort"
          printf "→ \033[36m${_fb_model} ${effort}\033[0m\n"
          ;;
        w|W)
          printf "\033[2mAbgebrochen.\033[0m\n"
          return 0
          ;;
      esac
    fi
    _rl_warned=1
    break  # Only warn once (freshest session)
  done

  _claudii_log info "starting claude: $model $effort"
  # Export effort for sessionline — workaround until Anthropic adds effort to statusLine JSON
  CLAUDII_EFFORT="$effort" claude --model "$model" --effort "$effort" "$@"
}

function cl  { _claudii_launch cl "$@"; }
function clo { _claudii_launch clo "$@"; }
function clm { _claudii_launch clm "$@"; }
function clq { _claudii_launch clq "$@"; }

# Agent launcher — launches claude with a system prompt from ~/.claude/agents/<name>.md
function _claudii_agent_launch {
  local agent_name="$1"; shift
  local agent_file="${HOME}/.claude/agents/${agent_name}.md"

  if [[ ! -f "$agent_file" ]]; then
    printf '\033[0;31m✗ Agent not found: %s\033[0m\n' "$agent_file" >&2
    printf '  Available agents:\n' >&2
    local found=0
    for f in "${HOME}/.claude/agents/"*.md(N); do
      printf '    %s\n' "$(basename "$f" .md)" >&2
      found=1
    done
    (( found == 0 )) && printf '    (none — create ~/.claude/agents/*.md files)\n' >&2
    return 1
  fi

  local prompt
  prompt=$(< "$agent_file")
  _claudii_log info "agent launch: $agent_name"
  claude --model opus --effort high --system-prompt "$prompt" "$@"
}

function clorch { _claudii_agent_launch orchestrator "$@"; }
function cle    { _claudii_agent_launch explorer "$@"; }

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
  printf '  \033[0;36mclaudii — performance metrics\033[0m\n'
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
      printf '\033[0;36mReloading claudii...\033[0m\n'
      source "$HOME/.zshrc"
      cd "$_dir"
      printf '\033[0;32m✓ claudii neu geladen  (%s)\033[0m\n' "$(basename "$_dir")"
      ;;
    update)
      if ! git -C "$CLAUDII_HOME" rev-parse --git-dir >/dev/null 2>&1; then
        printf '\033[0;31m✗ Not a git repo — install via:\033[0m\n'
        printf '  git clone https://github.com/bmmmm/claudii\n'
        return 1
      fi
      local _dir="$PWD"
      printf '\033[0;36mPulling latest claudii...\033[0m\n'
      git -C "$CLAUDII_HOME" pull --ff-only || {
        printf '\033[0;31m✗ git pull failed\033[0m\n'; return 1
      }
      printf '\033[0;36mReloading...\033[0m\n'
      source "$HOME/.zshrc"
      cd "$_dir"
      printf '\033[0;32m✓ claudii updated and reloaded  (%s)\033[0m\n' "$(basename "$_dir")"
      ;;
    metrics)
      _claudii_show_metrics
      ;;
    "")
      command claudii
      print -z "claudii "
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
  "$CLAUDII_HOME/bin/claudii-status" 2>&1
  [[ $? -eq 0 ]] && printf '  \033[0;32m✓ Alle Modelle verfügbar\033[0m\n'
  return 0
}
