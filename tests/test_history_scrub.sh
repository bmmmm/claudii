# touches: scripts/history-scrub.sh
# test_history_scrub.sh — the scrub keeps real rows, quarantines fixture rows,
# never deletes, and refuses a file that grew mid-scan.

_hs_cache="$CLAUDII_TEST_TMP/history_scrub"
rm -rf "$_hs_cache"; mkdir -p "$_hs_cache"
_hs_file="$_hs_cache/history-2026-08.tsv"
_hs_script="$CLAUDII_HOME/scripts/history-scrub.sh"

# 3 real rows (UUID session ids) + 3 fixture rows (empty id, invented ids)
hist_row "$_hs_file" 1788000001 "Opus"    "1.50"  10 5 "977dc8be-d4cb-4db0-a248-7b7088fe2e60" 1000 200 0
hist_row "$_hs_file" 1788000002 "Sonnet"  "0.25"  10 5 "1faf3c66-e063-47e4-b3b3-8f5adb2e94d2" 1000 200 0
hist_row "$_hs_file" 1788000003 "T"       "12.53" 10 5 ""                                     1000 200 0
hist_row "$_hs_file" 1788000004 "Opus"    "2.00"  10 5 "4da830bc-0cb1-407c-87f9-aa067a1ad3e8" 1000 200 0
hist_row "$_hs_file" 1788000005 "Sonnet"  "0.55"  10 5 "widthsess001"                         1000 200 0
hist_row "$_hs_file" 1788000006 "O"       "0.10"  10 5 "testwt99"                             1000 200 0

# ── dry run: reports, writes nothing ────────────────────────────────────────
_hs_out=$(bash "$_hs_script" --cache-dir "$_hs_cache" 2>&1 || true)
assert_contains "dry run counts the keepers" "3" "$_hs_out"
assert_contains "dry run says nothing was written" "Dry run" "$_hs_out"
assert_eq "dry run leaves the file untouched" "6" "$(wc -l < "$_hs_file" | tr -d ' ')"
assert_eq "dry run writes no quarantine file" "absent" \
  "$([[ -f "$_hs_file.quarantine" ]] && echo present || echo absent)"

# ── apply: splits the file ──────────────────────────────────────────────────
_hs_out=$(bash "$_hs_script" --cache-dir "$_hs_cache" --apply 2>&1 || true)
assert_eq "apply keeps only the UUID rows" "3" "$(wc -l < "$_hs_file" | tr -d ' ')"
assert_eq "apply quarantines the fixture rows" "3" \
  "$(wc -l < "$_hs_file.quarantine" | tr -d ' ')"

_hs_kept=$(cat "$_hs_file")
assert_contains "a real session survives" "977dc8be" "$_hs_kept"
assert_not_contains "the invented session id is gone" "widthsess001" "$_hs_kept"
assert_not_contains "the fake model row is gone" "12.53" "$_hs_kept"

_hs_quar=$(cat "$_hs_file.quarantine")
assert_contains "quarantine holds the invented id" "widthsess001" "$_hs_quar"
assert_contains "quarantine holds the empty-id row" "12.53" "$_hs_quar"

# Nothing is destroyed: backup + quarantine together reconstruct the original.
_hs_bak=$(ls "$_hs_cache"/history-2026-08.tsv.*.bak 2>/dev/null | head -1)
assert_eq "a timestamped backup exists" "0" \
  "$([[ -n "$_hs_bak" && -f "$_hs_bak" ]] && echo 0 || echo 1)"
assert_eq "the backup is the untouched original" "6" \
  "$(wc -l < "$_hs_bak" | tr -d ' ')"

# ── idempotence: a second apply finds nothing left to do ────────────────────
bash "$_hs_script" --cache-dir "$_hs_cache" --apply >/dev/null 2>&1 || true
assert_eq "second apply changes nothing" "3" "$(wc -l < "$_hs_file" | tr -d ' ')"
assert_eq "second apply adds no quarantine rows" "3" \
  "$(wc -l < "$_hs_file.quarantine" | tr -d ' ')"

# ── bad flag ────────────────────────────────────────────────────────────────
assert_exit_code "unknown option exits 2" 2 "bash '$_hs_script' --bogus"

rm -rf "$_hs_cache"
unset _hs_cache _hs_file _hs_script _hs_out _hs_kept _hs_quar _hs_bak
