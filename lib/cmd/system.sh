# lib/cmd/system.sh — system/control commands
# (on, off, claudestatus, dashboard, status, cc-statusline, update, watch, doctor)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_on() {
  _cfg_init
  # Enable all three layers
  echo "$(jq '.statusline.enabled = true | .dashboard.enabled = "on"' "$CONFIG")" > "$CONFIG"
  SETTINGS="${HOME}/.claude/settings.json"
  if [[ -f "$SETTINGS" ]]; then
    if ! jq -e '.statusLine.command == "claudii-sessionline"' "$SETTINGS" >/dev/null 2>&1; then
      echo "$(jq '. + {"statusLine": {"type": "command", "command": "claudii-sessionline"}}' "$SETTINGS")" > "$SETTINGS"
    fi
  fi
  echo -e "${CLAUDII_CLR_GREEN}All layers enabled${CLAUDII_CLR_RESET}  (ClaudeStatus · Dashboard · CC-Statusline)"
}

_cmd_off() {
  _cfg_init
  # Disable all three layers
  echo "$(jq '.statusline.enabled = false | .dashboard.enabled = "off"' "$CONFIG")" > "$CONFIG"
  SETTINGS="${HOME}/.claude/settings.json"
  if [[ -f "$SETTINGS" ]] && jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    echo "$(jq 'del(.statusLine)' "$SETTINGS")" > "$SETTINGS"
  fi
  echo -e "${CLAUDII_CLR_YELLOW}All layers disabled${CLAUDII_CLR_RESET}  (ClaudeStatus · Dashboard · CC-Statusline)"
}

_cmd_claudestatus() {
  _cfg_init
  case "${2:-}" in
    on)
      echo "$(jq '.statusline.enabled = true' "$CONFIG")" > "$CONFIG"
      echo -e "${CLAUDII_CLR_GREEN}ClaudeStatus aktiviert${CLAUDII_CLR_RESET}"
      ;;
    off)
      echo "$(jq '.statusline.enabled = false' "$CONFIG")" > "$CONFIG"
      echo -e "${CLAUDII_CLR_YELLOW}ClaudeStatus deaktiviert${CLAUDII_CLR_RESET}"
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
      echo "Usage: claudii claudestatus [on|off]"; exit 1
      ;;
  esac
}

_cmd_dashboard() {
  _cfg_init
  case "${2:-}" in
    on)
      echo "$(jq '.dashboard.enabled = "on"' "$CONFIG")" > "$CONFIG"
      echo -e "${CLAUDII_CLR_GREEN}Dashboard: on${CLAUDII_CLR_RESET}"
      ;;
    off)
      echo "$(jq '.dashboard.enabled = "off"' "$CONFIG")" > "$CONFIG"
      echo -e "${CLAUDII_CLR_YELLOW}Dashboard: off${CLAUDII_CLR_RESET}"
      ;;
    "")
      current=$(_cfgget dashboard.enabled)
      current="${current:-off}"
      if [[ "$current" == "off" ]]; then
        echo -e "Dashboard: ${CLAUDII_CLR_YELLOW}off${CLAUDII_CLR_RESET}  (claudii dashboard on to enable)"
      else
        echo -e "Dashboard: ${CLAUDII_CLR_GREEN}on${CLAUDII_CLR_RESET}"
      fi
      ;;
    *)
      echo "Unknown subcommand: ${2} — run 'claudii dashboard [on|off]'" >&2; exit 1
      ;;
  esac
}

_cmd_status() {
  _cfg_init
  case "${2:-}" in
    *m|*[0-9])
      interval="${2:-}"
      [[ "$interval" == *m ]] && seconds=$(( ${interval%m} * 60 )) || seconds="$interval"
      if ! [[ "$seconds" =~ ^[0-9]+$ ]] || (( seconds < 30 )); then
        echo "Ungültiges Intervall: $interval (mindestens 30s)"; exit 1
      fi
      echo "$(jq --argjson v "$seconds" '.status.cache_ttl = $v' "$CONFIG")" > "$CONFIG"
      echo "Refresh-Intervall: ${interval} (${seconds}s)"
      ;;
    "")
      cache_file="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/status-models"
      rm -f "$cache_file"
      "$CLAUDII_HOME/bin/claudii-status" --quiet
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
          for _sm in "${_status_models[@]}"; do
            _sm="${_sm// /}"
            _sm_state=$(grep "^${_sm}=" "$cache_file" 2>/dev/null | cut -d= -f2)
            _sm_label="$(echo "${_sm:0:1}" | tr '[:lower:]' '[:upper:]')${_sm:1}"
            case "${_sm_state:-unknown}" in
              ok)       _sm_icon="${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_GREEN}ok${CLAUDII_CLR_RESET}"       ;;
              degraded) _sm_icon="${CLAUDII_CLR_YELLOW}⚠${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_YELLOW}degraded${CLAUDII_CLR_RESET}" ;;
              down)     _sm_icon="${CLAUDII_CLR_RED}✗${CLAUDII_CLR_RESET}" ; _sm_text="${CLAUDII_CLR_RED}down${CLAUDII_CLR_RESET}"     ;;
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

        # ── Current incident from status.claude.com RSS ────────────────
        printf '\n'
        _inc_rss_url=$(_cfgget status.rss_url)
        _inc_rss_url="${_inc_rss_url:-https://status.claude.com/history.rss}"
        _inc_rss=$(curl -sf --max-time 8 "$_inc_rss_url" 2>/dev/null || true)
        if [[ -n "$_inc_rss" ]]; then
          # Extract first <item> (most recent incident)
          _inc_item=$(echo "$_inc_rss" | awk '
            /<item/    { p=1; buf="" }
            p          { buf = buf $0 "\n" }
            /<\/item>/ { if (p) { printf "%s", buf; p=0; exit } }
          ')
          if [[ -n "$_inc_item" ]]; then
            _inc_title=$(echo "$_inc_item" | sed -n 's/.*<title[^>]*>\(.*\)<\/title>.*/\1/p' | head -1 | \
              sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&apos;/'"'"'/g; s/&quot;/"/g')
            # Extract description (collapse newlines for multi-line CDATA)
            _inc_desc=$(printf '%s' "$_inc_item" | tr '\n' '\001' | \
              sed 's/.*<description[^>]*>\(.*\)<\/description>.*/\1/' | \
              tr '\001' '\n' | \
              sed 's/<!\[CDATA\[//g; s/\]\]>//g' | \
              sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&apos;/'"'"'/g; s/&quot;/"/g')
            # Most recent status = first <strong> tag in description
            _inc_curstat=$(echo "$_inc_desc" | sed -n 's/.*<strong>\([^<]*\)<\/strong>.*/\1/p' | head -1)
            if [[ -n "$_inc_title" ]]; then
              case "${_inc_curstat,,}" in
                resolved)                 _ic="${CLAUDII_CLR_GREEN}"  ; _is="✓ Resolved"     ;;
                monitoring)               _ic="${CLAUDII_CLR_YELLOW}" ; _is="◎ Monitoring"   ;;
                investigating|identified) _ic="${CLAUDII_CLR_RED}"    ; _is="● Investigating" ;;
                *)                        _ic="${CLAUDII_CLR_DIM}"    ; _is="○"              ;;
              esac
              printf "  %b%s%b  %s\n" "$_ic" "$_is" "$CLAUDII_CLR_RESET" "$_inc_title"
              printf '\n'
              # Parse individual updates: each <p> has date + status + message
              printf '%s\n' "$_inc_desc" | tr '\n' ' ' | sed 's/<\/p>/\n/g' | \
              while IFS= read -r _para; do
                _ptime=$(echo "$_para" | sed -n 's/.*<small>\([^<]*\)<\/small>.*/\1/p')
                _pstat=$(echo "$_para" | sed -n 's/.*<strong>\([^<]*\)<\/strong>.*/\1/p')
                _pmsg=$(echo "$_para" | sed 's/.*<\/strong>[[:space:]]*-[[:space:]]*//' | \
                  sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/  */ /g')
                [[ -z "$_pstat" ]] && continue
                printf "    ${CLAUDII_CLR_DIM}%-18s${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_BOLD}%-15s${CLAUDII_CLR_RESET}  %s\n" \
                  "${_ptime}" "$_pstat" "$_pmsg"
              done
              printf '\n'
            fi
          fi
        fi
        printf '\n'
      fi
      ;;
    *)
      echo "Unbekannte status-Option: ${2}"
      echo "Usage: claudii status [5m|15m|30m]"; exit 1
      ;;
  esac
}

