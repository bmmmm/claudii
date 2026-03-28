# Contributing to claudii

## Setup

```bash
git clone https://github.com/bmmmm/claudii
cd claudii
```

No build step. The plugin runs directly from source.

### Dev vs Homebrew

If you have claudii installed via Homebrew, replace your source line in `~/.zshrc`:

```bash
# Dev version wins when present, otherwise falls back to Homebrew
source "${HOME}/path/to/claudii/claudii.plugin.zsh" 2>/dev/null \
  || source "$(brew --prefix)/opt/claudii/libexec/claudii.plugin.zsh"
```

The plugin detects conflicts automatically and warns if two installs are found.

## Tests

```bash
bash tests/run.sh              # full suite (210 tests)
bash tests/run.sh tests/test_status.sh   # single file
```

Tests are plain bash — no framework needed. Each `test_*.sh` file in `tests/` is sourced by `run.sh`. Assert helpers: `assert_eq`, `assert_contains`, `assert_exit_code`, `assert_file_exists`.

## Structure

```
claudii.plugin.zsh      # entry point (sources lib/)
bin/claudii              # CLI commands
bin/claudii-status       # ClaudeStatus health checker
bin/claudii-sessionline  # Claude Code sessionline handler
lib/config.zsh           # config loader (jq + zsh cache)
lib/functions.zsh        # shell aliases + metrics
lib/statusline.zsh       # RPROMPT precmd hook
lib/log.sh               # shared logging (bash + zsh)
config/defaults.json     # shipped defaults
completions/_claudii     # zsh completions
man/man1/claudii.1       # man page (groff)
```

## Conventions

- **No hardcoded values** — everything via `config/defaults.json`
- **No network in precmd** — RPROMPT reads cache only, background refresh
- **jq required** — config is JSON, no awk/sed parsing
- **Tests for everything** — new commands need matching `test_*.sh`
- **Code comments in English**, UI text in German

## Adding a command

1. Add case in `bin/claudii`
2. Add completion in `completions/_claudii`
3. Add man page section in `man/man1/claudii.1`
4. Add test in `tests/test_*.sh`
5. Run `bash tests/run.sh` — the `test_docs.sh` suite verifies all four are in sync

## Naming

- **ClaudeStatus** — our RPROMPT health monitor
- **Sessionline** — in-session status bar (native implementation)
- CLI commands: `claudii status`, `claudii sessionline` (lowercase)
- Config keys: `statusline.*` (internal, don't rename)

## Pull requests

- One feature per PR
- Tests must pass
- `man claudii` must document new commands
- GPL-3.0 applies to all contributions
