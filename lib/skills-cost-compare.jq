# skills-cost-compare.jq — join two priced windows into comparison rows.
# Called from _skills_cost_compare (lib/cmd/skills-cost.sh) with:
#   jq -n -L "$CLAUDII_HOME/lib" --arg k <attr_key> --arg kind <attr_kind>
#      --argjson rates <rate table> --argjson prior <merged> --argjson recent <merged>
#      -f lib/skills-cost-compare.jq
# Output: JSON array of {name, calls_prior, calls_recent, out_per_call_*,
# avg_usd_*, out_per_call_delta}, sorted by combined call volume.
include "tier";

# Per-row {name, calls, out_tok, tot_usd} for one window (same per-model
# pricing + Sonnet residual as the single-window view in skills-cost-rows.jq).
def rows($m):
  ($m.attribution_models // {} | to_entries
    | map((.key | split("|")) as $p | select($p[0] == $kind)
        | {name:($p[1]//""), model:($p[2]//"unknown"),
           in_tok:(.value.in_tok//0), out_tok:(.value.out_tok//0),
           cache_read:(.value.cache_read//0), cache_create:(.value.cache_create//0)})) as $am
  | ($m[$k] // {} | to_entries
      | map({name:.key, calls:(.value.calls//0), in_tok:(.value.in_tok//0),
             out_tok:(.value.out_tok//0), cache_read:(.value.cache_read//0), cache_create:(.value.cache_create//0)}))
  | map(. as $row
      | ([$am[] | select(.name == $row.name)]) as $cand
      | ($cand | map(($rates[tier(.model)]) as $r
          | (.in_tok*$r.in + .out_tok*$r.out + .cache_read*$r.cr + .cache_create*$r.cc)) | add // 0) as $musd
      | (([$row.in_tok       - ($cand|map(.in_tok)|add//0),       0]|max)) as $ri
      | (([$row.out_tok      - ($cand|map(.out_tok)|add//0),      0]|max)) as $ro
      | (([$row.cache_read   - ($cand|map(.cache_read)|add//0),   0]|max)) as $rcr
      | (([$row.cache_create - ($cand|map(.cache_create)|add//0), 0]|max)) as $rcc
      | ($ri*$rates.sonnet.in + $ro*$rates.sonnet.out + $rcr*$rates.sonnet.cr + $rcc*$rates.sonnet.cc) as $rusd
      | {name:$row.name, calls:$row.calls, out_tok:$row.out_tok, tot_usd:($musd+$rusd)});

(rows($prior)) as $P
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
