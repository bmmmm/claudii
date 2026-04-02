# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Tests: Token-Tracking in cost + trends

**Type: Docs/Tests**
**Complexity: Small**
**Touches: tests/test_cost.sh, tests/test_trends.sh**

Add test coverage for the token feature added in v0.9.0+:
- `claudii cost` pretty output contains "tok" when history.tsv has token columns (cols 7+8)
- `claudii trends` pretty output contains "tok" in day rows and Total line
- Fallback: old history entries without token columns → no "tok" in output (graceful)
- JSON output: `trends --json` contains `tokens` field on each day object

Use a synthetic `history.tsv` fixture with known token values to assert exact output.

---

### CHANGELOG: Unreleased block für v0.10.0

**Type: Docs**
**Complexity: Small**
**Touches: CHANGELOG.md**

Add `## [Unreleased]` section above `## [0.9.0]` documenting changes since v0.9.0:
- `feat(cost,trends)`: Token usage per period — `input_tok`/`output_tok` in history.tsv, running_spend delta per day, displayed as `X.XM tok` after each Total line
- `feat(release)`: Homebrew tap auto-update + SHA256 + Full Changelog link in release notes
- `refactor(release)`: Simplified release notes (SHA256 + compare URL only)

---

### cost.week_start + System-Timezone für epoch_to_date

**Type: Feature**
**Complexity: Medium**
**Touches: lib/cmd/sessions.sh, lib/cmd/display.sh, config/defaults.json**

Two related config/correctness fixes for cost + trends date handling:

**1. `cost.week_start`** — configurable week start day, default `"monday"`.
Add `"cost": { "week_start": "monday" }` to `config/defaults.json`.
Map string → DOW (monday=1..sunday=7). General formula:
`days_back = (today_dow - ws_dow + 7) % 7` — works for any start day.
Apply in `_cmd_cost_from_history()` (week_start_str) and `_cmd_trends()` (this_week_start_ts, last_week boundaries, _week_days loop start).

**2. System timezone** — `epoch_to_date()` currently divides by 86400 UTC, which misattributes sessions near midnight for users in non-UTC timezones.
Compute offset: `date +%z | awk '{s=(substr($0,1,1)=="-")?-1:1; print s*(substr($0,2,2)*3600+substr($0,4,2)*60)}'`
Pass as `-v tz_offset=N` to awk; `epoch_to_date` uses `int((ts + tz_offset) / 86400)`.
Drop all `TZ=UTC` prefixes from bash `date` calls in both files (they were only there for consistency with awk UTC).

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

### sessionline: Multi-line + Segment-Refactor

**Type: Feature + Refactor**
**Complexity: Medium**
**Touches: bin/claudii-sessionline, config/defaults.json, man/man1/claudii.1, tests/test_sessionline.sh, CHANGELOG.md**

Refactor `bin/claudii-sessionline` to support configurable multi-line output in Claude Code. Fixes two efficiency bugs in the same pass.

#### Why

Claude Code renders whatever the statusLine command writes to stdout — multiple lines just work. Currently we drop info at narrow terminals (adaptive truncation). Multi-line solves this cleanly. Additionally two subprocess inefficiencies were found during competitor analysis.

#### Efficiency fixes (do first, they simplify the refactor)

**1. `date +%s` called twice** — lines ~247 and ~286. Set `_now=$(date +%s)` once near the top of the script (after the jq parse block, before the output section) and replace both call sites with `$_now`.

**2. `bc` in `_tok()`** — `$(echo "scale=1; $n/1000" | bc)` is a two-process pipeline. Replace with a single awk call:
```bash
_tok() {
  local n=$1
  [[ -z "$n" || "$n" == "null" ]] && return
  if   (( n >= 1000000 )); then awk "BEGIN{printf \"%.1fM\",$n/1000000}"
  elif (( n >= 1000    )); then awk "BEGIN{printf \"%.1fK\",$n/1000}"
  else printf "%d" "$n"
  fi
}
```

#### Segment pre-computation

Replace the current monolithic `out` string with individual pre-computed segment variables. Each segment is computed once before the layout loop — empty string if data missing/null:

```bash
_seg_model=""       # bold model name + optional effort
_seg_context=""     # colored bar + usable% + ⚡cache%  (see below)
_seg_cost=""        # cyan $X.XX
_seg_rate5h=""      # colored 5h:X% ↺Xm  (existing logic, extracted)
_seg_rate7d=""      # colored 7d:X% ↺Xd  (existing logic, extracted)
_seg_tokens=""      # DIM Xk↑ Xk↓
_seg_lines=""       # green +X red -X  (only when > 0)
_seg_dur=""         # DIM Xm / Xh Xm
_seg_eta=""         # DIM ETA:Xm  (only when _burn_eta set and > 0)
_seg_worktree=""    # DIM worktree_name  (only when set)
_seg_agent=""       # DIM @agent_name   (only when set)
```

