# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Feature: `claudii cost` — Today / Week / Months / Years

**Type: Feature**
**Complexity: Medium**
**Touches: `lib/cmd/sessions.sh` `_cmd_cost()`**

Aktuell: Today + All-time aus Session-Cache-Files (kein historisches Datum).
Neu: vollständige Zeitstruktur aus `history.tsv` (wie `_cmd_trends`).

**Datenquelle:** `history.tsv` — letzter Eintrag pro Session pro Periode (kein Double-Count).

**Output-Struktur:**
```
  Today — Apr 1
    Sonnet  $12.40  3 sessions
    ─────────────────
    $12.40

  Week — Mar 30 – Apr 1
    Sonnet  $45.20  8 sessions
    Opus     $8.50  2 sessions
    ─────────────────
    $53.70

  Months
    Apr  $12.40    Mar  $142.10    Feb  $89.30    Jan  $51.20
    Nov  $38.10    Oct  $29.80     ...

  Years
    2026  $295.00    2025  $432.80
```

**Details:**
- Today + Week: per-Model-Breakdown (wie heute)
- Months: kompaktes Grid (Monat + Gesamt, kein per-Model)
- Years: einzeilig
- `--json`/`--tsv` analog erweitern
- Accent-Header, Cyan für Dollar-Beträge, Dim für Separatoren

---

### Feature: Session-Fingerprint in `claudii se` + Context-Aware Orchestration

**Type: Feature**
**Complexity: Medium**
**Touches: `bin/claudii` (`_session_fingerprint()`), `lib/cmd/sessions.sh` (`_cmd_sessions()`), Orchestrator-Skill**

Ziel: Sessions nach Kontext-Relevanz auswählen statt immer frisch zu starten.

**Teil 1 — Fingerprint-Daten:**
JSONL parsen → Dateien aus Tool-Calls zählen (Read/Edit/Write/Glob):
```bash
_session_fingerprint() {
  # grep tool_input.file_path aus JSONL, count per file, top 5
}
```
Output: `{"lib/statusline.zsh": 23, "lib/cmd/sessions.sh": 8}`

**`claudii se` Anzeige** (3. Zeile pro Session):
```
  ● Opus 4.6  ~/offline_coding/claudii
    ████████░ 82%  │ $42.22  │ 5h:57%  │ 6m ago  86016a8d
    ✦ statusline.zsh(23)  sessions.sh(8)  bin/claudii(5)
```

**`claudii se --json`** erweitern um `fingerprint` + `last_user_message` (letzter User-Turn aus JSONL, max 80 Zeichen).

**Teil 2 — `claudii se --resume <id>`:**
Convenience-Wrapper: `exec claude --resume "$1"` — spart das manuelle Abtippen der Session-ID.
Dispatch in `bin/claudii`, Completion ergänzen.

**Teil 3 — Orchestrator nutzt Fingerprints:**
Vor Agent-Spawn: `claudii se --json` lesen → Overlap-Score zwischen Session-Fingerprints und Task-Dateien berechnen → bei hohem Overlap `--resume <id>` statt Fresh-Start.
(Blockiert bis Claude Code `--resume` im Agent-Tool unterstützt — aktuell nur für interactive sessions.)

---

### Fix: `project_path` direkt in Session-Cache schreiben

**Type: Fix**
**Complexity: Small**
**Touches: `bin/claudii-sessionline`**

Aktuell: Projekt-Pfad wird aus JSONL gelesen (braucht `session_id`). Sessions ohne `session_id` (`session-unknown`) zeigen `(path unknown)`.

Fix: `claudii-sessionline` schreibt `project_path=<cwd>` direkt in Cache-File.
Die `cwd` ist im JSON-Stdin von Claude Code bereits enthalten → kein Lookup nötig.
`_session_project_path` als primären Weg behalten, `project_path`-Feld als Fallback lesen.

---

### Refactor: "Dashboard" → "Session Dashboard" umbenennen

**Type: Refactor**
**Complexity: Large**
**Touches: `lib/statusline.zsh`, `lib/cmd/system.sh`, `bin/claudii`, `config/defaults.json`, `completions/_claudii`, `man/man1/claudii.1`, `CLAUDE.md`, `tests/`**

"Dashboard" ist generisch. "Session Dashboard" macht klar: Session-Zeilen above the prompt, nicht Overview oder ClaudeStatus.

**Scope:**
- Config-Key: `dashboard.enabled` → `session-dashboard.enabled` (Migration-Fallback: alten Key noch lesen)
- CLI: `claudii dashboard [on|off]` → `claudii session-dashboard [on|off]`, `dashboard` als deprecated Alias
- Suppress-Logik: String-Match auf `claudii se*` → `_CLAUDII_SHOWED_SESSIONS=1` Flag (Commands setzen selbst)
- Docs: Man-Page, CLAUDE.md, README

**Hinweis:** Zuletzt angehen — viele Stellen.

---

## In Progress
