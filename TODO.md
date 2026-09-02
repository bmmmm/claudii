# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

> Die sechs Entdopplungs-Tasks aus dem Audit vom 2026-09-02 sind erledigt
> (84b2cd3, f9b914f, 796ab53, 3331012, 8bd36a2, 96e52e7). Was hier steht, sind
> die Reste, die die Tasks selbst offengelegt haben — jeweils weil ihre
> Touches-Liste den Call-Site nicht enthielt.

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

### Die 17 verbleibenden Commands unter den Exit-Code-Vertrag

**Type: Refactor** · **Complexity: Medium** · **Touches: lib/cmd/system.sh,
lib/cmd/sessions.sh, lib/cmd/display.sh, lib/cmd/config.sh, lib/cmd/omlx.sh,
lib/cmd/vpnii.sh, lib/cmd/vibemap.sh**

28 von 45 dispatchten Commands liefern bei unbekannter Option rc 2 mit
`claudii <cmd>: unknown option: <arg>`. Die übrigen stehen in `_AC_PENDING`
(`tests/test_arg_contract.sh`) und die Liste ist eine **Ratsche**: der Test
verlangt, dass ein Pending-Command den Vertrag noch *verfehlt*, geht also rot,
wenn jemand einen konvertiert ohne ihn aus der Liste zu nehmen. Verifiziert
2026-09-02, indem `perf` konvertiert und in der Liste gelassen wurde — genau
eine Assertion fiel. Kein Freibrief, nur eine Reihenfolge.

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
- **Cleaning the private identities out of the public history** (2026-09-02) — three
  of 703 commits on `main` were authored under a private identity instead of the
  public one: two as a local bot account (`9913b6a`, `311713a`) and one under a
  private mail address (`063e063`). Old commits also hold absolute home paths and
  the private forge host. (Deliberately not spelled out here: the pre-push gate
  scans tracked files, and naming the values would put them back into the working
  copy — `git log --format=%ae main | sort -u` shows them.) The **working copy is
  clean**; this is history alone, public for months. Removing it means
  `leak-response`: a history rewrite plus deleting and rebuilding the GitHub repo,
  because a force-push leaves the old objects reachable there. Price: **32
  releases** and the stars. Forks are 0, so the path is technically open —
  revisit only if the identities ever matter more than the release history.
