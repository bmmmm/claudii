# lib/cmd/sessions.sh — session data commands (cost, sessions, sessions-inactive, smart default)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_cost() {
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  shopt -s nullglob
  session_files=("$cache_dir"/session-*)
  shopt -u nullglob

  if [[ ${#session_files[@]} -eq 0 ]]; then
    echo "No session data found. Start a Claude session first."
    exit 0
  fi

  now=$(date +%s)
  # Use calendar midnight as cutoff (not rolling 24h)
  if date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s' >/dev/null 2>&1; then
    cutoff=$(date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s')
  else
    cutoff=$(date -d "$(date '+%Y-%m-%d')" '+%s')
  fi

  # Parallel indexed arrays for per-model totals (bash 3.2 compatible, no declare -A)
  _cost_models=()
  _today_cost=()
  _today_count=()
  _alltime_cost=()
  _alltime_count=()

  # Helper: find index of model in _cost_models, returns -1 if not found
  _cost_model_idx() {
    local needle="$1" _i
    for (( _i=0; _i<${#_cost_models[@]}; _i++ )); do
      [[ "${_cost_models[$_i]}" == "$needle" ]] && echo "$_i" && return
    done
    echo "-1"
  }

  for f in "${session_files[@]}"; do
    [[ -f "$f" ]] || continue

    # Read key=value pairs
    cost="" model=""
    while IFS='=' read -r key val; do
      case "$key" in
        cost)  cost="$val"  ;;
        model) model="$val" ;;
      esac
    done < "$f"

    [[ -z "$model" ]] && continue
    [[ -z "$cost" ]]  && cost="0"

    # Normalize model name to short form
    case "$model" in
      *[Oo]pus*)   short="Opus"   ;;
      *[Ss]onnet*) short="Sonnet" ;;
      *[Hh]aiku*)  short="Haiku"  ;;
      *)           short="$model" ;;
    esac

    # Get mtime
    if stat -f%m "$f" >/dev/null 2>&1; then
      mtime=$(stat -f%m "$f")
    else
      mtime=$(stat -c%Y "$f")
    fi

    # Find or add model index
    idx=$(_cost_model_idx "$short")
    if [[ "$idx" == "-1" ]]; then
      idx=${#_cost_models[@]}
      _cost_models+=("$short")
      _today_cost+=("0")
      _today_count+=("0")
      _alltime_cost+=("0")
      _alltime_count+=("0")
    fi

    # Accumulate all-time
    _alltime_cost[$idx]=$(printf '%.4f' \
      "$(echo "${_alltime_cost[$idx]} + $cost" | bc -l 2>/dev/null || echo "${_alltime_cost[$idx]}")")
    _alltime_count[$idx]=$(( ${_alltime_count[$idx]} + 1 ))

    # Accumulate today (mtime within last 24h)
    if (( mtime >= cutoff )); then
      _today_cost[$idx]=$(printf '%.4f' \
        "$(echo "${_today_cost[$idx]} + $cost" | bc -l 2>/dev/null || echo "${_today_cost[$idx]}")")
      _today_count[$idx]=$(( ${_today_count[$idx]} + 1 ))
    fi
  done

  if [[ "$_FORMAT" == "json" ]]; then
    # Build JSON with today + alltime breakdown
    today_obj="{}"
    alltime_obj="{}"
    for (( _i=0; _i<${#_cost_models[@]}; _i++ )); do
      m="${_cost_models[$_i]}"
      if [[ "${_today_count[$_i]}" != "0" ]]; then
        today_obj=$(echo "$today_obj" | jq --arg m "$m" --argjson c "${_today_cost[$_i]}" --argjson n "${_today_count[$_i]}" \
          '.[$m] = {cost: $c, sessions: $n}')
      fi
      alltime_obj=$(echo "$alltime_obj" | jq --arg m "$m" --argjson c "${_alltime_cost[$_i]}" --argjson n "${_alltime_count[$_i]}" \
        '.[$m] = {cost: $c, sessions: $n}')
    done
    jq -n --argjson today "$today_obj" --argjson alltime "$alltime_obj" \
      '{"today": $today, "alltime": $alltime}'
    exit 0
  elif [[ "$_FORMAT" == "tsv" ]]; then
    printf "period\tmodel\tcost\tsessions\n"
    for (( _i=0; _i<${#_cost_models[@]}; _i++ )); do
      m="${_cost_models[$_i]}"
      [[ "${_today_count[$_i]}" != "0" ]] && \
        printf "today\t%s\t%s\t%s\n" "$m" "${_today_cost[$_i]}" "${_today_count[$_i]}"
      printf "alltime\t%s\t%s\t%s\n" "$m" "${_alltime_cost[$_i]}" "${_alltime_count[$_i]}"
    done
    exit 0
  fi

  line='  ─────────────────'

  _print_section() {
    local section="$1"  # "today" or "alltime"
    local total=0 has_data=0
    for (( _pi=0; _pi<${#_cost_models[@]}; _pi++ )); do
      local _pm="${_cost_models[$_pi]}"
      if [[ "$section" == "today" ]]; then
        local _pc="${_today_cost[$_pi]}" _pn="${_today_count[$_pi]}"
      else
        local _pc="${_alltime_cost[$_pi]}" _pn="${_alltime_count[$_pi]}"
      fi
      [[ "$_pn" == "0" ]] && continue
      printf "    %-10s ${CLAUDII_CLR_CYAN}\$%s${CLAUDII_CLR_RESET}  (%s session%s)\n" \
        "$_pm" "$(printf '%.2f' "$_pc")" "$_pn" "$( (( _pn != 1 )) && echo 's' || true)"
      total=$(echo "$total + $_pc" | bc -l)
      has_data=1
    done
    if (( has_data )); then
      printf '%s\n' "$line"
      printf "    %-10s ${CLAUDII_CLR_CYAN}\$%s${CLAUDII_CLR_RESET}\n" "Total" "$(printf '%.2f' "$total")"
    else
      printf "    (none)\n"
    fi
  }

  printf '\n'
  printf "  ${CLAUDII_CLR_ACCENT}Today${CLAUDII_CLR_RESET}\n"
  _print_section today
  printf '\n'
  printf "  ${CLAUDII_CLR_ACCENT}All time${CLAUDII_CLR_RESET}\n"
  _print_section alltime
  printf '\n'
}

_cmd_sessions_inactive() {
  # "claudii sessions-inactive" — shows only inactive (stale/dead) sessions
  _cfg_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"

  printf '\n'
  printf "  ${CLAUDII_CLR_BOLD}Inactive Sessions${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_DIM}Sessions whose Claude Code process has ended. Cache kept until GC runs.${CLAUDII_CLR_RESET}\n"

  shopt -s nullglob
  _is_files=("$cache_dir"/session-*)
  shopt -u nullglob

  _has_files=0
  _rendered_any=0

  [[ ${#_is_files[@]} -gt 0 ]] && _has_files=1

  if [[ $_has_files -eq 1 ]]; then
    for _is_f in "${_is_files[@]}"; do
      [[ -f "$_is_f" ]] || continue

      _parse_session_cache "$_is_f"

      [[ -z "$_PSC_model" ]] && continue

      # Skip active sessions — this command shows only inactive
      if [[ $_PSC_is_active -eq 1 ]]; then continue; fi

      # Context bar
      _is_bar=""
      if [[ -n "$_PSC_ctx_pct" && "$_PSC_ctx_pct" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _is_pct=${_PSC_ctx_pct%.*}
        (( _is_pct > 100 )) && _is_pct=100
        (( _is_pct < 0 ))   && _is_pct=0
        _render_ctx_bar "$_is_pct"
        _is_bar=" ${_CTX_BAR} ${CLAUDII_CLR_DIM}${_is_pct}%${CLAUDII_CLR_RESET}"
      fi

      _is_line="  ${CLAUDII_CLR_DIM}○${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}${_PSC_model}${CLAUDII_CLR_RESET}${_is_bar}"

      if [[ -n "$_PSC_cost" && "$_PSC_cost" != "0" ]]; then
        _is_line+=" ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} ${CLAUDII_CLR_CYAN}\$$(printf '%.2f' "$_PSC_cost")${CLAUDII_CLR_RESET}"
      fi

      if [[ -n "$_PSC_cache_pct" && "$_PSC_cache_pct" != "0" ]]; then
        _is_line+=" ${CLAUDII_CLR_DIM}│ ⚡${_PSC_cache_pct}%${CLAUDII_CLR_RESET}"
      fi

      # Rate limits
      if [[ -n "$_PSC_rate_5h" && "$_PSC_rate_5h" != "0" ]] || [[ -n "$_PSC_rate_7d" && "$_PSC_rate_7d" != "0" ]]; then
        _is_line+="${CLAUDII_CLR_DIM}"
        [[ -n "$_PSC_rate_5h" && "$_PSC_rate_5h" != "0" ]] && _is_line+=" 5h:${_PSC_rate_5h%.*}%"
        [[ -n "$_PSC_rate_7d" && "$_PSC_rate_7d" != "0" ]] && _is_line+=" 7d:${_PSC_rate_7d%.*}%"
        _is_line+="${CLAUDII_CLR_RESET}"
      fi

      if [[ -n "$_PSC_worktree" ]]; then
        _is_line+=" ${CLAUDII_CLR_DIM}[wt:${_PSC_worktree}]${CLAUDII_CLR_RESET}"
      fi
      if [[ -n "$_PSC_agent" ]]; then
        _is_line+=" ${CLAUDII_CLR_DIM}[agent:${_PSC_agent}]${CLAUDII_CLR_RESET}"
      fi

      # Age
      _render_age "$_PSC_age"
      _is_line+="  ${CLAUDII_CLR_DIM}${_AGE_STR}${CLAUDII_CLR_RESET}"

      printf '%s\n' "$_is_line"
      _rendered_any=1
    done
  fi

  if [[ $_has_files -eq 1 ]] && [[ $_rendered_any -eq 0 ]]; then
    printf "  No inactive sessions.\n"
  elif [[ $_has_files -eq 0 ]]; then
    printf "  No session data found.\n"
  fi

  # GC footer: count stale files (ppid dead AND age > 3600s)
  _is_now=$(date +%s)
  _is_stale=0
  for _is_gc_f in "${_is_files[@]}"; do
    [[ -f "$_is_gc_f" ]] || continue
    _is_gc_ppid=$(grep '^ppid=' "$_is_gc_f" 2>/dev/null | cut -d= -f2 || true)
    _is_gc_mtime=$(stat -f%m "$_is_gc_f" 2>/dev/null || stat -c%Y "$_is_gc_f" 2>/dev/null || echo 0)
    (( _is_now - _is_gc_mtime < 3600 )) && continue
    [[ -n "$_is_gc_ppid" ]] && kill -0 "$_is_gc_ppid" 2>/dev/null && continue
    (( ++_is_stale ))
  done
  if (( _is_stale > 0 )); then
    printf "  ${CLAUDII_CLR_DIM}%d stale session%s pending GC${CLAUDII_CLR_RESET}\n" \
      "$_is_stale" "$( (( _is_stale != 1 )) && printf 's' || true)"
  fi

  printf '\n'
}

_cmd_sessions() {
  _cfg_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  now=$(date +%s)
  active=0 stale=0 total_cost=0
  latest_5h="" latest_7d="" latest_reset=""

  # Collect all session data into parallel arrays
  declare -a _sf_model _sf_ctx _sf_cost _sf_rate5h _sf_rate7d _sf_reset5h \
             _sf_ppid _sf_worktree _sf_agent _sf_cache _sf_sid \
             _sf_is_active _sf_age _sf_projpath _sf_sesname
  _sf_count=0

  shopt -s nullglob
  for sf in "$cache_dir"/session-*; do
    [[ -f "$sf" ]] || continue
    _parse_session_cache "$sf"

    # Accumulate cost
    if [[ -n "$_PSC_cost" && "$_PSC_cost" != "0" ]]; then
      total_cost=$(echo "$total_cost + $_PSC_cost" | bc 2>/dev/null || echo "$total_cost")
    fi

    # Track freshest rate limits
    if [[ -n "$_PSC_rate_5h" ]] && [[ "$_PSC_is_active" -eq 1 ]]; then
      latest_5h="$_PSC_rate_5h"; latest_7d="$_PSC_rate_7d"; latest_reset="$_PSC_reset_5h"
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
    # Resolve project path + session name from JSONL (only for pretty output)
    if [[ "$_FORMAT" != "json" && "$_FORMAT" != "tsv" ]]; then
      _sf_projpath[$_sf_count]=$(_session_project_path "$_PSC_session_id")
      _sf_sesname[$_sf_count]=$(_session_name "$_PSC_session_id")
      # Fallback: for active sessions with unknown session_id, try ppid cwd via lsof
      if [[ -z "${_sf_projpath[$_sf_count]}" && "$_PSC_is_active" -eq 1 && -n "$_PSC_ppid" ]]; then
        _ppid_cwd=$(lsof -p "$_PSC_ppid" -d cwd -Fn 2>/dev/null | awk '/^n/{sub(/^n/,"");print;exit}' || true)
        if [[ -n "$_ppid_cwd" ]]; then
          _ppid_cwd="${_ppid_cwd/#$HOME/\~}"
          (( ${#_ppid_cwd} > 40 )) && _ppid_cwd="...${_ppid_cwd: -37}"
          _sf_projpath[$_sf_count]="$_ppid_cwd"
        fi
      fi
    else
      _sf_projpath[$_sf_count]=""
      _sf_sesname[$_sf_count]=""
    fi
    if [[ "$_PSC_is_active" -eq 1 ]]; then
      (( ++active ))
    else
      (( ++stale ))
    fi
    (( ++_sf_count ))
  done
  shopt -u nullglob

  if [[ "$_FORMAT" == "json" ]]; then
    # Build JSON array from collected data
    _json_arr="["
    _first=1
    for (( _i=0; _i<_sf_count; _i++ )); do
      [[ "$_first" -eq 0 ]] && _json_arr+=","
      _json_arr+=$(jq -n \
        --arg model "${_sf_model[$_i]}" \
        --arg ctx_pct "${_sf_ctx[$_i]}" \
        --arg cost "${_sf_cost[$_i]:-0}" \
        --arg rate_5h "${_sf_rate5h[$_i]}" \
        --arg rate_7d "${_sf_rate7d[$_i]}" \
        --arg reset_5h "${_sf_reset5h[$_i]}" \
        --arg session_id "${_sf_sid[$_i]}" \
        --arg worktree "${_sf_worktree[$_i]}" \
        --arg agent "${_sf_agent[$_i]}" \
        --arg age "${_sf_age[$_i]}" \
        --arg status "${_sf_is_active[$_i]}" \
        '{model:$model, ctx_pct:($ctx_pct|if .=="" then null else tonumber? end),
          cost:($cost|tonumber? // 0), rate_5h:($rate_5h|if .=="" then null else tonumber? end),
          rate_7d:($rate_7d|if .=="" then null else tonumber? end),
          reset_5h:($reset_5h|if .=="" then null else tonumber? end),
          session_id:$session_id, worktree:$worktree, agent:$agent,
          age_seconds:($age|tonumber), status:$status}')
      _first=0
    done
    _json_arr+="]"
    echo "$_json_arr" | jq .
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

  # Pretty output — two lines per session for visual clarity
  printf '\n'
  for (( _i=0; _i<_sf_count; _i++ )); do
    if [[ "${_sf_is_active[$_i]}" -eq 1 ]]; then
      status_icon="${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET}"
    else
      status_icon="${CLAUDII_CLR_DIM}○${CLAUDII_CLR_RESET}"
    fi
    _render_age "${_sf_age[$_i]}"

    # Line 1: status indicator + model + project path + session name + metadata
    line="  ${status_icon} ${CLAUDII_CLR_ACCENT}${_sf_model[$_i]:-?}${CLAUDII_CLR_RESET}"
    if [[ -n "${_sf_projpath[$_i]}" ]]; then
      line+="  ${CLAUDII_CLR_DIM}${_sf_projpath[$_i]}${CLAUDII_CLR_RESET}"
    else
      line+="  ${CLAUDII_CLR_DIM}(path unknown)${CLAUDII_CLR_RESET}"
    fi
    [[ -n "${_sf_sesname[$_i]}" ]]  && line+="  ${CLAUDII_CLR_DIM}\"${_sf_sesname[$_i]}\"${CLAUDII_CLR_RESET}"
    [[ -n "${_sf_worktree[$_i]}" ]] && line+=" ${CLAUDII_CLR_DIM}[wt:${_sf_worktree[$_i]}]${CLAUDII_CLR_RESET}"
    [[ -n "${_sf_agent[$_i]}" ]]    && line+=" ${CLAUDII_CLR_DIM}[agent:${_sf_agent[$_i]}]${CLAUDII_CLR_RESET}"
    printf '%s\n' "$line"

    # Line 2: context bar + cost + rate limits + age + session id (indented)
    detail="    "
    if [[ -n "${_sf_ctx[$_i]}" && "${_sf_ctx[$_i]}" =~ ^[0-9] ]]; then
      _render_ctx_bar "${_sf_ctx[$_i]%.*}"
      detail+="${_CTX_BAR} ${_sf_ctx[$_i]%.*}%"
    fi
    if [[ -n "${_sf_cost[$_i]}" && "${_sf_cost[$_i]}" != "0" ]]; then
      detail+="  ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} ${CLAUDII_CLR_CYAN}\$$(printf '%.2f' "${_sf_cost[$_i]}")${CLAUDII_CLR_RESET}"
    fi
    if [[ -n "${_sf_rate5h[$_i]}" ]]; then
      detail+="  ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} 5h:${_sf_rate5h[$_i]%.*}%"
      if [[ -n "${_sf_reset5h[$_i]}" && "${_sf_reset5h[$_i]}" =~ ^[0-9]+$ ]]; then
        _rem=$(( ${_sf_reset5h[$_i]} - now ))
        (( _rem > 0 )) && detail+=" ↺$(( _rem / 60 ))m"
      fi
    fi
    detail+="  ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}${_AGE_STR}${CLAUDII_CLR_RESET}"
    if [[ -n "${_sf_sid[$_i]}" ]]; then
      detail+="  ${CLAUDII_CLR_DIM}${_sf_sid[$_i]:0:8}${CLAUDII_CLR_RESET}"
    else
      detail+="  ${CLAUDII_CLR_DIM}(id unknown)${CLAUDII_CLR_RESET}"
    fi
    printf '%s\n\n' "$detail"
  done

  # Summary
  printf '\n'
  total_fmt=$(printf '$%.2f' "$total_cost")
  printf "  ${CLAUDII_CLR_ACCENT}%d aktiv, %d beendet, %s total${CLAUDII_CLR_RESET}" "$active" "$stale" "$total_fmt"
  if [[ -n "$latest_5h" ]]; then
    reset_str=""
    if [[ -n "$latest_reset" && "$latest_reset" != "0" ]]; then
      remaining=$(( latest_reset - now ))
      (( remaining > 0 )) && reset_str=" (Reset in $(( remaining / 60 ))min)"
    fi
    printf "  ${CLAUDII_CLR_DIM}5h:%s%% 7d:%s%%%s${CLAUDII_CLR_RESET}" "${latest_5h%.*}" "${latest_7d%.*}" "$reset_str"
  fi
  printf '\n\n'
}

_cmd_default() {
  # Smart account overview: Sessions · Account · Agents · Services
  _cfg_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  now=$(date +%s)

  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_ACCENT}v%s${CLAUDII_CLR_RESET}\n" "$VERSION"
  printf '\n'

  # ── Gather session data ────────────────────────────────────────────
  shopt -s nullglob
  _ov_files=("$cache_dir"/session-*)
  shopt -u nullglob

  _ov_acct_5h="" _ov_acct_7d="" _ov_acct_reset="" _ov_acct_7d_start="" _ov_acct_reset_7d="" _ov_acct_mt=0
  _ov_today_cost=0 _ov_today_count=0 _ov_stale=0
  # Use calendar midnight as cutoff (not rolling 24h)
  if date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s' >/dev/null 2>&1; then
    _ov_cutoff=$(date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s')
  else
    _ov_cutoff=$(date -d "$(date '+%Y-%m-%d')" '+%s')
  fi
  _ov_any_session=0
  _ov_active_count=0 _ov_inactive_count=0

  if [[ ${#_ov_files[@]} -gt 0 ]]; then
    for _ov_f in "${_ov_files[@]}"; do
      [[ -f "$_ov_f" ]] || continue

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

      # Today's cost accumulation
      if (( _PSC_mtime >= _ov_cutoff )); then
        _ov_today_count=$(( _ov_today_count + 1 ))
        if [[ -n "$_PSC_cost" && "$_PSC_cost" != "0" ]]; then
          _ov_today_cost=$(echo "$_ov_today_cost + $_PSC_cost" | bc 2>/dev/null || echo "$_ov_today_cost")
        fi
      fi

      # Count active vs inactive; count stale (dead ppid, age > 24h) for GC hint
      if [[ "$_PSC_is_active" -eq 1 ]]; then
        (( ++_ov_active_count ))
      else
        (( ++_ov_inactive_count ))
        if (( _PSC_age >= 86400 )); then
          [[ -z "$_PSC_ppid" ]] || ! kill -0 "$_PSC_ppid" 2>/dev/null && (( _ov_stale++ ))
        fi
      fi
    done
  fi

  # ── Account ───────────────────────────────────────────────────────
  printf '\n'
  if [[ -n "$_ov_acct_5h" ]]; then
    printf "  ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Account${CLAUDII_CLR_RESET}\n"

    _ov_5h_int=${_ov_acct_5h%.*}
    # 5h urgency color: < 50% green, 50-79% yellow, >= 80% red
    if (( _ov_5h_int >= 80 )); then
      _ov_5h_clr="${CLAUDII_CLR_RED}"
    elif (( _ov_5h_int >= 50 )); then
      _ov_5h_clr="${CLAUDII_CLR_YELLOW}"
    else
      _ov_5h_clr="${CLAUDII_CLR_GREEN}"
    fi
    _ov_acct_line="    5h: ${_ov_5h_clr}${_ov_5h_int}%${CLAUDII_CLR_RESET}"
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
        _ov_acct_line+=" ${_ov_reset_clr}reset ${_ov_rem_min}min${CLAUDII_CLR_RESET}"
      fi
    fi
    if [[ -n "$_ov_acct_7d" ]]; then
      _ov_7d_int=${_ov_acct_7d%.*}
      # 7d urgency color: < 50% green, 50-79% yellow, >= 80% red
      if (( _ov_7d_int >= 80 )); then
        _ov_7d_clr="${CLAUDII_CLR_RED}"
      elif (( _ov_7d_int >= 50 )); then
        _ov_7d_clr="${CLAUDII_CLR_YELLOW}"
      else
        _ov_7d_clr="${CLAUDII_CLR_GREEN}"
      fi
      _ov_acct_line+=" ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} 7d: ${_ov_7d_clr}${_ov_7d_int}%${CLAUDII_CLR_RESET}"
      # 7d delta
      if [[ -n "$_ov_acct_7d_start" ]]; then
        _ov_delta=$(( _ov_7d_int - ${_ov_acct_7d_start%.*} ))
        (( _ov_delta > 0 )) && _ov_acct_line+=" ${CLAUDII_CLR_DIM}(+${_ov_delta}%)${CLAUDII_CLR_RESET}"
      fi
      # 7d reset countdown
      if [[ -n "$_ov_acct_reset_7d" && "$_ov_acct_reset_7d" != "0" ]]; then
        _ov_r7d_rem=$(( _ov_acct_reset_7d - now ))
        if (( _ov_r7d_rem > 0 )); then
          if (( _ov_r7d_rem >= 86400 )); then
            _ov_r7d_d=$(( _ov_r7d_rem / 86400 ))
            _ov_r7d_h=$(( (_ov_r7d_rem % 86400) / 3600 ))
            _ov_acct_line+=" ${CLAUDII_CLR_DIM}reset ${_ov_r7d_d}d${_ov_r7d_h}h${CLAUDII_CLR_RESET}"
          elif (( _ov_r7d_rem >= 3600 )); then
            _ov_r7d_h=$(( _ov_r7d_rem / 3600 ))
            _ov_acct_line+=" ${CLAUDII_CLR_DIM}reset ${_ov_r7d_h}h${CLAUDII_CLR_RESET}"
          else
            _ov_acct_line+=" ${CLAUDII_CLR_DIM}reset $(( _ov_r7d_rem / 60 ))min${CLAUDII_CLR_RESET}"
          fi
        fi
      fi
    fi
    # Today's cost with accent color, and session count
    if (( _ov_today_count > 0 )); then
      _ov_today_fmt=$(printf '%.2f' "$_ov_today_cost")
      _ov_s=""; (( _ov_today_count != 1 )) && _ov_s="s"
      _ov_acct_line+=" ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}\$${_ov_today_fmt}${CLAUDII_CLR_RESET} today (${_ov_today_count} session${_ov_s})"
    fi
    printf '%s\n' "$_ov_acct_line"
  else
    printf "  ${CLAUDII_CLR_DIM}○ Account                         rate limits appear after first session${CLAUDII_CLR_RESET}\n"
  fi

  # ── Agents ────────────────────────────────────────────────────────
  printf '\n'
  _ov_agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$CONFIG" 2>/dev/null)
  [[ -z "$_ov_agents_json" ]] && _ov_agents_json=$(jq -r 'if (.agents // {}) | keys | length > 0 then .agents | tojson else empty end' "$DEFAULTS" 2>/dev/null)

  if [[ -n "$_ov_agents_json" ]]; then
    printf "  ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Agents${CLAUDII_CLR_RESET}\n"
    while IFS=$'\t' read -r _a_alias _a_skill _a_model _a_effort; do
      printf "    %-8s  %-12s  %s/%s\n" "$_a_alias" "$_a_skill" "$_a_model" "$_a_effort"
    done < <(echo "$_ov_agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // "")] | @tsv')
  else
    printf "  ${CLAUDII_CLR_DIM}○ Agents                          claudii agents to configure${CLAUDII_CLR_RESET}\n"
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
  [[ -f "$_ov_sl_settings" ]] && jq -e '.statusLine.command == "claudii-sessionline"' "$_ov_sl_settings" >/dev/null 2>&1 && _ov_sl_on=1
  _ov_watch_pid="$cache_dir/watch.pid"
  _ov_watch_on=0
  [[ -f "$_ov_watch_pid" ]] && kill -0 "$(<"$_ov_watch_pid")" 2>/dev/null && _ov_watch_on=1

  _ov_svc_any=0
  [[ "$_ov_cs_en" == "true" ]]   && _ov_svc_any=1
  [[ "$_ov_dash_en" != "off" ]]  && _ov_svc_any=1
  (( _ov_sl_on ))                && _ov_svc_any=1
  (( _ov_watch_on ))             && _ov_svc_any=1

  if (( _ov_svc_any )); then
    printf "  ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Services${CLAUDII_CLR_RESET}\n"
  else
    printf "  ${CLAUDII_CLR_DIM}○${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Services${CLAUDII_CLR_RESET}\n"
  fi

  # ClaudeStatus — with inline model health when on
  if [[ "$_ov_cs_en" == "true" ]]; then
    _ov_model_health=""
    _ov_status_cache="$cache_dir/status-models"
    if [[ -f "$_ov_status_cache" ]]; then
      _ov_health_str=""
      while IFS='=' read -r _om _os; do
        [[ -z "$_om" || "$_om" == _* ]] && continue
        case "$_om" in
          opus)   _om_cap="Opus"   ;;
          sonnet) _om_cap="Sonnet" ;;
          haiku)  _om_cap="Haiku"  ;;
          *)      _om_cap="$_om"   ;;
        esac
        case "$_os" in
          ok)       _ov_health_str+="${CLAUDII_CLR_GREEN}${_om_cap} ✓${CLAUDII_CLR_RESET} " ;;
          degraded) _ov_health_str+="${CLAUDII_CLR_YELLOW}${_om_cap} ⚠${CLAUDII_CLR_RESET} " ;;
          down)     _ov_health_str+="${CLAUDII_CLR_RED}${_om_cap} ✗${CLAUDII_CLR_RESET} " ;;
        esac
      done < "$_ov_status_cache"
      [[ -n "$_ov_health_str" ]] && _ov_model_health="  ${CLAUDII_CLR_DIM}[${CLAUDII_CLR_RESET}${_ov_health_str% }${CLAUDII_CLR_DIM}]${CLAUDII_CLR_RESET}"
    fi
    printf "    ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} ClaudeStatus%s\n" "$_ov_model_health"
  else
    printf "    ${CLAUDII_CLR_DIM}○ ClaudeStatus%-20s claudii on${CLAUDII_CLR_RESET}\n" ""
  fi

  # Session Dashboard
  if [[ "$_ov_dash_en" != "off" ]]; then
    printf "    ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} Dashboard\n"
  else
    printf "    ${CLAUDII_CLR_DIM}○ Dashboard%-23s claudii dashboard on${CLAUDII_CLR_RESET}\n" ""
  fi

  # CC-Statusline
  if (( _ov_sl_on )); then
    printf "    ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} CC-Statusline\n"
  else
    printf "    ${CLAUDII_CLR_DIM}○ CC-Statusline%-20s claudii cc-statusline on${CLAUDII_CLR_RESET}\n" ""
  fi

  # Watch
  if (( _ov_watch_on )); then
    printf "    ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} Watch\n"
  else
    printf "    ${CLAUDII_CLR_DIM}○ Watch%-27s claudii watch start${CLAUDII_CLR_RESET}\n" ""
  fi

  # ── Sessions — summary only; details via `claudii se` ────────────
  printf '\n'
  if (( _ov_any_session )); then
    if (( _ov_active_count > 0 )); then
      printf "  ${CLAUDII_CLR_GREEN}●${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Sessions${CLAUDII_CLR_RESET}\n"
      _ov_s=""; (( _ov_active_count != 1 )) && _ov_s="s"
      printf "    %d active session%s  ${CLAUDII_CLR_DIM}·  claudii se for details${CLAUDII_CLR_RESET}\n" \
        "$_ov_active_count" "$_ov_s"
    else
      printf "  ${CLAUDII_CLR_DIM}○${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Sessions${CLAUDII_CLR_RESET}\n"
    fi

    (( _ov_inactive_count > 0 )) && \
      printf "    ${CLAUDII_CLR_DIM}%d inactive  ·  claudii si${CLAUDII_CLR_RESET}\n" "$_ov_inactive_count"

    # Stale session GC hint: > 5 dead sessions older than 24h (counted in first loop)
    (( _ov_stale > 5 )) && \
      printf "    ${CLAUDII_CLR_DIM}%d stale sessions  ·  claudii si${CLAUDII_CLR_RESET}\n" "$_ov_stale"
  else
    printf "  ${CLAUDII_CLR_DIM}○ Sessions                        start Claude to see data here${CLAUDII_CLR_RESET}\n"
  fi

  printf '\n'
  printf "  ${CLAUDII_CLR_DIM}claudii help  for all commands${CLAUDII_CLR_RESET}\n"
  printf '\n'
}
