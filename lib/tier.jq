# tier.jq — jq module: map a raw model id to a rate-table tier key (tier), to
# its family and display label (family, model_label), and price a token
# bucket at its tier's rates (usd, model_usd, at the bottom).
# Included by lib/skills-cost-rows.jq, lib/skills-cost-compare.jq and
# lib/insights-cost-rows.jq via `include "tier";` (callers pass
# -L "$CLAUDII_HOME/lib").
# Most-specific first; unknown → sonnet (the historical blended default).
# Word-anchored like lib/model_tier.awk's tier_label() — a glued substring
# ("myopusx") must not classify as a tier. Keep in sync with the _rates table
# in lib/cmd/skills-cost.sh — on a new model TIER add a branch here AND a
# _rates entry there. A version bump CAN be price-relevant too: Sonnet 5
# ($2/$10) broke the tier-price assumption that 4.x ($3/$15) set, so sonnet-4*
# ids map to "sonnet-legacy" while everything else sonnet is the current rate.
# Fable 5.1 is the second, narrower case: only the cache read moved ($0.25/MTok
# flat, not 0.1×in), so "fable-legacy" prices Fable 5 / Mythos 5. The version
# tail matches `5` NOT followed by another segment — claude-fable-5 is legacy,
# claude-fable-5-1 (and a future 5.2) is not. claude-mythos-5-1 follows Fable
# 5.1: Anthropic left its cache read open at launch, and every sibling here
# already bills Mythos as Fable.
# Opus 5.5 (CC 2.1.280) is the third and inverted: it's the NEW price ($4/$20,
# 5% cache read, not the usual 10%) while every older opus id (5/4.8/4.7/4.6)
# keeps the existing "opus" rate — so the specific branch comes first and
# "opus" stays the fallback for everything else in the family, unlike the
# sonnet-legacy/fable-legacy pattern where the specific branch is the OLD price.
# The `($|[^0-9.-])` tail (copied from the Fable pattern, which needs it to
# reject "5-1") also rejects a dash-suffixed id like "claude-opus-5-5-20260915"
# — deliberately: per Anthropic's model-ids-and-versions doc, dateless IDs from
# the 4.6 generation on (which includes 5.5) ARE the pinned snapshot and never
# grow a dated suffix on the Claude API, so that shape shouldn't occur for this
# model. If a real platform ID ever does show up with a trailing suffix, widen
# this tail rather than dropping it — the digit/dash exclusion is what stops a
# hypothetical future "opus-5-50" or "opus-5-5-1" from misclassifying as 5.5.
# Sonnet 5.5 (5% cache read) reuses that tail as "sonnet-5-5"; plain "sonnet"
# stays Sonnet 5. Haiku 5.5 ($0.10/$0.50) follows the legacy pattern instead:
# haiku-4* ids are "haiku-legacy" ($1/$5); any other haiku is the current
# rate. Claude 3.x sonnet ids (claude-3-5-sonnet-*) are "sonnet-legacy"
# ($3/$15).
# The pre-4.5 list prices get their own keys, because the bare family rate
# is far off for them: Opus 4 / 4.1 and Claude 3 Opus bill $15/$75 (Opus fell
# to $5/$25 only with 4.5) — "opus-legacy"; Claude 3.5 Haiku $0.80/$4 —
# "haiku-3-5"; Claude 3 Haiku $0.25/$1.25 — "haiku-3" (both used to bill at
# haiku-legacy's $1/$5). Their tail `($|[^0-9.-]|-[0-9]{8})` accepts the end,
# a "[1m]"/"@"/space suffix or a dated snapshot ("claude-opus-4-20250514"),
# but not a "-5" minor: claude-opus-4-5 stays "opus".
def tier($m):
  ($m // "" | ascii_downcase) as $l
  | if   ($l | test("(^|[^a-z])(fable|mythos)[- ]5($|[^0-9.-])")) then "fable-legacy"
    elif ($l | test("(^|[^a-z])(fable|mythos)([^a-z]|$)")) then "fable"
    elif ($l | test("(^|[^a-z])opus[- ]5[- ]5($|[^0-9.-])")) then "opus-5-5"
    elif ($l | test("(^|[^a-z])opus[- ]4([- .][01])?($|[^0-9.-]|-[0-9]{8})") or
              ($l | test("(^|[^a-z0-9])3[- ]opus([^a-z]|$)"))) then "opus-legacy"
    elif ($l | test("(^|[^a-z])opus([^a-z]|$)"))           then "opus"
    elif ($l | test("(^|[^a-z])haiku[- ]3[- .]5($|[^0-9.-]|-[0-9]{8})") or
              ($l | test("(^|[^a-z0-9])3[-.]5[- ]haiku([^a-z]|$)"))) then "haiku-3-5"
    elif ($l | test("(^|[^a-z])haiku[- ]3($|[^0-9.-]|-[0-9]{8})") or
              ($l | test("(^|[^a-z0-9])3[- ]haiku([^a-z]|$)"))) then "haiku-3"
    elif ($l | test("(^|[^a-z])haiku[- ]4([^0-9]|$)") or
              ($l | test("(^|[^a-z0-9])3([-.][0-9])?[- ]haiku([^a-z]|$)"))) then "haiku-legacy"
    elif ($l | test("(^|[^a-z])haiku([^a-z]|$)"))          then "haiku"
    elif ($l | test("sonnet[- ]4([^0-9]|$)") or
              ($l | test("(^|[^a-z0-9])3([-.][0-9])?[- ]sonnet([^a-z]|$)"))) then "sonnet-legacy"
    elif ($l | test("(^|[^a-z])sonnet[- ]5[- ]5($|[^0-9.-])")) then "sonnet-5-5"
    else "sonnet" end;

# The model family, word-anchored like tier(): "Fable" (Mythos included),
# "Opus", "Sonnet", "Haiku", or "" for anything else. Same answer as
# tier_label() in lib/model_tier.awk for every Claude id; "" where awk hands an
# unknown id back.
def family($m):
  ($m // "" | ascii_downcase) as $l
  | if   ($l | test("(^|[^a-z])(fable|mythos)([^a-z]|$)")) then "Fable"
    elif ($l | test("(^|[^a-z])opus([^a-z]|$)"))   then "Opus"
    elif ($l | test("(^|[^a-z])sonnet([^a-z]|$)")) then "Sonnet"
    elif ($l | test("(^|[^a-z])haiku([^a-z]|$)"))  then "Haiku"
    else "" end;

# Display label: family + the version the id carries — "claude-opus-5-1" ->
# "Opus 5.1", "claude-3-5-haiku-20241022" -> "Haiku 3.5", "opus" -> "Opus".
# A single-digit minor only, so a trailing date is not read as one. Mythos
# labels as "Fable" without a version. The jq twin of _insights_model_label in
# lib/cmd/insights.sh — tests/test_model_label_agreement.sh pins the two to
# the same string; "" for a non-Claude id (bash passes it through).
def model_label($m):
  family($m) as $t
  | ($m // "" | ascii_downcase) as $l
  | if $t == "" then ""
    elif ($l | test("mythos")) then "Fable"
    else ( ($l | capture("(fable|opus|sonnet|haiku)-(?<a>[0-9])(-(?<b>[0-9]))?($|[^0-9])"))
           // ($l | capture("(^|[^a-z0-9])(?<a>[0-9])(-(?<b>[0-9]))?-(fable|opus|sonnet|haiku)"))
           // null ) as $c
      | if $c == null then $t
        elif $c.b == null then "\($t) \($c.a)"
        else "\($t) \($c.a).\($c.b)" end
    end;

# Price one token bucket {in_tok, out_tok, cache_read, cache_create,
# cache_create_1h} (all numbers — callers default missing keys to 0) at the
# _rates row $r. Cache writes bill by TTL: cache_create_1h at "cc1h" (2×
# input), the rest of cache_create at "cc" (5m, 1.25× input). A bucket without
# the TTL split (insights caches before schema v11) has cache_create_1h 0, so
# all its writes stay at the 5m rate — the split is never guessed. One
# definition for the per-model and the residual cost in both programs.
def usd($r):
  .in_tok * $r.in + .out_tok * $r.out + .cache_read * $r.cr
  + (.cache_create - .cache_create_1h) * $r.cc + .cache_create_1h * $r.cc1h;

# Price one per-model token bucket — an attribution bucket, or a day bucket in
# lib/insights-cost-rows.jq — {model, in_tok, … cache_create_1h, long_in_tok,
# … long_cache_create_1h} (callers default missing keys to 0). A
# tier with a "<tier>-long" row in $rates bills a request whose prompt is over
# its threshold at that row (Haiku 5.5: "haiku-long", 5× every column, over
# 100,000 prompt tokens — cache reads and writes count towards the prompt, and
# the whole request pays the higher price, output included). insights.jq
# keeps that share in the long_* counters; the rest of the bucket bills at the
# tier's base row. Buckets without long_* (caches before schema v14, tiers
# without a -long row) price exactly as usd($rates[tier]) did.
def model_usd($rates):
  tier(.model) as $t
  | ($rates[$t + "-long"] // null) as $lr
  | if $lr == null then usd($rates[$t])
    else
      . as $b
      | ({in_tok: $b.long_in_tok, out_tok: $b.long_out_tok, cache_read: $b.long_cache_read,
          cache_create: $b.long_cache_create, cache_create_1h: $b.long_cache_create_1h}
         | map_values(. // 0)) as $l
      | ({in_tok: ($b.in_tok - $l.in_tok), out_tok: ($b.out_tok - $l.out_tok),
          cache_read: ($b.cache_read - $l.cache_read),
          cache_create: ($b.cache_create - $l.cache_create),
          cache_create_1h: ($b.cache_create_1h - $l.cache_create_1h)} | usd($rates[$t]))
        + ($l | usd($lr))
    end;

# Price the aggregate rows of one attribution kind ("skill", "plugin", "mcp")
# of a merged insights document — the single copy of what lib/skills-cost-
# rows.jq and lib/skills-cost-compare.jq each used to carry.
#   .[$k]                  {name: {calls, in_tok, out_tok, cache_read, …}}
#   .attribution_models    {"<kind>|<name>|<model>": token bucket} (schema v5)
# Each row's per-model buckets are priced at their own tier (model_usd). What
# they do not cover — aggregate minus the per-model tokens, i.e. pre-v5 or
# orphaned data — prices at the flat legacy-Sonnet rate, which that data
# predates Sonnet 5 for. model is the bucket model with >= 80% of the row's
# attributed calls, else "mixed". Output, in .[$k] order:
#   [{name, calls, in_tok, out_tok, cache_read, cache_create,
#     cache_create_1h, tot_usd, model}]
def attr_rows($kind; $k; $rates):
  ( .attribution_models // {} | to_entries
    | map((.key | split("|")) as $p
        | select($p[0] == $kind)
        | {name: ($p[1] // ""), model: ($p[2] // "unknown"),
           calls:                (.value.calls                // 0),
           in_tok:               (.value.in_tok               // 0),
           out_tok:              (.value.out_tok              // 0),
           cache_read:           (.value.cache_read           // 0),
           cache_create:         (.value.cache_create         // 0),
           cache_create_1h:      (.value.cache_create_1h      // 0),
           long_in_tok:          (.value.long_in_tok          // 0),
           long_out_tok:         (.value.long_out_tok         // 0),
           long_cache_read:      (.value.long_cache_read      // 0),
           long_cache_create:    (.value.long_cache_create    // 0),
           long_cache_create_1h: (.value.long_cache_create_1h // 0)}) ) as $am
  | .[$k] // {}
  | to_entries
  | map({name:            .key,
         calls:           (.value.calls           // 0),
         in_tok:          (.value.in_tok          // 0),
         out_tok:         (.value.out_tok         // 0),
         cache_read:      (.value.cache_read      // 0),
         cache_create:    (.value.cache_create    // 0),
         cache_create_1h: (.value.cache_create_1h // 0)})
  | map(. as $row
      | [$am[] | select(.name == $row.name)] as $cand
      | def res($f): [$row[$f] - ($cand | map(.[$f]) | add // 0), 0] | max;
      ($cand | map(model_usd($rates)) | add // 0) as $model_usd
      | ({in_tok: res("in_tok"), out_tok: res("out_tok"), cache_read: res("cache_read"),
          cache_create: res("cache_create"), cache_create_1h: res("cache_create_1h")}
         | usd($rates["sonnet-legacy"])) as $res_usd
      | ($cand | map(.calls) | add // 0) as $acalls
      | $row + {tot_usd: ($model_usd + $res_usd),
                model: (if $acalls <= 0 then "mixed"
                        else ($cand | max_by(.calls)) as $top
                          | if ($top.calls / $acalls) >= 0.8 then $top.model else "mixed" end
                        end)});
