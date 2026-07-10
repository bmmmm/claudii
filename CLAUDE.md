# claudii — Claude Interaction Intelligence

zsh plugin + CLI for Claude Code power users.

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
lib/cmd/system.sh       # Commands: on/off, claudestatus, session-dashboard, status, cc-statusline, insomnii, update, doctor
lib/cmd/sessions.sh     # Commands: sessions, sessions-inactive, pin, gc
lib/cmd/cost.sh         # Commands: cost, cost --forecast (history aggregation, D-grid + amount-sorted bars)
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
lib/model_tier.awk      # tier_label() — awk-side model→tier collapse (cost/trends)
lib/forecast.awk        # cost --forecast — 5h burn slope + month-end projection
lib/usage_spark.awk     # overview usage section — 30-day token-per-day sparkline
lib/epoch_to_date.awk   # epoch→YYYY-MM-DD without date forks (injected)
lib/tier.jq             # jq module: tier() model→rate-tier mapping
lib/otel.jq             # jq: Claude Code OTLP/JSON export → perf-cache shape (claudii-otel-receiver)
lib/insights.jq         # per-session JSONL aggregation program (claudii-insights)
lib/insights-merge.jq   # merge program: cache files → one aggregate (claudii-insights merge)
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

## Naming

- **ClaudeStatus** — RPROMPT health monitor (our feature)
- **Session Dashboard** — session lines prepended to PROMPT after claudii commands
- **Sessionline** — in-session status bar inside Claude Code (native implementation)
- **Overview** — what `claudii` (bare, no args) shows: account + usage + sessions + agents + services
- Commands: `claudii on/off`, `claudii status`, `claudii cc-statusline`
- Config keys: `statusline.*` (internal, don't rename)

## Command Roles — What Shows Where

| Name | Trigger | Location | Content |
|------|---------|----------|---------|
| **Session Dashboard** | automatic, after `claudii` commands | PROMPT (above prompt line) | Active sessions: model · ctx% · token throughput · 5h rate · ↺ |
| **ClaudeStatus** | automatic, after every command | RPROMPT (right side) | API health per model |
| **Overview** (`claudii`) | on demand | stdout | Modular sections via `overview.sections`: account · usage · sessions · activity · agents · services · commands |
| **`claudii status`** | on demand | stdout | Per-model API health + current incident from RSS timeline |
| **`claudii se`** | on demand | stdout | Full session detail: project · name · context bar · token throughput + cache-hit · rate · age · ID |
| **`claudii si`** | on demand | stdout | Inactive/ended sessions with GC hint |

## Status Cache

`~/.cache/claudii/status-models` (override: `CLAUDII_CACHE_DIR`):
```
opus=down
sonnet=ok
haiku=ok
```

Written by `bin/claudii-status`. Two refreshers, both TTL-gated with PID-file dedup (`status.pid`): the zsh precmd (adaptive TTL: 2× base healthy, ÷5 during incidents) and `bin/claudii-cc-statusline` (base TTL — without it the cache went stale during long Claude Code sessions with no shell prompt). No network in precmd itself — both only spawn the fetch in background.

## Rules

- All settings via config.json, nothing hardcoded
- jq is required
- No network calls in precmd (cache only)
- Background jobs: always `( cmd & )` subshell pattern (PID leak otherwise — details: gotchas memory #4)
- Compatible with oh-my-zsh, zinit, manual source
- Tests in tests/, run with `bash tests/run.sh` (add `--summary` for single-line pass/fail count). **CI macos-latest runs `/bin/bash` 3.2** — when a change touches test fixtures or any shell-quoting/default-arg/expansion logic, run `/bin/bash tests/run.sh` before pushing. Local `bash` is Homebrew 5.x and silently masks 3.2-only breakage (e.g. `${4:-{\}}` → `{\}` on 3.2 vs `{}` on 5.x), so a green local run is not a green CI run.
- **No `declare -A` in `bin/`** — macOS `/bin/bash` 3.2 silently degrades it to an indexed array (string keys evaluate as `arr[0]`, last-write-wins). Use `case` for label maps, `printf -v "_p_${k}" "%s" "$v"` + `${!_p_…}` for sparse 2D lookups, or parallel indexed arrays; guard new maps with a regression assert that invokes `/bin/bash` explicitly (the Homebrew-5.x test runner won't catch it).
- **Never string-match `statusLine.command`** — use `_cc_statusline_connected` (lib/helpers.sh). The configured command may be a wrapper chain (`cc-insomnii --after=<user-wrap>` where only the wrap script invokes `claudii-cc-statusline`); literal matching broke twice (insomnii wrapper, then user sleep-wrap) and made `claudii on` clobber the user's chain.
- **The 5h rate limit is account-wide** — never attribute it to a single model in UI text, and read it from the *newest* fresh `session-*` cache file (glob order is by session id, not freshness). All rate displays follow `statusline.rate_display`; color/thresholds stay keyed on used%.
- **An awk file carries no semantics of its own — verify any claim about a `lib/*.awk` program against its `-v` bindings at the call site** (`lib/cmd/*.sh`). Variable names lie: `trends.awk`'s `week_start` is bound to the *rolling* `seven_ts`, not the calendar week start. A review finding "confirmed" from the awk side alone produced a false CONFIRMED once (2026-07-02) — the refutation only surfaced on the pre-fix re-read of the binding site.

## Token efficiency (for Claude-in-session)

- **Use `bash tests/run.sh --summary`** instead of `… | tail -5` — saves ~500 lines per run.
- **Subagent prompts**: always cap reply length ("under 400 words"). Split by agent role: *search/Explore* agents (read-only, cheap models) get "only report PROVEN findings with reproducers" — they hallucinate verbose reports otherwise. *Bug-finding/review* agents (Opus) get the opposite — "report every finding incl. low-confidence ones, with a confidence level; filtering happens in a separate step"; models follow "be conservative / only high-severity" literally and silently drop real bugs, so filter outside the finding stage and verify on the main thread.
- **Agent reports are advisory, not authoritative** — always verify claims against current code before fixing (agents hallucinate file paths, CI config, and variable semantics).

## When adding features

1. Add command function `_cmd_<name>()` in the appropriate `lib/cmd/*.sh` file
2. Add dispatch entry in `bin/claudii` main case statement
3. Add completion in `completions/_claudii`
4. **Update `man/man1/claudii.1`** — this is the single source of truth
5. Add test in `tests/test_*.sh`
6. `test_docs.sh` verifies all five stay in sync
7. Wiki is auto-generated from the man page — never edit the wiki directly
8. Update `CHANGELOG.md` unreleased block

## When removing or renaming a command

1. `CHANGELOG.md` — update unreleased block
2. `tests/test_<command>.sh` — delete if exists
3. `.gitignore` — clean up stale rules if files were removed
4. `.claude/settings.local.json` — remove stale `Bash(...)` allow entry (local only — never commit, never `git add .claude/`)
5. Formula caveats live only in `bmmmm/homebrew-tap` (single source of truth) — `scripts/release.sh` syncs URL/SHA at release time. Edit there directly if caveats change.

## When a new Claude model ships

claudii only *recognizes and displays* model IDs — `/model` picks them, the defaults are version-agnostic — so a model bump is a display + docs sweep, not a config rename. Follow **`docs/model-bump-checklist.md`**: label cases, `_flat_1m_model()` window/pricing-shape check (incl. its untracked mirror in `~/.claude/hooks/compact-nudge.sh`), new-tier wiring across awk/jq/rates, `_KNOWN_MODEL_FAMILIES`, and the pricing `_rates` table.

## Project skills

`/shape` — hygiene + TODOs · `/orchestrate` — implement TODOs · `/explore` — ecosystem scan

## When orchestrating

Use `/orchestrate`. Each agent works on its own `worktree-<name>` branch — orchestrator merges back to main.
Set `git tag -f before-wave-N` before spawning, `git tag -f wave-N-done` after tests are green.
Revert one merged agent: `git revert <merge-hash> -m 1 --no-edit`.
Revert a full wave — `git revert before-wave-N..HEAD` does NOT work once the wave has `--no-ff` merge commits (fails with "commit … is a merge but no -m option given"). Use instead: **unpushed** → `git reset --hard before-wave-N`; **pushed** → revert each merge commit newest-first → `git revert -m 1 --no-edit <merge-N> … <merge-1>`.
**Agents touching `lib/statusline.zsh`:** warn about removed functions (`_claudii_render_global_line`, `_claudii_render_session_lines`, `_claudii_build_title`).
**Dashboard test preconditions:** `jq '."session-dashboard".enabled = "on"'` in config + `_CLAUDII_CMD_RAN=1` in zsh subprocess — both required or tests pass vacuously.
**After completing planned work:** if a `.claude/plans/*.md` file guided the work, delete it after implementing — plan files auto-load into every future session, and stale ones produce false "continue this work" prompts.

## When committing

Only check what the commit actually touches — skip checks that don't apply:

- Touched `bin/claudii` or `lib/cmd/*.sh`? → `bash tests/run.sh` + verify man page, completions, CHANGELOG in sync
- Removed a command? → orphaned `tests/test_<command>.sh` deleted?
- Docs/config only? → no checks needed

## When releasing

`scripts/release.sh <version>` is the only entry point (bump + double test-pass + tag + push + CI watch). Always `--dry-run` first. **SemVer from the unreleased block:** any `### Added` → bump MINOR; only `### Fixed`/`### Changed` → PATCH (pre-flight enforces it; deliberate under-bump needs `--allow-version-mismatch`).

**Dual-remote gap:** the script pushes `origin` only — push GitHub yourself afterwards (`git push github main && git push github vX.Y.Z`) or its CI watch times out (fix pending: issue #1). Full mechanics + half-release recovery: **`docs/release-runbook.md`**.

## Memory Types

This project overrides the default memory type set. Use these instead of the harness defaults:

- **`rule`** — evergreen discipline; reads like "always/never do X", no incident story needed.
- **`lesson`** — incident-based learning; the story is load-bearing — stripped of it, the rule loses force.
- **`project`** — fast-decaying initiative/state info; convert relative dates to absolute when saving.
- **`reference`** — pointers to external systems (URLs, repos, dashboards).
- **`user`** — language profile and collaboration preferences for bmmmm.

`feedback` is retired in this project — re-type any remaining `feedback_*.md` to `rule` or `lesson` on next touch.

**Slug convention (overrides the harness's kebab-case default):** a memory's frontmatter `name:` MUST equal its filename without `.md` (snake_case), and `[[links]]` use that exact slug — the harness's kebab-case default produces dangling `[[links]]` here (a whole collection drifted that way once). Pick the filename first, then set `name:` to match it verbatim.
