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

## In Progress

