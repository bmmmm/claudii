# usage_spark.awk — daily input+output token totals for a rolling N-day window,
# from the cost/trends history TSV. Uses the shared per-session delta
# attribution (attr_delta from attribution.awk; history_cols.awk and
# attribution.awk are loaded via -f before this file)
# so a long-running session is not counted cumulatively. Emits a fixed-width
# value series (oldest -> newest, zero-filled) plus a summary line, for the
# bare-overview usage sparkline. Day bucketing is by LOCAL calendar day
# (int((ts+tz_offset)/86400)), matching the cost/trends/overview date math.
#
# Args (-v):
#   today_epoch=<epoch>  current time; the window ends on its local calendar day. Required.
#   tz_offset=<secs>     signed local UTC offset (date +%z). Default 0 (UTC).
#   ndays=<n>            window length in days. Default 30.
#
# History TSV columns: read by name through lib/history_cols.awk (HC_SCHEMA)
# — ts, sid, in and out.
# Output (stdout):
#   line 1: ndays space-separated integers (in+out tokens per day, oldest first)
#   line 2: max<TAB>today<TAB>total<TAB>active_days<TAB>peak_idx<TAB>today_sessions
# today_sessions = distinct session ids with positive token activity on the
# current local day — drives the account line's "(N sessions)" count, so the
# overview needs only this one history pass (not a second today-only scan).
# DST can shift a bucket by <=1 day for the ~1h around midnight twice a year
# (tz_offset is fixed at now's offset) — acceptable for a 30-day trend view.

BEGIN {
  FS = "\t"
  # Without HC[] every $HC_* below would degrade to $0 — numbers that are
  # quietly wrong rather than absent. (exit from BEGIN still runs END, hence
  # the flag; END bails before it prints anything.)
  if (!("ts" in HC)) {
    print "usage_spark.awk: needs -f lib/history_cols.awk loaded first" > "/dev/stderr"
    hc_missing = 1
    exit 2
  }
  if (ndays == "" || ndays + 0 == 0) ndays = 30
  tz_offset = tz_offset + 0
  if (today_epoch == "" || today_epoch + 0 == 0) {
    print "usage_spark.awk: needs -v today_epoch=<epoch>" > "/dev/stderr"
    hc_missing = 1   # same bail-out: END must not print a zero series
    exit 2
  }
  today_day = int((today_epoch + tz_offset) / 86400)
  start_day = today_day - (ndays - 1)
}

{ gsub(/\r/, "") }            # strip CR for cross-platform TSV (CRLF from synced files)
NF < HC_MINCOL { next }       # guard against short/malformed rows
$HC_TS == "timestamp" || $HC_TS == "" || $HC_SID == "" { next }
{
  ts = $HC_TS + 0; if (ts == 0) next
  sid = $HC_SID
  tok = ($HC_IN == "" ? 0 : $HC_IN + 0) + ($HC_OUT == "" ? 0 : $HC_OUT + 0)
  tinc = attr_delta(base, sid, tok)
  if (tinc <= 0) next
  day = int((ts + tz_offset) / 86400)
  if (day < start_day || day > today_day) next
  daily[day - start_day] += tinc      # idx 0 (oldest) .. ndays-1 (today)
  if (day == today_day) tsess[sid] = 1   # distinct sessions active today
  total += tinc
}

END {
  if (hc_missing) exit 2
  max = 0; peak = 0; active = 0; series = ""
  for (i = 0; i < ndays; i++) {
    v = (i in daily) ? daily[i] : 0
    if (v > max) { max = v; peak = i }
    if (v > 0) active++
    series = series (i > 0 ? " " : "") v
  }
  today_tok = (ndays - 1) in daily ? daily[ndays - 1] : 0
  today_sessions = 0; for (s in tsess) today_sessions++
  printf "%s\n", series
  printf "%d\t%d\t%d\t%d\t%d\t%d\n", max, today_tok, total, active, peak, today_sessions
}
