# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Fix: Error Messages — alle `exit 1`-Pfade actionable machen

**Type: Fix**
**Complexity: Small**
**Touches: `lib/cmd/system.sh`, `lib/cmd/config.sh`, `bin/claudii`**

Verbleibende nicht-actionable Fehlermeldungen (CLAUDE.md-Regel: jede Meldung muss sagen was zu tun ist):

- `system.sh`: `"Usage: claudii claudestatus [on|off]"` → `>&2` + "run 'claudii claudestatus [on|off]'"
- `system.sh`: `"Ungültiges Intervall: $interval"` → `>&2` + Beispiel
- `system.sh`: `"Usage: claudii status [5m|15m|30m]"` → `>&2` + actionable
- `system.sh`: `"Fehler: $SETTINGS nicht gefunden"` (2x) → `>&2` + URL
- `system.sh`: `"claudii: cannot determine install method"` → `>&2`
- `system.sh`: `"Invalid volume: $vol"` → `>&2` + Beispiel
- `system.sh`: `"Usage: claudii watch [...]"` → `>&2` + actionable
- `config.sh`: `"Datei nicht gefunden: $file"` → `>&2` + Hinweis
- `config.sh`: `"Kein gültiges JSON: $file"` → `>&2` + `jq . $file`
- `bin/claudii`: `"Unknown command: $1"` → `>&2` + "run 'claudii help'"

---

### Fix: Performance `claudii se` — lsof batchen statt pro Session

**Type: Fix**
**Complexity: Small**
**Touches: `lib/cmd/sessions.sh`**

`_cmd_sessions` ruft `lsof -p $ppid -d cwd` einmal **pro Session** als Fallback für den project_path. Bei 5 aktiven Sessions = 5 lsof-Prozesse seriell.

**Fix:** Alle ppids in einem Batch-Aufruf: `lsof -p pid1,pid2,pid3 -d cwd -Fn` gibt alle cwd-Zeilen auf einmal aus. Dann per awk `pid → cwd` mappen.

---

### Feature: Spinner für `claudii se` und `claudii cost`

**Type: Feature**
**Complexity: Small**
**Touches: `lib/cmd/sessions.sh`, `bin/claudii` (oder eigene `lib/spinner.sh`)**

Braille-Spinner als Background-Job während langsame Commands laufen:
- Zeichen: `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` rotierend via `\r` auf stderr
- ASCII-Fallback (`|/-\`) bei `$TERM=dumb` oder non-UTF-8 `$LANG`
- Start vor dem teuren Teil, kill via `kill $spinner_pid` danach
- ~15 Zeilen, wiederverwendbar

---

### Fix: precmd Reentranz + Background-Job-Akkumulation

**Type: Fix**
**Complexity: Small**
**Touches: `lib/statusline.zsh`**

Zwei Race Conditions im precmd-Hook:
1. **Reentranz**: kein Guard — wenn der Hook selbst langsam ist und der User schnell tippt, kann er sich überlappen. Fix: `_CLAUDII_PRECMD_RUNNING`-Flag setzen/löschen.
2. **Job-Akkumulation**: Hintergrundprozesse für Status-Fetch stapeln sich wenn Netz langsam. Fix: vor neuem Spawn prüfen ob der vorherige noch läuft (PID-File oder Job-Count).

---

### Fix: Security — Command Injection + unquoted Variables

**Type: Fix**
**Complexity: Small**
**Touches: `bin/claudii`, `lib/cmd/sessions.sh`, `lib/cmd/system.sh`**

Audit für:
- Unquoted Variablen in `eval`-ähnlichen Kontexten (z.B. `eval "$cmd"`, unquoted `$var` in `[[ ]]`)
- Command Injection in user-supplied Werten die direkt in Shell-Befehle fließen
- `_validate_key` prüft nur alphanumerisch+`._-` — ok für config keys. Andere User-Inputs prüfen.

---

### Fix: Selektive Tests — `# touches:` Mapping in Test-Files

**Type: Fix**
**Complexity: Small**
**Touches: `tests/test_*.sh`, `tests/run.sh`**

Agents laufen stumpf alle ~330 Tests wenn sie eine einzige Datei ändern. Fix: Kommentar-Block am Anfang jedes Test-Files:
```bash
# touches: lib/cmd/sessions.sh lib/cmd/display.sh
```
`run.sh` kann dann mit `--for lib/cmd/sessions.sh` nur die relevanten Test-Files ausführen.

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress
