# lib/cmd/cost.sh — claudii cost (history-based cost aggregation)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_cost_from_history() {
  # Last argument is today_str, all preceding args are history file paths
  local today_str="${@: -1}"   # YYYY-MM-DD for "today" cutoff
  local -a _history_files=("${@:1:$#-1}")

  _date_init
  local _date_cmd="$_DATE_CMD" _tz_offset="$_TZ_OFFSET" _ws_dow="$_WS_DOW"

  # Pure-awk date conversion — shared epoch_to_date from lib/epoch_to_date.awk
  local _epoch_awk _attr_awk _tier_awk _fmt_awk
  _epoch_awk=$(<"$CLAUDII_HOME/lib/epoch_to_date.awk")
  _attr_awk=$(<"$CLAUDII_HOME/lib/attribution.awk")
  _tier_awk=$(<"$CLAUDII_HOME/lib/model_tier.awk")
  _fmt_awk=$(<"$CLAUDII_HOME/lib/fmt.awk")   # fmt_tok / rep / bar (shared)

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
${_fmt_awk}
"'
    # Look up one model/period cost cell ("" when the model had no spend there).
    function cell_cost(kind, m, pk,   k) {
      k = m SUBSEP pk
      if (kind == "month") return (k in month_cost) ? month_cost[k] : ""
      return (k in year_cost) ? year_cost[k] : ""
    }
    # B-style per-model bar section (Today / Week): each present tier as
    # $amount + share bar + percent, sorted by amount descending (Bug 3: was
    # hash-order). `costs` is the per-model cost map for the period; `extra` is a
    # dim qualifier after the title (the Week date range) or ""; `period_tok` is
    # the token total for the period (shown in the header — Bug 5). Only canonical
    # tiers (tier_order[]) are shown, so leaked local/test models stay out of
    # the view (Bug 4).
    function render_bars(title, extra, costs, period_tok,
                         LBL_W, AMT_W, BAR_W, SECT_W,
                         i, j, mx, m, v, n, tot, hdr, hdr_vis, _t, lvis, lpad,
                         tmpn, tmpv, nf, pct) {
      LBL_W = 9; AMT_W = 11; BAR_W = 35
      SECT_W = 2 + LBL_W + 1 + AMT_W + 3 + BAR_W + 2 + 6
      n = 0; tot = 0
      for (i = 1; i <= n_tiers; i++) {
        m = tier_order[i]
        if ((m in costs) && costs[m] > 0) { n++; bn[n] = m; bv[n] = costs[m]; tot += costs[m] }
      }
      # Header: title (+ extra) left, "$total · Ntok" right (token suffix only > 0)
      hdr = (tot > 0) ? fmt_usd(tot) : "$0.00"; hdr_vis = length(hdr)
      if (period_tok > 0) { _t = fmt_tok(period_tok); hdr = hdr " \302\267 " _t " tok"; hdr_vis += 3 + length(_t) + 4 }
      lvis = length(title) + (extra != "" ? 2 + length(extra) : 0)
      lpad = SECT_W - 2 - lvis - hdr_vis; if (lpad < 2) lpad = 2
      printf "  %s%s%s", pink, title, reset
      if (extra != "") printf "  %s%s%s", dim, extra, reset
      printf "%s%s%s%s\n", rep(" ", lpad), dim, hdr, reset
      printf "  %s%s%s\n", dim, rep("\342\224\200", SECT_W - 2), reset
      if (n == 0) { printf "  %s(none)%s\n\n", dim, reset; return }
      for (i = 1; i <= n; i++) {                       # selection sort, amount desc
        mx = i
        for (j = i + 1; j <= n; j++) if (bv[j] > bv[mx]) mx = j
        if (mx != i) { tmpn = bn[i]; bn[i] = bn[mx]; bn[mx] = tmpn; tmpv = bv[i]; bv[i] = bv[mx]; bv[mx] = tmpv }
      }
      for (i = 1; i <= n; i++) {
        m = bn[i]; v = bv[i]
        nf = bar_filled(v, tot, BAR_W)
        pct = (tot > 0) ? (v * 100 / tot) : 0
        printf "  %-*s %s%*s%s   %s%s%s%s%s   %s%5.1f%%%s\n", \
          LBL_W, m, cyan, AMT_W, fmt_usd(v), reset, \
          cyan, rep("\342\226\210", nf), dim, rep("\342\226\221", BAR_W - nf), reset, \
          cyan, pct, reset
      }
      printf "\n"
    }

    # D-style matrix (Months / Years): one period per row, canonical tiers as
    # columns separated by │ (no outer frame), with a bottom Total row. Column
    # widths track the widest formatted value so the │ rules line up; empty cells
    # render a right-aligned "-". $-only (cost stays the dollar menu).
    function render_dgrid(pkeys, np, kind, label_hdr,
                          i, j, m, pk, c, v, ncol, any, lblw, totw,
                          rowtot, grandtot, row, rule, val, cellv) {
      if (np == 0) { printf "    (none)\n\n"; return }
      ncol = 0
      for (i = 1; i <= n_tiers; i++) {
        m = tier_order[i]; any = 0
        for (j = 1; j <= np; j++) if (cell_cost(kind, m, pkeys[j]) != "") { any = 1; break }
        if (any) { ncol++; gc[ncol] = m; gw[ncol] = length(m); gt[ncol] = 0 }
      }
      if (ncol == 0) { printf "    (none)\n\n"; return }
      lblw = length(label_hdr); if (length("Total") > lblw) lblw = length("Total")
      for (j = 1; j <= np; j++) if (length(pkeys[j]) > lblw) lblw = length(pkeys[j])
      totw = length("Total"); grandtot = 0
      for (j = 1; j <= np; j++) {
        pk = pkeys[j]; rowtot = 0
        for (i = 1; i <= ncol; i++) {
          c = cell_cost(kind, gc[i], pk)
          if (c != "") { v = fmt_usd(c + 0); if (length(v) > gw[i]) gw[i] = length(v); rowtot += c + 0; gt[i] += c + 0 }
        }
        ptot[j] = rowtot; v = fmt_usd(rowtot); if (length(v) > totw) totw = length(v)
      }
      for (i = 1; i <= ncol; i++) { grandtot += gt[i]; v = fmt_usd(gt[i]); if (length(v) > gw[i]) gw[i] = length(v) }
      v = fmt_usd(grandtot); if (length(v) > totw) totw = length(v)

      # Header row + rule (label column carries a trailing space before the │)
      row = sprintf("  %s%-*s%s ", dim, lblw, label_hdr, reset)
      rule = "  " rep("\342\224\200", lblw + 1)
      for (i = 1; i <= ncol; i++) {
        row = row dim "\342\224\202" reset sprintf(" %s%*s%s ", pink, gw[i], gc[i], reset)
        rule = rule "\342\224\274" rep("\342\224\200", gw[i] + 2)
      }
      row = row dim "\342\224\202" reset sprintf(" %s%*s%s", pink, totw, "Total", reset)
      rule = rule "\342\224\274" rep("\342\224\200", totw + 1)
      print row; print rule

      # Data rows
      for (j = 1; j <= np; j++) {
        pk = pkeys[j]
        row = sprintf("  %s%-*s%s ", dim, lblw, pk, reset)
        for (i = 1; i <= ncol; i++) {
          c = cell_cost(kind, gc[i], pk)
          if (c == "") cellv = rep(" ", gw[i] - 1) "-"          # right-aligned ASCII dash (width-safe)
          else         cellv = sprintf("%s%*s%s", cyan, gw[i], fmt_usd(c + 0), reset)
          row = row dim "\342\224\202" reset " " cellv " "
        }
        row = row dim "\342\224\202" reset sprintf(" %s%*s%s", cyan, totw, fmt_usd(ptot[j]), reset)
        print row
      }

      # Bottom Total row
      print rule
      row = sprintf("  %s%-*s%s ", pink, lblw, "Total", reset)
      for (i = 1; i <= ncol; i++)
        row = row dim "\342\224\202" reset sprintf(" %s%*s%s ", cyan, gw[i], fmt_usd(gt[i]), reset)
      row = row dim "\342\224\202" reset sprintf(" %s%*s%s", cyan, totw, fmt_usd(grandtot), reset)
      print row
      printf "\n"
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
      # Canonical tier order for the legend, bar sections and D-grid columns.
      # Only these tiers are shown (the $-relevant Claude models) so leaked
      # local/test models stay out of the curated view (Bug 4). A new TIER is
      # added here (see "When a new Claude model ships" in CLAUDE.md).
      n_tiers = split("Opus Sonnet Haiku Fable", _to, " ")
      for (i = 1; i <= n_tiers; i++) tier_order[i] = _to[i]

      # Legend: present tiers, friendly (versioned) labels. Track visible width
      # separately — the "·" separators are 2 bytes but 1 column each.
      legend = ""; legend_vis = 0
      for (i = 1; i <= n_tiers; i++) {
        m = tier_order[i]
        if (m in all_models) {
          disp = (m in model_display) ? model_display[m] : m
          if (legend != "") { legend = legend "  \302\267  "; legend_vis += 5 }
          legend = legend disp; legend_vis += length(disp)
        }
      }

      printf "\n"
      _gap = 68 - 2 - length("claudii cost") - legend_vis; if (_gap < 2) _gap = 2
      printf "  %sclaudii cost%s%s%s%s%s\n\n", cyan, reset, rep(" ", _gap), dim, legend, reset

      render_bars("Today", "", today_cost, today_tok)
      render_bars("Week", sprintf("(%s - %s)", week_start, today), week_cost, week_tok)
      printf "  %sMonths%s\n", pink, reset
      render_dgrid(mon_keys, n_mon, "month", "Month")
      printf "  %sYears%s\n", pink, reset
      render_dgrid(yr_keys, n_yr, "year", "Year")
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
