# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Self-Improvement Loop — `/usage` Per-Category Auto-Tuning

**Type: Feature**
**Complexity: Medium-large**
**Touches: `bin/claudii-insights`, `lib/insights.jq`, new sub-command (likely `claudii skills-cost` + `claudii self-improve`)**
**Triggered by:** CC v2.1.149 shipped `/usage` Per-Category Breakdown (Skills / Subagents / Plugins / MCP costs).

**Why this matters:** First time we can attribute cost to a *specific skill*. Opens an auto-tuning loop nobody in the ecosystem does — fits the "outer-layer decision support" lane (see Key Insights 2026-05-27 in watchlist).

**Concept:**
1. **Aggregate** — extend `lib/insights.jq` to extract per-skill / per-subagent / per-plugin token+cost from JSONL (same data CC `/usage` uses, from our side).
2. **Detect outliers** — heuristics: skill X is 5× the median cost-per-invocation; subagent Y burns Opus when description fits Haiku; plugin Z's MCP server reloaded N× without being called.
3. **Surface** — `claudii skills-cost` table, cost-trend per skill, top-N expensive.
4. **Auto-suggest fixes** — for top-3 outliers, propose concrete edits to `~/.claude/skills/<name>/SKILL.md` (downgrade model, tighten "When NOT to use", split into cheaper variant). Print diff, ask, don't auto-apply.
5. **Opt-in `claudii self-improve --apply`** — applies after confirmation per finding.

**Spec-first gate:** before coding, verify per-skill cost is actually in the JSONL stream (vs only in CC's runtime `/usage` output). If runtime-only, design needs ingestion-fallback (`claude /usage --json | claudii self-improve`). Spec → `tmp/self-improve-spec.md`.

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
