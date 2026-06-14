# lib/cmd/overview.sh — claudii bare overview, modular section renderers.
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail
#
# Sections are config-driven: `overview.sections` (array) controls order and
# which sections render. Default order lives in config/defaults.json; a
# hardcoded fallback below keeps the overview alive if both configs lack it.
# Each `_ov_render_<name>` owns its own leading blank line + header so
# reordering/disabling never leaves stray spacing.

_OV_DEFAULT_SECTIONS="account sessions activity agents services commands"

# Normalize model identifier to canonical short form (Opus/Sonnet/Haiku); echoes input on no match.
_norm_model_short() {
  case "$1" in
    *[Oo]pus*)   echo "Opus"   ;;
    *[Ss]onnet*) echo "Sonnet" ;;
    *[Hh]aiku*)  echo "Haiku"  ;;
    *)           echo "$1"     ;;
  esac
}

# Resolve the section list: user config → shipped defaults → hardcoded.
_ov_sections() {
  local _s
  _s=$(jq -r '(.overview.sections // empty) | join(" ")' "$CONFIG" 2>/dev/null)
  [[ -z "$_s" ]] && _s=$(jq -r '(.overview.sections // empty) | join(" ")' "$DEFAULTS" 2>/dev/null)
  [[ -z "$_s" ]] && _s="$_OV_DEFAULT_SECTIONS"
  printf '%s\n' "$_s"
}

# Dim command-hint line. Every argument is a full invocable command
# ("claudii se") — never data or pseudo-labels — joined with " · ".
_ov_hint() {
  local _h="" _c
  for _c in "$@"; do
    [[ -n "$_h" ]] && _h+=" · "
    _h+="$_c"
  done
  printf "    ${CLAUDII_CLR_DIM}→ %s${CLAUDII_CLR_RESET}\n" "$_h"
}

