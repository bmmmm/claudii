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

### Feature: Dashboard-Zeilen rechts ausrichten (RPROMPT-Stil)

**Type: Feature**
**Complexity: Medium**
**Touches: `lib/statusline.zsh` `_claudii_dashboard()`**

Aktuell erscheinen Dashboard-Zeilen links (2-Space-Indent, PROMPT-prepend). Ziel: rechts ausrichten, so wie ClaudeStatus — optisch konsistent, nimmt weniger visuelle Aufmerksamkeit.

Optionen:
1. **Right-align via `%>{}` / `%(col)` in PROMPT** — zsh kann Spalten-Offset. Erfordert Terminal-Breite (`$COLUMNS`) und padding pro Zeile.
2. **RPROMPT multi-line** — RPROMPT zeigt nur eine Zeile, passt nicht für N Sessions.
3. **`%>` right-fill** — `printf "%*s"` mit Terminalbreite, kein zsh-Trick nötig.

Vorherige Entscheidung war gegen Right-Alignment wegen EAW (East-Asian-Width) und Cursor-Tricks. Mit `%>{}` in zsh PROMPT_SUBST ist das sauber lösbar ohne ESC-Sequenzen.

Format-Ziel:
```
                        Sonnet 4.6  74%  $33.85  5h:60% ↺84m
                        Sonnet 4.6  49%  $59.62  5h:60% ↺81m
➜  claudii git:(main) _
```

### Design: Dashboard nach `claudii`-Commands unterdrücken?

**Type: Design**
**Complexity: Small**
**Touches: `lib/statusline.zsh`**

Dashboard zeigt Session-Zeilen nach JEDEM Befehl — auch nach `claudii status`, `claudii se` etc. Redundant wenn man gerade Overview/Sessions-Detail gesehen hat.

Lösung: In `preexec` den letzten Befehl merken (`_CLAUDII_LAST_CMD`). In `_claudii_dashboard`: wenn `$_CLAUDII_LAST_CMD` mit `claudii` anfängt → kein Dashboard.

Kein Config-Key nötig — das ist sinnvolles Default-Verhalten.

---

## In Progress

