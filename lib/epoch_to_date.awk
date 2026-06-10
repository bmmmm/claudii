# epoch_to_date.awk — shared epoch-to-YYYY-MM-DD conversion
# Requires: -v tz_offset=N (seconds offset from UTC, e.g. 3600 for CET)
# Usage: embed via shell variable or cat into awk program string
# Works on BSD awk (macOS) + GNU awk — no strftime needed.

function is_leap(y,    l) {
  l = 0
  if (y % 4 == 0) l = 1
  if (y % 100 == 0) l = 0
  if (y % 400 == 0) l = 1
  return l
}
function epoch_to_date(ts,    days, y, leap, m, mdays) {
  days = int((ts + tz_offset) / 86400)
  # Memoize per day-bucket: callers feed (roughly) chronological rows, so
  # consecutive calls hit the same day ~99.9% of the time. Without this the
  # year loop below runs 50+ iterations per call — measured 3.2s vs 0.5s for
  # a 100k-row history pass (claudii cost / trends).
  if (days == _e2d_day && _e2d_str != "") return _e2d_str
  _e2d_day = days
  y = 1970
  for (;;) {
    leap = is_leap(y)
    if (days < 365 + leap) break
    days -= 365 + leap; y++
  }
  leap = is_leap(y)
  split("31 " (28+leap) " 31 30 31 30 31 31 30 31 30 31", mdays, " ")
  for (m = 1; m <= 12; m++) { if (days < mdays[m]) break; days -= mdays[m] }
  _e2d_str = sprintf("%04d-%02d-%02d", y, m, days + 1)
  return _e2d_str
}
