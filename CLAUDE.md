@AGENTS.md

Claude Code delta. The canon is `AGENTS.md` (imported above); nothing from it is repeated here.

## Project skills

`/shape` — hygiene + TODOs · `/orchestrate` — implement TODOs · `/explore` — ecosystem scan

## When orchestrating

Use `/orchestrate` — each agent works its own `worktree-<name>` branch,
orchestrator merges back to main. Wave-tag/revert recipes, known
`lib/statusline.zsh` / dashboard-test regressions, and the post-work
plan-file cleanup reminder: **`docs/orchestration-notes.md`**.

## Memory Types

This project overrides the default memory type set. Use these instead of the harness defaults:

- **`rule`** — evergreen discipline; reads like "always/never do X", no incident story needed.
- **`lesson`** — incident-based learning; the story is load-bearing — stripped of it, the rule loses force.
- **`project`** — fast-decaying initiative/state info; convert relative dates to absolute when saving.
- **`reference`** — pointers to external systems (URLs, repos, dashboards).
- **`user`** — language profile and collaboration preferences for bmmmm.

`feedback` is retired in this project — re-type any remaining `feedback_*.md` to `rule` or `lesson` on next touch.

**Slug convention (overrides the harness's kebab-case default):** a memory's frontmatter `name:` MUST equal its filename without `.md` (snake_case), and `[[links]]` use that exact slug — the harness's kebab-case default produces dangling `[[links]]` here (a whole collection drifted that way once). Pick the filename first, then set `name:` to match it verbatim.
