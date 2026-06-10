# touches: lib/timefmt.sh lib/helpers.sh bin/claudii-cc-statusline
# test_timefmt.sh — shared relative-time formatters (_fmt_rel / _fmt_brief).
# These back the cron/reset segments in sessions/overview/cc-statusline; the
# suppression rules (0m / 0h dropped) are asserted at every cascade boundary.
# Runs under /bin/bash 3.2 AND the runner's bash — the formatters live in a
# file sourced by bin/ scripts, which macOS executes with /bin/bash 3.2.

_tfm_script='
  source "$CLAUDII_HOME/lib/timefmt.sh"
  out=""
  for s in -5 0 30 59 60 90 3599 3600 3660 7200 86399 86400 90000 172800 605000; do
    _fmt_rel "$s"; out+="${_REL_FMT};"
  done
  out+="|"
  for s in -5 0 59 60 3599 3600 86399 86400 172800; do
    _fmt_brief "$s"; out+="${_BRIEF_FMT};"
  done
  printf "%s" "$out"
'
_tfm_expect=';;<1m;<1m;1m;1m;59m;1h;1h1m;2h;23h59m;1d;1d1h;2d;7d;|0s;0s;59s;1m;59m;1h;23h;1d;2d;'

for _tfm_bash in /bin/bash bash; do
  _tfm_out=$(CLAUDII_HOME="$CLAUDII_HOME" "$_tfm_bash" -c "$_tfm_script" 2>&1)
  assert_eq "timefmt ($_tfm_bash): _fmt_rel/_fmt_brief cascade boundaries" \
    "$_tfm_expect" "$_tfm_out"
done

# Under set -e a zero/negative input must not abort the caller (return 0 path).
_tfm_sete=$(CLAUDII_HOME="$CLAUDII_HOME" /bin/bash -c '
  set -eu
  source "$CLAUDII_HOME/lib/timefmt.sh"
  _fmt_rel 0
  _fmt_brief -1
  echo survived
' 2>&1)
assert_eq "timefmt: zero/negative input survives set -eu" "survived" "$_tfm_sete"

unset _tfm_script _tfm_expect _tfm_bash _tfm_out _tfm_sete
