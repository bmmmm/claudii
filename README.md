# claudii

**A passive display layer for Claude Code power users.**
claudii shows you what's happening — model health, session costs, context usage, rate limits, cache efficiency.
No agents, no background daemons, no API calls from your prompt. Just reads local cache files.

## Highlights

- **Three display layers + Dashboard** — model health in RPROMPT, multi-session dashboard above your prompt, dense metrics line inside Claude Code
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

## Three display layers + Dashboard

### 1. ClaudeStatus — RPROMPT
Model health in your right prompt. Cache-only, never blocks.

![ClaudeStatus](screenshot-claudestatus.png)

`✓` ok · `~` degraded · `↓` down · `?` unreachable · `[…]` loading · `⟳` refreshing

### 2. Dashboard — above your prompt
Multi-session dashboard auto-activates when Claude sessions are running. Shows aggregated rate limits, per-session context bars, costs, and cache efficiency.

```
5h:8% reset 257min │ 7d:61% (+3%) │ $93.20 today (7 sessions)
Opus 4.6 ████████ 73% │ $25.63 │ ⚡42% │ [wt:main]
Sonnet   ████░░░░ 42% │ $1.20  │ [wt:feat-xyz]
Opus 4.6 ██░░░░░░ 15% │ $0.30  │ [agent:explorer]     [Opus ✓ Sonnet ✓ Haiku ✓] 21m
```

Toggle with `claudii dash on/off/auto`. Detail view: `claudii dash show`

### 3. Sessionline — inside Claude Code
Dense metrics on every turn via the `statusLine` hook.

![Sessionline](screenshot-sessionline.png)

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
claudii dash                   # multi-session dashboard detail view
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
| `dashboard.enabled` | `auto` | Dashboard mode (auto/true/off) |

## Why claudii?

Most Claude Code tools either live *inside* Claude (status bars, themes) or *outside* as reporting dashboards. claudii bridges both — it's the only tool that feeds live session data (cost, context, rate limits, cache efficiency) into your normal shell prompt, so you always know what's going on without switching windows.

It runs entirely on bash + jq. No Python, no Node, no daemons. `zsh` · `jq` · `curl` — that's the full dependency list. Compatible with oh-my-zsh, zinit, and manual source.

## License

[GPL-3.0](LICENSE)
