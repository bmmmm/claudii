# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### ux: claudii cost — Modell-Split in Monats/Jahres-Ansicht + Legende

**Type: Feature**
**Complexity: Small**
**Touches: lib/cmd/sessions.sh** (awk in `_cmd_cost_from_history`)

Derzeit zeigen "Months" und "Years" im pretty output nur die Gesamtsumme.
Opus-Kosten sind drin (z.B. $444.50 für März enthält Opus + Sonnet), aber
nicht sichtbar aufgeteilt.

**Fix 1 — Monats/Jahres-Breakdown:** Wie Today/Week pro Modell aufgelistet,
dann Gesamt:
```
  2026-03
    Opus        $254.10  (3 sessions)
    Sonnet      $190.40  (7 sessions)
    Total       $444.50
```

**Fix 2 — Modell-Legende oben:** Kleine Kopfzeile die zeigt welche Modelle
in der History auftauchen — mit Kurzform (O)pus / (S)onnet / (H)aiku +
Modell-ID aus history.tsv (z.B. "claude-opus-4-6"):
```
  Models: (O) Opus · (S) Sonnet · (H) Haiku
```
"Gesetzt" aus den tatsächlichen Einträgen in history.tsv, nicht config.

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress

