# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agents: `claudii agents` (definiert unter `agents` in der User-Config; `config/defaults.json` liefert keine mehr).

---

## Pending

> Stand 2026-11-25, nach dem Aufräum-Audit (Branch
> `t3/repo-audit-dead-code-cleanup`). Was hier steht, ist offen und an
> aktuellem Code geprüft.

### Die vier positionellen awk-Programme auf HC[] ziehen

**Type: Refactor** · **Complexity: Small** · **Touches: lib/cmd/week.sh,
lib/cmd/overview.sh, lib/window.awk, lib/window_bounds.awk,
lib/window_history.awk, lib/usage_spark.awk**

`lib/history_cols.awk` deklariert die 11 Spalten jetzt an einer Stelle, aber
`window.awk`, `window_bounds.awk`, `window_history.awk` und `usage_spark.awk`
lesen weiter positionell — ihre Call-Sites (`week.sh`, `overview.sh`) lagen
außerhalb der Touches, und awk hat kein include: ohne `-f lib/history_cols.awk`
am Call-Site würde jeder Feldzugriff still zu `$0` degradieren. Also: das `-f`
an den vier Call-Sites ergänzen, dann die Positionen durch `HC[]` ersetzen.
`tests/test_history_cols.sh` pinnt die heutigen Positionen gegen das Schema und
wird rot, wenn die Umstellung danebengeht.

### Die sechs verbleibenden Commands unter den Exit-Code-Vertrag

**Type: Refactor** · **Complexity: Medium** · **Touches: lib/cmd/system.sh,
lib/cmd/insights.sh, tests/test_arg_contract.sh, man/man1/claudii.1**

33 von 39 dispatchten Commands liefern bei unbekannter Option rc 2 mit
`claudii <cmd>: unknown option: <arg>` (Helfer `_cli_unknown_opt`,
`lib/cmd/insights.sh`) und bei `-h`/`--help` die Usage mit rc 0. Offen sind
`cc-statusline`, `claudestatus`, `insomnii`, `session-dashboard`, `status`
(alle `lib/cmd/system.sh`) und `session` (`lib/cmd/insights.sh`) — heute rc 1
auf `--bogus`. Sie stehen in `_AC_PENDING` (`tests/test_arg_contract.sh`), und
die Liste ist eine **Ratsche**: der Test verlangt, dass ein Pending-Command den
Vertrag noch *verfehlt*, geht also rot, wenn jemand einen konvertiert, ohne
ihn aus der Liste zu nehmen. Mit jedem konvertierten Command die Zählung in
der Man-Page (EXIT STATUS, „33 of the 39“) mitziehen.

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
  `.statusLine.command` (`_cmd_doctor` in `lib/cmd/system.sh`) and warns on foreign values.
  Running the check on every render would mean jq-on-settings.json per precmd,
  which is the wrong perf trade for an edge case.
