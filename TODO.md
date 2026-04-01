# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Bug: `claudii cost` — Kosten falsch periodenzugeordnet (kein Tages-Delta)

**Type: Bug**
**Complexity: Medium**
**Touches: `lib/cmd/sessions.sh` `_cmd_cost_from_history()`**

**Problem:** Dedup nimmt letzten Eintrag pro Session (max cost) und weist den vollen Betrag dem Tag dieses Eintrags zu. Eine Session die am 28. März begann und heute noch aktiv ist → kompletter Betrag erscheint in April.

**Fix: Tägliche Deltas in awk**

Für jede Session pro Tag D:
```
cost_on_day_D = last_cost_for_sid_on_D - last_cost_for_sid_on_(D-1)
```
Erster Tag der Session: kein Vortag → voller Betrag dieses Tages als Delta.

**Awk-Strategie:**
1. Alle Einträge sortiert nach `sid + day` einlesen
2. Pro sid: letzten Kostenwert pro Tag merken (`last_cost[sid][day]`)
3. Delta berechnen: `delta = last_cost[sid][day] - last_cost[sid][prev_day]`
4. Delta dem jeweiligen Tag/Woche/Monat/Jahr zuordnen

---

### Update: `/orchestrate` Skill — Touches-basierte Parallelisierung + Branch-Isolation

**Type: Improvement**
**Complexity: Small**
**Touches: `.claude/skills/orchestrate/SKILL.md`**

Aktuell parallelisiert der Orchestrator nach Gefühl → Merge-Konflikte wenn zwei Agents dieselben Dateien anfassen.

**Fix:**
1. `**Touches:**`-Felder aus TODO-Items lesen vor Parallelisierung
2. Überlappende Touches → seriell; disjunkte Touches → parallel auf **eigenen Branches**
3. Merge nach jeder Welle seriell durch Orchestrator

---

### Refactor: "Dashboard" → "Session Dashboard" umbenennen

**Type: Refactor**
**Complexity: Large**
**Touches: `lib/statusline.zsh`, `lib/cmd/system.sh`, `bin/claudii`, `config/defaults.json`, `completions/_claudii`, `man/man1/claudii.1`, `CLAUDE.md`, `tests/`**

Config-Key: `dashboard.enabled` → `session-dashboard.enabled` (Migration-Fallback).
CLI: `claudii dashboard [on|off]` → `claudii session-dashboard [on|off]`, deprecated Alias behalten.
Suppress-Logik: String-Match → `_CLAUDII_SHOWED_SESSIONS=1` Flag.

**Hinweis:** Zuletzt angehen — viele Stellen.

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress
