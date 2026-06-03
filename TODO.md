# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Agent prompts — apply prompting discipline (global, not this repo)

**Type: Refactor** · **Complexity: Small** · **Touches: global persona skills (`persona-code-reviewer`, `persona-security-auditor`) in `~/.claude/skills/`**

claudii's own skills (`.claude/skills/`) are already clean — no `CRITICAL`/`MUST`/ALL-CAPS imperatives. What remains lives outside this repo:

- Strip `CRITICAL:`/`MUST`/ALL-CAPS imperatives from the global persona skills (4.8 over-triggers on these).
- Review/bug-finding agents: switch to coverage-first ("report every finding incl. low-confidence, with a confidence level; filtering is a separate step") — keep "PROVEN-only" for cheap Explore/search agents that hallucinate.
- State scope explicitly in prompts (4.8 no longer silently generalizes).

---

### Self-Improvement Loop — `/usage` Per-Category Auto-Tuning (Wave 2+)

**Wave 1 shipped 2026-05-27** — `attribution_skills` / `attribution_plugins` accumulated by `lib/insights.jq` (schema_version 3), aggregated by `bin/claudii-insights merge`, surfaced by `claudii skills-cost [--days N] [--plugins] [--json]`. First real data on `bin/claudii`: top spenders are `memory-gc` ($95.88 / 746 calls) and `orchestrate` ($35.93 / 325 calls) across 30d.

**Wave 2 candidates (manual iteration after looking at real tables):**
- **Subagent attribution** — needs `isSidechain` + `parentUuid` chain design after seeing real data
- **MCP-tool attribution** — design decision: anteilig vs full-row cost
- **`model` column** currently shows `mixed` always — surface dominant model per skill from `.models` correlation
- **Outlier heuristics** beyond simple 3× median — none flagged on real data, threshold may need tuning or per-skill-category bands
- **Skill-edit auto-suggestion** (`claudii self-improve`) — judgment-LLM-call, not mechanical transform
- **Auto-apply** (`--apply`) — last, after suggestions are trusted

**Refactor candidate from Wave 1:** Agent C's `_cmd_skills_cost` reads insights cache files directly instead of using `claudii-insights merge` (because Agent B's merge extension wasn't visible to C at spawn time). Functionally equivalent but architecturally inconsistent — should be refactored to use `merge` so the cutoff/project filters stay in one place.

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
(Defer-until-v0.18.4-6 note dropped — we're past v0.19.0, no longer gated.)

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert (extern):** Claude Code unterstützt `--resume` im Agent-/Task-Tool nicht — kein Permission-Gate, nichts freizugeben. Wartet auf Upstream-Feature.

---

## Decided against (2026-05-20)

- **Peak-Hours-Indicator** — the 5am-11am PT weekday peak window Anthropic
  announced in Dec 2024 is no longer in effect. Competitors that still surface
  it (claude-pulse, PeakClaude) are tracking a defunct rule. Nothing to mirror.
- **Active statusLine-hijack-detection** — `claudii doctor` already checks
  `.statusLine.command` (`lib/cmd/system.sh:400-411`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.
