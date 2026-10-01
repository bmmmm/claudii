# vibemap-strip.awk — aggregate vibemap.tsv into a (days-ago × hour) strip.
#
# Input:  TSV with fields epoch, weekday, hour, minute, model, sid8, delta_ms.
# Output: TSV with fields days_ago(0=today), hour(0-23), count.
#         Plus one final line: "max\t<n>" — max cell count, for normalization.
#
# Args (via -v):
#   now=<epoch>       — current time, used to compute days_ago. Required.
#   maxdays=<n>       — drop rows older than this. Default 14.
#   tz_offset=<secs>  — signed local UTC offset in seconds (from `date +%z`).
#                       Default 0 (UTC). Buckets rows by LOCAL calendar day.
#
# days_ago is a LOCAL calendar-day difference: floor((epoch+tz_offset)/86400)
# for `now` minus the same for each row. This buckets midnight-to-midnight in
# local time — matching the calendar-date labels the renderer draws — rather
# than a rolling 24h window from `now` (which mis-rowed late-evening entries
# near midnight). tz_offset is fixed at the offset of `now`, so rows on the far
# side of a DST transition can be off by one day for the ~1h around midnight
# twice a year — acceptable for a weekly activity view.

BEGIN {
  FS = "\t"
  if (maxdays == "" || maxdays + 0 == 0) maxdays = 14
  if (now == "" || now + 0 == 0) {
    print "vibemap-strip.awk: needs -v now=<epoch>" > "/dev/stderr"
    exit 2
  }
  tz_offset = tz_offset + 0                    # empty → 0 (UTC)
  now_day = int((now + tz_offset) / 86400)     # local day number of "now"
  max = 0
}

NF >= 4 {
  e = $1 + 0
  h = $3 + 0
  if (h < 0 || h > 23) next
  d = now_day - int((e + tz_offset) / 86400)   # local calendar-day difference
  if (d < 0) d = 0
  if (d > maxdays - 1) next
  count[d, h]++
  if (count[d, h] > max) max = count[d, h]
}

END {
  for (key in count) {
    split(key, parts, SUBSEP)
    printf "%s\t%s\t%d\n", parts[1], parts[2], count[key]
  }
  printf "max\t%d\n", max
}
