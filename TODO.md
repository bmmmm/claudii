# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Refactor: "Dashboard" → "Session Dashboard" umbenennen

**Type: Refactor**
**Complexity: Large**
**Touches: `lib/statusline.zsh`, `lib/cmd/system.sh`, `bin/claudii`, `config/defaults.json`, `completions/_claudii`, `man/man1/claudii.1`, `CLAUDE.md`, `tests/`**

"Dashboard" ist generisch und klingt wie das Haupt-Feature. "Session Dashboard" macht klar, dass es sich um die Session-Zeilen above the prompt handelt — nicht um Overview oder ClaudeStatus.

**Scope:**
- Config-Key: `dashboard.enabled` → `session-dashboard.enabled` (mit Migration-Fallback: alten Key noch lesen)
- CLI: `claudii dashboard [on|off]` → `claudii session-dashboard [on|off]`, `dashboard` als deprecated Alias behalten
- Interne Variablen/Funktionen: `_claudii_dashboard` → `_claudii_session_dashboard`, `_CLAUDII_DASH_*` → `_CLAUDII_SDASH_*`
- Suppress-Logik: aktuell String-Match auf `claudii se*` etc. → ersetzen durch `_CLAUDII_SHOWED_SESSIONS=1` Flag das Commands wie `se/si/sessions` selbst setzen (kein Befehlsnamen-Matching im Hook nötig)
- Docs: Man-Page, CLAUDE.md Command Roles Tabelle, README

**Hinweis:** Erst nach allen anderen Pending-Items angehen — sehr viele Stellen.

---

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

