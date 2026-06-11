# lib/cmd/overview.sh — claudii bare overview (Account · Agents · Services · Activity · Sessions)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

# Normalize model identifier to canonical short form (Opus/Sonnet/Haiku); echoes input on no match.
_norm_model_short() {
  case "$1" in
    *[Oo]pus*)   echo "Opus"   ;;
    *[Ss]onnet*) echo "Sonnet" ;;
    *[Hh]aiku*)  echo "Haiku"  ;;
    *)           echo "$1"     ;;
  esac
}


_cmd_default() {
  # Smart account overview: Sessions · Account · Agents · Services
  _cfg_init
  _live_pids_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  now=$(date +%s); _NOW="$now"

  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_ACCENT}v%s${CLAUDII_CLR_RESET}\n" "$VERSION"
  printf '\n'

  # ── Gather session data ────────────────────────────────────────────
  _session_files "$cache_dir"
  _ov_files=("${_SESSION_FILES[@]+"${_SESSION_FILES[@]}"}")

  _ov_acct_5h="" _ov_acct_7d="" _ov_acct_reset="" _ov_acct_7d_start="" _ov_acct_reset_7d="" _ov_acct_mt=0
  _ov_today_cost=0 _ov_today_count=0 _ov_stale=0
  _ov_next_cron=0 _ov_total_bg=0
  # Calendar-midnight cutoff for "today" (not rolling 24h) — see _midnight_epoch.
  _ov_cutoff=$(_midnight_epoch)
  _ov_any_session=0
  _ov_active_count=0 _ov_inactive_count=0

  if [[ ${#_ov_files[@]} -gt 0 ]]; then
    for _ov_f in "${_ov_files[@]}"; do
      _parse_session_cache "$_ov_f"

      # Skip if no model (corrupt/empty file)
      [[ -z "$_PSC_model" ]] && continue
      _ov_any_session=1

      # Track freshest rate-limit data (from most-recently-modified file)
      if (( _PSC_mtime > _ov_acct_mt )) && [[ -n "$_PSC_rate_5h" ]]; then
        _ov_acct_mt=$_PSC_mtime
        _ov_acct_5h="$_PSC_rate_5h"
        _ov_acct_7d="$_PSC_rate_7d"
        _ov_acct_reset="$_PSC_reset_5h"
        _ov_acct_reset_7d="$_PSC_reset_7d"
        _ov_acct_7d_start="$_PSC_rate_7d_start"
      fi

      # Today's cost accumulation — fallback only, used when no history exists
      # (overridden by the history-delta computation after this loop).
      if (( _PSC_mtime >= _ov_cutoff )); then
        _ov_today_count=$(( _ov_today_count + 1 ))
        if [[ -n "$_PSC_cost" && "$_PSC_cost" != "0" ]]; then
          _ov_today_cost=$(awk -v a="$_ov_today_cost" -v b="$_PSC_cost" 'BEGIN{print a+b}')
        fi
      fi

      # Count active vs inactive; count stale (dead ppid, age > 24h) for GC hint
      if [[ "$_PSC_is_active" -eq 1 ]]; then
        (( ++_ov_active_count ))
      else
        (( ++_ov_inactive_count ))
        if (( _PSC_age >= 86400 )); then
          if [[ -z "$_PSC_ppid" ]] || ! kill -0 "$_PSC_ppid" 2>/dev/null; then
            (( ++_ov_stale ))
          fi
        fi
      fi

      # Cron summary: track earliest future next_cron_at across all sessions
      if [[ "$_PSC_cron" =~ ^[0-9]+$ && "$_PSC_cron" != "0" ]]; then
        _ov_cron_rem=$(( _PSC_cron - now ))
        if (( _ov_cron_rem > 0 )); then
          if (( _ov_next_cron == 0 || _PSC_cron < _ov_next_cron )); then
            _ov_next_cron=$_PSC_cron
          fi
        fi
      fi

      # bg_tasks total across all sessions
      if [[ "$_PSC_bg_tasks" =~ ^[0-9]+$ ]]; then
        _ov_total_bg=$(( _ov_total_bg + _PSC_bg_tasks ))
      fi
    done
  fi

  # ── Today's cost from history deltas ──────────────────────────────
  # Same per-session increment attribution as `claudii cost`, so the overview
  # and the cost command agree (the session-cache sum above double-counts
  # multi-day sessions: cumulative cost keyed by file mtime). Only the files
  # that can hold today's rows are scanned (legacy history.tsv + current
  # month) — a session spanning a month boundary loses its prior-month
  # baseline on the 1st, which matches first-row-counts-as-spend semantics.
  # Session count = distinct SIDs with spend today (matches `claudii cost`).
  _ov_hist_files=()
  [[ -s "$cache_dir/history.tsv" ]] && _ov_hist_files+=("$cache_dir/history.tsv")
  _ov_hist_month="$cache_dir/history-$(date '+%Y-%m').tsv"
  [[ -s "$_ov_hist_month" ]] && _ov_hist_files+=("$_ov_hist_month")
  if [[ ${#_ov_hist_files[@]} -gt 0 ]]; then
    _ov_tz=$(_tz_offset_secs)
    _ov_today_hist=$(awk -F'\t' -v tz_offset="${_ov_tz:-0}" -v today="$(date '+%Y-%m-%d')" "
$(<"$CLAUDII_HOME/lib/epoch_to_date.awk")
"'
      NF < 6 { next }
      $1 == "timestamp" || $1 == "" || $6 == "" { next }
      {
        ts = $1 + 0; if (ts == 0) next
        cost = $3 + 0; sid = $6
        cinc = 0
        if (sid in base) {
          prev = base[sid]
          if (cost > prev)            cinc = cost - prev
          else if (cost < prev * 0.5) cinc = cost   # genuine reset (compaction)
        } else cinc = cost
        base[sid] = cost
        if (cinc > 0 && epoch_to_date(ts) == today) { total += cinc; seen[sid] = 1 }
      }
      END { n = 0; for (s in seen) n++; printf "%.4f %d", total, n }
    ' "${_ov_hist_files[@]}" 2>/dev/null)
    if [[ "$_ov_today_hist" == *" "* ]]; then
      _ov_today_cost="${_ov_today_hist% *}"
      _ov_today_count="${_ov_today_hist##* }"
    fi
  fi

  # ── Account ───────────────────────────────────────────────────────
  printf '\n'
  if [[ -n "$_ov_acct_5h" ]]; then
    printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Account${CLAUDII_CLR_RESET}\n"

    # rate_display: "remaining" flips % to 100-X; color thresholds stay on used%.
    # _rate_mark gives a visible cue (↓) for the inverted mode.
    _rate_disp_init

    _ov_5h_int=${_ov_acct_5h%.*}
    _ov_5h_disp=$_ov_5h_int
    [[ "$_RATE_DISP" == "remaining" ]] && _ov_5h_disp=$(( 100 - _ov_5h_int ))
    # 5h urgency color: < 50% green, 50-79% yellow, >= 80% red
    if (( _ov_5h_int >= 80 )); then
      _ov_5h_clr="${CLAUDII_CLR_RED}"
    elif (( _ov_5h_int >= 50 )); then
      _ov_5h_clr="${CLAUDII_CLR_YELLOW}"
    else
      _ov_5h_clr="${CLAUDII_CLR_GREEN}"
    fi
    _ov_acct_line="    5h${_rate_mark}: ${_ov_5h_clr}${_ov_5h_disp}%${CLAUDII_CLR_RESET}"
    # Reset countdown with urgency color
    if [[ -n "$_ov_acct_reset" && "$_ov_acct_reset" != "0" ]]; then
      _ov_remaining=$(( _ov_acct_reset - now ))
      if (( _ov_remaining > 0 )); then
        _ov_rem_min=$(( _ov_remaining / 60 ))
        if (( _ov_rem_min < 10 )); then
          _ov_reset_clr="${CLAUDII_CLR_RED}"
        elif (( _ov_rem_min <= 60 )); then
          _ov_reset_clr="${CLAUDII_CLR_YELLOW}"
        else
          _ov_reset_clr="${CLAUDII_CLR_DIM}"
        fi
        _ov_acct_line+=" ${_ov_reset_clr}↺${_ov_rem_min}m${CLAUDII_CLR_RESET}"
      fi
    fi
    if [[ -n "$_ov_acct_7d" ]]; then
      _ov_7d_int=${_ov_acct_7d%.*}
      _ov_7d_disp=$_ov_7d_int
      [[ "$_RATE_DISP" == "remaining" ]] && _ov_7d_disp=$(( 100 - _ov_7d_int ))
      # 7d urgency color: < 50% green, 50-79% yellow, >= 80% red (based on used %)
      if (( _ov_7d_int >= 80 )); then
        _ov_7d_clr="${CLAUDII_CLR_RED}"
      elif (( _ov_7d_int >= 50 )); then
        _ov_7d_clr="${CLAUDII_CLR_YELLOW}"
      else
        _ov_7d_clr="${CLAUDII_CLR_GREEN}"
      fi
      _ov_acct_line+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} 7d${_rate_mark}: ${_ov_7d_clr}${_ov_7d_disp}%${CLAUDII_CLR_RESET}"
      # 7d delta — sign flips in remaining mode (usage +12% = remaining −12%)
      if [[ -n "$_ov_acct_7d_start" ]]; then
        _ov_delta=$(( _ov_7d_int - ${_ov_acct_7d_start%.*} ))
        _ov_delta_disp=$_ov_delta
        [[ "$_RATE_DISP" == "remaining" ]] && _ov_delta_disp=$(( -_ov_delta ))
        if (( _ov_delta > 0 )); then
          # Sign computed as a separate conditional statement: the inline
          # form `$( (( _ov_delta_disp > 0 )) && echo "+" )` propagates the
          # arithmetic exit code (1 when the test is false) into the `+=`
          # assignment, which `set -e` in bin/claudii then aborts on. That
          # killed the overview right after the Account header in
          # `rate_display=remaining` mode whenever the 7d delta was positive
          # (negation makes _ov_delta_disp negative → test fails → exit 1).
          _ov_sign=""
          (( _ov_delta_disp > 0 )) && _ov_sign="+"
          _ov_acct_line+=" ${CLAUDII_CLR_DIM}(${_ov_sign}${_ov_delta_disp}%)${CLAUDII_CLR_RESET}"
        fi
      fi
      # 7d reset countdown (shared cascade: m / h+m / d+h, zero units suppressed)
      if [[ -n "$_ov_acct_reset_7d" && "$_ov_acct_reset_7d" != "0" ]]; then
        _fmt_rel $(( _ov_acct_reset_7d - now ))
        [[ -n "$_REL_FMT" ]] && _ov_acct_line+=" ${CLAUDII_CLR_DIM}↺${_REL_FMT}${CLAUDII_CLR_RESET}"
      fi
    fi
    # Today's cost with accent color, and session count
    if (( _ov_today_count > 0 )); then
      _ov_today_fmt=$(printf '%.2f' "$_ov_today_cost")
      _ov_s=""; (( _ov_today_count != 1 )) && _ov_s="s"
      _ov_acct_line+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}\$${_ov_today_fmt}${CLAUDII_CLR_RESET} today (${_ov_today_count} session${_ov_s})"
    fi
    printf '%s\n' "$_ov_acct_line"
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Account                         rate limits appear after first session${CLAUDII_CLR_RESET}\n"
  fi

  # ── Agents ────────────────────────────────────────────────────────
  printf '\n'
  _ov_agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$CONFIG" 2>/dev/null)
  [[ -z "$_ov_agents_json" ]] && _ov_agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$DEFAULTS" 2>/dev/null)

  if [[ -n "$_ov_agents_json" ]]; then
    printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Agents${CLAUDII_CLR_RESET}\n"
    local _a_D=$'\x1f'
    while IFS="$_a_D" read -r _a_alias _a_skill _a_model _a_effort; do
      local _a_spec="${_a_model}"
      [[ -n "$_a_effort" ]] && _a_spec="${_a_model}/${_a_effort}"
      printf "    %-8s  %-12s  %s\n" "$_a_alias" "$_a_skill" "$_a_spec"
    done < <(echo "$_ov_agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // "")] | join("\u001f")')
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Agents                          claudii agents to configure${CLAUDII_CLR_RESET}\n"
  fi

  # ── Services ──────────────────────────────────────────────────────
  printf '\n'
  _ov_cs_en=$(_cfgget statusline.enabled)
  _ov_dash_en=$(_cfgget session-dashboard.enabled)
  # Migration fallback: read legacy key if new one absent
  [[ -z "$_ov_dash_en" ]] && _ov_dash_en=$(_cfgget dashboard.enabled)
  [[ -z "$_ov_dash_en" ]] && _ov_dash_en="off"
  _ov_sl_settings="${HOME}/.claude/settings.json"
  _ov_sl_on=0
  # _cc_statusline_connected — also matches wrapper chains (cc-insomnii, user scripts)
  [[ -f "$_ov_sl_settings" ]] && _cc_statusline_connected "$(jq -r '.statusLine.command // ""' "$_ov_sl_settings" 2>/dev/null)" && _ov_sl_on=1
  _ov_svc_any=0
  [[ "$_ov_cs_en" == "true" ]]   && _ov_svc_any=1
  [[ "$_ov_dash_en" != "off" ]]  && _ov_svc_any=1
  (( _ov_sl_on ))                && _ov_svc_any=1

  if (( _ov_svc_any )); then
    printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Services${CLAUDII_CLR_RESET}\n"
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Services${CLAUDII_CLR_RESET}\n"
  fi

  # ClaudeStatus — with inline model health when on
  if [[ "$_ov_cs_en" == "true" ]]; then
    _ov_model_health=""
    _ov_status_cache="$cache_dir/status-models"
    if [[ -f "$_ov_status_cache" ]]; then
      _ov_health_str=""
      while IFS='=' read -r _om _os; do
        [[ -z "$_om" || "$_om" == _* ]] && continue
        _om_cap=$(_norm_model_short "$_om")
        case "$_os" in
          ok)       _ov_health_str+="${CLAUDII_CLR_GREEN}${_om_cap} ${CLAUDII_SYM_OK}${CLAUDII_CLR_RESET} " ;;
          degraded) _ov_health_str+="${CLAUDII_CLR_YELLOW}${_om_cap} ${CLAUDII_SYM_WARN}${CLAUDII_CLR_RESET} " ;;
          down)     _ov_health_str+="${CLAUDII_CLR_RED}${_om_cap} ${CLAUDII_SYM_ERROR}${CLAUDII_CLR_RESET} " ;;
        esac
      done < "$_ov_status_cache"
      [[ -n "$_ov_health_str" ]] && _ov_model_health="  ${CLAUDII_CLR_DIM}[${CLAUDII_CLR_RESET}${_ov_health_str% }${CLAUDII_CLR_DIM}]${CLAUDII_CLR_RESET}"
    fi
    printf "    ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ClaudeStatus%s\n" "$_ov_model_health"
  else
    printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} ClaudeStatus%-20s claudii on${CLAUDII_CLR_RESET}\n" ""
  fi

  # Session Dashboard
  if [[ "$_ov_dash_en" != "off" ]]; then
    printf "    ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} Dashboard\n"
  else
    printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Dashboard%-23s claudii dashboard on${CLAUDII_CLR_RESET}\n" ""
  fi

  # CC-Statusline
  if (( _ov_sl_on )); then
    printf "    ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} CC-Statusline\n"
  else
    printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} CC-Statusline%-20s claudii cc-statusline on${CLAUDII_CLR_RESET}\n" ""
  fi

  # ── Activity — mini vibemap strip ─────────────────────────────────
  # Opt-out via vibemap.overview=false — section is suppressed entirely,
  # skipping the mini_strip call (and its cached file read).
  # jq quirk: `// default` treats false as falsy and replaces it with the
  # default. For boolean opt-out flags we need an explicit equality check.
  local _ov_vm_show
  _ov_vm_show=$(jq -r '.vibemap.overview == false' \
    "${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json" 2>/dev/null)
  if [[ "$_ov_vm_show" != "true" ]]; then
    printf '\n'
    _ov_vm_strip=""
    _ov_vm_strip=$(_vibemap_mini_strip 2>/dev/null) && _ov_vm_ok=1 || _ov_vm_ok=0
    if (( _ov_vm_ok )); then
      printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Activity${CLAUDII_CLR_RESET}\n"
      printf "    %s\n" "$_ov_vm_strip"
      printf "    ${CLAUDII_CLR_DIM}last 43d · claudii vibemap strip for detail${CLAUDII_CLR_RESET}\n"
    else
      printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Activity                        claudii config set vibemap.enabled true${CLAUDII_CLR_RESET}\n"
    fi
  fi

  # ── Sessions — summary only; details via `claudii se` ────────────
  printf '\n'
  if (( _ov_any_session )); then
    if (( _ov_active_count > 0 )); then
      printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Sessions${CLAUDII_CLR_RESET}\n"
      _ov_s=""; (( _ov_active_count != 1 )) && _ov_s="s"
      printf "    %d active session%s  ${CLAUDII_CLR_DIM}·  claudii se for details${CLAUDII_CLR_RESET}\n" \
        "$_ov_active_count" "$_ov_s"
    else
      printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Sessions${CLAUDII_CLR_RESET}\n"
    fi

    (( _ov_inactive_count > 0 )) && \
      printf "    ${CLAUDII_CLR_DIM}%d inactive  ·  claudii si${CLAUDII_CLR_RESET}\n" "$_ov_inactive_count"

    # Stale session GC hint: > 5 dead sessions older than 24h (counted in first loop)
    (( _ov_stale > 5 )) && \
      printf "    ${CLAUDII_CLR_DIM}%d stale sessions  ·  claudii si${CLAUDII_CLR_RESET}\n" "$_ov_stale"

    # Cron + bg_tasks summary line: shown when at least one session has a future cron
    if (( _ov_next_cron > 0 )); then
      _fmt_rel $(( _ov_next_cron - now ))
      if [[ -n "$_REL_FMT" ]]; then
        _ov_cron_line="    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_CRON} next wake in ${_REL_FMT}"
        if (( _ov_total_bg > 0 )); then
          _ov_bg_s=""; (( _ov_total_bg != 1 )) && _ov_bg_s="s"
          _ov_cron_line+="  ·  ${_ov_total_bg} bg task${_ov_bg_s}"
        fi
        _ov_cron_line+="${CLAUDII_CLR_RESET}"
        printf '%s\n' "$_ov_cron_line"
      fi
    fi
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Sessions                        start Claude to see data here${CLAUDII_CLR_RESET}\n"
  fi

  printf '\n'
  printf "  ${CLAUDII_CLR_DIM}claudii help  for all commands${CLAUDII_CLR_RESET}\n"
  printf '\n'
}
