# tier.jq — jq module: map a raw model id to a rate-table tier key, and price
# a token bucket at that tier's rates (usd, at the bottom).
# Included by lib/skills-cost-rows.jq and lib/skills-cost-compare.jq via
# `include "tier";` (callers pass -L "$CLAUDII_HOME/lib").
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
# haiku-4* ids and Claude 3.x haiku ids (claude-3-5-haiku-*, claude-3-haiku-*)
# are "haiku-legacy" ($1/$5 — the old blanket rate, close enough for 3.x);
# any other haiku is the current rate. Claude 3.x sonnet ids
# (claude-3-5-sonnet-*) are "sonnet-legacy" ($3/$15).
def tier($m):
  ($m // "" | ascii_downcase) as $l
  | if   ($l | test("(^|[^a-z])(fable|mythos)[- ]5($|[^0-9.-])")) then "fable-legacy"
    elif ($l | test("(^|[^a-z])(fable|mythos)([^a-z]|$)")) then "fable"
    elif ($l | test("(^|[^a-z])opus[- ]5[- ]5($|[^0-9.-])")) then "opus-5-5"
    elif ($l | test("(^|[^a-z])opus([^a-z]|$)"))           then "opus"
    elif ($l | test("(^|[^a-z])haiku[- ]4([^0-9]|$)") or
              ($l | test("(^|[^a-z0-9])3([-.][0-9])?[- ]haiku([^a-z]|$)"))) then "haiku-legacy"
    elif ($l | test("(^|[^a-z])haiku([^a-z]|$)"))          then "haiku"
    elif ($l | test("sonnet[- ]4([^0-9]|$)") or
              ($l | test("(^|[^a-z0-9])3([-.][0-9])?[- ]sonnet([^a-z]|$)"))) then "sonnet-legacy"
    elif ($l | test("(^|[^a-z])sonnet[- ]5[- ]5($|[^0-9.-])")) then "sonnet-5-5"
    else "sonnet" end;

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

# Price one per-model attribution bucket {model, in_tok, … cache_create_1h,
# long_in_tok, … long_cache_create_1h} (callers default missing keys to 0). A
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
