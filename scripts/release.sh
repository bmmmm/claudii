#!/bin/bash
# claudii release — bump version, run tests, tag, push, and create a GitHub release
# Usage: scripts/release.sh <version> [--dry-run]

set -euo pipefail

# Determine CLAUDII_HOME from the location of this script
CLAUDII_HOME="${CLAUDII_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

# ── Parse flags ──
_dry_run=0
_rel_version=""
for _rel_arg in "${@:1}"; do
  case "$_rel_arg" in
    --dry-run) _dry_run=1 ;;
    -*)        echo "Unknown flag: $_rel_arg"; echo "Usage: scripts/release.sh <version> [--dry-run]"; exit 1 ;;
    *)         _rel_version="$_rel_arg" ;;
  esac
done

if [[ -z "$_rel_version" ]]; then
  echo "Usage: scripts/release.sh <version> [--dry-run]"
  echo "  Example: scripts/release.sh 0.7.0"
  exit 1
fi

# Strip leading v if provided
_rel_version="${_rel_version#v}"
_rel_tag="v${_rel_version}"

# Parse remote URL early — needed for CI HEAD check and release creation
_remote_url=$(git -C "${CLAUDII_HOME}" remote get-url origin 2>/dev/null || echo "")
if [[ "$_remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  _gh_owner="${BASH_REMATCH[1]}"
  _gh_repo="${BASH_REMATCH[2]}"
else
  _gh_owner="" _gh_repo=""
fi

# ── Helpers ──
_rel_box_start() { printf '┌ %s\n' "$1"; }
_rel_box_item()  { printf "│ %b %s\n" "$1" "$2"; }
_rel_box_sep()   { printf '├ %s\n' "$1"; }
_rel_box_end()   { printf '└ %s\n' "$1"; }

_rel_ok()   { _rel_box_item "\033[0;32m✓\033[0m" "$1"; }
_rel_fail() { _rel_box_item "\033[0;31m✗\033[0m" "$1"; printf '\n'; }
_rel_spin() { _rel_box_item "⏳" "$1"; }

printf '\n'
[[ "$_dry_run" -eq 1 ]] && printf '  \033[38;5;240m[dry-run]\033[0m '
printf '\033[0;36mclaudii release\033[0m \033[38;5;213m%s\033[0m\n\n' "$_rel_tag"

# ── Pre-flight ──
_rel_box_start "Pre-Flight"

# 1. Working tree must be clean
_git_dirty=$(git -C "$CLAUDII_HOME" status --porcelain 2>/dev/null)
if [[ -n "$_git_dirty" ]]; then
  _rel_fail "Working tree nicht sauber — bitte erst committen"
  git -C "$CLAUDII_HOME" status --short >&2
  exit 1
fi
_rel_ok "Working tree sauber"

# 2. No existing tag
_existing_tag=$(git -C "$CLAUDII_HOME" tag -l "$_rel_tag")
if [[ -n "$_existing_tag" ]]; then
  _rel_fail "Tag $_rel_tag existiert bereits"
  echo "  git tag -d $_rel_tag  (lokal löschen)" >&2
  echo "  git push origin :refs/tags/$_rel_tag  (remote löschen)" >&2
  exit 1
fi
_rel_ok "Kein offener Tag $_rel_tag"

# 3. CI check: HEAD commit must have a completed, successful CI run
if command -v gh >/dev/null 2>&1 && [[ -n "$_gh_owner" ]]; then
  _head=$(git -C "$CLAUDII_HOME" rev-parse HEAD)
  _ci_checks=$(gh api "repos/${_gh_owner}/${_gh_repo}/commits/${_head}/check-runs" \
    --jq '[.check_runs[] | select(.name | startswith("test"))] | {
      total: length,
      failed: [.[] | select(.conclusion == "failure")] | length,
      pending: [.[] | select(.status != "completed")] | length
    }' 2>/dev/null || echo "")
  if [[ -n "$_ci_checks" ]]; then
    _ci_failed=$(echo "$_ci_checks" | jq -r '.failed')
    _ci_pending=$(echo "$_ci_checks" | jq -r '.pending')
    _ci_total=$(echo "$_ci_checks" | jq -r '.total')
    if [[ "$_ci_failed" -gt 0 ]]; then
      _rel_fail "CI: ${_ci_failed}/${_ci_total} test jobs failed for HEAD ${_head:0:7}"
      echo "  Fix CI failures before releasing — check https://github.com/${_gh_owner}/${_gh_repo}/commit/${_head}/checks" >&2
      exit 1
    elif [[ "$_ci_pending" -gt 0 ]]; then
      _rel_fail "CI: ${_ci_pending} test jobs still pending for HEAD ${_head:0:7} — wait for CI to complete"
      exit 1
    elif [[ "$_ci_total" -gt 0 ]]; then
      _rel_ok "CI: all ${_ci_total} test jobs green for HEAD ${_head:0:7}"
    fi
  fi
fi

# ── Version Bump ──
_rel_box_sep "Version Bump"

_bin_file="$CLAUDII_HOME/bin/claudii"
_man_file="$CLAUDII_HOME/man/man1/claudii.1"
_changelog="$CLAUDII_HOME/CHANGELOG.md"
_today=$(date +%Y-%m-%d)

if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "bin/claudii VERSION → $_rel_version (dry-run)"
  _rel_ok "man/man1/claudii.1 → $_rel_version (dry-run)"
  _rel_ok "CHANGELOG.md [Unreleased] → [$_rel_version] (dry-run)"
else
  # Bump VERSION in bin/claudii
  sed -i '' "s/^VERSION=.*/VERSION=\"${_rel_version}\"/" "$_bin_file"
  _new_bin=$(grep '^VERSION=' "$_bin_file" | tr -d '"' | cut -d= -f2)
  [[ "$_new_bin" == "$_rel_version" ]] || { _rel_fail "bin/claudii VERSION bump fehlgeschlagen"; exit 1; }
  _rel_ok "bin/claudii VERSION → $_rel_version"

  # Bump version in man page
  sed -i '' "s/\"claudii [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\"/\"claudii ${_rel_version}\"/" "$_man_file"
  _new_man=$(grep -oE 'claudii [0-9]+\.[0-9]+\.[0-9]+' "$_man_file" | head -1 | awk '{print $2}')
  [[ "$_new_man" == "$_rel_version" ]] || { _rel_fail "man page version bump fehlgeschlagen"; exit 1; }
  _rel_ok "man/man1/claudii.1 → $_rel_version"

  # Promote [Unreleased] → [X.Y.Z — DATE] and insert new empty [Unreleased] block
  if ! grep -q '^\#\# \[Unreleased\]' "$_changelog"; then
    _rel_fail "CHANGELOG.md hat keinen [Unreleased]-Block"
    exit 1
  fi
  awk -v ver="$_rel_tag" -v date="$_today" '
    /^## \[Unreleased\]/ {
      print "## [Unreleased]"
      print ""
      print "---"
      print ""
      print "## [" ver "] \342\200\224 " date
      next
    }
    { print }
  ' "$_changelog" > "${_changelog}.tmp" && mv "${_changelog}.tmp" "$_changelog"
  _rel_ok "CHANGELOG.md [Unreleased] → [$_rel_tag] — $_today"
fi

# ── Tests ──
_rel_box_sep "Tests"

if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "Tests — skipped (dry-run)"
else
  _test_out=$(bash "$CLAUDII_HOME/tests/run.sh" 2>&1)
  _test_exit=$?
  if [[ $_test_exit -eq 0 ]]; then
    _test_passed=$(echo "$_test_out" | grep -oE '[0-9]+ passed' | tail -1)
    _rel_ok "Tests grün ($_test_passed)"
  else
    _rel_fail "Tests fehlgeschlagen — version bump rückgängig machen"
    echo "$_test_out" | tail -20 >&2
    # Restore files on test failure
    git -C "$CLAUDII_HOME" checkout -- "$_bin_file" "$_man_file" "$_changelog" 2>/dev/null || true
    exit 1
  fi
fi

# ── Commit & Release ──
_rel_box_sep "Release"

if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "Commit version bump — skipped (dry-run)"
  _rel_ok "Push origin main — skipped (dry-run)"
  _rel_ok "Tag $_rel_tag — skipped (dry-run)"
  _rel_ok "Push origin $_rel_tag — skipped (dry-run)"
else
  # Commit version bump
  git -C "$CLAUDII_HOME" add "$_bin_file" "$_man_file" "$_changelog"
  git -C "$CLAUDII_HOME" commit -m "chore(release): bump version to $_rel_version" 2>&1
  _rel_ok "Committed: chore(release): bump version to $_rel_version"

  # Push commits first — tag must not land on GitHub before the code does
  _cur_branch=$(git -C "$CLAUDII_HOME" branch --show-current 2>/dev/null || echo "main")
  git -C "$CLAUDII_HOME" push origin "$_cur_branch" 2>&1
  _push_branch_exit=$?
  if [[ $_push_branch_exit -ne 0 ]]; then
    _rel_fail "Push von branch '$_cur_branch' fehlgeschlagen"
    exit 1
  fi
  _rel_ok "Branch '$_cur_branch' gepusht"

  git -C "$CLAUDII_HOME" tag -a "$_rel_tag" -m "$_rel_tag" 2>&1
  _rel_ok "Tag $_rel_tag gesetzt"

  git -C "$CLAUDII_HOME" push origin "$_rel_tag" 2>&1
  _push_exit=$?
  if [[ $_push_exit -ne 0 ]]; then
    _rel_fail "Push von $_rel_tag fehlgeschlagen"
    git -C "$CLAUDII_HOME" tag -d "$_rel_tag" 2>/dev/null || true
    exit 1
  fi
  _rel_ok "Tag $_rel_tag gepusht"
fi

# ── Poll GitHub Actions ──
_rel_box_sep "GitHub Actions"

if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "GitHub Actions — skipped (dry-run)"
else
  if [[ -z "$_gh_owner" ]]; then
    _rel_fail "Kein GitHub-Remote gefunden: $_remote_url"
    exit 1
  fi

  _rel_spin "Warte auf GitHub Actions..."

  _poll_timeout=300
  _poll_interval=10
  _poll_elapsed=0
  _run_id=""
  _run_conclusion=""
  _spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  _spin_idx=0

  while (( _poll_elapsed < _poll_timeout )); do
    _head=$(git -C "$CLAUDII_HOME" rev-parse HEAD)
    _runs=$(gh api "repos/${_gh_owner}/${_gh_repo}/actions/runs" \
      --jq ".workflow_runs[] | select(.event == \"push\" and .head_sha == \"${_head}\" and (.name | test(\"[Rr]elease\"))) | {id: .id, status: .status, conclusion: .conclusion, name: .name}" \
      2>/dev/null || echo "")

    if [[ -n "$_runs" ]]; then
      _run_id=$(echo "$_runs" | jq -r '.id' | head -1)
      _run_status=$(echo "$_runs" | jq -r '.status' | head -1)
      _run_conclusion=$(echo "$_runs" | jq -r '.conclusion' | head -1)

      if [[ "$_run_status" == "completed" ]]; then
        break
      fi
    fi

    _spin_char="${_spinner_chars:$(( _spin_idx % ${#_spinner_chars} )):1}"
    printf '\r│ %s Warte auf GitHub Actions... (%ds)  ' "$_spin_char" "$_poll_elapsed"
    _spin_idx=$(( _spin_idx + 1 ))

    sleep "$_poll_interval"
    _poll_elapsed=$(( _poll_elapsed + _poll_interval ))
  done
  printf '\r'

  if [[ -z "$_run_id" ]]; then
    _rel_fail "Kein GitHub-Actions-Run für $_rel_tag gefunden (Timeout ${_poll_timeout}s)"
    echo "  Prüfe: https://github.com/${_gh_owner}/${_gh_repo}/actions" >&2
    exit 1
  fi

  _run_url="https://github.com/${_gh_owner}/${_gh_repo}/actions/runs/${_run_id}"

  if [[ "$_run_conclusion" == "success" ]]; then
    _rel_ok "Release-Workflow grün (Run #${_run_id})"
  else
    _rel_fail "Workflow fehlgeschlagen: conclusion=$_run_conclusion"
    echo "  $_run_url" >&2
    git -C "$CLAUDII_HOME" push origin ":refs/tags/$_rel_tag" 2>/dev/null || true
    git -C "$CLAUDII_HOME" tag -d "$_rel_tag" 2>/dev/null || true
    echo "  Tag $_rel_tag wurde entfernt." >&2
    exit 1
  fi

  _release_url="https://github.com/${_gh_owner}/${_gh_repo}/releases/tag/${_rel_tag}"
  _rel_ok "Release-Workflow hat GitHub Release erstellt"
fi

# ── Homebrew Tap ──
_rel_box_sep "Homebrew Tap"
_tap_owner="bmmmm"
_tap_repo="homebrew-tap"
_tap_formula="Formula/claudii.rb"
_tarball_url="https://github.com/${_gh_owner:-bmmmm}/${_gh_repo:-claudii}/archive/refs/tags/${_rel_tag}.tar.gz"
if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "Tap-Update — skipped (dry-run)"
else
  _sha256=$(curl -fsSL "$_tarball_url" | shasum -a 256 | cut -d' ' -f1)
  _tap_file_sha=$(gh api "repos/${_tap_owner}/${_tap_repo}/contents/${_tap_formula}" \
    --jq '.sha' 2>/dev/null || echo "")
  if [[ -z "$_tap_file_sha" ]]; then
    _rel_fail "Tap: ${_tap_formula} nicht gefunden in ${_tap_owner}/${_tap_repo}"
  else
    _tap_current=$(gh api "repos/${_tap_owner}/${_tap_repo}/contents/${_tap_formula}" \
      --jq '.content' | base64 -d)
    _tap_new=$(printf '%s' "$_tap_current" \
      | sed "s|url \"https://.*\.tar\.gz\"|url \"${_tarball_url}\"|" \
      | sed "s|sha256 \"[a-f0-9]*\"|sha256 \"${_sha256}\"|" \
      | sed "s|version \"[0-9.]*\"|version \"${_rel_version}\"|")
    _tap_encoded=$(printf '%s' "$_tap_new" | base64)
    gh api "repos/${_tap_owner}/${_tap_repo}/contents/${_tap_formula}" \
      --method PUT \
      --field message="chore: update claudii to ${_rel_tag}" \
      --field content="$_tap_encoded" \
      --field sha="$_tap_file_sha" \
      --jq '.commit.sha' >/dev/null
    _rel_ok "bmmmm/homebrew-tap → ${_rel_version} (sha256: ${_sha256:0:12}…)"
  fi

  # Append SHA256 + linked commit list to GitHub release notes
  _prev_tag=$(git -C "$CLAUDII_HOME" tag --sort=-version:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | grep -v "^${_rel_tag}$" | head -1)
  _release_body=$(gh release view "${_rel_tag}" \
    --repo "${_gh_owner}/${_gh_repo}" --json body -q .body 2>/dev/null || echo "")
  _notes_extra=$(printf '\n\n---\n**Homebrew SHA256:** `%s`' "$_sha256")
  if [[ -n "$_prev_tag" ]]; then
    _compare_url="https://github.com/${_gh_owner}/${_gh_repo}/compare/${_prev_tag}...${_rel_tag}"
    _notes_extra=$(printf '%s\n**Full Changelog:** [%s...%s](%s)' \
      "$_notes_extra" "$_prev_tag" "$_rel_tag" "$_compare_url")
  fi
  gh release edit "${_rel_tag}" --repo "${_gh_owner}/${_gh_repo}" \
    --notes "${_release_body}${_notes_extra}" >/dev/null
  _rel_ok "Release Notes: SHA256 + Changelog-Link angehängt"
fi

# ── Done ──
if [[ "$_dry_run" -eq 1 ]]; then
  _rel_box_end "Dry-run abgeschlossen — keine Änderungen vorgenommen"
else
  _rel_box_end "Done — ${_release_url:-https://github.com/bmmmm/claudii/releases/tag/${_rel_tag}}"
fi
printf '\n'
