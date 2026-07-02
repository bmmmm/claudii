# claudii shell functions — cl, clo, clm, clq, clf, clh

# Shared relative-time formatters (_fmt_rel) — bash 3.2 file, zsh-safe.
source "${CLAUDII_HOME}/lib/timefmt.sh"

# Rate-limit warning before launching a model session.
# Usage: _claudii_rl_warn <model_varname> <effort_varname>
# Returns: 0 = proceed, 1 = aborted. Updates model/effort via eval if user switches.
function _claudii_rl_warn {
  local _model_var="$1" _effort_var="$2"
  local _model="${(P)_model_var}"
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local -A _rfst
  local _sf _sf_mt _sf_content _rl_5h _rl_reset _rl_int _reset_str _remaining
  local _color _fb_model _choice _fb_effort
  local _best_mt=0 _best_5h="" _best_reset=""

  # The 5h window is account-wide — every fresh session file carries the same
  # limit, just sampled at different times. Scan all of them and keep the
  # newest sample (glob order is by session id, NOT by freshness; the old
  # `break` on first hit could warn from a stale-by-minutes sample).
  for _sf in "$_cache_base"/session-*(N); do
    [[ "$_sf" == *.tmp.* ]] && continue
    _sf_mt=0
    if (( ${+modules[zsh/stat]} )); then
      _rfst=()
      zstat -H _rfst "$_sf" 2>/dev/null && _sf_mt=${_rfst[mtime]:-0}
    else
      _sf_mt=$(stat -f%m "$_sf" 2>/dev/null || stat -c%Y "$_sf" 2>/dev/null || echo 0)
    fi
    (( (EPOCHSECONDS - _sf_mt) > 300 )) && continue
    (( _sf_mt <= _best_mt )) && continue

    _sf_content=""
    { _sf_content=$(<"$_sf"); } 2>/dev/null
    [[ -z "$_sf_content" ]] && continue

    _rl_5h="" _rl_reset=""
    # Anchor the extraction (not just the guard) on a leading newline so a value
    # that happens to contain "rate_5h=" can't be matched as the key.
    local _nl=$'\n'"$_sf_content"
    [[ "$_nl" == *$'\n'rate_5h=* ]]  && _rl_5h="${${_nl#*$'\n'rate_5h=}%%$'\n'*}"
    [[ "$_nl" == *$'\n'reset_5h=* ]] && _rl_reset="${${_nl#*$'\n'reset_5h=}%%$'\n'*}"
    [[ -z "$_rl_5h" || "$_rl_5h" == "null" ]] && continue

    _best_mt=$_sf_mt
    _best_5h=$_rl_5h
    _best_reset=$_rl_reset
  done

  [[ -z "$_best_5h" ]] && return 0
  _rl_int=${_best_5h%.*}
  (( _rl_int < 80 )) && return 0

  _reset_str=""
  if [[ -n "$_best_reset" && "$_best_reset" != "0" && "$_best_reset" != "null" ]]; then
    _remaining=$(( ${_best_reset%.*} - ${_CLAUDII_NOW:-$EPOCHSECONDS} ))
    if (( _remaining > 0 )); then
      _fmt_rel $_remaining
      [[ -n "$_REL_FMT" ]] && _reset_str=" · resets in ${_REL_FMT}"
    fi
  fi

  # Threshold/color stay keyed on used %; the displayed number follows
  # statusline.rate_display like every other surface (overview, dashboard,
  # sessionline). The limit is account-wide, so the message names the 5h
  # window — the old text attributed it to the model being launched
  # ("Sonnet 5h at 86%"), which read as a per-model limit.
  local _disp=$_rl_int _word="used"
  if [[ "$(claudii_config_get statusline.rate_display)" == "remaining" ]]; then
    _disp=$(( 100 - _rl_int ))
    _word="left"
  fi

  _color="$CLAUDII_CLR_YELLOW"
  (( _rl_int >= 90 )) && _color="$CLAUDII_CLR_RED"

  printf "${_color}⚠ 5h limit: ${_disp}%% ${_word}${_reset_str}${CLAUDII_CLR_RESET}\n"
  if [[ "$_model" == "opus" ]]; then
    _fb_model=$(claudii_config_get "fallback.opus.model")
    [[ -z "$_fb_model" ]] && _fb_model="sonnet"
    printf "  Switch to ${_fb_model}? ${CLAUDII_CLR_DIM}[Enter] proceed · [s] ${_fb_model} · [w] wait${CLAUDII_CLR_RESET} "
    _choice=""
    read -k1 _choice
    echo ""
    case "$_choice" in
      s|S)
        _fb_effort=$(claudii_config_get "fallback.opus.effort")
        # No namerefs: zsh 5.9 (macOS) has no `local -n`/`typeset -n` — it
        # errored "bad option: -n" and the model was silently NOT switched
        # while the confirmation line still printed. eval on the validated
        # internal varname ("model"/"effort" from _claudii_launch) instead.
        eval "${_model_var}=\${_fb_model}"
        [[ -n "$_fb_effort" ]] && eval "${_effort_var}=\${_fb_effort}"
        # Effort shown = what the launch will actually use: the fallback
        # effort, or the caller's unchanged effort var ((P) indirection —
        # the old `aliases.$_model_var.effort` looked up the literal key
        # "aliases.model.effort", which never exists).
        printf "→ ${CLAUDII_CLR_CYAN}${_fb_model} ${_fb_effort:-${(P)_effort_var}}${CLAUDII_CLR_RESET}\n"
        ;;
      w|W)
        printf "${CLAUDII_CLR_DIM}Cancelled.${CLAUDII_CLR_RESET}\n"
        return 1
        ;;
    esac
  fi
  return 0
}

function _claudii_launch {
  local alias_name=$1; shift
  local model=$(claudii_config_get "aliases.$alias_name.model")
  local effort=$(claudii_config_get "aliases.$alias_name.effort")
  local dir=$(claudii_config_get "aliases.$alias_name.dir")

  _claudii_log debug "launch: alias=$alias_name model=$model effort=$effort"
  [[ -n "$dir" ]] && cd "${dir/#\~/$HOME}"

  # Check fallback — read the status-models cache the precmd keeps warm instead of
  # a synchronous network round-trip on every launch. The old inline claudii-status
  # call blocked the launch up to ~5s on a stale cache AND dumped the health line to
  # the terminal before every `cl`/`clo`/… start. If the cache is absent (brand-new
  # shell, status job not finished), kick off a background refresh ( cmd & ) and
  # proceed with the chosen model — fallback is a convenience, not a gate.
  if [[ "$(claudii_config_get fallback.enabled)" == "true" ]]; then
    local cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models"
    if [[ ! -f "$cache" ]]; then
      ( "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null & )
    elif grep -q "^${model}=down" "$cache" 2>/dev/null; then
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
  _claudii_rl_warn model effort || return 1

  _claudii_log info "starting claude: $model $effort"
  claude --model "$model" --effort "$effort" "$@"
}

# Register alias shell functions dynamically from config (aliases.*)
# Creates functions like cl, clo, clm, clq, clf — no hardcoded list.
function _claudii_register_aliases {
  local config="${CLAUDII_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json}"
  [[ -f "$config" ]] || return
  local aliases_json
  aliases_json=$(jq -r '.aliases // {} | keys[]' "$config" 2>/dev/null) || return
  [[ -z "$aliases_json" ]] && return
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { echo "claudii: invalid alias name: $name" >&2; continue; }
    functions[$name]="_claudii_launch $name \"\$@\""
    _claudii_log debug "registered alias: $name"
  done <<< "$aliases_json"
}
_claudii_register_aliases

# Agent launcher — starts claude with a skill as system prompt
# Looks in: .claude/skills/<name>/SKILL.md (project) → ~/.claude/agents/<name>.md (global)
# Empty agent_name = plain worker launch (model/effort only, no system prompt) —
# used by skill-less agents like hk/sn/op from config.agents.
function _claudii_agent_launch {
  local agent_name="$1" model="${2:-opus}" effort="${3:-high}"
  shift 3 2>/dev/null || shift $#

  if [[ -z "$agent_name" ]]; then
    _claudii_log info "agent launch: plain worker model=$model effort=$effort"
    claude --model "$model" --effort "$effort" "$@"
    return $?
  fi

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
  claude --model "$model" --effort "$effort" --name "$agent_name" --append-system-prompt "$prompt" "$@"
}

# Register agent aliases from config (agents.*.skill/model/effort)
# Creates shell functions dynamically — no hardcoded aliases
function _claudii_register_agents {
  _claudii_cache_load
  local config="${CLAUDII_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json}"
  [[ -f "$config" ]] || return

  # US (0x1F) separator, not tab: zsh `read` treats tab as IFS-whitespace and
  # collapses runs of it, so an empty skill field ("hk\t\thaiku\thigh") shifted
  # every following field (model→skill, effort→model, effort empty → "invalid
  # agent effort" on every shell start). 0x1F is non-whitespace → empty fields
  # survive.
  local agents_json _us=$'\x1f'
  agents_json=$(jq -r '.agents // {} | to_entries[] | [.key, (.value.skill // ""), (.value.model // "opus"), (.value.effort // "high")] | join("\u001f")' "$config" 2>/dev/null) || return

  [[ -z "$agents_json" ]] && return

  while IFS="$_us" read -r name skill model effort; do
    [[ -z "$name" ]] && continue
    [[ "$name"   =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$  ]] || { echo "claudii: invalid agent name: $name"   >&2; continue; }
    [[ "$name" == claudii || "$name" == claude || "$name" == clh ]] && { echo "claudii: reserved name: $name" >&2; continue; }
    # skill is optional — agents without one (hk/sn/op/…) register as plain
    # model/effort launchers. Skipping them entirely left every skill-less
    # default agent advertised by `claudii agents` but unregistered (command
    # not found).
    if [[ -n "$skill" ]]; then
      [[ "$skill" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || { echo "claudii: invalid agent skill: $skill" >&2; continue; }
    fi
    [[ "$model"  =~ ^[a-zA-Z][a-zA-Z0-9_-]*$  ]] || { echo "claudii: invalid agent model: $model" >&2; continue; }
    [[ "$effort" =~ ^[a-zA-Z]+$               ]] || { echo "claudii: invalid agent effort: $effort" >&2; continue; }
    functions[$name]="_claudii_agent_launch \"$skill\" \"$model\" \"$effort\" \"\$@\""
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
      printf "${CLAUDII_CLR_GREEN}✓ claudii reloaded  (%s)${CLAUDII_CLR_RESET}\n" "$(basename "$_dir")"
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
  printf '  │ Alias │ Model  │ Effort │          Context           │\n'
  printf '  ├───────┼────────┼────────┼────────────────────────────┤\n'

  local alias_list=()
  while IFS= read -r _a_key; do [[ -n "$_a_key" ]] && alias_list+=("$_a_key"); done < <(jq -r '.aliases | keys[]' "$CLAUDII_CONFIG" 2>/dev/null)
  local total=${#alias_list[@]} i=0
  for a in "${alias_list[@]}"; do
    (( ++i ))
    printf '  │ %-5s │ %-6s │ %-6s │ %-26s │\n' \
      "$a" "$(claudii_config_get aliases.$a.model)" \
      "$(claudii_config_get aliases.$a.effort)" \
      "$(claudii_config_get aliases.$a.description)"
    (( i < total )) && printf '  ├───────┼────────┼────────┼────────────────────────────┤\n'
  done
  printf '  └───────┴────────┴────────┴────────────────────────────┘\n'
  echo ""
  "$CLAUDII_HOME/bin/claudii-status" 2>&1; local _status_exit=$?
  [[ $_status_exit -eq 0 ]] && printf "${CLAUDII_CLR_GREEN}  ✓ All models available${CLAUDII_CLR_RESET}\n"
  return $_status_exit
}
