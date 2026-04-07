# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

### Fix: sessionline preserves pin flag

**Type: Fix**
**Complexity: Low**
**Touches: `bin/claudii-sessionline`**

`bin/claudii-sessionline` überschreibt Session-Cache-Files atomar (tmp+mv), liest dabei aber `pinned=1` nicht aus dem alten File.
Beim Schreiben des neuen Cache: altes File lesen, `pinned=`-Wert mergen, erst dann neu schreiben.

---

## In Progress

