# window.awk — usage inside one Anthropic weekly rate-limit window.
#
# Reads raw history rows (the 11-col layout bin/claudii-cc-statusline writes)
# and sums the increments falling inside [window_start, now]. Rows BEFORE the
# window are still processed on purpose: attr_delta() carries a per-session
# baseline, and without the earlier rows the first in-window row of a
# long-running session would be booked as if the whole session had happened
# inside the window. Only the summation is gated — the attribution is not.
# Because every row carries its own epoch, a session straddling the boundary
# splits row-exactly; no proportional splitting logic is needed.
#
# Requires attr_delta() from lib/attribution.awk, prepended by the caller
# (same idiom as lib/cmd/cost.sh and lib/trends.awk).
#
# Variables (-v): window_start — epoch of the window's first second.
#
# Emits one TSV line:
#   tok  cost  sessions  pct_lo  tok_at_lo  pct_hi  tok_at_hi
#
# The four trailing fields are the calibration pair: the earliest and latest
# in-window rows that carried a seven_day percentage, with the in-window token
# count reached at that moment. (tok_at_hi - tok_at_lo) / ((pct_hi - pct_lo)/100)
# estimates the quota size without depending on where the window started —
# which is why it beats the naive tok/pct once the spread is wide enough.
# All four are 0 when no row carried a percentage (history predating the
# feature, or a session that never saw a seven_day field).

{ gsub(/\r/, "") }   # strip CR — history files synced across platforms carry CRLF
NF < 6 { next }
$1 == "timestamp" || $1 == "" || $6 == "" { next }

{
  ts = $1 + 0
  if (ts == 0) next

  sid = $6
  cinc = attr_delta(cost_baseline, sid, $3 + 0)
  tinc = attr_delta(tok_baseline, sid, ($7 == "" ? 0 : $7 + 0) + ($8 == "" ? 0 : $8 + 0))

  if (ts < window_start) next

  win_cost += cinc
  win_tok  += tinc
  if (cinc > 0 || tinc > 0) seen_sid[sid] = 1

  # Calibration: pair the running in-window token total with the percentage
  # Claude Code reported at that moment. Column 10 is empty for rows written
  # before this feature shipped, so guard rather than coerce.
  if ($10 != "") {
    pct = $10 + 0
    if (pct > 0) {
      if (!have_lo) { pct_lo = pct; tok_at_lo = win_tok; have_lo = 1 }
      pct_hi = pct; tok_at_hi = win_tok
    }
  }
}

END {
  n = 0
  for (s in seen_sid) n++
  # Cost twice: the exact float for JSON, and integer cents for display. The
  # shell must not run "%.2f" over the float — a VAR=C prefix on bash's printf
  # builtin does not reliably reload the locale (it kept a comma locale on CI
  # while working locally), so the pretty path stays integer-only.
  printf "%d\t%.6f\t%d\t%.4f\t%d\t%.4f\t%d\t%d\n", \
    win_tok, win_cost, n, pct_lo, tok_at_lo, pct_hi, tok_at_hi, \
    int(win_cost * 100 + 0.5)
}
