# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Feature: `claudii cost` — Monats- und Jahresübersicht

**Type: Feature**
**Complexity: Medium**
**Touches: `lib/cmd/sessions.sh` `_cmd_cost()`, ggf. `lib/cmd/display.sh`**

Aktuell zeigt `claudii cost` nur Today + All-time. Ziel: Aufschlüsselung nach Monaten + Jahresübersicht.

**Datenquelle:** `history.tsv` (hat Timestamps + Kosten pro Session-Eintrag) — wie `_cmd_trends`, nicht Session-Cache-Files (die haben kein historisches Datum).

**Output-Struktur:**
```
  Current Month (March 2026)
    Opus    $12.40  (18 sessions)
    Sonnet   $3.20  (41 sessions)
    ─────────────────
    Total   $15.60

  Feb 2026    $22.10   Jan 2026    $18.40   Dec 2025    $9.80
  ─────────────────────────────────────────────────────────────
  2026 YTD   $55.70    2025       $89.30
```

**Details:**
- Aktuellen Monat ausführlich (wie Today in `_cmd_cost`)
- Letzte N Monate einzeilig (Monat + Gesamt, kein Per-Model-Breakdown)
- Jahres-Totals unten
- `--json`/`--tsv` Output analog zu bestehenden Formaten erweitern

---

## In Progress

