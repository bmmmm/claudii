# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### [W1a] Feature: Overview — Color Polish + Accent

**Type: Feature**
**Complexity: Small**
**Touches: `lib/cmd/sessions.sh` `_cmd_default()` only**
**Parallel with: W1b**

Nutzt ausschließlich existierende `CLAUDII_CLR_*` Vars (keine neuen hardcoded Codes).
Da die Vars später durch das Theme-System ersetzt werden, ist dieser Task automatisch theme-aware.

**Rate-Limit-Werte** (5h, 7d) — colored by threshold:
- `< 50%` → `CLAUDII_CLR_GREEN`
- `50–80%` → `CLAUDII_CLR_YELLOW`
- `>= 80%` → `CLAUDII_CLR_RED`

**Reset-Countdown** — Urgency-Farbe:
- `> 60min` → `CLAUDII_CLR_DIM`
- `10–60min` → `CLAUDII_CLR_YELLOW`
- `< 10min` → `CLAUDII_CLR_RED`

**Accent** (`CLAUDII_CLR_ACCENT`, pink):
- `claudii vX.Y.Z` Header-Versionsnummer
- Today's cost (`$X.XX`) in Account-Sektion
- Aktive Session-Bullet-Zeile (Anzahl)

**Dashboard** (`lib/statusline.zsh`): dieselbe Urgency-Logik für 5h-Rate in Dashboard-Zeilen.

---

### [W1b] Feature: Theme-Schema in Config + `claudii config theme`

**Type: Feature**
**Complexity: Small**
**Touches: `config/defaults.json`, `lib/cmd/config.sh`**
**Parallel mit: W1a**

1. **`config/defaults.json`** — neues `theme`-Objekt:
```json
"theme": {
  "name": "default",
  "colors": {
    "accent":     "38;5;213",
    "rate_ok":    "0;32",
    "rate_warn":  "0;33",
    "rate_crit":  "0;31",
    "reset_ok":   "2",
    "reset_warn": "0;33",
    "reset_crit": "0;31"
  }
}
```
Zweites Preset `"pastel"` definieren:
- accent: `38;5;219` (helleres Pink)
- rate_ok: `38;5;114` (softes Grün)
- rate_warn: `38;5;221` (softes Gelb)
- rate_crit: `38;5;210` (softes Rot)

2. **`claudii config theme <name>`** — setzt `theme.name` in user config.
   Verfügbare Themes auflisten (`claudii config theme` ohne Argument).
   Kein Neustart nötig — wird beim nächsten Befehl geladen.

3. **Completions** (`completions/_claudii`) für `config theme default|pastel` ergänzen.

---

### [W2] Feature: `visual.sh` Theme-Loading aus Config

**Type: Feature**
**Complexity: Medium**
**Touches: `lib/visual.sh`, `lib/config.zsh`**
**Depends on: W1b (Schema definiert)**

`lib/visual.sh` wird config-aware:

1. Nach dem Laden der statischen Defaults: `_claudii_theme_load` aufrufen
2. Diese Funktion liest `theme.name` + `theme.colors.*` aus Config (via `_cfgget` oder direktem JSON-Parse)
3. Überschreibt `CLAUDII_CLR_*` Vars entsprechend:
   ```bash
   CLAUDII_CLR_ACCENT=$'\033['"${_theme_accent}"'m'
   CLAUDII_CLR_GREEN=$'\033['"${_theme_rate_ok}"'m'
   # etc.
   ```
4. Fallback: wenn kein theme in config → hardcoded defaults bleiben (kein Bruch)
5. ZSH-Theme-Adaption: `$TERM_PROGRAM`, `$COLORFGBG` oder `$ZSH_THEME` können optionalen Auto-Preset triggern (z.B. light-Hintergrund → pastel). Als `theme.name: "auto"` implementieren.

**Tests:** `test_config.sh` — Theme-Wechsel ändert CLAUDII_CLR_ACCENT; Theme "pastel" setzt andere Codes als "default".

### Fix: `claudii status` — Zeit fehlt bei manchen Incident-Zeilen

**Type: Bug**
**Complexity: Small**
**Touches: `lib/cmd/system.sh` `_cmd_status()`**

Die "Resolved"-Zeile zeigt keine Uhrzeit, obwohl Monitoring und Investigating Zeiten haben (`2:19 PT / 9:19 UTC`). Das `<small>`-Tag-Parsing schlägt für den neuesten Eintrag fehl. Zeit soll immer angezeigt werden — gibt guten Überblick über den Incident-Verlauf.

Root cause ermitteln: RSS direkt fetchen, Paragraph-Struktur des Resolved-Eintrags prüfen. Falls `<small>` content anders encoded ist (entities, nested tags), sed-Pattern anpassen.

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

