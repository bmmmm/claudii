# lib/cmd/sessions.sh — session data commands (cost, sessions, sessions-inactive, smart default)
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

  # Terminal width drives how many month/year tiles fit side-by-side (default 80
  # when not a tty / COLUMNS unset). Pretty output only — JSON/TSV ignore it.
  local _cost_cols="${COLUMNS:-}"
  [[ "$_cost_cols" =~ ^[0-9]+$ ]] || _cost_cols=$(tput cols 2>/dev/null || echo 80)
  [[ "$_cost_cols" =~ ^[0-9]+$ ]] || _cost_cols=80

  # Stage 1 augments rows (epoch→day, model normalization), stage 2 computes
  # daily deltas and aggregates into today/week/month/year/alltime. Piped
  # directly — capturing stage 1 into a shell variable copied a multi-MB
  # intermediate through the shell twice; the pipe also runs both concurrently.
  # The empty-input case (no valid rows) is handled in stage 2's END block.
  awk -F'\t' -v tz_offset="${_tz_offset:-0}" "
${_epoch_awk}
"'
    { gsub(/\r/, "") }  # strip CR for cross-platform TSV (CRLF from synced files)
    NF < 6 { next }     # guard against short/malformed rows (history schema has >= 6 cols)
    $1 == "timestamp" || $1 == "" || $6 == "" { next }
    {
      ts = $1 + 0; if (ts == 0) next
      day = epoch_to_date(ts)
      model = $2; cost = $3 + 0; sid = $6; raw = $2
      in_tok = ($7 == "" ? 0 : $7 + 0); out_tok = ($8 == "" ? 0 : $8 + 0)
      if      (tolower(model) ~ /(^|[^a-z])opus([^a-z]|$)/)   model = "Opus"
      else if (tolower(model) ~ /(^|[^a-z])sonnet([^a-z]|$)/) model = "Sonnet"
      else if (tolower(model) ~ /(^|[^a-z])haiku([^a-z]|$)/)  model = "Haiku"
      print day "\t" model "\t" cost "\t" sid "\t" raw "\t" in_tok "\t" out_tok
    }
  ' "${_history_files[@]}" | awk -F'\t' \
    -v today="$today_str" \
    -v week_start="${week_start_str:-$today_str}" \
    -v cols="$_cost_cols" \
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
    function rep(c, n,   s, i) { s = ""; for (i = 0; i < n; i++) s = s c; return s }
    # Look up one model/period cost cell ("" when the model had no spend there).
    function cell_cost(kind, m, pk,   k) {
      k = m SUBSEP pk
      if (kind == "month") return (k in month_cost) ? month_cost[k] : ""
      return (k in year_cost) ? year_cost[k] : ""
    }
    # Render a set of periods (months or years) as fixed-width tiles laid out
    # side-by-side, as many per row as the terminal width allows. Each tile:
    #   <period>
    #     <Model>   $cost
    #     ────────────────
    #     Total     $cost     (only when the period has >1 model)
    # Padding is computed from a tracked visible width (cell_vis), so ANSI color
    # escapes never throw off column alignment or the vertical │ separators.
    function render_grid(pkeys, np, kind,
                         LW, VW, TW, dashw, sepvis, sepcol, perrow,
                         i, pk, mi2, m, c, valstr, tot,
                         start, end, ncols, ci, rr, nmod, dstr, tval,
                         maxrows, r, line_out, cell, vis, pad) {
      if (np == 0) { printf "    (none)\n\n"; return }
      LW = 5; VW = 5                            # min widths: "Total", "$0.00"
      for (i = 1; i <= np; i++) {
        pk = pkeys[i]; tot = 0
        for (mi2 = 1; mi2 <= n_ordered; mi2++) {
          m = ordered_models[mi2]; c = cell_cost(kind, m, pk)
          if (c == "") continue
          if (length(m) > LW) LW = length(m)
          valstr = sprintf("$%.2f", c + 0); if (length(valstr) > VW) VW = length(valstr)
          tot += c
        }
        valstr = sprintf("$%.2f", tot); if (length(valstr) > VW) VW = length(valstr)
      }
      TW = 2 + LW + 1 + VW; dashw = LW + 1 + VW
      sepvis = 5; sepcol = sprintf("%s  \342\224\202  %s", dim, reset)
      perrow = int((cols - 2 + sepvis) / (TW + sepvis))
      if (perrow < 1) perrow = 1
      if (perrow > 6) perrow = 6                # cap — avoid a wall of tiles on ultra-wide terminals
      for (start = 1; start <= np; start += perrow) {
        end = start + perrow - 1; if (end > np) end = np
        ncols = end - start + 1; maxrows = 0
        for (ci = 1; ci <= ncols; ci++) {
          pk = pkeys[start + ci - 1]; rr = 0; tot = 0; nmod = 0
          rr++; cell_str[ci, rr] = pk; cell_vis[ci, rr] = length(pk)
          for (mi2 = 1; mi2 <= n_ordered; mi2++) {
            m = ordered_models[mi2]; c = cell_cost(kind, m, pk)
            if (c == "") continue
            valstr = sprintf("%*s", VW, sprintf("$%.2f", c + 0))
            rr++; cell_str[ci, rr] = sprintf("  %-*s %s%s%s", LW, m, cyan, valstr, reset)
            cell_vis[ci, rr] = 2 + LW + 1 + VW
            tot += c; nmod++
          }
          if (nmod > 1) {
            dstr = rep("\342\224\200", dashw)
            rr++; cell_str[ci, rr] = sprintf("  %s%s%s", dim, dstr, reset); cell_vis[ci, rr] = 2 + dashw
            tval = sprintf("%*s", VW, sprintf("$%.2f", tot))
            rr++; cell_str[ci, rr] = sprintf("  %s%-*s%s %s%s%s", pink, LW, "Total", reset, cyan, tval, reset)
            cell_vis[ci, rr] = 2 + LW + 1 + VW
          }
          col_nrows[ci] = rr; if (rr > maxrows) maxrows = rr
        }
        for (r = 1; r <= maxrows; r++) {
          line_out = "  "
          for (ci = 1; ci <= ncols; ci++) {
            if (r <= col_nrows[ci]) { cell = cell_str[ci, r]; vis = cell_vis[ci, r] }
            else { cell = ""; vis = 0 }
            pad = TW - vis; if (pad < 0) pad = 0
            line_out = line_out cell rep(" ", pad)
            if (ci < ncols) line_out = line_out sepcol
          }
          print line_out
        }
        printf "\n"
      }
    }
    {
      day = $1; model = $2; cost = $3 + 0; sid = $4; raw = $5
      in_tok = $6 + 0; out_tok = $7 + 0; total_tok = in_tok + out_tok
      if (sid == "" || day == "" || model == "") next

      # Track most informative display name (prefer versioned, e.g. "Opus 4.6" > "Opus")
      if (raw != "" && (!(model in model_display) || \
          (index(raw, ".") > 0 && index(model_display[model], ".") == 0)))
        model_display[model] = raw

      # Per-row spend increment, attributed to the model ACTIVE on this row.
      # cost ($3) is the session-cumulative total (model-agnostic), so a per-model
      # cost series cannot be reconstructed — but each *increment* can be attributed
      # to whichever model was running when it was incurred. This fixes the
      # mixed-model-day bug where the whole-day delta was credited to the last
      # model seen (e.g. Opus work + Sonnet cleanup → all counted as Sonnet).
      # Increments on cost increases; a >50% drop counts the post-reset cost as
      # fresh spend (context compaction); minor fluctuations are ignored.
      # NOTE: relies on rows arriving in chronological order per session
      # (guaranteed by real-time history append + lexical glob == chronological).
      cinc = 0
      if (sid in sid_baseline) {
        prev = sid_baseline[sid]
        if (cost > prev)            cinc = cost - prev
        else if (cost < prev * 0.5) cinc = cost   # genuine reset (context compaction)
      } else {
        cinc = cost                                # first row: starting cost as spend
      }
      sid_baseline[sid] = cost

      # Token increment — same delta approach; tokens are reported as model-agnostic
      # period totals, so they are accumulated per-day, not per-model.
      tinc = 0
      if (sid in tok_baseline) {
        ptok = tok_baseline[sid]
        if (total_tok > ptok)            tinc = total_tok - ptok
        else if (total_tok < ptok * 0.5) tinc = total_tok
      } else {
        tinc = total_tok
      }
      tok_baseline[sid] = total_tok

      all_models[model] = 1
      mk = substr(day, 1, 7); yk = substr(day, 1, 4)
      if (cinc > 0) {
        all_months[mk] = 1; all_years[yk] = 1
        alltime_cost[model]         += cinc; seen_sid_alltime[model SUBSEP sid]          = 1
        if (day == today)      { today_cost[model] += cinc; seen_sid_today[model SUBSEP sid] = 1 }
        if (day >= week_start) { week_cost[model]  += cinc; seen_sid_week[model SUBSEP sid]  = 1 }
        month_cost[model SUBSEP mk] += cinc; seen_sid_month[model SUBSEP mk SUBSEP sid] = 1
        year_cost[model SUBSEP yk]  += cinc; seen_sid_year[model SUBSEP yk SUBSEP sid]  = 1
      }
      if (tinc > 0) {
        alltime_tok += tinc
        if (day == today)      today_tok += tinc
        if (day >= week_start) week_tok  += tinc
        month_tok[mk] += tinc
        year_tok[yk]  += tinc
      }
    }
    END {
      # No valid rows reached us (history files empty/malformed) — same message
      # the pre-pipe code printed after its empty-capture check.
      if (NR == 0) {
        printf "  No history data found — start a Claude session to record costs.\n"
        exit
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

      # Ordered model list for the tile renderer: canonical tiers first, extras
      # after (stable iteration order so tile rows align across all periods).
      n_ordered = 0
      for (mi = 1; mi <= 3; mi++) if (_mo[mi] in all_models) ordered_models[++n_ordered] = _mo[mi]
      for (m in all_models)
        if (m != "Opus" && m != "Sonnet" && m != "Haiku" && m != "") ordered_models[++n_ordered] = m

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
      render_grid(mon_keys, n_mon, "month")

      printf "  %sYears%s\n", pink, reset
      render_grid(yr_keys, n_yr, "year")
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
  # Drop atomic-write artifacts (session-*.tmp.PID left behind by crashed writers)
  _sf_real=()
  for _sf_e in "${session_files[@]+"${session_files[@]}"}"; do
    [[ "$_sf_e" == *.tmp.* ]] || _sf_real+=("$_sf_e")
  done
  session_files=("${_sf_real[@]+"${_sf_real[@]}"}")
  unset _sf_real _sf_e

  if [[ ${#session_files[@]} -eq 0 ]]; then
    echo "No session data found. Start a Claude session first."
    exit 0
  fi

  now=$(date +%s)
  # Calendar-midnight cutoff for "today" (not rolling 24h) — see _midnight_epoch.
  cutoff=$(_midnight_epoch)

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

    short=$(_norm_model_short "$model")

    # Get mtime (one fork: BSD stat -f, GNU stat -c fallback; 0 if both fail)
    mtime=$(_mtime "$f")

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

    # Accumulate today (file mtime on or after local calendar midnight — cutoff
    # above). This no-history fallback keys "today" off the session file's mtime,
    # so a multi-day session's full cumulative cost lands in "today" (approximate).
    # The history path (_cmd_cost_from_history) is accurate and is preferred
    # whenever history-*.tsv exists.
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

  for _sf in "${_gc_files[@]}"; do
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
  # contains() — also matches the cc-insomnii wrapper command
  [[ -f "$_ov_sl_settings" ]] && jq -e '.statusLine.command // "" | contains("claudii-cc-statusline")' "$_ov_sl_settings" >/dev/null 2>&1 && _ov_sl_on=1
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
