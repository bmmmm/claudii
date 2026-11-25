# touches: lib/spinner.sh
# test_spinner.sh — every spinner mode reads its label through the shared
# _claudii_spinner_read_label (ascii and beam used to inline it; wave ignored
# CLAUDII_SPINNER_LABEL_FILE altogether).

_SP_TMP="$(mktemp -d)"
trap 'rm -rf "$_SP_TMP"' EXIT
_sp_label="$_SP_TMP/label"
printf 'scanning-session-files\n' > "$_sp_label"

# _sp_capture <mode> [needle] — run one spinner mode, echo what it wrote to
# stderr. Polls (up to ~5 s) until <needle> shows up instead of a fixed sleep:
# on a loaded machine the backgrounded subshell may not even have opened its
# output file after 0.4 s. Without a needle, runs a short fixed time.
_sp_capture() {
  local _mode="$1" _needle="${2:-}" _out="$_SP_TMP/out.$1" _pid _n
  : > "$_out"
  (
    # shellcheck source=lib/spinner.sh
    source "$CLAUDII_HOME/lib/spinner.sh"
    export CLAUDII_SPINNER_LABEL_FILE="$_sp_label" COLUMNS=60
    "_claudii_spinner_${_mode}"
  ) 2> "$_out" &
  _pid=$!
  for _n in $(seq 1 50); do
    sleep 0.1
    [[ -n "$_needle" ]] && grep -q -- "$_needle" "$_out" 2>/dev/null && break
  done
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null || true
  cat "$_out"
}

for _sp_mode in ascii beam wave dots pulse bounce arc orbit; do
  assert_contains "spinner $_sp_mode: shows the label file's text" \
    "scanning-session-files" "$(_sp_capture "$_sp_mode" scanning-session-files)"
done

# No label file → every mode falls back to "Loading".
rm -f "$_sp_label"
for _sp_mode in ascii beam wave; do
  assert_contains "spinner $_sp_mode: no label file → Loading" "Loading" "$(_sp_capture "$_sp_mode" Loading)"
done

# Over-long label is truncated to 45 chars with a leading ellipsis (shared rule).
printf '%s\n' "$(printf 'x%.0s' $(seq 1 80))" > "$_sp_label"
_sp_long="$(_sp_capture wave …)"
assert_contains "spinner wave: long label truncated with ellipsis" "…" "$_sp_long"
assert_not_contains "spinner wave: long label not printed in full" "$(printf 'x%.0s' $(seq 1 50))" "$_sp_long"

unset -f _sp_capture
unset _SP_TMP _sp_label _sp_mode _sp_long
