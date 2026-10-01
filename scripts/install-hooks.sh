#!/usr/bin/env bash
# scripts/install-hooks.sh — install this repo's commit guards.
#
# Usage: bash scripts/install-hooks.sh [--check]
#   --check   report status and exit non-zero if anything is missing (no writes)
#
# Copies .githooks/pre-commit.d/* into .git/hooks/pre-commit.d/, where the
# pre-commit dispatcher picks them up in lexical order alongside the
# machine-wide guards (path-guard, secret-guard, filename-guard,
# mirror-leak-guard).
#
# Why a copy into .d/ rather than `git config core.hooksPath .githooks`:
# pointing hooksPath at the repo would REPLACE .git/hooks entirely, disabling
# every machine-wide guard for this repo. The guards and the repo's own checks
# have to coexist, so they share one directory.
#
# .git/hooks is not tracked, so this is per-clone setup — run it once after
# cloning. `claudii doctor` reports when it has not been run.

set -euo pipefail

_check=0
[[ "${1:-}" == "--check" ]] && _check=1

_repo="$(cd "$(dirname "$0")/.." && pwd)"
_src="$_repo/.githooks/pre-commit.d"
_git_dir="$(git -C "$_repo" rev-parse --git-common-dir 2>/dev/null || echo "$_repo/.git")"
case "$_git_dir" in /*) ;; *) _git_dir="$_repo/$_git_dir" ;; esac
_dst="$_git_dir/hooks/pre-commit.d"

[[ -d "$_src" ]] || { echo "install-hooks: no $_src" >&2; exit 1; }

_missing=0
for _g in "$_src"/*; do
  [[ -f "$_g" ]] || continue
  _name="$(basename "$_g")"
  if [[ -f "$_dst/$_name" ]] && cmp -s "$_g" "$_dst/$_name"; then
    (( _check )) && printf '  ok       %s\n' "$_name"
    continue
  fi
  _missing=1
  if (( _check )); then
    if [[ -f "$_dst/$_name" ]]; then
      printf '  stale    %s (differs from the tracked source)\n' "$_name"
    else
      printf '  missing  %s\n' "$_name"
    fi
    continue
  fi
  mkdir -p "$_dst"
  cp "$_g" "$_dst/$_name"
  chmod +x "$_dst/$_name"
  printf '  installed  %s\n' "$_name"
done

if (( _check )); then
  if (( _missing )); then
    echo "  → run: bash scripts/install-hooks.sh" >&2
    exit 1
  fi
  echo "  all repo hooks installed"
  exit 0
fi

# The dispatcher is machine-wide (ops-managed) and not this script's to create;
# without it the guards sit in a directory nobody reads.
if [[ ! -x "$_git_dir/hooks/pre-commit" ]]; then
  printf '\n  note: %s/hooks/pre-commit is missing or not executable —\n' "$_git_dir" >&2
  printf '        the guards in pre-commit.d/ only run when a dispatcher calls them.\n' >&2
fi
echo "  done"
