# claudii

**Claude Interaction Intelligence** — zsh plugin for Claude Code power users.

## Features

- **Shell aliases** (`cl`, `clo`, `clm`, `clq`) with configurable model/effort presets
- **Auto-fallback** — switches to healthy model when one is down (via status.claude.com RSS)
- **RPROMPT statusline** — per-model health indicator with last-fetch age
- **`clh`** — quick reference table + live status
- **`claudii` CLI** — `status`, `config get/set/reset`, `search`
- **All settings configurable** — `~/.config/claudii/config.json`

## Install

### Homebrew (recommended)

```bash
brew tap bmmmm/claudii
brew install claudii
```

Add to `~/.zshrc`:
```bash
source "$(brew --prefix)/opt/claudii/libexec/claudii.plugin.zsh"
```

### Manual

```bash
git clone https://github.com/bmmmm/claudii ~/claudii
bash ~/claudii/install.sh
```

## Usage

```bash
cl              # Sonnet high (default)
clo             # Opus high
clm             # Opus max
clq             # Sonnet medium → ~/claude-search
clh             # Show alias table + model health

claudii status  # Check model health
claudii config  # Show all settings
claudii config get aliases.cl.model
claudii config set statusline.models "opus,sonnet"
claudii config set status.cache_ttl 600
claudii config reset
```

## RPROMPT

Shows per-model health + cache age, right-aligned:

```
➜  project (main)                        [Opus ↓ Sonnet ✓ Haiku ✓] 3m
```

Configure which models to show:

```bash
claudii config set statusline.models "opus"          # just Opus
claudii config set statusline.models "opus,sonnet"   # two models
claudii config set statusline.enabled false           # disable
```

## Config

Stored in `~/.config/claudii/config.json`. Defaults in `config/defaults.json`.

| Key | Default | Description |
|-----|---------|-------------|
| `aliases.cl.model` | sonnet | Model for `cl` |
| `aliases.cl.effort` | high | Effort for `cl` |
| `fallback.enabled` | true | Auto-switch on outage |
| `fallback.opus.model` | sonnet | Opus fallback model |
| `status.cache_ttl` | 900 | RSS fetch interval (seconds) |
| `status.rss_url` | status.claude.com/history.rss | Status feed URL |
| `statusline.enabled` | true | Show RPROMPT |
| `statusline.models` | opus,sonnet,haiku | Models to display |

## Structure

```
claudii.plugin.zsh      # Entry point
bin/
  claudii               # CLI (status, config, search)
  claudii-status        # RSS parser (standalone)
lib/
  config.zsh            # Config loader
  functions.zsh         # cl, clo, clm, clq, clh
  statusline.zsh        # RPROMPT hook
config/
  defaults.json         # Shipped defaults
tests/
  run.sh                # Test runner
  test_*.sh             # E2E tests
```

## Tests

```bash
bash tests/run.sh
```

## In-Session Statusline

Shows live metrics **inside** Claude Code sessions (complements the RPROMPT which works outside):

```
Opus ████░░░░░░ 42% $0.55 in:15.2K out:4.5K 5h:23% 7d:71%
```

- Model name, context window bar, session cost, token counts
- Rate limits (5h and 7d usage %, color-coded)

Setup:
```bash
claudii sessionline on   # adds statusLine to ~/.claude/settings.json
```

Inspired by [wynandw87/claude-code-statusline](https://github.com/wynandw87/claude-code-statusline) (MIT).

## Requirements

- zsh
- jq
- curl
