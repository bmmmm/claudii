# vibemap-strip.awk — aggregate vibemap.tsv into a (days-ago × hour) strip.
#
# Input:  TSV with fields epoch, weekday, hour, minute, model, sid8, delta_ms.
# Output: TSV with fields days_ago(0=today), hour(0-23), count.
#         Plus one final line: "max\t<n>" — max cell count, for normalization.
#
# Args (via -v):
#   now=<epoch>     — current time, used to compute days_ago. Required.
#   maxdays=<n>     — drop rows older than this. Default 14.
#
# Day boundaries follow local time; we compute days_ago by truncating both
# epochs to local midnight (epoch_local % 86400 → seconds-since-local-midnight,
# subtracted to get the local-midnight of that day) before integer-dividing.

BEGIN {
  FS = "\t"
  if (maxdays == "" || maxdays + 0 == 0) maxdays = 14
  if (now == "" || now + 0 == 0) {
    print "vibemap-strip.awk: needs -v now=<epoch>" > "/dev/stderr"
    exit 2
  }
  # Anchor to local midnight of "today". Caller passes `now`, we keep it.
  max = 0
}

NF >= 4 {
  e  = $1 + 0
  h  = $3 + 0
  if (h < 0 || h > 23) next
  # Calendar-day diff: snap both to local midnight, divide.
  # Without timezone math in pure awk, approximate via 86400 buckets — fine
  # for weekly views, off-by-one for entries crossing DST. Acceptable.
  d = int((now - e) / 86400)
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
