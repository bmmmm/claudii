#!/usr/bin/env bash
# scripts/lint.sh — shellcheck the whole project, the way it is actually loaded.
#
# Usage: bash scripts/lint.sh [--list]
#   --list   print the files that would be checked, then exit
#
# Two things this gets right that a plain "scan a directory" does not:
#
# 1. `-x` (follow sourced files). lib/cmd/*.sh are fragments: bin/claudii
#    sources lib/helpers.sh and friends before them, so the _PSC_* globals they
#    use are assigned in a different file. Linted standalone they produce 29
#    "referenced but not assigned" warnings that are pure artefacts of looking
#    at a fragment in isolation. Linted from the entry point, with -x, the same
#    code is clean — and a real typo would still show.
#
# 2. Shell detection by shebang. bin/ holds a Python receiver
#    (claudii-otel-receiver); forcing --shell=bash over the directory reports
#    its docstring as a syntax error. zsh files are skipped too — shellcheck
#    has no zsh mode, and pretending they are bash invents findings.
#
# Excluded rules, same set the workflow used:
#   SC1090/SC1091  dynamic and unfollowable `source` paths
#   SC2034         "unused" — normal for the shared _seg_*/_PSC_* globals
#   SC1007         `VAR=` blanking, used deliberately throughout

set -uo pipefail

_repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$_repo" || exit 1

_is_bashish() {  # <file> -> 0 when the shebang says bash or sh
  local _first
  IFS= read -r _first < "$1" 2>/dev/null || return 1
  case "$_first" in
    '#!'*[!a-zA-Z]bash*|'#!'*bash) return 0 ;;
    '#!'*[!a-zA-Z]sh|'#!'*/sh|'#!'*env\ sh) return 0 ;;
    *) return 1 ;;
  esac
}

_targets=()
# Entry points: -x pulls lib/*.sh and lib/cmd/*.sh in behind them.
for _f in bin/* scripts/*.sh tests/*.sh .githooks/pre-commit.d/*; do
  [[ -f "$_f" ]] || continue
  _is_bashish "$_f" && _targets+=("$_f")
done
# Test files are sourced fragments with no shebang, but they are real bash and
# the helpers they use come from tests/run.sh.
for _f in tests/test_*.sh; do
  [[ -f "$_f" ]] || continue
  _is_bashish "$_f" || _targets+=("$_f")
done

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "${_targets[@]}"
  exit 0
fi

command -v shellcheck >/dev/null 2>&1 || {
  echo "lint: shellcheck not found — brew install shellcheck" >&2; exit 1; }

echo "  shellcheck ${#_targets[@]} file(s)"
shellcheck -x -S warning --shell=bash \
  --exclude=SC1090,SC1091,SC2034,SC1007 \
  "${_targets[@]}"
_rc=$?
(( _rc == 0 )) && echo "  clean"
exit "$_rc"
