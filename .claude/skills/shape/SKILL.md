---
name: shape
description: Hygiene-check for claudii repo. Checks memories, skills, docs, config, settings, CI, README for staleness and inconsistencies.
model: opus
effort: low
---

# claudii Shape — Hygiene Checker

Find stale references and cross-file drift, root-cause them, report. Static checks only — no feature planning (→ `/orchestrate`), no ecosystem research (→ `/explore`), no test runs. Tiny isolated fix → just do it.

## Step 1: Scan

Read each source below and cross-check every reference it makes against what actually exists in `bin/`, `lib/`, `scripts/`, `config/`. A pointer to a removed command/script/file is the typical finding.

- **CLAUDE.md** — architecture table, naming, command-role table, rules still match the code?
- **`config/defaults.json`** — agent aliases/descriptions current? A description naming an old model version is drift (see CLAUDE.md "When a new Claude model ships").
- **Memories** — read `MEMORY.md` index first (`~/.claude/projects/-Users-bma-offline-coding-claudii/memory/`); stale entries, contradictions, wrong file/flag names?
- **Skills** (`.claude/skills/`) — dead references? overlaps? model frontmatter sane (main-thread skill → `opus`/`inherit`, never `sonnet`)?
- **TODO.md / ROADMAP.md** — bloated, duplicated, or already-shipped items?
- **`.claude/settings.local.json`** — every `Bash(...)` entry still maps to a real command/script? Plus stale `.gitignore` rules for removed files. Local-only — never commit, never `git add .claude/`.
- **`.github/workflows/`** — reference commands or files that no longer exist?
- **README.md** — example commands + referenced features still valid?
- **`scripts/release.sh`** — drifted from the Homebrew tap it syncs (URL/SHA/caveats)?

## Step 2: Root-cause each finding

1. **Symptom** — what's stale/inconsistent
2. **Root cause** — which process let it drift?
3. **Fix** — direct fix now, or a TODO line for `/orchestrate`

## Step 3: Release check

```bash
last_tag=$(git describe --tags --abbrev=0 --match "v*" 2>/dev/null)
git log ${last_tag:+$last_tag..}HEAD --oneline --grep="^feat" | wc -l   # new feat commits
```

- `>= 1 feat` → mention "Release possible (N features)"
- `>= 3 feat` → recommend "We should release"

Bump type follows the CHANGELOG unreleased block, not the commit count: any `### Added` → MINOR, only `### Fixed`/`### Changed` → PATCH.

## Step 4: Report

Concise — surface only what was found, skip clean areas:
- **Hygiene findings** — grouped, each with its fix
- **Release?** — only if relevant

## Rules

- Static hygiene only — leave ecosystem scans to `/explore`, planning/waves/agents to `/orchestrate`
- Commit all pending changes before handing off to `/orchestrate`
- Talk to the user in their language; code and docs in English
