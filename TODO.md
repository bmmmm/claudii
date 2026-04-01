# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Feature: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**

**Blockiert:** Claude Code `--resume` im Agent-Tool wird noch nicht unterstützt — nur für interactive sessions.

Wenn verfügbar: Vor Agent-Spawn `claudii se --json` lesen → Overlap-Score zwischen Session-Fingerprints und Task-Dateien berechnen → bei hohem Overlap `--resume <id>` statt Fresh-Start.

---


## In Progress