_cmd_cc_statusline() {
  SETTINGS="${HOME}/.claude/settings.json"
  case "${2:-}" in
    on)
      if [[ ! -f "$SETTINGS" ]]; then
        echo "Fehler: $SETTINGS nicht gefunden — ist Claude Code installiert?"; exit 1
      fi
      if jq -e '.statusLine.command == "claudii-sessionline"' "$SETTINGS" >/dev/null 2>&1; then
        echo -e "${CLAUDII_CLR_CYAN}CC-Statusline bereits aktiv${CLAUDII_CLR_RESET}"
      else
        echo "$(jq '. + {"statusLine": {"type": "command", "command": "claudii-sessionline"}}' "$SETTINGS")" > "$SETTINGS"
        echo -e "${CLAUDII_CLR_GREEN}CC-Statusline aktiviert${CLAUDII_CLR_RESET}  → Claude Code neu starten zum Aktivieren"
      fi
      ;;
    off)
      if [[ ! -f "$SETTINGS" ]]; then
        echo "Fehler: $SETTINGS nicht gefunden"; exit 1
      fi
      if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        echo "$(jq 'del(.statusLine)' "$SETTINGS")" > "$SETTINGS"
        echo -e "${CLAUDII_CLR_YELLOW}CC-Statusline deaktiviert${CLAUDII_CLR_RESET}  → Claude Code neu starten"
      else
        echo "CC-Statusline war nicht konfiguriert"
      fi
      ;;
    "")
      if [[ ! -f "$SETTINGS" ]]; then
        echo "CC-Statusline: nicht konfiguriert  ($SETTINGS fehlt)"
      elif jq -e '.statusLine.command == "claudii-sessionline"' "$SETTINGS" >/dev/null 2>&1; then
        echo -e "CC-Statusline: ${CLAUDII_CLR_GREEN}aktiv${CLAUDII_CLR_RESET}  ($SETTINGS)"
      elif jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        other=$(jq -r '.statusLine.command // .statusLine' "$SETTINGS")
        echo -e "CC-Statusline: ${CLAUDII_CLR_YELLOW}andere Konfiguration${CLAUDII_CLR_RESET}  ($other)"
      else
        echo "CC-Statusline: nicht konfiguriert"
        echo "  → claudii cc-statusline on  zum Aktivieren"
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
    echo "claudii: cannot determine install method"
    echo "  Homebrew: brew upgrade claudii"
    echo "  Git:      cd $CLAUDII_HOME && git pull"
    exit 1
  fi
  printf "${CLAUDII_CLR_GREEN}✓ Updated. Run: claudii restart${CLAUDII_CLR_RESET}\n"
}

