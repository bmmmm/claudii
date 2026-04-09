# lib/cmd/system.sh — system/control commands
# (on, off, claudestatus, session-dashboard, status, cc-statusline, update, doctor)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_on() {
  _cfg_init
  # Enable all three layers
  _jq_update "$CONFIG" '.statusline.enabled = true | ."session-dashboard".enabled = "on"'
  SETTINGS="${HOME}/.claude/settings.json"
  if [[ -f "$SETTINGS" ]]; then
    if ! jq -e '.statusLine.command == "claudii-sessionline"' "$SETTINGS" >/dev/null 2>&1; then
      _jq_update "$SETTINGS" '. + {"statusLine": {"type": "command", "command": "claudii-sessionline"}}'
    fi
  fi
  echo -e "${CLAUDII_CLR_GREEN}All layers enabled${CLAUDII_CLR_RESET}  (ClaudeStatus · Session Dashboard · CC-Statusline)"
}

_cmd_off() {
  _cfg_init
  # Disable all three layers
  _jq_update "$CONFIG" '.statusline.enabled = false | ."session-dashboard".enabled = "off"'
  SETTINGS="${HOME}/.claude/settings.json"
  if [[ -f "$SETTINGS" ]] && jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    _jq_update "$SETTINGS" 'del(.statusLine)'
  fi
  echo -e "${CLAUDII_CLR_YELLOW}All layers disabled${CLAUDII_CLR_RESET}  (ClaudeStatus · Session Dashboard · CC-Statusline)"
}

_cmd_claudestatus() {
  _cfg_init
  case "${2:-}" in
    on)
      _jq_update "$CONFIG" '.statusline.enabled = true'
      echo -e "${CLAUDII_CLR_GREEN}ClaudeStatus enabled${CLAUDII_CLR_RESET}"
      ;;
    off)
      _jq_update "$CONFIG" '.statusline.enabled = false'
      echo -e "${CLAUDII_CLR_YELLOW}ClaudeStatus disabled${CLAUDII_CLR_RESET}"
      ;;
    "")
      enabled=$(_cfgget statusline.enabled)
      if [[ "$enabled" == "true" ]]; then
        echo -e "ClaudeStatus: ${CLAUDII_CLR_GREEN}on${CLAUDII_CLR_RESET}"
      else
        echo -e "ClaudeStatus: ${CLAUDII_CLR_YELLOW}off${CLAUDII_CLR_RESET}"
      fi
      ;;
    *)
      echo "Usage: claudii claudestatus [on|off] — run 'claudii claudestatus on' or 'claudii claudestatus off'" >&2; exit 1
      ;;
  esac
}

_cmd_session_dashboard() {
  _cfg_init
  case "${2:-}" in
    on)
      _jq_update "$CONFIG" '."session-dashboard".enabled = "on"'
      echo -e "${CLAUDII_CLR_GREEN}Dashboard: on${CLAUDII_CLR_RESET}"
      ;;
    off)
      _jq_update "$CONFIG" '."session-dashboard".enabled = "off"'
      echo -e "${CLAUDII_CLR_YELLOW}Dashboard: off${CLAUDII_CLR_RESET}"
      ;;
    "")
      current=$(_cfgget session-dashboard.enabled)
      [[ -z "$current" ]] && current=$(_cfgget dashboard.enabled)
      current="${current:-off}"
      if [[ "$current" == "off" ]]; then
        echo -e "Session Dashboard: ${CLAUDII_CLR_YELLOW}off${CLAUDII_CLR_RESET}  (claudii session-dashboard on to enable)"
      else
        echo -e "Session Dashboard: ${CLAUDII_CLR_GREEN}on${CLAUDII_CLR_RESET}"
      fi
      ;;
    *)
      echo "Unknown subcommand: ${2} — run 'claudii session-dashboard [on|off]'" >&2; exit 1
      ;;
  esac
}

