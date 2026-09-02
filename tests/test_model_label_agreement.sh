# touches: lib/cmd/insights.sh lib/cmd/overview.sh lib/cmd/perf.sh lib/model_tier.awk lib/tier.jq

# test_model_label_agreement.sh — the four model->label implementations agree.
#
# There are four of them and they used to drift silently:
#   bash  _insights_model_label  (lib/cmd/insights.sh)  versioned display label
#   bash  _norm_model_short      (lib/cmd/overview.sh)  tier collapse, delegates
#   awk   tier_label()           (lib/model_tier.awk)   tier, cost/trends legends
#   jq    tier()                 (lib/tier.jq)          rate-table key
#
# awk and jq stay separate implementations on purpose — different languages,
# not duplication worth removing. What they need is this: ONE fixture list, run
# through all four, with every agreement AND every deliberate divergence pinned.
# The drift that motivated the file: bash did not know the Mythos->Fable alias
# that the other three did, so `claudii` printed "Fable" and `claudii perf`
# printed "mythos" for the SAME status-cache line.

# ── Runners ──────────────────────────────────────────────────────────────────
# insights.sh + overview.sh are pure function definitions when sourced (no side
# effects), so the two bash implementations can be called directly. NOT in a
# subshell — assert_eq increments the run.sh PASS/FAIL counters in this scope.
# lib/visual.sh first: _perf_health_line interpolates the CLAUDII_CLR_* palette
# unguarded, and run.sh runs test files under `set -u`.
source "$CLAUDII_HOME/lib/visual.sh" 2>/dev/null
source "$CLAUDII_HOME/lib/cmd/insights.sh" 2>/dev/null
source "$CLAUDII_HOME/lib/cmd/overview.sh" 2>/dev/null
source "$CLAUDII_HOME/lib/cmd/perf.sh" 2>/dev/null

_MLA_TIER_AWK=$(cat "$CLAUDII_HOME/lib/model_tier.awk")

# awk: same injection shape the real call sites use ($(<lib/model_tier.awk)
# spliced into the program at lib/cmd/cost.sh and lib/cmd/display.sh).
# LC_ALL=C, not LC_NUMERIC/LC_CTYPE — a set LC_ALL beats either, and CI has a
# de_DE leg (docs/gotchas.md, lesson_locale_awk).
_mla_awk() { LC_ALL=C awk -v m="$1" "$_MLA_TIER_AWK"' BEGIN { print tier_label(m) }'; }

# jq: the module as its consumers include it (-L "$CLAUDII_HOME/lib").
_mla_jq() { jq -L "$CLAUDII_HOME/lib" -rn --arg m "$1" 'include "tier"; tier($m)'; }

# ── The fixture list — one row per real model family ─────────────────────────
# Columns: model-id | bash label | bash tier | awk tier | jq rate key
# Kept as a here-doc rather than an array so a new model is one readable line.
# The jq column is lower-case by design (it keys the _rates table in
# lib/cmd/skills-cost.sh); the agreement assert compares it case-folded.
_MLA_ROWS='
claude-opus-5|Opus 5|Opus|Opus|opus
claude-opus-4-8|Opus 4.8|Opus|Opus|opus
claude-opus-4-7|Opus 4.7|Opus|Opus|opus
claude-sonnet-5|Sonnet 5|Sonnet|Sonnet|sonnet
claude-sonnet-4-6|Sonnet 4.6|Sonnet|Sonnet|sonnet-legacy
claude-haiku-4-5|Haiku 4.5|Haiku|Haiku|haiku
claude-fable-5|Fable 5|Fable|Fable|fable
claude-mythos-5-1|Fable|Fable|Fable|fable
opus|Opus|Opus|Opus|opus
sonnet|Sonnet|Sonnet|Sonnet|sonnet
haiku|Haiku|Haiku|Haiku|haiku
fable|Fable|Fable|Fable|fable
mythos|Fable|Fable|Fable|fable
'

while IFS='|' read -r _m _exp_label _exp_btier _exp_atier _exp_jtier; do
  [[ -z "$_m" ]] && continue

  # 1. Each implementation still says what this list says it says.
  assert_eq "label($_m): bash label"      "$_exp_label" "$(_insights_model_label "$_m")"
  assert_eq "label($_m): bash tier"       "$_exp_btier" "$(_norm_model_short "$_m")"
  assert_eq "label($_m): awk tier_label"  "$_exp_atier" "$(_mla_awk "$_m")"
  assert_eq "label($_m): jq tier"         "$_exp_jtier" "$(_mla_jq "$_m")"

  # 2. The agreement axis: the two tier implementations must return the SAME
  #    string, and the versioned bash label must start with that same tier.
  assert_eq "agree($_m): bash tier == awk tier" "$(_mla_awk "$_m")" "$(_norm_model_short "$_m")"
  assert_eq "agree($_m): bash label is tier-prefixed" \
    "$_exp_atier" "$(_lbl=$(_insights_model_label "$_m"); printf '%s' "${_lbl%% *}")"

  # 3. jq keys the rate table, so it lower-cases the tier — and it may REFINE
  #    it: Sonnet 4.x billed $3/$15 where Sonnet 5 bills $2/$10, so the rate key
  #    splits into "sonnet-legacy" where the label stays "Sonnet". That is a
  #    refinement, not a disagreement, so the family part is what has to match.
  #    Derived from jq's ACTUAL output, never from the expectation column — a
  #    branch keyed on the fixture would assert nothing about jq at all.
  _mla_jq_out=$(_mla_jq "$_m")
  assert_eq "agree($_m): jq key family == lower(awk tier)" \
    "$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$_exp_atier")" "${_mla_jq_out%-legacy}"
done <<< "$_MLA_ROWS"

# ── Documented divergences — pinned so they stay deliberate ──────────────────
# An unknown id: bash and awk hand it back untouched (it becomes its own legend
# entry), jq falls back to "sonnet" — the historical blended rate, so unpriced
# data still contributes a dollar figure instead of vanishing. Unifying these
# would change what `claudii skills-cost` charges for unknown models, so they
# are asserted apart rather than folded together.
assert_eq "unknown: bash label passes through" "gpt-4o"  "$(_insights_model_label gpt-4o)"
assert_eq "unknown: bash tier passes through"  "gpt-4o"  "$(_norm_model_short gpt-4o)"
assert_eq "unknown: awk passes through"        "gpt-4o"  "$(_mla_awk gpt-4o)"
assert_eq "unknown: jq falls back to sonnet"   "sonnet"  "$(_mla_jq gpt-4o)"

assert_eq "empty: bash label is empty"         ""        "$(_insights_model_label '')"
assert_eq "empty: bash tier is empty"          ""        "$(_norm_model_short '')"
assert_eq "empty: awk is empty"                ""        "$(_mla_awk '')"
assert_eq "empty: jq falls back to sonnet"     "sonnet"  "$(_mla_jq '')"

# Word anchoring: awk and jq anchor on non-letter boundaries (a glued substring
# must not classify — it drives legend grouping and a priced rate lookup), the
# bash globs match anywhere (the label is cosmetic). Pinned, not unified.
assert_eq "glued: bash label matches the substring" "Opus"    "$(_insights_model_label myopusx)"
assert_eq "glued: awk refuses the substring"        "myopusx" "$(_mla_awk myopusx)"
assert_eq "glued: jq refuses the substring"         "sonnet"  "$(_mla_jq myopusx)"

# Case folding: all four resolve a capitalised id. bash used to fold only in
# _norm_model_short, so _insights_model_label handed "Opus" straight back.
assert_eq "case: bash label folds"  "Opus 4.8" "$(_insights_model_label Claude-Opus-4-8)"
assert_eq "case: bash tier folds"   "Opus"     "$(_norm_model_short Claude-Opus-4-8)"
assert_eq "case: awk folds"         "Opus"     "$(_mla_awk Claude-Opus-4-8)"
assert_eq "case: jq folds"          "opus"     "$(_mla_jq Claude-Opus-4-8)"

# ── The regression guard: overview and perf render one cache identically ─────
# The actual visible symptom. Both read $CLAUDII_CACHE_DIR/status-models; the
# overview's ClaudeStatus block and _perf_health_line must produce the same
# string for every key in it, including a family only one of them used to know.
_MLA_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/claudii_mla.XXXXXX")
printf 'opus=ok\nsonnet=degraded\nhaiku=ok\nfable=ok\nmythos=down\n_incident=investigating\n' \
  > "$_MLA_CACHE/status-models"

_MLA_PERF=$(CLAUDII_CACHE_DIR="$_MLA_CACHE" _perf_health_line | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "perf health: renders the cache" "API health" "$_MLA_PERF"
assert_not_contains "perf health: no raw mythos key" "mythos" "$_MLA_PERF"

while IFS='=' read -r _k _v; do
  [[ -z "$_k" || "$_k" == _* ]] && continue
  # What the overview's ClaudeStatus block prints for this key vs. what the
  # perf health line prints for it. Before the merge these differed for
  # mythos ("Fable" vs "mythos").
  assert_contains "same cache, same string: $_k -> $(_insights_model_label "$_k")" \
    "$(_insights_model_label "$_k")" "$_MLA_PERF"
done < "$_MLA_CACHE/status-models"

# And the overview's own rendering of that cache names the same models.
_MLA_OV=$(CLAUDII_CACHE_DIR="$_MLA_CACHE" HOME="$HOME" \
  bash "$CLAUDII_HOME/bin/claudii" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "overview: degraded Sonnet named"  "Sonnet" "$_MLA_OV"
assert_contains "overview: down Mythos reads Fable" "Fable"  "$_MLA_OV"
assert_not_contains "overview: no raw mythos key"   "mythos" "$_MLA_OV"

rm -rf "$_MLA_CACHE"
unset _MLA_ROWS _MLA_CACHE _MLA_PERF _MLA_OV _MLA_TIER_AWK _MLA_JQ_OUT _mla_jq_out \
      _m _exp_label _exp_btier _exp_atier _exp_jtier _k _v
