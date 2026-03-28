# claudii

**A passive display layer for Claude Code power users.**
claudii shows you what's happening — model health, session costs, context usage, rate limits.
It does not run agents, modify files, or call the network from your prompt.

![claudii screenshot](screenshot.png)

## What it does / What it doesn't

**It does:**
- Display model health (Opus/Sonnet/Haiku) in your RPROMPT — read from a local cache file, no network in precmd
- Show session data above your prompt — read from cache files written by Claude Code itself
- Render a dense status line inside Claude Code sessions with cost, context, tokens, rate limits
- Give you fast aliases (`cl`, `clo`, `clm`) with auto-fallback when a model is down

**It doesn't:**
- Make network calls in your shell prompt — zero latency impact on prompt rendering
- Run background processes constantly — the status cache refreshes once per TTL (default: 15 min), only when stale
- Intercept or modify your Claude sessions — the sessionline is a read-only display hook
- Install agents, daemons, or anything that starts on boot

**How the cache refresh works:**
The RPROMPT reads `~/.cache/claudii/status-models` (plain text, one line per model).
`claudii-status` writes that file when the cache is older than `status.cache_ttl` seconds.
It runs as a background subshell — one network call, then exits. No persistent process.

**How the sessionline works:**
Claude Code's native `statusLine` hook calls `claudii-sessionline` on each update and passes
session JSON via stdin. The handler writes a cache file and exits. Nothing runs between updates.

## Three display layers

### 1. ClaudeStatus — RPROMPT
Model health indicators. Reads from local cache only — never blocks your prompt.

```
➜  project (main)                       [Opus ✓ Sonnet ✓ Haiku ↓] 13m ⟳
```

Indicators: `✓` ok · `~` degraded · `↓` down · `?` API unreachable · `[…]` loading · `⟳` refreshing

### 2. SessionBar — above the prompt line
Live session data rendered by `precmd`. Reads from cache files written by the sessionline handler.
Only prints when the data changes.

```
Opus ████████░░ 76% │ $0.07 │ 5h:17% reset 43min
```

### 3. Sessionline — inside Claude Code
Rendered by Claude Code's own `statusLine` hook on every turn.

```
Opus ████░░░░░░ 42% │ $0.55 │ 15K↑ 4K↓ │ 5h:23% 7d:71% │ +156 -23 │ 12m
```

Shows: model · context bar · cost · token counts · rate limits · lines changed · session duration · worktree · agent context

## Install

```bash
brew tap bmmmm/tap && brew install claudii
```

Add to `~/.zshrc`:
```bash
source "$(brew --prefix)/opt/claudii/libexec/claudii.plugin.zsh"
```

Enable the sessionline (writes one key to `~/.claude/settings.json`):
```bash
claudii sessionline on
# then restart Claude Code
```

<details>
<summary>Manual install (without Homebrew)</summary>

```bash
git clone https://github.com/bmmmm/claudii ~/claudii
bash ~/claudii/install.sh
```
</details>

## Aliases

```bash
cl       # Claude Sonnet, high effort — general default
clo      # Claude Opus, high effort — complex tasks
clm      # Claude Opus, max effort — maximum reasoning
clq      # Claude Sonnet, medium effort — launches in search.dir
clh      # Alias table + live model health check
```

Auto-fallback: if the configured model is down, claudii picks a healthy one.
Configurable via `claudii config set aliases.cl.model <model>`.

## Commands

```bash
# ClaudeStatus
claudii on / off               # enable/disable RPROMPT indicator
claudii status                 # live model health check (bypasses cache)
claudii status 5m              # set cache refresh interval
claudii show model             # show monitored models
claudii show model opus sonnet # replace model list
claudii show model add haiku   # add a model
claudii show model rm haiku    # remove a model

# Sessionline
claudii sessionline            # show whether sessionline is active
claudii sessionline on / off   # configure in ~/.claude/settings.json
claudii sessions               # list active and recent sessions
claudii sessions --json        # JSON output

# Cost & analytics
claudii cost                   # today + all-time cost breakdown
claudii stats                  # session count + model distribution
claudii trends                 # weekly/daily cost history (Flight Recorder)

# Session handoff
claudii continue               # show context from last session
claudii continue --launch      # fork last session into a new one
claudii continue --resume      # resume the exact same session

# Notifications
claudii watch                  # start rate-limit reset notifier
claudii watch stop             # stop the notifier
claudii watch status           # check if running

# Config
claudii config                 # show all config values
claudii config get <key>       # read a value (dot-notation)
claudii config set <key> <val> # write a value
claudii config reset           # reset to defaults
claudii config export [file]   # export as JSON
claudii config import <file>   # import from JSON (backs up current)

# Diagnostics
claudii doctor                 # installation health check
claudii components             # component overview + data flow
claudii metrics                # plugin load time, hook timing (zsh only)
claudii debug [level]          # show or set log level (off/error/warn/info/debug)

# Other
claudii restart                # reload plugin (sources ~/.zshrc)
claudii version                # print version
claudii about                  # version + features + project URL
man claudii                    # full reference
```

## Shortcuts

| Short | Expands to |
|-------|------------|
| `s`   | `status`   |
| `ss`  | `sessions` |
| `c`   | `cost`     |
| `t`   | `trends`   |
| `d`   | `doctor`   |

Example: `claudii s` is identical to `claudii status`.

## Config

User config at `~/.config/claudii/config.json`. Created from defaults on first run.

Key paths (dot-notation):

| Key | Default | Description |
|-----|---------|-------------|
| `aliases.cl.model` | `sonnet` | Model for `cl` |
| `aliases.clo.model` | `opus` | Model for `clo` |
| `aliases.clm.effort` | `max` | Effort for `clm` |
| `fallback.enabled` | `true` | Auto-fallback on outage |
| `status.cache_ttl` | `900` | Cache TTL in seconds |
| `statusline.enabled` | `true` | ClaudeStatus in RPROMPT |
| `statusline.models` | `opus,sonnet,haiku` | Models to monitor |
| `search.dir` | `~/claude-search` | Directory for `clq` / `claudii search` |

## Cache files

```
~/.cache/claudii/status-models   # per-model health (opus=ok, sonnet=ok, ...)
~/.cache/claudii/session-*       # per-session data written by sessionline handler
~/.cache/claudii/history.tsv     # persistent cost history (Flight Recorder)
~/.cache/claudii/watch.pid       # watcher PID (only when watch is running)
```

## Requirements

`zsh` · `jq` · `curl`

Compatible with oh-my-zsh, zinit, and manual source.

## License

[GPL-3.0](LICENSE)
