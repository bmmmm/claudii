# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Refactor: `claudii cost` — Display-Cleanup (Sessions + Tokens raus, Total visuell abgrenzen)

**Type: Refactor**
**Complexity: Small**
**Touches: lib/cmd/sessions.sh**

`claudii cost` ist reines Accounting — nur Dollar-Beträge, kein Token-Ballast, keine Session-Counts.
Sessions und Tokens gehören in `claudii trends`.

**Entfernen:**
- `(N session)` / `(N sessions)` aus allen Per-Modell-Zeilen (Today, Week, Months, Years)
- `138K tok` / `2.6M tok` Token-Suffix aus allen Total-Zeilen

**Visual redesign (pro Section):**
- Blank line VOR dem Section-Header (`Today`, `Week`, `Months`, `Years`) für Luft zwischen Abschnitten
- Per-Modell-Zeilen: nur `    Opus       $0.00` — kein dim, volle Lesbarkeit
- Separator-Linie bleibt (`─────────────────`)
- Total-Zeile: Label `Total` in ACCENT (pink/magenta), Betrag in BOLD+CYAN → visuell klar vom Rest abgehoben
- **Extra Leerzeile nach der Total-Zeile** (nach der ─── Separator-Zeile + Total), damit Sections atmen

Ziel-Layout pro Section:
```
  Today
    Opus       $0.00
    Sonnet     $10.52
  ─────────────────────
    Total      $10.52

  Week  (2026-03-30 – 2026-04-03)
    ...
```

Nested Sections (Months/Years) gleich behandeln — Total kursiv oder ACCENT, danach Leerzeile.

---

### Bug: `lib/trends.awk` — False-Reset-Schwelle fehlt (cost + tokens)

**Type: Bug**
**Complexity: Small**
**Touches: lib/trends.awk**

`trends.awk` verwendet noch die alte Reset-Heuristik ohne 0.5-Schwelle:
- `cost < prev` → overcounts nach Context-Compaction (selber Bug der in `sessions.sh` in Wave 1 gefixt wurde)
- `total_tok < prev_tok` → Token-Summen ebenso falsch

Fix:
```awk
} else if (cost < prev * 0.5) {   # war: cost < prev
} else if (total_tok < prev_tok * 0.5) {  # war: total_tok < prev_tok
```

Genuine Compaction-Drop ist immer >50% — alles darunter ist Floating-Point-Rauschen.
Auch `tok_delta`-Branch analog anpassen.

---

### Refactor: `bin/claudii-sessionline` — Awk-Subprocess-Explosion reduzieren

**Type: Refactor**
**Complexity: Medium**
**Touches: bin/claudii-sessionline**

Aktuell: **8 `awk BEGIN` Subprozesse** pro Statusline-Update — alle für simples Rechnen:

| Variable | Formel | Ersatz |
|---|---|---|
| `_usable_pct` | `int(local_pct / 0.8)` | `(( _usable_pct = local_pct * 100 / 80 ))` |
| `_reset_min` | `int((reset_5h - now) / 60)` | `(( _reset_min = (reset_5h - _now + 30) / 60 ))` |
| `_reset_7d_sec` | `reset_7d - now` | `(( _reset_7d_sec = reset_7d - _now ))` |
| `_api_pct` | `int(api_int / dur_int * 100)` | `(( _api_pct = _api_int * 100 / _dur_int ))` |
| `_session_min_f` + `_burn_eta` | Float-Division | **Zusammenlegen** in einem awk-Aufruf |
| `_tok()` × 2–3 | `%.1fK` / `%.1fM` | **Einen** kombinierten awk-Aufruf für alle Token-Werte |

Ziel: von 8 auf max. 2 awk-Forks pro Update (einer für Float-Arithmetic, einer für Token-Formatierung).
Kein `bc`, keine neuen Tools.

---

### Refactor: `lib/cmd/sessions.sh` + `lib/visual.sh` — Hardcoded Symbols durch Konstanten ersetzen

**Type: Refactor**
**Complexity: Small**
**Touches: lib/cmd/sessions.sh, lib/visual.sh**

`sessions.sh` verwendet `●`, `○`, `│`, `✓`, `✗`, `⚠`, `⚡` direkt im Code statt `$CLAUDII_SYM_*`.
Die Konstanten in `visual.sh` werden kaum genutzt (2×ACTIVE, 2×INACTIVE, je 3×OK/DOWN/DEGRADED).

Änderungen:
1. In `lib/visual.sh`: `CLAUDII_SYM_CACHE="⚡"` ergänzen (bislang kein Eintrag)
2. In `lib/cmd/sessions.sh`: alle `●` → `$CLAUDII_SYM_ACTIVE`, `○` → `$CLAUDII_SYM_INACTIVE`, `│` → `$CLAUDII_SYM_SEP`, `✓` → `$CLAUDII_SYM_OK`, `✗` → `$CLAUDII_SYM_ERROR`, `⚠` → `$CLAUDII_SYM_WARN`, `⚡` → `$CLAUDII_SYM_CACHE`
3. `system.sh` analog (hat `✓` / `⚠` / `✗` hardcoded in `_cmd_status`)

---

### Refactor: `bin/claudii-sessionline` — Benannte Farb-Lokalvariablen statt nackter ANSI-Codes

**Type: Refactor**
**Complexity: Small**
**Touches: bin/claudii-sessionline**

sessionline hat ~20 hardcoded `\033[31m`, `\033[36m` etc. — keine benannten Konstanten, kein Bezug zu `visual.sh`. Farben sind im Code unsichtbar.

Fix: Am Anfang von `bin/claudii-sessionline` (nach `RST` und `DIM`) alle genutzten Farben als benannte Lokalvariablen definieren:
```bash
RST="\033[0m"; DIM="\033[2m"; BOLD="\033[1m"
CYAN="\033[0;36m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"
RED="\033[0;31m"; WHITE="\033[0;97m"; ACCENT="\033[38;5;213m"
```
Dann alle nackten `\033[Xm` im Code durch die Namen ersetzen. Selbe Werte wie `visual.sh` — kein Verhalten ändert sich.

---

### Docs: `README.md` — Sessionline-Beispiel aktualisieren

**Type: Docs**
**Complexity: Small**
**Touches: README.md**

Zeile ~45: Beispiel zeigt noch altes einzeiliges Format mit `$1.24` Cost-Segment:
```
claude-sonnet-4-5  ●●●●●●○○○○  $1.24  12.4k ⚡73%  5h:28%  +47/-12  0:42
```
Cost ist seit Wave 2 kein Default-Segment mehr. Multi-Line-Output ist jetzt Standard.

Update: Beispiel durch reales 3-Zeilen-Output ersetzen (aus `config/defaults.json`), kurze Erklärung der Zeilen.
Dashboard-Beispiel prüfen — zeigt noch `$25.63` Cost, ist das noch aktuell?

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress

