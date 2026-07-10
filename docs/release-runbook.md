# Release runbook

Referenced from CLAUDE.md § "When releasing". `scripts/release.sh <version>` is
the only entry point.

## What the script does

Bumps `bin/claudii` VERSION + the man page + `CHANGELOG.md` (`[Unreleased]` →
`[vX.Y.Z]`), runs tests **twice** (pass 1 before the bump = full suite; pass 2
after the bump = only the version-aware test files, grep-discovered via
`VERSION=`/`CHANGELOG` — the bump touches nothing else), commits, pushes `main`
+ the tag to `origin` (Forgejo), then **watches CI by default** and exits
non-zero if the workflow fails (`--no-watch` to opt out for headless runs).
The double test-pass means a bump-induced failure aborts locally (files rolled
back, no tag) instead of surfacing only on CI.

## Dual-remote caveat (verified v0.26.0, 2026-07-10)

The `github` remote is **local** (no server-side Forgejo→GitHub push mirror
anymore), but the script pushes `origin` only and then polls GitHub for the
release workflow — that poll times out after 2min with "Workflow not visible —
mirror may be stuck" and exit 1, even though nothing is broken. Until
https://git.6bm.de/bsz/claudii/issues/1 lands (script pushes the local `github`
remote itself), finish manually:

```bash
git push github main && git push github vX.Y.Z
gh run watch "$(gh run list -R bmmmm/claudii --workflow release.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')" -R bmmmm/claudii --exit-status
```

The tag on GitHub triggers `.github/workflows/release.yml` (clean-env tests →
GitHub Release → Homebrew-tap sync). A failed run leaves the tag public with
**no** Release and **no** tap sync — a half-release; with `--no-watch` you must
confirm CI green yourself.

## Recovery from a half-release

(Tag pushed, CI failed, no artifact yet.) Fix + commit on main,
`git tag -f vX.Y.Z`, push main + the moved tag to **both** remotes:

```bash
git push origin main && git push origin vX.Y.Z --force
git push github main && git push github vX.Y.Z --force
```

The re-pushed tag re-triggers the workflow. Safe **only** because no artifact
was consumed (tap not synced, no Release created); never force-move a tag that
already shipped.
