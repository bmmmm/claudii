# Changelog

All notable changes to claudii are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

---

## [Unreleased]

---

## [v0.13.0] — 2026-04-07

### Added
- **`claudii gc`:** Manual session garbage collection — removes ended sessions that exceed the configured keep count
- **`claudii resume <id>`:** Print the `claude -r <uuid>` command for a session by short ID or index

### Fixed
- **ClaudeStatus:** Resolved incident detection now correctly matches HTML-encoded RSS entities (`&lt;strong&gt;`) — previously matched nothing, causing all recent incidents (including resolved ones) to trigger false degraded state
- **ClaudeStatus:** `claudii status` no longer aborts silently under `set -e` when models are degraded — added `|| true` to status check call
- **Config:** `claudii config set` now auto-creates nested parent paths using `setpath` — previously failed silently on missing intermediate keys
- **Config:** Search model/effort falls back through `search.*` → `aliases.clq.*` → hardcoded default
- **Sessions:** `claudii pin`/`unpin` use atomic `tmp+mv` write — eliminates race with concurrent sessionline rewrites
- **`claudii status`:** Removed duplicate incident display block

### Changed
- **Internal:** Extracted `_collect_history_files`, `_date_init`, `_spinner_start/stop` helpers from `bin/claudii` — reduces duplication across cost/trends/sessions commands
- **`scripts/cleanup-worktree.sh`:** Added `--all` flag and zombie dir support — handles physical dirs not registered in git worktree list

---

## [v0.12.0] — 2026-04-07

### Added
- **CC-Statusline:** New `claude-status` segment (default line 4) — shows model health indicators (`Opus ✓  Sonnet ✓  Haiku ✓`) from the ClaudeStatus cache directly inside Claude Code
- **History rotation:** Flight Recorder now writes monthly files (`history-YYYY-MM.tsv`) — prevents unbounded growth, old `history.tsv` still read for backward compat
- **Dynamic aliases:** Shell aliases (`cl`, `clo`, `clm`, `clq`) now registered dynamically from `aliases.*` in config — add/remove aliases without editing code
- **`claudii pin/unpin`:** Protect inactive sessions from garbage collection — pinned sessions show `⊡` badge in `claudii si`, stale sessions marked with `stale` tag
- **Shared epoch_to_date:** Deduplicated awk date function into `lib/epoch_to_date.awk`

### Removed
- **`claudii watch`** — Background notification watcher removed. Rate-limit info is already visible in Sessionline and Dashboard. Slot reserved for a better notification mechanism in the future.

### Changed
- **Internal:** Atomic jq-write pattern extracted into `_jq_update()` helper — replaces 14 inline instances across `system.sh` and `config.sh`
- **Internal:** Session JSONL lookup uses `_session_build_map` + single-pass `_session_resolve` — one awk per session instead of 3 greps
- **i18n:** All user-facing strings translated to English (config descriptions, error messages, prompts, table headers)
- **`claudii help`:** Alias table now reads from `config/defaults.json` dynamically

### Fixed
- **Performance:** Removed awk subprocess spawning in precmd hook (cost=0 history fallback) — eliminates latency spikes when history.tsv is large
- **Performance:** `claudii status` no longer fetches RSS twice — reads cached `status-cache.xml` from previous `claudii-status` run
- **Performance:** Prevent duplicate `claudii-status` background spawns via PID lock file
- **ClaudeStatus:** RSS feed now always fetched alongside components API — catches incidents Anthropic hasn't yet reflected in component status (previously only fetched on non-operational signal)
- **ClaudeStatus:** Default refresh interval reduced from 15min to 5min (`status.cache_ttl`: 900 → 300)

---

## [0.11.0] — 2026-04-03

### Added
- **Sessionline:** `duration` segment added to default line 3 — shows total session runtime, giving context to the `api-duration` ratio (e.g. `api:45m (73%)` is more readable when you can see total session was `1h02m`)
- **`claudii trends`:** Rolling 7-day window replaces calendar week — always shows exactly 7 days regardless of weekday; most recent day (Today) shown first
- **`claudii trends`:** Total line now includes session count and model breakdown (`21 sessions, 5 Opus, 16 Sonnet`)
- **`claudii trends`:** Two new stat lines — `Median: $X.XX/day (30d)` and `Trend: $X/day (7d) vs $X/day (30d) ↑/↓` for spend pattern awareness

