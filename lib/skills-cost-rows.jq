# skills-cost-rows.jq — price one merged insights JSON into per-row TSV.
# Called from _cmd_skills_cost (lib/cmd/skills-cost.sh) with:
#   jq -r -L "$CLAUDII_HOME/lib" --arg k <attr_key> --arg kind <attr_kind>
#      --argjson rates <rate table> -f lib/skills-cost-rows.jq
# Input: merged insights JSON (claudii-insights merge).
# Output rows: name\tcalls\ttot_usd\tavg_usd\tmodel\tin\tout\tcr\tcc
#
# Pricing: every per-model token bucket in attribution_models is priced at its
# own tier; any residual not covered by per-model data (pre-v5 orphans) is
# priced at the flat legacy-Sonnet rate (that data predates Sonnet 5). Both go
# through usd() from lib/tier.jq, which bills cache writes by TTL (schema v11
# cache_create_1h at the 1h rate, the rest at the 5m rate) and, for a tier with
# a "-long" row (Haiku 5.5), bills the long_* share — requests over 100K prompt
# tokens — at that row (model_usd).
# The dominant model per row comes from the per-model call counts: the top
# model needs >=80% of the row's attributed calls, otherwise "mixed".
include "tier";

($rates["sonnet-legacy"]) as $sonnet
| (.attribution_models // {} | to_entries
    | map((.key | split("|")) as $p
        | select($p[0] == $kind)
        | {name: ($p[1] // ""), model: ($p[2] // "unknown"),
           calls:           (.value.calls           // 0),
           in_tok:          (.value.in_tok          // 0),
           out_tok:         (.value.out_tok         // 0),
           cache_read:      (.value.cache_read      // 0),
           cache_create:    (.value.cache_create    // 0),
           cache_create_1h: (.value.cache_create_1h // 0),
           long_in_tok:          (.value.long_in_tok          // 0),
           long_out_tok:         (.value.long_out_tok         // 0),
           long_cache_read:      (.value.long_cache_read      // 0),
           long_cache_create:    (.value.long_cache_create    // 0),
           long_cache_create_1h: (.value.long_cache_create_1h // 0)})
  ) as $am
| .[$k] // {}
| to_entries
| map({
    name:            .key,
    calls:           (.value.calls           // 0),
    in_tok:          (.value.in_tok          // 0),
    out_tok:         (.value.out_tok         // 0),
    cache_read:      (.value.cache_read      // 0),
    cache_create:    (.value.cache_create    // 0),
    cache_create_1h: (.value.cache_create_1h // 0)
  })
| map(. as $row
    | ([$am[] | select(.name == $row.name)]) as $cand
    # per-model priced cost (schema-v5 token attribution)
    | ($cand | map(model_usd($rates)) | add // 0) as $model_usd
    # residual = aggregate − per-model-covered tokens (pre-v5 orphans), legacy Sonnet
    | (([$row.in_tok          - ($cand | map(.in_tok)          | add // 0), 0] | max)) as $res_in
    | (([$row.out_tok         - ($cand | map(.out_tok)         | add // 0), 0] | max)) as $res_out
    | (([$row.cache_read      - ($cand | map(.cache_read)      | add // 0), 0] | max)) as $res_cr
    | (([$row.cache_create    - ($cand | map(.cache_create)    | add // 0), 0] | max)) as $res_cc
    | (([$row.cache_create_1h - ($cand | map(.cache_create_1h) | add // 0), 0] | max)) as $res_cc1h
    | ({in_tok: $res_in, out_tok: $res_out, cache_read: $res_cr,
        cache_create: $res_cc, cache_create_1h: $res_cc1h} | usd($sonnet)) as $res_usd
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
