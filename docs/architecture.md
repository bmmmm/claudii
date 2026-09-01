# claudii — Architecture & Command Roles

Moved out of `CLAUDE.md` (2026-08-31) so the every-turn context stays under its
word gate; this file is the navigation reference — read it before working in
`lib/cmd/*`, adding a command, or touching a statusline segment. The behavioural
rules stay in `CLAUDE.md`.

## Architecture

```
claudii.plugin.zsh      # Entry point (sources lib/)
bin/claudii             # CLI dispatcher (<300 lines; helpers live in lib/helpers.sh)
bin/claudii-status         # ClaudeStatus health checker (components API + RSS)
bin/claudii-cc-statusline  # In-session statusline handler (bash+jq, reads stdin JSON)
bin/claudii-insights       # JSONL aggregator → per-session insights cache (aggregate/merge/gc)
bin/claudii-stop-hook        # Stop hook: terminalSequence notifications, session-cache keys
bin/claudii-session-end-hook # SessionEnd hook: desktop notification with session cost
bin/claudii-otel           # OTLP control (setup/off/receiver/doctor) — exact perf metrics vs transcript estimate
bin/claudii-otel-receiver  # Python OTLP/HTTP receiver → ~/.cache/claudii/otel/
bin/claudii-bumpii-refresh # Background refresher for the bumpii segment (pending updates + release inbox)
bin/claudii-ci-refresh     # Background refresher for the ci segment (gh run list → per-repo+branch cache)
lib/cmd/system.sh       # Commands: on/off, claudestatus, session-dashboard, status, cc-statusline, insomnii, update, doctor
lib/cmd/sessions.sh     # Commands: sessions, sessions-inactive, pin, gc
lib/cmd/cost.sh         # Commands: cost, cost --forecast, cost --window (history aggregation, D-grid + amount-sorted bars)
lib/cmd/week.sh         # Command: week (Anthropic 7-day rate-limit window; _week_stats/_week_render_block reused by limits)
lib/cmd/overview.sh     # Command: default overview (bare `claudii`)
lib/cmd/skills-cost.sh  # Command: skills-cost (per-skill/plugin/MCP cost, --compare)
lib/cmd/display.sh      # Commands: trends, version, changelog, explain, 42
lib/cmd/config.sh       # Commands: config, agents, search
lib/cmd/insights.sh     # Commands: cache, tokens, tools, limits, session (insights-cache views; cycleable window + --json)
lib/cmd/perf.sh         # Command: perf (response-time p50/p90/p99, tok/s, latency trend; OTLP metrics or transcript estimate)
lib/cmd/omlx.sh         # Command: omlx (gateii/oMLX integration)
lib/cmd/vibemap.sh      # Command: vibemap (activity heatmap; core in lib/vibemap.sh)
lib/cmd/vpnii.sh        # Command: vpnii (VPN state file for wg-quick hooks)
lib/helpers.sh          # Shared bash helpers (_cfgget, _parse_session_cache, _mtime, …)
lib/render.sh           # Shared bash renderers (_fmt_tok, _render_bar_row, _sparkline, _cache_hit_pct)
lib/fmt.awk             # Shared awk formatters (fmt_tok/fmt_usd/rep/bar — locale-immune)
lib/trends.awk          # awk program for trends aggregation
lib/attribution.awk     # attr_delta() — shared per-session cost/token delta heuristic
lib/window.awk          # week/cost --window — in-window tokens/cost + quota calibration pair (epoch-gated, uses attr_delta)
lib/model_tier.awk      # tier_label() — awk-side model→tier collapse (cost/trends)
lib/forecast.awk        # cost --forecast — 5h burn slope + month-end projection
lib/usage_spark.awk     # overview usage section — 30-day token-per-day sparkline
lib/epoch_to_date.awk   # epoch→YYYY-MM-DD without date forks (injected)
lib/tier.jq             # jq module: tier() model→rate-tier mapping
lib/otel.jq             # jq: Claude Code OTLP/JSON export → perf-cache shape (claudii-otel-receiver)
lib/insights.jq         # per-session JSONL aggregation program (claudii-insights)
lib/insights-merge.jq   # merge program: cache files → one aggregate (claudii-insights merge)
lib/repos.jq            # per-repo session rollup (claudii repos — active time vs wall-clock span)
lib/skills-cost-rows.jq    # skills-cost pricing program (per-model rates + residual)
lib/skills-cost-compare.jq # skills-cost --compare window-join program
lib/vibemap-grid.awk    # vibemap grid renderer
lib/vibemap-strip.awk   # vibemap mini-strip renderer
lib/vibemap.sh          # vibemap core (append/resolve, shared with cc-statusline)
lib/timefmt.sh          # Shared time formatters (_fmt_rel/_fmt_brief/_fmt_abs, bash 3.2)
lib/spinner.sh          # Spinner animation (BG job, label file)
lib/config.zsh          # Config loader (jq, falls back to defaults)
lib/functions.zsh       # cl/clo/clm/clq/clh with auto-fallback
lib/statusline.zsh      # RPROMPT precmd hook
lib/vpnii.zsh           # VPN/Tailscale RPROMPT segment
lib/visual.sh           # Color/symbol constants + theme loader (CLAUDII_CLR_*, CLAUDII_SYM_*)
lib/log.sh              # Shared logging (bash + zsh)
config/defaults.json    # Shipped defaults
completions/_claudii    # zsh completions
man/man1/claudii.1      # Man page (groff) — single source of truth for docs
```

## Command Roles — What Shows Where

- **Sessionline** — in-session status bar inside Claude Code (native, not ours)
- Config keys: `statusline.*` (internal, don't rename)

| Name | Trigger | Location | Content |
|------|---------|----------|---------|
| **Session Dashboard** | automatic, after `claudii` commands | PROMPT (above prompt line) | Active sessions: model · ctx% · token throughput · 5h rate · ↺ |
| **ClaudeStatus** | automatic, after every command | RPROMPT (right side) | API health per model |
| **Overview** (`claudii`) | on demand | stdout | Modular sections via `overview.sections`: account · usage · sessions · activity · agents · services · commands |
| **`claudii status`** | on demand | stdout | Per-model API health + current incident from RSS timeline |
| **`claudii se`** | on demand | stdout | Full session detail: project · name · context bar · token throughput + cache-hit · rate · age · ID |
| **`claudii si`** | on demand | stdout | Inactive/ended sessions with GC hint |
