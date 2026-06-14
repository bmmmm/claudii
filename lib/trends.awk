# trends.awk — claudii trends aggregation and formatting (token-primary)
# Standalone awk program, called via -f from _cmd_trends().
# Requires lib/attribution.awk AND lib/fmt.awk loaded first
# (awk -f attribution.awk -f fmt.awk -f trends.awk): attribution.awk supplies
# attr_delta(), fmt.awk supplies fmt_tok()/fmt_usd()/rep()/bar()/bar_filled().
# Input: tab-separated lines: day\tmodel\tcost\tsid\tin_tok\tout_tok\tapi_dur_ms
# Variables (passed via -v): today, week_start, last_mon, last_sun, thirty,
#   week_days, fmt, cyan, dim, pink, reset

{
  day = $1; model = $2; cost = $3 + 0; sid = $4
  in_tok = $5 + 0; out_tok = $6 + 0; total_tok = in_tok + out_tok
  api_dur = $7 + 0
  if (sid == "") next

  # Incremental cost/token/api deltas for this row — shared baseline-delta
  # heuristic (growth, compaction reset, noise) in lib/attribution.awk.
  delta = attr_delta(sid_baseline, sid, cost)
  if (delta > 0) day_cost[day] += delta

  tok_delta = attr_delta(tok_baseline, sid, total_tok)
  if (tok_delta > 0) {
    day_tok[day] += tok_delta
    # 30d per-model token split. Filter blank/synthetic model names — they
    # used to leak an empty "  0%" slice into the model split (Bug 2).
    if (day >= thirty && model != "" && model != "<synthetic>") {
      model_tok_30d[model] += tok_delta
      total_tok_30d += tok_delta
    }
  }

  # api_dur ($7) is the session-CUMULATIVE total_api_duration_ms (cc-statusline
  # writes .cost.total_api_duration_ms), so it must be delta'd per session like
  # cost/tokens. Summing the raw column folded every render's running total into
  # a ~6651h/day nonsense figure (Bug 1).
  api_delta = attr_delta(api_baseline, sid, api_dur)
  if (api_delta > 0) day_api[day] += api_delta

  # Count each session once per (day, sid) for session counts and model split
  if (!((sid, day) in session_day_seen)) {
    session_day_seen[sid, day] = 1
    day_sessions[day]++
    day_model_sessions[day, model]++

    if (day >= thirty && !((sid, "30d") in session_30d_seen)) {
      session_30d_seen[sid, "30d"] = 1
      model_sessions_30d[model]++
      ++total_sessions_30d
    }
  }
}
END {
  # ── Window aggregates ──
  tw_cost = 0; tw_sessions = 0; tw_tok = 0; tw_api_ms = 0
  lw_cost = 0; lw_sessions = 0; lw_tok = 0
  for (d in day_cost) {
    if (d >= week_start) { tw_cost += day_cost[d]; tw_sessions += day_sessions[d] }
    if (d >= last_mon && d <= last_sun) { lw_cost += day_cost[d]; lw_sessions += day_sessions[d] }
  }
  for (d in day_tok) {
    if (d >= week_start) tw_tok += day_tok[d]
    if (d >= last_mon && d <= last_sun) lw_tok += day_tok[d]
  }
  for (d in day_api) if (d >= week_start) tw_api_ms += day_api[d]

  # Cost-based costliest day (30d) — kept only for the JSON contract.
  max_day_cost = 0; max_day = ""
  for (d in day_cost) if (d >= thirty && day_cost[d] > max_day_cost) { max_day_cost = day_cost[d]; max_day = d }

  # tw_model_sessions (day_model_sessions keyed by day,model) — JSON only.
  for (combo in day_model_sessions) {
    split(combo, cp, SUBSEP)
    if (cp[1] >= week_start) tw_model_sessions[cp[2]] += day_model_sessions[combo]
  }

  # Parse week_days "date:name,..." into wd_date[1..n] / wd_name[1..n]
  n_days = split(week_days, _wd_parts, ",")
  for (i = 1; i <= n_days; i++) {
    split(_wd_parts[i], _dn, ":")
    wd_date[i] = _dn[1]; wd_name[i] = _dn[2]
  }

  # --- JSON output ---  (token-aware; sessions/percent retained for back-compat)
  if (fmt == "json") {
    printf "{"
    printf "\"this_week\":["
    for (i = 1; i <= n_days; i++) {
      d = wd_date[i]
      if (i > 1) printf ","
      printf "{\"date\":\"%s\",\"day\":\"%s\",\"cost\":%.2f,\"tokens\":%d,\"sessions\":%d}", \
        d, wd_name[i], (d in day_cost ? day_cost[d] : 0), (d in day_tok ? day_tok[d] : 0), (d in day_sessions ? day_sessions[d] : 0)
    }
    printf "],"
    printf "\"this_week_total\":%.2f,\"this_week_tokens\":%d,", tw_cost, tw_tok
    printf "\"last_week\":{\"cost\":%.2f,\"tokens\":%d,\"sessions\":%d},", lw_cost, lw_tok, lw_sessions
    printf "\"model_split_30d\":{"
    first = 1
    for (m in model_sessions_30d) {
      pct = (total_sessions_30d > 0) ? int(model_sessions_30d[m] * 100 / total_sessions_30d + 0.5) : 0
      if (!first) printf ","
      printf "\"%s\":{\"sessions\":%d,\"percent\":%d,\"tokens\":%d}", \
        m, model_sessions_30d[m], pct, (m in model_tok_30d ? model_tok_30d[m] : 0)
      first = 0
    }
    printf "},"
    if (max_day != "") printf "\"costliest_day_30d\":{\"date\":\"%s\",\"cost\":%.2f}", max_day, max_day_cost
    else printf "\"costliest_day_30d\":null"
    printf "}\n"
    exit
  }

  # --- Pretty output ---  (token-primary: daily token bars, $ as a dim side column)
  PFX = 14          # label + right-aligned token count share this block
  BAR_W = 24
  SPEND_W = 10      # right-aligned "$2,367.44"
  SESS_W = 8        # right-aligned; header "sessions" fits
  total_w = 2 + PFX + 3 + BAR_W + 3 + SPEND_W + 2 + SESS_W   # 66

  # Busiest day + max daily tokens (bar normalization) over the visible window
  max_tok = 0; max_tok_day = ""
  for (i = 1; i <= n_days; i++) {
    d = wd_date[i]
    dt = (d in day_tok) ? day_tok[d] : 0
    if (dt > max_tok) { max_tok = dt; max_tok_day = d }
  }

  sep = "  " rep("\342\224\200", total_w - 2)

  printf "\n"
  # Title line: "claudii trends" left, "last 7 days" right
  _hdr = "claudii trends"; _win = "last 7 days"
  _gap = total_w - 2 - length(_hdr) - length(_win); if (_gap < 2) _gap = 2
  printf "  %s%s%s%s%s%s%s\n\n", cyan, _hdr, reset, rep(" ", _gap), dim, _win, reset

  # Column header
  _lead = "Daily tokens"
  _rpad = total_w - 2 - length(_lead) - SPEND_W - 2 - SESS_W; if (_rpad < 1) _rpad = 1
  printf "  %s%s%s%s%s%*s  %*s%s\n", \
    pink, _lead, reset, rep(" ", _rpad), dim, SPEND_W, "spend", SESS_W, "sessions", reset
  print sep

  # Daily rows, newest first (Today at top)
  for (i = n_days; i >= 1; i--) {
    d = wd_date[i]
    label = (d == today) ? "Today" : wd_name[i]
    dt = (d in day_tok)      ? day_tok[d]      : 0
    dc = (d in day_cost)     ? day_cost[d]     : 0
    ds = (d in day_sessions) ? day_sessions[d] : 0

    _toks = fmt_tok(dt); if (_toks == "") _toks = "0"
    _pad = PFX - length(label) - length(_toks); if (_pad < 1) _pad = 1
    nf = bar_filled(dt, max_tok, BAR_W)
    _barcol = cyan rep("\342\226\210", nf) dim rep("\342\226\221", BAR_W - nf) reset
    _spend = (dc > 0) ? fmt_usd(dc) : "-"

    printf "  %s%s%s%s%s   %s   %s%*s%s  %*d\n", \
      label, rep(" ", _pad), cyan, _toks, reset, \
      _barcol, \
      dim, SPEND_W, _spend, reset, \
      SESS_W, ds
  }

  print sep
  # 7d total row (no bar)
  _ttoks = fmt_tok(tw_tok); if (_ttoks == "") _ttoks = "0"
  _tpad = PFX - length("7d total") - length(_ttoks); if (_tpad < 1) _tpad = 1
  printf "  %s%s%s%s%s%s%s   %s   %s%*s%s  %*d\n", \
    pink, "7d total", reset, rep(" ", _tpad), cyan, _ttoks, reset, \
    rep(" ", BAR_W), \
    dim, SPEND_W, (tw_cost > 0 ? fmt_usd(tw_cost) : "-"), reset, \
    SESS_W, tw_sessions

  # ── Model split (30d, by tokens) ──
  if (total_tok_30d > 0) {
    printf "\n  %sModel split (30d, by tokens)%s\n", pink, reset
    print sep
    # Sort model keys by tokens desc (selection sort, n is tiny)
    nm = 0
    for (m in model_tok_30d) ms_keys[++nm] = m
    for (a = 1; a <= nm; a++) {
      mx = a
      for (b = a + 1; b <= nm; b++) if (model_tok_30d[ms_keys[b]] > model_tok_30d[ms_keys[mx]]) mx = b
      if (mx != a) { tmp = ms_keys[a]; ms_keys[a] = ms_keys[mx]; ms_keys[mx] = tmp }
    }
    MBAR_W = 38
    for (a = 1; a <= nm; a++) {
      m = ms_keys[a]
      mt = model_tok_30d[m]
      pct = int(mt * 100 / total_tok_30d + 0.5)
      if (pct < 1) continue   # drop sub-1% noise (leaked fixture/local models, Bug 4)
      nf = bar_filled(mt, total_tok_30d, MBAR_W)
      _mbar = cyan rep("\342\226\210", nf) dim rep("\342\226\221", MBAR_W - nf) reset
      printf "  %-9s %s   %s%3d%%%s\n", m, _mbar, cyan, pct, reset
    }
  }

  # ── Footer: busiest day, avg API, trend ──
  printf "\n"
  split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", _mn, " ")
  if (max_tok_day != "") {
    split(max_tok_day, _md, "-")
    printf "  %sBusiest%s   %s %d \302\267 %s%s tok%s\n", \
      pink, reset, _mn[_md[2] + 0], _md[3] + 0, cyan, fmt_tok(max_tok), reset
  }
  # avg API duration per session over the 7d window
  if (tw_sessions > 0 && tw_api_ms > 0) {
    avg_min = int(tw_api_ms / tw_sessions / 60000 + 0.5)
    if (avg_min >= 1) printf "  %savg API%s   %dm/session (7d)\n", pink, reset, avg_min
    else             printf "  %savg API%s   <1m/session (7d)\n", pink, reset
  }

  # Trend: 7d vs 30d daily token average — gated until history spans ~30 days,
  # else the fixed /30 denominator reports a wildly misleading swing on sparse data.
  tok_30d = 0; min_tok_day = ""
  for (d in day_tok) {
    if (d >= thirty) tok_30d += day_tok[d]
    if (day_tok[d] > 0 && (min_tok_day == "" || d < min_tok_day)) min_tok_day = d
  }
  avg_7d = tw_tok / 7
  avg_30d = tok_30d / 30
  have_30d = (min_tok_day != "" && min_tok_day <= thirty)
  if (avg_30d > 0 && have_30d) {
    trend_raw = (avg_7d - avg_30d) / avg_30d * 100
    trend_pct = int(trend_raw + (trend_raw >= 0 ? 0.5 : -0.5))
    arrow = (trend_pct > 0) ? "\342\206\221" : (trend_pct < 0 ? "\342\206\223" : "\342\206\222")
    sign  = (trend_pct > 0) ? "+" : ""
    printf "  %sTrend%s     %s/day (7d)  %s %s%d%%  %svs %s/day (30d)%s\n", \
      pink, reset, fmt_tok(int(avg_7d + 0.5)), arrow, sign, trend_pct, \
      dim, fmt_tok(int(avg_30d + 0.5)), reset
  }

  printf "\n"
}
