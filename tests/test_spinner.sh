# touches: lib/spinner.sh
# test_spinner.sh — every spinner mode reads its label through the shared
# _claudii_spinner_read_label (ascii and beam used to inline it; wave ignored
# CLAUDII_SPINNER_LABEL_FILE altogether).

_SP_TMP="$(mktemp -d)"
trap 'rm -rf "$_SP_TMP"' EXIT
_sp_label="$_SP_TMP/label"
printf 'scanning-session-files\n' > "$_sp_label"

# _sp_capture <mode> — run one spinner mode ~0.4s, echo what it wrote to stderr.
_sp_capture() {
  local _mode="$1" _out="$_SP_TMP/out.$1" _pid
  (
    # shellcheck source=lib/spinner.sh
    source "$CLAUDII_HOME/lib/spinner.sh"
    export CLAUDII_SPINNER_LABEL_FILE="$_sp_label" COLUMNS=60
    "_claudii_spinner_${_mode}"
  ) 2> "$_out" &
  _pid=$!
  sleep 0.4
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null || true
  cat "$_out"
}

for _sp_mode in ascii beam wave dots pulse bounce arc orbit; do
  assert_contains "spinner $_sp_mode: shows the label file's text" \
    "scanning-session-files" "$(_sp_capture "$_sp_mode")"
done

# No label file → every mode falls back to "Loading".
rm -f "$_sp_label"
for _sp_mode in ascii beam wave; do
  assert_contains "spinner $_sp_mode: no label file → Loading" "Loading" "$(_sp_capture "$_sp_mode")"
done

# Over-long label is truncated to 45 chars with a leading ellipsis (shared rule).
printf '%s\n' "$(printf 'x%.0s' $(seq 1 80))" > "$_sp_label"
_sp_long="$(_sp_capture wave)"
assert_contains "spinner wave: long label truncated with ellipsis" "…" "$_sp_long"
assert_not_contains "spinner wave: long label not printed in full" "$(printf 'x%.0s' $(seq 1 50))" "$_sp_long"

unset -f _sp_capture
unset _SP_TMP _sp_label _sp_mode _sp_long
