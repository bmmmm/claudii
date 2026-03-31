# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI dispatcher + shared helpers (<300 lines)
bin/claudii-status      # ClaudeStatus health checker (components API + RSS)
bin/claudii-sessionline # Sessionline handler (bash+jq, reads stdin JSON)
lib/cmd/system.sh       # Commands: on/off, claudestatus, session-dashboard, status, cc-statusline, update, watch, doctor
lib/cmd/sessions.sh     # Commands: cost, sessions, sessions-inactive, default
lib/cmd/display.sh      # Commands: trends, version, changelog, layers, 42
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
- Tests in tests/, run with `bash tests/run.sh`
- **`(( ++var ))` not `(( var++ ))`** — post-increment of 0 exits 1 under `set -e` on bash 5.x (Ubuntu CI), bash 3.2 (macOS) tolerates it silently. Use pre-increment for all standalone counters.

## When adding features

1. Add command function `_cmd_<name>()` in the appropriate `lib/cmd/*.sh` file
2. Add dispatch entry in `bin/claudii` main case statement
3. Add completion in `completions/_claudii`
4. **Update `man/man1/claudii.1`** — this is the single source of truth
5. Add test in `tests/test_*.sh`
6. `test_docs.sh` verifies all five stay in sync
7. Wiki is auto-generated from the man page — never edit the wiki directly
8. Update `CHANGELOG.md` unreleased block
9. Check `memory/watchlist.md` Key Insights — remove entries for features now implemented

## When removing or renaming a command

1. `Formula/claudii.rb` — check caveats
2. `CHANGELOG.md` — update unreleased block
3. `tests/test_<command>.sh` — delete if exists
4. `.gitignore` — clean up stale rules if files were removed
5. `.claude/settings.local.json` — remove stale `Bash(...)` allow entry (local only — never commit, never `git add .claude/`)

## Available skills for this project

| Skill | When to use |
|-------|-------------|
| `/shape` | Hygiene check + feature ideas → TODOs |
| `/orchestrate` | Implement tasks from TODO.md via parallel agents |
| `/explore` | Competitive intelligence, ecosystem scan, upstream skill tracking |
| `/commit` | Auto-generate commit message and commit |
| `/commit-push-pr` | Commit + push + open PR in one step |
| `/clean_gone` | Clean up stale remote-deleted branches |
| `/revise-claude-md` | Update this CLAUDE.md with session learnings |
| `/claude-md-improver` | Audit and improve CLAUDE.md quality |
| `/skill-creator` | Create or improve skills in `.claude/skills/` |

## When orchestrating (wave tags + revert patterns)

- **Before each wave:** `git tag before-wave-N` — enables `git revert before-wave-N..HEAD` to undo the whole wave
- **After each wave (tests green):** `git tag wave-N-done`
- **Revert a single merge commit:** `git revert <hash> -m 1 --no-edit` — the `-m 1` is mandatory for merge commits
- **Agents touching `lib/statusline.zsh`:** always warn them about removed functions (`_claudii_render_global_line`, `_claudii_render_session_lines`, `_claudii_build_title`) so they don't re-add them from stale worktree state
- **Dashboard test preconditions:** `jq '."session-dashboard".enabled = "on"'` in config + `_CLAUDII_CMD_RAN=1` in zsh subprocess — both required or tests pass vacuously

## When committing

Only check what the commit actually touches — skip checks that don't apply:

- Touched `bin/claudii` or `lib/cmd/*.sh`? → `bash tests/run.sh` + verify man page, completions, CHANGELOG in sync
- Removed a command? → orphaned `tests/test_<command>.sh` deleted?
- Docs/config only? → no checks needed
