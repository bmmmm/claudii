# claudii

**See your Claude Code session costs, context usage, and rate limits directly in your shell prompt.**

Most Claude Code tools live either *inside* Claude or as separate reporting dashboards. claudii bridges both — it feeds live session data into your normal zsh prompt so you always know what's happening without switching windows.

Pure bash + jq. No Python, no Node, no daemons. Compatible with oh-my-zsh, zinit, and manual source.

![CC-Statusline](screenshot-sessionline.png)

## Install

```bash
brew tap bmmmm/tap && brew install claudii
```

Add to `~/.zshrc`:
```bash
source "$(brew --prefix)/opt/claudii/libexec/claudii.plugin.zsh"
```

Enable the in-session status line (writes one key to `~/.claude/settings.json`):
```bash
claudii cc-statusline on
# restart Claude Code
```

<details>
<summary>Manual install (without Homebrew)</summary>

```bash
git clone https://github.com/bmmmm/claudii ~/claudii
bash ~/claudii/install.sh
```
</details>

## What you get

Three display layers, all read-only — claudii never modifies your sessions or makes API calls:

### 1. CC-Statusline — inside Claude Code
Dense metrics on every turn via the native `statusLine` hook.

```
claude-sonnet-4-5  ●●●●●●○○○○  $1.24  12.4k ⚡73%  5h:28%  +47/-12  0:42
```

model · context bar · cost · tokens + cache ratio · rate limits · lines changed · duration

### 2. Dashboard — above your shell prompt
Appears automatically when Claude sessions are running. One line per active session:

```
  Opus     73%  $25.63  5h:28% ↺42m
  Sonnet   42%  $1.20
```

### 3. ClaudeStatus — RPROMPT
Model health in your right prompt. Cache-only, never blocks your prompt.

![ClaudeStatus](screenshot-claudestatus.png)

`✓` ok · `~` degraded · `↓` down · `?` unreachable · `[…]` loading

## Highlights

- **Cost tracking** — per-session, per-day, per-model breakdown (`claudii cost`, `claudii trends`)
- **Rate-limit intelligence** — 5h/7d usage with reset countdown, auto-fallback to healthy models
- **Cache-hit ratio** — see how efficiently Claude uses prompt caching (`⚡73%`)
- **Notifications** — get pinged when your rate limit resets (`claudii watch`)
- **Fast aliases** — `cl` (Sonnet), `clo` (Opus), `clm` (Opus max) with auto-fallback on outage

## How it works

**Shell prompt:** A background subshell checks `status.claude.com` once every 15 minutes, writes a plain-text cache file, then exits. No persistent process, no network calls in `precmd`.

**Inside Claude Code:** The native `statusLine` hook calls `claudii-sessionline` on each turn and passes session JSON via stdin. Nothing runs between turns.

## Aliases

```bash
cl       # Sonnet, high effort — general default
clo      # Opus, high effort — complex tasks
clm      # Opus, max effort — maximum reasoning
clq      # Sonnet, medium effort — search mode
clh      # alias table + live model health
```

Auto-fallback: if a model is down, claudii picks a healthy one automatically.

## Agent Aliases

Agent aliases launch Claude with a specific skill as the system prompt:

```bash
claudii agents                              # list configured agents
claudii config set agents.clorch.skill orchestrate
claudii config set agents.clorch.model opus
```

## Commands

```bash
claudii                          # smart overview: sessions, account, agents, services
claudii on / off                 # enable/disable all display layers
claudii status                   # live model health check        (shortcut: s)
claudii sessions                 # active + recent sessions       (shortcut: ss)
claudii cost                     # per-model cost breakdown       (shortcut: c)
claudii trends                   # weekly/daily cost history      (shortcut: t)
claudii watch                    # notify when rate limit resets
claudii doctor                   # installation health check      (shortcut: d)
claudii config get/set <key>     # read/write config
```

All commands support `--json` and `--tsv` for scripting. Full reference: `man claudii`

## Config

`~/.config/claudii/config.json` — created from defaults on first run.

| Key | Default | What it does |
|-----|---------|--------------|
| `aliases.cl.model` | `sonnet` | Model for `cl` |
| `aliases.clo.model` | `opus` | Model for `clo` |
| `fallback.enabled` | `true` | Auto-switch on outage |
| `status.cache_ttl` | `900` | Health check interval (seconds) |
| `statusline.models` | `opus,sonnet,haiku` | Models shown in RPROMPT |
| `dashboard.enabled` | `auto` | Dashboard mode (auto/true/off) |
| `watch.sound` | `` | Path to sound file for notifications |
| `watch.volume` | `50` | Notification volume (0-100) |

## License

[GPL-3.0](LICENSE) · [ko-fi](https://ko-fi.com/bmabma)
