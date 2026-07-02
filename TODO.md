# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### cc-statusline/status: input-robustness guards + fork diet round 2

**Type: Refactor**
**Complexity: Small**
**Touches: bin/claudii-cc-statusline, bin/claudii-status, tests/test_sessionline.sh**

Three verified-low findings from the 2026-07-02 full-repo review, batched
because they share files (the confirmed bugs were fixed in a063260):
- `read -r json` (cc-statusline stdin read) takes only the first line; if
  Claude Code ever emits pretty/multi-line JSON the parse silently falls to the
  empty fallback. Slurp all of stdin without adding a fork.
- claudii-status pipes untrusted status-API text through `echo "$_search_text"`
  (two sites) — leading `-e`/`-n` or backslashes in incident text get munged;
  use `printf '%s\n'`.
- The proxy segment jq in cc-statusline runs on every render whenever
  `.claude/settings.local.json` exists — gate it on the segment being in the
  active layout, like remotes/git-sync/ruler already are.

Done when: output unchanged on current payloads (full suite green under
`/bin/bash` 3.2) plus a regression test feeding multi-line JSON to
cc-statusline.

### Context-bar rounding parity (floor vs round-half-up)

**Type: Refactor**
**Complexity: Small**
**Touches: lib/helpers.sh, tests/test_helpers.sh**

`_render_ctx_bar` floors its fill (`_pct*8/100`) while every sibling renderer
rounds half-up (`bar_filled` in lib/fmt.awk, `_bar_filled` in lib/render.sh) —
the 8-cell session context bar under-fills by up to one cell (62% → 4/8 where
the shared rule gives 5/8). Switch to round-half-up and pin the boundary
values (e.g. 56%, 62%) in a parity test against `bar_filled`.

Done when: 62% renders 5/8, parity test passes, full suite green.

### Session-cache lost-update race (FIXME anchored in code)

**Type: Refactor**
**Complexity: Medium**
**Touches: bin/claudii-cc-statusline, bin/claudii-stop-hook, tests/**

See `FIXME(race)` above the session-cache write in bin/claudii-cc-statusline:
the statusline's read-modify-write can clobber `next_cron_at`/`bg_tasks`
written by claudii-stop-hook between the `_cache_get` reads and the `mv`
(lost update — atomic per file, no corruption, needs a Stop hook mid-render).
Fix by merge-on-write (re-read the hook-owned keys immediately before the
`mv`) or a tiny lock; keep the hot path fork-free either way.

Done when: an interleaved-write test (statusline render racing a stop-hook
write) preserves the hook's keys, and the FIXME is removed.

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert (extern):** Claude Code unterstützt `--resume` im Agent-/Task-Tool nicht — kein Permission-Gate, nichts freizugeben. Wartet auf Upstream-Feature.

---

## Decided against

- **Orphan-cache GC for insights** (2026-06-12) — 389 of 654 cache files are orphans
  (source JSONL deleted by Claude Code's `cleanupPeriodDays`; CC never touches our
  cache dir). They are the only cost history beyond CC's transcript retention and
  total 2.6 MB — deleting them removes the feature they are. The `.schema` marker
  (schema gate in `bin/claudii-insights`) already ended the rebuild-loop they caused.
  If size ever matters: opt-in retention in `claudii gc` (last_seen-based, dry-run
  default), not before.
- **Peak-Hours-Indicator** (2026-05-20) — the 5am-11am PT weekday peak window Anthropic
  announced in Dec 2024 is no longer in effect. Competitors that still surface
  it (claude-pulse, PeakClaude) are tracking a defunct rule. Nothing to mirror.
- **Active statusLine-hijack-detection** (2026-05-20) — `claudii doctor` already checks
  `.statusLine.command` (`lib/cmd/system.sh:400-411`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.
