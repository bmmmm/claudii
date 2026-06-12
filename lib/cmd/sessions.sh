# lib/cmd/sessions.sh — session listing commands (sessions, sessions-inactive, pin, gc)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_sessions_inactive() {
  # "claudii sessions-inactive" — shows only inactive (stale/dead) sessions
  _cfg_init
  _live_pids_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _rate_disp_init
  _NOW=$(date +%s)

  printf '\n'
  printf "  ${CLAUDII_CLR_BOLD}Inactive Sessions${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_DIM}Sessions whose Claude Code process has ended. Cache kept until GC runs.${CLAUDII_CLR_RESET}\n"

  _session_files "$cache_dir"
  _is_files=("${_SESSION_FILES[@]+"${_SESSION_FILES[@]}"}")

  _has_files=0
  _rendered_any=0
  _is_stale=0 _is_pinned=0

  [[ ${#_is_files[@]} -gt 0 ]] && _has_files=1

  if [[ $_has_files -eq 1 ]]; then
    for _is_f in "${_is_files[@]}"; do
      [[ -f "$_is_f" ]] || continue

      _parse_session_cache "$_is_f"

      [[ -z "$_PSC_model" ]] && continue

      # Skip active sessions — this command shows only inactive
      if [[ $_PSC_is_active -eq 1 ]]; then continue; fi

      # Status badge: pinned (protected) vs stale (GC candidate) vs idle.
      # Footer counters increment HERE so they always match the rendered list
      # (a second kill-0-only loop used to disagree with the agents-API+24h
      # liveness the rows are based on).
      local _is_badge _is_tag=""
      if [[ "$_PSC_pinned" == "1" ]]; then
        _is_badge="${CLAUDII_CLR_CYAN}${CLAUDII_SYM_PIN}${CLAUDII_CLR_RESET}"
        _is_tag=" ${CLAUDII_CLR_CYAN}pinned${CLAUDII_CLR_RESET}"
        (( ++_is_pinned ))
      elif (( _PSC_age >= 3600 )); then
        _is_badge="${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET}"
        _is_tag=" ${CLAUDII_CLR_DIM}stale${CLAUDII_CLR_RESET}"
        (( ++_is_stale ))
      else
        _is_badge="${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET}"
      fi

      # Strip context window suffix from model name
      local _is_model
      _is_model="$(_strip_model_name "${_PSC_model}")"

      # Line 1: badge + model + metadata
      _is_line="  ${_is_badge} ${CLAUDII_CLR_ACCENT}${_is_model}${CLAUDII_CLR_RESET}"
      [[ -n "$_PSC_worktree" ]] && _is_line+=" ${CLAUDII_CLR_DIM}[wt:${_PSC_worktree}]${CLAUDII_CLR_RESET}"
      [[ -n "$_PSC_agent" ]]    && _is_line+=" ${CLAUDII_CLR_DIM}[agent:${_PSC_agent}]${CLAUDII_CLR_RESET}"
      printf '%s\n' "$_is_line"

      # Line 2: context bar + rate limits + age + status tag
      local _is_detail="    "
      if [[ -n "$_PSC_ctx_pct" && "$_PSC_ctx_pct" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _is_pct=${_PSC_ctx_pct%.*}
        (( _is_pct > 100 )) && _is_pct=100
        (( _is_pct < 0 ))   && _is_pct=0
        _render_ctx_bar "$_is_pct"
        _is_detail+="${_CTX_BAR} ${_is_pct}%"
      fi
      if [[ -n "$_PSC_rate_5h" && "$_PSC_rate_5h" != "0" ]]; then
        _is_detail+="  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}5h${_rate_mark}${CLAUDII_CLR_RESET} $(_rate_pct_disp "$_PSC_rate_5h")%"
      fi
      _render_age "$_PSC_age"
      _is_detail+="  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP} ${_AGE_STR}${CLAUDII_CLR_RESET}${_is_tag}"
      printf '%s\n' "$_is_detail"

      # Line 3: resume command with full session UUID
      if [[ -n "$_PSC_session_id" ]]; then
        printf "    ${CLAUDII_CLR_DIM}claude -r ${CLAUDII_CLR_RESET}${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_PSC_session_id"
      fi

      printf '\n'
      _rendered_any=1
    done
  fi

  if [[ $_has_files -eq 1 ]] && [[ $_rendered_any -eq 0 ]]; then
    printf "  No inactive sessions.\n"
  elif [[ $_has_files -eq 0 ]]; then
    printf "  No session data found.\n"
  fi

  # GC footer — counters collected in the render loop above (same data, same
  # liveness logic, no second pass over the files).
  local _gc_parts=""
  (( _is_stale > 0 )) && _gc_parts="${_is_stale} stale"
  (( _is_pinned > 0 )) && {
    [[ -n "$_gc_parts" ]] && _gc_parts+=", "
    _gc_parts+="${_is_pinned} pinned"
  }
  [[ -n "$_gc_parts" ]] && printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_gc_parts"

  printf '\n'
}

# Pin/unpin a session — pinned sessions are protected from GC.
# Matches by session_id substring (first match wins).
# (sessionline preserves pinned=1 across cache rewrites — see bin/claudii-cc-statusline.)
_session_toggle_pin() {
  local action="$1" needle="$2"
  local cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local found=0
  _session_files "$cache_dir"
  for f in "${_SESSION_FILES[@]+"${_SESSION_FILES[@]}"}"; do
    local sid line
    while IFS= read -r line; do sid="${line#*=}"; break; done < <(grep '^session_id=' "$f" 2>/dev/null)
    if [[ "$sid" == *"$needle"* ]] || [[ "${f##*/session-}" == *"$needle"* ]]; then
      local _tmp="${f}.pin.$$"
      if [[ "$action" == "pin" ]]; then
        if grep -q '^pinned=1$' "$f" 2>/dev/null; then
          echo "Already pinned: $sid"
        else
          { grep -v '^pinned=' "$f" 2>/dev/null; echo "pinned=1"; } > "$_tmp" && mv -f "$_tmp" "$f"
          echo "Pinned: $sid"
        fi
      else
        if grep -q '^pinned=1$' "$f" 2>/dev/null; then
          grep -v '^pinned=' "$f" 2>/dev/null > "$_tmp" && mv -f "$_tmp" "$f"
          echo "Unpinned: $sid"
        else
          echo "Not pinned: $sid"
        fi
      fi
      found=1; break
    fi
  done
  (( found )) || { echo "No session matching '$needle' — run 'claudii se' to list active sessions" >&2; exit 1; }
}

_cmd_pin() {
  [[ -z "${2:-}" ]] && { echo "Usage: claudii pin <session-id>" >&2; exit 1; }
  _session_toggle_pin pin "$2"
}

_cmd_unpin() {
  [[ -z "${2:-}" ]] && { echo "Usage: claudii unpin <session-id>" >&2; exit 1; }
  _session_toggle_pin unpin "$2"
}

_strip_model_name() {
  local _m="$1"
  _m="${_m% (*context)}"
  _m="${_m% (*Context)}"
  printf '%s' "$_m"
}

# Rate display flip — returns the integer to render given a raw "used" value.
# Caller must set $_RATE_DISP to "used" or "remaining" once per command (via _cfgget).
# Color thresholds always key off the raw used%, so callers keep using the input int.
_rate_pct_disp() {
  local _u=${1%.*}
  if [[ "${_RATE_DISP:-used}" == "remaining" ]]; then printf '%s' "$(( 100 - _u ))"
  else printf '%s' "$_u"; fi
}

_cmd_sessions() {
  _cfg_init
  _live_pids_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  now=$(date +%s); _NOW="$now"
  active=0 stale=0
  latest_5h="" latest_7d="" latest_reset="" latest_5h_mt=0
  _rate_disp_init

  # Collect all session data into parallel arrays
  declare -a _sf_model _sf_ctx _sf_cost _sf_rate5h _sf_rate7d _sf_reset5h \
             _sf_ppid _sf_worktree _sf_agent _sf_cache _sf_sid \
             _sf_is_active _sf_age _sf_projpath _sf_sesname \
             _sf_fingerprint _sf_last_msg _sf_kind _sf_pace _sf_cron _sf_bgtasks
  _sf_count=0

  # Show spinner on stderr only for pretty output (not JSON/TSV — those are piped)
  _spinner_start

  # Build session→JSONL map once (O(1) lookup per session instead of O(dirs) scan)
  _session_build_map

  _session_files "$cache_dir"
  for sf in "${_SESSION_FILES[@]+"${_SESSION_FILES[@]}"}"; do
    [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" ]] && printf '%s' "${sf/#$HOME/\~}" > "$CLAUDII_SPINNER_LABEL_FILE"
    _parse_session_cache "$sf"

    # Track freshest rate limits — use mtime to pick the most recently updated session
    if [[ -n "$_PSC_rate_5h" ]] && [[ "$_PSC_is_active" -eq 1 ]] && (( _PSC_mtime > latest_5h_mt )); then
      latest_5h="$_PSC_rate_5h"; latest_7d="$_PSC_rate_7d"; latest_reset="$_PSC_reset_5h"
      latest_5h_mt=$_PSC_mtime
    fi

    _sf_model[$_sf_count]="$_PSC_model"
    _sf_ctx[$_sf_count]="$_PSC_ctx_pct"
    _sf_cost[$_sf_count]="$_PSC_cost"
    _sf_rate5h[$_sf_count]="$_PSC_rate_5h"
    _sf_rate7d[$_sf_count]="$_PSC_rate_7d"
    _sf_reset5h[$_sf_count]="$_PSC_reset_5h"
    _sf_ppid[$_sf_count]="$_PSC_ppid"
    _sf_sid[$_sf_count]="$_PSC_session_id"
    _sf_worktree[$_sf_count]="$_PSC_worktree"
    _sf_agent[$_sf_count]="$_PSC_agent"
    _sf_cache[$_sf_count]="$_PSC_cache_pct"
    _sf_age[$_sf_count]="$_PSC_age"
    _sf_is_active[$_sf_count]="$_PSC_is_active"
    _sf_kind[$_sf_count]="$_PSC_kind"
    _sf_pace[$_sf_count]="$_PSC_pace"
    _sf_cron[$_sf_count]="$_PSC_cron"
    _sf_bgtasks[$_sf_count]="$_PSC_bg_tasks"
    # Resolve project path + session name from JSONL (only for pretty output)
    if [[ "$_FORMAT" != "tsv" ]]; then
      # One awk pass over the JSONL for name + fingerprint + last_message + cwd.
      # (Was a separate _session_project_path grep|head|grep|sed pipe PLUS a
      #  _session_resolve awk — each re-scanned the same file and re-resolved the
      #  jsonl path. Now a single resolve does all four.)
      local _resolved _res_name _res_fp _res_msg _res_cwd
      _resolved=$(_session_resolve "$_PSC_session_id")
      { IFS= read -r _res_name; IFS= read -r _res_fp; IFS= read -r _res_msg; IFS= read -r _res_cwd; } <<< "$_resolved" || true
      _sf_sesname[$_sf_count]="$_res_name"
      _sf_fingerprint[$_sf_count]="$_res_fp"
      _sf_last_msg[$_sf_count]="$_res_msg"
      # Shorten the resolved cwd ($HOME→~, cap 40) — matches old _session_project_path.
      _sf_projpath[$_sf_count]=""
      if [[ -n "$_res_cwd" ]]; then
        _ppath="${_res_cwd/#$HOME/\~}"
        (( ${#_ppath} > 40 )) && _ppath="...${_ppath: -37}"
        _sf_projpath[$_sf_count]="$_ppath"
      fi
      # Fallback: project_path written directly by sessionline (agents without session_id)
      if [[ -z "${_sf_projpath[$_sf_count]}" && -n "$_PSC_project_path" ]]; then
        _ppath="${_PSC_project_path/#$HOME/\~}"
        (( ${#_ppath} > 40 )) && _ppath="...${_ppath: -37}"
        _sf_projpath[$_sf_count]="$_ppath"
      fi
    else
      _sf_projpath[$_sf_count]=""
      _sf_sesname[$_sf_count]=""
      _sf_fingerprint[$_sf_count]=""
      _sf_last_msg[$_sf_count]=""
    fi
    if [[ "$_PSC_is_active" -eq 1 ]]; then
      (( ++active ))
    else
      (( ++stale ))
    fi
    (( ++_sf_count ))
  done

  # Kill spinner and clear spinner line
  _spinner_stop

  # Fallback 2 — batch lsof for active sessions still missing a project path.
  # Collects all ppids that need resolution, issues a single lsof call, then
  # assigns results back. Skipped for json/tsv output (no path needed there).
  if [[ "$_FORMAT" != "json" && "$_FORMAT" != "tsv" ]]; then
    _lsof_ppids=()
    _lsof_idx=()
    for (( _i=0; _i<_sf_count; _i++ )); do
      if [[ -z "${_sf_projpath[$_i]}" && "${_sf_is_active[$_i]}" -eq 1 \
            && -n "${_sf_ppid[$_i]}" ]]; then
        _lsof_ppids+=("${_sf_ppid[$_i]}")
        _lsof_idx+=("$_i")
      fi
    done
    if [[ ${#_lsof_ppids[@]} -gt 0 ]]; then
      # Build pid→cwd map from a single lsof invocation.
      # Output format: pPID\nnPATH\npPID\nnPATH...
      _lsof_pids_map=()
      _lsof_cwd_map=()
      _lsof_cur_pid=""
      printf -v _lsof_pid_list '%s,' "${_lsof_ppids[@]}"
      _lsof_pid_list="${_lsof_pid_list%,}"
      while IFS= read -r _lsof_line; do
        case "$_lsof_line" in
          p*) _lsof_cur_pid="${_lsof_line#p}" ;;
          n*) _lsof_pids_map+=("$_lsof_cur_pid")
              _lsof_cwd_map+=("${_lsof_line#n}")
              ;;
        esac
      done < <(lsof -p "$_lsof_pid_list" -d cwd -Fn 2>/dev/null || true)
      # Assign resolved paths back to the session array
      for (( _j=0; _j<${#_lsof_idx[@]}; _j++ )); do
        _target_pid="${_sf_ppid[${_lsof_idx[$_j]}]}"
        for (( _k=0; _k<${#_lsof_pids_map[@]}; _k++ )); do
          if [[ "${_lsof_pids_map[$_k]}" == "$_target_pid" ]]; then
            _raw_cwd="${_lsof_cwd_map[$_k]}"
            _short_cwd="${_raw_cwd/#$HOME/\~}"
            (( ${#_short_cwd} > 40 )) && _short_cwd="...${_short_cwd: -37}"
            _sf_projpath[${_lsof_idx[$_j]}]="$_short_cwd"
            break
          fi
        done
      done
      unset _lsof_pids_map _lsof_cwd_map _lsof_pid_list _lsof_cur_pid \
            _lsof_line _target_pid _raw_cwd _short_cwd _j _k
    fi
    unset _lsof_ppids _lsof_idx
  fi

  if [[ "$_FORMAT" == "json" ]]; then
    # Build JSON array from collected data
    # One jq invocation over US-delimited rows (was one jq -n fork PER session).
    # Fields are session metadata / truncated single-line strings — they cannot
    # contain 0x1F or newlines, so the row format is unambiguous.
    local _jd=$'\x1f' _json_rows=""
    for (( _i=0; _i<_sf_count; _i++ )); do
      _json_rows+="${_sf_model[$_i]}${_jd}${_sf_ctx[$_i]}${_jd}${_sf_cost[$_i]:-0}${_jd}"
      _json_rows+="${_sf_rate5h[$_i]}${_jd}${_sf_rate7d[$_i]}${_jd}${_sf_reset5h[$_i]}${_jd}"
      _json_rows+="${_sf_sid[$_i]}${_jd}${_sf_worktree[$_i]}${_jd}${_sf_agent[$_i]}${_jd}"
      _json_rows+="${_sf_age[$_i]}${_jd}${_sf_is_active[$_i]}${_jd}"
      _json_rows+="${_sf_fingerprint[$_i]}${_jd}${_sf_last_msg[$_i]}"$'\n'
    done
    printf '%s' "$_json_rows" | jq -Rs 'split("\n") | map(select(length > 0) | split("\u001f") | {
        model: .[0],
        ctx_pct: (.[1] | if . == "" then null else (tonumber? // null) end),
        cost: (.[2] | tonumber? // 0),
        rate_5h: (.[3] | if . == "" then null else (tonumber? // null) end),
        rate_7d: (.[4] | if . == "" then null else (tonumber? // null) end),
        reset_5h: (.[5] | if . == "" then null else (tonumber? // null) end),
        session_id: .[6], worktree: .[7], agent: .[8],
        age_seconds: (.[9] | tonumber), status: .[10],
        fingerprint: .[11], last_user_message: .[12]
      })'
    exit 0
  elif [[ "$_FORMAT" == "tsv" ]]; then
    printf "model\tctx_pct\tcost\trate_5h\trate_7d\treset_5h\tsession_id\tworktree\tagent\tage_seconds\tstatus\n"
    for (( _i=0; _i<_sf_count; _i++ )); do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "${_sf_model[$_i]}" "${_sf_ctx[$_i]}" "${_sf_cost[$_i]:-0}" \
        "${_sf_rate5h[$_i]}" "${_sf_rate7d[$_i]}" "${_sf_reset5h[$_i]}" \
        "${_sf_sid[$_i]}" "${_sf_worktree[$_i]}" "${_sf_agent[$_i]}" \
        "${_sf_age[$_i]}" "${_sf_is_active[$_i]}"
    done
    exit 0
  fi

  # ── Build cross-session file→color map ──────────────────────────────────────
  # Collect all unique filenames from fingerprints, assign consistent colors.
  local _fp_names=() _fp_colors=() _fp_count=0
  local _palette_size=${#CLAUDII_FP_PALETTE[@]}
  for (( _i=0; _i<_sf_count; _i++ )); do
    local _fp="${_sf_fingerprint[$_i]}"
    [[ -z "$_fp" ]] && continue
    # Parse "file1(N) file2(N) ..." — extract bare filenames
    local _word _fp_words=()
    IFS=' ' read -ra _fp_words <<< "$_fp"
    for _word in "${_fp_words[@]}"; do
      local _fname="${_word%%(*}"
      [[ -z "$_fname" ]] && continue
      # Check if already in map
      local _found=0
      for (( _k=0; _k<_fp_count; _k++ )); do
        [[ "${_fp_names[$_k]}" == "$_fname" ]] && { _found=1; break; }
      done
      if [[ $_found -eq 0 ]]; then
        _fp_names[$_fp_count]="$_fname"
        _fp_colors[$_fp_count]="${CLAUDII_FP_PALETTE[$(( _fp_count % _palette_size ))]}"
        (( ++_fp_count ))
      fi
    done
  done

  # Helper: colorize a fingerprint string using the file→color map
  _colorize_fingerprint() {
    local _fp="$1" _out="" _word _fname _count_part _fp_words=()
    IFS=' ' read -ra _fp_words <<< "$_fp"
    for _word in "${_fp_words[@]}"; do
      _fname="${_word%%(*}"
      _count_part="(${_word#*(}"
      [[ "$_count_part" == "($_fname" ]] && _count_part=""  # no parens found
      local _clr="$CLAUDII_CLR_DIM"
      for (( _k=0; _k<_fp_count; _k++ )); do
        [[ "${_fp_names[$_k]}" == "$_fname" ]] && { _clr="${_fp_colors[$_k]}"; break; }
      done
      [[ -n "$_out" ]] && _out+=" "
      _out+="${_clr}${_fname}${CLAUDII_CLR_RESET}${CLAUDII_CLR_DIM}${_count_part}${CLAUDII_CLR_RESET}"
    done
    printf '%s' "$_out"
  }

  # ── Pretty output ────────────────────────────────────────────────────────────
  printf '\n'
  for (( _i=0; _i<_sf_count; _i++ )); do
    if [[ "${_sf_is_active[$_i]}" -eq 1 ]]; then
      status_icon="${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET}"
    else
      status_icon="${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET}"
    fi
    _render_age "${_sf_age[$_i]}"

    # Strip context window suffix from model name (e.g. "Opus 4.6 (1M context)" → "Opus 4.6")
    local _display_model
    _display_model="$(_strip_model_name "${_sf_model[$_i]:-?}")"

    # Background-session badge (kind comes from `claude agents --json`).
    local _bg_badge=""
    [[ "${_sf_kind[$_i]}" == "background" ]] && \
      _bg_badge=" ${CLAUDII_CLR_DIM}[bg]${CLAUDII_CLR_RESET}"

    # bg_tasks count badge — shown when bg_tasks >= 1 (from claudii-stop-hook)
    local _bgtasks_badge=""
    local _bgt_val="${_sf_bgtasks[$_i]:-0}"
    if [[ "$_bgt_val" =~ ^[0-9]+$ && "$_bgt_val" -ge 1 ]]; then
      _bgtasks_badge=" ${CLAUDII_CLR_DIM}[${_bgt_val} bg]${CLAUDII_CLR_RESET}"
    fi

    # Line 1: status + model + [bg] + [N bg] + project path + metadata
    line="  ${status_icon} ${CLAUDII_CLR_ACCENT}${_display_model}${CLAUDII_CLR_RESET}${_bg_badge}${_bgtasks_badge}"
    if [[ -n "${_sf_projpath[$_i]}" ]]; then
      line+="  ${CLAUDII_CLR_DIM}${_sf_projpath[$_i]}${CLAUDII_CLR_RESET}"
    fi
    [[ -n "${_sf_sesname[$_i]}" ]]  && line+="  ${CLAUDII_CLR_DIM}\"${_sf_sesname[$_i]}\"${CLAUDII_CLR_RESET}"
    [[ -n "${_sf_worktree[$_i]}" ]] && line+=" ${CLAUDII_CLR_DIM}[wt:${_sf_worktree[$_i]}]${CLAUDII_CLR_RESET}"
    [[ -n "${_sf_agent[$_i]}" ]]    && line+=" ${CLAUDII_CLR_DIM}[agent:${_sf_agent[$_i]}]${CLAUDII_CLR_RESET}"
    printf '%s\n' "$line"

    # Line 2: context bar + rate limits + age
    detail="    "
    if [[ -n "${_sf_ctx[$_i]}" && "${_sf_ctx[$_i]}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      _ctx_display="${_sf_ctx[$_i]%.*}"
      (( _ctx_display > 100 )) && _ctx_display=100
      (( _ctx_display < 0 ))   && _ctx_display=0
      _render_ctx_bar "$_ctx_display"
      detail+="${_CTX_BAR} ${_ctx_display}%"
    fi
    if [[ -n "${_sf_rate5h[$_i]}" && "${_sf_rate5h[$_i]}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      detail+="  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}5h${_rate_mark}${CLAUDII_CLR_RESET} $(_rate_pct_disp "${_sf_rate5h[$_i]}")%"
      if [[ -n "${_sf_reset5h[$_i]}" && "${_sf_reset5h[$_i]}" =~ ^[0-9]+$ ]]; then
        _rem=$(( ${_sf_reset5h[$_i]} - now ))
        (( _rem > 0 )) && detail+=" ${CLAUDII_CLR_DIM}↺$(( _rem / 60 ))m${CLAUDII_CLR_RESET}"
      fi
      # Pace glyph — shown after 5h rate when cached (opt-in signal, no noise when absent)
      case "${_sf_pace[$_i]:-}" in
        ahead)   detail+=" ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_PACE_AHEAD}${CLAUDII_CLR_RESET}" ;;
        on_pace) detail+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_PACE_ON}${CLAUDII_CLR_RESET}"     ;;
        behind)  detail+=" ${CLAUDII_CLR_YELLOW}${CLAUDII_SYM_PACE_BEHIND}${CLAUDII_CLR_RESET}" ;;
      esac
    fi
    # Cron glyph — shown when next_cron_at is in the future (written by claudii-stop-hook)
    if [[ "${_sf_cron[$_i]:-}" =~ ^[0-9]+$ && "${_sf_cron[$_i]}" != "0" ]]; then
      _fmt_rel $(( ${_sf_cron[$_i]} - now ))
      [[ -n "$_REL_FMT" ]] && detail+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_CRON}${_REL_FMT}${CLAUDII_CLR_RESET}"
    fi
    detail+="  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP} ${_AGE_STR}${CLAUDII_CLR_RESET}"
    printf '%s\n' "$detail"

    # Line 3: resume command with full session UUID
    if [[ -n "${_sf_sid[$_i]}" ]]; then
      printf "    ${CLAUDII_CLR_DIM}claude -r ${CLAUDII_CLR_RESET}${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "${_sf_sid[$_i]}"
    fi

    # Line 4: fingerprint — cross-session colored file names
    if [[ -n "${_sf_fingerprint[$_i]}" ]]; then
      printf "    ${CLAUDII_CLR_DIM}${CLAUDII_SYM_FINGERPRINT}${CLAUDII_CLR_RESET} %s\n" "$(_colorize_fingerprint "${_sf_fingerprint[$_i]}")"
    fi

    printf '\n'
  done

  # Summary
  printf "  ${CLAUDII_CLR_ACCENT}%d active, %d ended${CLAUDII_CLR_RESET}" "$active" "$stale"
  if [[ -n "$latest_5h" ]]; then
    reset_str=""
    if [[ -n "$latest_reset" && "$latest_reset" != "0" ]]; then
      remaining=$(( latest_reset - now ))
      (( remaining > 0 )) && reset_str=" (resets in $(( remaining / 60 ))min)"
    fi
    printf "  ${CLAUDII_CLR_DIM}5h%s:%s%% 7d%s:%s%%%s${CLAUDII_CLR_RESET}" "$_rate_mark" "$(_rate_pct_disp "$latest_5h")" "$_rate_mark" "$(_rate_pct_disp "$latest_7d")" "$reset_str"
  fi
  printf '\n'
  printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_ACTIVE} active  ${CLAUDII_SYM_INACTIVE} ended  ${CLAUDII_SYM_FINGERPRINT} file(N) = most-touched files  ·  claude -r = resume session${CLAUDII_CLR_RESET}\n"
  printf '\n'
}

_cmd_gc() {
  local _insights_days="" _yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      gc|g)       ;;  # command name — dispatcher passes "$@" including it
      --insights) shift; _insights_days="${1:-}" ;;
      --yes|-y)   _yes=1 ;;
      *) printf 'Usage: claudii gc [--insights DAYS [--yes]]\n' >&2; return 1 ;;
    esac
    shift
  done

  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local _removed=0 _kept=0 _now
  _now=${EPOCHSECONDS:-$(date +%s)}

  shopt -s nullglob
  local _gc_files=("$_cache_base"/session-*)
  shopt -u nullglob

  # Sweep orphan atomic-write artifacts (session-*.tmp.PID) older than 60s.
  # cc-statusline/stop-hook write to .tmp.$$ then mv; a SIGKILL between write and
  # rename leaves these behind. They are never real sessions — delete unconditionally.
  for _sf in "${_gc_files[@]+"${_gc_files[@]}"}"; do
    [[ "$_sf" == *.tmp.* ]] || continue
    local _tmp_mt
    _tmp_mt=$(_mtime "$_sf")
    if (( _now - _tmp_mt > 60 )); then
      rm -f "$_sf" && (( ++_removed ))
    fi
  done

  # ${arr[@]+…} guard: empty array + set -u = "unbound variable" on bash 3.2
  for _sf in "${_gc_files[@]+"${_gc_files[@]}"}"; do
    [[ -f "$_sf" ]] || continue
    [[ "$_sf" == *.tmp.* ]] && continue

    local _sc _ppid _pinned _sf_mt _age
    { _sc=$(<"$_sf"); } 2>/dev/null || continue

    # Extract ppid
    _ppid=""
    if [[ $'\n'"$_sc" == *$'\n'ppid=* ]]; then
      _tmp="${_sc#*$'\n'ppid=}"; _ppid="${_tmp%%$'\n'*}"
    fi

    # Extract pinned
    _pinned=""
    if [[ $'\n'"$_sc" == *$'\n'pinned=* ]]; then
      _tmp="${_sc#*$'\n'pinned=}"; _pinned="${_tmp%%$'\n'*}"
    fi

    # Never GC pinned sessions
    if [[ "$_pinned" == "1" ]]; then
      (( ++_kept ))
      continue
    fi

    # Get file mtime
    _sf_mt=$(_mtime "$_sf")
    _age=$(( _now - _sf_mt ))

    if [[ "$_ppid" =~ ^[0-9]+$ && "$_ppid" != "0" ]]; then
      # PID-tracked session: remove if PID dead AND age > 300s
      if (( _age > 300 )) && ! kill -0 "$_ppid" 2>/dev/null; then
        rm -f "$_sf" && (( ++_removed ))
      else
        (( ++_kept ))
      fi
    else
      # Age-only session: remove if older than 300s
      if (( _age > 300 )); then
        rm -f "$_sf" && (( ++_removed ))
      else
        (( ++_kept ))
      fi
    fi
  done

  local _ks="" _rs=""
  (( _kept    != 1 )) && _ks="s"
  (( _removed != 1 )) && _rs="s"

  if (( _removed == 0 )); then
    printf "Nothing to clean up  (%d session file%s retained)\n" "$_kept" "$_ks"
  else
    printf "Removed %d stale session file%s  (%d retained)\n" "$_removed" "$_rs" "$_kept"
  fi

  # Opt-in: prune orphaned insights caches (source JSONL deleted by Claude
  # Code). Dry-run unless --yes — orphans are the long-range cost history.
  if [[ -n "$_insights_days" ]]; then
    local _gc_args=(gc --older-than "$_insights_days")
    (( _yes )) && _gc_args+=(--yes)
    "$CLAUDII_HOME/bin/claudii-insights" "${_gc_args[@]}"
  fi
}
