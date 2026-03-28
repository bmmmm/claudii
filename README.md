# claudii

**A passive display layer for Claude Code power users.**
claudii shows you what's happening — model health, session costs, context usage, rate limits, cache efficiency.
No agents, no background daemons, no API calls from your prompt. Just reads local cache files.

![claudii screenshot](screenshot.png)

## Highlights

- **Three display layers** — model health in RPROMPT, session bar above your prompt, dense metrics line inside Claude Code
- **Cache-hit ratio** — see how efficiently Claude uses prompt caching (`⚡73%`)
- **Rate-limit intelligence** — 5h/7d usage with reset countdown, auto-fallback to healthy models
- **Cost tracking** — per-session, per-day, per-model breakdown (`claudii cost`, `claudii trends`)
- **Session handoff** — pick up where you left off after context exhaustion (`claudii continue --launch`)
- **Notifications** — get pinged when your rate limit resets (`claudii watch`)
- **Fast aliases** — `cl` (Sonnet), `clo` (Opus), `clm` (Opus max) with effort mode display

## How it works

claudii is read-only. It never modifies your Claude sessions or makes API calls on your behalf.

**Shell prompt (RPROMPT + SessionBar):** Reads `~/.cache/claudii/status-models` — a plain text file written by a background subshell that checks `status.claude.com` once every 15 minutes, then exits. No persistent process, no network in `precmd`.

**Inside Claude Code (Sessionline):** Claude Code's native `statusLine` hook calls `claudii-sessionline` on each turn and passes session JSON via stdin. The handler writes a cache file and prints one line. Nothing runs between updates.

## Three display layers

### 1. ClaudeStatus — RPROMPT
Model health in your right prompt. Cache-only, never blocks.

```
➜  project (main)                       [Opus ✓ Sonnet ✓ Haiku ↓] 13m ⟳
```

`✓` ok · `~` degraded · `↓` down · `?` unreachable · `[…]` loading · `⟳` refreshing

### 2. SessionBar — above your prompt
Live session data from cache files. Only prints when data changes.

```
Opus ████████░░ 76% │ $0.07 │ 5h:17% reset 43min
```

### 3. Sessionline — inside Claude Code
Dense metrics on every turn via the `statusLine` hook.

```
Opus max ████░░░░░░ 42% │ $0.55 │ 15K↑ 4K↓ ⚡73% │ 5h:23% 7d:71% │ +156 -23 │ 12m
```

model · effort · context bar · cost · tokens + cache ratio · rate limits · lines changed · duration

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
cl       # Sonnet, high effort — general default
clo      # Opus, high effort — complex tasks
clm      # Opus, max effort — maximum reasoning
clq      # Sonnet, medium effort — search mode
clh      # alias table + live model health
```

Auto-fallback: if a model is down, claudii picks a healthy one.

## Commands

```bash
claudii status                 # live model health check
claudii sessions               # active + recent sessions
claudii cost                   # per-model cost breakdown (today + all-time)
claudii trends                 # weekly/daily cost history (Flight Recorder)
claudii continue --launch      # fork last session into a new one
claudii watch                  # notify when rate limit resets
claudii doctor                 # installation health check
claudii config get <key>       # read/write config (dot-notation)
```

Shortcuts: `s` → status, `ss` → sessions, `c` → cost, `t` → trends, `d` → doctor

All commands support `--json` and `--tsv` for scripting. Full reference: `man claudii`

## Config

`~/.config/claudii/config.json` — created from defaults on first run.

| Key | Default | What it does |
|-----|---------|--------------|
| `aliases.cl.model` | `sonnet` | Model for `cl` |
| `aliases.clo.model` | `opus` | Model for `clo` |
| `fallback.enabled` | `true` | Auto-switch on outage |
| `status.cache_ttl` | `900` | Health check interval (seconds) |
| `statusline.models` | `opus,sonnet,haiku` | Models in RPROMPT |

## Why claudii?

Most Claude Code tools either live *inside* Claude (status bars, themes) or *outside* as reporting dashboards. claudii bridges both — it's the only tool that feeds live session data (cost, context, rate limits, cache efficiency) into your normal shell prompt, so you always know what's going on without switching windows.

It runs entirely on bash + jq. No Python, no Node, no daemons. `zsh` · `jq` · `curl` — that's the full dependency list. Compatible with oh-my-zsh, zinit, and manual source.

## License

[GPL-3.0](LICENSE)
