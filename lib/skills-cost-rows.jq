# skills-cost-rows.jq — price one merged insights JSON into per-row TSV.
# Called from _cmd_skills_cost (lib/cmd/skills-cost.sh) with:
#   jq -r -L "$CLAUDII_HOME/lib" --arg k <attr_key> --arg kind <attr_kind>
#      --argjson rates <rate table> -f lib/skills-cost-rows.jq
# Input: merged insights JSON (claudii-insights merge).
# Output rows: name\tcalls\ttot_usd\tavg_usd\tmodel\tin\tout\tcr\tcc
#
# Pricing: attr_rows() in lib/tier.jq — every per-model token bucket in
# attribution_models at its own tier, the residual not covered by per-model
# data (pre-v5 orphans) at the flat legacy-Sonnet rate, and the dominant model
# per row (>=80% of the row's attributed calls, otherwise "mixed").
include "tier";

attr_rows($kind; $k; $rates)
| map(. + {avg_usd: (if .calls > 0 then .tot_usd / .calls else 0 end)})
| sort_by(-.tot_usd)
| .[]
| [.name, (.calls | tostring), (.tot_usd | tostring), (.avg_usd | tostring), .model,
   (.in_tok | tostring), (.out_tok | tostring), (.cache_read | tostring), (.cache_create | tostring)]
| @tsv
