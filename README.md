# claudii

**See your Claude Code session costs, context usage, and rate limits directly in your shell prompt.**

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
claudii on
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
Dense metrics on every turn via the native `statusLine` hook. Four lines by default:

```
claude-sonnet-4-6  ████████░░  ⚡73%
5h:28%  7d:12%  eta:4h  +47/-12
api:23m (71%)  12.4k tok  wt:feature-branch
Opus ✓  Sonnet ✓  Haiku ✓
```

model + context bar + cache-create · rate-5h + rate-7d + burn-eta + lines-changed · api-duration + tokens + worktree · claude-status

### 2. Session Dashboard — above your shell prompt
Appears automatically after `claudii` commands when sessions are active:

```
  sonnet-4-6   73%  $25.63  5h:28% ↺42m
  opus-4       42%   $1.20
```

### 3. ClaudeStatus — RPROMPT
Model health in your right prompt, refreshed every 5 minutes. Never blocks your prompt.

![ClaudeStatus](screenshot-claudestatus.png)

`✓` ok · `~` degraded · `↓` down · `?` unreachable · `[…]` loading

## Commands

```bash
claudii                          # overview: sessions, account, agents, services
claudii on / off                 # enable/disable all display layers
claudii status                   # live model health check
claudii sessions / se            # active sessions with context, cost, rate
claudii sessions-inactive / si   # ended sessions + GC hint
claudii pin <id>                 # protect session from garbage collection
claudii unpin <id>               # remove GC protection
claudii cost / c                 # per-model cost breakdown
claudii trends / t               # weekly/daily cost history
claudii explain                  # explain claudii layers and architecture
claudii doctor / d               # installation health check
claudii config get/set <key>     # read/write config
claudii agents                   # list configured agent aliases
```

All commands support `--json` and `--tsv` for scripting. Full reference: `man claudii`

## Aliases

Registered dynamically from config — add/remove without editing shell files:

```bash
cl       # Sonnet, high effort — general default
clo      # Opus, high effort — complex tasks
clm      # Opus, max effort — maximum reasoning
clq      # Sonnet, medium effort — search mode
clh      # alias table + live model health
```

Auto-fallback: if a model is down, claudii picks a healthy one automatically.

Agent aliases launch Claude with a specific skill as the system prompt:

```bash
claudii agents                              # list configured agents
claudii config set agents.myagent.skill orchestrate
claudii config set agents.myagent.model opus
```

## Config

`~/.config/claudii/config.json` — created from defaults on first run.

| Key | Default | What it does |
|-----|---------|--------------|
| `aliases.cl.model` | `sonnet` | Model for `cl` |
| `aliases.clo.model` | `opus` | Model for `clo` |
| `fallback.enabled` | `true` | Auto-switch on outage |
| `status.cache_ttl` | `300` | Health check interval (seconds) |
| `statusline.models` | `opus,sonnet,haiku` | Models shown in RPROMPT |
| `session-dashboard.enabled` | `off` | Dashboard mode (on/off) |

## License

[GPL-3.0](LICENSE) · [ko-fi](https://ko-fi.com/bmabma)

---

<details>
<summary>How it works</summary>

**Shell prompt (ClaudeStatus):** A background subshell fetches `status.claude.com` — components API first, then RSS feed — once every 5 minutes, writes a plain-text cache file, then exits. No persistent process, no network calls in `precmd`.

**Inside Claude Code (CC-Statusline):** The native `statusLine` hook calls `claudii-sessionline` on each turn and passes session JSON via stdin. Nothing runs between turns.

</details>
