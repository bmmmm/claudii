# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Fix: `claudii status` — Zeit fehlt bei manchen Incident-Zeilen

**Type: Bug**
**Complexity: Small**
**Touches: `lib/cmd/system.sh` `_cmd_status()`**

Die "Resolved"-Zeile zeigt keine Uhrzeit, obwohl Monitoring und Investigating Zeiten haben (`2:19 PT / 9:19 UTC`). Das `<small>`-Tag-Parsing schlägt für den neuesten Eintrag fehl. Zeit soll immer angezeigt werden — gibt guten Überblick über den Incident-Verlauf.

Root cause ermitteln: RSS direkt fetchen, Paragraph-Struktur des Resolved-Eintrags prüfen. Falls `<small>` content anders encoded ist (entities, nested tags), sed-Pattern anpassen.

---

### Fix: Dashboard `↺`-Countdown fehlt für letzte Session

**Type: Bug**
**Complexity: Small**
**Touches: `lib/statusline.zsh` `_claudii_dashboard()`**

Wenn eine Session kein `reset_5h` im Cache-File hat (leeres Feld `reset_5h=`), fehlt das `↺Xm`. Die anderen Sessions auf demselben Account haben denselben Reset-Timestamp.

Fix: In `_claudii_collect_sessions` den neuesten validen `reset_5h`-Wert über alle Sessions merken. In `_claudii_dashboard` als Fallback nutzen wenn `_rst` für eine Session leer ist — alle aktiven Sessions teilen sich denselben Rate-Limit-Reset.

---

### Design: Dashboard nach `claudii`-Commands unterdrücken?

**Type: Design**
**Complexity: Medium**
**Touches: `lib/statusline.zsh`, evtl. Config**

Das Dashboard zeigt die Session-Zeilen nach JEDEM Befehl — auch nach `claudii status`, `claudii sessions` etc. Nach dem Refactoring zeigen diese Commands jetzt eigene Session-Infos, sodass Dashboard-Zeilen danach redundant sind.

Optionen:
1. Immer unterdrücken wenn letzter Befehl `claudii` war (aus `preexec`-Analyse)
2. Konfigurierbar: `dashboard.suppress_after_claudii: true` (Default: false)
3. Status-quo belassen

**Zur Diskussion** bevor implementiert.

---

## In Progress

