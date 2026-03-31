#!/bin/bash
# claudii release — tag, push, and create a GitHub release
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

# 1. Run tests
if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "Tests — skipped (dry-run)"
else
  _test_out=$(bash "$CLAUDII_HOME/tests/run.sh" 2>&1)
  _test_exit=$?
  if [[ $_test_exit -eq 0 ]]; then
    _test_passed=$(echo "$_test_out" | grep -oE '[0-9]+ passed' | tail -1)
    _rel_ok "Tests lokal grün ($_test_passed)"
  else
    _rel_fail "Tests fehlgeschlagen"
    echo "$_test_out" | tail -20 >&2
    exit 1
  fi
fi

# 2. Version sync check
_bin_version=$(grep '^VERSION=' "$CLAUDII_HOME/bin/claudii" | head -1 | tr -d '"' | cut -d= -f2)
_man_version=$(grep -oE 'claudii [0-9]+\.[0-9]+\.[0-9]+' "$CLAUDII_HOME/man/man1/claudii.1" | head -1 | awk '{print $2}')

_ver_ok=1
if [[ "$_bin_version" != "$_rel_version" ]]; then
  _rel_fail "bin/claudii VERSION=$_bin_version != $_rel_version"
  _ver_ok=0
fi
if [[ "$_man_version" != "$_rel_version" ]]; then
  _rel_fail "man page version=$_man_version != $_rel_version"
  _ver_ok=0
fi
if [[ "$_ver_ok" -eq 0 ]]; then
  echo "  Update VERSION in bin/claudii and man/man1/claudii.1 to $_rel_version" >&2
  exit 1
fi
_rel_ok "Versionen synchron (bin=$_bin_version, man=$_man_version)"

# 3. No existing tag
_existing_tag=$(git -C "$CLAUDII_HOME" tag -l "$_rel_tag")
if [[ -n "$_existing_tag" ]]; then
  _rel_fail "Tag $_rel_tag existiert bereits"
  echo "  git tag -d $_rel_tag  (lokal löschen)" >&2
  echo "  git push origin :refs/tags/$_rel_tag  (remote löschen)" >&2
  exit 1
fi
_rel_ok "Kein offener Tag $_rel_tag"

# 4. CI status check (last run on current branch, requires gh)
if command -v gh >/dev/null 2>&1; then
  _ci_branch=$(git -C "$CLAUDII_HOME" branch --show-current 2>/dev/null || true)
  if [[ -n "$_ci_branch" ]]; then
    _ci_conclusion=$(gh run list --branch "$_ci_branch" --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null || true)
    if [[ "$_ci_conclusion" == "failure" ]]; then
      _rel_fail "Last CI run on branch '$_ci_branch' failed — check GitHub Actions"
      exit 1
    elif [[ -n "$_ci_conclusion" ]]; then
      _rel_ok "CI: $_ci_conclusion (branch: $_ci_branch)"
    fi
  fi
fi

# ── Release ──
_rel_box_sep "Release"

# 5. Push main branch, then create and push tag
if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "Push origin main — skipped (dry-run)"
  _rel_ok "Tag $_rel_tag — skipped (dry-run)"
  _rel_ok "Push origin $_rel_tag — skipped (dry-run)"
else
  # Push commits first — tag must not land on GitHub before the code does
  _cur_branch=$(git -C "$CLAUDII_HOME" branch --show-current 2>/dev/null || echo "main")
  git -C "$CLAUDII_HOME" push origin "$_cur_branch" 2>&1
  _push_branch_exit=$?
  if [[ $_push_branch_exit -ne 0 ]]; then
    _rel_fail "Push von branch '$_cur_branch' fehlgeschlagen — commits müssen vor dem Tag auf GitHub sein"
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

# 6. Poll GitHub Actions
if [[ "$_dry_run" -eq 1 ]]; then
  _rel_ok "GitHub Actions — skipped (dry-run)"
else
  # Get repo owner/name from remote URL
  _remote_url=$(git -C "$CLAUDII_HOME" remote get-url origin 2>/dev/null || echo "")
  if [[ "$_remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    _gh_owner="${BASH_REMATCH[1]}"
    _gh_repo="${BASH_REMATCH[2]}"
  else
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
    # Look for a workflow run triggered by the tag push
    _runs=$(gh api "repos/${_gh_owner}/${_gh_repo}/actions/runs" \
      --jq ".workflow_runs[] | select(.event == \"push\" and (.head_branch == \"refs/tags/${_rel_tag}\" or .head_branch == \"${_rel_tag}\")) | {id: .id, status: .status, conclusion: .conclusion, name: .name}" \
      2>/dev/null || echo "")

    if [[ -n "$_runs" ]]; then
      _run_id=$(echo "$_runs" | jq -r '.id' | head -1)
      _run_status=$(echo "$_runs" | jq -r '.status' | head -1)
      _run_conclusion=$(echo "$_runs" | jq -r '.conclusion' | head -1)
      _run_name=$(echo "$_runs" | jq -r '.name' | head -1)

      if [[ "$_run_status" == "completed" ]]; then
        break
      fi
    fi

    # Spinner update
    _spin_char="${_spinner_chars:$(( _spin_idx % ${#_spinner_chars} )):1}"
    printf '\r│ %s Warte auf GitHub Actions... (%ds)  ' "$_spin_char" "$_poll_elapsed"
    _spin_idx=$(( _spin_idx + 1 ))

    sleep "$_poll_interval"
    _poll_elapsed=$(( _poll_elapsed + _poll_interval ))
  done
  printf '\r'  # Clear spinner line

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
    # Cleanup: remove the pushed tag since release failed
    git -C "$CLAUDII_HOME" push origin ":refs/tags/$_rel_tag" 2>/dev/null || true
    git -C "$CLAUDII_HOME" tag -d "$_rel_tag" 2>/dev/null || true
    echo "  Tag $_rel_tag wurde entfernt." >&2
    exit 1
  fi

  # 7. Create GitHub Release
  _release_out=$(gh release create "$_rel_tag" \
    --title "$_rel_tag" \
    --generate-notes \
    --repo "${_gh_owner}/${_gh_repo}" 2>&1)
  _release_exit=$?

  if [[ $_release_exit -eq 0 ]]; then
    _release_url=$(echo "$_release_out" | grep -oE 'https://[^ ]+' | head -1)
    [[ -z "$_release_url" ]] && _release_url="https://github.com/${_gh_owner}/${_gh_repo}/releases/tag/${_rel_tag}"
    _rel_ok "GitHub Release erstellt"
  else
    _rel_fail "gh release create fehlgeschlagen"
    echo "$_release_out" >&2
    exit 1
  fi
fi

# ── Done ──
if [[ "$_dry_run" -eq 1 ]]; then
  _rel_box_end "Dry-run abgeschlossen — keine Änderungen vorgenommen"
else
  _rel_box_end "Done — ${_release_url:-https://github.com/bmmmm/claudii/releases/tag/${_rel_tag}}"
fi
printf '\n'
