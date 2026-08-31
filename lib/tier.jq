# tier.jq — jq module: map a raw model id to a rate-table tier key.
# Included by lib/skills-cost-rows.jq and lib/skills-cost-compare.jq via
# `include "tier";` (callers pass -L "$CLAUDII_HOME/lib").
# Most-specific first; unknown → sonnet (the historical blended default).
# Word-anchored like lib/model_tier.awk's tier_label() — a glued substring
# ("myopusx") must not classify as a tier. Keep in sync with the _rates table
# in lib/cmd/skills-cost.sh — on a new model TIER add a branch here AND a
# _rates entry there. A version bump CAN be price-relevant too: Sonnet 5
# ($2/$10) broke the tier-price assumption that 4.x ($3/$15) set, so sonnet-4*
# ids map to "sonnet-legacy" while everything else sonnet is the current rate.
def tier($m):
  ($m // "" | ascii_downcase) as $l
  | if   ($l | test("(^|[^a-z])(fable|mythos)([^a-z]|$)")) then "fable"
    elif ($l | test("(^|[^a-z])opus([^a-z]|$)"))           then "opus"
    elif ($l | test("(^|[^a-z])haiku([^a-z]|$)"))          then "haiku"
    elif ($l | test("sonnet[- ]4([^0-9]|$)"))              then "sonnet-legacy"
    else "sonnet" end;
