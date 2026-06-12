# tier.jq — jq module: map a raw model id to a rate-table tier key.
# Included by lib/skills-cost-rows.jq and lib/skills-cost-compare.jq via
# `include "tier";` (callers pass -L "$CLAUDII_HOME/lib").
# Most-specific first; unknown → sonnet (the historical blended default).
# Keep in sync with the _rates table in lib/cmd/skills-cost.sh — on a new
# model TIER (not a version bump), add a branch here AND a _rates entry there.
def tier($m):
  ($m // "" | ascii_downcase) as $l
  | if   ($l | test("fable|mythos")) then "fable"
    elif ($l | test("opus"))         then "opus"
    elif ($l | test("haiku"))        then "haiku"
    elif ($l | test("sonnet"))       then "sonnet"
    else "sonnet" end;
