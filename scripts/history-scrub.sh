#!/usr/bin/env bash
# scripts/history-scrub.sh — quarantine test-fixture rows from the cost history.
#
# Usage: scripts/history-scrub.sh [--apply] [--cache-dir DIR]
#   (default is a dry run: it reports, it does not write)
#
# Why this exists
# ---------------
# tests/run.sh used to run every test file with the user's real HOME, so the
# ~130 statusline invocations in tests/test_sessionline.sh rendered against the
# live ~/.cache/claudii and appended a fixture row to the real cost history on
# every render. Measured before the fix: 66,812 of 475,659 rows across all
# months. The dollar effect is small ($60,137.30 -> $60,133.26 all-time), the
# counting effect is not — the 7-day session count read 128 instead of 116 and
# avg API/session 39m instead of 43m.
#
# The runner is fixed (tests/run.sh sandboxes HOME and the XDG roots per test
# file; tests/test_isolation.sh keeps it fixed). This script cleans up what the
# old behaviour already wrote.
#
# What counts as a fixture row
# ----------------------------
# Column 6 is the session id. Claude Code session ids are UUIDs; the fixtures
# use empty ids or invented ones ("widthsess001", "testwt99"), and models that
# do not exist ("T", "O"). The rule here is deliberately the narrow one: keep
# every row whose column 6 starts with 8 hex digits and a dash, quarantine the
# rest.
#
# It is a heuristic, so nothing is deleted. Quarantined rows are appended to
# history-<month>.tsv.quarantine and a timestamped backup of each original is
# written next to it. To undo one file:
#   cat history-2026-08.tsv.quarantine >> history-2026-08.tsv && sort -n -o ...
# or simply restore the .bak.
#
# Verify the result, do not trust it: run `claudii cost` before and after. The
# expected all-time delta on this machine was $4.04. A much larger delta means
# the heuristic ate real rows — restore the backup.

set -euo pipefail

_cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
_apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)     _apply=1; shift ;;
    --dry-run)   _apply=0; shift ;;
    --cache-dir) _cache="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
    *) echo "history-scrub: unknown option: $1" >&2
       echo "Usage: $0 [--apply] [--cache-dir DIR]" >&2; exit 2 ;;
  esac
done

[[ -d "$_cache" ]] || { echo "history-scrub: no cache dir at $_cache" >&2; exit 1; }

# 8 hex digits + dash, written out rather than as {8} — BSD awk's support for
# interval expressions has been the kind of thing this repo gets burned by.
_uuid_re='^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-'

_stamp=$(date +%Y%m%d%H%M%S)
_total_keep=0 _total_quar=0 _files=0

printf '\n  history-scrub  %s\n' "$( ((_apply)) && echo 'apply' || echo 'dry run')"
printf '  cache: %s\n\n' "$_cache"
printf '  %-24s %10s %10s\n' "file" "keep" "quarantine"
printf '  %-24s %10s %10s\n' "------------------------" "----------" "----------"

for _f in "$_cache"/history-*.tsv; do
  [[ -f "$_f" ]] || continue
  _base=$(basename "$_f")

  _keep=$(LC_ALL=C awk -F'\t' -v re="$_uuid_re" '$6 ~ re' "$_f" | wc -l | tr -d ' ')
  _quar=$(LC_ALL=C awk -F'\t' -v re="$_uuid_re" '$6 !~ re' "$_f" | wc -l | tr -d ' ')
  _total_keep=$(( _total_keep + _keep ))
  _total_quar=$(( _total_quar + _quar ))
  _files=$(( _files + 1 ))

  printf '  %-24s %10s %10s\n' "$_base" "$_keep" "$_quar"

  (( _apply )) || continue
  (( _quar > 0 )) || continue

  # A live statusline appends to this file with >>. Count first, count again
  # before the swap: if a row arrived in between, skip the file rather than
  # lose it. Re-run the script afterwards.
  _before=$(wc -l < "$_f" | tr -d ' ')

  _tmp_keep=$(mktemp "${TMPDIR:-/tmp}/hscrub_keep.XXXXXX")
  _tmp_quar=$(mktemp "${TMPDIR:-/tmp}/hscrub_quar.XXXXXX")
  LC_ALL=C awk -F'\t' -v re="$_uuid_re" '$6 ~ re'  "$_f" > "$_tmp_keep"
  LC_ALL=C awk -F'\t' -v re="$_uuid_re" '$6 !~ re' "$_f" > "$_tmp_quar"

  _after=$(wc -l < "$_f" | tr -d ' ')
  if [[ "$_before" != "$_after" ]]; then
    printf '    skipped — file grew during the scan (%s -> %s rows), re-run\n' \
      "$_before" "$_after"
    rm -f "$_tmp_keep" "$_tmp_quar"
    continue
  fi

  cp "$_f" "${_f}.${_stamp}.bak"
  cat "$_tmp_quar" >> "${_f}.quarantine"
  mv -f "$_tmp_keep" "$_f"
  rm -f "$_tmp_quar"
  printf '    backup: %s\n' "$(basename "${_f}.${_stamp}.bak")"
done

printf '  %-24s %10s %10s\n' "------------------------" "----------" "----------"
printf '  %-24s %10s %10s\n\n' "$_files file(s)" "$_total_keep" "$_total_quar"

if (( _apply )); then
  echo "  Done. Verify with: claudii cost"
  echo "  Undo one month:  mv history-<month>.tsv.<stamp>.bak history-<month>.tsv"
else
  echo "  Dry run — nothing written. Re-run with --apply to quarantine."
fi
printf '\n'
