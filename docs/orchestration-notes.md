# Orchestration notes

Referenced from CLAUDE.md § "When orchestrating". Use `/orchestrate`; each
agent works its own `worktree-<name>` branch, orchestrator merges back to
main.

## Wave tags & revert

Set `git tag -f before-wave-N` before spawning, `git tag -f wave-N-done` after
tests are green.

Revert one merged agent: `git revert <merge-hash> -m 1 --no-edit`.

Revert a full wave — `git revert before-wave-N..HEAD` does NOT work once the
wave has `--no-ff` merge commits (fails with "commit … is a merge but no -m
option given"). Use instead: **unpushed** → `git reset --hard before-wave-N`;
**pushed** → revert each merge commit newest-first → `git revert -m 1
--no-edit <merge-N> … <merge-1>`.

## Known regressions to warn agents about

**Agents touching `lib/statusline.zsh`:** warn about removed functions
(`_claudii_render_global_line`, `_claudii_render_session_lines`,
`_claudii_build_title`).

**Dashboard test preconditions:** `jq '."session-dashboard".enabled = "on"'`
in config + `_CLAUDII_CMD_RAN=1` in zsh subprocess — both required or tests
pass vacuously.

## After completing planned work

If a `.claude/plans/*.md` file guided the work, delete it after implementing
— plan files auto-load into every future session, and stale ones produce
false "continue this work" prompts.
