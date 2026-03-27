# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI: status, config, search
bin/claudii-status      # RSS parser, writes per-model cache
lib/config.zsh          # Config loader (jq, falls back to defaults)
lib/functions.zsh       # cl/clo/clm/clq/clh with auto-fallback
lib/statusline.zsh      # RPROMPT precmd hook
config/defaults.json    # Shipped defaults
```

## Config

User config: `~/.config/claudii/config.json`
Created from `config/defaults.json` on first load.

## Status Cache

`$TMPDIR/claudii-status-models` — per-model status:
```
opus=down
sonnet=ok
haiku=ok
```

Written by `bin/claudii-status`, read by statusline (no network in prompt).

## Rules

- All settings via config.json, nothing hardcoded
- jq is required
- No network calls in precmd (cache only)
- Compatible with oh-my-zsh, zinit, manual source
- Tests in tests/, run with `bash tests/run.sh`
