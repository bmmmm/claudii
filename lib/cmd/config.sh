# lib/cmd/config.sh — configuration and tool commands (config, agents, search)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_config_usage() {
  cat <<'EOF'
Usage: claudii config [get KEY | set KEY VALUE | reset | export [FILE] | import FILE | theme [NAME]]

Without a subcommand, prints the user config.

  get KEY           print one value (user config, falling back to the defaults)
  set KEY VALUE     write one value (numbers and true/false stay typed)
  reset             overwrite the user config with the defaults
  export [FILE]     copy the config to FILE (stdout without FILE)
  import FILE       replace the config with FILE (a backup is kept)
  theme [NAME]      list the colour themes, or switch to NAME (or "auto")
EOF
}

_cmd_config() {
  _cfg_init
  # Locals: the sourced handler used to leave all of these in the CLI's scope.
  local key value file theme_arg current valid t _known _unknown _bad_agents _reserved

  case "${2:-}" in
    -h|--help)
      _config_usage
      return 0
      ;;
    get)
      key="${3:-}"
      [[ -z "$key" ]] && { echo "Usage: claudii config get <key>" >&2; return 1; }
      # _cfgget: the same user-config-then-defaults lookup (with the jq path
      # quoting that hyphenated keys need) every other reader uses — validates
      # the key itself, so there is one implementation, not two.
      _cfgget "$key" || return 1
      ;;
    set)
      key="${3:-}"
      [[ -z "$key" ]] && { echo "Usage: claudii config set <key> <value>" >&2; return 1; }
      _validate_key "$key" || return 1
      value="${4:-}"
      [[ -z "$value" ]] && { echo "Usage: claudii config set <key> <value>" >&2; return 1; }
      if [[ "$value" =~ ^(0|[1-9][0-9]*)(\.[0-9]+)?$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
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
      file="${3:-}"
      [[ -z "$file" ]] && { echo "Usage: claudii config import <file>" >&2; return 1; }
      [[ -f "$file" ]] || { echo "File not found: $file — check the path" >&2; return 1; }
      jq '.' "$file" >/dev/null 2>&1 || { echo "Not valid JSON: $file — run 'jq . $file' to diagnose" >&2; return 1; }
      jq -e 'type == "object"' "$file" >/dev/null 2>&1 || { echo "config import: $file is not a JSON object — aborting" >&2; return 1; }
      # Validate only known top-level keys (a non-object would make `keys` error → empty → vacuous pass).
      # The known set IS defaults.json (shipped with the install, so always
      # readable) — it never drifts when a new config block ships.
      _known=$(jq -c 'keys' "$DEFAULTS" 2>/dev/null)
      [[ -n "$_known" ]] || { echo "config import: cannot read $DEFAULTS — aborting" >&2; return 1; }
      _unknown=$(jq --argjson known "$_known" 'keys - $known | length' "$file")
      [[ "$_unknown" -eq 0 ]] || { printf "config import: unknown keys in %s — aborting\n" "$file" >&2; return 1; }

      # Validate agent names match allowed pattern
      if jq -e '.agents | type == "object"' "$file" >/dev/null 2>&1; then
        _bad_agents=$(jq -r '.agents | to_entries[] | select(.key | test("^[a-zA-Z_][a-zA-Z0-9_-]*$") | not) | .key' "$file")
        [[ -z "$_bad_agents" ]] || { printf "config import: invalid agent name(s): %s\n" "$_bad_agents" >&2; return 1; }
        # Block reserved names — an agent named claudii/claude/clh/clre would shadow
        # the zsh wrapper at registration time and silently break all subcommands.
        _reserved=$(jq -r '.agents | keys[] | select(. == "claudii" or . == "claude" or . == "clh" or . == "clre")' "$file")
        [[ -z "$_reserved" ]] || { printf "config import: reserved agent name(s): %s — would shadow built-in commands\n" "$_reserved" >&2; return 1; }
      fi
      cp "$CONFIG" "${CONFIG}.bak"
      cp "$file" "$CONFIG"
      echo "Config imported from $file  (Backup: ${CONFIG}.bak)"
      ;;
    theme)
      # claudii config theme         → list available themes
      # claudii config theme <name>  → set theme.name in user config
      theme_arg="${3:-}"
      if [[ -z "$theme_arg" ]]; then
        # List available themes from defaults.json theme_presets
        echo "Available themes:"
        current=$(jq -r '.theme.name // "default"' "$CONFIG" 2>/dev/null)
        # "auto" is no preset: lib/visual.sh resolves it to pastel or default
        # from the terminal background, so it is listed apart from the presets.
        if [[ "$current" == "auto" ]]; then
          echo "  * auto (active — light/dark detected from the terminal)"
        else
          echo "    auto (light/dark detected from the terminal)"
        fi
        jq -r '.theme_presets | keys[]' "$DEFAULTS" 2>/dev/null | sort | while IFS= read -r t; do
          if [[ "$t" == "$current" ]]; then
            echo "  * $t (active)"
          else
            echo "    $t"
          fi
        done
      else
        # Validate that the theme exists in defaults — or is "auto"
        valid=$(jq -r --arg name "$theme_arg" '.theme_presets | has($name)' "$DEFAULTS" 2>/dev/null)
        if [[ "$valid" != "true" && "$theme_arg" != "auto" ]]; then
          echo "Unknown theme: $theme_arg — available: auto, $(jq -r '.theme_presets | keys | join(", ")' "$DEFAULTS" 2>/dev/null)" >&2
          return 1
        fi
        # Set theme.name in user config
        _jq_update "$CONFIG" --arg name "$theme_arg" '.theme.name = $name'
        echo "Theme set to: $theme_arg"
      fi
      ;;
    "")
      echo "User config: $CONFIG"
      echo ""
      jq '.' "$CONFIG"
      ;;
    # Anything else used to fall into the print-everything arm above: a typo
    # such as `config gett` dumped the whole user config and answered 0.
    *)
      _cli_unknown_opt config "$2" '[get|set|reset|export|import|theme]' || return $?
      ;;
  esac
}

