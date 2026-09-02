# Release runbook

Referenced from CLAUDE.md § "When releasing". `scripts/release.sh <version>` is
the only entry point.

## Always `--dry-run` first

`scripts/release.sh <version> --dry-run` walks every gate and prints what it
would do, without touching a file. CLAUDE.md requires it; it is also the only
way to see the SemVer verdict before it is a commit.

## Pre-flight gates, in order

1. Working tree clean (staged *and* unstaged).
2. Tag `vX.Y.Z` does not exist yet.
3. `CHANGELOG.md` has a `## [Unreleased]` block with at least one `- ` entry.
4. **SemVer plausibility.** If the unreleased block carries a `### Added` and
   the new version is only a PATCH bump, the script refuses. `### Fixed` /
   `### Changed` alone are fine as a PATCH. Override with
   `--allow-version-mismatch` — for a deliberate under-bump, not to get past a
   surprise. The gate does not look at `### Removed` or `### Security`, so a
   MAJOR-worthy change is still your call.
5. Tests, pass 1: the full suite, before anything is written.

## What the script does

Bumps **four** files — `bin/claudii` VERSION, the man page, `docs/index.html`
and `CHANGELOG.md` (`[Unreleased]` → `[vX.Y.Z]`). They live in one
`_bumped_files` array (`scripts/release.sh:161`) that the bump, the rollback
and `git add` all read, because they used to be three separate lists and
`docs/index.html` was missing from the `add`: v0.27.0 got tagged with a 0.26.0
landing page against a 0.27.0 binary, which the version gate in
`tests/test_docs.sh` then failed on a fresh checkout of the tag.

Then runs tests **twice** (pass 1 before the bump = full suite; pass 2
after the bump = only the version-aware test files, grep-discovered via
`VERSION=`/`CHANGELOG` — the bump touches nothing else), commits, pushes `main`
+ the tag to `origin` (Forgejo), then **watches CI by default** and exits
non-zero if the workflow fails (`--no-watch` to opt out for headless runs).
The double test-pass means a bump-induced failure aborts locally (files rolled
back, no tag) instead of surfacing only on CI.

## Dual-remote (fixed, issue #1)

The `github` remote is **local** (no server-side Forgejo→GitHub push mirror
anymore). The script detects a local `github` remote and, after pushing
`origin`, pushes main + the release tag there too — before polling GitHub for
the release workflow. No manual GitHub push needed anymore. If the `github`
remote is missing, the script skips this step (prints and continues — there is
nothing to push to). If the remote exists but the push to it fails — e.g. the
pre-push leak-gate blocks it — the script fails loudly and prints the git/hook
output, instead of silently polling a GitHub repo that never got the tag.

The tag on GitHub triggers `.github/workflows/release.yml` (clean-env tests →
GitHub Release → Homebrew-tap sync). A failed run leaves the tag public with
**no** Release and **no** tap sync — a half-release; with `--no-watch` you must
confirm CI green yourself.

## Two green things that prove nothing

**A green release run is not a green matrix.** `.github/workflows/release.yml`
is a single job on `ubuntu-latest` under the default locale. The
macOS/`de_DE.UTF-8` matrix lives in `.github/workflows/ci.yml` and fires only
on `push: branches: [main]`. So the tagged tree is only matrix-verified through
the `main` run of the same commit — check that run, not the release run.

**A green release run is not a synced tap.** If `TAP_TOKEN` is missing or
expired, the tap step prints a `::warning::` annotation and `exit 0`. The step
is green, the run is green, and `scripts/release.sh`'s `gh run watch` only
reads the run status — so it reports success. The proof is the formula in
`bmmmm/homebrew-tap`: it must name the new version, and its `sha256` must match
the real tarball (`curl -sL <url> | shasum -a 256`).

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
