# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI dispatcher (<300 lines; helpers live in lib/helpers.sh)
bin/claudii-status         # ClaudeStatus health checker (components API + RSS)
bin/claudii-cc-statusline  # In-session statusline handler (bash+jq, reads stdin JSON)
bin/claudii-insights       # JSONL aggregator → per-session insights cache (aggregate/merge/gc)
bin/claudii-stop-hook        # Stop hook: terminalSequence notifications, session-cache keys
bin/claudii-session-end-hook # SessionEnd hook: desktop notification with session cost
lib/cmd/system.sh       # Commands: on/off, claudestatus, session-dashboard, status, cc-statusline, insomnii, update, doctor
lib/cmd/sessions.sh     # Commands: sessions, sessions-inactive, pin, gc
lib/cmd/cost.sh         # Command: cost (history-based aggregation + tile renderer)
lib/cmd/overview.sh     # Command: default overview (bare `claudii`)
lib/cmd/skills-cost.sh  # Command: skills-cost (per-skill/plugin/MCP cost, --compare)
lib/cmd/display.sh      # Commands: trends, version, changelog, explain, 42
lib/cmd/config.sh       # Commands: config, agents, search
lib/cmd/insights.sh     # Command: cache (prompt-cache hit-rate table)
lib/cmd/omlx.sh         # Command: omlx (gateii/oMLX integration)
lib/cmd/vibemap.sh      # Command: vibemap (activity heatmap; core in lib/vibemap.sh)
lib/cmd/vpnii.sh        # Command: vpnii (VPN state file for wg-quick hooks)
lib/helpers.sh          # Shared bash helpers (_cfgget, _parse_session_cache, _mtime, …)
lib/trends.awk          # awk program for trends aggregation
lib/attribution.awk     # attr_delta() — shared per-session cost/token delta heuristic
lib/model_tier.awk      # tier_label() — awk-side model→tier collapse (cost/trends)
lib/epoch_to_date.awk   # epoch→YYYY-MM-DD without date forks (injected)
lib/tier.jq             # jq module: tier() model→rate-tier mapping
lib/insights.jq         # per-session JSONL aggregation program (claudii-insights)
lib/insights-merge.jq   # merge program: cache files → one aggregate (claudii-insights merge)
lib/skills-cost-rows.jq    # skills-cost pricing program (per-model rates + residual)
lib/skills-cost-compare.jq # skills-cost --compare window-join program
lib/vibemap-grid.awk    # vibemap grid renderer
lib/vibemap-strip.awk   # vibemap mini-strip renderer
lib/vibemap.sh          # vibemap core (append/resolve, shared with cc-statusline)
lib/timefmt.sh          # Shared time formatters (_fmt_rel/_fmt_brief/_fmt_abs, bash 3.2)
lib/spinner.sh          # Spinner animation (BG job, label file)
lib/config.zsh          # Config loader (jq, falls back to defaults)
lib/functions.zsh       # cl/clo/clm/clq/clh with auto-fallback
lib/statusline.zsh      # RPROMPT precmd hook
lib/vpnii.zsh           # VPN/Tailscale RPROMPT segment
lib/visual.sh           # Color/symbol constants + theme loader (CLAUDII_CLR_*, CLAUDII_SYM_*)
lib/log.sh              # Shared logging (bash + zsh)
config/defaults.json    # Shipped defaults
completions/_claudii    # zsh completions
man/man1/claudii.1      # Man page (groff) — single source of truth for docs
```

## Naming

- **ClaudeStatus** — RPROMPT health monitor (our feature)
- **Session Dashboard** — session lines prepended to PROMPT after claudii commands
- **Sessionline** — in-session status bar inside Claude Code (native implementation)
- **Overview** — what `claudii` (bare, no args) shows: account + agents + services + session summary
- Commands: `claudii on/off`, `claudii status`, `claudii cc-statusline`
- Config keys: `statusline.*` (internal, don't rename)

## Command Roles — What Shows Where

| Name | Trigger | Location | Content |
|------|---------|----------|---------|
| **Session Dashboard** | automatic, after `claudii` commands | PROMPT (above prompt line) | Active sessions: model · ctx% · cost · 5h rate · ↺ |
| **ClaudeStatus** | automatic, after every command | RPROMPT (right side) | API health per model |
| **Overview** (`claudii`) | on demand | stdout | Modular sections via `overview.sections`: account · sessions · activity · agents · services · commands |
| **`claudii status`** | on demand | stdout | Per-model API health + current incident from RSS timeline |
| **`claudii se`** | on demand | stdout | Full session detail: project · name · context bar · cost · rate · age · ID |
| **`claudii si`** | on demand | stdout | Inactive/ended sessions with GC hint |

## Status Cache

`~/.cache/claudii/status-models` (override: `CLAUDII_CACHE_DIR`):
```
opus=down
sonnet=ok
haiku=ok
```

Written by `bin/claudii-status`. Two refreshers, both TTL-gated with PID-file dedup (`status.pid`): the zsh precmd (adaptive TTL: 2× base healthy, ÷5 during incidents) and `bin/claudii-cc-statusline` (base TTL — without it the cache went stale during long Claude Code sessions with no shell prompt). No network in precmd itself — both only spawn the fetch in background.

## Rules

- All settings via config.json, nothing hardcoded
- jq is required
- No network calls in precmd (cache only)
- Background jobs: always `( cmd & )` subshell pattern (prevents [N] PID leak — anonymous functions with no_monitor still leak)
- Compatible with oh-my-zsh, zinit, manual source
- Tests in tests/, run with `bash tests/run.sh` (add `--summary` for single-line pass/fail count)
- **`(( ++var ))` not `(( var++ ))`** — post-increment of 0 exits 1 under `set -e` on bash 5.x (Ubuntu CI), bash 3.2 (macOS) tolerates it silently. Use pre-increment for all standalone counters.
- **No `declare -A` in `bin/`** — every script there has `#!/bin/bash` and runs under macOS `/bin/bash` 3.2, which silently falls back to a regular indexed array and evaluates string keys as `arr[0]` (last-write-wins). Use `case` for label maps, `printf -v "_p_${k}" "%s" "$v"` + `${!_p_…}` for sparse 2D lookups, or parallel indexed arrays. The test runner uses Homebrew `bash` 5.x so it does NOT catch this — add a regression assert that invokes `/bin/bash` explicitly when adding similar maps.
- **Never string-match `statusLine.command`** — use `_cc_statusline_connected` (lib/helpers.sh). The configured command may be a wrapper chain (`cc-insomnii --after=<user-wrap>` where only the wrap script invokes `claudii-cc-statusline`); literal matching broke twice (insomnii wrapper, then user sleep-wrap) and made `claudii on` clobber the user's chain.
- **The 5h rate limit is account-wide** — never attribute it to a single model in UI text, and read it from the *newest* fresh `session-*` cache file (glob order is by session id, not freshness). All rate displays follow `statusline.rate_display`; color/thresholds stay keyed on used%.

