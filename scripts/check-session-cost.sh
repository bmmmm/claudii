#!/bin/bash
# Diagnostic: show cost entries and resets for a session in history.tsv
# Usage: bash scripts/check-session-cost.sh <session_id> [date YYYY-MM-DD]
set -euo pipefail

SID="${1:?Usage: check-session-cost.sh <session_id> [YYYY-MM-DD]}"
DATE="${2:-$(date +%Y-%m-%d)}"
HISTORY="${CLAUDII_CACHE_DIR:-$HOME/.cache/claudii}/history.tsv"

[[ -f "$HISTORY" ]] || { echo "history.tsv not found: $HISTORY"; exit 1; }

awk -F'\t' -v sid="$SID" -v target_date="$DATE" '
  function is_leap(y,    l) {
    l = 0
    if (y % 4   == 0) l = 1
    if (y % 100 == 0) l = 0
    if (y % 400 == 0) l = 1
    return l
  }
  function epoch_to_date(ts,    days, y, leap, m, mdays) {
    days = int(ts / 86400); y = 1970
    for (;;) {
      leap = is_leap(y)
      if (days < 365 + leap) break
      days -= 365 + leap; y++
    }
    leap = is_leap(y)
    split("31 " (28+leap) " 31 30 31 30 31 31 30 31 30 31", mdays, " ")
    for (m = 1; m <= 12; m++) { if (days < mdays[m]) break; days -= mdays[m] }
    return sprintf("%04d-%02d-%02d", y, m, days + 1)
  }
  $6 == sid {
    ts = $1 + 0; if (ts == 0) next
    day = epoch_to_date(ts)
    cost = $3 + 0
    if (day == target_date) {
      if (cost < prev && prev > 0)
        printf "RESET  ts=%-12d  from %.4f → %.4f\n", ts, prev, cost
      else
        printf "entry  ts=%-12d  cost=%.4f\n", ts, cost
      prev = cost
    }
  }
' "$HISTORY"