`_seg_rate5h` and `_seg_rate7d` encapsulate the existing delta + countdown logic (move it, don't rewrite it).

#### `_seg_context` — Usable % + ⚡ zusammengeführt

`_seg_cache` entfällt als eigenes Segment. Cache-Hit-Ratio wandert in `_seg_context` — beide erzählen die "Context-Effizienz"-Geschichte und gehören zusammen:

```
████████░░ 95% ⚡73%
```

**Berechnung Usable %:** statt `used/max` → `used / (max × 0.8)`.
Beispiel: 76% raw bei 200k max → 152k used / 160k usable = 95% usable.
Die Warnschwellen bleiben: grün <70%, gelb 70-89%, rot 90+ — greifen jetzt aber früher (bei 72% raw statt 90% raw), was die ehrlichere Warnung ist.

**⚡ bleibt** als Suffix in `_seg_context`, nur wenn cache_read > 0 (wie heute).
**Segment-ID** im Layout-Config: `context-bar` (unverändert, kein Breaking Change).

Der `cache-pct`-Eintrag in der Layout-Loop-Case-Tabelle bleibt als Alias erhalten (falls jemand es explizit konfiguriert hat), gibt aber denselben `_seg_context`-Inhalt zurück.

#### Layout config

Hardcode the default layout as a constant (no jq needed in common case):

```bash
_DEFAULT_LINES="model,context-bar,cost,rate-5h,rate-7d
tokens,cache-pct,lines-changed,duration,burn-eta,worktree,agent"
```

Read user override from config file (0 extra jq calls if no custom config, 1 if yes):

```bash
_lines_raw="$_DEFAULT_LINES"
_config_file="${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json"
if [[ -f "$_config_file" ]]; then
  _from_cfg=$(jq -r 'if .statusline.lines then (.statusline.lines | .[] | join(",")) else empty end' \
    "$_config_file" 2>/dev/null)
  [[ -n "$_from_cfg" ]] && _lines_raw="$_from_cfg"
fi
```

#### Layout loop (replaces entire current output section)

```bash
RST="\033[0m"; DIM="\033[2m"; SEP="${DIM} │${RST} "

while IFS= read -r _line_segs; do
  [[ -z "$_line_segs" ]] && continue
  _line_out=""; _first=1
  IFS=',' read -ra _segs <<< "$_line_segs"
  for _seg in "${_segs[@]}"; do
    case "$_seg" in
      model)        _val="$_seg_model"    ;;
      context-bar)  _val="$_seg_context"  ;;
      cost)         _val="$_seg_cost"     ;;
      rate-5h)      _val="$_seg_rate5h"   ;;
      rate-7d)      _val="$_seg_rate7d"   ;;
      tokens)       _val="$_seg_tokens"   ;;
      cache-pct)    _val="$_seg_cache"    ;;
      lines-changed) _val="$_seg_lines"   ;;
      duration)     _val="$_seg_dur"      ;;
      burn-eta)     _val="$_seg_eta"      ;;
      worktree)     _val="$_seg_worktree" ;;
      agent)        _val="$_seg_agent"    ;;
      *)            _val=""               ;;
    esac
    if [[ -n "$_val" ]]; then
      if (( _first )); then _line_out="$_val"; _first=0
      else _line_out+="${SEP}${_val}"; fi
    fi
  done
  [[ -n "$_line_out" ]] && echo -e "\033[0m${_line_out}"
done <<< "$_lines_raw"
```

Remove the entire `(( _cols >= 60 ))` / `(( _cols >= 80 ))` / `(( _cols > 100 ))` block — replaced by layout loop above.

#### config/defaults.json

Add:
```json
"statusline": {
  "lines": [
    ["model", "context-bar", "cost", "rate-5h", "rate-7d"],
    ["tokens", "cache-pct", "lines-changed", "duration", "burn-eta", "worktree", "agent"]
  ]
}
```

#### man/man1/claudii.1

Add `statusline.lines` config key documentation. Valid segment IDs: `model`, `context-bar`, `cost`, `rate-5h`, `rate-7d`, `tokens`, `cache-pct`, `lines-changed`, `duration`, `burn-eta`, `worktree`, `agent`. To restore 1-line behavior: set lines to a single array.

#### tests/test_sessionline.sh

- Default 2-line output: verify stdout has exactly 2 non-empty lines
- Single-line config: `statusline.lines` with 1 array → 1 output line
- Empty segments skipped: worktree/agent absent when not in JSON input
- burn-eta visible: session with duration + rate_5h → `_seg_eta` appears on line 2
- `_tok()` correctness: 999→"999", 1000→"1.0K", 1500→"1.5K", 1000000→"1.0M"
- No `bc` in script: `grep -v 'bc'` or verify output without bc installed

#### CHANGELOG.md

Add to unreleased block:
- `feat(sessionline)`: Configurable multi-line output — `statusline.lines` in config.json
- `refactor(sessionline)`: Segment pre-computation, remove COLUMNS-based truncation
- `fix(sessionline)`: Eliminate duplicate `date +%s` call and `bc` subprocess in `_tok()`
- `feat(sessionline)`: burn-eta, worktree, agent now visible (on line 2 by default)

---

## In Progress

