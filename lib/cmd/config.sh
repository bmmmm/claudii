# lib/cmd/config.sh — configuration and tool commands (config, agents, search)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_config() {
  _cfg_init

  # Build a properly quoted jq path from a dotted key.
  # Needed for keys with hyphens (e.g. "session-dashboard.enabled" → ."session-dashboard"."enabled")
  # since jq parses ."session-dashboard" as ."session" - "dashboard" (subtraction).
  _build_jq_path() {
    local key="$1" _jp="" _seg
    local _IFS_OLD="$IFS"
    IFS='.' read -ra _segs <<< "$key"
    IFS="$_IFS_OLD"
    for _seg in "${_segs[@]}"; do
      _jp+='."'"$_seg"'"'
    done
    echo "$_jp"
  }

  case "${2:-}" in
    get)
      key="${3:?Usage: claudii config get <key>}"
      _validate_key "$key" || exit 1
      jq_path=$(_build_jq_path "$key")
      val=$(jq -r "if ($jq_path | type) != \"null\" then ($jq_path | tostring) else empty end" "$CONFIG" 2>/dev/null)
      [[ -z "$val" ]] && val=$(jq -r "if ($jq_path | type) != \"null\" then ($jq_path | tostring) else empty end" "$DEFAULTS" 2>/dev/null)
      echo "$val"
      ;;
    set)
      key="${3:?Usage: claudii config set <key> <value>}"
      _validate_key "$key" || exit 1
      value="${4:?Usage: claudii config set <key> <value>}"
      if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
        _jq_update "$CONFIG" --arg k "$key" --argjson v "$value" \
          'setpath($k | split("."); $v)'
      else
        _jq_update "$CONFIG" --arg k "$key" --arg v "$value" \
          'setpath($k | split("."); $v)'
      fi
      echo "Set $key = $value"
      ;;
    reset)
      cp "$DEFAULTS" "$CONFIG"
      echo "Config reset to defaults"
      ;;
    export)
      file="${3:-}"
      if [[ -n "$file" ]]; then
        cp "$CONFIG" "$file"
        echo "Config exported to $file"
      else
        cat "$CONFIG"
      fi
      ;;
    import)
      file="${3:?Usage: claudii config import <file>}"
      [[ -f "$file" ]] || { echo "File not found: $file — check the path" >&2; exit 1; }
      jq '.' "$file" >/dev/null 2>&1 || { echo "Not valid JSON: $file — run 'jq . $file' to diagnose" >&2; exit 1; }
      # Validate only known top-level keys
      _known='["statusline","debug","theme","theme_presets","cost","search","status","agents","fallback","aliases","session-dashboard"]'
      _unknown=$(jq --argjson known "$_known" 'keys - $known | length' "$file")
      [[ "$_unknown" -eq 0 ]] || { printf "config import: unknown keys in %s — aborting\n" "$file" >&2; exit 1; }

      # Validate agent names match allowed pattern
      if jq -e '.agents | type == "object"' "$file" >/dev/null 2>&1; then
        _bad_agents=$(jq -r '.agents | to_entries[] | select(.key | test("^[a-zA-Z_][a-zA-Z0-9_-]*$") | not) | .key' "$file")
        [[ -z "$_bad_agents" ]] || { printf "config import: invalid agent name(s): %s\n" "$_bad_agents" >&2; exit 1; }
      fi
      cp "$CONFIG" "${CONFIG}.bak"
      cp "$file" "$CONFIG"
      echo "Config importiert aus $file  (Backup: ${CONFIG}.bak)"
      ;;
    theme)
      # claudii config theme         → list available themes
      # claudii config theme <name>  → set theme.name in user config
      theme_arg="${3:-}"
      if [[ -z "$theme_arg" ]]; then
        # List available themes from defaults.json theme_presets
        echo "Available themes:"
        current=$(jq -r '.theme.name // "default"' "$CONFIG" 2>/dev/null)
        jq -r '.theme_presets | keys[]' "$DEFAULTS" 2>/dev/null | sort | while IFS= read -r t; do
          if [[ "$t" == "$current" ]]; then
            echo "  * $t (active)"
          else
            echo "    $t"
          fi
        done
      else
        # Validate that the theme exists in defaults
        valid=$(jq -r --arg name "$theme_arg" '.theme_presets | has($name)' "$DEFAULTS" 2>/dev/null)
        if [[ "$valid" != "true" ]]; then
          echo "Unknown theme: $theme_arg — available: $(jq -r '.theme_presets | keys | join(", ")' "$DEFAULTS" 2>/dev/null)" >&2
          exit 1
        fi
        # Set theme.name in user config
        _jq_update "$CONFIG" --arg name "$theme_arg" '.theme.name = $name'
        echo "Theme set to: $theme_arg"
      fi
      ;;
    *)
      echo "User config: $CONFIG"
      echo ""
      jq '.' "$CONFIG"
      ;;
  esac
}

