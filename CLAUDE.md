# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture & Command Roles

Full file map (every `bin/`, `lib/`, `lib/cmd/*` role) and the
what-shows-where table (Sessionline / Dashboard / RPROMPT / stdout commands):
**`docs/architecture.md`** — read it before navigating the code or adding a
command/segment. Invariant kept here: config keys `statusline.*` are internal —
don't rename.

## Status Cache

`~/.cache/claudii/status-models` (override: `CLAUDII_CACHE_DIR`):
```
opus=down
sonnet=ok
haiku=ok
```

Written by `bin/claudii-status`. Two refreshers, both TTL-gated with PID-file dedup (`status.pid`): the zsh precmd (adaptive TTL: 2× base healthy, ÷5 during incidents) and `bin/claudii-cc-statusline` (base TTL — without it the cache went stale during long Claude Code sessions with no shell prompt). No network in precmd itself — both only spawn the fetch in background.

## Rules

- Settings via config.json only (nothing hardcoded); jq required; no network calls in precmd (cache only); compatible with oh-my-zsh/zinit/manual source
- Background jobs: always `( cmd & )` subshell pattern (PID leak otherwise — details: gotchas memory #4)
- Tests in tests/, `bash tests/run.sh` (`--summary` for single-line pass/fail count). **CI macos-latest runs `/bin/bash` 3.2**, local `bash` is Homebrew 5.x and masks 3.2-only breakage — a green local run is not a green CI run. Details + repro: `docs/gotchas.md`.
- **No `declare -A` in `bin/`** — `/bin/bash` 3.2 silently degrades it to an indexed array. Details + workarounds: `docs/gotchas.md`.
- **Never string-match `statusLine.command`** — use `_cc_statusline_connected` (lib/helpers.sh) instead; literal matching has broken this twice. Details: `docs/gotchas.md`.
- **The 5h rate limit is account-wide** — never attribute it to a single model in UI text, and read it from the *newest* fresh `session-*` cache file (glob order is by session id, not freshness). All rate displays follow `statusline.rate_display`; color/thresholds stay keyed on used%.
- **An awk file carries no semantics of its own** — verify any claim about a `lib/*.awk` program against its `-v` bindings at the call site (`lib/cmd/*.sh`); variable names lie. Incident + details: `docs/gotchas.md`.

## Token efficiency (for Claude-in-session)

- **Use `bash tests/run.sh --summary`** instead of `… | tail -5` — saves ~500 lines per run.

## When adding features

1. Add command function `_cmd_<name>()` in the appropriate `lib/cmd/*.sh` file
2. Add dispatch entry in `bin/claudii` main case statement
3. Add completion in `completions/_claudii`
4. **Update `man/man1/claudii.1`**
5. Add test in `tests/test_*.sh`
6. `test_docs.sh` verifies all five stay in sync — but only for names in its hardcoded `MAN_COMMANDS`/`ALL_COMMANDS` arrays: **add the new name there too**, or the gate passes vacuously. Statusline segments are the exception: their list is derived from the dispatch `case`, so a new segment goes red until the man page has its `^name<TAB>` row
7. Wiki is auto-generated from the man page — never edit the wiki directly
8. Update `CHANGELOG.md` unreleased block

## When removing or renaming a command

1. `CHANGELOG.md` — update unreleased block
2. `tests/test_<command>.sh` — delete if exists
3. `.gitignore` — clean up stale rules if files were removed
4. `.claude/settings.local.json` — remove stale `Bash(...)` allow entry (local only — never commit, never `git add .claude/`)
5. Formula caveats live only in `bmmmm/homebrew-tap` (single source of truth) — `scripts/release.sh` syncs URL/SHA at release time. Edit there directly if caveats change.

## When a new Claude model ships

A model bump is a display + docs sweep, not a config rename (background: `docs/model-bump-checklist.md`). Checklist: label cases, `_flat_1m_model()` window/pricing-shape check (incl. its untracked mirror in `~/.claude/hooks/compact-nudge.sh`), new-tier wiring across awk/jq/rates, `_KNOWN_MODEL_FAMILIES`, and the pricing `_rates` table.

## Project skills

`/shape` — hygiene + TODOs · `/orchestrate` — implement TODOs · `/explore` — ecosystem scan

## When orchestrating

Use `/orchestrate` — each agent works its own `worktree-<name>` branch,
orchestrator merges back to main. Wave-tag/revert recipes, known
`lib/statusline.zsh` / dashboard-test regressions, and the post-work
plan-file cleanup reminder: **`docs/orchestration-notes.md`**.

## When committing

Only check what the commit actually touches: code → `bash tests/run.sh` + the doc-sync steps above; a removed command → also delete its `tests/test_<command>.sh`; docs/config only → no checks.

## When releasing

`scripts/release.sh <version>` is the only entry point (bump + double test-pass + tag + push + CI watch). Always `--dry-run` first. **SemVer from the unreleased block:** any `### Added` → bump MINOR; only `### Fixed`/`### Changed` → PATCH (pre-flight enforces it; deliberate under-bump needs `--allow-version-mismatch`).

**Dual-remote:** the script pushes `origin`, then (if a local `github` remote exists) main + the tag to `github` too, before the CI watch — no manual GitHub push needed anymore (was issue #1). Commands + half-release recovery: **`docs/release-runbook.md`**.

## Memory Types

This project overrides the default memory type set. Use these instead of the harness defaults:

- **`rule`** — evergreen discipline; reads like "always/never do X", no incident story needed.
- **`lesson`** — incident-based learning; the story is load-bearing — stripped of it, the rule loses force.
- **`project`** — fast-decaying initiative/state info; convert relative dates to absolute when saving.
- **`reference`** — pointers to external systems (URLs, repos, dashboards).
- **`user`** — language profile and collaboration preferences for bmmmm.

`feedback` is retired in this project — re-type any remaining `feedback_*.md` to `rule` or `lesson` on next touch.

**Slug convention (overrides the harness's kebab-case default):** a memory's frontmatter `name:` MUST equal its filename without `.md` (snake_case), and `[[links]]` use that exact slug — the harness's kebab-case default produces dangling `[[links]]` here (a whole collection drifted that way once). Pick the filename first, then set `name:` to match it verbatim.
