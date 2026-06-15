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
bash tests/run.sh                        # full suite
bash tests/run.sh --summary              # single-line pass/fail count
bash tests/run.sh tests/test_status.sh   # single file
```

Tests are plain bash — no framework needed. Each `test_*.sh` file in `tests/` is
sourced by `run.sh`. Assert helpers: `assert_eq`, `assert_contains`,
`assert_not_contains`, `assert_matches`, `assert_exit_code`,
`assert_file_exists`, `assert_no_literal_ansi`.

CI runs on `macos-latest` and `ubuntu-latest`. macOS uses `/bin/bash` 3.2 (the
strictest target) and runs the suite under both `LC_ALL=C` and `de_DE.UTF-8`
(the comma-locale awk guard); Ubuntu runs under `C` only. Local `bash` is
usually Homebrew 5.x, which silently masks 3.2-only breakage — run
`/bin/bash tests/run.sh` before pushing any shell-quoting, default-arg, or
fixture change.

## Structure

```
claudii.plugin.zsh      # entry point (sources lib/)
bin/claudii              # CLI dispatcher (commands live in lib/cmd/)
bin/claudii-status         # ClaudeStatus health checker
bin/claudii-cc-statusline  # in-session statusline handler
bin/claudii-insights       # JSONL aggregator (per-session insights cache)
lib/cmd/*.sh             # one file per command group (cost, sessions, insights, …)
lib/*.sh                 # shared helpers (helpers.sh, render.sh, visual.sh, timefmt.sh)
lib/*.zsh                # shell integration (config, functions, statusline)
lib/*.jq / lib/*.awk     # aggregation programs (jq/awk >3 lines live in their own file)
config/defaults.json     # shipped defaults
completions/_claudii     # zsh completions
man/man1/claudii.1       # man page (groff) — single source of truth for docs
```

## Conventions

- **No hardcoded values** — everything via `config/defaults.json`
- **No network in precmd** — RPROMPT reads cache only, background refresh
- **jq required** — config is JSON, no awk/sed parsing
- **bash 3.2 compatible** — `bin/` runs under macOS `/bin/bash`: no `declare -A`, and `(( ++var ))` not `(( var++ ))`
- **Tests for everything** — new commands need a matching `test_*.sh`
- **Code comments in English**, UI text in German

## Adding a command

1. Add `_cmd_<name>()` in the right `lib/cmd/*.sh`
2. Add a dispatch entry in `bin/claudii`
3. Add a completion in `completions/_claudii`
4. Add a man page section in `man/man1/claudii.1`
5. Add a test in `tests/test_*.sh` and a `CHANGELOG.md` entry
6. Run `bash tests/run.sh` — the `test_docs.sh` suite verifies the man page, completion, dispatcher, and CHANGELOG stay in sync

## Naming

- **ClaudeStatus** — our RPROMPT health monitor
- **Session Dashboard** — session lines above the shell prompt
- **CC-Statusline** — in-session status bar inside Claude Code
- CLI commands: `claudii status`, `claudii cc-statusline` (lowercase)
- Config keys: `statusline.*` (internal, don't rename)

## Pull requests

- One feature per PR
- Tests must pass
- `man claudii` must document new commands
- GPL-3.0 applies to all contributions
