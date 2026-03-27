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

# claudii wrapper: intercepts 'restart' in the current shell,
# delegates everything else to the binary.
function claudii {
  if [[ "${1:-}" == "restart" ]]; then
    local _dir="$PWD"
    printf '\033[0;36mReloading claudii...\033[0m\n'
    source "$HOME/.zshrc"
    cd "$_dir"
    printf '\033[0;32m✓ claudii neu geladen  (%s)\033[0m\n' "$(basename "$_dir")"
  else
    command claudii "$@"
  fi
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
