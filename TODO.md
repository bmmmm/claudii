# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Self-Improvement Loop — `/usage` Per-Category Auto-Tuning

**Type: Feature**
**Triggered by:** CC v2.1.149 shipped `/usage` Per-Category Breakdown (Skills / Subagents / Plugins / MCP costs).
**Why:** First time we can attribute cost to a *specific skill*. Opens an auto-tuning loop nobody in the ecosystem does — "outer-layer decision support" lane (Key Insights 2026-05-27 in watchlist).

**Spec-gate (2026-05-27): RESOLVED.** Per-skill / per-plugin attribution IS in JSONL — top-level fields `attributionSkill` (string or null) and `attributionPlugin` (string or null) on every `assistant` row. Verified across 10 recent sessions. JSONL ingestion is sufficient — no `/usage`-runtime fallback needed.

---

#### Wave 1 — Data layer + read-only view (orchestrate-able)

Three independent agents, each tight scope. Tests required per agent.

**Agent A — `lib/insights.jq` extension** (haiku high)
- Bump `schema_version: 2 → 3` (forces cache rebuild on next `claudii-insights aggregate`)
- Add to initial state: `attribution_skills: {}`, `attribution_plugins: {}`
- In the assistant-row branch (currently lines 44–58): when `$r.attributionSkill | type == "string"`, accumulate same shape as `.models[$model]` PLUS a `calls` counter (calls needed for avg cost/call later; `.models` doesn't track this and we won't backfill it — new dimension, new counter):
  ```
  attribution_skills[name]: { calls, in_tok, out_tok, cache_read, cache_create }
  attribution_plugins[name]: { calls, in_tok, out_tok, cache_read, cache_create }
  ```
- Sidechain rows (subagents) are out of scope for Wave 1 — leave `isSidechain: true` rows attributed normally (they may also have `attributionSkill` set from the spawning context — fine, document but don't special-case).
- Test fixture: drop a 5-line synthetic JSONL with mixed null/string attribution into `tests/fixtures/insights-attribution.jsonl`, assert aggregated counters match by hand.

**Agent B — `bin/claudii-insights merge` extension** (haiku high)
- Add `attribution_skills: {}` and `attribution_plugins: {}` to merge initial state (line 178–197)
- Add `.attribution_skills = add_obj_nested(.attribution_skills; $s.attribution_skills)` (and plugins) to reduce block (after line 214) — the helper is already defined
- Update inline `--help` (line 16–17 and 230) to mention the new fields
- Test: extend an existing merge test, assert the new keys appear and aggregate across 2 sessions

**Agent C — `claudii skills-cost` command** (sonnet high)
- New `_cmd_skills_cost()` in `lib/cmd/sessions.sh`; dispatch in `bin/claudii`; completion in `completions/_claudii`; man page entry; CHANGELOG unreleased
- Flags: `--days N` (default 30), `--plugins` (show plugin table instead of skill table), `--json`
- Reads from `claudii-insights merge --days N`
- Uses existing pricing logic — locate it (`lib/cmd/cost.sh` or similar; grep `price\|pricing\|usd` first), do NOT duplicate
- Computes per-row: total cost (in + out + cache_create + cache_read at model-correct prices), avg cost/call, model-mix string
- Sorts desc by total cost; marks outliers (cost/call ≥ 3× median across all rows in the table) with a flag column — no auto-edit
- Output mockup (use `lib/visual.sh` constants for color):
  ```
  $ claudii skills-cost --days 30

  Skill                       Calls   Tot $    Avg $   Model        Flag
  ─────────────────────────── ─────── ─────── ─────── ──────────── ────
  explore                       17     2.31    0.136   opus-4-7      !
  scope-permissions              4     0.08    0.020   sonnet-4-6
  proxy                          3     0.05    0.017   sonnet-4-6
  commit-commands:commit         3     0.04    0.013   sonnet-4-6

  Median cost/call: $0.017 — rows flagged (!) are ≥3× median
  ```
- Tests: snapshot test against a fixture cache directory; assert outlier-flag math; assert `--plugins` switches table; assert `--json` is parseable

**Out of scope for Wave 1** (Wave 2+, manual iteration after looking at real tables):
- Subagent attribution (needs `isSidechain` + `parentUuid` chain — design after seeing real data)
- MCP-tool attribution (needs anteilig-vs-full-row design decision)
- Outlier heuristics beyond simple median multiple
- Skill-edit auto-suggestion (`claudii self-improve`) — that's a judgment-LLM-call design, not mechanical
- Auto-apply (`--apply`)

---

### `terminalSequence` Notifications from claudii hooks

**Type: Feature**
**Complexity: Small**
**Touches: hooks (new or existing), `lib/cmd/system.sh`**
**Triggered by:** CC v2.1.141 added `terminalSequence` field in Hook JSON Output — Desktop Notifications, Window Titles, Bells without controlling terminal.

**Use-cases:**
- ClaudeStatus model down → window-title `[!opus down] claude`
- Burn-ETA critical (<30min to depletion) → bell + title
- Session ended (Stop hook) → notification "session ended, cost $X.YZ"

**Before patching:** read `code.claude.com/docs/en/hooks` for exact `terminalSequence` schema (added 2026-05-18).

---

### Verify v2.1.141 Multi-Line Statusline Bugfix Closed Our Reports

**Type: Investigation**
**Complexity: Trivial**

CC v2.1.141 fixed "Multi-Line Statusline Row Dropping / Corruption when line > terminal width". We render multi-line sessionline — likely hit our users. Action:
1. `git log --grep="multi-line\|statusline.*width\|row.*drop" --since=2026-03`
2. Scan Forgejo/GitHub issues for sessionline corruption reports
3. If all pre-2.1.141 → close with "fixed upstream in CC 2.1.141" + bump min-version note in README

---

### Backlog — Compaction counter

**Type: Feature**
**Complexity: Small-medium**
**Touches: session cache schema, `bin/claudii-cc-statusline`**

ccstatusline shipped #282 (compaction counter). Pairs naturally with our
burn-ETA — "how many compactions did this session survive?". Inner layer.
Defer until after v0.18.4-6.

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## Decided against (2026-05-20)

- **Peak-Hours-Indicator** — the 5am-11am PT weekday peak window Anthropic
  announced in Dec 2024 is no longer in effect. Competitors that still surface
  it (claude-pulse, PeakClaude) are tracking a defunct rule. Nothing to mirror.
- **Active statusLine-hijack-detection** — `claudii doctor` already checks
  `.statusLine.command` (`lib/cmd/system.sh:400-411`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.

---

## In Progress
