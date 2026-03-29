# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI: sessions, cost, trends, dashboard, watch, agents, config, search, on/off
bin/claudii-status      # ClaudeStatus health checker (components API + RSS)
bin/claudii-sessionline # Sessionline handler (bash+jq, reads stdin JSON)
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
- **Sessionline** — in-session status bar (native implementation)
- Commands: `claudii on/off`, `claudii status`, `claudii cc-statusline`
- Config keys: `statusline.*` (internal, don't rename)

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

## When adding features

1. Add code in `bin/claudii` or `lib/`
2. Add completion in `completions/_claudii`
3. **Update `man/man1/claudii.1`** — this is the single source of truth
4. Add test in `tests/test_*.sh`
5. `test_docs.sh` verifies all four stay in sync
6. Wiki is auto-generated from the man page — never edit the wiki directly
7. Update `CHANGELOG.md` unreleased block
8. Check `memory/watchlist.md` Key Insights — remove entries for features now implemented

## When removing or renaming a command

1. `Formula/claudii.rb` — check caveats
2. `CHANGELOG.md` — update unreleased block
3. `tests/test_<command>.sh` — delete if exists
4. `.gitignore` — clean up stale rules if files were removed

## When committing

Only check what the commit actually touches — skip checks that don't apply:

- Touched `bin/claudii` commands? → `bash tests/run.sh` + verify man page, completions, CHANGELOG in sync
- Removed a command? → orphaned `tests/test_<command>.sh` deleted?
- Docs/config only? → no checks needed
