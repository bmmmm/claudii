# claudii

**Claude Code session metrics in your shell — costs, rate limits, model health, and a bedtime nudge that escalates into a synthwave shame display past 1am.**

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
Dense metrics on every turn via the native `statusLine` hook:

```
Opus max ▲  ████████░░  ⚡73%
5h:28%  7d:12%  eta:4h  +47/-12
api:23m  12.4k↑ 4.2k↓  23m  feature-branch  ⌂ gateii
Opus ✓  Sonnet ✓  Haiku ✓  │  @orchestrate
⚡ commit-msg Qwen3.5-9B 2s
```

Layout, segments, and conditionals (`vpn`, `omlx`, `proxy`, `worktree` only render when relevant) are documented in `man claudii`. The `clock` segment escalates from a quiet `☾ 22:14` to a per-character rainbow + rotating glyph + rotating shame string if you push past 1h overdue — try it after 23:00.

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
claudii omlx [status|connect|test|disconnect]
                                 # local-LLM (oMLX/gateii) sessionline integration
claudii vpnii [set <name>|clear|show]
                                 # WireGuard tunnel marker for the VPN segment
                                 # (call from wg-quick PostUp/PreDown)
claudii vibemap [grid|strip|status|clear|path]
                                 # opt-in activity heatmap (default off)
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
| `statusline.bedtime` | `23:00` | Bedtime threshold for the `clock` segment (HH:MM, local time) |
| `statusline.rate_display` | `used` | Rate-limit mode: `used` or `remaining` (counts down) |
| `statusline.lines` | _see `config/defaults.json`_ | cc-statusline layout — array of arrays of segment names |
| `vibemap.enabled` | `false` | Opt-in: log each render to `~/.cache/claudii/vibemap.tsv`. Local-only, no prompt content. |
| `fallback.enabled` | `true` | Auto-switch alias to a healthy model on outage |
| `session-dashboard.enabled` | `off` | Show session dashboard above the prompt after `claudii` commands |

All keys: `claudii config set <Tab>` (zsh completion) or `man claudii`.

## License

[GPL-3.0](LICENSE) · [ko-fi](https://ko-fi.com/bmabma)

---

<details>
<summary>How it works</summary>

**Shell prompt (ClaudeStatus):** A background subshell fetches `status.claude.com` — components API first, then RSS feed — once every 5 minutes, writes a plain-text cache file, then exits. No persistent process, no network calls in `precmd`.

**Inside Claude Code (CC-Statusline):** The native `statusLine` hook calls `claudii-sessionline` on each turn and passes session JSON via stdin. Nothing runs between turns.

</details>