## Token efficiency (for Claude-in-session)

Session transcripts show recurring waste patterns. Follow these:

- **Don't re-Read the same file within a session** unless it was just edited. Keep the content in working memory; scroll back if needed.
- **Use `bash tests/run.sh --summary`** instead of `… | tail -5` — saves ~500 lines per run.
- **Batch Edits per file** — 3+ sequential Edits to the same file means rewrite with Write instead.
- **Never `cat`/`grep`/`find` via Bash** — use Read/Grep/Glob tools. Pre-tool hooks should block this; if they don't, fix the hook.
- **Subagent prompts**: always cap reply length ("under 400 words"). Then split by agent role: *search/Explore* agents (read-only, cheap models) get "only report PROVEN findings with reproducers" — they hallucinate verbose reports otherwise. *Bug-finding/review* agents (Opus) get the opposite — "report every finding incl. low-confidence ones, with a confidence level; filtering happens in a separate step." Claude 4.8 follows "be conservative / only high-severity" literally and silently drops real bugs (recall loss), so move filtering out of the finding stage and verify on the main thread.
- **Parallelize tool calls** when independent — one message with N Bash/Read/Grep calls, not N sequential messages.
- **Agent reports are advisory, not authoritative** — always verify claims against current code before fixing (Explore agents hallucinate file paths, CI config, and variable semantics).

