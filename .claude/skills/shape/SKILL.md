---
name: shape
description: Hygiene-check for claudii repo. Checks memories, skills, docs, settings, CI, Formula, README for staleness and inconsistencies.
model: haiku
effort: high
---

# claudii Shape — Hygiene Checker

Check repo health, find stale references, report problems. No TODO planning (that's `/orchestrate` Step 0).

claudii extends the Claude Code Statusline — inward (Sessionline) and outward (RPROMPT, sessions, cost, decision support). No other tool covers both layers.

## When NOT to use

- User wants to **plan or implement features** → `/orchestrate`
- User wants **ecosystem research** → `/explore`
- Tiny isolated fix → just do it

## Step 1: Load context

1. `TODO.md` — current tasks
2. `ROADMAP.md` — backlog

## Step 2: Hygiene check

Check on every `/shape` invocation:

- **Memories** (`memory/`) — stale entries? Contradictions?
- **Skills** (`.claude/skills/`) — dead references? Overlaps?
- **CLAUDE.md** — architecture table, naming, rules still current?
- **TODO.md / ROADMAP.md** — bloated? Duplicates?
- **`.claude/settings.local.json`** — dead `Bash(...)` entries? Cross-check every entry against actual files and commands in `bin/`. Stale entry = command or script no longer exists.
- **`.github/workflows/`** — do CI/release/wiki workflows reference commands or files that no longer exist?
- **`Formula/claudii.rb`** — caveats, bin wrappers (`%w[...]`), and test assertions still match current commands and files?
- **`README.md`** — example commands still valid? Referenced features still exist?

For each problem found — root cause loop:
1. **Symptom** — what's broken
2. **Root cause** — why did this happen? Which process failed?
3. **Fix** — concrete action (direct fix or TODO for `/orchestrate`)

## Step 3: Release check

```bash
last_tag=$(git describe --tags --abbrev=0 --match "v*" 2>/dev/null)
feat_count=$(git log ${last_tag}..HEAD --oneline --grep="^feat" | wc -l)
```

- `>= 1 feat` → mention: "Release possible (N new features)"
- `>= 3 feat` → recommend: "We should release"

## Step 4: Present results

Concise:
- **Hygiene findings** — only if something was found
- **Release?** — only if relevant

## Rules

- **No ecosystem scanning** — that's `/explore`
- **No task planning, no waves, no agents** — that's `/orchestrate`
- **Token efficiency** — no bloat
- **Communicate with user in their language, code and docs in English**
- **Commit before handing off** — before `/orchestrate`, all pending changes must be committed
