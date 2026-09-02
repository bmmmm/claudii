# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

> Die folgenden vier stammen aus dem Audit vom 2026-09-02 (PID-Race und
> Theme sind erledigt, 84b2cd3 / f9b914f). Isolation, Hot-Path,
> Gates und Docs-Drift sind erledigt und committet; das hier ist der Rest der
> Entdopplung, datei-disjunkt geschnitten für `/orchestrate`.

### Ein Normalizer für history.tsv, benannte Spalten

**Type: Refactor** · **Complexity: Medium** · **Touches: lib/cmd/cost.sh, lib/cmd/display.sh, lib/*.awk**

`lib/cmd/cost.sh:57-70` und `lib/cmd/display.sh:66-79` sind byte-nah identische
Stage-1-Normalizer (Unterschied: cost hält `raw=$2`, trends `api_dur=$9`). Die
11 Spaltenpositionen stehen zusätzlich in acht Dateien hartkodiert
(`window.awk`, `window_bounds.awk`, `window_history.awk`, `trends.awk`,
`usage_spark.awk`, `forecast.awk` plus die zwei Inline-Kopien) — eine zwölfte
Spalte kostet heute acht Edits. Ziel: ein `lib/history_rows.awk` plus ein
`lib/history_cols.awk` mit benannten Indizes, per mehrfachem `-f` dazugeladen.
CLAUDE.md-Regel beachten: die `-v`-Bindungen am Call-Site gehören in den
Kopfkommentar. **Abnahme:** `cost`, `trends`, `week`, `cost --window`
byte-identisch vorher/nachher auf demselben Cache.

### Ein Modell→Label-Mapping statt vier

**Type: Refactor** · **Complexity: Medium** · **Touches: lib/cmd/insights.sh, lib/cmd/overview.sh, lib/model_tier.awk, lib/tier.jq**

`_insights_model_label` (`insights.sh:56-72`, versioniert), `_norm_model_short`
(`overview.sh:13-21`, nur Tier), `tier_label()` (`model_tier.awk`), `tier()`
(`tier.jq`). Sichtbare Folge: `overview.sh:461/521` und `perf.sh:53` rendern
dieselben Cache-Daten mit verschiedenen Labels. Die beiden bash-Kopien
zusammenlegen; awk und jq bleiben sprachbedingt eigen, bekommen aber einen Test,
der alle drei gegen eine feste Modell-Liste auf Gleichheit prüft.

### Ein Parser für status-models statt acht

**Type: Refactor** · **Complexity: Medium** · **Touches: lib/helpers.sh, lib/cmd/overview.sh,
lib/cmd/perf.sh, lib/cmd/system.sh, lib/cmd/display.sh, bin/claudii-status,
bin/claudii-cc-statusline, lib/statusline.zsh**

Acht Kopien, nicht sechs — nachgemessen 2026-09-02, nachdem die alte Liste
zwei davon nicht kannte: `display.sh:162` (`cs_cache`) fehlte ganz, und
`system.sh` hat **zwei** Stellen (`:327`, `:390`), nicht eine. Dazu
`overview.sh:507`, `perf.sh:35`, `claudii-status:23`, `cc-statusline:1480`,
`statusline.zsh:91`. Zeilennummern driften — nach den Variablennamen suchen,
nicht nach der Zahl.

`system.sh` forkt ein `grep` **pro Modell** statt einmal durchzulaufen; das ist
der konkrete Preis, nicht nur die Ästhetik. Die CLI-Kopien auf einen Helfer in
`lib/helpers.sh` ziehen. Die zwei Hot-Path-Kopien (`cc-statusline`,
`statusline.zsh`) bleiben absichtlich eigenständig und fork-frei — sie
bekommen aber den Test, den die „kept in sync“-Kommentare bisher durch
Handarbeit ersetzen: gleicher Cache-Inhalt rein, gleicher String raus, bei
allen dreien.

### Ein Arg-Parser, ein Exit-Code-Vertrag

**Type: Refactor** · **Complexity: Large** · **Touches: bin/claudii, lib/cmd/*.sh**

Sechs Parser-Stile; `--bogus` liefert je nach Command rc 0, 1 oder 2 mit drei
Präfixen; `cost --bogus` schweigt ganz. Die Aufrufkonvention des Dispatchers ist
uneinheitlich (`"$@"` vs `"${@:2}"` vs gar nichts), weshalb jeder Parser den
Command-Namen selbst überspringen muss. Auf `_insights_window`
(`insights.sh:112`) vereinheitlichen, `skills-cost.sh:118`, `week.sh:407`,
`cost.sh:531` migrieren. Die unerreichbaren `--json`-Arme (`week.sh:420`,
`skills-cost.sh:126`) löschen — `bin/claudii:23-30` strippt das Flag vorher.
Vertrag: unbekannte Option → rc 2, `claudii <cmd>: unknown option: <arg>` auf
stderr, plus ein Test über alle Commands. **Achtung:** rc 0 → 2 ist eine
Verhaltensänderung und gehört unter `### Changed`.

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
