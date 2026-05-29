# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Claude 4.8 follow-through — propagate session findings

> Context: Opus 4.8 recognition + effort-tier tuning + prompting discipline landed in
> `bde6566`, `3610374`, `12d2746`, `8259fdc` (claudii) and `a73698f`, `cea827f` (dotfiles).
> Code/config/CLAUDE.md are done; the items below are the remaining doc + agent surface.
> Findings to apply everywhere: house default `high` (xhigh on demand, max as fallback);
> `clm` alias is now `xhigh` (was `max`); `op`/`opm`/`orc` agents are `high`; ultracode =
> Claude Code menu mode (= xhigh + standing workflow consent), not a CLI `--effort` value;
> 4.8 follows prompts literally (no CRITICAL/MUST/ALL-CAPS → over-triggering), spawns fewer
> subagents (request fan-out explicitly), and drops real bugs when told to "be conservative"
> at a review finding-stage (use coverage-first + separate verification).

#### TODO: Docs sweep — Claude 4.8 / effort / ultracode
**Type: Docs** · **Complexity: Small** · **Touches: wiki (auto-gen), `help` output, any `docs/*.md`**
- Regenerate wiki from the man page after the man-page update below (wiki is auto-generated — never hand-edit).
- Grep all narrative docs + `lib/cmd/*` help strings for stale model/effort wording (`max effort`, `4-5`, `4-6` defaults, "thinking toggle").
- Confirm CHANGELOG unreleased block covers all of `bde6566`/`3610374`/`12d2746`/`8259fdc` (it does — verify before release).

#### ~~TODO: README update — aliases + effort modes~~ ✅ DONE (README revamp)
Full README revamp: `clm` max→xhigh, effort-mode + ultracode note in the CC-Statusline
section, effort-ladder framing in Aliases, model examples bumped (opus-4-8, Opus xhigh),
added the missing `cache` command (prompt-cache insights) + `gc`/`update`/`changelog`.

#### TODO: Man page pass — 4.8 + effort consistency
**Type: Docs** · **Complexity: Trivial** · **Touches: `man/man1/claudii.1`**
- Sessionline segment example still reads `Claude Sonnet 4.5` (line ~593) — bump to a current model.
- Verify alias rows + effort wording are consistent after the `clm`→xhigh change (partly done in `12d2746`).
- `test_docs.sh` must stay green; wiki regen follows (see docs sweep).

#### TODO: Agent prompts — apply prompting discipline
**Type: Refactor** · **Complexity: Small** · **Touches: claudii subagent spawn prompts, global persona skills (`persona-code-reviewer`, `persona-security-auditor`)**
- Strip `CRITICAL:`/`MUST`/ALL-CAPS imperatives from spawn prompts + skill descriptions (4.8 over-triggers on these).
- Review/bug-finding agents: switch to coverage-first ("report every finding incl. low-confidence, with a confidence level; filtering is a separate step") — keep "PROVEN-only" for cheap Explore/search agents that hallucinate.
- State scope explicitly in prompts (4.8 no longer silently generalizes).
- No `.claude/agents/` dir exists — these live in spawn-prompt strings + the global persona skills.

#### TODO: Orchestrate skill — sync effort + 4.8 findings
**Type: Refactor** · **Complexity: Small** · **Touches: `.claude/skills/orchestrate/SKILL.md` (project) + `~/.claude/skills/orchestrate/SKILL.md` (global, dotfiles repo)**
- Frontmatter `effort: medium` → `effort: high` in BOTH files (out of sync since `orc` agent moved medium→high in `12d2746`).
- Add 4.8 guidance: orchestrator must request subagent fan-out explicitly (4.8 under-spawns); review waves use coverage-first finding + separate verification.
- Global file is in the dotfiles repo (`~/offline_coding/dotfiles`) — separate commit there.

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
