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
lib/cmd/sessions.sh     # Commands: cost, sessions, sessions-inactive, default
lib/cmd/display.sh      # Commands: trends, version, changelog, explain, 42
lib/cmd/config.sh       # Commands: config, agents, search
lib/trends.awk          # awk program for trends aggregation
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
- **Subagent prompts**: enforce "under 400 words" reply caps and "only report PROVEN bugs with reproducers" — Explore agents otherwise hallucinate verbose reports.
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

## Project skills

`/shape` — hygiene + TODOs · `/orchestrate` — implement TODOs · `/explore` — ecosystem scan

## When orchestrating

Use `/orchestrate`. Each agent works on its own `worktree-<name>` branch — orchestrator merges back to main.
Set `git tag -f before-wave-N` before spawning, `git tag -f wave-N-done` after tests are green.
Revert full wave: `git revert before-wave-N..HEAD`. Single merge commit: `git revert <hash> -m 1 --no-edit`.
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

## Memory Types

This project overrides the default memory type set. Use these instead of the harness defaults:

- **`rule`** — evergreen discipline / how-to-apply pattern. Reads like "always do X" or "never do Y." No incident story needed. Example: "jq logic > 3 lines belongs in a `.jq` file."
- **`lesson`** — incident-based learning. Reads like "we got burned when Y, here's the rule that falls out." The story is load-bearing — if you strip it, the rule loses force. Example: "schema bumps require a Consumer-Sweep — we shipped v2 with `merge` still treating `limit_hits` as a counter, debug took bash -x."
- **`project`** — initiative/state info that decays fast (deadlines, who's doing what, why a rewrite is happening). Convert relative dates to absolute when saving.
- **`reference`** — pointers to external systems (URLs, repos, dashboards).
- **`user`** — language profile and collaboration preferences for bmmmm.

`feedback` is retired in this project — it conflated rules and lessons. Migration: every existing `feedback_*.md` should be re-typed to `rule` or `lesson` on next touch.
