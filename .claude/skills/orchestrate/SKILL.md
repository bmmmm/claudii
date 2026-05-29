---
name: orchestrate
description: Orchestrate claudii TODO items with parallel subagents. Extends global /orchestrate with claudii-specific rules.
model: opus
effort: high
---

# claudii Orchestrator — Project Override

Extends the global `/orchestrate` skill. Follow all global rules and phases. This file adds claudii-specific extensions only — nothing here overrides global rules unless explicitly marked.

---

## Phase 1 additions

### 1.2 Pre-flight (claudii)

`scripts/cleanup-worktree.sh` is the project's safety net for orphaned `.claude/worktrees/agent-*` dirs. With Claude Code's native `isolation: "worktree"` auto-cleanup, it's only needed when the global Phase 1.2 sanity check actually finds zombies — not as a routine pre-flight step:

```bash
bash scripts/cleanup-worktree.sh --all             # all agent-* dirs
bash scripts/cleanup-worktree.sh agent-XXXXXXXX    # single
```
Already in `settings.local.json` allow-list — no sandbox override needed.

### 1.3 Agent aliases

Read available agent aliases from config:
```bash
jq -r '.agents | to_entries[] | "\(.key)\t\(.value.model)\t\(.value.effort)\t\(.value.description)"' config/defaults.json
```

Use these aliases in wave plan presentation (e.g. `sn` for Sonnet high, `op` for Opus high).

### 1.4 Statusline.zsh warnings

Before any wave touching `lib/statusline.zsh`, read the file and list which arrays/functions exist. Always append to those agent prompts:

> **Removed functions — do not re-add:** `_claudii_render_global_line`, `_claudii_render_session_lines`, `_claudii_build_title`. If you see references to these anywhere, delete them.
>
> **Current session arrays:** `_CLAUDII_SDASH_MODELS`, `_CLAUDII_SDASH_CTXS`, `_CLAUDII_SDASH_COSTS`, `_CLAUDII_SDASH_5HS`, `_CLAUDII_SDASH_R5HS` — no others.

---

## Phase 2 additions

### Agent Contract appendix (claudii)

Append after the global Agent Contract:

**By task type:**
- `Feature` → "Run `bash tests/run.sh`. Update man page (`man/man1/claudii.1`), completions (`completions/_claudii`), and `CHANGELOG.md` unreleased block to stay in sync. `test_docs.sh` verifies all four match."
- `Refactor` / `Docs` → "Run `bash tests/run.sh`. Delete orphaned `tests/test_<cmd>.sh` for any removed commands."

**Dashboard test preconditions** (for any agent touching session-dashboard code):
> Always set `session-dashboard.enabled = "on"` via `jq` in the test config AND set `_CLAUDII_CMD_RAN=1` inside the zsh subprocess before calling `_claudii_session_dashboard`. Without both, the dashboard exits early and tests pass vacuously.

---

## Phase 3 additions

### 3.3 Git permissions

`git merge`, `git branch -D`, `git worktree remove` are in `settings.local.json` allow-list — no sandbox override needed for these. If still blocked, use `dangerouslyDisableSandbox: true` on that specific call only. Never add `Bash(git *)` wildcard.

---

## Phase 4 additions

### Sync checklist (run before finalizing)

Any wave that touched commands must verify these five stay in sync:
1. `bin/claudii` — dispatch case
2. `completions/_claudii` — completion entries
3. `man/man1/claudii.1` — man page (single source of truth)
4. `CHANGELOG.md` — unreleased block
5. `tests/test_docs.sh` — auto-verifies 1–4

---

## claudii Rules

- **`(( ++var ))`** not `(( var++ ))` — post-increment of 0 exits 1 under `set -e` on bash 5.x (Ubuntu CI)
- **Background jobs:** always `( cmd & )` subshell pattern — `disown` and `no_monitor` still leak `[N] PID`
- **jq writes:** always atomic — `mktemp` + `mv`, never write directly to config file
- **Never commit `.claude/`** — gitignored, local-only; `settings.local.json` especially
- **Tests:** `bash tests/run.sh` — must stay green throughout all waves
