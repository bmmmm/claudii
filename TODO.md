# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### v0.18.3 — `claude agents --json` adapter

**Type: Feature**
**Complexity: Small (Steps 1+2 only — see plan)**
**Touches: `lib/helpers.sh`, `lib/cmd/sessions.sh`, `tests/`**

Replace `kill -0 $ppid` liveness check in `_parse_session_cache` with a lookup
against `claude agents --json` (verified to exist in Claude Code v2.1.145). Adds
authoritative process status, eliminates the 24h PID-recycling guard, and surfaces
`kind: background` sessions with a `[bg]` badge in `claudii se`.

Detailed plan: `.claude/plans/v0.18.3-claude-agents-adapter.md` (local only —
delete after implementing).

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
