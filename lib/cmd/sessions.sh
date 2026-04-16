# lib/cmd/sessions.sh — session data commands (cost, sessions, sessions-inactive, smart default)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail
# _claudii_spinner is defined in lib/spinner.sh (sourced by bin/claudii)

# _cmd_cost_from_history — cost breakdown with correct daily deltas from history.tsv
# Each session's cost on a given day = last_cost_that_day - last_cost_previous_day.
# This avoids attributing multi-day sessions' full cost to their last active day.
_cmd_cost_from_history() {
  # Last argument is today_str, all preceding args are history file paths
  local today_str="${@: -1}"   # YYYY-MM-DD for "today" cutoff
  local -a _history_files=("${@:1:$#-1}")

  _date_init
  local _date_cmd="$_DATE_CMD" _tz_offset="$_TZ_OFFSET" _ws_dow="$_WS_DOW"

  # Pure-awk date conversion — shared epoch_to_date from lib/epoch_to_date.awk
  local _epoch_awk
  _epoch_awk=$(<"$CLAUDII_HOME/lib/epoch_to_date.awk")
  local _augmented
  _augmented=$(awk -F'\t' -v tz_offset="${_tz_offset:-0}" "
${_epoch_awk}
"'
    $1 == "timestamp" || $1 == "" || $6 == "" { next }
    {
      ts = $1 + 0; if (ts == 0) next
      day = epoch_to_date(ts)
      model = $2; cost = $3 + 0; sid = $6; raw = $2
      in_tok = ($7 == "" ? 0 : $7 + 0); out_tok = ($8 == "" ? 0 : $8 + 0)
      if      (model ~ /[Oo]pus/)   model = "Opus"
      else if (model ~ /[Ss]onnet/) model = "Sonnet"
      else if (model ~ /[Hh]aiku/)  model = "Haiku"
      print day "\t" model "\t" cost "\t" sid "\t" raw "\t" in_tok "\t" out_tok
    }
  ' "${_history_files[@]}")

  if [[ -z "$_augmented" ]]; then
    echo "  No history data found — start a Claude session to record costs."
    return
  fi

  # Compute week start based on configured week_start day (local time)
  local today_dow week_start_str today_mon today_year _week_start_ts _days_back
  if [[ "$_date_cmd" == "macos" ]]; then
    today_dow=$(date -j -f '%Y-%m-%d' "$today_str" '+%u' 2>/dev/null)
    _days_back=$(( (today_dow - _ws_dow + 7) % 7 ))
    _week_start_ts=$(( $(date -j -f '%Y-%m-%d' "$today_str" '+%s' 2>/dev/null) - _days_back * 86400 ))
    week_start_str=$(date -j -f '%s' "$_week_start_ts" '+%Y-%m-%d' 2>/dev/null)
  else
    today_dow=$(date -d "$today_str" '+%u' 2>/dev/null)
    _days_back=$(( (today_dow - _ws_dow + 7) % 7 ))
    _week_start_ts=$(( $(date -d "$today_str" '+%s' 2>/dev/null) - _days_back * 86400 ))
    week_start_str=$(date -d "@$_week_start_ts" '+%Y-%m-%d' 2>/dev/null)
  fi
  today_mon="${today_str:0:7}"   # YYYY-MM
  today_year="${today_str:0:4}"  # YYYY

  # awk: compute daily deltas, aggregate into today/week/month/year/alltime
  echo "$_augmented" | awk -F'\t' \
    -v today="$today_str" \
    -v week_start="${week_start_str:-$today_str}" \
    -v fmt="${_FORMAT:-}" \
    -v cyan="$CLAUDII_CLR_CYAN" \
    -v dim="$CLAUDII_CLR_DIM" \
    -v pink="$CLAUDII_CLR_ACCENT" \
    -v reset="$CLAUDII_CLR_RESET" \
    '
    function fmt_tok(t) {
      if (t >= 1000000) return sprintf("%.1fM", t / 1000000)
      if (t >= 1000)    return sprintf("%.0fK", t / 1000)
      if (t > 0)        return t ""
      return ""
    }
    {
      day = $1; model = $2; cost = $3 + 0; sid = $4; raw = $5
      in_tok = $6 + 0; out_tok = $7 + 0; total_tok = in_tok + out_tok
      if (sid == "" || day == "") next
      key = sid SUBSEP day

      # Track most informative display name (prefer versioned, e.g. "Opus 4.6" > "Opus")
      if (raw != "" && (!(model in model_display) || \
          (index(raw, ".") > 0 && index(model_display[model], ".") == 0)))
        model_display[model] = raw

      # running_spend[sid]: cumulative spend from first observation.
      # Increments on cost increases; on reset (cost drops) adds the new post-reset cost
      # as fresh spend. This correctly accounts for intra-day resets (e.g. context compaction).
      if (sid in sid_baseline) {
        prev = sid_baseline[sid]
        if (cost > prev) {
          running_spend[sid] += cost - prev
        } else if (cost < prev * 0.5) {
          running_spend[sid] += cost  # genuine reset (context compaction)
        } # else: minor fluctuation — update baseline silently
      } else {
        running_spend[sid] = cost  # first row: treat starting cost as spend (like prev=0)
      }
      sid_baseline[sid] = cost

      # Token running_spend — same delta approach as cost
      if (sid in tok_baseline) {
        prev_tok = tok_baseline[sid]
        if (total_tok > prev_tok)            { tok_running[sid] += total_tok - prev_tok }
        else if (total_tok < prev_tok * 0.5) { tok_running[sid] += total_tok }
      } else {
        tok_running[sid] = total_tok
      }
      tok_baseline[sid] = total_tok
      day_tok_snapshot[key] = tok_running[sid]

      # Record running_spend snapshot at end of each (session, day)
      day_spend[key] = running_spend[sid]
      sid_model[key] = model
      if (!(sid SUBSEP day in sid_has_day)) {
        sid_day_list[sid] = (sid in sid_day_list) ? (sid_day_list[sid] " " day) : day
        sid_has_day[sid SUBSEP day] = 1
      }
      all_sids[sid] = 1
    }
    END {
      for (sid in all_sids) {
        n = split(sid_day_list[sid], days_arr, " ")
        # Bubble sort ascending (YYYY-MM-DD is lexicographically ordered)
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            if (days_arr[i] > days_arr[j]) { tmp = days_arr[i]; days_arr[i] = days_arr[j]; days_arr[j] = tmp }
        prev_spend = 0; prev_tok = 0
        for (i = 1; i <= n; i++) {
          d = days_arr[i]
          k = sid SUBSEP d
          cur_spend = (k in day_spend) ? day_spend[k] : 0
          cur_tok   = (k in day_tok_snapshot) ? day_tok_snapshot[k] : 0
          delta     = cur_spend - prev_spend
          tok_delta = cur_tok - prev_tok
          if (delta < 0)     delta = 0
          if (tok_delta < 0) tok_delta = 0
          m = (k in sid_model) ? sid_model[k] : "?"
          prev_spend = cur_spend; prev_tok = cur_tok
          all_models[m] = 1
          alltime_cost[m] += delta; seen_sid_alltime[m SUBSEP sid] = 1; alltime_tok += tok_delta
          if (d == today)      { today_cost[m] += delta; seen_sid_today[m SUBSEP sid] = 1; today_tok += tok_delta }
          if (d >= week_start) { week_cost[m]  += delta; seen_sid_week[m SUBSEP sid]  = 1; week_tok  += tok_delta }
          mon_key = substr(d, 1, 7)
          month_cost[m SUBSEP mon_key] += delta; seen_sid_month[m SUBSEP mon_key SUBSEP sid] = 1; month_tok[mon_key] += tok_delta
          all_months[mon_key] = 1
          yr_key = substr(d, 1, 4)
          year_cost[m SUBSEP yr_key] += delta; seen_sid_year[m SUBSEP yr_key SUBSEP sid] = 1; year_tok[yr_key] += tok_delta
          all_years[yr_key] = 1
        }
      }

      # Sort months descending (bubble sort on keys — YYYY-MM sorts lexically)
      n_mon = 0; for (mk in all_months) mon_keys[++n_mon] = mk
      for (i = 1; i <= n_mon; i++) for (j = i+1; j <= n_mon; j++)
        if (mon_keys[i] < mon_keys[j]) { tmp = mon_keys[i]; mon_keys[i] = mon_keys[j]; mon_keys[j] = tmp }
      # Sort years descending
      n_yr = 0; for (yk in all_years) yr_keys[++n_yr] = yk
      for (i = 1; i <= n_yr; i++) for (j = i+1; j <= n_yr; j++)
        if (yr_keys[i] < yr_keys[j]) { tmp = yr_keys[i]; yr_keys[i] = yr_keys[j]; yr_keys[j] = tmp }

      # Derive session counts from distinct-SID sets (Bug 1 fix: count unique SIDs, not day-entries)
      for (k in seen_sid_alltime) { split(k, _p, SUBSEP); alltime_sessions[_p[1]]++ }
      for (k in seen_sid_today)   { split(k, _p, SUBSEP); today_sessions[_p[1]]++ }
      for (k in seen_sid_week)    { split(k, _p, SUBSEP); week_sessions[_p[1]]++ }
      for (k in seen_sid_month) {
        split(k, _p, SUBSEP)   # _p[1]=model _p[2]=mon_key _p[3]=sid
        month_sessions[_p[1] SUBSEP _p[2]]++
      }
      for (k in seen_sid_year) {
        split(k, _p, SUBSEP)   # _p[1]=model _p[2]=yr_key _p[3]=sid
        year_sessions[_p[1] SUBSEP _p[2]]++
      }

      # --- JSON output ---
      if (fmt == "json") {
        printf "{"
        # today
        printf "\"today\":{"
        first = 1
        for (m in all_models) {
          if (!(m in today_cost) || today_sessions[m] == 0) continue
          if (!first) printf ","
          printf "\"%s\":{\"cost\":%.4f,\"sessions\":%d}", m, today_cost[m], today_sessions[m]
          first = 0
        }
        printf "},"
        # week
        printf "\"week\":{"
        first = 1
        for (m in all_models) {
          if (!(m in week_cost) || week_sessions[m] == 0) continue
          if (!first) printf ","
          printf "\"%s\":{\"cost\":%.4f,\"sessions\":%d}", m, week_cost[m], week_sessions[m]
          first = 0
        }
        printf "},"
        # months
        printf "\"months\":{"
        first = 1
        for (i = 1; i <= n_mon; i++) {
          mk = mon_keys[i]
          if (!first) printf ","
          printf "\"%s\":{", mk
          inner = 1
          for (m in all_models) {
            k = m SUBSEP mk
            if (!(k in month_cost)) continue
            if (!inner) printf ","
            printf "\"%s\":{\"cost\":%.4f,\"sessions\":%d}", m, month_cost[k], month_sessions[k]
            inner = 0
          }
          printf "}"
          first = 0
        }
        printf "},"
        # years
        printf "\"years\":{"
        first = 1
        for (i = 1; i <= n_yr; i++) {
          yk = yr_keys[i]
          if (!first) printf ","
          printf "\"%s\":{", yk
          inner = 1
          for (m in all_models) {
            k = m SUBSEP yk
            if (!(k in year_cost)) continue
            if (!inner) printf ","
            printf "\"%s\":%.4f", m, year_cost[k]
            inner = 0
          }
          printf "}"
          first = 0
        }
        printf "}}"
        printf "\n"
        exit
      }

      # --- TSV output ---
      if (fmt == "tsv") {
        printf "period\tmodel\tcost\tsessions\n"
        for (m in all_models) {
          if (m in today_cost && today_sessions[m] > 0)
            printf "today\t%s\t%.4f\t%d\n", m, today_cost[m], today_sessions[m]
          if (m in week_cost && week_sessions[m] > 0)
            printf "week\t%s\t%.4f\t%d\n", m, week_cost[m], week_sessions[m]
        }
        for (i = 1; i <= n_mon; i++) {
          mk = mon_keys[i]
          for (m in all_models) {
            k = m SUBSEP mk
            if (k in month_cost)
              printf "month\t%s\t%.4f\t%d\n", m, month_cost[k], month_sessions[k]
          }
        }
        for (i = 1; i <= n_yr; i++) {
          yk = yr_keys[i]
          for (m in all_models) {
            k = m SUBSEP yk
            if (k in year_cost)
              printf "year\t%s\t%.4f\n", m, year_cost[k]
          }
        }
        for (m in all_models) {
          if (m in alltime_cost && alltime_sessions[m] > 0)
            printf "alltime\t%s\t%.4f\t%d\n", m, alltime_cost[m], alltime_sessions[m]
        }
        exit
      }

      # --- Pretty output ---
      line = "  \342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200"

      # Fixed display order for all per-model loops below
      split("Opus Sonnet Haiku", _mo, " ")

      # Legend: show which model families appear in the data, with abbreviation and version
      legend = ""
      for (mi = 1; mi <= 3; mi++) {
        m = _mo[mi]
        if (m in all_models) {
          disp = (m in model_display) ? model_display[m] : m
          if (legend != "") legend = legend "  \302\267  "
          legend = legend "(" substr(m, 1, 1) ") " disp
        }
      }
      for (m in all_models) {
        if (m != "Opus" && m != "Sonnet" && m != "Haiku") {
          disp = (m in model_display) ? model_display[m] : m
          if (legend != "") legend = legend "  \302\267  "
          legend = legend "(" substr(m, 1, 1) ") " disp
        }
      }

      printf "\n"
      if (legend != "") { printf "  %s%s%s\n\n", dim, legend, reset }
      printf "  %sToday%s\n", pink, reset
      total = 0; has = 0
      for (m in all_models) {
        if (!(m in today_cost) || today_sessions[m] == 0) continue
        printf "    %-10s %s$%.2f%s\n", m, cyan, today_cost[m], reset
        total += today_cost[m]; has = 1
      }
      if (has) {
        printf "%s\n", line
        printf "    %s%-10s%s %s$%.2f%s\n", pink, "Total", reset, cyan, total, reset
        printf "\n"
      } else { printf "    (none)\n" }

      printf "\n"
      printf "  %sWeek%s  %s(%s \342\200\223 %s)%s\n", pink, reset, dim, week_start, today, reset
      total = 0; has = 0
      for (m in all_models) {
        if (!(m in week_cost) || week_sessions[m] == 0) continue
        printf "    %-10s %s$%.2f%s\n", m, cyan, week_cost[m], reset
        total += week_cost[m]; has = 1
      }
      if (has) {
        printf "%s\n", line
        printf "    %s%-10s%s %s$%.2f%s\n", pink, "Total", reset, cyan, total, reset
        printf "\n"
      } else { printf "    (none)\n" }

      printf "\n"
      printf "  %sMonths%s\n", pink, reset
      for (i = 1; i <= n_mon; i++) {
        mk = mon_keys[i]
        total = 0; n_mod = 0
        for (mi2 = 1; mi2 <= 3; mi2++) {
          m = _mo[mi2]; k = m SUBSEP mk
          if (k in month_cost) { total += month_cost[k]; n_mod++ }
        }
        for (m in all_models) {
          if (m != "Opus" && m != "Sonnet" && m != "Haiku") {
            k = m SUBSEP mk
            if (k in month_cost) { total += month_cost[k]; n_mod++ }
          }
        }
        if (total == 0) continue
        printf "    %s\n", mk
        for (mi2 = 1; mi2 <= 3; mi2++) {
          m = _mo[mi2]; k = m SUBSEP mk
          if (k in month_cost) {
            printf "      %-8s %s$%.2f%s\n", m, cyan, month_cost[k], reset
          }
        }
        for (m in all_models) {
          if (m != "Opus" && m != "Sonnet" && m != "Haiku") {
            k = m SUBSEP mk
            if (k in month_cost) {
              printf "      %-8s %s$%.2f%s\n", m, cyan, month_cost[k], reset
            }
          }
        }
        if (n_mod > 1) {
          printf "%s\n", line
          printf "      %s%-8s%s %s$%.2f%s\n", pink, "Total", reset, cyan, total, reset
          printf "\n"
        }
      }
      if (n_mon == 0) printf "    (none)\n"

      printf "\n"
      printf "  %sYears%s\n", pink, reset
      for (i = 1; i <= n_yr; i++) {
        yk = yr_keys[i]
        total = 0; n_mod = 0
        for (mi2 = 1; mi2 <= 3; mi2++) {
          m = _mo[mi2]; k = m SUBSEP yk
          if (k in year_cost) { total += year_cost[k]; n_mod++ }
        }
        for (m in all_models) {
          if (m != "Opus" && m != "Sonnet" && m != "Haiku") {
            k = m SUBSEP yk
            if (k in year_cost) { total += year_cost[k]; n_mod++ }
          }
        }
        if (total == 0) continue
        printf "    %s\n", yk
        for (mi2 = 1; mi2 <= 3; mi2++) {
          m = _mo[mi2]; k = m SUBSEP yk
          if (k in year_cost) {
            printf "      %-8s %s$%.2f%s\n", m, cyan, year_cost[k], reset
          }
        }
        for (m in all_models) {
          if (m != "Opus" && m != "Sonnet" && m != "Haiku") {
            k = m SUBSEP yk
            if (k in year_cost) {
              printf "      %-8s %s$%.2f%s\n", m, cyan, year_cost[k], reset
            }
          }
        }
        if (n_mod > 1) {
          printf "%s\n", line
          printf "      %s%-8s%s %s$%.2f%s\n", pink, "Total", reset, cyan, total, reset
          printf "\n"
        }
      }
      if (n_yr == 0) printf "    (none)\n"

      printf "\n"
    }
    '
}

_cmd_cost() {
  _cfg_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"

  # Prefer history (Flight Recorder) for correct daily-delta cost attribution.
  # Monthly rotation: read history-*.tsv + legacy history.tsv
  # Falls back to session-cache files when no history exists yet.
  _collect_history_files "$cache_dir"
  if [[ ${#_HIST_FILES[@]} -gt 0 ]]; then
    today_str=$(date '+%Y-%m-%d')  # local time — must match epoch_to_date() with tz_offset
    _spinner_start "${cache_dir/#$HOME/\~}/history-*.tsv"
    _cmd_cost_from_history "${_HIST_FILES[@]}" "$today_str"
    _spinner_stop
    return
  fi


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

  # Show spinner on stderr only for pretty output (not JSON/TSV — those are piped)
  _spinner_start

  for f in "${session_files[@]}"; do
    [[ -f "$f" ]] || continue
    [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" ]] && printf '%s' "${f/#$HOME/\~}" > "$CLAUDII_SPINNER_LABEL_FILE"

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
    _alltime_cost[$idx]=$(awk -v a="${_alltime_cost[$idx]}" -v b="$cost" 'BEGIN{printf "%.4f", a+b}')
    _alltime_count[$idx]=$(( ${_alltime_count[$idx]} + 1 ))

    # Accumulate today (mtime within last 24h)
    if (( mtime >= cutoff )); then
      _today_cost[$idx]=$(awk -v a="${_today_cost[$idx]}" -v b="$cost" 'BEGIN{printf "%.4f", a+b}')
      _today_count[$idx]=$(( ${_today_count[$idx]} + 1 ))
    fi
  done

  # Kill spinner and clear spinner line
  _spinner_stop

  if [[ "$_FORMAT" == "json" ]]; then
    # Build JSON inline — avoids one jq subprocess per model
    _today_inner="" _alltime_inner=""
    for (( _i=0; _i<${#_cost_models[@]}; _i++ )); do
      m="${_cost_models[$_i]}"
      [[ -n "$_alltime_inner" ]] && _alltime_inner+=","
      _alltime_inner+="\"$m\":{\"cost\":${_alltime_cost[$_i]},\"sessions\":${_alltime_count[$_i]}}"
      if [[ "${_today_count[$_i]}" != "0" ]]; then
        [[ -n "$_today_inner" ]] && _today_inner+=","
        _today_inner+="\"$m\":{\"cost\":${_today_cost[$_i]},\"sessions\":${_today_count[$_i]}}"
      fi
    done
    printf '{"today":{%s},"alltime":{%s}}\n' "$_today_inner" "$_alltime_inner"
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

  _cost_sep='  ─────────────────────'

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
      printf "    %-12s ${CLAUDII_CLR_CYAN}\$%s${CLAUDII_CLR_RESET}  %s session%s\n" \
        "$_pm" "$(printf '%.2f' "$_pc")" "$_pn" "$( (( _pn != 1 )) && echo 's' || true)"
      total=$(awk -v a="$total" -v b="$_pc" 'BEGIN{print a+b}')
      has_data=1
    done
    if (( has_data )); then
      printf "${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_cost_sep"
      printf "    ${CLAUDII_CLR_CYAN}\$%s${CLAUDII_CLR_RESET}\n" "$(printf '%.2f' "$total")"
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

      # Status badge: pinned (protected) vs stale (GC candidate) vs idle
      local _is_badge _is_tag=""
      if [[ "$_PSC_pinned" == "1" ]]; then
        _is_badge="${CLAUDII_CLR_CYAN}${CLAUDII_SYM_PIN}${CLAUDII_CLR_RESET}"
        _is_tag=" ${CLAUDII_CLR_CYAN}pinned${CLAUDII_CLR_RESET}"
      elif (( _PSC_age >= 3600 )); then
        _is_badge="${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE}${CLAUDII_CLR_RESET}"
        _is_tag=" ${CLAUDII_CLR_DIM}stale${CLAUDII_CLR_RESET}"
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
        _is_detail+="  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}5h${CLAUDII_CLR_RESET} ${_PSC_rate_5h%.*}%"
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

  # GC footer: count stale and pinned files
  _is_now=$(date +%s)
  _is_stale=0 _is_pinned=0
  for _is_gc_f in "${_is_files[@]}"; do
    [[ -f "$_is_gc_f" ]] || continue
    _is_gc_ppid=$(grep '^ppid=' "$_is_gc_f" 2>/dev/null | cut -d= -f2 || true)
    [[ -n "$_is_gc_ppid" ]] && kill -0 "$_is_gc_ppid" 2>/dev/null && continue
    _is_gc_mtime=$(stat -f%m "$_is_gc_f" 2>/dev/null || stat -c%Y "$_is_gc_f" 2>/dev/null || echo 0)
    if grep -q '^pinned=1$' "$_is_gc_f" 2>/dev/null; then
      (( ++_is_pinned ))
    elif (( _is_now - _is_gc_mtime >= 3600 )); then
      (( ++_is_stale ))
    fi
  done
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
# NOTE: bin/claudii-sessionline does NOT preserve pinned=1 when rewriting the cache file.
#       This is a known limitation. Future fix: sessionline should merge existing cache
#       keys (like pinned=1) before rewriting to maintain pin state across updates.
_cmd_pin() {
  local needle="${2:-}"
  [[ -z "$needle" ]] && { echo "Usage: claudii pin <session-id>" >&2; exit 1; }
  local cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local found=0
  for f in "$cache_dir"/session-*; do
    [[ -f "$f" ]] || continue
    local sid
    sid=$(grep '^session_id=' "$f" 2>/dev/null | cut -d= -f2)
    if [[ "$sid" == *"$needle"* ]] || [[ "${f##*/session-}" == *"$needle"* ]]; then
      if grep -q '^pinned=1$' "$f" 2>/dev/null; then
        echo "Already pinned: $sid"
      else
        # Atomic pin write: tmp+mv prevents race between pin and sessionline rewrites
        local _tmp="${f}.pin.$$"
        { grep -v '^pinned=' "$f" 2>/dev/null; echo "pinned=1"; } > "$_tmp" && mv -f "$_tmp" "$f"
        echo "Pinned: $sid"
      fi
      found=1; break
    fi
  done
  (( found )) || { echo "No session matching '$needle' — run 'claudii se' to list active sessions" >&2; exit 1; }
}

_cmd_unpin() {
  local needle="${2:-}"
  [[ -z "$needle" ]] && { echo "Usage: claudii unpin <session-id>" >&2; exit 1; }
  local cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local found=0
  for f in "$cache_dir"/session-*; do
    [[ -f "$f" ]] || continue
    local sid
    sid=$(grep '^session_id=' "$f" 2>/dev/null | cut -d= -f2)
    if [[ "$sid" == *"$needle"* ]] || [[ "${f##*/session-}" == *"$needle"* ]]; then
      if grep -q '^pinned=1$' "$f" 2>/dev/null; then
        # Atomic unpin write: tmp+mv prevents race with sessionline rewrites
        local _tmp="${f}.unpin.$$"
        grep -v '^pinned=' "$f" 2>/dev/null > "$_tmp" && mv -f "$_tmp" "$f"
        echo "Unpinned: $sid"
      else
        echo "Not pinned: $sid"
      fi
      found=1; break
    fi
  done
  (( found )) || { echo "No session matching '$needle' — run 'claudii se' to list active sessions" >&2; exit 1; }
}

_strip_model_name() {
  local _m="$1"
  _m="${_m% (*context)}"
  _m="${_m% (*Context)}"
  printf '%s' "$_m"
}

_cmd_sessions() {
  _cfg_init
  cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  now=$(date +%s)
  active=0 stale=0
  latest_5h="" latest_7d="" latest_reset=""

  # Collect all session data into parallel arrays
  declare -a _sf_model _sf_ctx _sf_cost _sf_rate5h _sf_rate7d _sf_reset5h \
             _sf_ppid _sf_worktree _sf_agent _sf_cache _sf_sid \
             _sf_is_active _sf_age _sf_projpath _sf_sesname \
             _sf_fingerprint _sf_last_msg
  _sf_count=0

  # Show spinner on stderr only for pretty output (not JSON/TSV — those are piped)
  _spinner_start

  # Build session→JSONL map once (O(1) lookup per session instead of O(dirs) scan)
  _session_build_map

  shopt -s nullglob
  for sf in "$cache_dir"/session-*; do
    [[ -f "$sf" ]] || continue
    [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" ]] && printf '%s' "${sf/#$HOME/\~}" > "$CLAUDII_SPINNER_LABEL_FILE"
    _parse_session_cache "$sf"

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
    if [[ "$_FORMAT" != "tsv" ]]; then
      _sf_projpath[$_sf_count]=$(_session_project_path "$_PSC_session_id")
      # Single awk pass for name + fingerprint + last_message (was 3 separate greps)
      local _resolved
      _resolved=$(_session_resolve "$_PSC_session_id")
      _sf_sesname[$_sf_count]=$(echo "$_resolved" | head -1)
      _sf_fingerprint[$_sf_count]=$(echo "$_resolved" | sed -n '2p')
      _sf_last_msg[$_sf_count]=$(echo "$_resolved" | sed -n '3p')
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
  shopt -u nullglob

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
      _lsof_pid_list="$(IFS=,; echo "${_lsof_ppids[*]}")"
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
        --arg fingerprint "${_sf_fingerprint[$_i]}" \
        --arg last_user_message "${_sf_last_msg[$_i]}" \
        '{model:$model, ctx_pct:($ctx_pct|if .=="" then null else tonumber? end),
          cost:($cost|tonumber? // 0), rate_5h:($rate_5h|if .=="" then null else tonumber? end),
          rate_7d:($rate_7d|if .=="" then null else tonumber? end),
          reset_5h:($reset_5h|if .=="" then null else tonumber? end),
          session_id:$session_id, worktree:$worktree, agent:$agent,
          age_seconds:($age|tonumber), status:$status,
          fingerprint:$fingerprint, last_user_message:$last_user_message}')
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

    # Line 1: status + model + project path + metadata
    line="  ${status_icon} ${CLAUDII_CLR_ACCENT}${_display_model}${CLAUDII_CLR_RESET}"
    if [[ -n "${_sf_projpath[$_i]}" ]]; then
      line+="  ${CLAUDII_CLR_DIM}${_sf_projpath[$_i]}${CLAUDII_CLR_RESET}"
    fi
    [[ -n "${_sf_sesname[$_i]}" ]]  && line+="  ${CLAUDII_CLR_DIM}\"${_sf_sesname[$_i]}\"${CLAUDII_CLR_RESET}"
    [[ -n "${_sf_worktree[$_i]}" ]] && line+=" ${CLAUDII_CLR_DIM}[wt:${_sf_worktree[$_i]}]${CLAUDII_CLR_RESET}"
    [[ -n "${_sf_agent[$_i]}" ]]    && line+=" ${CLAUDII_CLR_DIM}[agent:${_sf_agent[$_i]}]${CLAUDII_CLR_RESET}"
    printf '%s\n' "$line"

    # Line 2: context bar + rate limits + age
    detail="    "
    if [[ -n "${_sf_ctx[$_i]}" && "${_sf_ctx[$_i]}" =~ ^[0-9] ]]; then
      _ctx_display="${_sf_ctx[$_i]%.*}"
      (( _ctx_display > 100 )) && _ctx_display=100
      _render_ctx_bar "$_ctx_display"
      detail+="${_CTX_BAR} ${_ctx_display}%"
    fi
    if [[ -n "${_sf_rate5h[$_i]}" ]]; then
      detail+="  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}5h${CLAUDII_CLR_RESET} ${_sf_rate5h[$_i]%.*}%"
      if [[ -n "${_sf_reset5h[$_i]}" && "${_sf_reset5h[$_i]}" =~ ^[0-9]+$ ]]; then
        _rem=$(( ${_sf_reset5h[$_i]} - now ))
        (( _rem > 0 )) && detail+=" ${CLAUDII_CLR_DIM}↺$(( _rem / 60 ))m${CLAUDII_CLR_RESET}"
      fi
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
    printf "  ${CLAUDII_CLR_DIM}5h:%s%% 7d:%s%%%s${CLAUDII_CLR_RESET}" "${latest_5h%.*}" "${latest_7d%.*}" "$reset_str"
  fi
  printf '\n'
  printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_ACTIVE} active  ${CLAUDII_SYM_INACTIVE} ended  ${CLAUDII_SYM_FINGERPRINT} file(N) = most-touched files  ·  claude -r = resume session${CLAUDII_CLR_RESET}\n"
  printf '\n'
}

_cmd_gc() {
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local _removed=0 _kept=0 _now
  _now=${EPOCHSECONDS:-$(date +%s)}

  shopt -s nullglob
  local _gc_files=("$_cache_base"/session-*)
  shopt -u nullglob

  for _sf in "${_gc_files[@]}"; do
    [[ -f "$_sf" ]] || continue

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
    _sf_mt=$(stat -f%m "$_sf" 2>/dev/null || stat -c%Y "$_sf" 2>/dev/null || echo 0)
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
    done
  fi

  # ── Account ───────────────────────────────────────────────────────
  printf '\n'
  if [[ -n "$_ov_acct_5h" ]]; then
    printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}Account${CLAUDII_CLR_RESET}\n"

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
      _ov_acct_line+=" ${CLAUDII_CLR_DIM}${CLAUDII_SYM_SEP}${CLAUDII_CLR_RESET} 7d: ${_ov_7d_clr}${_ov_7d_int}%${CLAUDII_CLR_RESET}"
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
    while IFS=$'\t' read -r _a_alias _a_skill _a_model _a_effort; do
      printf "    %-8s  %-12s  %s/%s\n" "$_a_alias" "$_a_skill" "$_a_model" "$_a_effort"
    done < <(echo "$_ov_agents_json" | jq -r 'to_entries[] | [.key, (.value.skill // ""), (.value.model // ""), (.value.effort // "")] | @tsv')
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
  [[ -f "$_ov_sl_settings" ]] && jq -e '.statusLine.command == "claudii-sessionline"' "$_ov_sl_settings" >/dev/null 2>&1 && _ov_sl_on=1
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
        case "$_om" in
          opus)   _om_cap="Opus"   ;;
          sonnet) _om_cap="Sonnet" ;;
          haiku)  _om_cap="Haiku"  ;;
          *)      _om_cap="$_om"   ;;
        esac
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
  else
    printf "  ${CLAUDII_CLR_DIM}${CLAUDII_SYM_INACTIVE} Sessions                        start Claude to see data here${CLAUDII_CLR_RESET}\n"
  fi

  printf '\n'
  printf "  ${CLAUDII_CLR_DIM}claudii help  for all commands${CLAUDII_CLR_RESET}\n"
  printf '\n'
}
