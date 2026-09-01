# window_history.awk — tokens/cost bucketed into consecutive weekly windows.
#
# Boundaries arrive as a comma-separated ascending epoch list (-v bounds), so
# window i spans [B[i], B[i+1]). They are computed by the caller from the
# reset_7d values actually observed in history (column 11), falling back to a
# 7-day grid only where none were recorded — Anthropic can reset a weekly
# window early, and a hard-coded 7-day grid would invent boundaries that never
# existed.
#
# As in lib/window.awk, every row feeds attr_delta() so the per-session
# baseline is correct, while only in-range rows are summed.
#
# Requires attr_delta() from lib/attribution.awk (prepended by the caller).
# Emits one TSV line per window: start  end  tokens  cost  sessions

BEGIN { nb = split(bounds, B, ",") }

{ gsub(/\r/, "") }
NF < 6 { next }
$1 == "timestamp" || $1 == "" || $6 == "" { next }

{
  ts = $1 + 0
  if (ts == 0) next
  sid = $6
  cinc = attr_delta(cost_baseline, sid, $3 + 0)
  tinc = attr_delta(tok_baseline, sid, ($7 == "" ? 0 : $7 + 0) + ($8 == "" ? 0 : $8 + 0))
  if (cinc <= 0 && tinc <= 0) next

  # Rows arrive chronologically, so resume the scan where the last row landed
  # instead of rescanning from window 1 for every one of ~100k rows.
  if (ts < B[1]) next
  while (cur < nb - 1 && ts >= B[cur + 1]) cur++
  if (cur < 1) cur = 1
  if (ts < B[cur] || ts >= B[cur + 1]) next

  tok[cur] += tinc
  cost[cur] += cinc
  if (!((cur SUBSEP sid) in seen)) { seen[cur SUBSEP sid] = 1; sessions[cur]++ }
}

END {
  # Cost as integer cents — the renderer must not format a float (see the note
  # in lib/window.awk about the unreliable VAR=C prefix on bash printf).
  for (i = 1; i < nb; i++)
    printf "%s\t%s\t%d\t%d\t%d\n", \
      B[i], B[i + 1], tok[i], int(cost[i] * 100 + 0.5), sessions[i]
}