_cmd_watch() {
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  pid_file="$cache_dir/watch.pid"

  _watch_notify() {
    local title="claudii watch" msg="$1"
    if command -v terminal-notifier >/dev/null 2>&1; then
      terminal-notifier -title "$title" -message "$msg" >/dev/null 2>&1
    else
      osascript -e "display notification \"$msg\" with title \"$title\"" >/dev/null 2>&1
    fi
    local sound volume
    _cfg_init
    sound=$(_cfgget watch.sound 2>/dev/null || true)
    volume=$(_cfgget watch.volume 2>/dev/null || true)
    if [[ -n "$sound" && -f "$sound" ]]; then
      ( afplay -v "$(awk "BEGIN { printf \"%.2f\", ${volume:-50}/100 }")" "$sound" & ) 2>/dev/null
    fi
  }

  _watch_loop() {
    local cache_dir="$1" pid_file="$2"
    local last_notified=0

    while true; do
      sleep 60
      local now
      now=$(date +%s)

      for sf in "$cache_dir"/session-*; do
        [[ -f "$sf" ]] || continue
        local reset_ts=""
        while IFS='=' read -r key val; do
          [[ "$key" == "reset_5h" ]] && reset_ts="$val"
        done < "$sf"

        [[ -z "$reset_ts" || "$reset_ts" == "0" ]] && continue
        # Rate limit has reset and we haven't notified for this timestamp yet
        if (( now >= reset_ts && reset_ts != last_notified )); then
          _watch_notify "5h rate limit reset — Claude is ready"
          last_notified="$reset_ts"
          break
        fi
      done
    done
  }

  case "${2:-start}" in
    start)
      [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
      # Check if already running
      if [[ -f "$pid_file" ]]; then
        existing_pid=$(<"$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
          echo "claudii watch already running (PID $existing_pid)"
          exit 0
        fi
      fi
      # Export functions needed in subshell
      export -f _watch_notify _watch_loop 2>/dev/null || true
      ( _watch_loop "$cache_dir" "$pid_file" &>/dev/null & echo $! > "$pid_file" ) &>/dev/null
      disown %% 2>/dev/null || true
      sleep 0.2
      if [[ -f "$pid_file" ]]; then
        watcher_pid=$(<"$pid_file")
        echo "claudii watch started (PID $watcher_pid)"
      else
        echo "claudii watch started"
      fi
      ;;
    stop)
      if [[ -f "$pid_file" ]]; then
        watcher_pid=$(<"$pid_file")
        if kill -0 "$watcher_pid" 2>/dev/null; then
          kill "$watcher_pid" 2>/dev/null
          rm -f "$pid_file"
          echo "claudii watch stopped (PID $watcher_pid)"
        else
          rm -f "$pid_file"
          echo "claudii watch was not running (stale PID file removed)"
        fi
      else
        echo "claudii watch is not running"
      fi
      ;;
    status)
      if [[ -f "$pid_file" ]]; then
        watcher_pid=$(<"$pid_file")
        if kill -0 "$watcher_pid" 2>/dev/null; then
          echo -e "claudii watch: ${CLAUDII_CLR_GREEN}running${CLAUDII_CLR_RESET} (PID $watcher_pid)"
        else
          rm -f "$pid_file"
          echo "claudii watch: not running (stale PID file removed)"
        fi
      else
        echo "claudii watch: not running"
      fi
      ;;
    test)
      _watch_notify "claudii watch is active"
      echo "claudii watch: test notification sent"
      ;;
    volume)
      _cfg_init
      if [[ -z "${3:-}" ]]; then
        val=$(_cfgget watch.volume)
        [[ -z "$val" ]] && val="50"
        echo "watch.volume: $val"
      else
        vol="${3}"
        if ! [[ "$vol" =~ ^[0-9]+$ ]] || (( vol < 0 || vol > 100 )); then
          echo "Invalid volume: $vol (must be 0-100)"; exit 1
        fi
        echo "$(jq --argjson v "$vol" '.watch.volume = $v' "$CONFIG")" > "$CONFIG"
        echo "watch.volume: $vol"
      fi
      ;;
    sound)
      _cfg_init
      if [[ -z "${3:-}" ]]; then
        val=$(_cfgget watch.sound)
        if [[ -z "$val" ]]; then
          echo "watch.sound: (default)"
        else
          echo "watch.sound: $val"
        fi
      elif [[ "${3}" == "default" ]]; then
        echo "$(jq '.watch.sound = ""' "$CONFIG")" > "$CONFIG"
        echo "watch.sound: (default)"
      else
        sound_file="${3}"
        [[ -f "$sound_file" ]] || { echo "File not found: $sound_file"; exit 1; }
        echo "$(jq --arg v "$sound_file" '.watch.sound = $v' "$CONFIG")" > "$CONFIG"
        echo "watch.sound: $sound_file"
      fi
      ;;
    *)
      echo "Usage: claudii watch [start|stop|status|test|volume|sound]"; exit 1
      ;;
  esac
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
    _dc_sf_ppid=$(grep '^ppid=' "$_dc_sf" 2>/dev/null | cut -d= -f2)
    _dc_sf_mt=$(stat -f%m "$_dc_sf" 2>/dev/null || stat -c%Y "$_dc_sf" 2>/dev/null || echo 0)
    (( _dc_now - _dc_sf_mt < 86400 )) && continue
    [[ -n "$_dc_sf_ppid" ]] && kill -0 "$_dc_sf_ppid" 2>/dev/null && continue
    (( _dc_stale++ ))
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

  ok="${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET}"
  warn="${CLAUDII_CLR_YELLOW}⚠${CLAUDII_CLR_RESET}"
  fail="${CLAUDII_CLR_RED}✗${CLAUDII_CLR_RESET}"
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
