# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### skills-cost: Pricing korrigieren + Urteils-Signale freilegen

**Type: Fix + Feature** · **Complexity: gestaffelt (3 Wellen)** · **Touches: `lib/cmd/skills-cost.sh`, `lib/insights.jq`, `bin/claudii-insights`, session-close Phase 2.7 (Konsument)**

Drei verifizierte Probleme am `skills-cost`-Output (Stand 2026-06-12):

1. **Dollar-Beträge systematisch falsch — Flat-Sonnet-Pricing über alle Modelle.**
   `lib/cmd/skills-cost.sh:40-43` rechnet alle Tokens zu Sonnet-Raten ($3/$15/M).
   Opus = 5×, Haiku = ⅓, Fable mehr. Schlimmer als der absolute Fehler: das
   **Ranking** zwischen Skills mit unterschiedlichem Modell-Mix verzerrt
   (Haiku-dominanter Skill ~3× überzeichnet, Opus-dominanter ~5× unterzeichnet) —
   und die 2×-Median-Outlier-Regel vergleicht genau über dieses Ranking.
   Saubere Lösung braucht per-Modell-**Token**-Attribution (`attribution_models`
   speichert heute nur Calls) = Schema v5.

2. **Token-Split fehlt im Output — dabei ist er das eigentliche Urteils-Signal.**
   Der Merge-Cache hat in/out/cache_read/cache_create pro Skill, aber `--json`
   gibt nur tot/avg raus. Der Split unterscheidet "Skill redet zu viel"
   (out-lastig → Reply-Cap in SKILL.md hilft) von "Skill läuft in fetten
   Sessions" (cache_read-lastig → SKILL.md-Edits helfen kaum). Live-Beispiel,
   unser geflaggter Outlier: `update-config` = 894 out-Tokens/Call (schweigsam!),
   aber 337K cache_read/Call — der Default-Ratschlag "Antworten kürzen" wäre
   falsch; der Hebel sind die Settings-Reads / der Trigger-Zeitpunkt. Ohne den
   Split urteilt session-close 2.7 blind.

3. **avg/Call ist konfundiert mit Session-Kontextgröße + kein Trend.**
   Jeder Call kostet proportional zum Kontext im Moment des Calls — Skills am
   Session-Ende sind per Konstruktion teuer (session-close $0.094, reflect
   $0.118: konsistent hoch, sagt nichts über die Skills). Ohne Vorher/Nachher-
   Vergleich kann der Self-Improvement-Loop nicht messen, ob ein SKILL.md-Edit
   etwas gebracht hat — der Loop schließt sich nicht.

**Wellen:**
- [x] **Welle A — shipped 2026-06-12:** Token-Split (in/out/cache_read/cache_create,
  absolut) in den `--json`-Rows + `meta.pricing`-Caveat. Per-Call-Werte bewusst
  weggelassen — trivial ableitbar (`tok/calls`), Konsument rechnet selbst.
  Contract-Erweiterung additiv (session-close 2.7 liest `rows[]`-Felder).
- [x] **Welle B — shipped 2026-06-12:** Schema v5, `attribution_models` von
  Calls-only auf `{calls,in/out/cache_read/cache_create}` pro Modell erweitert;
  `skills-cost` preist jeden per-Modell-Token-Bucket zu seiner Tier-Rate, Residual
  (pre-v5 Orphans ohne Split) flat-Sonnet. Consumer-Sweep: merge `add_models`
  (Skalar-tolerant), `SCHEMA_VERSION=5` in `bin/claudii-insights`, Tests
  (attribution/merge/skills-cost), CLAUDE.md Pricing-Note. `--json` rows[]-Contract
  unverändert (tot_usd nur präziser).
- [ ] **Welle C — Trend-Vergleich:** Zeitfenster-Vergleich (z.B.
  `--compare 30:30` oder vorher/nachher um einen Edit-Zeitstempel), damit
  Phase 2.7 Skill-Edits auf Wirkung prüfen kann. Design offen: Kontext-
  Konfundierung (Problem 3) mindestens dokumentieren, idealerweise
  out-Tokens/Call als kontextrobustere Vergleichsmetrik anbieten.

---

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

Data-quality work tracked in the dedicated pending item above
("skills-cost: Pricing korrigieren + Urteils-Signale freilegen", Wellen A–C).

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
