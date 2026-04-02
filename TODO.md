# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Bug: `claudii cost` — falsche Summen (Session-Counts, Opus overcount, Week-Datumsbereich)

**Type: Bug**
**Complexity: Medium**
**Touches: lib/cmd/sessions.sh**

Drei konkrete Bugs:

**1. Session-Count falsch** — `alltime_sessions[m]++` im END-Block des awk zählt
(Session, Tag)-Paare, nicht distinkte Sessions. Eine 3-tägige Session zählt als
"3 sessions". Fix: Im END-Block `sid_model[m SUBSEP sid] = 1` tracken, in Ausgabe
über `for k in ...` zählen wie viele distinkte SIDs pro Modell existieren.

**2. False Context-Reset → Opus overcount** — Reset-Heuristik:
`else if (cost < prev) { running_spend[sid] += cost }` hat keine Schwelle.
Floating-point Rauschen (z.B. cost geht von 10.003 auf 10.002) löst einen "Reset"
aus und addiert den vollen Post-Reset-Wert erneut. Opus ist teurer → mehr Rauschen
→ mehr overcounting. Fix: Reset nur wenn `cost < prev * 0.5` (echter Compaction-Drop
ist immer >50%); bei kleineren Rückgängen `prev = cost` setzen ohne running_spend zu erhöhen.

**3. Week > laufender Monat — fehlender Datumsbereich** — Wenn die Woche den
Monatsanfang überspannt (z.B. KW enthält noch März-Tage, laufender Monat = April)
ist Week-Total > April-Total. Kein Rechenfehler, aber irreführend. Fix: Wochentitel
zeigt Datumspanne: `Week  (Mon 31 Mar – Thu 3 Apr  ·  Mon–Thu)`.

---

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

### A: api-duration Ratio im Segment

**Type: Enhancement**
**Complexity: Small**
**Touches: bin/claudii-sessionline**

`api-duration` Segment zeigt aktuell nur Absolutzeit (`api:45m`). Stattdessen Ratio ergänzen:
`api:45m (73%)` — API-Zeit als % der Gesamtsession-Laufzeit.

Berechnung: `api_duration_ms / duration_ms * 100`. Nur anzeigen wenn beide Werte > 0.

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

