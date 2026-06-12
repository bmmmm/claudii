# tier.jq — jq module: map a raw model id to a rate-table tier key.
# Included by lib/skills-cost-rows.jq and lib/skills-cost-compare.jq via
# `include "tier";` (callers pass -L "$CLAUDII_HOME/lib").
# Most-specific first; unknown → sonnet (the historical blended default).
# Word-anchored like lib/model_tier.awk's tier_label() — a glued substring
# ("myopusx") must not classify as a tier. Keep in sync with the _rates table
# in lib/cmd/skills-cost.sh — on a new model TIER (not a version bump), add a
# branch here AND a _rates entry there.
def tier($m):
  ($m // "" | ascii_downcase) as $l
  | if   ($l | test("(^|[^a-z])(fable|mythos)([^a-z]|$)")) then "fable"
    elif ($l | test("(^|[^a-z])opus([^a-z]|$)"))           then "opus"
    elif ($l | test("(^|[^a-z])haiku([^a-z]|$)"))          then "haiku"
    else "sonnet" end;
