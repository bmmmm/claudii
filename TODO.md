# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Self-Improvement Loop — `/usage` Per-Category Auto-Tuning (Wave 2+)

**Wave 1 shipped 2026-05-27** — `attribution_skills` / `attribution_plugins` accumulated by `lib/insights.jq` (schema_version 3), aggregated by `bin/claudii-insights merge`, surfaced by `claudii skills-cost [--days N] [--plugins] [--json]`. First real data on `bin/claudii`: top spenders are `memory-gc` ($95.88 / 746 calls) and `orchestrate` ($35.93 / 325 calls) across 30d.

**Wave 2 candidates (manual iteration after looking at real tables):**
- **Subagent attribution** — needs `isSidechain` + `parentUuid` chain design after seeing real data
- **MCP-tool attribution** — design decision: anteilig vs full-row cost
- **`model` column** currently shows `mixed` always — surface dominant model per skill from `.models` correlation
- **Outlier heuristics** beyond simple 3× median — none flagged on real data, threshold may need tuning or per-skill-category bands
- **Skill-edit auto-suggestion** (`claudii self-improve`) — judgment-LLM-call, not mechanical transform
- **Auto-apply** (`--apply`) — last, after suggestions are trusted

---

### `terminalSequence` Notifications from claudii hooks

**Type: Feature**
**Complexity: Small**
**Touches: hooks (new or existing), `lib/cmd/system.sh`**
**Triggered by:** CC v2.1.141 added `terminalSequence` field in Hook JSON Output — Desktop Notifications, Window Titles, Bells without controlling terminal.

**Use-cases:**
- ClaudeStatus model down → window-title `[!opus down] claude`
- Burn-ETA critical (<30min to depletion) → bell + title
- Session ended → notification "session ended, cost $X.YZ" — use the **`SessionEnd` hook** (CC v2.1.169), not Stop: fires on real session termination, has matchers for the end reason (`clear`/`resume`/`logout`/`prompt_input_exit`/`other`), cannot block (observability-only — exactly our case)

**Schema (verified against code.claude.com/docs/en/hooks, 2026-06-12):** hook stdout JSON `{"terminalSequence": "<escape sequence>"}`; allowlist is OSC `0`/`1`/`2` (window/icon title), OSC `9` (iTerm2/ConEmu/Windows Terminal/WezTerm notify, incl. `9;4` taskbar progress), OSC `99` (Kitty), OSC `777` (urxvt/**Ghostty**/Warp), bare BEL. Anything else is rejected silently. Works in tmux/screen, requires CC ≥2.1.141. Ghostty (our terminal) → OSC 777: `printf '\033]777;notify;%s;%s\007' "$title" "$body"`.

---

### Backlog — Compaction counter

**Type: Feature**
**Complexity: Small-medium**
**Touches: session cache schema, `bin/claudii-cc-statusline`**

ccstatusline shipped #282 (compaction counter). Pairs naturally with our
burn-ETA — "how many compactions did this session survive?". Inner layer.
(Defer-until-v0.18.4-6 note dropped — we're past v0.19.0, no longer gated.)

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert (extern):** Claude Code unterstützt `--resume` im Agent-/Task-Tool nicht — kein Permission-Gate, nichts freizugeben. Wartet auf Upstream-Feature.

---

## Decided against (2026-05-20)

- **Peak-Hours-Indicator** — the 5am-11am PT weekday peak window Anthropic
  announced in Dec 2024 is no longer in effect. Competitors that still surface
  it (claude-pulse, PeakClaude) are tracking a defunct rule. Nothing to mirror.
- **Active statusLine-hijack-detection** — `claudii doctor` already checks
  `.statusLine.command` (`lib/cmd/system.sh:400-411`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.