_search_usage() {
  cat <<'EOF'
Usage: claudii search [QUERY…] [-- CLAUDE_FLAGS…]

Start Claude Code in the search workspace (search.dir, default ~/search) with
the search model and effort. QUERY becomes the opening prompt; anything after
a bare -- goes to claude untouched (e.g. claudii search -- --continue).
EOF
}

_cmd_search() {
  # Before the exec, so a typo'd flag is rejected rather than handed to claude
  # (it answered whatever claude answered). Flags for claude itself follow `--`.
  local _sa _passthru=0
  local -a _search_args=()
  for _sa in "${@:2}"; do
    if (( _passthru )); then _search_args+=("$_sa"); continue; fi
    case "$_sa" in
      -h|--help) _search_usage; return 0 ;;
      --)        _passthru=1 ;;
      -*)        _cli_unknown_opt search "$_sa" '[QUERY…] [-- CLAUDE_FLAGS…]' || return $? ;;
      *)         _search_args+=("$_sa") ;;
    esac
  done
  _cfg_init
  local search_dir model effort
  search_dir=$(_claudii_search_dir "$(_cfgget search.dir)")

  # Try search.model first, fall back to aliases.clq.model, then to default haiku
  model=$(_cfgget search.model)
  [[ -z "$model" ]] && model=$(_cfgget aliases.clq.model)
  [[ -z "$model" ]] && model="haiku"

  # Try search.effort first, fall back to aliases.clq.effort, then to default xhigh
  effort=$(_cfgget search.effort)
  [[ -z "$effort" ]] && effort=$(_cfgget aliases.clq.effort)
  [[ -z "$effort" ]] && effort="xhigh"

  cd "$search_dir" 2>/dev/null || { echo "claudii: cannot use search directory: $search_dir" >&2; return 1; }
  exec claude --model "$model" --effort "$effort" ${_search_args[@]+"${_search_args[@]}"}
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
      return 0
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
    return 0
  fi

  # Agents are configured — show table
  if [[ "$_FORMAT" == "json" ]]; then
    echo "$agents_json" | jq 'to_entries | map({alias: .key} + .value)'
    return 0
  fi

  if _plain; then
    # TSV / piped output
    printf "alias\tskill\tmodel\teffort\tdescription\n"
    echo "$agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // ""), (.value.description // "")] | @tsv'
  else
    # Pretty table: single jq TSV call, then compute widths + render in shell.
    # Description is the last column — left untruncated; terminal soft-wraps it.
    local _ag_rows=()
    while IFS=$'\t' read -r _ag_alias _ag_skill _ag_model _ag_effort _ag_desc; do
      _ag_rows+=("${_ag_alias}	${_ag_skill}	${_ag_model}	${_ag_effort}	${_ag_desc}")
    done < <(echo "$agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // ""), (.value.description // "")] | @tsv')

    max_alias=5; max_skill=5; max_model=5; max_effort=6
    for _row in "${_ag_rows[@]}"; do
      IFS=$'\t' read -r _ag_alias _ag_skill _ag_model _ag_effort _ag_desc <<< "$_row"
      [[ ${#_ag_alias} -gt $max_alias ]] && max_alias=${#_ag_alias}
      [[ ${#_ag_skill} -gt $max_skill ]] && max_skill=${#_ag_skill}
      [[ ${#_ag_model} -gt $max_model ]] && max_model=${#_ag_model}
      [[ ${#_ag_effort} -gt $max_effort ]] && max_effort=${#_ag_effort}
    done

    printf '\n'
    printf "  ${CLAUDII_CLR_ACCENT}%-${max_alias}s  %-${max_skill}s  %-${max_model}s  %-${max_effort}s  DESCRIPTION${CLAUDII_CLR_RESET}\n" "ALIAS" "SKILL" "MODEL" "EFFORT"
    for _row in "${_ag_rows[@]}"; do
      IFS=$'\t' read -r _ag_alias _ag_skill _ag_model _ag_effort _ag_desc <<< "$_row"
      printf "  %-${max_alias}s  %-${max_skill}s  %-${max_model}s  %-${max_effort}s  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_ag_alias" "$_ag_skill" "$_ag_model" "$_ag_effort" "$_ag_desc"
    done
    printf '\n'
    printf 'Type the alias to launch. Example: %s\n\n' "${_ag_rows[0]%%	*}"
  fi
}
