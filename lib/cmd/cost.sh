# lib/cmd/cost.sh — claudii cost (history-based cost aggregation)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_cost_from_history() {
  # Last argument is today_str, all preceding args are history file paths
  local today_str="${@: -1}"   # YYYY-MM-DD for "today" cutoff
  local -a _history_files=("${@:1:$#-1}")

  _date_init
  local _date_cmd="$_DATE_CMD" _tz_offset="$_TZ_OFFSET" _ws_dow="$_WS_DOW"

  # Pure-awk date conversion — shared epoch_to_date from lib/epoch_to_date.awk
  local _epoch_awk _attr_awk _tier_awk
  _epoch_awk=$(<"$CLAUDII_HOME/lib/epoch_to_date.awk")
  _attr_awk=$(<"$CLAUDII_HOME/lib/attribution.awk")
  _tier_awk=$(<"$CLAUDII_HOME/lib/model_tier.awk")

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
${_tier_awk}
"'
    { gsub(/\r/, "") }  # strip CR for cross-platform TSV (CRLF from synced files)
    NF < 6 { next }     # guard against short/malformed rows (history schema has >= 6 cols)
    $1 == "timestamp" || $1 == "" || $6 == "" { next }
    {
      ts = $1 + 0; if (ts == 0) next
      day = epoch_to_date(ts)
      model = $2; cost = $3 + 0; sid = $6; raw = $2
      in_tok = ($7 == "" ? 0 : $7 + 0); out_tok = ($8 == "" ? 0 : $8 + 0)
      model = tier_label(model)   # shared tier collapse (lib/model_tier.awk)
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
    "
${_attr_awk}
"'
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
      # Delta heuristic (resets, noise) is the shared attr_delta() from
      # lib/attribution.awk, injected above.
      cinc = attr_delta(sid_baseline, sid, cost)

      # Token increment — same delta approach; tokens are reported as model-agnostic
      # period totals, so they are accumulated per-day, not per-model.
      tinc = attr_delta(tok_baseline, sid, total_tok)

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

  # History (Flight Recorder) is the only data source — it carries correct
  # daily-delta cost attribution. Monthly rotation: history-*.tsv + legacy
  # history.tsv. The old no-history fallback (summing cumulative session-cache
  # cost by file mtime) was removed in 0.21: it only ever applied before the
  # first statusline render wrote history, and its mtime-keyed "today"
  # misattributed multi-day sessions.
  _collect_history_files "$cache_dir"
  if [[ ${#_HIST_FILES[@]} -eq 0 ]]; then
    echo "No cost history yet — run 'claudii cc-statusline on' and start a Claude session to record costs."
    return 0
  fi
  today_str=$(date '+%Y-%m-%d')  # local time — must match epoch_to_date() with tz_offset
  _spinner_start "${cache_dir/#$HOME/~}/history-*.tsv"
  _cmd_cost_from_history "${_HIST_FILES[@]}" "$today_str"
  _spinner_stop
}