# ── Gather — one pass over session caches + history, sets _ov_* globals ─────
_ov_gather() {
  _session_files "$cache_dir"
  _ov_files=("${_SESSION_FILES[@]+"${_SESSION_FILES[@]}"}")

  _ov_acct_5h="" _ov_acct_7d="" _ov_acct_reset="" _ov_acct_7d_start="" _ov_acct_reset_7d="" _ov_acct_mt=0
  _ov_today_tok=0 _ov_today_count=0 _ov_stale=0
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

      # Today's token throughput — fallback only, used when no history exists
      # (overridden by the history-delta computation after this loop). Sums the
      # per-session cumulative in+out (tok=) the sessionline wrote to the cache.
      if (( _PSC_mtime >= _ov_cutoff )); then
        _ov_today_count=$(( _ov_today_count + 1 ))
        if [[ "$_PSC_tok" =~ ^[0-9]+$ && "$_PSC_tok" != "0" ]]; then
          _ov_today_tok=$(( _ov_today_tok + _PSC_tok ))
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

  # ── Today's tokens from history deltas ──────────────────────────────
  # Same per-session increment attribution as `claudii cost`/`trends`, so the
  # overview agrees with them (the session-cache sum above double-counts
  # multi-day sessions: cumulative tok= keyed by file mtime). in+out token
  # deltas (9-col history: in=$7, out=$8). Only the files that can hold today's
  # rows are scanned (legacy history.tsv + current month) — a session spanning a
  # month boundary loses its prior-month baseline on the 1st, which matches
  # first-row-counts-as-throughput semantics. Session count = distinct SIDs with
  # token activity today.
  _ov_hist_files=()
  [[ -s "$cache_dir/history.tsv" ]] && _ov_hist_files+=("$cache_dir/history.tsv")
  _ov_hist_month="$cache_dir/history-$(date '+%Y-%m').tsv"
  [[ -s "$_ov_hist_month" ]] && _ov_hist_files+=("$_ov_hist_month")
  if [[ ${#_ov_hist_files[@]} -gt 0 ]]; then
    _ov_tz=$(_tz_offset_secs)
    _ov_today_hist=$(awk -F'\t' -v tz_offset="${_ov_tz:-0}" -v today="$(date '+%Y-%m-%d')" "
$(<"$CLAUDII_HOME/lib/epoch_to_date.awk")
$(<"$CLAUDII_HOME/lib/attribution.awk")
"'
      NF < 6 { next }
      $1 == "timestamp" || $1 == "" || $6 == "" { next }
      {
        ts = $1 + 0; if (ts == 0) next
        sid = $6
        tok = ($7 == "" ? 0 : $7 + 0) + ($8 == "" ? 0 : $8 + 0)
        tinc = attr_delta(base, sid, tok)
        if (tinc > 0 && epoch_to_date(ts) == today) { total += tinc; seen[sid] = 1 }
      }
      END { n = 0; for (s in seen) n++; printf "%d %d", total, n }
    ' "${_ov_hist_files[@]}" 2>/dev/null)
    if [[ "$_ov_today_hist" == *" "* ]]; then
      _ov_today_tok="${_ov_today_hist% *}"
      _ov_today_count="${_ov_today_hist##* }"
    fi
  fi
}

# ── Account ──────────────────────────────────────────────────────────────────
_ov_render_account() {
  printf '\n'
  if [[ -z "$_ov_acct_5h" ]]; then
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Account                         rate limits appear after first session${CLAUDII_CLR_RESET}\n"
    return 0
  fi
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
      # Display via the shared cascade (m / h+m); urgency color stays minute-keyed.
      _fmt_rel "$_ov_remaining"
      [[ -z "$_REL_FMT" ]] && _REL_FMT="${_ov_rem_min}m"
      _ov_acct_line+=" ${_ov_reset_clr}↺${_REL_FMT}${CLAUDII_CLR_RESET}"
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
  # Today's token throughput with accent color, and session count.
  # ($ is no longer shown here — the dollar view lives in `claudii cost`.)
  if (( _ov_today_count > 0 )); then
    _ov_today_fmt=$(_fmt_tok "$_ov_today_tok")
    _ov_s=""; (( _ov_today_count != 1 )) && _ov_s="s"
    _ov_acct_line+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}${_ov_today_fmt} tok${CLAUDII_CLR_RESET} today (${_ov_today_count} session${_ov_s})"
  fi
  printf '%s\n' "$_ov_acct_line"
}

# ── Sessions ─────────────────────────────────────────────────────────────────
_ov_render_sessions() {
  printf '\n'
  if (( _ov_any_session == 0 )); then
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Sessions                        start Claude to see data here${CLAUDII_CLR_RESET}\n"
    return 0
  fi

  if (( _ov_active_count > 0 )); then
    printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Sessions${CLAUDII_CLR_RESET}\n"
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Sessions${CLAUDII_CLR_RESET}\n"
  fi

  # Count line: active (colored when > 0), inactive/stale only when present —
  # the word "inactive" must not appear for a clean cache (see test_tmp_filter).
  local _ov_sess_line=""
  # Keep "N active session(s)" as one uncolored literal — scripts and tests
  # grep for the plain phrase; an ANSI wrap inside it broke the match once.
  if (( _ov_active_count > 0 )); then
    _ov_s=""; (( _ov_active_count != 1 )) && _ov_s="s"
    _ov_sess_line="    ${_ov_active_count} active session${_ov_s}"
  else
    _ov_sess_line="    ${CLAUDII_CLR_DIM}0 active sessions${CLAUDII_CLR_RESET}"
  fi
  (( _ov_inactive_count > 0 )) && \
    _ov_sess_line+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP} ${_ov_inactive_count} inactive${CLAUDII_CLR_RESET}"
  (( _ov_stale > 0 )) && \
    _ov_sess_line+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP} ${_ov_stale} stale${CLAUDII_CLR_RESET}"
  printf '%s\n' "$_ov_sess_line"

  # Cron + bg_tasks line: shown when at least one session has a future cron
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

  # Command hints — only commands that currently have something to act on.
  local _ov_hints=("claudii se")
  (( _ov_inactive_count > 0 )) && _ov_hints+=("claudii si")
  (( _ov_stale > 0 ))          && _ov_hints+=("claudii gc")
  _ov_hint "${_ov_hints[@]}"
}

# ── Activity — mini vibemap strip ────────────────────────────────────────────
_ov_render_activity() {
  # Opt-out via vibemap.overview=false — section is suppressed entirely,
  # skipping the mini_strip call (and its cached file read).
  # jq quirk: `// default` treats false as falsy and replaces it with the
  # default. For boolean opt-out flags we need an explicit equality check.
  local _ov_vm_show
  _ov_vm_show=$(jq -r '.vibemap.overview == false' "$CONFIG" 2>/dev/null)
  [[ "$_ov_vm_show" == "true" ]] && return 0

  printf '\n'
  local _ov_vm_strip="" _ov_vm_ok
  _ov_vm_strip=$(_vibemap_mini_strip 2>/dev/null) && _ov_vm_ok=1 || _ov_vm_ok=0
  if (( _ov_vm_ok )); then
    printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Activity${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}last 43d${CLAUDII_CLR_RESET}\n"
    printf "    %s\n" "$_ov_vm_strip"
    _ov_hint "claudii vibemap" "claudii vibemap strip"
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Activity                        claudii config set vibemap.enabled true${CLAUDII_CLR_RESET}\n"
  fi
}

# ── Agents — grouped by model tier + shell aliases ───────────────────────────
_ov_render_agents() {
  printf '\n'
  _ov_agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$CONFIG" 2>/dev/null)
  [[ -z "$_ov_agents_json" ]] && _ov_agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$DEFAULTS" 2>/dev/null)

  if [[ -z "$_ov_agents_json" ]]; then
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Agents                          claudii agents to configure${CLAUDII_CLR_RESET}\n"
    return 0
  fi

  # Shell aliases (cl/clo/…) come from .aliases — same fallback chain.
  local _ov_alias_names
  _ov_alias_names=$(jq -r '(.aliases // {}) | keys | join(" ")' "$CONFIG" 2>/dev/null)
  [[ -z "$_ov_alias_names" ]] && _ov_alias_names=$(jq -r '(.aliases // {}) | keys | join(" ")' "$DEFAULTS" 2>/dev/null)

  local _ov_agent_count _ov_alias_count=0
  _ov_agent_count=$(echo "$_ov_agents_json" | jq -r 'length')
  if [[ -n "$_ov_alias_names" ]]; then
    set -- $_ov_alias_names; _ov_alias_count=$#
  fi
  local _ov_ag_summary="${_ov_agent_count} agents"
  (( _ov_alias_count > 0 )) && _ov_ag_summary+=" ${CLAUDII_SYM_SEP} ${_ov_alias_count} shell aliases"
  printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Agents${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_ov_ag_summary"

  # Group agent entries by model tier. No declare -A (bash 3.2 in bin/) —
  # four flat accumulator strings, tier resolved via _norm_model_short + case.
  local _ag_haiku="" _ag_sonnet="" _ag_opus="" _ag_other=""
  local _a_model _a_entry
  while IFS=$'\t' read -r _a_model _a_entry; do
    [[ -z "$_a_entry" ]] && continue
    case "$(_norm_model_short "$_a_model")" in
      Haiku)  _ag_haiku+="${_ag_haiku:+ · }${_a_entry}"   ;;
      Sonnet) _ag_sonnet+="${_ag_sonnet:+ · }${_a_entry}" ;;
      Opus)   _ag_opus+="${_ag_opus:+ · }${_a_entry}"     ;;
      *)      _ag_other+="${_ag_other:+ · }${_a_entry}"   ;;
    esac
  done < <(echo "$_ov_agents_json" | jq -r 'to_entries | sort_by(.key)[] | [(.value.model // "?"), (.key + (if (.value.effort // "") == "" then "" else "/" + .value.effort end))] | @tsv')

  [[ -n "$_ag_haiku"  ]] && printf "    ${CLAUDII_CLR_DIM}%-7s${CLAUDII_CLR_RESET} %s\n" "haiku"  "$_ag_haiku"
  [[ -n "$_ag_sonnet" ]] && printf "    ${CLAUDII_CLR_DIM}%-7s${CLAUDII_CLR_RESET} %s\n" "sonnet" "$_ag_sonnet"
  [[ -n "$_ag_opus"   ]] && printf "    ${CLAUDII_CLR_DIM}%-7s${CLAUDII_CLR_RESET} %s\n" "opus"   "$_ag_opus"
  [[ -n "$_ag_other"  ]] && printf "    ${CLAUDII_CLR_DIM}%-7s${CLAUDII_CLR_RESET} %s\n" "other"  "$_ag_other"
  [[ -n "$_ov_alias_names" ]] && printf "    ${CLAUDII_CLR_DIM}%-7s${CLAUDII_CLR_RESET} %s\n" "shell"  "${_ov_alias_names// / · }"

  _ov_hint "claudii agents"
}

