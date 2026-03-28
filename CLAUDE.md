# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI: on/off, status, config, search
bin/claudii-status      # ClaudeStatus health checker (components API + RSS)
bin/claudii-sessionline # Claude Code Status Line handler
lib/config.zsh          # Config loader (jq, falls back to defaults)
lib/functions.zsh       # cl/clo/clm/clq/clh with auto-fallback
lib/statusline.zsh      # RPROMPT precmd hook
lib/log.sh              # Shared logging (bash + zsh)
config/defaults.json    # Shipped defaults
completions/_claudii    # zsh completions
man/man1/claudii.1      # Man page (groff) — single source of truth for docs
```

## Naming

- **ClaudeStatus** — RPROMPT health monitor (our feature)
- **Claude Code Status Line** — in-session bar (by wynandw87, bundled)
- Commands: `claudii on/off`, `claudii status`, `claudii sessionline`
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
- Background jobs: always `() { setopt local_options no_monitor; cmd & }` (prevents [N] PID leak)
- Compatible with oh-my-zsh, zinit, manual source
- Tests in tests/, run with `bash tests/run.sh`

## When adding features

1. Add code in `bin/claudii` or `lib/`
2. Add completion in `completions/_claudii`
3. **Update `man/man1/claudii.1`** — this is the single source of truth
4. Add test in `tests/test_*.sh`
5. `test_docs.sh` verifies all four stay in sync
6. Wiki is auto-generated from the man page — never edit the wiki directly
