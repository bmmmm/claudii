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

### Fix: RSS-Filter "Resolved" zu loose

**Type: Fix**
**Complexity: Low**
**Touches: `bin/claudii-status`**

`grep -qi "Resolved"` matched auch "Unresolved". Präzisere Prüfung:
den letzten `<strong>`-Status im Item extrahieren und prüfen ob er `Resolved` ist,
statt den gesamten Item-Block zu matchen.

---

### Fix: pin/unpin atomar machen

**Type: Fix**
**Complexity: Low**
**Touches: `lib/cmd/sessions.sh`**

`pin` schreibt `pinned=1` per `echo >>` (non-atomic). SessionLine überschreibt das Flag mit atomarem mv.
SessionLine muss das `pinned`-Flag beim Schreiben des Cache-Files erhalten (lesen + weiterführen).

---

### Fix: deutsche Strings im Output

**Type: Fix**
**Complexity: Trivial**
**Touches: `lib/cmd/config.sh`, `lib/cmd/system.sh`, `lib/functions.zsh`**

Drei überlebende deutsche Strings:
- `config.sh:71` — "Config importiert aus $file"
- `system.sh:266` — "Unbekannte status-Option"
- `functions.zsh:224` — "claudii neu geladen"

---

### Refactor: History-File-Sammlung deduplizieren

**Type: Refactor**
**Complexity: Low**
**Touches: `lib/cmd/sessions.sh`, `lib/cmd/display.sh`**

Gleicher Glob-Pattern (`history.tsv` + `history-*.tsv`) in `_cmd_cost` und `_cmd_trends` copy-pasted.
→ `_collect_history_files()` Helper in `bin/claudii` oder separatem lib extracten.

---

### Refactor: Datum-Initialisierung deduplizieren

**Type: Refactor**
**Complexity: Low**
**Touches: `lib/cmd/sessions.sh`, `lib/cmd/display.sh`**

macOS/GNU date-Erkennung + `week_start`-Berechnung + TZ-Offset je ~40 Zeilen in beiden Files identisch.
→ `_date_init()` Helper der `_DATE_CMD`, `_TZ_OFFSET`, `_WS_DOW` setzt.

---

### Refactor: Spinner-Lifecycle deduplizieren

**Type: Refactor**
**Complexity: Low**
**Touches: `lib/cmd/sessions.sh`, `lib/cmd/display.sh`**

Create/kill/cleanup-Pattern 4× wiederholt mit kleinen Variationen.
→ `_spinner_start <label>` / `_spinner_stop` Helpers.

---

### Cleanup: tote Funktionen entfernen

**Type: Cleanup**
**Complexity: Trivial**
**Touches: `lib/visual.sh`, `bin/claudii`**

- `_claudii_sym()` in `visual.sh` definiert, nirgendwo aufgerufen → löschen
- `_session_name`, `_session_fingerprint`, `_session_last_user_message` in `bin/claudii` — Legacy-Wrapper prüfen ob noch aufgerufen, ggf. löschen

---

### Feature: `claudii gc`

**Type: Feature**
**Complexity: Low**
**Touches: `lib/cmd/sessions.sh`, `bin/claudii`, `completions/_claudii`, `man/man1/claudii.1`**

Kein manueller GC-Trigger vorhanden. User sieht Hint in `claudii si` aber kann nicht selbst aufräumen.
→ `claudii gc`: löscht Session-Cache-Files deren PID tot ist, Alter > Threshold, nicht gepinnt.
Man page, Completion, Test hinzufügen.

---

### Feature: `claudii resume <id>`

**Type: Feature**
**Complexity: Low**
**Touches: `bin/claudii`, `completions/_claudii`, `man/man1/claudii.1`**

`--resume`-Flag existiert intern aber ist undokumentiert (kein Help, keine Completion, kein Man-Eintrag).
→ Als eigenen `claudii resume <session-id>` Command exponieren mit Completion aus aktiven Sessions.

---

### Fix: `claudii status` zeigt Incident doppelt

**Type: Fix**
**Complexity: Low**
**Touches: `lib/cmd/system.sh`**

Bei aktivem Incident erscheint der Titel inline mit dem Modell-Status UND nochmal in der RSS-Sektion.
→ Inline-Version entfernen wenn vollständige RSS-Sektion folgt, oder Sektionen zusammenführen.

---

### Fix: `config set` kann keine fehlenden Parent-Pfade anlegen

**Type: Fix**
**Complexity: Low**
**Touches: `lib/cmd/config.sh`**

`claudii config set foo.bar.baz 42` schlägt fehl wenn `foo` oder `foo.bar` nicht in config existieren.
→ jq `setpath/2` oder deep-merge verwenden statt direkter Pfadzuweisung.

---

### Fix: `claudii search` hardcoded auf `clq`-Alias

**Type: Fix**
**Complexity: Low**
**Touches: `lib/cmd/config.sh`**

`claudii search` liest `aliases.clq.model` / `aliases.clq.effort` direkt.
Wenn Alias umbenannt → search bricht lautlos.
→ Eigene `search.model` / `search.effort` Keys in defaults.json, mit Fallback auf `clq`.

---

## In Progress

