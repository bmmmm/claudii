# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI dispatcher + shared helpers (<300 lines)
bin/claudii-status         # ClaudeStatus health checker (components API + RSS)
bin/claudii-cc-statusline  # In-session statusline handler (bash+jq, reads stdin JSON)
bin/claudii-insights       # JSONL aggregator for prompt-cache hit-rate insights
lib/cmd/system.sh       # Commands: on/off, claudestatus, session-dashboard, status, cc-statusline, update, doctor
lib/cmd/sessions.sh     # Commands: sessions, sessions-inactive, pin, gc
lib/cmd/cost.sh         # Command: cost (history-based aggregation + tile renderer)
lib/cmd/overview.sh     # Command: default overview (bare `claudii`)
lib/cmd/skills-cost.sh  # Command: skills-cost (per-skill/plugin cost from insights cache)
lib/cmd/display.sh      # Commands: trends, version, changelog, explain, 42
lib/cmd/config.sh       # Commands: config, agents, search
lib/trends.awk          # awk program for trends aggregation
lib/timefmt.sh          # Shared relative-time formatters (_fmt_rel/_fmt_brief, bash 3.2)
lib/config.zsh          # Config loader (jq, falls back to defaults)
lib/functions.zsh       # cl/clo/clm/clq/clh with auto-fallback
lib/statusline.zsh      # RPROMPT precmd hook
lib/visual.sh           # Color/symbol constants (CLAUDII_CLR_*, CLAUDII_SYM_*)
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
| **Overview** (`claudii`) | on demand | stdout | Account rate limits · Agents config · Services status · Session count summary |
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

Written by `bin/claudii-status`, read by RPROMPT (no network in precmd).

## Rules

- All settings via config.json, nothing hardcoded
- jq is required
- No network calls in precmd (cache only)
- Background jobs: always `( cmd & )` subshell pattern (prevents [N] PID leak — anonymous functions with no_monitor still leak)
- Compatible with oh-my-zsh, zinit, manual source
- Tests in tests/, run with `bash tests/run.sh` (add `--summary` for single-line pass/fail count)
- **`(( ++var ))` not `(( var++ ))`** — post-increment of 0 exits 1 under `set -e` on bash 5.x (Ubuntu CI), bash 3.2 (macOS) tolerates it silently. Use pre-increment for all standalone counters.
- **No `declare -A` in `bin/`** — every script there has `#!/bin/bash` and runs under macOS `/bin/bash` 3.2, which silently falls back to a regular indexed array and evaluates string keys as `arr[0]` (last-write-wins). Use `case` for label maps, `printf -v "_p_${k}" "%s" "$v"` + `${!_p_…}` for sparse 2D lookups, or parallel indexed arrays. The test runner uses Homebrew `bash` 5.x so it does NOT catch this — add a regression assert that invokes `/bin/bash` explicitly when adding similar maps.

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
5. The tier-collapsing AWK in `lib/cmd/cost.sh` / `lib/cmd/display.sh` is
   version-agnostic (matches bare `opus`/`sonnet`/`haiku`) — no change.
6. `CHANGELOG.md` unreleased block + `bash tests/run.sh --summary`.

If the new model also changes **pricing**, update the per-token constants in
`lib/cmd/skills-cost.sh` (`_P_IN`/`_P_OUT`/`_P_CR`/`_P_CC`) — those are the only hardcoded
rates (`claudii cost` itself reads `costUSD` from history, not these). Verify
`claudii skills-cost` totals afterwards.

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
VERSION + the man page + `CHANGELOG.md` (`[Unreleased]` → `[vX.Y.Z]`), runs the
test suite **twice** (pass 1 before the bump = fast gate; pass 2 after the bump =
authoritative — the bump rewrites the CHANGELOG, and version-aware tests like the
`changelog` notes check only validate the tagged state), commits, then pushes
`main` + the tag to `origin` (Forgejo). It returns once the tag is pushed.

1. **Version (SemVer):** any `### Added` in the unreleased block → bump MINOR
   (`0.20.0`); only `### Fixed`/`### Changed` → bump PATCH (`0.20.1`).
2. **Dry-run first:** `scripts/release.sh X.Y.Z --dry-run` checks pre-flight
   (clean tree, tag free, on main) + bump targets without mutating anything.
3. **Real run:** `scripts/release.sh X.Y.Z`. The double test-pass means a
   bump-induced failure aborts locally (files rolled back, no tag) instead of
   surfacing only on CI.
4. **Always watch CI — the script does NOT.** The tag reaches GitHub via the
   Forgejo→GitHub mirror and triggers `.github/workflows/release.yml` (clean-env
   tests → GitHub Release → Homebrew-tap sync). Run
   `gh run watch <id> --repo bmmmm/claudii` and confirm green. A failed run
   leaves the tag public with **no** Release and **no** tap sync — a half-release.
5. **Recovery from a half-release** (tag pushed, CI failed, no artifact yet): fix
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
