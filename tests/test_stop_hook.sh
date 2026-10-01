# touches: bin/claudii-stop-hook lib/helpers.sh
# test_stop_hook.sh — claudii-stop-hook Stop-hook integration

SH="$CLAUDII_HOME/bin/claudii-stop-hook"
_SH_TMPDIRS=()
trap 'rm -rf "${_SH_TMPDIRS[@]}" 2>/dev/null' EXIT

# ── Basic: epoch next_run_at persisted ──────────────────────────────────────
_sh_tmp="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp")
_future=$(( $(date +%s) + 3600 ))
echo "{\"session_id\":\"stophook0011\",\"session_crons\":[{\"next_run_at\":${_future}}],\"background_tasks\":[]}" \
  | CLAUDII_CACHE_DIR="$_sh_tmp" bash "$SH" 2>/dev/null
_sh_cache="$_sh_tmp/session-stophook"
assert_file_exists "stop-hook: cache file created" "$_sh_cache"
_sh_contents="$(cat "$_sh_cache" 2>/dev/null)"
assert_contains "stop-hook: next_cron_at written" "next_cron_at=${_future}" "$_sh_contents"
assert_contains "stop-hook: bg_tasks written" "bg_tasks=0" "$_sh_contents"

# ── Multiple crons: pick earliest ───────────────────────────────────────────
_sh_tmp2="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp2")
_near=$(( $(date +%s) + 900 ))
_far=$(( $(date +%s) + 7200 ))
echo "{\"session_id\":\"stophook0022\",\"session_crons\":[{\"next_run_at\":${_far}},{\"next_run_at\":${_near}}]}" \
  | CLAUDII_CACHE_DIR="$_sh_tmp2" bash "$SH" 2>/dev/null
_sh_cache2="$_sh_tmp2/session-stophook"
_sh_contents2="$(cat "$_sh_cache2" 2>/dev/null)"
assert_contains "stop-hook: picks earliest cron" "next_cron_at=${_near}" "$_sh_contents2"

# ── Empty session_crons array ────────────────────────────────────────────────
_sh_tmp3="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp3")
echo '{"session_id":"stophook0033","session_crons":[]}' \
  | CLAUDII_CACHE_DIR="$_sh_tmp3" bash "$SH" 2>/dev/null
_sh_cache3="$_sh_tmp3/session-stophook"
_sh_contents3="$(cat "$_sh_cache3" 2>/dev/null)"
assert_contains "stop-hook: empty crons → next_cron_at empty" "next_cron_at=" "$_sh_contents3"
# next_cron_at should be present but with empty value
_cron_val3="$(echo "$_sh_contents3" | grep '^next_cron_at=' | cut -d= -f2)"
assert_eq "stop-hook: empty crons → empty value" "" "$_cron_val3"

# ── Missing session_crons field ─────────────────────────────────────────────
_sh_tmp4="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp4")
echo '{"session_id":"stophook0044","cost":1.23}' \
  | CLAUDII_CACHE_DIR="$_sh_tmp4" bash "$SH" 2>/dev/null
_sh_cache4="$_sh_tmp4/session-stophook"
_sh_contents4="$(cat "$_sh_cache4" 2>/dev/null)"
assert_contains "stop-hook: missing field → cache written" "next_cron_at=" "$_sh_contents4"

# ── Malformed JSON → graceful (no crash, exit 0) ────────────────────────────
_sh_tmp5="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp5")
_sh_exit=$(echo 'NOT JSON AT ALL' | CLAUDII_CACHE_DIR="$_sh_tmp5" bash "$SH" 2>/dev/null; echo $?)
# No session_id in malformed JSON → hook exits 0 early (no cache written is ok)
assert_eq "stop-hook: malformed JSON → exit 0" "0" "$_sh_exit"

# ── Preserve existing keys (read-modify-write) ──────────────────────────────
_sh_tmp6="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp6")
# Pre-populate the cache with existing session data
printf 'model=Sonnet 4.6\ncost=1.23\nppid=%s\nsession_id=stophook0066\npace=ahead\n' "$$" \
  > "$_sh_tmp6/session-stophook"
_future6=$(( $(date +%s) + 1800 ))
echo "{\"session_id\":\"stophook0066\",\"session_crons\":[{\"next_run_at\":${_future6}}]}" \
  | CLAUDII_CACHE_DIR="$_sh_tmp6" bash "$SH" 2>/dev/null
_sh_contents6="$(cat "$_sh_tmp6/session-stophook" 2>/dev/null)"
assert_contains "stop-hook: preserves model= key" "model=Sonnet 4.6" "$_sh_contents6"
assert_contains "stop-hook: preserves cost= key" "cost=1.23" "$_sh_contents6"
assert_contains "stop-hook: preserves pace= key" "pace=ahead" "$_sh_contents6"
assert_contains "stop-hook: writes new next_cron_at" "next_cron_at=${_future6}" "$_sh_contents6"

# ── background_tasks count ──────────────────────────────────────────────────
_sh_tmp7="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp7")
_future7=$(( $(date +%s) + 600 ))
echo "{\"session_id\":\"stophook0077\",\"session_crons\":[{\"next_run_at\":${_future7}}],\"background_tasks\":[{\"id\":\"t1\"},{\"id\":\"t2\"}]}" \
  | CLAUDII_CACHE_DIR="$_sh_tmp7" bash "$SH" 2>/dev/null
_sh_contents7="$(cat "$_sh_tmp7/session-stophook" 2>/dev/null)"
assert_contains "stop-hook: bg_tasks=2 written" "bg_tasks=2" "$_sh_contents7"

# ── Missing session_id → no file written, exits 0 ───────────────────────────
_sh_tmp8="$(mktemp -d)"; _SH_TMPDIRS+=("$_sh_tmp8")
_sh_exit8=$(echo '{"session_crons":[{"next_run_at":9999999999}]}' \
  | CLAUDII_CACHE_DIR="$_sh_tmp8" bash "$SH" 2>/dev/null; echo $?)
assert_eq "stop-hook: missing session_id → exit 0" "0" "$_sh_exit8"
_sh_files8=$(ls "$_sh_tmp8/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "stop-hook: missing session_id → no cache file" "0" "$_sh_files8"
