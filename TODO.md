# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Refactor: `claudii se` — alle Kostenwerte entfernen

**Type: Refactor**
**Complexity: Small**
**Touches: lib/cmd/sessions.sh**

Kosten gehören nicht in `se` — dafür gibt es `claudii cost`. Entfernen:
- Cost-Segment aus Session-Detailzeile (pro Session `$18.48`, `$4.16`)
- `$22.64 total` aus der Footer-Summary-Zeile (`N aktiv, M beendet, $X total`)
- "cost = session total" aus der Legende
- Ebenfalls in `_cmd_sessions_inactive`: Cost-Segment entfernen
- `_sf_cost`-Array befüllen und an `claudii se --json` ausgeben (für Dashboard-Fallback
  in statusline.zsh), aber nicht im Pretty-Output anzeigen

---

### Refactor: `claudii cost` / `claudii trends` — Abgrenzung schärfen

**Type: Refactor**
**Complexity: Small**
**Touches: lib/cmd/sessions.sh, lib/cmd/display.sh, man/man1/claudii.1, completions/_claudii**

Aktuelle Überlappung: beide zeigen "diese Woche" und "heute".

Ziel:
- `claudii cost` → **Accounting**: exakte Dollar-Beträge pro Periode (heute/Woche/Monat/
  Jahr/gesamt), per Modell aufgeschlüsselt, Session-Counts. Woche mit Datumspanne.
  Kein Kalender-Chart.
- `claudii trends` → **Visualisierung**: Balken-Timeline der letzten 30 Tage,
  Woche-über-Woche-Vergleich, Trend-Pfeile. Keine Perioden-Summen die `cost` schon zeigt.

Konkret: `trends` entfernt die Text-Zeile "Week: $X.XX  Last: $Y.YY" (die ist jetzt in
`cost` mit mehr Detail). `cost` entfernt keine Periode, bekommt aber den Wochentitel
mit Datumspanne (aus dem Bug-Fix oben). Man-Page + Completions: beide Commands
mit je 1-Satz-Beschreibung der Abgrenzung aktualisieren.

---

### B: api-duration in history.tsv tracken → Trends

**Type: Feature**
**Complexity: Small**
**Touches: bin/claudii-sessionline, lib/cmd/display.sh (trends)**

`api_duration_ms` zu history.tsv hinzufügen (aktuell 8 Felder → 9 Felder).
`claudii trends` zeigt dann tägliche API-Wartezeit: `Mo api:1h23m  Di api:2h01m`.

Achtung: Schema-Änderung — bestehende history.tsv-Zeilen haben kein 9. Feld → `trends`
muss mit leerem Feld umgehen (awk: `$9 == "" ? 0 : $9`).

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress

