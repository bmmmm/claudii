# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Self-Improvement Loop — `/usage` Per-Category Auto-Tuning

**Wave 1 shipped 2026-05-27** — `attribution_skills` / `attribution_plugins` accumulated by `lib/insights.jq` (schema_version 3), aggregated by `bin/claudii-insights merge`, surfaced by `claudii skills-cost [--days N] [--plugins] [--json]`.

**Wave 2 shipped 2026-06-12** (insights schema v4) — subagent attribution (Agent tool_use → `toolUseResult.agentId` → skill chain; subagent transcripts were invisible to the aggregator before: orchestrate 380 → 1568 attributed calls on real data), MCP-tool attribution (`skills-cost --mcp`, message cost split evenly across its MCP tools), dominant-model column (≥80% of attributed calls via flat `attribution_models`, else `mixed`), outlier rule 2× median + ≥10 calls (3× never fired on real data).

**Wave 3 resolved 2026-06-12 — dissolved, mostly out of claudii's scope:**
- **Skill-edit auto-suggestion** — moved OUT of claudii. claudii's contribution is the
  data layer (`skills-cost --json`, done in waves 1+2); the judgment lives in the global
  `/session-close` skill (Phase 2.7 reads `--json` outliers, proposes SKILL.md edits in
  the live session). A `claudii self-improve` CLI shelling out to `claude -p` would
  rebuild what a session does natively (prompt-building in bash, output parsing, API cost).
- **Auto-apply (`--apply`)** — dropped with it; the session applies edits directly.
- **Per-skill-category outlier bands** — still conditional: only if the 2×-median rule
  flags too much/little over time. Rule went live 2026-06-12; revisit with usage data.

`skills-cost --json` is now a consumed interface (session-close Phase 2.7) — treat its
shape (`rows[].{name,calls,tot_usd,avg_usd,model,outlier}`, `meta`) as a contract.

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert (extern):** Claude Code unterstützt `--resume` im Agent-/Task-Tool nicht — kein Permission-Gate, nichts freizugeben. Wartet auf Upstream-Feature.

---

## Decided against

- **Orphan-cache GC for insights** (2026-06-12) — 389 of 654 cache files are orphans
  (source JSONL deleted by Claude Code's `cleanupPeriodDays`; CC never touches our
  cache dir). They are the only cost history beyond CC's transcript retention and
  total 2.6 MB — deleting them removes the feature they are. The `.schema` marker
  (schema gate in `bin/claudii-insights`) already ended the rebuild-loop they caused.
  If size ever matters: opt-in retention in `claudii gc` (last_seen-based, dry-run
  default), not before.
- **Peak-Hours-Indicator** (2026-05-20) — the 5am-11am PT weekday peak window Anthropic
  announced in Dec 2024 is no longer in effect. Competitors that still surface
  it (claude-pulse, PeakClaude) are tracking a defunct rule. Nothing to mirror.
- **Active statusLine-hijack-detection** (2026-05-20) — `claudii doctor` already checks
  `.statusLine.command` (`lib/cmd/system.sh:400-411`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.
