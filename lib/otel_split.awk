# otel_split.awk — split a legacy single-file OTLP export into per-day raw files.
# Called from `claudii-otel migrate` (bin/claudii-otel) together with
# lib/epoch_to_date.awk:
#   LC_ALL=C awk -v tz_offset=0 -v dir=<stage dir> -v sig=<traces|logs|…>
#       -v tag=<legacy-RUN> -v fallback=<YYYY-MM-DD>
#       -f lib/epoch_to_date.awk -f lib/otel_split.awk <file>
# Input: one OTLP/JSON batch per line, in arrival order.
# Output: dir/<sig>-YYYY-MM-DD.<tag>.jsonl, one per UTC day, lines unchanged;
# on stdout the number of records read, which migrate checks against the parts
# (wc -l on the input would miss a final line without a newline).
#
# The day is the first "...UnixNano" timestamp of the line (span start or log
# time, int64 nanoseconds, quoted or not). A line without one (the receiver's
# `_unparsed` marker) stays with the previous line's day — the file is in
# arrival order, so that is the day it arrived. Lines before the first
# timestamp are held back and go to the first day found (`fallback` if the file
# has no timestamp at all), so every line lands in a dated file.
function part(d) { return dir "/" sig "-" d "." tag ".jsonl" }
{
  if (match($0, /UnixNano":"?[0-9]+/)) {
    ns = substr($0, RSTART, RLENGTH)
    gsub(/[^0-9]/, "", ns)
    if (length(ns) > 9) day = epoch_to_date(substr(ns, 1, length(ns) - 9) + 0)
  }
  if (day == "") { held[++nheld] = $0; next }
  if (day != cur) {
    if (cur != "") close(out)
    cur = day
    out = part(day)
  }
  for (i = 1; i <= nheld; i++) print held[i] >> out
  nheld = 0
  # >> not >: after close() a > would truncate the day's file when an
  # out-of-order line reopens it. migrate clears the run's parts before it starts.
  print >> out
}
END {
  if (nheld) {
    out = part(day != "" ? day : fallback)
    for (i = 1; i <= nheld; i++) print held[i] >> out
  }
  print NR
}
