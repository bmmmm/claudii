# skills-cost-compare.jq — join two priced windows into comparison rows.
# Called from _skills_cost_compare (lib/cmd/skills-cost.sh) with:
#   printf '%s\n%s\n' <prior merged> <recent merged> |
#   jq -n -L "$CLAUDII_HOME/lib" --arg k <attr_key> --arg kind <attr_kind>
#      --argjson rates <rate table> -f lib/skills-cost-compare.jq
# Input: two merged insights JSON documents on stdin — the prior window first,
# the recent one second (read with `input`; never --argjson, which hits the
# 128 KiB per-argument limit on Linux once a window grows).
# Output: JSON array of {name, calls_prior, calls_recent, out_per_call_*,
# avg_usd_*, out_per_call_delta}, sorted by combined call volume.
include "tier";

# Per-row {name, calls, out_tok, tot_usd} for one window, priced by attr_rows()
# in lib/tier.jq — the same pricing as the single-window view.
def rows($m):
  $m | attr_rows($kind; $k; $rates) | map({name, calls, out_tok, tot_usd});

input as $prior
| input as $recent
| (rows($prior)) as $P
| (rows($recent)) as $R
| ([$P[].name, $R[].name] | unique) as $names
| $names | map(
    . as $n
    | (($P | map(select(.name==$n)))[0] // {calls:0,out_tok:0,tot_usd:0}) as $p
    | (($R | map(select(.name==$n)))[0] // {calls:0,out_tok:0,tot_usd:0}) as $r
    | {name:$n,
       calls_prior:$p.calls, calls_recent:$r.calls,
       out_per_call_prior:(if $p.calls>0 then ($p.out_tok/$p.calls) else 0 end),
       out_per_call_recent:(if $r.calls>0 then ($r.out_tok/$r.calls) else 0 end),
       avg_usd_prior:(if $p.calls>0 then ($p.tot_usd/$p.calls) else 0 end),
       avg_usd_recent:(if $r.calls>0 then ($r.tot_usd/$r.calls) else 0 end)}
    | . + {out_per_call_delta:(.out_per_call_recent - .out_per_call_prior)})
| map(select(.calls_prior>0 or .calls_recent>0))
| sort_by(-(.calls_prior + .calls_recent))
