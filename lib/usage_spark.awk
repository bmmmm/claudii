# usage_spark.awk — daily input+output token totals for a rolling N-day window,
# from the cost/trends history TSV. Uses the shared per-session delta
# attribution (attr_delta from attribution.awk, loaded via -f before this file)
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
# History TSV columns: ts=$1 model=$2 cost=$3 ctx=$4 rate=$5 sid=$6 in=$7 out=$8 ...
# Output (stdout):
#   line 1: ndays space-separated integers (in+out tokens per day, oldest first)
#   line 2: max<TAB>today<TAB>total<TAB>active_days<TAB>peak_idx
# DST can shift a bucket by <=1 day for the ~1h around midnight twice a year
# (tz_offset is fixed at now's offset) — acceptable for a 30-day trend view.

BEGIN {
  FS = "\t"
  if (ndays == "" || ndays + 0 == 0) ndays = 30
  tz_offset = tz_offset + 0
  if (today_epoch == "" || today_epoch + 0 == 0) {
    print "usage_spark.awk: needs -v today_epoch=<epoch>" > "/dev/stderr"
    exit 2
  }
  today_day = int((today_epoch + tz_offset) / 86400)
  start_day = today_day - (ndays - 1)
}

{ gsub(/\r/, "") }            # strip CR for cross-platform TSV (CRLF from synced files)
NF < 6 { next }               # guard against short/malformed rows
$1 == "timestamp" || $1 == "" || $6 == "" { next }
{
  ts = $1 + 0; if (ts == 0) next
  sid = $6
  tok = ($7 == "" ? 0 : $7 + 0) + ($8 == "" ? 0 : $8 + 0)
  tinc = attr_delta(base, sid, tok)
  if (tinc <= 0) next
  day = int((ts + tz_offset) / 86400)
  if (day < start_day || day > today_day) next
  daily[day - start_day] += tinc      # idx 0 (oldest) .. ndays-1 (today)
  total += tinc
}

END {
  max = 0; peak = 0; active = 0; series = ""
  for (i = 0; i < ndays; i++) {
    v = (i in daily) ? daily[i] : 0
    if (v > max) { max = v; peak = i }
    if (v > 0) active++
    series = series (i > 0 ? " " : "") v
  }
  today_tok = (ndays - 1) in daily ? daily[ndays - 1] : 0
  printf "%s\n", series
  printf "%d\t%d\t%d\t%d\t%d\n", max, today_tok, total, active, peak
}