### Fixed
- **`claudii trends`:** False-reset threshold applied — cost/token deltas < 50% drop no longer treated as context compaction (same fix as `claudii cost` in v0.9.0)

### Changed
- **Sessionline:** All hardcoded ANSI escape codes replaced with named color variables (`CYAN`, `GREEN`, `RED`, etc.) — palette now explicit and maintainable
- **Sessionline:** Reduced awk subprocess forks from 8 to 2 per update — integer arithmetic now uses bash `(( ))`
- **README:** Sessionline example updated to reflect 3-line multi-segment default; cost segment removed from example
- **`claudii cost`:** Session counts and token totals removed from display — pure dollar accounting; Total label highlighted in accent color with blank line after each section
- **Internal:** Hardcoded symbols (`●`, `○`, `│`, `✓`, `✗`, `⚠`, `⚡`) replaced with `CLAUDII_SYM_*` constants; added `CLAUDII_SYM_CACHE`, `CLAUDII_SYM_FINGERPRINT`, and `CLAUDII_SYM_MONITORING` to `visual.sh`

---

## [0.10.0] — 2026-04-03

### Added

- **`claudii trends`:** Daily API wait time shown per day (`api:1h23m`) — `api_duration_ms` now persisted in `history.tsv` (field 9)
- **Sessionline:** `api-duration` segment now shows ratio `api:45m (73%)` — API time as % of total session runtime
- **`claudii cost`/`claudii trends`:** Token usage tracking — `input_tok` and `output_tok` stored in `history.tsv`; displayed as `X.XK tok` / `X.XM tok` after each Total line
- **`claudii cost`:** Configurable week start via `cost.week_start` in config — supports all 7 day names (default: `monday`)
- **Sessionline:** Configurable multi-line output via `statusline.lines` in config.json — burn-eta, worktree, agent now visible on line 2 by default

### Changed
- **`claudii trends`:** "Last week" summary removed — period summaries are now exclusively in `claudii cost`; `claudii cost` is the accounting view, `claudii trends` is the visualization view
- **Sessionline:** `history.tsv` schema extended to 9 fields — `api_duration_ms` added as field 9; existing 8-field rows remain compatible (missing field treated as 0)
- **`claudii se`:** Cost removed from pretty output — use `claudii cost` for cost accounting; `--json` output retains the `cost` field
- **Release notes:** SHA256 checksum and Full Changelog compare URL appended automatically after GitHub Release is created; format simplified (no bullet lists)
- **Homebrew tap:** Auto-updated on release via polling workflow
- **Sessionline:** Segment pre-computation replaces monolithic output string; COLUMNS-based adaptive truncation removed

### Fixed
- **Release workflow:** `head_sha` filter corrected in polling step; unindented `---` no longer breaks YAML block scalar
- **Sessionline:** Duplicate `date +%s` call eliminated; `bc` subprocess in `_tok()` replaced with pure awk; `history.tsv` now correctly stores `input_tok` and `output_tok` per entry
- **`claudii cost`/`claudii trends`:** `epoch_to_date()` now applies local timezone offset — sessions near midnight no longer land on the wrong day in non-UTC timezones
- **Session Dashboard:** Sessions with `cost=0` in cache now fall back to `history.tsv` lookup — active sessions no longer show missing cost
- **`claudii status`:** Incident update timestamps correctly extracted when `<small>` contains nested `<a>` tags; blank line between updates for readability
- **`claudii cost`:** Session counts now count distinct sessions (not session-day pairs) — multi-day sessions counted once per model
- **`claudii cost`:** False context-reset detection fixed — threshold `cost < prev * 0.5` prevents floating-point noise from triggering spurious resets; Opus overcounting eliminated
- **`claudii cost`:** Week header shows date range `(YYYY-MM-DD – YYYY-MM-DD)` when week spans a month boundary

---

## [0.9.0] — 2026-04-02

### Added
- **Loading animations:** New `lib/spinner.sh` module with three modes — beam (default: `⠋ file.sh ⠹` with 6-phase green L→R gradient), wave (full-width scrolling block-element hill), and ASCII fallback for dumb terminals. Active during `cost`, `se`, and `trends`. Spinner displays the file path currently being processed; each new file gets its own line (scrolling log effect).
- **`claudii cost`:** Model legend at top of output (`(O) Opus 4.6 · (S) Sonnet 4.6`) and per-model cost breakdown in Months and Years sections — Opus costs were previously hidden in totals.
- **`claudii se`:** Dim legend line below the summary explaining `✦ file(N)` (file access count), session-total cost, and 5h/7d API rate limit usage.

### Changed
- **`claudii trends`:** Cost attribution now uses `running_spend` algorithm — multi-day session costs correctly attributed per-day delta, not to the last active day. UTC date consistency: all date boundaries computed in UTC to match `epoch_to_date()` in awk (prevents "today" row disappearing in UTC±N timezones around midnight).
- **Performance:** `claudii trends` aggregation is now O(1) per row; was O(n) `date(1)` subprocesses per row.

### Fixed
- **`claudii cost`:** Multi-day sessions no longer attribute their full cumulative cost to the last active day. Each day now shows only the delta (last cost that day minus last cost the previous day). Backed by `history.tsv` via new `_cmd_cost_from_history()`.
- **`claudii cost`:** BSD awk (macOS) compatibility for leap-year calculation; intra-day reset accounting (context compaction mid-session no longer double-counts cost).

---

## [0.8.1] — 2026-04-01

### Fixed
- **CI/Ubuntu:** `(( var++ ))` when var=0 exits under `set -e` on bash 5.x — all six standalone post-increment counters changed to pre-increment (`++var`)
- **Config:** `_cfgget` now handles hyphenated keys (e.g. `session-dashboard.enabled`) — builds quoted jq path per segment to avoid subtraction ambiguity

---

## [0.8.0] — 2026-04-01

### Added
- `claudii config theme` lists available color themes; `claudii config theme <name>` sets the active theme
- Theme schema in `config/defaults.json`: `theme` (active theme) and `theme_presets` (built-in themes: `default`, `pastel`)
- Theme loading: `_claudii_theme_load` applies color presets from config to `CLAUDII_CLR_*` vars at boot and on config reload
- `theme.name: "auto"` detects light/dark terminal via `$COLORFGBG` / `$TERM_PROGRAM` heuristics

### Changed
- `claudii dashboard` renamed to `claudii session-dashboard`; `dashboard` kept as deprecated alias
- Config key `dashboard.enabled` renamed to `session-dashboard.enabled`; old key still read as migration fallback
- Internal: `_claudii_dashboard` → `_claudii_session_dashboard`, `_CLAUDII_DASH_*` → `_CLAUDII_SDASH_*`
- Session dashboard now renders only after `claudii` commands — suppressed after `ls`, `git`, etc. for less visual noise
- Session dashboard suppression after `se`/`si`/`sessions` now uses `_CLAUDII_SHOWED_SESSIONS` flag instead of command-name matching
- Overview (`claudii`) and dashboard: rate-limit values (5h, 7d) are now color-coded by urgency — green (< 50%), yellow (50–79%), red (≥ 80%)
- Overview: reset countdown colored by urgency — dim (> 60 min), yellow (10–60 min), red (< 10 min)
- Overview: version number, today's cost, and active session bullet use `CLAUDII_CLR_ACCENT` for visual hierarchy
- `claudii config set` now recognizes float values (e.g. `watch.volume 0.5`) and stores them as JSON numbers

### Fixed
- **Security:** `osascript` notification message/title are now escaped before interpolation into AppleScript string
- **Security:** Agent names from config are validated before `eval` in `_claudii_register_agents` — prevents code injection via crafted config
- **Robustness:** All `jq` config writes now use atomic `mktemp` + `mv` pattern — config file can no longer be silently wiped on jq error
- **Robustness:** `_watch_loop` fork now exports all helper function dependencies (`_cfg_init`, `_cfgget`, `_validate_key`) — watch sound config was previously inaccessible in the subprocess
- `claudii trends` awk syntax error (missing `}` in END block)
- Session name in `claudii sessions` / bare `claudii` showing raw sed code from JSONL tool-result transcripts
- `claudii status` now shows per-update timestamps and status (Investigating/Monitoring/Resolved) from incident description when an outage is detected — the `<small>` time was previously not parsed at all; `<var>` tags inside `<small>` are now stripped before extraction
- Rate-limit display (`claudii sessions`) no longer shows `7d:%` when 7d data is absent — each value rendered independently
- `_cmd_search`: actionable error message when configured search directory doesn't exist

---

## [0.7.0] — 2026-03-30

