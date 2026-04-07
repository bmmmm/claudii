# claudii TODO

> Protokoll: siehe `/orchestrate` Skill. Agent-Aliases: `claudii agents` oder `config/defaults.json`.

---

## Pending

### Fix: bin/claudii dead parse fields + atomic write consistency

**Type: Refactor**
**Complexity: Small**
**Touches: `bin/claudii`**

Two isolated fixes in `bin/claudii`:

1. **Dead fields in `_parse_session_cache`** (lines 345, 362-363): `_PSC_model_id` and `_PSC_burn_eta` are parsed from the session cache but never read anywhere in the codebase. Remove them from the init block (line 345) and the case statement (lines 362-363).

2. **`_jq_update` uses `mv` without `-f`** (line 257): All other atomic writes in the codebase use `mv -f`. Change `mv "$_tmp" "$_file"` to `mv -f "$_tmp" "$_file"` for consistency.

---

### Refactor: sessions.sh model name helper + stale-session readability

**Type: Refactor**
**Complexity: Small**
**Touches: `lib/cmd/sessions.sh`**

Two readability/DRY fixes in `lib/cmd/sessions.sh`:

1. **Duplicate model name stripping** (lines 617-619 and 957-959): The pattern `"${var% (*context)}"` / `"${var% (*Context)}"` appears twice identically. Extract into a helper function `_strip_model_name()` in `lib/cmd/sessions.sh` and call it from both locations.

2. **Stale-session detection one-liner** (line 1136): 
   ```bash
   [[ -z "$_PSC_ppid" ]] || ! kill -0 "$_PSC_ppid" 2>/dev/null && (( ++_ov_stale ))
   ```
   Logic is correct but operator chaining is hard to read. Rewrite as explicit `if` block:
   ```bash
   if [[ -z "$_PSC_ppid" ]] || ! kill -0 "$_PSC_ppid" 2>/dev/null; then
     (( ++_ov_stale ))
   fi
   ```

---

### Blocked: Session-Fingerprint Teil 3 — Orchestrator nutzt Fingerprints

**Type: Feature**
**Complexity: Medium**
**Touches: Orchestrator-Skill**
**Blockiert:** Claude Code `--resume` im Agent-Tool nicht unterstützt.

---

### Fix: sessionline preserves pin flag

**Type: Fix**
**Complexity: Low**
**Touches: `bin/claudii-sessionline`**

`bin/claudii-sessionline` überschreibt Session-Cache-Files atomar (tmp+mv), liest dabei aber `pinned=1` nicht aus dem alten File.
Beim Schreiben des neuen Cache: altes File lesen, `pinned=`-Wert mergen, erst dann neu schreiben.

---

## In Progress

