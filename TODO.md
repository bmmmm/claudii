# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Feature: `claudii trends` — rolling 7d window, today-first, total sessions, median + trend stats

**Type: Feature**
**Complexity: Medium**
**Touches: lib/trends.awk, lib/cmd/display.sh, man/man1/claudii.1, tests/test_trends.sh**

Four connected changes to `claudii trends` pretty output (JSON output untouched):

**1. "Last 7 days" rolling window (replaces "This week Mon–Sun")**

In `lib/cmd/display.sh`: change `week_days` construction from `this_monday..today`
to a rolling 7-day window `(today - 6)..today`. Pass `week_start` (date string of 6 days ago)
as a new `-v week_start=` arg to awk instead of `this_mon`. Update awk's `tw_cost/tw_sessions/tw_tok`
accumulator to use `d >= week_start` instead of `d >= this_mon`.

In `lib/trends.awk`: change header label from `"This week (Mon–Sun)"` to `"Last 7 days"`.

**2. Today at top (reverse chronological order)**

In the pretty output loop, change `for (i = 1; i <= n_days; i++)` to
`for (i = n_days; i >= 1; i--)`. "Today" is already substituted when `d == today`.

**3. Total line: add session count + model breakdown**

Currently: `Total   $372.38  2.9M tok`
Target:    `Total   $372.38  2.9M tok  (21 sessions, 5 Opus, 16 Sonnet)`

`tw_sessions` is already computed. Accumulate `tw_model_sessions[model]` alongside
`tw_sessions` in the same loop that computes `tw_cost`. Then format like day lines.

**4. Two fun-fact lines after "Costliest day"**

```
  Costliest day: 2026-03-29 ($141.75)
  Median:        $42.30/day (30d)
  Trend:         $74/day (7d) vs $38/day (30d) ↑+95%
```

**Median** — collect all `day_cost[d]` where `d >= thirty` into an array,
insertion-sort it (BSD awk has no `asort()`; n ≤ 30 so O(n²) is fine), pick middle value.

**Trend** — `avg_7d = tw_cost / 7`. `avg_30d`: sum all 30d day_cost / 30 (fixed denominator,
not days-with-data — gives honest burn rate including zero days).
`trend_pct = int((avg_7d - avg_30d) / avg_30d * 100 + 0.5)`.
Arrow: `↑` if positive, `↓` if negative, `→` if zero.
Format: `$X/day (7d) vs $X/day (30d) ↑+X%` — use dim for the "vs 30d" part.

**Documentation** — update `man/man1/claudii.1` `claudii trends` description to reflect:
rolling 7-day window, today-first, median and trend stats. One short paragraph is enough.

**Tests** — update `tests/test_trends.sh`:
- Header now "Last 7 days" not "This week"
- Today appears before older days in output
- Total line contains session count
- "Median:" and "Trend:" lines present in output

Run `bash tests/run.sh` and fix any failures. Baseline: **504 passed, 0 failed**.

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress

