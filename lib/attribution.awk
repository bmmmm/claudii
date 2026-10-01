# attribution.awk — shared per-session delta attribution for history rows.
# Injected into the aggregation programs of `claudii cost` (lib/cmd/cost.sh),
# `claudii trends` (second -f before lib/trends.awk) and the overview's
# today-cost pass (lib/cmd/overview.sh). Single source of truth for the
# baseline-delta heuristic — it used to live as three drifting copies.
#
# attr_delta(baseline, sid, cur) — incremental spend/tokens for this row.
#   baseline: per-session array (passed by reference, updated in place)
#   sid:      session id (array key)
#   cur:      session-cumulative value (cost USD or token count)
# Returns the increment to attribute to this row:
#   first row of a session  → cur (starting value counts as spend)
#   cur > prev              → cur - prev (normal growth)
#   cur < prev * 0.5        → cur (genuine reset, e.g. context compaction:
#                             post-reset cumulative restarts near zero)
#   otherwise               → 0 (noise or tiny decrease — ignore)
# Relies on rows arriving in chronological order per session (guaranteed by
# real-time history append + lexical glob == chronological in
# _collect_history_files — see lib/helpers.sh).
function attr_delta(baseline, sid, cur,   prev, d) {
  if (sid in baseline) {
    prev = baseline[sid]
    if (cur > prev)            d = cur - prev
    else if (cur < prev * 0.5) d = cur
    else                       d = 0
  } else {
    d = cur
  }
  baseline[sid] = cur
  return d
}
