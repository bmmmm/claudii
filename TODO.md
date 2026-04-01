# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Audit: Code Quality, Bugs & Performance — Opus Review

**Type: Audit + Fix**
**Complexity: Medium**
**Model: Opus**
**Touches: `bin/claudii`, `bin/claudii-sessionline`, `lib/cmd/sessions.sh`, `lib/cmd/system.sh`, `lib/statusline.zsh`, `lib/visual.sh`, `tests/`**

Tiefer Audit durch Opus — kein Feature, nur Qualität.

**Scope:**
- **Code Quality:** Doppelter Code, unklare Variablennamen, inkonsistente Patterns, fehlende Guards
- **Bugs:** Edge Cases die Tests nicht abdecken — leere Felder, unerwartete jq-Outputs, Race Conditions in Cache-Writes, set -e Fallstricke in Arithmetic
- **Performance:** Unnötige Subshells, mehrfache jq-Aufrufe wo einer reicht, teure lsof-Aufrufe in Hot Paths (`_cmd_sessions` ruft lsof pro Session)
- **Security:** Command Injection Risiken, unquoted Variablen in eval-ähnlichen Kontexten

- **Test Coverage:** Code-Paths identifizieren die von keinem Test abgedeckt sind — nicht 100% Coverage anstreben, sondern gezielt: welche Edge Cases können in Produktion knallen? Fehlende Tests für die kritischsten Paths hinzufügen.
- **Error Messages:** Alle `echo "Error/No/..."` und `exit 1`-Stellen prüfen — sind sie actionable? Per CLAUDE.md-Regel: nie "Error: unknown" ohne Hinweis was zu tun ist. Blinde Fehlermeldungen durch konkrete Handlungsanweisungen ersetzen.
- **Race Conditions:** Cache-Files ohne Locking gleichzeitig von mehreren Sessions schreiben (`claudii-sessionline` + `claudii watch` + manueller Aufruf) — atomare Writes fehlen. Background-Job-Akkumulation in `precmd`: wenn Hook langsam ist und Shell schnell tippt, stapeln sich Jobs. `precmd`-Reentranz: kein Guard gegen parallele Invocations. `watch`-Mode: kein Exit-Guard bei Signal — kann als Zombie weiterlaufen.

- **Spinner für langsame Commands:** `claudii se` und `claudii cost` haben spürbare Ladezeiten (lsof pro Session, history.tsv-Parsing). Spinner als Background-Job: Braille `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` rotierend via `\r`, ASCII-Fallback (`|/-\`) bei `$TERM=dumb` oder non-UTF-8 `$LANG`. Kill-Signal wenn Command fertig. ~15 Zeilen. Nur wenn Performance-Fix aus diesem Audit noch Restlatenz lässt.
- **Test Parallelisierung:** `tests/run.sh` führt Test-Files sequenziell via `source` aus — kein parallelism möglich, Agents die gleichzeitig testen blockieren sich gegenseitig. Fix: (1) `test_statusline.sh` + `test_config.sh` nutzen feste `tmp/test_*` Pfade → auf `mktemp -d` umstellen; (2) `run.sh` auf Subprozesse umstellen (jede Test-File als `bash "$f"` im Background, Output in Temp-File, aggregieren); (3) `sleep 3` in `test_statusline.sh` auf 1s reduzieren. Erwarteter Gewinn: ~15-20s → ~3-5s Laufzeit.
- **Known Bugs (confirmed):** `lib/cmd/system.sh:513` `(( _dc_stale++ ))` und `lib/cmd/sessions.sh:778` `(( _ov_stale++ ))` — beide initialisiert mit 0, unter `set -euo pipefail`, erster Fund killt den Prozess. Fix: `++_dc_stale` / `++_ov_stale`.

**Output:** Konkrete Fixes mit Begründung — kein Refactoring um des Refactorings willen. Jede Änderung braucht einen nachvollziehbaren Grund. Tests müssen danach grün bleiben.

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress
