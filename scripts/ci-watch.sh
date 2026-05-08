#!/usr/bin/env bash
# scripts/ci-watch.sh — poll all CI runs for the latest push until done.
#
# Usage: scripts/ci-watch.sh [--interval N] [--sha <sha>]
#   --interval N   poll every N seconds (default: 10)
#   --sha <sha>    watch runs for a specific commit (default: HEAD)
#
# Exits 0 if all runs pass, 1 if any fail.

set -euo pipefail

_interval=10
_sha=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) _interval="$2"; shift 2 ;;
    --sha)      _sha="$2";      shift 2 ;;
    *) echo "Usage: $0 [--interval N] [--sha <sha>]" >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "ci-watch: gh CLI not found" >&2; exit 1; }

[[ -z "$_sha" ]] && _sha=$(git rev-parse HEAD)
_sha=$(git rev-parse "$_sha")  # expand short SHA to full
_short="${_sha:0:7}"

_red=$'\033[0;31m'; _green=$'\033[0;32m'; _yellow=$'\033[0;33m'; _dim=$'\033[2m'; _nc=$'\033[0m'

echo "${_dim}Watching CI for ${_short}…${_nc}"

_spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
_spin_i=0
_failed=0

while true; do
  # Fetch all runs for this commit
  _runs=$(gh run list --commit "$_sha" --json databaseId,name,status,conclusion \
    --jq '.[] | "\(.databaseId)\t\(.name)\t\(.status)\t\(.conclusion // "—")"' 2>/dev/null || true)

  if [[ -z "$_runs" ]]; then
    _spin="${_spinner:$(( _spin_i % ${#_spinner} )):1}"
    (( ++_spin_i ))
    printf "\r  %s  waiting for runs to register…  " "$_spin"
    sleep "$_interval"
    continue
  fi

  # Check if any run is still in_progress or queued
  _pending=$(echo "$_runs" | awk -F'\t' '$3 == "in_progress" || $3 == "queued" || $3 == "waiting" { print }')

  if [[ -n "$_pending" ]]; then
    _spin="${_spinner:$(( _spin_i % ${#_spinner} )):1}"
    (( ++_spin_i ))
    _names=$(echo "$_pending" | awk -F'\t' '{ printf "%s", $2; if (NR < 3) printf ", " }')
    printf "\r  %s  running: %-40s" "$_spin" "$_names"
    sleep "$_interval"
    continue
  fi

  # All done — report results
  printf "\r%-60s\n" ""  # clear spinner line

  _failed=0
  while IFS=$'\t' read -r _id _name _status _conclusion; do
    if [[ "$_conclusion" == "success" ]]; then
      printf "  ${_green}✓${_nc}  %s\n" "$_name"
    elif [[ "$_conclusion" == "skipped" || "$_conclusion" == "cancelled" ]]; then
      printf "  ${_dim}–${_nc}  %s (%s)\n" "$_name" "$_conclusion"
    else
      printf "  ${_red}✗${_nc}  %s (%s)\n" "$_name" "$_conclusion"
      _failed=1
      echo ""
      echo "${_red}── Failures in: $_name ──────────────────────────────${_nc}"
      gh run view "$_id" --log-failed 2>/dev/null \
        | sed 's/^.*[0-9]Z *//' \
        | sed $'s/\x1b\[[0-9;]*m//g; s/\^\[\[[0-9;]*m//g' \
        | grep -E "(✗|Failures:|  - )" \
        | grep -v "^$" \
        | head -30
      echo ""
    fi
  done <<< "$_runs"

  break
done

if (( _failed )); then
  echo "${_red}CI failed.${_nc}"
  exit 1
else
  echo "${_green}CI passed.${_nc}"
  exit 0
fi