_cmd_status() {
  _cfg_init
  case "${2:-}" in
    *m|*[0-9])
      interval="${2:-}"
      # Strip trailing 'm' first, then validate numeric before any arithmetic (prevents injection)
      if [[ "$interval" == *m ]]; then
        _int_num="${interval%m}"
      else
        _int_num="$interval"
      fi
      if ! [[ "$_int_num" =~ ^[0-9]+$ ]]; then
        echo "Invalid interval: $interval (minimum 30s) — valid values: 5m, 15m, 30m" >&2; exit 1
      fi
      if [[ "$interval" == *m ]]; then
        seconds=$(( _int_num * 60 ))
      else
        seconds="$_int_num"
      fi
      if (( seconds < 30 )); then
        echo "Invalid interval: $interval (minimum 30s) — valid values: 5m, 15m, 30m" >&2; exit 1
      fi
      _jq_update "$CONFIG" --argjson v "$seconds" '.status.cache_ttl = $v'
      echo "Refresh interval: ${interval} (${seconds}s)"
      ;;
    "")
      cache_file="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models"
      "$CLAUDII_HOME/bin/claudii-status" --quiet || true
      if [[ "$_FORMAT" == "json" ]]; then
        if [[ -f "$cache_file" ]]; then
          jq -Rn '[inputs | select(length > 0) | split("=") | {"model": .[0], "status": .[1]}]' < "$cache_file"
        else
          echo "[]"
        fi
      else
        # Per-model status display
        printf '\n'
        models_cfg=$(_cfgget statusline.models)
        models_cfg="${models_cfg:-opus,sonnet,haiku}"
        IFS=',' read -ra _status_models <<< "$models_cfg"

        if [[ ! -f "$cache_file" ]]; then
          printf '  no cache — run: claudii status 5m\n'
        else
          _status_any_issue=false
          for _sm in "${_status_models[@]}"; do
            _sm="${_sm// /}"
            _sm_state=$(grep "^${_sm}=" "$cache_file" 2>/dev/null | cut -d= -f2 || true)
            _sm_label="$(echo "${_sm:0:1}" | tr '[:lower:]' '[:upper:]')${_sm:1}"
            case "${_sm_state:-unknown}" in
              ok)       _sm_icon="${CLAUDII_CLR_GREEN}${CLAUDII_SYM_OK}${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_GREEN}ok${CLAUDII_CLR_RESET}"       ;;
              degraded) _sm_icon="${CLAUDII_CLR_YELLOW}${CLAUDII_SYM_WARN}${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_YELLOW}degraded${CLAUDII_CLR_RESET}" ; _status_any_issue=true ;;
              down)     _sm_icon="${CLAUDII_CLR_RED}${CLAUDII_SYM_ERROR}${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_RED}down${CLAUDII_CLR_RESET}"     ; _status_any_issue=true ;;
              *)        _sm_icon="${CLAUDII_CLR_DIM}?${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_DIM}unknown${CLAUDII_CLR_RESET}" ;;
            esac
            printf "  %-9s %b %b\n" "$_sm_label" "$_sm_icon" "$_sm_text"
          done

          printf '\n'
          _cache_mtime=0
          if stat -f%m "$cache_file" >/dev/null 2>&1; then
            _cache_mtime=$(stat -f%m "$cache_file")
          else
            _cache_mtime=$(stat -c%Y "$cache_file" 2>/dev/null || echo 0)
          fi
          _now=$(date +%s)
          _cache_age=$(( _now - _cache_mtime ))
          if (( _cache_age < 60 )); then
            _age_str="just now"
          else
            _age_str="$(( _cache_age / 60 ))m ago"
          fi
          _ttl_val=$(_cfgget status.cache_ttl)
          _ttl_val="${_ttl_val:-900}"
          _ttl_min=$(( _ttl_val / 60 ))
          printf "  ${CLAUDII_CLR_DIM}Last check: %s  ·  refreshes every %sm${CLAUDII_CLR_RESET}\n" "$_age_str" "$_ttl_min"
        fi

        # ── Current incidents from unresolved.json (cached by claudii-status) ──
        _inc_cache="${cache_file%/*}/status-unresolved.json"
        if [[ -f "$_inc_cache" ]]; then
          _inc_count=$(jq -r '.incidents | length' "$_inc_cache" 2>/dev/null || echo "0")
          if [[ "$_inc_count" == "0" ]]; then
            printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_OK} No active incidents${CLAUDII_CLR_RESET}\n"
          else
            jq -r '.incidents[] | [.name, .status, (.incident_updates // [] | .[0:3][] | [.status, .body, .created_at] | @tsv)] | @tsv' \
              "$_inc_cache" 2>/dev/null | \
            while IFS=$'\t' read -r _name _status _upd_status _upd_body _upd_time; do
              _status_lc=$(echo "$_status" | tr '[:upper:]' '[:lower:]')
              case "$_status_lc" in
                resolved)                 _ic="${CLAUDII_CLR_GREEN}"  ; _is="${CLAUDII_SYM_OK} Resolved"    ;;
                monitoring)               _ic="${CLAUDII_CLR_YELLOW}" ; _is="${CLAUDII_SYM_MONITORING} Monitoring"    ;;
                investigating|identified) _ic="${CLAUDII_CLR_YELLOW}" ; _is="${CLAUDII_SYM_MONITORING} ${_status}"   ;;
                *)                        _ic="${CLAUDII_CLR_DIM}"    ; _is="${CLAUDII_SYM_INACTIVE} ${_status}"     ;;
              esac
              printf '\n'
              printf "  %b%s%b  %s\n" "$_ic" "$_is" "$CLAUDII_CLR_RESET" "$_name"
            done
            jq -r '.incidents[] | .incident_updates[0:3][] | [.status, .created_at, .body] | @tsv' \
              "$_inc_cache" 2>/dev/null | \
            while IFS=$'\t' read -r _upd_status _upd_time _upd_body; do
              _ts=$(echo "$_upd_time" | sed 's/T/ /; s/\..*//' 2>/dev/null || echo "$_upd_time")
              printf "    ${CLAUDII_CLR_DIM}%-20s${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_BOLD}%-15s${CLAUDII_CLR_RESET}  %s\n" \
                "$_ts" "$_upd_status" "$_upd_body"
            done
          fi
        fi
        printf '\n'
      fi
      ;;
    *)
      echo "Unknown status option: ${2} — run 'claudii status [5m|15m|30m]' to set the refresh interval" >&2; exit 1
      ;;
  esac
}

