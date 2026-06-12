# skills-cost-rows.jq — price one merged insights JSON into per-row TSV.
# Called from _cmd_skills_cost (lib/cmd/skills-cost.sh) with:
#   jq -r -L "$CLAUDII_HOME/lib" --arg k <attr_key> --arg kind <attr_kind>
#      --argjson rates <rate table> -f lib/skills-cost-rows.jq
# Input: merged insights JSON (claudii-insights merge).
# Output rows: name\tcalls\ttot_usd\tavg_usd\tmodel\tin\tout\tcr\tcc
#
# Pricing: every per-model token bucket in attribution_models is priced at its
# own tier; any residual not covered by per-model data (pre-v5 orphans) is
# priced at the flat Sonnet rate. The dominant model per row comes from the
# per-model call counts: the top model needs >=80% of the row's attributed
# calls, otherwise "mixed".
include "tier";

($rates.sonnet) as $sonnet
| (.attribution_models // {} | to_entries
    | map((.key | split("|")) as $p
        | select($p[0] == $kind)
        | {name: ($p[1] // ""), model: ($p[2] // "unknown"),
           calls:        (.value.calls        // 0),
           in_tok:       (.value.in_tok       // 0),
           out_tok:      (.value.out_tok      // 0),
           cache_read:   (.value.cache_read   // 0),
           cache_create: (.value.cache_create // 0)})
  ) as $am
| .[$k] // {}
| to_entries
| map({
    name:         .key,
    calls:        (.value.calls        // 0),
    in_tok:       (.value.in_tok       // 0),
    out_tok:      (.value.out_tok      // 0),
    cache_read:   (.value.cache_read   // 0),
    cache_create: (.value.cache_create // 0)
  })
| map(. as $row
    | ([$am[] | select(.name == $row.name)]) as $cand
    # per-model priced cost (schema-v5 token attribution)
    | ($cand | map(($rates[tier(.model)]) as $r
        | (.in_tok * $r.in + .out_tok * $r.out + .cache_read * $r.cr + .cache_create * $r.cc)
      ) | add // 0) as $model_usd
    # residual = aggregate − per-model-covered tokens (pre-v5 orphans), flat Sonnet
    | (([$row.in_tok       - ($cand | map(.in_tok)       | add // 0), 0] | max)) as $res_in
    | (([$row.out_tok      - ($cand | map(.out_tok)      | add // 0), 0] | max)) as $res_out
    | (([$row.cache_read   - ($cand | map(.cache_read)   | add // 0), 0] | max)) as $res_cr
    | (([$row.cache_create - ($cand | map(.cache_create) | add // 0), 0] | max)) as $res_cc
    | ($res_in * $sonnet.in + $res_out * $sonnet.out + $res_cr * $sonnet.cr + $res_cc * $sonnet.cc) as $res_usd
    | $row + {tot_usd: ($model_usd + $res_usd)}
  )
| map(. + {avg_usd: (if .calls > 0 then .tot_usd / .calls else 0 end)})
| map(. as $row | $row + {model: (
    [$am[] | select(.name == $row.name)] as $cand
    | ($cand | map(.calls) | add // 0) as $tot
    | if $tot <= 0 then "mixed"
      else ($cand | max_by(.calls)) as $top
        | (if ($top.calls / $tot) >= 0.8 then $top.model else "mixed" end)
      end
  )})
| sort_by(-.tot_usd)
| .[]
| [.name, (.calls | tostring), (.tot_usd | tostring), (.avg_usd | tostring), .model,
   (.in_tok | tostring), (.out_tok | tostring), (.cache_read | tostring), (.cache_create | tostring)]
| @tsv
