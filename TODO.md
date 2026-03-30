# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### [DASHBOARD] Back to minimal — raus mit OSC2, rein mit bedingtem Rendering

**Type: Refactor + Fix**
**Complexity: Medium**
**Touches: `lib/statusline.zsh`, `tests/test_statusline.sh`**

OSC2 (Fenstertitel) ist die falsche Lösung — unsichtbar, terminal-abhängig, abgelehnt.
Das Doubling-Problem auf leerem Enter lösen wir anders: **conditioned rendering**.

#### Prinzip
Dashboard erscheint nur nach echten Commands (`preexec` setzt Flag).
Leerer Enter → kein Dashboard, plain PROMPT. Kein Cursor-Trick, kein OSC.

```
→ git:(main) git status          ← preexec: _CMD_RAN=1
[output...]
  Sonnet  76%  $0.66  5h:28%    ← precmd: _CMD_RAN=1 → zeige dashboard, setze =0
→ git:(main) |
→ git:(main) |                  ← leerer Enter: _CMD_RAN=0 → kein dashboard
→ git:(main) |                  ← nochmal: weiterhin kein dashboard
→ git:(main) claudii se         ← preexec: _CMD_RAN=1
[output...]
  Sonnet  76%  $0.67  5h:29%    ← dashboard aktualisiert
→ git:(main) |
```

Beim ersten Prompt nach Terminal-Start: `_CLAUDII_CMD_RAN=1` (initial), also Dashboard sichtbar.
Nach TRAPWINCH (Resize): `_CLAUDII_CMD_RAN=1` setzen + `zle reset-prompt`.

#### Dashboard-Format — MINIMAL, kein Fancy

Jede aktive Session = **eine Zeile**, left-aligned, dim:

```
  Sonnet  76%  $0.66  5h:28% ↺179m
  Opus    30%  $2.10
```

Regeln:
- Nur die 4 wichtigsten Felder: model, ctx%, cost, 5h-rate
- Reset-Countdown (`↺Xm`) nur wenn vorhanden und > 0
- Kein global line (5h/7d/cost aggregiert) — entfernt
- Keine Block-Chars (█░), kein ⚡, kein EAW-Problem
- Kein right-alignment, kein Padding, kein Overflow-Check
- KEIN `awk` oder externe Prozesse in der Render-Schleife
- PROMPT-Embedding: `"${dash_lines}${_CLAUDII_USER_PROMPT}"` — ZLE verwaltet alles

#### Was raus muss aus `lib/statusline.zsh`
- `_claudii_build_title` — weg
- `_CLAUDII_LAST_TITLE`, `_CLAUDII_TITLE_BUF` — weg
- OSC2 `printf '\033]2;...'` — weg
- `_claudii_render_global_line` (schon weg, sicherstellen)
- `_claudii_render_session_lines` (schon weg, sicherstellen)
- `_CLAUDII_DASH_*` Arrays für 7d_start, burn_eta — nicht mehr gebraucht → entfernen
- `[[ -t 1 ]]` Guard — nicht mehr gebraucht

#### Was neu rein muss
```zsh
typeset -gi _CLAUDII_CMD_RAN=1   # 1 = erstes Prompt zeigt Dashboard

function _claudii_preexec { _CLAUDII_CMD_RAN=1 }
add-zsh-hook preexec _claudii_preexec

function TRAPWINCH {
  _CLAUDII_CMD_RAN=1
  zle reset-prompt 2>/dev/null
}
```

#### `_claudii_dashboard` — komplett neu, ~40 Zeilen

```zsh
function _claudii_dashboard {
  local _dash_mode="..."
  if [[ "$_dash_mode" == "off" ]]; then
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi
  if [[ $_CLAUDII_CMD_RAN -eq 0 ]]; then
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi
  _CLAUDII_CMD_RAN=0

  _claudii_collect_sessions
  if (( _CLAUDII_DASH_COUNT == 0 )); then
    PROMPT="${_CLAUDII_USER_PROMPT}"; return
  fi

  local _dash_lines="" _now=${EPOCHSECONDS:-$(date +%s)}
  local _di
  for (( _di=1; _di<=_CLAUDII_DASH_COUNT; _di++ )); do
    local _line="  %F{8}${_CLAUDII_DASH_MODELS[$_di]}"
    local _ctx="${_CLAUDII_DASH_CTXS[$_di]%.*}"
    [[ -n "$_ctx" ]] && _line+="  ${_ctx}%%"
    local _cost="${_CLAUDII_DASH_COSTS[$_di]}"
    if [[ -n "$_cost" && "$_cost" != "0" ]]; then
      local _cf; _cf=$(printf '%.2f' "$_cost" 2>/dev/null) && _line+="  \$${_cf}"
    fi
    local _r5h="${_CLAUDII_DASH_5HS[$_di]}"
    if [[ -n "$_r5h" && "$_r5h" != "null" ]]; then
      _line+="  5h:${_r5h%.*}%%"
      local _rst="${_CLAUDII_DASH_R5HS[$_di]}"
      if [[ -n "$_rst" && "$_rst" =~ ^[0-9]+$ ]]; then
        local _rem=$(( _rst - _now ))
        (( _rem > 0 )) && _line+=" ↺$(( _rem / 60 ))m"
      fi
    fi
    _line+="%f"
    _dash_lines+="${_line}"$'\n'
  done

  PROMPT="${_dash_lines}${_CLAUDII_USER_PROMPT}"
}
```

#### Tests anpassen
- Alle OSC2-Tests entfernen (title-Tests)
- Conditional-Rendering testen: `_CLAUDII_CMD_RAN=0` → kein Dashboard in PROMPT
- Conditional-Rendering testen: `_CLAUDII_CMD_RAN=1` → Dashboard in PROMPT
- Format testen: model, ctx%, cost, 5h-rate in Output
- `dashboard off` → plain PROMPT
- Keine EAW/Overflow-Tests mehr nötig

**Done when:** `bash tests/run.sh` grün. Terminal zeigt Dashboard nach echten Commands, nicht auf leerem Enter.

---

### [QA] Kompletter Bug-Scan — alle Komponenten

**Type: Test + Fix**
**Complexity: Large**
**Touches: alle `lib/` Dateien, `bin/claudii`, `bin/claudii-sessionline`**

Aufwändiger Bug-Finding-Pass. Agent liest alle Files, sucht aktiv nach den folgenden Mustern:

#### Scan-Kategorie 1: zsh `local`-in-Loop-Leak
Bekannter Bug (gerade gefunden: `_c_fmt`): `local varname` innerhalb einer for/while-Schleife
druckt den aktuellen Wert auf stdout wenn die Variable bereits im Scope ist.

**Suche nach:** Jede `local` Deklaration INNERHALB eines `for/while`-Blocks in:
- `lib/statusline.zsh`
- `lib/config.zsh`
- `claudii.plugin.zsh`

**Fix:** `local` Deklarationen müssen VOR der Schleife stehen.

#### Scan-Kategorie 2: Arithmetik-Fehler bei leeren/invaliden Werten
Überall wo `$(( expr ))` auf Variablen operiert die leer oder "null" sein könnten:
- `_sf_age=$(( ${EPOCHSECONDS:-$(date +%s)} - _sf_mt ))` — was wenn `_sf_mt` leer?
- `_rem=$(( _gr5h_reset - _now ))` — was wenn `_gr5h_reset` nicht-numerisch?
- Alle `$(( ))` Ausdrücke mit session-cache-Feldern

**Fix:** Numerik-Guards `[[ "$var" =~ ^[0-9]+$ ]]` vor Arithmetik.

