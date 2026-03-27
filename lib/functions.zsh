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
    local cache="${TMPDIR:-/tmp}/claudii-status-models"
    if [[ -f "$cache" ]] && grep -q "^${model}=down" "$cache" 2>/dev/null; then
      local fb_model=$(claudii_config_get "fallback.$model.model")
      local fb_effort=$(claudii_config_get "fallback.$model.effort")
      _claudii_log warn "fallback: $model → ${fb_model:-$model} (model was down)"
      echo "→ Fallback: ${fb_model:-$model} ${fb_effort:-$effort}"
      claude --model "${fb_model:-$model}" --effort "${fb_effort:-$effort}" "$@"
      return
    fi
  fi

  _claudii_log info "starting claude: $model $effort"
  claude --model "$model" --effort "$effort" "$@"
}

function cl  { _claudii_launch cl "$@"; }
function clo { _claudii_launch clo "$@"; }
function clm { _claudii_launch clm "$@"; }
function clq { _claudii_launch clq "$@"; }

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
