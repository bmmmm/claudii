# window_bounds.awk — the weekly windows actually observed in history.
#
# The reset7d column carries the reset epoch Claude Code announced while each
# row was written. A window change shows up as that value changing, so the boundary
# between two windows is the first timestamp bearing the new value — NOT the
# announced reset of the old one, which is precisely the reset that did not
# happen when Anthropic ends a window early.
#
# Emits one line per distinct announced reset:
#   reset_epoch  first_seen_ts  last_seen_ts
# Unsorted (awk hash order); the caller sorts by first_seen_ts.
#
# Variables (-v): none — everything it needs is in the row. Requires
# lib/history_cols.awk loaded first (lib/cmd/week.sh:
# awk -f history_cols.awk -f window_bounds.awk); it reads ts, sid and reset7d
# by name, and a row too short to carry reset7d predates the column.

BEGIN {
  # Without HC[] every $HC_* below would degrade to $0 — numbers that are
  # quietly wrong rather than absent. (exit from BEGIN still runs END, hence
  # the flag; END bails before it prints anything.)
  if (!("ts" in HC)) {
    print "window_bounds.awk: needs -f lib/history_cols.awk loaded first" > "/dev/stderr"
    hc_missing = 1
    exit 2
  }
}

{ gsub(/\r/, "") }
NF < HC_RESET_7D { next }
$HC_TS == "timestamp" || $HC_RESET_7D == "" || $HC_SID == "" { next }
{
  r = $HC_RESET_7D + 0; ts = $HC_TS + 0
  if (r <= 0 || ts <= 0) next
  # A reset lies ahead of the row that reported it, at most one window away.
  if (r <= ts || r > ts + 691200) next
  if (!(r in fst) || ts < fst[r]) fst[r] = ts
  if (ts > lst[r]) lst[r] = ts
  n[r]++
}
END {
  if (hc_missing) exit 2
  # A window that was genuinely observed shows up on many renders. Stray
  # single sightings are column-shifted rows (a tab inside a field upstream),
  # and treating one as a boundary would fabricate a window.
  for (r in fst) if (n[r] >= 3) printf "%d\t%d\t%d\n", r, fst[r], lst[r]
}