#### Scan-Kategorie 3: Subshell-Leaks in `precmd`-Pfad
Jeder `$(...)` Aufruf in `_claudii_statusline_render` oder `_claudii_dashboard`
ist ein Performance-Problem und potentieller Stdout-Leak.

**Suche nach:**
- Alle `$(...)` in `lib/statusline.zsh` — einzeln prüfen ob vermeidbar
- `$(date +%s)` → `$EPOCHSECONDS` bevorzugen wenn EPOCHSECONDS gesetzt
- `$(stat ...)` → zstat wenn `_CLAUDII_HAVE_ZSTAT`

**Ziel:** Null Subshells im heißen Render-Pfad (bei aktiver Session).

#### Scan-Kategorie 4: `bin/claudii-sessionline` Output-Leaks
`bin/claudii-sessionline` ist ein bash-Skript das JSON von Claude Code liest und
den Statusline-Text ausgibt. Es schreibt auch Session-Cache-Dateien.

**Suche nach:**
- Alle `local varname` innerhalb von Schleifen (bash hat denselben Bug nicht, aber Zuweisungen können leaken wenn in Command-Substitution)
- Alle `echo`/`printf` Aufrufe die nicht auf stdout sein sollten
- Alle `>&2` die fehlen (debug output das auf stdout landet)
- Variablen-Zuweisungen wie `x=$(cmd)` gefolgt von einem `echo $x` im falschen Kontext

#### Scan-Kategorie 5: `claudii cost` Today-Bug
`cutoff=$(( now - 86400 ))` ist ein 24h-Rolling-Window, nicht Mitternacht lokal.

**Fix (dual-path macOS/GNU):**
```bash
if date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s' >/dev/null 2>&1; then
  cutoff=$(date -j -f '%Y-%m-%d' "$(date '+%Y-%m-%d')" '+%s')
else
  cutoff=$(date -d "$(date '+%Y-%m-%d')" '+%s')
fi
```
Ort: `lib/cmd/sessions.sh`, `_cmd_cost()`, Zeile ~16.

#### Scan-Kategorie 6: `kill -0 "$s_ppid"` mit leerem PPID
In `_claudii_collect_sessions`:
```zsh
if [[ -n "$s_ppid" && "$s_ppid" != "0" && "$s_ppid" != "" ]]; then
  kill -0 "$s_ppid" 2>/dev/null || continue
fi
```
Die doppelte Prüfung (`-n` + `!= ""`) ist redundant. Aber: was wenn `$s_ppid`
Whitespace enthält? `kill -0 " "` wirft Fehler, der mit `2>/dev/null` unterdrückt
wird — korrekt, aber die Session wird dann behalten (kein `continue`).

**Prüfen:** Ist die Logik korrekt? Session ohne valide PPID → behalten oder verwerfen?

#### Scan-Kategorie 7: `_claudii_render_global_line` / `_claudii_render_session_lines` — Ghost-Code
Diese Funktionen wurden entfernt. Sicherstellen dass:
- Keine Referenz mehr in irgendeiner Datei vorkommt (`grep` über alle lib/ und tests/)
- Keine verwaisten Tests die diese Funktionen aufrufen

#### Scan-Kategorie 8: `claudii trends` edge cases
- Was wenn `history.tsv` Zeilen mit fehlenden Feldern hat?
- Was wenn `cost` in history.tsv `NaN` oder leer ist?
- Was wenn `sid` (session_id) leer ist? (`if (sid == "") next` deckt das ab — verifizieren)

#### Ergebnisse
Für jeden gefundenen Bug: Fix direkt committen. Am Ende `bash tests/run.sh` → 0 failures.
Report: welche Bugs gefunden, welche fixes angewandt.

---

### cost: "Today" = rolling 24h statt Kalender-Mitternacht

**Type: Fix**
**Complexity: Small**
**Touches: `lib/cmd/sessions.sh`**

Siehe Scan-Kategorie 5 oben — separates TODO falls der QA-Agent es nicht abdeckt.

---

## In Progress

