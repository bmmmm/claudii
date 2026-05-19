# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### v0.18.4 — `github` field in sessionline

**Type: Feature**
**Complexity: Small (~1-2h)**
**Touches: `bin/claudii-cc-statusline`, `lib/visual.sh` (symbol), `man/man1/claudii.1`, `tests/test_cc_statusline_preset.sh`**

Claude Code 2.1.145+ ships a `github` block in the statusLine JSON stdin
when invoked inside a repo with detected GitHub remote (and an open PR for
the current branch, if any). Surface `<owner>/<repo>` or
`<owner>/<repo>#<pr_number>` as a new sessionline segment so users always
see which PR they're touching without leaving the editor.

Steps:
1. Verify schema — start `claude` in a repo, capture stdin JSON, confirm
   field name + nesting. Docs: `docs.anthropic.com/en/docs/claude-code/status-bar`.
2. Add `github` segment to `bin/claudii-cc-statusline` segment renderer.
3. Add a glyph constant in `lib/visual.sh` (e.g. octocat or `⎇`).
4. Update `config/defaults.json` if we want it in the default layout.
5. Update man page segment table + `test_cc_statusline_preset.sh`.
6. CHANGELOG Unreleased + release v0.18.4.

### v0.18.5 — `session_crons` in `claudii se`

**Type: Feature**
**Complexity: Medium (~2-4h)**
**Touches: `bin/claudii-cc-statusline` (cache write), `lib/cmd/sessions.sh`, `lib/helpers.sh`, `man/man1/claudii.1`, tests**

Claude Code 2.1.140+ exposes `background_tasks` and `session_crons` in
Stop / SubagentStop hook JSON. Persist `next_cron_at` into the session
cache, render the next scheduled wake in `claudii se`. Outer-layer
decision signal — answers "when does this session wake itself again?".

### v0.18.6 — Pace-Indicator tri-state in sessionline

**Type: Feature**
**Complexity: Medium**
**Touches: `bin/claudii-cc-statusline`, `lib/cmd/sessions.sh`, sessionline layout**

Closes the long-open gap from watchlist Key Insights (Z. 90 in
memory/watchlist.md). We already compute burn-ETA — turn it into a
tri-state ahead/on-pace/behind indicator that surfaces in sessionline.
Builds on existing cache, no new data source. Direct response to
claude-pace (193 stars) gaining traction.

### Backlog — Compaction counter

**Type: Feature**
**Complexity: Small-medium**
**Touches: session cache schema, `bin/claudii-cc-statusline`**

ccstatusline shipped #282 (compaction counter). Pairs naturally with our
burn-ETA — "how many compactions did this session survive?". Inner layer.
Defer until after v0.18.4-6.

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## Decided against (2026-05-20)

- **Peak-Hours-Indicator** — the 5am-11am PT weekday peak window Anthropic
  announced in Dec 2024 is no longer in effect. Competitors that still surface
  it (claude-pulse, PeakClaude) are tracking a defunct rule. Nothing to mirror.
- **Active statusLine-hijack-detection** — `claudii doctor` already checks
  `.statusLine.command` (`lib/cmd/system.sh:400-411`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.

---

## In Progress
