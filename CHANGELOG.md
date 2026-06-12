# Changelog

All notable changes to claudii are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

---

## [Unreleased]

### Added
- **Fable 5 recognition** (CC v2.1.170 shipped `claude-fable-5`, Anthropic's new Mythos-class tier above Opus). `_insights_model_label()` (`lib/cmd/insights.sh`) maps `*fable-5*` → `Fable 5` plus a bare `*fable*` tier fallback — previously the raw model ID leaked into the `claudii cache` per-model table. The tier-collapsing AWK in `lib/cmd/cost.sh` / `lib/cmd/display.sh` gained a `Fable` branch (most-capable-first) so cost tiles and trends group Fable sessions under one label instead of per-version IDs. Label asserts added to `tests/test_cache.sh`; the CLAUDE.md model-ship checklist now distinguishes version bumps (no AWK change) from new tiers (AWK branch in both files required).

- **Terminal notifications via hook `terminalSequence`** (CC ≥ 2.1.141). `bin/claudii-stop-hook` now emits `{"terminalSequence": …}` when a monitored model is down (window-title alert, OSC 0) or the cached burn-ETA drops below a threshold (bell + title); the new `bin/claudii-session-end-hook` (wire into `hooks.SessionEnd`) sends a desktop notification with the session cost on real session termination — OSC 777 (Ghostty/urxvt/Warp) or OSC 9 (iTerm2/WezTerm) via `notifications.osc`. All config-gated under the new `notifications.*` block in `config/defaults.json` (master switch default **off**); `config import` accepts the new top-level key. 21 new asserts in `tests/test_notifications.sh`, incl. a `/bin/bash` 3.2 regression pass.
- **Compaction counter segment** (`bin/claudii-cc-statusline`, ccstatusline #282 prior art). No compaction signal exists in the statusline JSON, so the script detects the footprint — context usage collapsing ≥ 30 points from ≥ 50% between renders of the same session — and persists `compactions=` / `last_ctx_pct=` in the per-session cache. New opt-in `compactions` segment renders `♻N` once the session survived at least one compaction ("how many compactions did this session survive?" — pairs with burn-ETA).
- **Context bar is auto-compact aware** (`bin/claudii-cc-statusline`). `context_window.used_percentage` is pre-calculated against the full window, but auto-compact fires well before 100% — the bar under-reported urgency (claude-pace shipped the same fix as their #15). When `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set (inherited from Claude Code), the bar scale derives from it: a value > 1 is treated as a token count (fraction = value / `context_window_size`), a value in (0,1] as the fraction itself, clamped to [50,100]%. Unset or garbage values keep the existing 80% practical-window default — zero behavior change for the common case.

### Changed
- **`skills-cost` aggregates via `claudii-insights merge`** (`lib/cmd/skills-cost.sh`). The command used to read the insights cache files directly with its own jq aggregation and `--days` cutoff — duplicating logic `merge` already owns (a Wave-1 artifact: the merge extension wasn't visible to the implementing agent at spawn time). It now calls the shared `_insights_merged_json` helper and prices the pre-summed attribution block, so cutoff/project filtering stays in one place. Output is unchanged.
- **`release.sh` watches CI by default** (`scripts/release.sh`). The script used to return once the tag was pushed; confirming the GitHub workflow (clean-env tests → Release → tap sync) was a manual step that CLAUDE.md still described as "the script does NOT watch" although a `--watch` flag already existed. Watching is now the default (`--no-watch` opts out for headless runs): the script polls up to 2min for the mirror-triggered run (was 30s — the Forgejo→GitHub mirror regularly needs longer), blocks on `gh run watch`, and exits non-zero with half-release recovery instructions if the workflow fails or never appears.
- **`release.sh` pre-flight validates the CHANGELOG against the version bump.** Two new gates: the `[Unreleased]` block must contain at least one entry (an empty block would tag a release with empty notes), and a block containing `### Added` rejects a PATCH-level version (SemVer: Added → MINOR) unless `--allow-version-mismatch` is passed.
- **Release test pass 2 runs only version-aware tests.** The post-bump pass re-ran the full suite although the bump only rewrites `bin/claudii` VERSION, the man-page version string, and CHANGELOG.md. It now grep-discovers the test files that read those (`VERSION=`/`CHANGELOG`) and runs just them, falling back to the full suite if discovery comes up empty. `tests/run.sh` gained multi-file positional args through the parallel/aggregate path so `--summary` works for subsets (single-file runs previously bypassed aggregation).
- **CHANGELOG hygiene is now tested** (`tests/test_docs.sh`). The unreleased block must not contain duplicate `###` section headers (v0.21.0 shipped with two `### Changed` sections, caught only by hand at release time) and only Keep-a-Changelog section names are allowed.

---

## [v0.21.0] — 2026-06-12

### Added
- **Overview is modular and config-driven** (`lib/cmd/overview.sh`). The bare `claudii` page is now built from section renderers — `account`, `sessions`, `activity`, `agents`, `services`, `commands` — with order and selection controlled by the new `overview.sections` config array (default in `config/defaults.json`; unknown names render an actionable inline warning instead of failing). New `commands` section: grouped quick reference (sessions / cost / activity / display / tools / system) where every listed item is a literal `claudii` subcommand — vibemap, omlx, vpnii, cache, gc, resume are finally discoverable from the overview. `config import` accepts the new `overview` top-level key.

### Changed
- **Overview Agents section grouped by model tier + shell aliases** (`lib/cmd/overview.sh`). The 9-line raw config dump (unsorted, empty skill columns) is now one line per tier (`haiku` / `sonnet` / `opus`, each agent as `name/effort`) plus a `shell` line listing the launcher aliases (`cl`, `clo`, …) that were previously missing entirely; header carries agent/alias counts.
- **Overview Sessions section consolidated** — one count line (`N active session(s) · M inactive · K stale`), cron/bg line, and a dim `→ claudii se · claudii si · claudii gc` hint that only offers commands with something to act on. Command hints across all sections use the `→` prefix and list invocable commands only, never data. Behavior change: the stale count shows whenever stale sessions exist (was: separate hint line only at >5) — it is data now, not a nag.
- **Overview Account 5h reset uses the shared `_fmt_rel` cascade** — `↺4h50m` instead of `↺290m` (urgency color unchanged, still minute-keyed).
- **`claudii help` lists every implemented command** (`bin/claudii`). `vibemap`, `cache`, `omlx`, `vpnii`, `gc`, and `resume` existed in the dispatcher, completions, and man page but were missing from the usage text; new groups "Activity & Insights" and "Config & Integrations". `tests/test_docs.sh` now asserts them in man page + completions + dispatcher.
- **`claudii cost` and `claudii trends` are ~5× faster** (4.1s → 0.8s and 3.9s → 0.7s on a 122k-row history). The shared `epoch_to_date()` awk function looped from 1970 on every call (50+ year iterations + a month-table `split` per history row); a one-slot day-bucket memo removes ~99.9% of that work since rows arrive chronologically. The cost pipeline additionally stops capturing the multi-MB augmented TSV into a shell variable — stage 1 and 2 awk now run as a direct pipe (concurrently). Output verified byte-identical across pretty/`--json`/`--tsv`/trends on a frozen history snapshot.
- **Overview "today" cost now agrees with `claudii cost`** (`lib/cmd/overview.sh`). The bare-`claudii` Account line summed cumulative session-cache cost keyed by file mtime, so a multi-day session's full cost landed in "today" and the two commands showed different numbers. The overview now runs the same per-session increment attribution over the history files that can hold today's rows (legacy `history.tsv` + current month); the session count is distinct SIDs with spend today. The mtime sum remains only as the no-history fallback.
- **`claudii cost` no longer has a session-cache fallback.** The pre-history code path (~150 lines: own accumulator arrays, O(n²) model-index helper, third output layer) only ever ran before the first statusline render created `history-*.tsv`, with known-wrong "today" attribution. First-run now prints an actionable pointer to `claudii cc-statusline on` instead of approximate numbers.
- **`_cfgget` forks jq once per unique key instead of up to twice per call** (`lib/helpers.sh`). Config + slurped defaults resolve in a single invocation (semantics unchanged, explicit `false` still honored), and a per-process memo makes repeated keys fork-free; `_jq_update` clears the memo on every config write so write-then-read in one command never serves a stale value.
- **`claudii se --json` builds its array in one jq call** instead of forking `jq -n` once per session (same output shape).
- **Shared relative-time formatters** (`lib/timefmt.sh`: `_fmt_rel`, `_fmt_brief`). The m / h+m / d+h cascade existed as six hand-rolled copies across `se`, overview, and the sessionline — the same drift class that produced the 0.20 `_fmt_reset` color bug. Visible deltas from unification: sub-minute cron countdowns render `<1m` instead of `0m`, and the overview 7d reset suppresses zero units (`2d0h` → `2d`). New helpers `_midnight_epoch`, `_rate_disp_init`, `_session_files` replace further inline triplets/quadruplets in `lib/helpers.sh` consumers.
- **`lib/cmd/sessions.sh` split** (was 1500+ lines): `claudii cost` lives in `lib/cmd/cost.sh`, the bare-`claudii` overview in `lib/cmd/overview.sh`; `sessions.sh` keeps `se`/`si`/`pin`/`gc` (~570 lines). Pure move plus the changes above.
- **`claudii cost` renders Months and Years as side-by-side tiles.** The Months/Years sections stacked one period per block — wasteful on wide terminals where you want to compare months at a glance. They now lay out as fixed-width tiles, as many per row as `$COLUMNS` allows (`tput cols` fallback, 80 default; capped at 6 to avoid a wall of tiles), separated by a dim vertical `│` rule. Padding is computed from a tracked visible width so ANSI colour codes never throw off column alignment or the vertical separators. Today/Week stay single-column (single periods). The per-period `─── / Total` footer still only shows when a period spans >1 model. Empty model rows (a stray history row with no model field) are now dropped at ingestion, so the legend no longer shows a `()` ghost entry.
- **Overview Activity strip widened from 14 to 43 days.** The mini vibemap strip under the `claudii` overview was held to 14 chars while its own `last … · claudii vibemap strip for detail` caption ran wider — wasted width. It now spans 43 days to fill the caption line.

### Fixed
- **Custom statusLine wrapper chains are recognized — and survive `claudii on`** (`lib/helpers.sh`, `lib/cmd/system.sh`, `lib/cmd/overview.sh`). The earlier `contains("claudii-cc-statusline")` fix only covered commands that name the binary literally; a user wrapper script in between (e.g. `cc-insomnii --after=my-wrap` where `my-wrap` invokes `claudii-cc-statusline`) was reported as "custom configuration" by `claudii cc-statusline`, warned about by `doctor`, shown as off in the overview — and **overwritten** by `claudii on` / `cc-statusline on`. New shared `_cc_statusline_connected()` follows one level of wrapper indirection (resolves each command word, greps the executable for the binary name); all four call sites use it, and `cc-statusline on` keeps a connected custom chain instead of replacing it.
- **Pre-launch rate-limit warning is window-scoped, honors `rate_display`, uses shared time format** (`lib/functions.zsh`). `⚠ Sonnet 5h at 86% Reset in 150min` attributed the account-wide 5h window to whatever model was being launched, printed raw minutes, and showed used% even with `statusline.rate_display=remaining`. Now: `⚠ 5h limit: 14% left · resets in 2h30m` (number follows rate_display, countdown via `_fmt_rel`; color/threshold still keyed on used%). The scan also picks the newest fresh session sample instead of the first in glob order.
- **`claudii status` shows the effective refresh interval, not just the config value** (`lib/cmd/system.sh`). The RPROMPT refresh is adaptive (2× base TTL while healthy, base÷5 min 60s during incidents, base when the API is unreachable — `lib/statusline.zsh`), but the footer always printed the bare config value: "refreshes every 15m" while the healthy-state refresh actually ran at 30m. The footer now mirrors the adaptive logic and prints e.g. "refreshes every 30m (adaptive, base 15m)"; man page documents the ladder.
- **ClaudeStatus cache refreshes from inside Claude Code** (`bin/claudii-cc-statusline`). The status-models cache was only ever refreshed by the zsh precmd — during a long Claude Code session with no shell prompt in between, the sessionline's claude-status segment age grew unbounded (stale health data, `47m`+ badges). The sessionline now spawns `claudii-status --quiet` in the background when the cache is older than `status.cache_ttl` (PID-file dedup, same recycling guard as the zsh spawner; skipped when the layout doesn't render `claude-status`).
- **`_cfgget` no longer swallows boolean `false`** (`lib/helpers.sh`). The lookup used jq's `// empty`, which treats `false` as falsy — an explicit user `false` (e.g. `claudii claudestatus off`) fell through to the defaults' `true`, so `claudii claudestatus`, the overview Services section, and `claudii explain` all reported ClaudeStatus as "on" while config.json said `false`. Replaced with the same type-check `config get` already used.
- **`claudii on` no longer clobbers the cc-insomnii wrapper** (`lib/cmd/system.sh`, `lib/cmd/sessions.sh`). Three places compared `statusLine.command` against the literal `claudii-cc-statusline`, so the wrapper command (`cc-insomnii --after=claudii-cc-statusline`) installed by `cc-statusline on` failed the check: `claudii on` overwrote it with the plain command, the overview showed CC-Statusline as off, and `doctor` warned "other command". All three now match with `contains()`.
- **Rate-limit fallback switch actually switches** (`lib/functions.zsh`). The `[s]` choice in `_claudii_rl_warn` used `local -n` namerefs, which zsh 5.9 (macOS default) does not support — the assignment errored "bad option: -n", the model was silently NOT switched, but the "→ sonnet high" confirmation still printed. Replaced with `eval` on the validated internal varnames. The confirmation line also looked up the literal config key `aliases.model.effort` (the varname, not the alias) — now shows the effort the launch will actually use.
- **Skill-less agents (`hk`, `sn`, `snmax`, `opl`, `opm`, `op`) are now usable** (`lib/functions.zsh`). Registration skipped any agent without a `skill` field, so the shipped worker aliases were advertised by `claudii agents` but never registered (command not found). They now register as plain `claude --model … --effort …` launchers. Related: the registration parser switched from tab to US (0x1F) separators — zsh `read` collapses runs of IFS-whitespace, so an empty skill field shifted every following field and printed "invalid agent effort:" on each shell start.
- **Sessionline reset countdown ≥24h renders dim, not green** (`bin/claudii-cc-statusline`). `_fmt_reset` left `_m` unassigned in the ≥24h branch, so the color ladder's `(( _m < 5 ))` saw 0 and painted multi-day resets green whenever used% was ≥50.
- **`statusline.shame|motivation|rainbow = false` is honored** (`bin/claudii-cc-statusline`). The config read used `// true`, which swallows an explicit `false` (jq falsy) — opting out was impossible. Also, a corrupt config.json made the jq fail and the `read` blanked the pre-seeded `true` defaults, forwarding empty values to cc-insomnii; defaults are now re-applied after the read.
- **`claudii cache --days <garbage>` errors instead of printing "No insight data yet"** (`lib/cmd/insights.sh`). `claudii-insights merge` validates `--days`, but its stderr is swallowed by the caller — the bad value surfaced as a misleading empty-data message. `_cmd_cache` now validates up front, matching `skills-cost`.
- **`claudii si` footer counts match the rendered list** (`lib/cmd/sessions.sh`). The stale/pinned footer re-scanned all files with a bare `kill -0` liveness check while the rows above used the agents-API + 24h-cap logic — the counts could disagree. Counters now increment in the render loop itself (also drops the second pass over the files).
- **Error messages pointed at the wrong GitHub repo** (`lib/cmd/system.sh`). Two `cc-statusline` errors referenced `github.com/bmaingret/claudii`; corrected to `github.com/bmmmm/claudii`. Plus a stale comment in `lib/vpnii.zsh` describing the user-resolution order wrong (it is SUDO_USER → CLAUDII_USER → console owner → $USER).

---

## [v0.20.0] — 2026-06-04

### Added
- **Opus 4.8 recognition.** `_insights_model_label()` (`lib/cmd/insights.sh`) now maps `claude-opus-4-8` → `Opus 4.8` for the `claudii cache` per-model breakdown. Older versions (`Opus 4.7`, `Opus 4.6`, `Sonnet 4.6`) keep their labels so historical data still resolves; `Haiku 4.5` gained a versioned label too. A new sourced-function test in `tests/test_cache.sh` locks the latest + older labels in place. The in-session statusline already shows the model verbatim via `.model.display_name`, and agent aliases stay version-agnostic (`opus`/`sonnet`/`haiku` + effort — Claude Code resolves to the latest), so no config rename is needed. The `orc` agent description now references Opus 4.8.
- **Sessionline highlights the high-end effort modes (`xhigh`, `ultracode`).** Claude Code's effort menu gained `ultracode` (= `xhigh` effort + standing consent to launch multi-agent workflows; it is a menu mode, not an API/CLI effort level). The in-session sessionline rendered `xhigh`/`ultracode` in the dim fallback colour — same weight as `low`/`medium` — which under-represented the most powerful modes. They now render in the accent colour alongside `max`. Handles whatever Claude Code reports as `effort.level` (`ultracode` or the underlying `xhigh`).

### Changed
- **Documented the model-update process.** New "When a new Claude model ships" section in `CLAUDE.md` defines the repeatable checklist (display label + test + agent description + changelog; pricing constants only if rates change) so future model bumps are a mechanical sweep rather than a hunt.
- **Agent + alias effort tiers tuned for Claude 4.8 prompting best practices.** `opm` (multi-file refactor) and `orc` (orchestrator) agents move `medium` → `high` (clears the under-thinking risk 4.8 has at `medium` on intelligence-sensitive work); `op` (foundation/cross-cutting) stays `high` as a compatibility-safe shipped default. The `clm` launch alias moves `max` → `xhigh` — per Anthropic's guidance `xhigh` is the sweet-spot for hard coding/agentic work while `max` tends to overthink with diminishing returns (the `snmax` agent keeps `max` for the single-file Sonnet case). The `CLAUDE.md` subagent guidance gained an effort ladder, an adaptive-thinking note (thinking is self-gated — tune `effort`, don't toggle thinking), and a finding-vs-verification split for review agents (don't tell 4.8 to "be conservative" at the finding stage — it drops real bugs).

- **Extracted `skills-cost` into its own file; added a shared `_mtime` helper.** `_cmd_skills_cost` (~215 lines) moved out of the 1730-line `lib/cmd/sessions.sh` into `lib/cmd/skills-cost.sh` — it reads the *insights* cache, a separate data source from the session-cache commands, so it lives on its own (`sessions.sh` → ~1500 lines). A new `_mtime()` in `lib/helpers.sh` (`stat -f%m \|\| stat -c%Y \|\| echo 0`) replaces the idiom that was inlined ~8× across `lib/cmd/*`; the zsh hot paths keep their `zstat` builtin. The pricing-constants home note in `CLAUDE.md` now points at the new file (and clarifies `claudii cost` reads `costUSD` from history, not these rates).

### Fixed
- **Fewer subprocess forks in the session listing paths.** `_parse_session_cache` (`lib/helpers.sh`, run once per session by `se`/`si`/overview) forked `stat` twice (probe + capture) and `date` once per session; collapsed to a single `_mtime` call plus a hoisted `$_NOW` the callers set once, so an N-session listing no longer forks `2N` stats + `N` dates. The `sessions-inactive` GC footer, the `doctor` stale-session count, and the hourly background session-GC (`claudii.plugin.zsh`) dropped their per-file `grep '^ppid=' \| cut` / `grep -q '^pinned=1'` forks for read-once parameter expansion (matching `_cmd_gc`'s existing style).
- **`_claudii_rl_warn` mtime fallback now handles GNU `stat` (`lib/functions.zsh`).** The non-`zstat` branch ran `stat -f%m … \|\| echo 0` with no `\|\| stat -c%Y` — every other call site has the GNU fallback. On a Linux zsh without the `zsh/stat` module the session mtime silently read `0`; added the fallback to match.
- **`skills-cost` test fixture no longer goes stale.** `tests/test_skills_cost.sh` hardcoded `last_seen:"2026-05-27T12:00:00Z"`; once wall-clock passed that date + 7 days, the `--days 7` cutoff filtered every fixture row out and the command returned before building `.meta`, flipping the `--days`-passthrough assertion (the 30-day-window tests would have followed). `last_seen` is now computed at test load (`date -u`), so the cutoff window always contains the fixture.
- **`trends`/`cost` test fixtures rewritten to the real 9-col history format.** Several fixtures used the obsolete 7-col layout (`sid` in column 4); against the current parser (`sid` in column 6) a token value was read as the session id and `out_tok`/`api_ms` were silently dropped, so the tests passed by column-shift accident (e.g. trends summed 7000 tokens where the data means 30000). Rewrote the stale fixtures to 9-col and added assertions that lock the layout: `trends --json` `this_week_tokens == 30000`, and `cost` multiday now asserts the `--tsv` session count `== 1` + cumulative cost `== 3.00` (the old `assert_not_contains "session"` ran against the *pretty* output, which never prints that word — vacuous). The reset-threshold fixture's `noise-sid`/`reset-sid` are now distinct sessions (they had collapsed to one under the column shift).
- **`vibemap` mini-strip no longer crashes on a cold cache under bash 5.x (Linux/CI).** `_vibemap_mini_strip` declared `local mt now_s` but only assigned `now_s` inside the cache-hit branch; on a cold cache `local now="$now_s"` then tripped `set -u` (bash 5.x → unbound variable), the caller swallowed it with `2>/dev/null` and fell through to the disabled placeholder — so the Activity strip silently never rendered for Linux users (macOS `/bin/bash` 3.2 masked it: `local now_s` is set-empty there). `now` is now computed unconditionally and the mtime read uses `_mtime`. The previously-vacuous test (it grepped the `last 14d` *footer* line for non-emptiness, matching even the disabled placeholder) now asserts a real density char in the Activity block.
- **In-session cost figure renders correctly under comma-decimal locales.** `bin/claudii-cc-statusline` ran `printf '%.2f' "$cost"` without an `LC_NUMERIC=C` guard, so under e.g. `de_DE.UTF-8` every render showed `$0,00` and leaked `printf: 0.55: invalid number` to stderr. Added the guard already used at `lib/cmd/omlx.sh:53`.
- **`claudii update` no longer mis-detects Homebrew on brew-less git installs.** The branch `[[ "$CLAUDII_HOME" == "$(brew --prefix 2>/dev/null)"* ]]` expanded to `""*` (matches every path) when `brew` is absent, routing Linux/source-clone installs into the `brew upgrade` branch (command-not-found). Now guards on `command -v brew` + a non-empty prefix + a `/` separator (with a `set -e`-safe `|| _brew_prefix=""`).
- **`claudii-insights merge --days` validates its argument.** A non-numeric/non-positive value made the `date -v "-${days}d"` cutoff fail → empty cutoff → silently "all sessions". Now rejected with an actionable error and exit 1 *before* the empty-cache early-return (so it fires regardless of cache state). Mirrors the guard already in `lib/cmd/skills-cost.sh`. Regression tests added.
- **`lib/insights.jq` skips valid-but-non-object JSONL lines instead of crashing.** `fromjson?` swallows parse errors but not type errors, so a bare string/number/array line (valid JSON, wrong shape) aborted the whole `reduce` (jq exit 5 → session dropped) — contradicting the docstring's "silently skips malformed lines". Added `| select(type == "object")`. Test extended with non-object fixture lines asserting the real message still aggregates.
- **`claudii config import` rejects a non-object JSON file.** A valid-JSON scalar/array/null passed the unknown-keys check vacuously (`jq 'keys'` errors → empty stdout → `[[ "" -eq 0 ]]` is true) and got installed as live config. Added a `type == "object"` guard right after the JSON-validity check.
- **`claudii-insights` schema-staleness check inspects all caches, not just the first.** `_schema_ok` read only `samples[0]`, so a mixed v2/v3 cache dir (cross-machine `~/.cache` sync, interrupted rebuild) could skip the forced rebuild. Now takes the min `schema_version` across all cache files (streamed, no slurp).
- **`claudii trends` Trend line is gated on ≥30 days of history.** The 7d-vs-30d trend uses a fixed `/30` denominator, so with only a few days of data `avg_7d` (÷7) dwarfed `avg_30d` (÷30) and reported a wildly misleading swing (e.g. `↑+329%`) for what was just a new account. The line is now suppressed until the earliest cost day is ≥30 days back; the Median line (not gated) still shows for sparse history. Test fixture extended to span 30 days; a new test asserts the line stays hidden for sparse data.
- **`claudii trends` computes all date boundaries in one awk pass.** The boundary block forked `date` ~21 times (today, week start, previous full week, 30d-ago, plus two `date` calls per day for the 7-day window) across a macOS/GNU `if/else`. Replaced with a single `BEGIN`-only awk using `epoch_to_date` + a weekday table (`(ld+4)%7`). Bonus correctness: boundaries now use the same fixed `tz_offset` as the data-augment pass, so `d >= week_start` comparisons are internally consistent (previously boundaries were DST-aware via `date` while data days used a fixed offset — they could disagree at a DST edge). New regression test asserts the 7-day weekday names match `date '+%a'`.
- **`claudii se` resolves each session's JSONL in one awk pass.** Per session it called `_session_project_path` (a `grep \| head \| grep \| sed` pipe + a `_session_jsonl` map scan) AND `_session_resolve` (an awk + another map scan over the *same* transcript). Folded the cwd extraction into the `_session_resolve` awk (4th output line) so each session does one map lookup + one file read instead of two of each plus a 4-process pipe — ~5 fewer subprocess spawns per session on the cold `se` path. The now-dead `_session_project_path` helper was removed.
- **`claudii cost` no-history fallback: collapsed double `stat`, documented the approximation.** The per-file mtime read forked `stat` twice (a probe + a capture); collapsed to one `stat -f%m || stat -c%Y || echo 0`. Added a comment that this fallback's per-model "today" is mtime-based (a multi-day session's full cost lands in today) and the history path is the accurate one. Documented the per-session chronological-order invariant the cost-delta math relies on in `trends.awk` and `_collect_history_files` so a future file-merge change can't silently break it.
- **Session dashboard now treats `false`/`0` as disabled, not just `off`.** `_claudii_session_dashboard` only disabled on the literal `off`, so a user setting `session-dashboard.enabled` to the boolean `false` (or `0`) got the dashboard anyway. `off`/`false`/`0` now all disable; `auto` (the default-on sentinel), `on`, and `true` still enable.
- **`claudii skills-cost --days` now validates its argument.** A non-numeric or non-positive `--days` slipped the `[[ "$days" -gt 0 ]] 2>/dev/null` guard and silently became "no cutoff" (all-time), then broke the downstream jq `($d|tonumber)` and `printf "%d"`. It now rejects anything that isn't a positive integer with an actionable error and exit 1. Test added.
- **`claudii trends` dropped a redundant second awk pass + dead code.** Daily API-duration totals were computed in a separate awk pass over the augmented stream (`_daily_api`), serialized to a `|`-joined string, and re-parsed in `trends.awk`'s `BEGIN`. Folded into the main pass (`api_by_day[$1] += $7`) — one fewer subprocess and no serialize/parse round-trip; behaviour identical (augmented rows always have a non-empty sid). Also removed a dead `for (m in …) { _dummy = m }` "force array init" loop and its misleading comment.
- **Anchored session-cache field extraction in the zsh hot path.** `_claudii_rl_warn` (`lib/functions.zsh`) and `_claudii_collect_sessions` ppid read (`lib/statusline.zsh`) used an anchored guard (`*\nkey=*`) but an un-anchored extraction (`${sc#*key=}`), so a field *value* containing `key=` could be mis-parsed. Both now anchor the extraction on a leading newline, matching the style already used for the other fields (and `_claudii_collect_sessions` reuses its single `_sc_nl` build for the ppid read too).
- **`claudii vpnii` hardening.** Home-directory resolution for a non-self `--user` now strips the `NFSHomeDirectory:` label (`sed -n 's/…//p'`) instead of `awk '{print $2}'`, which truncated home paths containing spaces. The root→user `sudo` write path now `chmod 0700`s the state dir to match the direct path (previously only the direct path tightened it). Stale comment about a `stat -f … || -c` fallback (the code branches on `uname -s` now) rewritten.
- **`claudii omlx` cleanups.** `_omlx_test` now wraps its body in a subshell with an `EXIT` trap so the synthetic temp dir is removed even if a command aborts under `set -e` (a function-level `RETURN` trap does not fire on a set-e abort). `_omlx_in_layout`'s presence check `(.statusline.lines // null) != null` is parenthesised — `//` binds looser than `!=`, so the old form collapsed to `… // false` and the `!= null` was dead (behaviour unchanged, intent restored). The oMLX `%.1f GB` probe output is now formatted under `LC_NUMERIC=C` so a comma-decimal locale can't render "1,5 GB".
- **`vibemap` bucketed activity by rolling 24h instead of calendar days.** `vibemap-strip.awk` computed `days_ago = int((now - epoch) / 86400)` — a rolling window from the current moment, not midnight-to-midnight — while its own header comment and the renderer's calendar-date labels assumed local calendar days. A late-evening entry (e.g. 23:30) showed up under "today" until ~24h later and could vanish from the today-row's future-hour blanking. Fix: bucket by local calendar-day number `floor((epoch + tz_offset) / 86400)`, with the signed local UTC offset passed in (new shared `_tz_offset_secs` helper, also now used by `_date_init`). DST transitions can still be off by one for the ~1h around midnight twice a year (documented). Regression test added.
- **Tailscale detection no longer forks `ifconfig` on every prompt.** The VPN RPROMPT segment (`lib/vpnii.zsh`, registered as an unconditional precmd hook for all users) and the in-session statusline (`bin/claudii-cc-statusline`, which builds the segment every render regardless of layout) each ran `ifconfig | grep` to detect a Tailscale CGNAT address — a fork + pipe + grep on every single prompt / render. The up/down result is now cached ~30s in a shared `vpnii-ts` cache file (`<epoch> <0|1>`); on a cache hit the read is a parameter expansion with no fork. Torn/garbage reads fall through to a re-probe. New deterministic test seeds the cache to exercise both the up and down hit paths.
- **Alias launches (`cl`/`clo`/`clm`/`clq`) no longer block on a synchronous status fetch.** With `fallback.enabled` (the shipped default), `_claudii_launch` ran `claudii-status` inline before every launch — a network round-trip (components API + RSS) that blocked the launch up to ~5s on a stale cache and dumped the health line to the terminal each time (`2>&1`). It now reads the `status-models` cache the precmd already keeps warm; if the cache is absent (brand-new shell) it kicks off a background refresh and proceeds with the chosen model. Fallback decisions use at-most-TTL-stale data — a convenience, not a launch gate.
- **`claudii changelog` showed no release notes for any version.** The matcher built a regex `\[VERSION\]` from `VERSION` (`0.19.0`) but CHANGELOG headers are v-prefixed (`## [v0.19.0]`), so it never matched and always printed "No changelog entry for vX". (The unescaped dots were a latent second bug.) Fix: literal-substring match gated on the `## [` header line, accepting both `[VERSION]` and `[vVERSION]`. The existing test passed vacuously because the version number also appears in the printed header — strengthened to assert the notes resolve (no "No changelog entry" fallback).
- **`claudii cost` mis-attributed mixed-model days.** `_cmd_cost_from_history` snapshotted one cost figure per `(session, day)` and credited the whole day's delta to whichever model ran *last* that day (`sid_model[key]` was overwritten per row). A session that ran Opus for the hard work then switched to Sonnet/Haiku for cleanup had its entire day's spend reported under the cleanup model — the per-model breakdown in Today/Week/Months/Years was wrong while only the grand total stayed correct. Fix: attribute each cost *increment* to the model active when it was incurred (per-row delta attribution). Period totals are unchanged (running spend is monotonic, so a day's delta equals the sum of that day's increments); only the per-model split is corrected. Also simplifies the `END` block — the per-session day-sort + day-over-day delta loop is gone. New regression test in `tests/test_cost.sh` (real 9-col history format).

---

## [v0.19.0] — 2026-05-28

### Added
- **`claudii skills-cost [--days N] [--plugins] [--json]`** — per-skill (or per-plugin) cost breakdown from `attribution_skills`/`attribution_plugins` data written by `claudii-insights`. Renders a table with Calls, Tot $, Avg $, Model (`mixed` — attribution spans multiple models in Wave 1), and an outlier flag (`!`) when a skill's average cost is ≥3× the median. `--plugins` switches to plugin attribution; `--json` emits machine-readable rows + meta object. Empty attribution block prints a "no data" hint.

### Changed
- **`claudii agents` now renders a `DESCRIPTION` column** (dim) alongside `ALIAS`/`SKILL`/`MODEL`/`EFFORT`, sourced from `agents.<alias>.description` in the config. TSV / `--json` outputs gained the same field. Terminal-soft-wraps long descriptions — no truncation, since this is meant to be a quick lookup of *why* an alias exists, not just *that* it exists.

### Fixed
- **RPROMPT freezing for the rest of a shell session after a mid-render interrupt.** `_claudii_statusline` set `_CLAUDII_PRECMD_RUNNING=1` before calling `_claudii_statusline_render` and only reset it on the normal exit path — if the render was cut short by a signal (Ctrl-C, `zle reset-prompt` from TRAPWINCH), the guard stayed `1` and every subsequent precmd returned early. The status models, age counter, and incident glyph stuck at whatever value happened to be displayed at interrupt-time. New shells were unaffected because they reinitialised the flag. Fix: guard now stores the start epoch instead of `1`, treats a flag older than 5s as stuck (auto-recovers without manual unset), and the cleanup runs in a zsh `{ … } always { … }` block so non-normal exits still clear it.

### Added
- **`vibemap.overview` config flag (default `true`) to hide the Activity strip in the bare `claudii` overview.** Set `claudii config set vibemap.overview false` to suppress the section entirely — when off, the mini-strip aggregation is also skipped so the overview no longer pays the ~20–60ms cost. Toggling does not affect data collection (controlled by `vibemap.enabled`) or the `claudii vibemap` / `vibemap strip` views.
- **`opm` agent (`opus`/`medium`)** in `config/defaults.json` for multi-file refactors with cross-file reasoning and ecosystem analysis — the slot between `opl` (review/arch) and `op` (foundation/cross-cutting) where Opus 4.7's reasoning earns its keep without going to high effort.

### Changed
- **`claudii vibemap` (grid view): drop pink data cells, fix header alignment.** Today's data column kept the normal density coloring (or bedtime-red); only the `▶Wed` header marker stays accent. Header slots were 7 cols wide while data cells were 5, shifting today's column under yesterday's label — now both 5 cols, with header leading reduced from 9 to 8 spaces to align with the bin-label prefix.
- **`claudii` overview Activity strip cached for 60s.** The mini-strip output (`~/.cache/claudii/vibemap-mini.cache`) is reused for up to a minute, cutting the warm-cache `_vibemap_mini_strip` call from ~67ms to ~19ms. Cache is dropped by `claudii vibemap clear`. Density chars are normalized to max, so single new entries don't shift the visible output — 60s feels live.
- **Agent tier shift for Opus 4.7.** `orc` (the orchestrator agent that drives `/orchestrate`) moves from `sonnet`/`high` to `opus`/`medium` — Opus 4.7's stabler long-tool-chain behaviour pays off when the orchestrator is coordinating multiple subagents over many edits, scope checks, and merges. The remaining agent descriptions in `defaults.json` are sharpened to match the new boundaries (Sonnet = clear-scope single-file, Opus medium+ = cross-file reasoning). The `/orchestrate` skill frontmatter (both global and the claudii override under `.claude/skills/orchestrate/`) follows: `model: opus, effort: medium`. No CLI flags change; users running `claudii orc` get the new model automatically. The matching tier hierarchy and "which model" decision table in `~/.claude/CLAUDE.md` are updated separately in the dotfiles repo.

---

## [v0.18.6] — 2026-05-20

### Added
- **`cron` sessionline segment + `claudii se` glyph from Stop-hook `session_crons`.** A new `bin/claudii-stop-hook` script reads the Stop/SubagentStop hook JSON, picks the earliest `next_run_at` from `session_crons`, and writes `next_cron_at=<epoch>` into the per-session cache (read-modify-write, preserving all other keys). The in-session `cron` segment renders `⏰ <relative>` (e.g. `⏰ 42m`) when the epoch is in the future; omitted when absent or past. `claudii se` shows the same glyph inline after the pace glyph. Symbol constant `CLAUDII_SYM_CRON` added to `lib/visual.sh`. Wire by adding `claudii-stop-hook` to `hooks.Stop` in `~/.claude/settings.json`. **Not in the default layout** — add `cron` to `statusline.lines` to opt in.
- **Pace-indicator tri-state in the in-session sessionline and `claudii se`.** Derived from the existing `_burn_eta` computation: a perfectly linear user hits 100% at exactly the 5-hour mark; actual `rate_5h` is compared to that baseline. Below 85% of linear → `↑` (green, ahead); 85%–115% → `=` (dim, on-pace); above 115% → `↓` (yellow, behind). The computed state is persisted as `pace=ahead|on_pace|behind` in the per-session cache alongside `burn_eta=`. The new `pace` segment in `bin/claudii-cc-statusline` renders the glyph only (no label — glyph color is the signal). `claudii se` appends the glyph after the 5h-rate column for each session row. Symbol constants `CLAUDII_SYM_PACE_AHEAD`, `CLAUDII_SYM_PACE_ON`, `CLAUDII_SYM_PACE_BEHIND` added to `lib/visual.sh`. **Not in the default layout** — add `pace` to `statusline.lines` to opt in.
- **`[N bg]` badge in `claudii se` + `bg-tasks` sessionline segment + cron-summary line in bare overview.** `bin/claudii-stop-hook` already writes `bg_tasks=<count>` (length of `background_tasks` array) into the per-session cache; `_parse_session_cache` now reads it into `_PSC_bg_tasks`. `claudii se` Line 1 appends a dim `[2 bg]` badge after the model name when bg_tasks ≥ 1 (distinct signal from the `[bg]` background-kind badge shipped in v0.18.3). The bare `claudii` overview Sessions block adds one dim line `⏰ next wake in 1h · 2 bg task(s)` summarising the earliest future cron across all cached sessions plus the total bg-task count (omitted when neither applies). New opt-in `bg-tasks` CC-Statusline segment renders `⚙ Nbg`. Symbol constant `CLAUDII_SYM_BG="⚙"` added to `lib/visual.sh`. Tests in `tests/test_sessionline.sh` and `tests/test_cli.sh`.

### Fixed
- **Bare `claudii` (Overview) was up to 5x slower than necessary when orphan atomic-write artifacts accumulated in the cache.** `bin/claudii-cc-statusline` and `bin/claudii-stop-hook` write via `session-<sid>.tmp.$$` then `mv -f`; if a writer is killed between the write and the rename, the `.tmp.PID` file is left behind. The session-* glob in `_cmd_default`, `_cmd_sessions`, `_cmd_sessions_inactive`, `_cmd_pin/unpin`, `_cmd_cost`, `_cmd_doctor`'s GC counter, `lib/cmd/display.sh`'s SessionBar counter, `lib/statusline.zsh`, and `lib/functions.zsh` all parsed these artifacts as if they were real sessions. Now every loop drops `*.tmp.*` entries up front. **`claudii gc` also sweeps orphan `*.tmp.*` files older than 60s** so accumulated leftovers are cleaned up.
- **Calendar-midnight cutoff in `_cmd_default` and `_cmd_cost` resolved to *now* instead of midnight on macOS.** BSD `date -j -f '%Y-%m-%d' '2026-05-20' '+%s'` keeps the *current* hour/minute/second when the format has no time component, so the cutoff equalled `now` and only files modified within the same second qualified for the today-cost / today-count blocks (gotcha #19 in memory documents the symptom; this was the upstream cause). Fix: pass `00:00:00` explicitly via `-f '%Y-%m-%d %H:%M:%S'`. The GNU `date -d` Linux fallback was already correct.

### Changed
- **`claudii vibemap` (grid view): today's weekday column now highlighted in accent pink.** The column header gains a `▶` prefix; every cell in that column is rendered in `CLAUDII_CLR_ACCENT` (pink) instead of plain white, making the current weekday visually obvious at a glance. The legend updates to `▶ = today`. Column alignment preserved — `▶` replaces one space, so the slot stays 5 columns wide.
- **`claudii` overview Activity strip: today's density char rendered in accent pink.** The rightmost character of the 14-day mini-strip (= today) is now wrapped in `CLAUDII_CLR_ACCENT`, matching the today-marker idiom from `claudii vibemap strip`. Logical 14-char length unchanged — ANSI escapes are invisible to terminal width.

---

## [v0.18.5] — 2026-05-20

### Added
- **`● Activity` segment in the bare `claudii` overview.** A 14-character strip showing prompt-activity density per day for the last two weeks (rightmost = today), rendered with the same `░ ▒ ▓ █` glyphs as `claudii vibemap`. Appears only when `vibemap.enabled=true` and at least one row exists; otherwise the dim placeholder line `○ Activity   claudii config set vibemap.enabled true` shows up so the feature is discoverable. Sits between Services and Sessions in the overview.

### Changed
- **`claudii vibemap strip`: today now visually stands apart from yesterday and the future.** The today-row's label and a new `▶` marker render in accent pink; a thin `│` cursor replaces the current-hour density char so "now" is locatable at a glance; all strictly-future hours of today are blanked out (was: indistinguishable from past hours). Past days render unchanged. Same 24-column alignment — the cursor swaps in 1:1 for the would-be density char, no width drift.
- **`man claudii` rewritten for scannability.** 1366 → 483 lines (513 rendered). EXAMPLES moved from the bottom to right after SYNOPSIS so usage is the first thing you see. Sections reorganized around user tasks (LAUNCHING CLAUDE / DISPLAY LAYERS / COMMANDS / CC-STATUSLINE SEGMENTS / CONFIGURATION) instead of feature-by-feature. The 16 per-segment expansion blocks below the segment table were collapsed into three short paragraphs covering the non-obvious bits (color thresholds, `rate_display` flip, clock delegation) — the table itself stays as the scannable index. CONFIGURATION switched from prose to a three-column table. Three-times-repeated rate-limit colour thresholds collapsed into one canonical location. No commands or segments dropped — `tests/test_docs.sh` still enforces the full list.

---

## [v0.18.4] — 2026-05-20

### Added
- **`github` sessionline segment surfaces `workspace.repo.{owner,name,pr_number}`.** Claude Code 2.1.145+ now ships repo identity and active-PR number in the statusLine JSON stdin. The new `github` segment renders `◆ <owner>/<name>` (dim) with `#<pr_number>` (yellow) appended when the API includes one — gives an at-a-glance PR pin without a `gh` subshell or a custom git script. Defensive: segment is omitted when either `owner` or `name` is missing (non-git project, no remote). Symbol constant `CLAUDII_SYM_REPO` added to `lib/visual.sh`. Not in the default layout — add `github` to `statusline.lines` in `~/.config/claudii/config.json` to enable. Tests cover full repo+PR, repo-without-PR, missing repo, and the owner-only malformed case in `tests/test_sessionline.sh`; `tests/test_docs.sh` enforces man-page sync.

### Security
- **Defense-in-depth hardening across three small surfaces.** `bin/claudii-cc-statusline` sets `umask 077` right after creating its 0700 cache dir, so the per-session cache files (`session-<sid>`, monthly `history-*.tsv`, the `*.tmp.$$` staging files) inherit 0600 instead of the umask-022 default 0644 — matters only if `CLAUDII_CACHE_DIR` is ever pointed outside the already-mode-700 default dir, but it's a one-line safety net. `bin/claudii-status` switches the incident-banner line (the `↳ $incident_detail` from `status.claude.com`) from `echo -e` to `printf '%s'`, so a feed that ever delivered a literal `\033`/`\n` in a title can no longer inject escape sequences into the terminal output. `.github/workflows/release.yml` tightens the tarball-SHA step from `curl -sL` to `curl -fsSL --max-time 60 --max-filesize 52428800`, so a hostile mirror can't stream an arbitrarily large body into the runner or have its 404 page hashed as a "release."

---

## [v0.18.3] — 2026-05-20

### Added
- **`claude agents --json` adapter for session liveness.** `lib/helpers.sh` gains `_live_pids_init` / `_pid_is_live` / `_pid_kind`, called once per command run by `_cmd_sessions`, `_cmd_sessions_inactive`, and `_cmd_default`. When `claude agents --json` (Claude Code ≥ 2.1.145) lists a session's `ppid`, that result is authoritative and also surfaces the `kind`. The legacy `kill -0` + 24h-age guard remains as a fallback for interactive sessions (which the API deliberately omits) and for hosts without the new `claude` binary. New `tests/test_agents_adapter.sh` covers populated/empty/garbage/no-binary paths plus an end-to-end smoketest against `bin/claudii`.
- **Background sessions marked with `[bg]` in `claudii se`.** When `claude agents --json` reports a session as `kind=background`, the rendered model line carries a dim `[bg]` badge after the model name. Interactive sessions render unchanged.

---

## [v0.18.2] — 2026-05-20

### Changed
- **Refactor: `bin/claudii` slims from 473 → 170 lines.** The 15 shared helper functions (`_collect_history_files`, `_date_init`, `_spinner_start/_stop`, `_session_build_map/_jsonl/_project_path/_resolve`, `_jq_update`, `_cfg_init`, `_validate_key`, `_cfgget`, `_parse_session_cache`, `_render_ctx_bar`, `_render_age`, `_plain`) move into the new `lib/helpers.sh` and are sourced after `visual.sh` / `spinner.sh`. The dispatcher is now back under the 300-line budget, command logic stays in `lib/cmd/*.sh`, helpers are reusable from any sourced file. No behavior change — all 683 tests pass.
- **Refactor: consolidated ANSI constants on `CLAUDII_CLR_*`.** `lib/cmd/vibemap.sh` dropped its two `local DIM RED RST` blocks (~4 lines of raw escapes per render function) and now uses `CLAUDII_CLR_DIM` / `CLAUDII_CLR_RED` / `CLAUDII_CLR_RESET` from `visual.sh`, which is already in scope. `bin/claudii-status` now sources `lib/visual.sh` directly and uses `CLAUDII_CLR_RED` / `CLAUDII_CLR_YELLOW` / `CLAUDII_CLR_RESET` instead of its own raw `RED='\033[0;31m'` triplet. `lib/cmd/omlx.sh` gained a one-line header note documenting the implicit `visual.sh` dependency. **User-visible effect:** themes that override colors (via `theme.name` in config) now reach the heatmap and the `claudii-status` output too, which previously stayed at hardcoded red/yellow regardless of theme.

---

## [v0.18.1] — 2026-05-20

### Fixed
- **Bash 3.2 incompatibility (macOS `/bin/bash`) — claude-status segment rendered all three models as "Haiku ✓ Haiku ✓ Haiku ✓"** instead of `Opus ✓ Sonnet ✓ Haiku ✓`. `bin/claudii-cc-statusline` used `declare -A _sc_lbls=([opus]=Opus [sonnet]=Sonnet [haiku]=Haiku)`. Bash 3.2 silently falls back to a regular indexed array, evaluates the string keys in arithmetic context (`opus` → 0, `sonnet` → 0, `haiku` → 0), and all three assignments overwrite `arr[0]` — last one wins. Tests didn't catch it because the test runner invokes the script via `bash` (PATH-resolved Homebrew bash 5.x), not the `/bin/bash` shebang. Replaced with an inline `case` statement.
- **Bash 3.2 incompatibility in `claudii vibemap` (grid + strip).** Same root cause — `declare -A counts` with `counts[$wd,$b]` keys was a no-op on macOS `/bin/bash`. Both views now use flat scalars (`_c_<wd>_<bin>=count` via `printf -v`) with a numeric-key guard so a stray corrupted row in `vibemap.tsv` skips that cell instead of failing the render.
- **Regression test** in `tests/test_sessionline.sh` now invokes `/bin/bash` explicitly and asserts Opus + Sonnet + Haiku each appear exactly once in the claude-status output.

---

## [v0.18.0] — 2026-05-14

### Added
- **`claudii cc-statusline on` now picks the wrapper command when cc-insomnii is present.** Detects `cc-insomnii` on PATH and `statusline.insomnii != "off"`, then writes `cc-insomnii --after=claudii-cc-statusline` into `~/.claude/settings.json` instead of plain `claudii-cc-statusline`. Result: cc-insomnii always owns the first line of the in-session statusline (its own visual identity — glyph + bedtime phrase), with the claudii layout rendered directly below. `claudii cc-statusline` (status) labels the active mode (`cc-insomnii wrapper` vs `plain — no insomnii wrapper`). `bin/claudii-cc-statusline` adds a parent-process guard (`PPID` → `ps -o comm=`): when invoked via the wrapper, the `clock` segment in custom layouts becomes a no-op so users with `clock` in their hand-edited `statusline.lines` don't get the insomnii line rendered twice.
- **`claudii cc-statusline preset [focused|calm|default]`**: named layout presets for the in-session statusline. `focused` is a dense 3-line layout (model + dir / context-bar + rate-5h + rate-7d / claude-status + vpn) — cc-insomnii (when installed) prepends its own line via the wrapper, so the layout is intentionally insomnii-free for users who want everything important without scrolling past noise. `calm` is the opposite extreme — a bare 2-line layout with just the model name (effort + thinking arrow included) on top and the context-bar below, nothing else, pure calmness. `default` restores the shipped 5-line layout. `claudii cc-statusline preset` (no args) lists what's available. Writes directly to `.statusline.lines` in `~/.config/claudii/config.json`, so hand-edits afterwards are preserved.
- **`claudii insomnii [on|off|auto|status|install]` subcommand**: control the [cc-insomnii](https://github.com/bmmmm/cc-insomnii) delegation without leaving claudii. `claudii insomnii` (no args) shows binary path, current delegation mode, and the forwarded bedtime; `on/off/auto` write `.statusline.insomnii` to config; `install` clones `$CC_INSOMNII_REPO` (default `https://github.com/bmmmm/cc-insomnii`) into `$CC_INSOMNII_CLONE_DIR` (default `~/.local/share/cc-insomnii-src`) and runs its `install.sh` — idempotent, re-running upgrades from latest checkout. The `claudii help` listing now includes a hint for the new subcommand.
- **cc-insomnii integration (full migration)**: clock segment rendering — the bedtime nudge, shame escalation, motivation tagline, rainbow chase, glyph swarm, the entire animated bedtime-shaming UX — has been extracted into a standalone repo at [github.com/bmmmm/cc-insomnii](https://github.com/bmmmm/cc-insomnii) and is now invoked from claudii via stdin pipe. New config key `statusline.insomnii` controls delegation: `auto` (default, use if installed), `off` (suppress entirely), `on` (require, warn via `claudii doctor` if missing). `statusline.bedtime` is forwarded as `CC_INSOMNII_BEDTIME`; legacy `statusline.shame`/`motivation`/`rainbow` keys still forward as the matching `CC_INSOMNII_*` env vars so users with those keys in their config keep working without changes. `claudii doctor` now reports detection status, install path, and active mode.

### Changed (BREAKING)
- **Rebrand: external binary `insomnii` → `cc-insomnii`**: claudii now detects and invokes `cc-insomnii` instead of `insomnii`. All env vars forwarded to the binary have been renamed (`INSOMNII_BEDTIME` → `CC_INSOMNII_BEDTIME`, `INSOMNII_SHAME` → `CC_INSOMNII_SHAME`, `INSOMNII_MOTIVATION` → `CC_INSOMNII_MOTIVATION`, `INSOMNII_RAINBOW` → `CC_INSOMNII_RAINBOW`). The install env vars are also renamed: `INSOMNII_REPO` → `CC_INSOMNII_REPO` (default `https://github.com/bmmmm/cc-insomnii`), `INSOMNII_CLONE_DIR` → `CC_INSOMNII_CLONE_DIR` (default `~/.local/share/cc-insomnii-src`). No old names are forwarded — hard cut. The `claudii insomnii` subcommand, `statusline.insomnii` config key, and all claudii-internal namespacing are unchanged.

### Removed (BREAKING)
- **Inline bedtime/shame/motivation/rainbow rendering removed from `bin/claudii-cc-statusline`** (~140 lines of vibe-coma logic, 4 escalation modes, glyph rotation, color-pair table, REVERSE/BLINK/UNDERLINE constants). The `clock` layout segment now produces output ONLY when [cc-insomnii](https://github.com/bmmmm/cc-insomnii) is installed — without it the segment is empty and the layout silently skips it. Migration: `brew install bmmmm/tap/cc-insomnii` (or clone + `bash install.sh` from the repo). cc-insomnii ships a much expanded message catalog (461 strings vs the previous 124, 6 escalation modes vs 4, plus new `dawn` and pre-bedtime warning modes) and adds breathing-pulse, char-decay, matrix-rain-drip, and glyph-swarm animations.
- **`claudii shame [on|off]`, `claudii motivation [on|off]`, `claudii rainbow [on|off]` subcommands removed.** The underlying config keys (`statusline.shame`, `.motivation`, `.rainbow`) still get forwarded to cc-insomnii as env vars when present, so users who already have them set in `~/.config/claudii/config.json` need no changes. To toggle going forward, set `CC_INSOMNII_*` env vars or edit `~/.config/cc-insomnii/config.json` directly. The `bedtime` key stays — it's still claudii's setting, used by both the cc-insomnii forwarding and the vibemap heatmap.
- **`config/shame-messages.json` deleted.** The shipped message catalog moved to cc-insomnii (and grew to ~3.7× the size).
- **`claudii cache`**: prompt-cache hit rate visualization. Per-day bars (rolling 7-day window, override with `--days N`), per-model bars, and a one-line summary of total tokens served from cache. Cache hit rate is the only cost lever the user directly controls — bouncing between projects and short sessions kills it, long focused sessions push it past 95% — so this view makes that tradeoff visible. Backed by a new `bin/claudii-insights` aggregator (bash + jq, no new dependencies) that walks every JSONL transcript under `~/.claude/projects/*/`, distills per-day/per-model token counts into one JSON file per session at `~/.cache/claudii/insights/<sid>.json`, and uses an mtime marker (`.last-scan`) to skip the unchanged majority on subsequent runs. First run for a fresh cache: ~10 s for ~400 sessions/270 MB. Steady state: <200 ms. Malformed JSONL lines are silently skipped (`fromjson? // empty`) so a single corrupt session doesn't take down the whole aggregation.

### Changed
- **Release flow: tap sync moves from `scripts/release.sh` into `.github/workflows/release.yml`**. The script now does just pre-flight + tests + version bump + tag push, then exits — CI runs tests on a clean Ubuntu env, builds release notes, computes the tarball SHA256, creates the GitHub Release, and PUTs the new Formula into `bmmmm/homebrew-tap`. Previously the script did all of this inline, which meant a single sandbox/TLS hiccup on the local box would silently abort the tap sync with a misleading "Formula not found" error. Tap update now needs a fine-grained PAT with `contents:write` on the tap repo, stored as `secrets.TAP_TOKEN` on the claudii repo — if missing, the workflow logs a warning and skips that step (Formula stays at the previous version, human updates manually).
- **Tests run BEFORE the version bump**, not after — eliminates the `git checkout --` rollback path. If tests fail, no files were ever mutated.
- **`scripts/release.sh --watch`** new flag: blocks on `gh run watch <id>` and exits non-zero if the workflow fails. Default (no flag) returns immediately after tag push so you can keep working.
- **Polling logic gone**: the old "wait up to 300s for the workflow run, match by `head_sha`" loop is replaced by `gh run watch`. Native, exits the moment the run completes, no false-positive timeouts.

---

## [v0.17.0] — 2026-05-08

### Added
- **`claudii vibemap`** (opt-in activity heatmap): logs one TSV line per cc-statusline render to `~/.cache/claudii/vibemap.tsv` (default off — set `vibemap.enabled=true` to start tracking), then renders ASCII heatmaps over the data. Two views: `claudii vibemap` shows a weekday × 3-hour-bin grid (Mon–Sun × 00-03..21-00), `claudii vibemap strip [--days N]` shows the last N days × 24 hours per row. Both color the bedtime window in red so overdue vibing patterns surface visually. Plus `vibemap status` (enabled/path/entry-count/oldest-entry), `vibemap path`, and `vibemap clear` for full lifecycle control. Schema: `epoch \t weekday \t hour \t minute \t model \t sid8 \t delta_ms` — local-only, never transmitted, no prompt content stored. Aggregation done in pure awk (`lib/vibemap-{grid,strip}.awk`), presentation in `lib/cmd/vibemap.sh`, logging hook in `lib/vibemap.sh` (used by both the CLI and the cc-statusline append path).
- **`clock` segment with bedtime nudge**: Renders local wall-clock time + a glyph that escalates as bedtime approaches and passes — `☾ 22:14` dim, → cyan 30 min out, → yellow at 10 min out, → blinking red `☾ 23:30 +30m` once past, → vibe-coma (per-character synthwave rainbow + rotating glyph from `💤 🌙 🦉 ✨ 🌌` + blink + a randomly-rotating shame string like `GO TO BED` / `TOUCH GRASS` / `FUTURE YOU SAYS NO`, all reshuffled every render) after the 1-hour overdue mark. Wrap-aware across midnight. Configurable via `statusline.bedtime` (HH:MM, default `23:00`). Add it to your `statusline.lines` layout to show.
- **`claudii vpnii set/clear/show`**: Wraps the WireGuard state-file write that wg-quick PostUp/PreDown hooks trigger. The CLI drops privilege from root to the real user (resolved via `SUDO_USER` → `/dev/console` owner → `$USER`, override with `--user <name>` or `CLAUDII_USER`), so `~/.cache/claudii/vpnii` is always owned by you — no more sudo to clean up after a missed PreDown. New wg conf shape: `PostUp = claudii vpnii set HomeLab` / `PreDown = claudii vpnii clear`. Old direct-write recipes still work but produce root-owned files.
- **Tailscale detection in cc-statusline + RPROMPT VPN segment**: Single `ifconfig` scan for an IPv4 in 100.64.0.0/10 (RFC 6598 CGNAT, Tailscale's range) — no daemon dependency, no `tailscale` CLI call. Renders `⬢ ts` next to the existing `⬡ <wg-tunnel>` when both are active. Both surfaces (cc-statusline and the zsh RPROMPT via `lib/vpnii.zsh`) use the same compact format. New symbol `CLAUDII_SYM_TAILSCALE="⬢"` in `lib/visual.sh`.
- **Incident age + bracket grouping in cc-statusline**: Model glyphs are now wrapped in `[…]` with the cache-mtime age and incident flag trailing outside, matching the RPROMPT format: `[Opus ✓ Sonnet ✓ Haiku ✓] 7m ⚐`. Without an active incident the brackets and trailing segment are omitted, preserving the bare `Opus ✓ Sonnet ✓ Haiku ✓` look. `bin/claudii-status` also persists `_incident_started=<epoch>` to the cache for downstream consumers.
- **Inverted rate display (`statusline.rate_display`)**: New config key — set to `remaining` to flip rate-5h / rate-7d from "used %" to "remaining %" (e.g. `5h:62%` becomes `5h↓:38%`). Session deltas flip sign too: `Δ5h:+12%` (used grew) becomes `Δ5h:−12%` (remaining shrank). The `↓` marker on the label distinguishes the modes at a glance (default `used` stays unmarked). The flip applies across cc-statusline, the precmd session dashboard, the `claudii` overview Account block, and `claudii se` rows. Colors and reset-countdown thresholds key off the underlying usage in both modes — "close to limit" still renders red whether shown as 86% used or 14% remaining.
- **Rate-limit color: green at low usage**: `_rlc` now uses green (`\033[32m`) instead of cyan (`\033[36m`) for the < 50% bucket. In remaining mode "97% remaining" reads as cyan was unintuitive — green matches the "lots of headroom" semantics cleanly. Also affects used mode, where low usage now reads green.

### Fixed
- **Rate-limit reset countdown format consistency**: The 5h reset always rendered in minutes (`↺79m`, `↺240m`) while 7d switched to hours (`↺1h`, `↺2d4h`). Both now use the same formatter: `Xm` < 60 minutes, `XhYm` (or `Xh` when minutes are zero) for 1–24 h, `XdYh` (or `Xd`) for 24 h+. So 79 minutes shows as `↺1h19m` for both windows instead of differing per limit.
- **Overview no longer aborts after Account header in `rate_display=remaining` mode**: `_cmd_default` built the 7d delta segment with `_ov_acct_line+=" (… $( (( _ov_delta_disp > 0 )) && echo "+" )${_ov_delta_disp}% …)"`. When `statusline.rate_display="remaining"` and the 7d rate had grown since the session started, the displayed delta got negated (`+3%` → `-3%`), the inline `(( ... ))` test failed, and its non-zero exit propagated through the `+=` assignment. `bin/claudii`'s `set -euo pipefail` then aborted the whole function right after the `● Account` header — Agents, Services, and Sessions blocks silently disappeared. Sign computation now runs in conditional context (`(( ... )) && _ov_sign="+"`) so the failing arithmetic test stays exempt from errexit. Regression test in `tests/test_cli.sh` covers the exact data shape (`remaining` mode + positive 7d delta with a live session).
- **Status check no longer flags all models for non-model incidents**: `bin/claudii-status` previously fell back to "mark every model as down" whenever the incident name didn't mention a model — which fired on incidents that have nothing to do with model availability (e.g. "Connection failures for organizations restricting GitHub access by IP address"). The cc-statusline rendered `Opus ↓ Sonnet ↓ Haiku ↓` and the launcher silently fell back from `clm` → sonnet. Parser now searches `name + incident_updates[].body + components[].name`; only flags models found there, plus a narrow safety net that flags all models when `components` lists the bare `API` entry (genuine inference outage). For everything else, `_incident=<status>` still gets persisted so the indicator (`⚐ Identified`, `‼ Investigating`, `◎ Monitoring`) still shows — only the per-model `↓` no longer lies.

### Refactored
- **Sessionline config read moved to top of script**: The four `statusline.*` keys (`lines`, `models`, `omlx_active_path`, `rate_display`) are now read in one `jq` call right after the cache-dir setup, before any segment processing. Lets later code (e.g. rate inversion) consume the config without forking a second `jq`.

### Removed
- **Local `Formula/claudii.rb`**: The local Formula was a duplicate of the one in `bmmmm/homebrew-tap`, kept solely so CI could run `brew audit --formula Formula/claudii.rb`. After the v0.16.0 drift incident the costs of that duplication outweighed the audit. The tap is now the single source of truth; `scripts/release.sh` updates it via the GitHub contents API at release time. The CI `brew audit` step is gone.

### Release pipeline
- **`scripts/release.sh` polling**: `_head=$(git rev-parse HEAD)` was captured AFTER the local Formula sync commit, so the workflow `head_sha` filter never matched. Replaced with `_tag_sha`, captured immediately after `git push origin <tag>`. The post-tag local commit no longer exists (Formula gone) but the fix stays for robustness.
- **Release notes extraction**: `release.yml` matched `## [${VERSION}]` (no v) but CHANGELOG headers carry the v-prefix (`## [v0.16.0]`). Awk now matches both forms.

---

## [v0.16.0] — 2026-05-06

### Added
- **`claudii omlx [status|connect|test|disconnect]`**: New top-level command for wiring up the [gateii](https://github.com/bmmmm/gateii) local-LLM agent layer to claudii's cc-statusline. `connect` detects the gateii data path (or stores a custom one via `statusline.omlx_active_path`), confirms the omlx segment is in the layout, and probes the oMLX server. `test` renders a synthetic `⚡ <task> <model> <Xs>` line for previewing. `disconnect` removes the segment from custom layouts.
- **Sessionline `omlx` segment**: New segment that reads gateii's `data/agents/active.json` (or env override `CLAUDII_OMLX_ACTIVE` / config `.statusline.omlx_active_path`) and renders `⚡ <task> <model-short> <Xs>` while a local omlx-backed agent is running. Empty (and the line is silently dropped) when no agent is active or gateii is not installed — zero impact for users without gateii.
- **Sessionline default layout: `omlx` line**: `_DEFAULT_LINES` (and `config/defaults.json`) now include `["omlx"]` as the 5th line. Users on the built-in default layout get the indicator automatically; users with a custom `.statusline.lines` need to add `["omlx"]` themselves or run `claudii omlx connect`.
- **Sessionline `effort.level` from JSON**: Model segment now reads reasoning effort from `effort.level` in the CC statusLine stdin JSON (available since CC v2.1.119), replacing the `CLAUDII_EFFORT` environment-variable workaround.
- **Sessionline thinking indicator**: When `thinking.enabled` is `true` in the statusLine JSON, a `▲` indicator is appended to the model segment.
- **Sessionline `workspace.git_worktree` fallback**: The `worktree` segment now falls back to `workspace.git_worktree` so it fires inside any linked git worktree, not just `--worktree` sessions.
- **Sessionline `dir` segment**: New segment showing `⌂ <dirname>` (dim text). Sources `worktree.original_cwd` in `--worktree` sessions, otherwise `workspace.project_dir`, with `workspace.current_dir` as last fallback. Added to default layout (line 3, after `worktree`).
- **Sessionline effort level coloring**: `effort.level` is now always displayed next to the model name, colored by tier — `max` in accent (pink), `high` in yellow, `medium`/`low` dim. Previously hidden when `high`.
- **Sessionline thinking indicator color**: The `▲` thinking indicator is now cyan instead of dim for better visibility.
- **Sessionline dir segment**: Directory name now rendered in yellow; prefix symbol `⌂` stays dim.
- **Spinner mode dispatch + 5 new modes**: `_spinner_start` resolves the mode once from env `CLAUDII_SPINNER_MODE` or config `ui.spinner` (default `random`) and exports it, so the spinner loop never spawns jq. New modes: `dots` (cyan braille rotation), `pulse` (gray brightness sweep), `bounce` (green dot in a track), `arc` (pink quarter-circles), `orbit` (purple braille pairs). The previously dormant `wave` mode is now wired into the random rotation. Set `claudii config set ui.spinner <mode>` to pin one, or leave it on `random` for variety.

### Fixed
- **`lib/log.sh` not sourced by plugin**: `lib/functions.zsh` calls `_claudii_log` at seven sites but `claudii.plugin.zsh` only sourced `visual.sh`, `config.zsh`, `functions.zsh`, `statusline.zsh` — never `log.sh`. Calls failed silently in interactive zsh sessions. Fixed by adding `source lib/log.sh` to the plugin entry.
- **Sessionline default layout: `agent` removed from line 4**: CC already shows the session name natively; the `agent` segment is still available for custom layouts but no longer shown by default.
- **`config/defaults.json` drift with `_DEFAULT_LINES` (round 2)**: The proxy/reshuffle commit updated `_DEFAULT_LINES` in `bin/claudii-sessionline` but not `config/defaults.json`. Since `_cfg_init` copies `defaults.json` to `~/.config/claudii/config.json` on first run, any user who triggered config init received the *old* layout, which then overrode the new in-script default. Synced both files again.
- **`config/defaults.json` drift with `_DEFAULT_LINES`**: The defaults file was missing `dir` (line 3) and `agent` (line 4) segments that the script's `_DEFAULT_LINES` had been advertising for several releases. `claudii config get statusline.lines` returned the stale list. Fixed by syncing both sources.
- **Overview: `model=` prefix in session dashboard** — the precmd session-dashboard extracted values from the session cache using `${sc#*$'\n'key=}`, which failed when `key=` was the first line (no leading newline). Fixed by prepending a newline before extraction (`_sc_nl=$'\n'"$sc"`), affecting model, ctx_pct, cost, rate_5h, and reset_5h display.
- **Overview: `reset Xmin` → `↺Xm`** — Account section reset countdowns now use the same `↺Xm` / `↺XdXh` format as the sessionline instead of the verbose `reset Xmin` / `reset Xd Xh` text.
- **Overview: agents trailing `/`** — Agents without a skill had their empty skill field eaten by `IFS=$'\t' read` (tab is bash whitespace — consecutive tabs collapse), causing columns to shift: `s=haiku m=high e=""` instead of `s="" m=haiku e=high`. Fixed by switching to `` (unit separator) as delimiter in jq/read, which is non-whitespace. Also fixed trailing `/` for agents without effort using conditional `model/effort` vs `model` formatting.

### Refactored
- **Sessionline jq calls on `config.json`**: Three separate `jq` invocations on the same config file (`statusline.lines`, `statusline.models`, `statusline.omlx_active_path`) collapsed into one. US (0x1F) separates the three values; RS (0x1E) separates rows inside `lines`, restored to `\n` in the shell. Saves two `jq` forks per cc-statusline render.
- **`claudii-status` jq calls on `$unresolved`**: Four separate `jq` invocations on the same incidents JSON (count, service level, names list, first-incident name) collapsed into one. Same US/RS scheme; embedded newlines in incident names are stripped to spaces inside `jq` so `read -r` does not truncate.

### Removed
- **`CLAUDII_SYM_CACHE` constant**: Defined in `lib/visual.sh` but never referenced (the sessionline used the literal `⚡` directly). Removed.

---

## [v0.15.0] — 2026-04-17

### Security
- **Sessions cache injection (awk):** Prevented awk code injection via unescaped session names in `_parse_session_cache` and three other sites where glob results are passed to awk — all now quote glob results and bracket `$1` references
- **Sessionline ANSI injection:** `echo -e` with user-controlled session names now uses `printf %s` — prevents embedded escape sequences from being interpreted
- **Token-in-URL:** Anthropic API key no longer visible in cURL/log output during `scripts/release.sh` SHA256 validation — replaced curl with python3
- **Config eval validation:** Agent names validated before `eval` to prevent code injection via crafted aliases
- **`_tok` awk injection:** Token-formatting helper now passes value via `-v` instead of string-interpolation — untrusted token counts can no longer inject awk code
- **Agent name hyphen + reserved-name guard:** Aliases containing hyphens or shadowing built-ins (`cd`, `ls`, etc.) are rejected before `eval`
- **Status feed size cap:** `curl --max-filesize 1m` on unresolved.json / RSS prevents memory exhaustion on oversize responses

### Fixed
- **Session cost/timestamp arithmetic:** Float `$*_mtime` (milliseconds from `epoch_to_date`) now handled in bash arithmetic via explicit rounding — `reset_5h` and `reset_7d` no longer fail on non-integer timestamps
- **Stat macOS-first:** `stat` invocation order corrected throughout (`-x` macOS flag before positional args); applied to `lib/statusline.zsh`, `lib/config.zsh`, and helper functions
- **Atomic writes:** All config/cache updates now use `mktemp` + `mv` pattern (was inline jq writes) — config file can no longer be silently wiped on jq error; added to `install.sh`, `claudii-status`, and sessionline cache updates
- **Sessionline GC file read:** Misplaced `2>/dev/null` removed from `if [[ ! -f ... ]]` condition — error suppression no longer hides permission errors
- **Context percentage unclamped:** `ctx_pct` now capped at 100 to prevent display of `>100%` due to rounding edge cases
- **Session age rendering:** `_render_age` now handles negative values from clock skew without crashing
- **Session cache by mtime:** `latest_5h` now uses cache file `mtime` instead of glob order — ensures correct 5-hour window detection on slow filesystems
- **`claudii update` exit code:** Now correctly exits 1 when brew/git commands fail (was returning 0 on syntax error in update check)
- **Sessionline orphaned arrow:** `↑` indicator now hidden when `input_tok=0` (no pending input)
- **`cc-statusline` usage to stderr:** Help text now printed to stderr, not stdout (consistent with other CLI tools)
- **ClaudeStatus RSS parsing:** Title pattern widened to match Anthropic's incident wording variations; jq type guard added to prevent crashes when API response lacks expected fields; RSS title now word-anchored to prevent `opus` matching `opus-3`-style substrings
- **Status test vacuous:** Removed exit-code test in `test_status.sh` that was silently passing when function didn't execute
- **Performance:** Removed awk subprocess spawning in precmd hook (cost=0 history fallback for performance)
- **Session ctx_pct regex:** Weak `^[0-9]` accepted `"50abc"` and leaked non-numeric into arithmetic — strengthened to `^[0-9]+(\.[0-9]+)?$`, added lower clamp; same validation applied to `rate5h` display path
- **Model word-anchoring in trends/sessions awk:** `/[Oo]pus/` substring match would misclassify fictional names like `sonnet-opus-hybrid` — replaced with word-anchored regex in both `sessions.sh` and `display.sh`
- **`claudii doctor` exit code:** Always returned 0 even when checks failed, breaking CI/automation — now returns 1 if any check is `fail`, in both text and JSON modes
- **history.tsv parse hardening:** awk now strips CR from fields (defense against CRLF-synced files) and guards `NF < 6` short rows in `trends` and `sessions` aggregations
- **Incident name newline strip:** Multi-line incident names from `unresolved.json` flattened via `tr '\n' ' '` — prevents broken RPROMPT/stderr layout
- **`config import` reserved names:** `claudii`, `claude`, `clh` now rejected at import time — previously slipped through to shell registration and broke subcommand dispatch silently
- **Plugin bootstrap `print -P %` expansion:** `claudii.plugin.zsh` now uses `printf` instead of `print -P` — prevents prompt-escape expansion on paths containing `%`
- **Portable shebangs:** `scripts/release.sh` and `scripts/check-session-cost.sh` switched to `#!/usr/bin/env bash`

### Changed
- **Session lookup errors:** Error messages now show what was searched (ID, name, pattern) with hints on how to fix
- **Config key validation:** Actionable error when setting non-existent keys — suggests valid alternatives and shows current config
- **Atomic jq-write pattern:** Extracted into `_jq_update()` helper, replaces 14 inline instances across `system.sh` and `config.sh`
- **Test runner `--summary` flag:** `bash tests/run.sh --summary` prints a single-line pass/fail total — cuts token usage in agent loops (582 passes → 1 line instead of ~800)
- **CLAUDE.md token-efficiency guide:** New section documents re-Read avoidance, batched Edits, agent-prompt caps, verify-before-fix

### Tests
- 20 new tests added for `claudii pin`, `claudii unpin`, `claudii resume` (test_pin_resume.sh)
- Regression tests: `_tok` awk injection, `config import` reserved-name guard, incident-name newline flattening, `trends`/`sessions` CRLF + short-row guards, doctor non-zero exit on failure

---

## [v0.14.0] — 2026-04-07

### Fixed
- **ClaudeStatus:** `unresolved.json` replaces `components.json` as primary source — authoritative active-incident list, no HTML parsing required. RSS remains fallback when API unreachable.
- **ClaudeStatus:** PID recycling guard in `_claudii_status_spawn` — `kill -0` alone can match unrelated processes that reused the PID; now also checks `status.pid` mtime (> 30s → recycled) to ensure only our actual job is counted as running
- **Sessionline:** `pinned=` flag now preserved on every cache update — was silently dropped when session cache was rewritten atomically
- **`_parse_session_cache`:** Removed dead fields `model_id` and `burn_eta` (no callers); `mv` → `mv -f` for consistent atomic overwrites
- **`cleanup-worktree.sh --all`:** Active worktrees with uncommitted changes or unmerged commits are now skipped instead of deleted — prevents accidental removal of in-progress agent work across parallel sessions. `--force` overrides.
- **Formula:** Local `Formula/claudii.rb` was stuck on v0.1.0; `scripts/release.sh` now syncs it on every release alongside the Homebrew tap.

### Changed
- **`scripts/cleanup-worktree.sh`:** `--all` flag removes all zombie `agent-*` dirs in one call; zombie dirs (no `.git` file) cleaned via `rm -rf` fallback (not `git worktree remove` — they aren't registered)
- **ClaudeStatus adaptive TTL:** Cache refresh interval now adjusts based on last known status — all-ok → `ttl × 2` (600s default), incident → `max(60, ttl / 5)` (60s default); halves external calls in normal conditions, doubles check frequency during incidents. Base TTL default corrected from stale 900s to 300s.

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
