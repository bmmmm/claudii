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
#   tok  cost  sessions  limit_lo  limit_med  limit_hi  pairs  cents
#
# The three limit fields are a Theil-Sen estimate of the quota size and its
# spread. Support points are (percent, in-window tokens at the moment that
# percent was FIRST reported); the implied limit of a pair is
# dtok / (dpct/100). Taking the median of all pairwise slopes IS Theil-Sen,
# which is why the median — not the mean — is the point estimate: a single
# bad pair cannot drag it. limit_lo/limit_hi are the extreme slopes, so the
# band widens exactly when the data disagree with itself. All three are 0
# when fewer than two support points lie >= 10 percentage points apart; the
# caller then falls back to tokens-over-percent.
#
# Why first occurrence, and why >= 10: the reported percentage is
# 1%-granular, so a row reading "12" means [12, 13). The first row at a
# given percent is the one closest to the moment that threshold was crossed,
# which is the least-biased pairing available. The same granularity makes a
# narrow spread mostly rounding noise — over 2 points, one percent of
# rounding is a 50% error in the slope; over 10 it is 10%.

# Quicksort, median-of-three pivot. The pair count is bounded by ~5050 (at
# most 101 one-percent buckets), and an insertion sort over that is seconds
# of awk; median-of-three additionally keeps the near-sorted input — which
# is the normal case here — off the quadratic path.
function _wq(a, lo, hi,   i, j, p, t, m) {
  if (lo >= hi) return
  m = int((lo + hi) / 2)
  if (a[m]  < a[lo]) { t = a[m];  a[m]  = a[lo]; a[lo] = t }
  if (a[hi] < a[lo]) { t = a[hi]; a[hi] = a[lo]; a[lo] = t }
  if (a[hi] < a[m])  { t = a[hi]; a[hi] = a[m];  a[m]  = t }
  p = a[m]; i = lo; j = hi
  while (i <= j) {
    while (a[i] < p) i++
    while (a[j] > p) j--
    if (i <= j) { t = a[i]; a[i] = a[j]; a[j] = t; i++; j-- }
  }
  _wq(a, lo, j)
  _wq(a, i, hi)
}

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

  # Calibration support point. Column 10 is empty for rows written before this
  # feature shipped, so guard rather than coerce. Bucket to whole percent:
  # the field is 1%-granular in practice but has been seen carrying a decimal
  # ("71.2"), and an unbucketed float would multiply the support points
  # without adding information.
  if ($10 != "") {
    pct = int($10 + 0)
    if (pct > 0 && !(pct in sup_tok)) sup_tok[pct] = win_tok
  }
}

END {
  n = 0
  for (s in seen_sid) n++

  np = 0
  for (p in sup_tok) pts[++np] = p + 0
  _wq(pts, 1, np)

  nl = 0
  for (i = 1; i <= np; i++)
    for (j = i + 1; j <= np; j++) {
      dp = pts[j] - pts[i]
      dt = sup_tok[pts[j]] - sup_tok[pts[i]]
      if (dp >= 10 && dt > 0) lims[++nl] = dt / (dp / 100)
    }

  lo = 0; med = 0; hi = 0
  if (nl > 0) {
    _wq(lims, 1, nl)
    lo = lims[1]; hi = lims[nl]
    med = (nl % 2) ? lims[(nl + 1) / 2] : (lims[nl / 2] + lims[nl / 2 + 1]) / 2
  }

  # Cost twice: the exact float for JSON, and integer cents for display. The
  # shell must not run "%.2f" over the float — a VAR=C prefix on bash's printf
  # builtin does not reliably reload the locale (it kept a comma locale on CI
  # while working locally), so the pretty path stays integer-only.
  printf "%d\t%.6f\t%d\t%d\t%d\t%d\t%d\t%d\n", \
    win_tok, win_cost, n, lo, med, hi, nl, int(win_cost * 100 + 0.5)
}