# ── Services ─────────────────────────────────────────────────────────────────
_ov_render_services() {
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
      _ov_affected=0
      while IFS='=' read -r _om _os; do
        [[ -z "$_om" || "$_om" == _* ]] && continue
        _om_cap=$(_norm_model_short "$_om")
        case "$_os" in
          ok)       _ov_health_str+="${CLAUDII_CLR_GREEN}${_om_cap} ${CLAUDII_SYM_OK}${CLAUDII_CLR_RESET} " ;;
          degraded) _ov_health_str+="${CLAUDII_CLR_YELLOW}${_om_cap} ${CLAUDII_SYM_WARN}${CLAUDII_CLR_RESET} "; _ov_affected=1 ;;
          down)     _ov_health_str+="${CLAUDII_CLR_RED}${_om_cap} ${CLAUDII_SYM_ERROR}${CLAUDII_CLR_RESET} "; _ov_affected=1 ;;
        esac
      done < "$_ov_status_cache"
      if [[ -n "$_ov_health_str" ]]; then
        _ov_model_health="  ${CLAUDII_CLR_DIM}[${CLAUDII_CLR_RESET}${_ov_health_str% }${CLAUDII_CLR_DIM}]${CLAUDII_CLR_RESET}"
        # Incident indicator — neutral note glyph when an incident exists but
        # no tracked model is affected; stage-colored otherwise. In sync with
        # bin/claudii-cc-statusline and lib/statusline.zsh.
        _ov_inc=$(grep -E '^_incident=' "$_ov_status_cache" 2>/dev/null | head -1 | cut -d= -f2)
        if [[ -n "$_ov_inc" && $_ov_affected -eq 0 ]]; then
          _ov_model_health+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_NOTE}${CLAUDII_CLR_RESET}"
        else
          case "$_ov_inc" in
            investigating) _ov_model_health+=" ${CLAUDII_CLR_RED}${CLAUDII_SYM_INVESTIGATING}${CLAUDII_CLR_RESET}" ;;
            identified)    _ov_model_health+=" ${CLAUDII_CLR_YELLOW}${CLAUDII_SYM_IDENTIFIED}${CLAUDII_CLR_RESET}" ;;
            monitoring)    _ov_model_health+=" ${CLAUDII_CLR_CYAN}${CLAUDII_SYM_MONITORING}${CLAUDII_CLR_RESET}" ;;
          esac
        fi
      fi
    fi
    printf "    ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ClaudeStatus%s\n" "$_ov_model_health"
  else
    printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} ClaudeStatus%-20s claudii on${CLAUDII_CLR_RESET}\n" ""
  fi

  # Session Dashboard
  if [[ "$_ov_dash_en" != "off" ]]; then
    printf "    ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} Dashboard\n"
  else
    printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Dashboard%-23s claudii session-dashboard on${CLAUDII_CLR_RESET}\n" ""
  fi

  # CC-Statusline
  if (( _ov_sl_on )); then
    printf "    ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} CC-Statusline\n"
  else
    printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} CC-Statusline%-20s claudii cc-statusline on${CLAUDII_CLR_RESET}\n" ""
  fi
}

# ── Commands — grouped quick reference ───────────────────────────────────────
# Every item after a group label is a literal subcommand of `claudii` —
# no data, no pseudo-labels (run as `claudii <item>`).
_ov_render_commands() {
  printf '\n'
  printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Commands${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}each runs as claudii <command>${CLAUDII_CLR_RESET}\n"
  printf "    ${CLAUDII_CLR_DIM}%-9s${CLAUDII_CLR_RESET} %s\n" "sessions" "se · si · pin · unpin · gc · resume"
  printf "    ${CLAUDII_CLR_DIM}%-9s${CLAUDII_CLR_RESET} %s\n" "cost"     "cost · trends · skills-cost"
  printf "    ${CLAUDII_CLR_DIM}%-9s${CLAUDII_CLR_RESET} %s\n" "activity" "vibemap · cache"
  printf "    ${CLAUDII_CLR_DIM}%-9s${CLAUDII_CLR_RESET} %s\n" "display"  "on · off · claudestatus · session-dashboard · cc-statusline · insomnii"
  printf "    ${CLAUDII_CLR_DIM}%-9s${CLAUDII_CLR_RESET} %s\n" "tools"    "agents · config · omlx · vpnii · search"
  printf "    ${CLAUDII_CLR_DIM}%-9s${CLAUDII_CLR_RESET} %s\n" "system"   "status · doctor · update · explain · changelog"
  _ov_hint "claudii help" "man claudii"
}

# ── Entry point — bare `claudii` ─────────────────────────────────────────────
_cmd_default() {
  _cfg_init
  _live_pids_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  now=$(date +%s); _NOW="$now"

  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_ACCENT}v%s${CLAUDII_CLR_RESET}\n" "$VERSION"

  _ov_gather

  local _ov_sec _ov_secs _ov_has_commands=0
  _ov_secs=$(_ov_sections)
  for _ov_sec in $_ov_secs; do
    case "$_ov_sec" in
      account)  _ov_render_account  ;;
      sessions) _ov_render_sessions ;;
      activity) _ov_render_activity ;;
      agents)   _ov_render_agents   ;;
      services) _ov_render_services ;;
      commands) _ov_render_commands; _ov_has_commands=1 ;;
      *)
        printf '\n'
        printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} unknown overview section '%s' — valid: %s (fix overview.sections via claudii config)${CLAUDII_CLR_RESET}\n" \
          "$_ov_sec" "$_OV_DEFAULT_SECTIONS"
        ;;
    esac
  done

  printf '\n'
  # The commands section already ends in a help hint — don't repeat it.
  if (( _ov_has_commands == 0 )); then
    printf "  ${CLAUDII_CLR_DIM}claudii help  for all commands${CLAUDII_CLR_RESET}\n"
    printf '\n'
  fi
}