## When adding features

1. Add command function `_cmd_<name>()` in the appropriate `lib/cmd/*.sh` file
2. Add dispatch entry in `bin/claudii` main case statement
3. Add completion in `completions/_claudii`
4. **Update `man/man1/claudii.1`** — this is the single source of truth
5. Add test in `tests/test_*.sh`
6. `test_docs.sh` verifies all five stay in sync
7. Wiki is auto-generated from the man page — never edit the wiki directly
8. Update `CHANGELOG.md` unreleased block

## When removing or renaming a command

1. `CHANGELOG.md` — update unreleased block
2. `tests/test_<command>.sh` — delete if exists
3. `.gitignore` — clean up stale rules if files were removed
4. `.claude/settings.local.json` — remove stale `Bash(...)` allow entry (local only — never commit, never `git add .claude/`)
5. Formula caveats live only in `bmmmm/homebrew-tap` (single source of truth) — `scripts/release.sh` syncs URL/SHA at release time. Edit there directly if caveats change.

## When a new Claude model ships

claudii does **not** pick the model for Claude Code — `/model` does. claudii only
*recognizes and displays* model IDs. The aliases/agent tiers in `config/defaults.json`
are version-agnostic on purpose (`opus`/`sonnet`/`haiku` + effort — Claude Code resolves
`opus` to the latest). So a model bump is a display + docs sweep, not a config rename.
Older versions stay selectable via `/model`; we only keep their friendly labels.

Trigger this checklist when Anthropic releases a new versioned model (e.g. Opus 4.9):

1. `lib/cmd/insights.sh` → `_insights_model_label()` — add `*opus-4-N*) → 'Opus 4.N'`
   case **above** the bare `*opus*` fallback (most-specific-first). Keep older cases.
2. `tests/test_cache.sh` — add a `label: opus 4.N (latest)` assert next to the existing
   ones (sourced `_insights_model_label` guard). Older asserts stay as regression cover.
3. `config/defaults.json` — bump any agent `description` that names a version
   (e.g. `orc`'s "Opus 4.N for long tool-chains"). Do **not** change `model`/`effort`.
4. `bin/claudii-cc-statusline` already shows `.model.display_name` verbatim — no change.
5. The tier mappings are version-agnostic (match bare `fable`/`opus`/`sonnet`/
   `haiku`) — no change for version bumps within a tier. A **new tier** (e.g.
   Fable in 2026-06) needs: a `tier_label()` branch in `lib/model_tier.awk`
   (most-capable-first; covers cost AND trends), a `tier()` branch in
   `lib/tier.jq` (covers both skills-cost programs), a `_rates` entry in
   `lib/cmd/skills-cost.sh`, plus a bare-tier fallback case in
   `_insights_model_label()` (see pricing note below).
6. `CHANGELOG.md` unreleased block + `bash tests/run.sh --summary`.

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

## Project skills

`/shape` — hygiene + TODOs · `/orchestrate` — implement TODOs · `/explore` — ecosystem scan

## When orchestrating

Use `/orchestrate`. Each agent works on its own `worktree-<name>` branch — orchestrator merges back to main.
Set `git tag -f before-wave-N` before spawning, `git tag -f wave-N-done` after tests are green.
Revert one merged agent: `git revert <merge-hash> -m 1 --no-edit`.
Revert a full wave — `git revert before-wave-N..HEAD` does NOT work once the wave has `--no-ff` merge commits (fails with "commit … is a merge but no -m option given"). Use instead: **unpushed** → `git reset --hard before-wave-N`; **pushed** → revert each merge commit newest-first → `git revert -m 1 --no-edit <merge-N> … <merge-1>`.
**Agents touching `lib/statusline.zsh`:** warn about removed functions (`_claudii_render_global_line`, `_claudii_render_session_lines`, `_claudii_build_title`).
**Dashboard test preconditions:** `jq '."session-dashboard".enabled = "on"'` in config + `_CLAUDII_CMD_RAN=1` in zsh subprocess — both required or tests pass vacuously.

## After completing planned work

If a `.claude/plans/*.md` file was used to plan the work, delete it after implementing:
- Plan files are auto-loaded into every future session
- Stale plans produce false "continue this work" prompts

## When committing

Only check what the commit actually touches — skip checks that don't apply:

- Touched `bin/claudii` or `lib/cmd/*.sh`? → `bash tests/run.sh` + verify man page, completions, CHANGELOG in sync
- Removed a command? → orphaned `tests/test_<command>.sh` deleted?
- Docs/config only? → no checks needed

## When releasing

`scripts/release.sh <version>` is the only entry point. It bumps `bin/claudii`
VERSION + the man page + `CHANGELOG.md` (`[Unreleased]` → `[vX.Y.Z]`), runs
tests **twice** (pass 1 before the bump = full suite; pass 2 after the bump =
only the version-aware test files, grep-discovered via `VERSION=`/`CHANGELOG` —
the bump touches nothing else), commits, pushes `main` + the tag to `origin`
(Forgejo), then **watches CI by default** and exits non-zero if the workflow
fails (`--no-watch` to opt out for headless runs).

1. **Version (SemVer):** any `### Added` in the unreleased block → bump MINOR
   (`0.20.0`); only `### Fixed`/`### Changed` → bump PATCH (`0.20.1`). The
   pre-flight enforces this (plus a non-empty unreleased block); a deliberate
   under-bump needs `--allow-version-mismatch`.
2. **Dry-run first:** `scripts/release.sh X.Y.Z --dry-run` checks pre-flight
   (clean tree, tag free, on main, CHANGELOG plausibility) + bump targets
   without mutating anything.
3. **Real run:** `scripts/release.sh X.Y.Z`. The double test-pass means a
   bump-induced failure aborts locally (files rolled back, no tag) instead of
   surfacing only on CI. The tag reaches GitHub via the Forgejo→GitHub mirror
   and triggers `.github/workflows/release.yml` (clean-env tests → GitHub
   Release → Homebrew-tap sync); the script polls up to 2min for the run to
   appear, then blocks on `gh run watch`. A failed run leaves the tag public
   with **no** Release and **no** tap sync — a half-release; with `--no-watch`
   you must confirm CI green yourself.
4. **Recovery from a half-release** (tag pushed, CI failed, no artifact yet): fix
   + commit on main, `git tag -f vX.Y.Z`, `git push origin main`, then
   `git push origin vX.Y.Z --force` — the mirror force-carries the tag and
   re-triggers the workflow. Safe **only** because no artifact was consumed (tap
   not synced, no Release created); never force-move a tag that already shipped.

## Memory Types

This project overrides the default memory type set. Use these instead of the harness defaults:

- **`rule`** — evergreen discipline / how-to-apply pattern. Reads like "always do X" or "never do Y." No incident story needed. Example: "jq logic > 3 lines belongs in a `.jq` file."
- **`lesson`** — incident-based learning. Reads like "we got burned when Y, here's the rule that falls out." The story is load-bearing — if you strip it, the rule loses force. Example: "schema bumps require a Consumer-Sweep — we shipped v2 with `merge` still treating `limit_hits` as a counter, debug took bash -x."
- **`project`** — initiative/state info that decays fast (deadlines, who's doing what, why a rewrite is happening). Convert relative dates to absolute when saving.
- **`reference`** — pointers to external systems (URLs, repos, dashboards).
- **`user`** — language profile and collaboration preferences for bmmmm.

`feedback` is retired in this project — it conflated rules and lessons. Migration: every existing `feedback_*.md` should be re-typed to `rule` or `lesson` on next touch.