_cmd_cc_statusline() {
  SETTINGS="${HOME}/.claude/settings.json"
  case "${2:-}" in
    on)
      if [[ ! -f "$SETTINGS" ]]; then
        echo "Error: $SETTINGS not found — run 'claudii update' to re-install, or check https://github.com/bmaingret/claudii" >&2; exit 1
      fi
      if jq -e '.statusLine.command == "claudii-sessionline"' "$SETTINGS" >/dev/null 2>&1; then
        echo -e "${CLAUDII_CLR_CYAN}CC-Statusline already active${CLAUDII_CLR_RESET}"
      else
        _jq_update "$SETTINGS" '. + {"statusLine": {"type": "command", "command": "claudii-sessionline"}}'
        echo -e "${CLAUDII_CLR_GREEN}CC-Statusline enabled${CLAUDII_CLR_RESET}  → restart Claude Code to activate"
      fi
      ;;
    off)
      if [[ ! -f "$SETTINGS" ]]; then
        echo "Error: $SETTINGS not found — run 'claudii update' to re-install, or check https://github.com/bmaingret/claudii" >&2; exit 1
      fi
      if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        _jq_update "$SETTINGS" 'del(.statusLine)'
        echo -e "${CLAUDII_CLR_YELLOW}CC-Statusline disabled${CLAUDII_CLR_RESET}  → restart Claude Code"
      else
        echo "CC-Statusline was not configured"
      fi
      ;;
    "")
      if [[ ! -f "$SETTINGS" ]]; then
        echo "CC-Statusline: not configured  ($SETTINGS missing)"
      elif jq -e '.statusLine.command == "claudii-sessionline"' "$SETTINGS" >/dev/null 2>&1; then
        echo -e "CC-Statusline: ${CLAUDII_CLR_GREEN}active${CLAUDII_CLR_RESET}  ($SETTINGS)"
      elif jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        other=$(jq -r '.statusLine.command // .statusLine' "$SETTINGS")
        echo -e "CC-Statusline: ${CLAUDII_CLR_YELLOW}custom configuration${CLAUDII_CLR_RESET}  ($other)"
      else
        echo "CC-Statusline: not configured"
        echo "  → claudii cc-statusline on  to enable"
      fi
      ;;
    *)
      echo "Usage: claudii cc-statusline [on|off]"; exit 1
      ;;
  esac
}

_cmd_update() {
  if [[ "$CLAUDII_HOME" == "$(brew --prefix 2>/dev/null)"* ]]; then
    echo "claudii: Homebrew install detected"
    brew upgrade claudii
  elif git -C "$CLAUDII_HOME" rev-parse --git-dir >/dev/null 2>&1; then
    echo "claudii: Git install detected"
    git -C "$CLAUDII_HOME" pull --ff-only
  else
    echo "claudii: cannot determine install method — try: brew upgrade claudii  or  cd $CLAUDII_HOME && git pull" >&2
    exit 1
  fi
  printf "${CLAUDII_CLR_GREEN}${CLAUDII_SYM_OK} Updated. Run: claudii restart${CLAUDII_CLR_RESET}\n"
}

_cmd_doctor() {
  _cfg_init

  # Collect check results into parallel arrays: name, status (ok/warn/fail), detail
  declare -a _dc_name _dc_status _dc_detail
  _dc_count=0

  _dc_add() { _dc_name[$_dc_count]="$1"; _dc_status[$_dc_count]="$2"; _dc_detail[$_dc_count]="$3"; _dc_count=$(( _dc_count + 1 )); }

  # 1. Claude Code
  if command -v claude >/dev/null 2>&1; then
    claude_ver=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    _dc_add "claude_code" "ok" "Claude Code $claude_ver"
  else
    _dc_add "claude_code" "fail" "Claude Code not found — install from https://claude.ai/download"
  fi

  # 2. jq
  if command -v jq >/dev/null 2>&1; then
    jq_ver=$(jq --version 2>/dev/null || echo "unknown")
    _dc_add "jq" "ok" "jq $jq_ver"
  else
    _dc_add "jq" "fail" "jq not installed — brew install jq"
  fi

  # 3. CC-Statusline config
  settings="${HOME}/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    _dc_add "cc_statusline" "warn" "CC-Statusline not configured — claudii cc-statusline on"
  elif jq -e '.statusLine.command == "claudii-sessionline"' "$settings" >/dev/null 2>&1; then
    _dc_add "cc_statusline" "ok" "CC-Statusline configured"
  elif jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
    other=$(jq -r '.statusLine.command // "unknown"' "$settings")
    _dc_add "cc_statusline" "warn" "CC-Statusline: other command ($other) — claudii cc-statusline on"
  else
    _dc_add "cc_statusline" "warn" "CC-Statusline not configured — claudii cc-statusline on"
  fi

  # 4. Cache directory
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  if [[ -d "$cache_dir" ]]; then
    cache_count=$(ls -1 "$cache_dir" 2>/dev/null | wc -l | tr -d ' ')
    _dc_add "cache" "ok" "Cache directory exists ($cache_count files)"
  else
    _dc_add "cache" "warn" "Cache directory missing — will be created on first status check"
  fi

  # 4b. Session cache GC — stale files (ppid dead AND age > 24h)
  _dc_now=$(date +%s)
  _dc_stale=0
  for _dc_sf in "$cache_dir"/session-*; do
    [[ -f "$_dc_sf" ]] || continue
    _dc_sf_ppid=$(grep '^ppid=' "$_dc_sf" 2>/dev/null | cut -d= -f2 || true)
    _dc_sf_mt=$(stat -f%m "$_dc_sf" 2>/dev/null || stat -c%Y "$_dc_sf" 2>/dev/null || echo 0)
    (( _dc_now - _dc_sf_mt < 86400 )) && continue
    [[ -n "$_dc_sf_ppid" ]] && kill -0 "$_dc_sf_ppid" 2>/dev/null && continue
    (( ++_dc_stale ))
  done
  if (( _dc_stale > 0 )); then
    _dc_s=""; (( _dc_stale != 1 )) && _dc_s="s"
    _dc_add "session_gc" "info" "Session cache: ${_dc_stale} stale file${_dc_s}, GC runs on next shell load"
  fi

  # 5. Completions
  comp_dir="$CLAUDII_HOME/completions"
  if [[ -f "$comp_dir/_claudii" ]]; then
    _dc_add "completions" "ok" "Completions file present ($comp_dir)"
  else
    _dc_add "completions" "fail" "Completions not found — add to .zshrc: fpath+=($comp_dir)"
  fi

  # 6. Plugin loaded
  if [[ -n "${CLAUDII_HOME:-}" ]]; then
    _dc_add "plugin" "ok" "Plugin loaded (CLAUDII_HOME=$CLAUDII_HOME)"
  else
    _dc_add "plugin" "warn" "CLAUDII_HOME not set — source claudii.plugin.zsh in .zshrc"
  fi

  # 7. Version
  _dc_add "version" "ok" "claudii v$VERSION"

  if [[ "$_FORMAT" == "json" ]]; then
    _json_arr="["
    _first=1
    for (( i=0; i<_dc_count; i++ )); do
      [[ "$_first" -eq 0 ]] && _json_arr+=","
      _json_arr+=$(jq -n --arg name "${_dc_name[$i]}" --arg status "${_dc_status[$i]}" --arg detail "${_dc_detail[$i]}" \
        '{"check": $name, "status": $status, "detail": $detail}')
      _first=0
    done
    _json_arr+="]"
    echo "$_json_arr" | jq .
    exit 0
  fi

  ok="${CLAUDII_CLR_GREEN}${CLAUDII_SYM_OK}${CLAUDII_CLR_RESET}"
  warn="${CLAUDII_CLR_YELLOW}${CLAUDII_SYM_WARN}${CLAUDII_CLR_RESET}"
  fail="${CLAUDII_CLR_RED}${CLAUDII_SYM_ERROR}${CLAUDII_CLR_RESET}"
  info="${CLAUDII_CLR_DIM}·${CLAUDII_CLR_RESET}"
  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii doctor${CLAUDII_CLR_RESET}\n\n"
  for (( i=0; i<_dc_count; i++ )); do
    case "${_dc_status[$i]}" in
      ok)   icon="$ok"   ;;
      warn) icon="$warn" ;;
      info) icon="$info" ;;
      *)    icon="$fail" ;;
    esac
    printf "  %b %s\n" "$icon" "${_dc_detail[$i]}"
  done
  printf '\n'
}
