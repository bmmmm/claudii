# lib/forecast.awk — `claudii cost --forecast` renderer (burn-rate + projection).
#
# Loaded AFTER the function libs (epoch_to_date.awk, attribution.awk, fmt.awk)
# via a chain of -f; this file carries the BEGIN/main/END blocks. Reads the raw
# history TSV (one row per CC-Statusline render):
#   $1=ts(epoch)  $3=cost(cumulative)  $5=rate_5h(%)  $6=session_id
#
# Two blocks:
#   1. 5h budget — live account-wide rate-limit burn. Current used%/reset come
#      from the newest fresh session cache (passed via -v; history has no reset
#      timestamp). Burn rate is the slope of rate_5h over the last `burnwin`
#      seconds, windowed to the current 5h cycle (ts >= reset5h - 5h).
#   2. This month — $ projection from per-session cost deltas (attr_delta),
#      with an honest ± band = daily-spend stddev * sqrt(remaining days).
#
# Required -v: now tz_offset reset5h rate_now have5h today thismon lastmon
#              monname dom ndays burnwin fmt
#              cyan dim pink reset green yellow red
# NOTE: `dim` is the dim-ANSI color; days-in-month is `ndays`, day-of-month `dom`.

# --- small formatters (BSD-awk safe: no strftime, no ^) ----------------------

# Epoch → "HH:MM" in local time (tz_offset seconds), no strftime.
function hhmm(ep,   loc, s) {
  loc = ep + tz_offset
  s = loc % 86400
  if (s < 0) s += 86400
  return sprintf("%02d:%02d", int(s / 3600), int((s % 3600) / 60))
}

# Seconds → "Xh Ym" (hours dropped when 0).
function dur_hm(sec,   h, m) {
  if (sec < 0) sec = 0
  h = int(sec / 3600); m = int((sec % 3600) / 60)
  if (h > 0) return sprintf("%dh %dm", h, m)
  return sprintf("%dm", m)
}

# Honest ETA rounding: <30m to the minute, <2h to 5m, beyond to 15m — the
# burn-rate slope is too noisy to claim minute precision past the first hour.
function rnd_eta(m) {
  if (m < 30)  return int(m + 0.5)
  if (m < 120) return int(m / 5 + 0.5) * 5
  return int(m / 15 + 0.5) * 15
}

# Cyan-filled / dim-empty bar (matches the cost.sh / render.sh bar style).
function cbar(filled, width) {
  if (filled < 0) filled = 0
  if (filled > width) filled = width
  return cyan rep("\342\226\210", filled) dim rep("\342\226\221", width - filled) reset
}

# B-style section header: pink title, dim note right-padded to HDR_W, dim rule.
function shead(title, note,   pad) {
  pad = HDR_W - length(title) - length(note); if (pad < 2) pad = 2
  printf "  %s%s%s%s%s%s%s\n", pink, title, reset, rep(" ", pad), dim, note, reset
  printf "  %s%s%s\n", dim, rep("\342\224\200", HDR_W), reset
}

# Burn slope in %/min between the earliest and latest rate_5h sample whose ts
# falls in [lo, hi]. Returns -1 when there are < 2 samples or they span < 3 min
# (too short to be anything but noise). rate_5h is monotonic within a cycle, so
# a negative raw delta (API jitter) is clamped to 0.
function burn_in(lo, hi,   i, ft, lt, fr, lr, span, n, raw) {
  ft = 0; lt = 0; n = 0
  for (i = 1; i <= ns; i++) {
    if (sx[i] < lo || sx[i] > hi) continue
    n++
    if (ft == 0 || sx[i] < ft) { ft = sx[i]; fr = sy[i] }
    if (sx[i] > lt)            { lt = sx[i]; lr = sy[i] }
  }
  if (n < 2) return -1
  span = (lt - ft) / 60
  if (span < 3) return -1
  raw = lr - fr; if (raw < 0) raw = 0
  return raw / span
}

# Sample stddev of this month's per-day spend over the elapsed days (zero-spend
# days included — they are real). Drives the projection ± band.
function daily_sd(   d, v, mean, ss) {
  if (dom <= 1) return 0
  mean = month_total / dom
  ss = 0
  for (d = 1; d <= dom; d++) { v = (d in daily) ? daily[d] : 0; ss += (v - mean) * (v - mean) }
  return sqrt(ss / (dom - 1))
}

BEGIN {
  LBL_W = 14
  BAR_W = 26
  HDR_W = 60
  ns = 0
}

# --- ingest history rows -----------------------------------------------------
{ gsub(/\r/, "") }                                   # strip CR from synced files
NF < 6 { next }
$1 == "timestamp" || $1 == "" || $6 == "" { next }
{
  ts = $1 + 0; if (ts == 0) next
  sid = $6
  cost = ($3 == "" ? 0 : $3 + 0)
  cinc = attr_delta(cbase, sid, cost)
  if (cinc > 0) {
    day = epoch_to_date(ts); mk = substr(day, 1, 7)
    if (mk == thismon)      { dd = substr(day, 9, 2) + 0; daily[dd] += cinc; month_total += cinc }
    else if (mk == lastmon) last_total += cinc
  }
  # rate_5h samples inside the burn window AND the current 5h cycle.
  if (have5h == 1 && ts >= now - burnwin && ts <= now + 5 && ts >= reset5h - 18000) {
    r = ($5 == "" ? -1 : $5 + 0)
    if (r >= 0) { ns++; sx[ns] = ts; sy[ns] = r }
  }
}

END {
  if (fmt == "json") { render_json(); exit }
  if (fmt == "tsv")  { render_tsv();  exit }
  printf "\n"
  render_5h()
  printf "\n"
  render_month()
  printf "\n"
}

# --- 5h budget block ---------------------------------------------------------
function render_5h(   used, nf, uc, burn, h1, h2, accel, ttl, ttr, eta, bt, agequal) {
  shead("5h budget", "(account-wide)")
  if (have5h != 1) {
    printf "  %-*s  %sno active session \342\200\224 live 5h state unavailable%s\n", \
      LBL_W, "Used now", dim, reset
    return
  }
  used = rate_now + 0
  nf = bar_filled(used, 100, BAR_W)
  uc = (used >= 80) ? red : ((used >= 50) ? yellow : green)
  # The cached used% is the last *observed* value; when the session cache is
  # stale (no render tick for a while) label its age — other sessions may have
  # burned the account-wide budget further since it was written.
  agequal = (age > 120) ? sprintf("   %s(%s ago)%s", dim, dur_hm(age), reset) : ""
  printf "  %-*s  %s   %s%d%%%s%s\n", LBL_W, "Used now", cbar(nf, BAR_W), uc, int(used + 0.5), reset, agequal

  # burn_in already excludes samples before the current cycle (ts >= reset5h-5h),
  # so right after a reset there are no in-cycle samples yet → burn=-1 → "idle".
  burn = burn_in(now - burnwin, now + 5)
  if (burn < 0) {
    printf "  %-*s  %s\342\200\224 not enough recent samples (idle)%s\n", LBL_W, "Burn rate", dim, reset
    printf "  %-*s  %s\342\200\224 need a longer sample%s\n", LBL_W, "Projected", dim, reset
  } else {
    h1 = burn_in(now - burnwin, now - burnwin / 2)
    h2 = burn_in(now - burnwin / 2 + 1, now + 5)   # +1: don't share the midpoint sample with h1
    accel = ""
    if (h1 > 0 && h2 >= 0) {
      if      (h2 > h1 * 1.3) accel = sprintf("   %s\342\206\221 accelerating%s", yellow, reset)
      else if (h2 < h1 * 0.7) accel = sprintf("   %s\342\206\223 slowing%s", green, reset)
      else                    accel = sprintf("   %ssteady%s", dim, reset)
    }
    bt = int(burn * 10 + 0.5)                       # integer tenths — locale-immune (no %f)
    printf "  %-*s  %s~%d.%d%%/min%s %sover last %dm%s%s\n", \
      LBL_W, "Burn rate", cyan, int(bt / 10), bt % 10, reset, dim, int(burnwin / 60), reset, accel

    if (burn > 0.0001) {
      ttl = (100 - used) / burn       # minutes until 100%
      ttr = (reset5h - now) / 60      # minutes until reset
      if (ttl < ttr) {
        eta = rnd_eta(ttl)
        printf "  %-*s  %slimit in ~%dm%s %s(\342\211\210 %s)%s   %s\342\232\240%s\n", \
          LBL_W, "Projected", red, eta, reset, dim, hhmm(now + ttl * 60), reset, red, reset
      } else {
        printf "  %-*s  %sresets before limit%s\n", LBL_W, "Projected", green, reset
      }
    } else {
      printf "  %-*s  %ssteady \342\200\224 no limit projected%s\n", LBL_W, "Projected", dim, reset
    }
  }

  printf "  %-*s  %sin %s%s %s(%s)%s\n", \
    LBL_W, "Resets", cyan, dur_hm(reset5h - now), reset, dim, hhmm(reset5h), reset
}

