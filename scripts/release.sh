#!/usr/bin/env bash
# claudii release — bump version, run tests locally (before AND after the bump),
# push tag, watch CI until the workflow is green. CI does the publish.
#
# Usage: scripts/release.sh <version> [--dry-run] [--no-watch] [--allow-version-mismatch]
#
# Tests run twice on purpose: pass 1 before the bump is the full suite (fast
# gate, no files mutated yet); pass 2 after the bump re-runs only the
# version-aware test files (those reading VERSION= or CHANGELOG) — the bump
# only rewrites bin/claudii VERSION, the man-page version string, and
# CHANGELOG.md, so re-validating the whole suite adds nothing. Without pass 2
# a bump-induced failure only shows up on CI after the tag is already public.
#
# After the tag push, .github/workflows/release.yml handles:
#   1. Tests on clean Ubuntu env
#   2. Release notes extraction from CHANGELOG.md
#   3. Tarball SHA256 computation
#   4. GitHub Release creation
#   5. Homebrew-tap Formula sync     ← needs `secrets.TAP_TOKEN`
#   6. SHA256 + Compare-link in notes
#
# One-time setup for the Homebrew tap sync:
#   * Create a fine-grained PAT with `contents:write` scoped to bmmmm/homebrew-tap.
#   * Add it as the `TAP_TOKEN` secret on this repo (Settings → Secrets and variables
#     → Actions). If the secret is missing, the workflow logs a warning and skips
#     the tap sync — you can update the Formula manually after the release.
#
# The script blocks on `gh run watch` by default and exits non-zero if the
# workflow fails — a failed run leaves the tag public with no Release and no
# tap sync (half-release), so watching is part of the release, not optional.
# Pass --no-watch only for headless runs where something else watches CI.

set -euo pipefail
CLAUDII_HOME="${CLAUDII_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

# ── Args ──────────────────────────────────────────────────────────────────────
_usage="Usage: $0 <version> [--dry-run] [--no-watch] [--allow-version-mismatch]"
_dry_run=0; _watch=1; _allow_mismatch=0; _rel_version=""
for _arg in "$@"; do
  case "$_arg" in
    --dry-run)  _dry_run=1 ;;
    --watch)    _watch=1 ;;   # default; kept for backward compatibility
    --no-watch) _watch=0 ;;
    --allow-version-mismatch) _allow_mismatch=1 ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)         echo "Unknown flag: $_arg" >&2; echo "$_usage" >&2; exit 1 ;;
    *)          _rel_version="$_arg" ;;
  esac
