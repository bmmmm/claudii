# claudii

**Claude Code session intelligence in your shell — token usage, prompt-cache hit rate, costs, rate limits, model health, and effort-mode awareness. With the standalone [`cc-insomnii`](https://github.com/bmmmm/cc-insomnii) plugin, a bedtime nudge that escalates into a synthwave shame display past 1am.**

Pure bash + jq. No Python, no Node, no daemons. Read-only — claudii never modifies your sessions or makes API calls on your behalf. Compatible with oh-my-zsh, zinit, and manual source.

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

Optional: install [`cc-insomnii`](https://github.com/bmmmm/cc-insomnii) for the
animated bedtime-shaming `clock` segment (5+ escalation modes, 460+ shame
messages, char-decay, matrix-rain-drip). claudii auto-detects it and
delegates the clock rendering — no settings.json change needed:
```bash
git clone https://github.com/bmmmm/cc-insomnii ~/cc-insomnii && bash ~/cc-insomnii/install.sh
claudii doctor | grep insomnii   # confirms detection
# add 'clock' to your layout if it isn't already
```

<details>
<summary>Manual install (without Homebrew)</summary>

```bash
git clone https://github.com/bmmmm/claudii ~/claudii
bash ~/claudii/install.sh
```
</details>

## What you get

Three display layers, all read-only:

### 1. CC-Statusline — inside Claude Code
Dense metrics on every turn via the native `statusLine` hook:

```
Opus xhigh ▲  ████████░░  ⚡73%
5h:28%  7d:12%  eta:4h  +47/-12
api:23m  12.4k↑ 4.2k↓  23m  feature-branch  ⌂ gateii
Opus ✓  Sonnet ✓  Haiku ✓  │  @orchestrate
⚡ commit-msg Qwen3.5-9B 2s
```

The model segment shows the active **effort mode** — the high-end modes (`xhigh`,
`ultracode`, `max`) are highlighted, `▲` marks active thinking. `ultracode` is Claude
Code's menu mode (= `xhigh` effort plus standing consent to launch multi-agent
workflows); claudii renders it whether Claude Code reports `ultracode` or the
underlying `xhigh`.

Layout, segments, and conditionals (`vpn`, `omlx`, `proxy`, `worktree` only render when relevant) are documented in `man claudii`. Multi-line layouts need Claude Code ≥ 2.1.141 — earlier versions dropped or corrupted statusline rows longer than the terminal width (fixed upstream). The `clock` segment is provided by the standalone [`cc-insomnii`](https://github.com/bmmmm/cc-insomnii) plugin (when installed) — it escalates from a quiet `☾ 22:14` to a per-character rainbow + rotating glyph + rotating shame string past 1h overdue, with `breathing-pulse`, `char-decay`, `matrix-rain-drip`, and `glyph-swarm` modes once you cross +3h. Without cc-insomnii the `clock` segment renders nothing — pure CC-Statusline still works fine for everything else.

### 2. Session Dashboard — above your shell prompt
Appears automatically after `claudii` commands when sessions are active:

```
  opus-4-8     73%  18.2k tok  5h:28% ↺42m
  sonnet-4-6   42%   3.1k tok
```

### 3. ClaudeStatus — RPROMPT
Model health in your right prompt, refreshed every 5 minutes. Never blocks your prompt.

![ClaudeStatus](screenshot-claudestatus.png)

`✓` ok · `~` degraded · `↓` down · `?` unreachable · `[…]` loading

## Commands

```bash
claudii                          # overview: account, usage, sessions, agents, services
claudii on / off                 # enable/disable all display layers
claudii status                   # live model health check
claudii sessions / se            # active sessions: context, cost, rate
claudii sessions-inactive / si   # ended sessions + GC hint
claudii gc / g                   # garbage-collect ended sessions
claudii pin / unpin <id>         # protect a session from garbage collection
claudii cost / c                 # per-model cost breakdown (--forecast = burn rate)
claudii tokens                   # token usage by type, model & day (today/7d/30d/year)
claudii tools                    # tool-call counts + per-tool error rates
claudii limits                   # rate-limit hits — when they hit, which model ran
claudii cache                    # prompt-cache hit rate + tokens saved, per model & day
claudii session <id>             # per-session token / tool / subagent drilldown
claudii trends / t               # token + cost history, 30-day model split
claudii perf / pf                # response-time (p50/p90/p99) + throughput dashboard (today/7d/30d/year)
claudii skills-cost              # per-skill / per-plugin / per-MCP cost (--compare · --json)
claudii explain                  # explain claudii's layers and architecture
claudii doctor / d               # installation health check
claudii update                   # self-update (Homebrew or git checkout)
claudii changelog                # what changed between versions
claudii config get/set <key>     # read/write config
claudii agents                   # list configured agent aliases
claudii omlx [status|connect|test|disconnect]
                                 # local-LLM (oMLX/gateii) sessionline integration
claudii vpnii [set <name>|clear|show]
                                 # WireGuard tunnel marker for the VPN segment
                                 # (call from wg-quick PostUp/PreDown)
claudii vibemap [strip|grid|status|clear|path]
                                 # opt-in activity heatmap, last 30 days (default off)
```

Most data commands support `--json` and `--tsv` for scripting. Full reference: `man claudii`

## Aliases

Launch aliases register dynamically from config — add/remove without editing shell files.
Each pairs a model with an [effort level](https://platform.claude.com/docs/en/build-with-claude/effort)
(`low` → `medium` → `high` → `xhigh` → `max`); `high` is the default that balances quality
and token spend, `xhigh`/`max` for the heaviest work:

```bash
cl       # Sonnet, high effort — general default
clo      # Opus, high effort — complex tasks, server work
clm      # Opus, xhigh effort — hardest problems, maximum reasoning
clq      # Sonnet, medium effort — search mode
clh      # alias table + live model health
```

Auto-fallback: if a model is down, claudii picks a healthy one automatically.

Agent aliases launch Claude with a specific skill as the system prompt and a model/effort
tier matched to the workload (read-only Haiku for search, Sonnet for scoped features, Opus
for cross-file reasoning and orchestration):

```bash
claudii agents                              # list configured agents + their tier
claudii config set agents.myagent.skill orchestrate
claudii config set agents.myagent.model opus
claudii config set agents.myagent.effort high
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

**Inside Claude Code (CC-Statusline):** The native `statusLine` hook calls `claudii-cc-statusline` on each turn and passes session JSON via stdin. Nothing runs between turns.

**Cost, token & cache data:** Read straight from Claude Code's local session JSONL — `claudii cost`, `tokens`, `tools`, `limits`, `cache`, `trends`, `skills-cost`, and `perf` aggregate it with jq. No telemetry, nothing leaves your machine.

**`claudii perf` (alias `pf`):** Surfaces response-time percentiles (p50/p90/p99) and output throughput (tok/s), derived from transcript timestamps. Sections: by model, a per-day p50 latency sparkline with a today-vs-baseline delta, a by-repo breakdown (or by-session with `--repo NAME`), and a one-line API health read from the ClaudeStatus cache. Cycleable windows (`today`/`7d`/`30d`/`year`/`--days N`) and `--json`, like the other insights commands.

**Optional OpenTelemetry source for `perf`:** Opt in via `perf.otel.enabled` (toggle: `claudii-otel setup` / `claudii-otel off`). A tiny stdlib Python receiver (`bin/claudii-otel-receiver`, no pip/brew/collector needed) captures Claude Code's OTLP/JSON export to `~/.cache/claudii/otel/`. This upgrades latency from the transcript estimate to exact `duration_ms` + `ttft_ms` (time-to-first-token, shown as **TTFT**), per-response success rate with retry count, and an API errors breakdown by HTTP status code. The receiver binds `127.0.0.1` only; nothing leaves the machine by default. Set `perf.otel.forward` to a collector URL to mirror batches there best-effort for central retention. The active source is shown in the `perf` header (`source: otel` vs `source: transcript`).

</details>
