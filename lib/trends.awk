# trends.awk — claudii trends aggregation and formatting
# Standalone awk program, called via -f from _cmd_trends()
# Input: tab-separated lines: day\tmodel\tcost\tsid
# Variables (passed via -v): today, this_mon, last_mon, last_sun, thirty,
#   week_days, fmt, cyan, dim, pink, reset

{
  day = $1; model = $2; cost = $3 + 0; sid = $4
  if (sid == "") next

  # Dedup: take max cost per session_id
  key = sid
  if (!(key in max_cost) || cost > max_cost[key]) {
    max_cost[key] = cost
    sid_day[key] = day
    sid_model[key] = model
  }
}
END {
  # Aggregate deduplicated sessions by day
  for (key in max_cost) {
    day = sid_day[key]
    model = sid_model[key]
    cost = max_cost[key]

    day_cost[day] += cost
    day_sessions[day]++
    day_model_sessions[day, model]++

    # 30d model split
    if (day >= thirty) {
      model_sessions_30d[model]++
      total_sessions_30d++
    }
  }

  # Costliest day (30d)
  max_day_cost = 0; max_day = ""
  for (d in day_cost) {
    if (d >= thirty && day_cost[d] > max_day_cost) {
      max_day_cost = day_cost[d]
      max_day = d
    }
  }

  # This week + last week totals
  tw_cost = 0; tw_sessions = 0
  lw_cost = 0; lw_sessions = 0
  for (d in day_cost) {
    if (d >= this_mon) { tw_cost += day_cost[d]; tw_sessions += day_sessions[d] }
    if (d >= last_mon && d <= last_sun) { lw_cost += day_cost[d]; lw_sessions += day_sessions[d] }
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
      printf "{\"date\":\"%s\",\"day\":\"%s\",\"cost\":%.2f,\"sessions\":%d}", \
        d, wd_name[i], (d in day_cost ? day_cost[d] : 0), (d in day_sessions ? day_sessions[d] : 0)
    }
    printf "],"

    printf "\"this_week_total\":%.2f,", tw_cost
    printf "\"last_week\":{\"cost\":%.2f,\"sessions\":%d},", lw_cost, lw_sessions

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
      printf "    %-7s %s$%.2f%s  (%d session%s, %s)\n", \
        label, cyan, day_cost[d], reset, sess, s_suffix, detail
    }
  }

  printf "%s\n", sep
  printf "    %-7s %s$%.2f%s\n", "Total", cyan, tw_cost, reset

  # Last week
  printf "\n  %sLast week%s\n", pink, reset
  if (lw_sessions > 0) {
    s_suffix = (lw_sessions != 1) ? "s" : ""
    printf "    Total  %s$%.2f%s  (%d session%s)\n", cyan, lw_cost, reset, lw_sessions, s_suffix
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
