# window_history.awk — tokens/cost bucketed into consecutive weekly windows.
#
# Boundaries arrive as a comma-separated ascending epoch list (-v bounds), so
# window i spans [B[i], B[i+1]). They are computed by the caller from the
# reset7d values actually observed in history, falling back to a
# 7-day grid only where none were recorded — Anthropic can reset a weekly
# window early, and a hard-coded 7-day grid would invent boundaries that never
# existed.
#
# As in lib/window.awk, every row feeds attr_delta() so the per-session
# baseline is correct, while only in-range rows are summed.
#
# Requires lib/history_cols.awk and lib/attribution.awk (attr_delta) loaded
# first: awk -f history_cols.awk -f attribution.awk -f window_history.awk
# (lib/cmd/week.sh).
#
# Variables (-v): bounds — the comma-separated ascending epoch list above. The
# only binding; everything else comes from the row.
#
# Columns: read by name through lib/history_cols.awk (HC_SCHEMA) — ts, cost,
# sid, in, out.
#
# Emits one TSV line per window: start  end  tokens  cost  sessions

BEGIN {
  # Without HC[] every $HC_* below would degrade to $0 — numbers that are
  # quietly wrong rather than absent. (exit from BEGIN still runs END, hence
  # the flag; END bails before it prints anything.)
  if (!("ts" in HC)) {
    print "window_history.awk: needs -f lib/history_cols.awk loaded first" > "/dev/stderr"
    hc_missing = 1
    exit 2
  }
  nb = split(bounds, B, ",")
}

{ gsub(/\r/, "") }
NF < HC_MINCOL { next }
$HC_TS == "timestamp" || $HC_TS == "" || $HC_SID == "" { next }

{
  ts = $HC_TS + 0
  if (ts == 0) next
  sid = $HC_SID
  cinc = attr_delta(cost_baseline, sid, $HC_COST + 0)
  tinc = attr_delta(tok_baseline, sid, ($HC_IN == "" ? 0 : $HC_IN + 0) + ($HC_OUT == "" ? 0 : $HC_OUT + 0))
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
  if (hc_missing) exit 2
  # Cost as integer cents — the renderer must not format a float (see the note
  # in lib/window.awk about the unreliable VAR=C prefix on bash printf).
  for (i = 1; i < nb; i++)
    printf "%s\t%s\t%d\t%d\t%d\n", \
      B[i], B[i + 1], tok[i], int(cost[i] * 100 + 0.5), sessions[i]
}
