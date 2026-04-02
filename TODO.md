# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Bug: Dashboard — fehlende Kosten bei Sessions mit cost=0

**Type: Bug**
**Complexity: Small**
**Touches: lib/statusline.zsh**

Session mit 48% ctx zeigt keine Kosten im Dashboard. Root cause: CC liefert manchmal
`total_cost_usd=0` statt dem echten Wert → `cost=0` im Cache → Dashboard-Bedingung
`"$_cost" != "0"` filtert ihn raus.

Fix: Fallback auf `history.tsv` wenn `cost=0` und `ctx_pct >= 5`. Lookup via `session_id`
(steht im Cache-File), neuester Eintrag aus `history.tsv` für diese Session-ID.

---

### Fix: `claudii status` — Incident-Anzeige: Timestamps, Zeilenumbrüche

**Type: Fix**
**Complexity: Small**
**Touches: lib/cmd/system.sh**

Probleme bei der Incident-Darstellung:
1. Timestamps pro Update-Eintrag fehlen oder sind falsch — `<small>` tags enthalten manchmal
   verschachtelte `<a>`/`<var>` Tags die nicht vollständig gestripped werden
2. Keine Leerzeile zwischen den einzelnen Updates → alles läuft zusammen
3. Lange Nachrichten wrappen nicht — `%-15s %s` format macht keine Umbrüche bei langen msgs
4. Beide Codepfade betroffen: RSS-Cache-Path (Status-Cache aus letztem Check) und
   Live-Fetch-Path (curl in `status live`)

Fix:
- Strip alle HTML-Tags aus `time_str` und `msg` (nicht nur `<var>`) via `gsub(/<[^>]*>/, "", x)`
- Leerzeile `printf '\n'` nach jedem Update-Eintrag
- `msg` auf 80 Zeichen umbrechen (fold-style via awk) mit Einrückung für Folgezeilen

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

## In Progress