done
[[ -z "$_rel_version" ]] && { echo "$_usage" >&2; exit 1; }
_rel_version="${_rel_version#v}"
[[ "$_rel_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Error: version must be X.Y.Z (got: $_rel_version)" >&2; exit 1; }
_rel_tag="v${_rel_version}"

# ── UI helpers ────────────────────────────────────────────────────────────────
_start() { printf '┌ %s\n' "$1"; }
_step()  { printf '├ %s\n' "$1"; }
_end()   { printf '└ %s\n' "$1"; }
_ok()    { printf "│ \033[0;32m✓\033[0m %s\n" "$1"; }
_fail()  { printf "│ \033[0;31m✗\033[0m %s\n" "$1"; }

_dry_marker=""; (( _dry_run )) && _dry_marker=" \033[38;5;240m[dry-run]\033[0m"
printf '\n  \033[0;36mclaudii release\033[0m \033[38;5;213m%s\033[0m%b\n\n' "$_rel_tag" "$_dry_marker"

# Resolve gh repo — needed for actions URL + watch
_remote=$(git -C "$CLAUDII_HOME" remote get-url origin 2>/dev/null || echo "")
if [[ "$_remote" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  _gh_owner="${BASH_REMATCH[1]}"; _gh_repo="${BASH_REMATCH[2]}"
else
  _gh_owner=bmmmm; _gh_repo=claudii
fi
_actions_url="https://github.com/${_gh_owner}/${_gh_repo}/actions"
_release_url="https://github.com/${_gh_owner}/${_gh_repo}/releases/tag/${_rel_tag}"

# ── Pre-flight ────────────────────────────────────────────────────────────────
_start "Pre-Flight"

if ! git -C "$CLAUDII_HOME" diff --quiet HEAD -- 2>/dev/null \
   || ! git -C "$CLAUDII_HOME" diff --cached --quiet 2>/dev/null; then
  _fail "Working tree dirty — commit or stash first"
  exit 1
fi
_ok "Working tree clean"

if git -C "$CLAUDII_HOME" rev-parse "$_rel_tag" >/dev/null 2>&1; then
  _fail "Tag $_rel_tag already exists"
  echo "  Delete with: git tag -d $_rel_tag && git push origin :refs/tags/$_rel_tag" >&2
  exit 1
fi
_ok "No existing tag $_rel_tag"

_branch=$(git -C "$CLAUDII_HOME" branch --show-current 2>/dev/null || echo main)
if [[ "$_branch" == "main" ]]; then
  _ok "On main"
else
  _ok "On non-main branch '$_branch' (releasing from there)"
fi

# CHANGELOG: [Unreleased] must exist and carry at least one entry — releasing
# an empty block would tag a release with empty notes.
_unreleased=$(awk '/^## \[Unreleased\]/{f=1;next} f&&/^## /{exit} f' "$CLAUDII_HOME/CHANGELOG.md")
if ! grep -q '^## \[Unreleased\]' "$CLAUDII_HOME/CHANGELOG.md"; then
  _fail "CHANGELOG.md has no [Unreleased] block"
  exit 1
fi
if ! grep -q '^- ' <<< "$_unreleased"; then
  _fail "CHANGELOG.md [Unreleased] block is empty — nothing to release"
  exit 1
fi
_ok "CHANGELOG [Unreleased] has entries"

# SemVer plausibility: '### Added' in the unreleased block requires a MINOR
# (or MAJOR) bump; only Fixed/Changed → PATCH. Catches the most likely human
# error (under-bumping a feature release). Override: --allow-version-mismatch.
_cur_version=$(grep '^VERSION=' "$CLAUDII_HOME/bin/claudii" | head -1 | tr -d '"' | cut -d= -f2)
IFS=. read -r _cur_maj _cur_min _ <<< "$_cur_version"
IFS=. read -r _new_maj _new_min _ <<< "$_rel_version"
if grep -q '^### Added' <<< "$_unreleased" \
   && (( _new_maj == _cur_maj && _new_min == _cur_min )); then
  if (( _allow_mismatch )); then
    _ok "Version $_rel_version is a PATCH bump despite '### Added' (override accepted)"
  else
    _fail "[Unreleased] has '### Added' but $_cur_version → $_rel_version is only a PATCH bump"
    echo "  SemVer rule: Added → bump MINOR (${_cur_maj}.$(( _cur_min + 1 )).0)." >&2
    echo "  Pass --allow-version-mismatch to release $_rel_version anyway." >&2
    exit 1
  fi
else
  _ok "Version $_rel_version matches unreleased content (current: $_cur_version)"
fi

# ── Tests, pass 1 (BEFORE bump — fast gate; nothing mutated yet, no rollback) ──
_step "Tests (pre-bump)"
if (( _dry_run )); then
  _ok "Tests — skipped (dry-run)"
else
  if _test_out=$(bash "$CLAUDII_HOME/tests/run.sh" --summary 2>&1); then
    _passed=$(echo "$_test_out" | grep -oE '[0-9]+ passed' | tail -1)
    _ok "Tests green (${_passed:-?})"
  else
    _fail "Tests failed — aborting (no files mutated)"
    echo "$_test_out" | tail -10 >&2
    exit 1
  fi
fi

# ── Version Bump ──────────────────────────────────────────────────────────────
_step "Version Bump"
_bin_file="$CLAUDII_HOME/bin/claudii"
_man_file="$CLAUDII_HOME/man/man1/claudii.1"
_changelog="$CLAUDII_HOME/CHANGELOG.md"
_today=$(date +%Y-%m-%d)

if (( _dry_run )); then
  _ok "bin/claudii VERSION → $_rel_version (dry-run)"
  _ok "man/man1/claudii.1 → $_rel_version (dry-run)"
  _ok "CHANGELOG.md [Unreleased] → [$_rel_tag] (dry-run)"
else
  sed -i.bak "s/^VERSION=.*/VERSION=\"${_rel_version}\"/" "$_bin_file"; rm -f "${_bin_file}.bak"
  grep -q "^VERSION=\"${_rel_version}\"$" "$_bin_file" \
    || { _fail "bin/claudii VERSION bump failed"; exit 1; }
  _ok "bin/claudii VERSION → $_rel_version"

  sed -i.bak "s/\"claudii [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\"/\"claudii ${_rel_version}\"/" "$_man_file"
  rm -f "${_man_file}.bak"
  grep -q "\"claudii ${_rel_version}\"" "$_man_file" \
    || { _fail "man/man1/claudii.1 bump failed"; exit 1; }
  _ok "man/man1/claudii.1 → $_rel_version"

  grep -q '^## \[Unreleased\]' "$_changelog" \
    || { _fail "CHANGELOG.md has no [Unreleased] block"; exit 1; }
  awk -v ver="$_rel_tag" -v date="$_today" '
    /^## \[Unreleased\]/ {
      print "## [Unreleased]"; print ""; print "---"; print ""
      print "## [" ver "] \342\200\224 " date
      next
    }
    { print }
  ' "$_changelog" > "${_changelog}.tmp.$$" && mv "${_changelog}.tmp.$$" "$_changelog"
  _ok "CHANGELOG.md [Unreleased] → [$_rel_tag] — $_today"
fi

# ── Tests, pass 2 (AFTER bump — authoritative for the bumped files) ──────────
# The bump rewrites CHANGELOG.md ([Unreleased] → [vX.Y.Z]) and the VERSION. Tests
# that read those for the *current* version (e.g. the `changelog` notes check)
# only validate the exact state that gets tagged HERE — pass 1 ran against the
# pre-bump tree and can stay green while this fails. CI would catch it, but only
# after the tag is already public (a half-release). Since the bump touches only
# VERSION / man-page version / CHANGELOG.md, pass 2 re-runs just the test files
# that read those (grep-discovered, falls back to the full suite if none match).
# On failure, roll the three bumped files back to HEAD (no commit exists yet)
# and abort: no commit, no tag.
_step "Tests (post-bump)"
if (( _dry_run )); then
  _ok "Tests post-bump — skipped (dry-run)"
else
  _va_tests=()
  while IFS= read -r _t; do
    [[ -n "$_t" ]] && _va_tests+=("$_t")
  done < <(grep -lE '\bVERSION=|CHANGELOG' "$CLAUDII_HOME"/tests/test_*.sh 2>/dev/null || true)
  if (( ${#_va_tests[@]} == 0 )); then
    # No version-aware test found — discovery broke; run the full suite instead.
    _test_cmd=(bash "$CLAUDII_HOME/tests/run.sh" --summary)
    _scope="full suite (no version-aware tests found)"
  else
    _test_cmd=(bash "$CLAUDII_HOME/tests/run.sh" --summary "${_va_tests[@]}")
    _scope="${#_va_tests[@]} version-aware file(s)"
  fi
  if _test_out=$("${_test_cmd[@]}" 2>&1); then
    _passed=$(echo "$_test_out" | grep -oE '[0-9]+ passed' | tail -1)
    _ok "Tests green post-bump (${_passed:-?}, $_scope)"
  else
    _fail "Tests failed after bump — rolled back, no commit/tag/push made"
    git -C "$CLAUDII_HOME" checkout -- "$_bin_file" "$_man_file" "$_changelog" 2>/dev/null || true
    echo "$_test_out" | tail -10 >&2
    exit 1
  fi
fi

# ── Tag & Push ────────────────────────────────────────────────────────────────
_step "Tag & Push"
if (( _dry_run )); then
  _ok "Commit — skipped (dry-run)"
  _ok "Push branch — skipped (dry-run)"
  _ok "Tag $_rel_tag — skipped (dry-run)"
  _ok "Push tag — skipped (dry-run)"
else
  git -C "$CLAUDII_HOME" add "$_bin_file" "$_man_file" "$_changelog"
  git -C "$CLAUDII_HOME" commit -m "chore(release): bump version to $_rel_version" >/dev/null
  _ok "Committed"

  git -C "$CLAUDII_HOME" push origin "$_branch" >/dev/null 2>&1 \
    || { _fail "Push branch failed"; exit 1; }
  _ok "Branch '$_branch' pushed"

  git -C "$CLAUDII_HOME" tag -a "$_rel_tag" -m "$_rel_tag"
  if ! git -C "$CLAUDII_HOME" push origin "$_rel_tag" >/dev/null 2>&1; then
    _fail "Push tag failed — local tag deleted"
    git -C "$CLAUDII_HOME" tag -d "$_rel_tag" >/dev/null 2>&1 || true
    exit 1
  fi
  _ok "Tag $_rel_tag pushed"
fi

# ── CI Handoff ────────────────────────────────────────────────────────────────
_step "CI"
if (( _dry_run )); then
  _ok "CI handoff — skipped (dry-run)"
  _end "Dry-run complete — no changes made"
  printf '\n'
  exit 0
fi

if (( _watch )) && command -v gh >/dev/null 2>&1; then
  # The tag reaches GitHub via the Forgejo→GitHub mirror — the run can take
  # well over 30s to register. Poll up to 2 minutes, then block on watch.
  _run_id=""
  for _try in $(seq 1 24); do
    _run_id=$(gh run list --workflow=release.yml --limit=5 \
      --json databaseId,headBranch \
      --jq ".[] | select(.headBranch==\"${_rel_tag}\") | .databaseId" 2>/dev/null \
      | head -1 || true)
    [[ -n "$_run_id" ]] && break
    sleep 5
  done
  if [[ -n "$_run_id" ]]; then
    _ok "Workflow #${_run_id} started — watching"
    printf '\n'
    if gh run watch "$_run_id" --exit-status --repo "${_gh_owner}/${_gh_repo}"; then
      _ok "Workflow green"
      _ok "Release: $_release_url"
    else
      _fail "Workflow failed — see $_actions_url/runs/${_run_id}"
      echo "  Half-release: tag is public, no GitHub Release / tap sync yet." >&2
      echo "  Recover: fix + commit on main, git tag -f $_rel_tag, push main," >&2
      echo "  then git push origin $_rel_tag --force (mirror re-triggers CI)." >&2
      exit 1
    fi
  else
    _fail "Workflow not visible after 2min — mirror may be stuck"
    echo "  Check $_actions_url — release is NOT confirmed until CI is green." >&2
    exit 1
  fi
else
  (( _watch )) || _ok "Watch disabled (--no-watch) — confirm CI yourself"
  command -v gh >/dev/null 2>&1 || _ok "gh not found — cannot watch CI"
  _ok "Tag pushed — CI runs the rest. Release is NOT done until CI is green:"
  _ok "Workflow:  $_actions_url"
  _ok "Release:   $_release_url"
fi

_end "Done"
printf '\n'
