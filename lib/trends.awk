# trends.awk — claudii trends aggregation and formatting
# Standalone awk program, called via -f from _cmd_trends()
# Input: tab-separated lines: day\tmodel\tcost\tsid\tin_tok\tout_tok
# Variables (passed via -v): today, this_mon, last_mon, last_sun, thirty,
#   week_days, fmt, cyan, dim, pink, reset

function fmt_tok(t) {
  if (t >= 1000000) return sprintf("%.1fM", t / 1000000)
  if (t >= 1000)    return sprintf("%.0fK", t / 1000)
  if (t > 0)        return t ""
  return ""
}

{
  day = $1; model = $2; cost = $3 + 0; sid = $4
  in_tok = $5 + 0; out_tok = $6 + 0; total_tok = in_tok + out_tok
  if (sid == "") next

  # running_spend: attribute incremental cost delta to this row's day.
  # Handles intra-day resets (context compaction) correctly.
  if (sid in sid_baseline) {
    prev = sid_baseline[sid]
    if (cost > prev) {
      delta = cost - prev
    } else if (cost < prev) {
      delta = cost   # reset: add post-reset starting value
    } else {
      delta = 0
    }
  } else {
    delta = cost     # first row for this session
  }
  sid_baseline[sid] = cost

  if (delta > 0) day_cost[day] += delta

  # Token running_spend — same delta approach as cost
  if (sid in tok_baseline) {
    prev_tok = tok_baseline[sid]
    if (total_tok > prev_tok)      tok_delta = total_tok - prev_tok
    else if (total_tok < prev_tok) tok_delta = total_tok
    else                           tok_delta = 0
  } else {
    tok_delta = total_tok
  }
  tok_baseline[sid] = total_tok
  if (tok_delta > 0) day_tok[day] += tok_delta

  # Count each session once per (day, sid) for session counts and model split
  if (!((sid, day) in session_day_seen)) {
    session_day_seen[sid, day] = 1
    day_sessions[day]++
    day_model_sessions[day, model]++

    # 30d model split: count each session once total
    if (day >= thirty && !((sid, "30d") in session_30d_seen)) {
      session_30d_seen[sid, "30d"] = 1
      model_sessions_30d[model]++
      total_sessions_30d++
    }
  }
}
END {
  # Costliest day (30d)
  max_day_cost = 0; max_day = ""
  for (d in day_cost) {
    if (d >= thirty && day_cost[d] > max_day_cost) {
      max_day_cost = day_cost[d]
      max_day = d
    }
  }

  # This week + last week totals
  tw_cost = 0; tw_sessions = 0; tw_tok = 0
  lw_cost = 0; lw_sessions = 0; lw_tok = 0
  for (d in day_cost) {
    if (d >= this_mon) {
      tw_cost += day_cost[d]; tw_sessions += day_sessions[d]; tw_tok += (d in day_tok ? day_tok[d] : 0)
    }
    if (d >= last_mon && d <= last_sun) {
      lw_cost += day_cost[d]; lw_sessions += day_sessions[d]; lw_tok += (d in day_tok ? day_tok[d] : 0)
    }
  }

  # Parse week_days string into arrays: wd_date[0..n], wd_name[0..n]
  n_days = split(week_days, _wd_parts, ",")
  for (i = 1; i <= n_days; i++) {
    split(_wd_parts[i], _dn, ":")
    wd_date[i] = _dn[1]
    wd_name[i] = _dn[2]
  }

  # --- JSON output ---
  if (fmt == "json") {
    printf "{"

    # this_week array
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

    # model_split_30d
    printf "\"model_split_30d\":{"
    first = 1
    for (m in model_sessions_30d) {
      pct = (total_sessions_30d > 0) ? int(model_sessions_30d[m] * 100 / total_sessions_30d + 0.5) : 0
      if (!first) printf ","
      printf "\"%s\":{\"sessions\":%d,\"percent\":%d}", m, model_sessions_30d[m], pct
      first = 0
    }
    printf "},"

    # costliest_day_30d
    if (max_day != "") {
      printf "\"costliest_day_30d\":{\"date\":\"%s\",\"cost\":%.2f}", max_day, max_day_cost
    } else {
      printf "\"costliest_day_30d\":null"
    }

    printf "}\n"
    exit
  }

  # --- Pretty output ---
  # cyan, dim, pink, reset passed as -v args from bash
  sep   = "  \342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200\342\224\200"

  printf "\n"
  printf "  %sclaudii trends%s\n\n", cyan, reset
  printf "  %sThis week%s (Mon\xe2\x80\x93Sun)\n", pink, reset

  for (i = 1; i <= n_days; i++) {
    d = wd_date[i]
    label = (d == today) ? "Today" : wd_name[i]

    if (!(d in day_cost) || day_cost[d] == 0) {
      printf "    %-7s %s$0.00%s  %s\342\200\224%s\n", label, dim, reset, dim, reset
    } else {
      # Build model detail
      detail = ""
      # Check known models in fixed order
      models_order[1] = "Opus"; models_order[2] = "Sonnet"; models_order[3] = "Haiku"
      for (mi = 1; mi <= 3; mi++) {
        m = models_order[mi]
        if ((d, m) in day_model_sessions) {
          if (detail != "") detail = detail ", "
          detail = detail day_model_sessions[d, m] " " m
        }
      }
      # Unknown models
      for (combo in day_model_sessions) {
        split(combo, cp, SUBSEP)
        if (cp[1] == d && cp[2] != "Opus" && cp[2] != "Sonnet" && cp[2] != "Haiku") {
          if (detail != "") detail = detail ", "
          detail = detail day_model_sessions[combo] " " cp[2]
        }
      }
      sess = day_sessions[d]
      s_suffix = (sess != 1) ? "s" : ""
      _ts = fmt_tok(d in day_tok ? day_tok[d] : 0)
      _tpart = (_ts != "") ? ("  " _ts " tok") : ""
      printf "    %-7s %s$%.2f%s%s  (%d session%s, %s)\n", \
        label, cyan, day_cost[d], reset, _tpart, sess, s_suffix, detail
    }
  }

  printf "%s\n", sep
  _ts = fmt_tok(tw_tok); _tfx = (_ts != "") ? ("  " _ts " tok") : ""
  printf "    %-7s %s$%.2f%s%s\n", "Total", cyan, tw_cost, reset, _tfx

  # Last week
  printf "\n  %sLast week%s\n", pink, reset
  if (lw_sessions > 0) {
    s_suffix = (lw_sessions != 1) ? "s" : ""
    _ts = fmt_tok(lw_tok); _tfx = (_ts != "") ? ("  " _ts " tok") : ""
    printf "    Total  %s$%.2f%s%s  (%d session%s)\n", cyan, lw_cost, reset, _tfx, lw_sessions, s_suffix
  } else {
    printf "    %s(no data)%s\n", dim, reset
  }

  # Model split (30d)
  if (total_sessions_30d > 0) {
    printf "\n"
    split_str = ""
    # Fixed order
    for (mi = 1; mi <= 3; mi++) {
      m = models_order[mi]
      if (m in model_sessions_30d) {
        pct = int(model_sessions_30d[m] * 100 / total_sessions_30d + 0.5)
        if (split_str != "") split_str = split_str " \302\267 "
        split_str = split_str m " " pct "%"
      }
    }
    # Unknown models
    for (m in model_sessions_30d) {
      if (m != "Opus" && m != "Sonnet" && m != "Haiku") {
        pct = int(model_sessions_30d[m] * 100 / total_sessions_30d + 0.5)
        if (split_str != "") split_str = split_str " \302\267 "
        split_str = split_str m " " pct "%"
      }
    }
    printf "  Model split (30d): %s\n", split_str
  }

  # Costliest day
  if (max_day != "") {
    printf "  Costliest day: %s (%s$%.2f%s)\n", max_day, cyan, max_day_cost, reset
  }
  printf "\n"
}
