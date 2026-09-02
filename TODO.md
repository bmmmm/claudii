# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

> Die folgenden sechs stammen aus dem Audit vom 2026-09-02. Isolation, Hot-Path,
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

### Ein Parser für status-models statt sechs

**Type: Refactor** · **Complexity: Medium** · **Touches: lib/helpers.sh, lib/cmd/overview.sh, lib/cmd/perf.sh, lib/cmd/system.sh**

Sechs Kopien (`overview.sh:517-528`, `perf.sh:44-55`, `system.sh:255`,
`bin/claudii-status:101,124`, `lib/statusline.zsh:91`,
`bin/claudii-cc-statusline:1425`); `system.sh:255` forkt dabei ein `grep` **pro
Modell** statt einmal durchzulaufen. Die drei CLI-Kopien auf einen Helfer
ziehen. Die zwei Hot-Path-Kopien bleiben fork-frei eigenständig — bekommen aber
den Test, den die Kommentare (`cc-statusline:1439`, `:1483`, „kept in sync")
bisher durch Handarbeit ersetzen: gleicher Cache-Inhalt, gleicher String bei
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

### Theme fehlt fünf Commands, exit/return gemischt

**Type: Fix** · **Complexity: Small** · **Touches: bin/claudii, lib/cmd/config.sh, lib/cmd/system.sh**

`_cfg_init` wird von gc, pin, unpin, vibemap, vpnii, cc-statusline, update,
version, changelog übersprungen — damit läuft `_claudii_theme_load`
(`helpers.sh:76`) nie und diese Commands rendern in der Default-Palette,
unabhängig von `theme.name`. **Erst sichtbar machen** (unter einem
nicht-default Theme rendern), dann beheben. Dazu: `config.sh` und `system.sh`
nutzen `exit 1` (~25 Stellen) in gesourcten Dateien, andere `return 1`; `exit`
aus einem `_cmd_*` überspringt `_spinner_stop`.

### PID-Race der vier Background-Refresher

**Type: Fix** · **Complexity: Small** · **Touches: bin/claudii-cc-statusline, bin/claudii-*-refresh**

Der Dedup existiert viermal (`cc-statusline:1115`, `:1337`, `:1515`, `:1665`)
mit uneinheitlicher TTL (30 s, ci 120 s), und das Elternteil legt die PID-Datei
nie an — das Kind schreibt sie erst nach dem Fork (`claudii-ci-refresh:80`,
`claudii-status:71`, `claudii-cc-update-refresh:63`,
`claudii-bumpii-refresh:52`), also spawnen zwei Renders im Fenster beide.
Ein `_spawn_refresher <pidfile> <ttl> <cmd…>` extrahieren, der die Absicht atomar
vor dem Fork markiert.

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
