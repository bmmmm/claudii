# Model-bump checklist

Referenced from CLAUDE.md § "When a new Claude model ships". Trigger this when
Anthropic releases a new versioned model (e.g. Opus 4.9).

Background: claudii does **not** pick the model for Claude Code — `/model` does.
claudii only *recognizes and displays* model IDs. The aliases/agent tiers in
`config/defaults.json` are version-agnostic on purpose (`opus`/`sonnet`/`haiku`
+ effort — Claude Code resolves `opus` to the latest). So a model bump is a
display + docs sweep, not a config rename. Older versions stay selectable via
`/model`; we only keep their friendly labels.

1. `lib/cmd/insights.sh` → `_insights_model_label()` — add `*opus-4-N*) → 'Opus 4.N'`
   case **above** the bare `*opus*` fallback (most-specific-first). Keep older cases.
2. `tests/test_cache.sh` — add a `label: opus 4.N (latest)` assert next to the existing
   ones (sourced `_insights_model_label` guard). Older asserts stay as regression cover.
3. `config/defaults.json` — bump any agent `description` that names a version
   (e.g. `orc`'s "Opus 4.N for long tool-chains"). Do **not** change `model`/`effort`.
4. `bin/claudii-cc-statusline` shows `.model.display_name` verbatim — no change
   for a version bump *within* an existing flat-1M-billing family. But check
   whether the **new model's context-window/pricing shape** matches its
   family's existing entry in `_flat_1m_model()` (opus/fable/mythos/sonnet-5+
   get a native 1M window, full-window compact floor, and never show the
   `>200k` marker; everything else gets the legacy 200k-default / paid-`[1m]`-
   opt-in treatment). A model that changes this shape (like Sonnet 5 did vs.
   Sonnet 4.6 — 1M went from paid opt-in to default, no premium) needs a new
   pattern arm here, confirmed against the `claude-api` skill or the user —
   don't assume from the family name alone. **The identical `case "$MODEL"`
   membership test also lives in `~/.claude/hooks/compact-nudge.sh`** (global,
   not version-controlled, no test suite) — sweep it in the same pass or it
   silently drifts.
5. The tier mappings are version-agnostic (match bare `fable`/`opus`/`sonnet`/
   `haiku`) — no change for version bumps within a tier. A **new tier** (e.g.
   Fable in 2026-06) needs: a `tier_label()` branch in `lib/model_tier.awk`
   (most-capable-first; covers cost AND trends), a `tier()` branch in
   `lib/tier.jq` (covers both skills-cost programs), a `_rates` entry in
   `lib/cmd/skills-cost.sh`, plus a bare-tier fallback case in
   `_insights_model_label()` (see pricing note below).
   Also add the family keyword to `_KNOWN_MODEL_FAMILIES` in
   `bin/claudii-status` — an incident that names only the new family (and
   lists the `API` component) would otherwise cascade `degraded` onto
   opus/sonnet/haiku via the broad-API fallback. The list is the superset of
   tracked + untracked families; only **new families** need adding (version
   bumps within `opus`/`sonnet`/`haiku`/`fable` already match).
   To also **surface the new family in the collapsed health display** (like
   Fable), add it to the `statusline.models` default in `config/defaults.json`
   and add its label case in three mirrors kept in sync: `_scm_lbl` (case) in
   `bin/claudii-cc-statusline`, `_norm_model_short` in `lib/cmd/overview.sh`,
   and — the zsh RPROMPT capitalizes via `${(C)model}` so no case is needed
   there. The display collapses to `claude ✓` when all are healthy, so an
   added family is invisible until it actually has an incident (`[Fable ↓]`).
6. `CHANGELOG.md` unreleased block + `bash tests/run.sh --summary`.

## Pricing changes

If the new model also changes **pricing**, update the per-model `_rates` table in
`lib/cmd/skills-cost.sh` (per-token USD per tier: in/out/cr/cc; cache_read = 0.1×
input, cache_create 5m = 1.25× input). That table is the only hardcoded rate set
(`claudii cost` itself reads `costUSD` from history, not these). The `tier()` def
in `lib/tier.jq` maps raw model ids to a `_rates` key (`fable`/`opus`/`haiku`/
`sonnet`, unknown → sonnet) — keep it in sync with the table. `claudii
skills-cost` prices each per-model token bucket (schema-v5 `attribution_models`)
at its tier; pre-v5 / orphaned caches have no per-model split, so their residual
tokens fall back to the flat Sonnet rate. Verify `claudii skills-cost` totals
afterwards.