### Added
- Bare `claudii` command shows smart account overview: sessions, account rate limits, agents, services
- `changelog` (shortcut: `about`) shows release notes for the current version from CHANGELOG.md
- `sessions-inactive` (shortcut: `si`) lists only inactive/stale sessions with context bar, cost, and rate-limit info
- `CLAUDII_CLR_ACCENT` constant (magenta 38;5;213m) in `lib/visual.sh`
- Helper functions: `_parse_session_cache`, `_render_ctx_bar`, `_render_age` for consistent session rendering

### Changed
- **Modular architecture:** `bin/claudii` split from 1835-line monolith into thin dispatcher (262 lines) + 4 command modules (`lib/cmd/system.sh`, `lib/cmd/sessions.sh`, `lib/cmd/display.sh`, `lib/cmd/config.sh`) + `lib/trends.awk`
- All raw `\033[` ANSI codes in `bin/claudii` replaced with `CLAUDII_CLR_*`/`CLAUDII_SYM_*` constants from `lib/visual.sh`
- All raw ANSI codes in `lib/functions.zsh` replaced with `CLAUDII_CLR_*` constants
- Sessions section uses ●/○ indicators with 8-block context bar, color-coded by usage
- Services section reflects ClaudeStatus, Dashboard, CC-Statusline, and Watch state

### Removed
- `dash` command (duplicated by `dashboard`)
- Dead command stubs: `show`, `debug`, `stats`, `continue`, `release`, `metrics`, `is`
- `bin/claudii-explore` (replaced by `/explore` skill)

### Refactored
- `_claudii_dashboard` split into `_claudii_collect_sessions`, `_claudii_render_global_line`, `_claudii_render_session_lines` (coordinator now ~30 lines)
- `_claudii_launch` rate-limit warning block extracted into `_claudii_rl_warn`

### Fixed
- **Security:** `printf '%b'` → `%s` in 3 session-rendering calls — prevents escape-sequence injection via JSONL session names
- `_session_name()` sanitizes output: strips non-printable chars, strips literal `\033[...m` sequences, trims to 60 chars
- **ANSI rendering:** `CLAUDII_CLR_*` in `lib/visual.sh`, `lib/log.sh`, `lib/config.zsh` use `$'...'` syntax (real ESC bytes); `printf` uses `%s` for color args
- Dollar sign invisible in dashboard cost display (`%{\$%}` → `'\$` in statusline.zsh)
- Loop variable `i` leaking into terminal after `sessions`/`cost` commands (renamed to `_i`)
- Printf single-quote regression: 38 printf calls with CLR vars in single quotes now use double quotes
- Awk trends colors: pass ANSI codes via `-v` args instead of inline assignments in single-quoted awk
- `local` outside function in `sessions)` block causing crash under `set -euo pipefail`
- `_claudii_agent_launch` reading wrong positional args after premature shift
- Rate limit decimal display in `sessions-inactive` (now integer)
- `clh` swallowing `claudii-status` exit code

### Tests
- 246 tests (was 236): `assert_no_literal_ansi` + `assert_matches` helpers; `assert_contains` → `grep -qF`; ANSI guards for bare claudii/sessions/cost/trends/doctor; session-name injection guard; agents/trends/cost content coverage

---

## [0.6.0] — 2025-11-01

### Added
- `agents` command: lists configured agents (alias→skill→model/effort) or shows onboarding if none configured
- `claudestatus [on|off]` command for toggling the RPROMPT ClaudeStatus layer
- `dashboard [on|off]` command for toggling the above-prompt Dashboard layer
- `cc-statusline [on|off]` replaces `sessionline` (backward-compat shim kept)
- `layers` command replaces `components` (backward-compat shim kept)
- `on` / `off` commands enable/disable all three display layers at once
- Dashboard multi-session view with detail cards, 7d-delta tracking, and toggle
- `dash show` subcommand for detailed session view
- `version` / `about` merged: interactive shows about-style output, piped shows bare version

### Changed
- `release` moved to `scripts/release.sh` (standalone script)
- `debug`, `stats`, `continue`, `explore`, `install-sessionline`, `show` commands removed (redirects added)
- Context bar uses ░ for empty blocks (was space)
- Cost display uses `$` prefix consistently

### Fixed
- Dashboard debug-variable leaks (`i=4`, `cost_fmt=35.59`) in PROMPT_SUBST context
- Dollar sign missing in dashboard cost display
- Stale sessions (empty model) no longer shown in dashboard
- Context bar empty blocks rendering correctly