# --- this-month block --------------------------------------------------------
function render_month(   mean, proj, sd, band, ref, bf, trend) {
  shead("This month", sprintf("(%s \302\267 %d of %d days)", monname, dom, ndays))
  if (month_total <= 0) {
    printf "  %-*s  %sno spend recorded this month%s\n", LBL_W, "Spent", dim, reset
    if (last_total > 0)
      printf "  %-*s  %s%s total%s\n", LBL_W, "vs last month", cyan, fmt_usd(last_total), reset
    return
  }
  mean = month_total / dom
  proj = mean * ndays
  sd = daily_sd()
  band = sd * sqrt((ndays - dom > 0) ? (ndays - dom) : 0)

  ref = (last_total > 0) ? last_total : proj          # bar reference: last month's total
  bf = bar_filled(month_total, ref, BAR_W)
  printf "  %-*s  %s%s%s   %s\n", LBL_W, "Spent", cyan, fmt_usd(month_total), reset, cbar(bf, BAR_W)
  printf "  %-*s  %s%s/day%s\n", LBL_W, "Pace", cyan, fmt_usd(mean), reset

  if (dom <= 1) {
    printf "  %-*s  %s~%s%s by %s %d   %searly \342\200\224 wide uncertainty%s\n", \
      LBL_W, "Projected", cyan, fmt_usd(proj), reset, monname, ndays, dim, reset
  } else if (band <= 0) {
    # band == 0 with dom > 1 means the last day of the month: projection equals
    # actual spend, no remaining days to vary — show it without a ± claim.
    printf "  %-*s  %s~%s%s by %s %d\n", \
      LBL_W, "Projected", cyan, fmt_usd(proj), reset, monname, ndays
  } else {
    printf "  %-*s  %s~%s%s by %s %d   %s\302\261%s%s\n", \
      LBL_W, "Projected", cyan, fmt_usd(proj), reset, monname, ndays, dim, fmt_usd(band), reset
  }

  if (last_total > 0) {
    if      (proj > last_total * 1.05) trend = sprintf("%son track to exceed%s", yellow, reset)
    else if (proj < last_total * 0.95) trend = sprintf("%son track to stay under%s", green, reset)
    else                               trend = sprintf("%s\342\211\210 in line%s", dim, reset)
    printf "  %-*s  %s%s total%s   %s\342\206\222%s  %s\n", \
      LBL_W, "vs last month", cyan, fmt_usd(last_total), reset, dim, reset, trend
  } else {
    printf "  %-*s  %sno prior month on record%s\n", LBL_W, "vs last month", dim, reset
  }
}

# --- machine-readable output -------------------------------------------------
function render_json(   burn, ttl, ttr, mean, proj, band) {
  printf "{\"five_hour\":{\"available\":%s", (have5h == 1) ? "true" : "false"
  if (have5h == 1) {
    burn = burn_in(now - burnwin, now + 5)
    printf ",\"used_pct\":%.1f,\"resets_at\":%d,\"resets_in_sec\":%d", \
      rate_now + 0, reset5h, ((reset5h - now > 0) ? reset5h - now : 0)
    if (burn >= 0) {
      printf ",\"burn_pct_per_min\":%.3f", burn
      if (burn > 0.0001) {
        ttl = (100 - (rate_now + 0)) / burn; ttr = (reset5h - now) / 60
        printf ",\"limit_before_reset\":%s", (ttl < ttr) ? "true" : "false"
        if (ttl < ttr) printf ",\"limit_eta_min\":%d", int(ttl + 0.5)
      }
    } else {
      printf ",\"burn_pct_per_min\":null"
    }
  }
  printf "}"
  mean = (dom > 0) ? month_total / dom : 0
  proj = mean * ndays
  band = daily_sd() * sqrt((ndays - dom > 0) ? (ndays - dom) : 0)
  printf ",\"month\":{\"spent\":%.2f,\"pace_per_day\":%.2f,\"projected\":%.2f,\"band\":%.2f,\"last_month\":%.2f,\"days_elapsed\":%d,\"days_in_month\":%d}", \
    month_total, mean, proj, band, last_total, dom, ndays
  printf "}\n"
}

function render_tsv(   burn, mean, proj, band) {
  printf "metric\tvalue\n"
  printf "5h_available\t%d\n", (have5h == 1) ? 1 : 0
  if (have5h == 1) {
    burn = burn_in(now - burnwin, now + 5)
    printf "5h_used_pct\t%.1f\n", rate_now + 0
    printf "5h_resets_in_sec\t%d\n", ((reset5h - now > 0) ? reset5h - now : 0)
    if (burn >= 0) printf "5h_burn_pct_per_min\t%.3f\n", burn
  }
  mean = (dom > 0) ? month_total / dom : 0
  proj = mean * ndays
  band = daily_sd() * sqrt((ndays - dom > 0) ? (ndays - dom) : 0)
  printf "month_spent\t%.2f\n", month_total
  printf "month_pace_per_day\t%.2f\n", mean
  printf "month_projected\t%.2f\n", proj
  printf "month_band\t%.2f\n", band
  printf "month_last_total\t%.2f\n", last_total
}
