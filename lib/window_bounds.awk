# window_bounds.awk — the weekly windows actually observed in history.
#
# Column 11 carries the reset epoch Claude Code announced while each row was
# written. A window change shows up as that value changing, so the boundary
# between two windows is the first timestamp bearing the new value — NOT the
# announced reset of the old one, which is precisely the reset that did not
# happen when Anthropic ends a window early.
#
# Emits one line per distinct announced reset:
#   reset_epoch  first_seen_ts  last_seen_ts
# Unsorted (awk hash order); the caller sorts by first_seen_ts.
#
# Variables (-v): none. lib/cmd/week.sh runs it as the only -f program, with no
# bindings at all — everything it needs is in the row.
#
# Columns: declared in lib/history_cols.awk (HC_SCHEMA) — ts and reset7d, plus
# the full-width check (`NF < 11`, i.e. HC_NCOL) that keeps pre-feature rows
# out. The indices stay spelled out here because that call site loads no
# history_cols.awk; tests/test_history_cols.sh pins them against the schema.

{ gsub(/\r/, "") }
NF < 11 { next }
$1 == "timestamp" || $11 == "" || $6 == "" { next }
{
  r = $11 + 0; ts = $1 + 0
  if (r <= 0 || ts <= 0) next
  # A reset lies ahead of the row that reported it, at most one window away.
  if (r <= ts || r > ts + 691200) next
  if (!(r in fst) || ts < fst[r]) fst[r] = ts
  if (ts > lst[r]) lst[r] = ts
  n[r]++
}
END {
  # A window that was genuinely observed shows up on many renders. Stray
  # single sightings are column-shifted rows (a tab inside a field upstream),
  # and treating one as a boundary would fabricate a window.
  for (r in fst) if (n[r] >= 3) printf "%d\t%d\t%d\n", r, fst[r], lst[r]
}