_cmd_search() {
  _cfg_init
  search_dir=$(_cfgget search.dir)
  search_dir="${search_dir/#\~/$HOME}"

  # Try search.model first, fall back to aliases.clq.model, then to default sonnet
  model=$(_cfgget search.model)
  [[ -z "$model" ]] && model=$(_cfgget aliases.clq.model)
  [[ -z "$model" ]] && model="sonnet"

  # Try search.effort first, fall back to aliases.clq.effort, then to default medium
  effort=$(_cfgget search.effort)
  [[ -z "$effort" ]] && effort=$(_cfgget aliases.clq.effort)
  [[ -z "$effort" ]] && effort="medium"

  cd "$search_dir" || { echo "claudii: search directory not found: $search_dir" >&2; exit 1; }
  exec claude --model "$model" --effort "$effort" "${@:2}"
}

_cmd_agents() {
  _cfg_init
  # Read agents object from config (user config first, then defaults)
  agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$CONFIG" 2>/dev/null)
  [[ -z "$agents_json" ]] && agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$DEFAULTS" 2>/dev/null)

  if [[ -z "$agents_json" ]]; then
    # No agents configured — show onboarding text
    if [[ "$_FORMAT" == "json" ]]; then
      echo "[]"
      exit 0
    fi

    printf '\nNo agents configured.\n\n'
    printf 'Agents let you launch Claude with a specific skill as system prompt — using a short\n'
    printf 'alias instead of a long --append-system-prompt flag.\n'
    printf '\n'
    printf 'Without agents:\n'
    printf '  claude --model opus --effort high --append-system-prompt "$(cat .claude/skills/orchestrate/SKILL.md)"\n'
    printf '\n'
    printf 'With agents (after setup):\n'
    printf '  clorch\n'
    printf '\n'
    printf 'Setup:\n'
    printf '  claudii config set agents.clorch.skill orchestrate\n'
    printf '  claudii config set agents.clorch.model opus\n'
    printf '  claudii config set agents.clorch.effort high\n'
    printf '\n'

    # Scan for skills in current directory
    printf 'Available skills in this project:\n'
    shopt -s nullglob
    skill_files=(.claude/skills/*/SKILL.md)
    shopt -u nullglob
    if [[ ${#skill_files[@]} -eq 0 ]]; then
      printf '  (none found)   — add skills to .claude/skills/<name>/SKILL.md\n'
    else
      for sf in "${skill_files[@]}"; do
        skill_name=$(basename "$(dirname "$sf")")
        printf '  %-14s %s\n' "$skill_name" "$sf"
      done
    fi
    printf '\n'
    exit 0
  fi

  # Agents are configured — show table
  if [[ "$_FORMAT" == "json" ]]; then
    echo "$agents_json" | jq 'to_entries | map({alias: .key} + .value)'
    exit 0
  fi

  if _plain; then
    # TSV / piped output
    printf "alias\tskill\tmodel\teffort\n"
    echo "$agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // "")] | @tsv'
  else
    # Pretty table: single jq TSV call, then compute widths + render in shell
    local _ag_rows=()
    while IFS=$'\t' read -r _ag_alias _ag_skill _ag_model _ag_effort; do
      _ag_rows+=("${_ag_alias}	${_ag_skill}	${_ag_model}	${_ag_effort}")
    done < <(echo "$agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // "")] | @tsv')

    max_alias=5; max_skill=5; max_model=5
    for _row in "${_ag_rows[@]}"; do
      IFS=$'\t' read -r _ag_alias _ag_skill _ag_model _ag_effort <<< "$_row"
      [[ ${#_ag_alias} -gt $max_alias ]] && max_alias=${#_ag_alias}
      [[ ${#_ag_skill} -gt $max_skill ]] && max_skill=${#_ag_skill}
      [[ ${#_ag_model} -gt $max_model ]] && max_model=${#_ag_model}
    done

    printf '\n'
    printf "  ${CLAUDII_CLR_ACCENT}%-${max_alias}s  %-${max_skill}s  %-${max_model}s  EFFORT${CLAUDII_CLR_RESET}\n" "ALIAS" "SKILL" "MODEL"
    for _row in "${_ag_rows[@]}"; do
      IFS=$'\t' read -r _ag_alias _ag_skill _ag_model _ag_effort <<< "$_row"
      printf "  %-${max_alias}s  %-${max_skill}s  %-${max_model}s  %s\n" "$_ag_alias" "$_ag_skill" "$_ag_model" "$_ag_effort"
    done
    printf '\n'
    printf 'Type the alias to launch. Example: %s\n\n' "${_ag_rows[0]%%	*}"
  fi
}
