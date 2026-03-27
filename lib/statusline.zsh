# claudii statusline — RPROMPT with per-model health + last-fetch age

function _claudii_statusline {
  [[ "$(claudii_config_get statusline.enabled)" != "true" ]] && { RPROMPT=""; return; }

  local cache="${TMPDIR:-/tmp}/claudii-status-models"
  if [[ ! -f "$cache" ]]; then
    "$CLAUDII_HOME/bin/claudii-status" --quiet &>/dev/null &
    RPROMPT=""; return
  fi

  local models=(${(s:,:)$(claudii_config_get statusline.models)})
  [[ ${#models} -eq 0 ]] && models=(opus sonnet haiku)

  local segments=""
  for model in "${models[@]}"; do
    model="${model// /}"
    if grep -q "^${model}=down" "$cache" 2>/dev/null; then
      segments+="%F{yellow}${(C)model} ↓%f "
    else
      segments+="%F{green}${(C)model} ✓%f "
    fi
  done

  # Last-fetch age
  local age=$(( $(date +%s) - $(stat -f%m "$cache") ))
  local age_str
  if (( age < 60 )); then age_str="${age}s"
  elif (( age < 3600 )); then age_str="$(( age / 60 ))m"
  else age_str="$(( age / 3600 ))h"
  fi

  RPROMPT="[${segments% }] %F{8}${age_str}%f"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claudii_statusline
