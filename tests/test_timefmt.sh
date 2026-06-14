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

# ── _fmt_abs: absolute timestamps honoring _CLAUDII_TZ ───────────────────────
_abs_script='
  source "$CLAUDII_HOME/lib/timefmt.sh"
  out=""
  _CLAUDII_TZ="UTC";           _fmt_abs 0;                       out+="${_ABS_FMT};"
  _CLAUDII_TZ="Europe/Berlin"; _fmt_abs 0;                       out+="${_ABS_FMT};"
  _CLAUDII_TZ="Europe/Berlin"; _fmt_abs 1765532400 "%H:%M %Z";   out+="${_ABS_FMT};"
  _CLAUDII_TZ="UTC";           _fmt_abs "not-a-number";          out+="${_ABS_FMT};"
  _CLAUDII_TZ="UTC";           _fmt_abs "";                      out+="${_ABS_FMT};"
  printf "%s" "$out"
'
# 1765532400 = 2025-12-12 10:40 CET (winter → CET, not CEST)
_abs_expect='1970-01-01 00:00;1970-01-01 01:00;10:40 CET;;;'
for _abs_bash in /bin/bash bash; do
  _abs_out=$(CLAUDII_HOME="$CLAUDII_HOME" "$_abs_bash" -c "$_abs_script" 2>&1)
  assert_eq "timefmt ($_abs_bash): _fmt_abs TZ conversion + invalid input" \
    "$_abs_expect" "$_abs_out"
done

# Empty _CLAUDII_TZ → system local, must not crash under set -eu
_abs_local=$(CLAUDII_HOME="$CLAUDII_HOME" /bin/bash -c '
  set -eu
  source "$CLAUDII_HOME/lib/timefmt.sh"
  _fmt_abs 0
  [[ -n "$_ABS_FMT" ]] && echo "ok"
')
assert_eq "timefmt: _fmt_abs system-local fallback under set -eu" "ok" "$_abs_local"

# ── _iso_epoch: ISO-8601 UTC → epoch (round-trips through _fmt_abs under UTC) ──
# Validates the Z-strip + fractional-strip + BSD/GNU parse. A round-trip back to
# the same string under TZ=UTC proves the epoch is right without hardcoding it.
_iso_script='
  source "$CLAUDII_HOME/lib/timefmt.sh"
  _CLAUDII_TZ="UTC"
  out=""
  _iso_epoch "2026-06-10T10:30:00Z";     _fmt_abs "$_EPOCH" "%Y-%m-%dT%H:%M:%SZ"; out+="${_ABS_FMT};"
  _iso_epoch "2026-06-10T10:30:00.999Z"; _fmt_abs "$_EPOCH" "%Y-%m-%dT%H:%M:%SZ"; out+="${_ABS_FMT};"
  _iso_epoch ""        ; out+="[${_EPOCH}];"
  _iso_epoch "garbage" ; out+="[${_EPOCH}];"
  printf "%s" "$out"
'
_iso_expect='2026-06-10T10:30:00Z;2026-06-10T10:30:00Z;[];[];'
for _iso_bash in /bin/bash bash; do
  _iso_out=$(CLAUDII_HOME="$CLAUDII_HOME" "$_iso_bash" -c "$_iso_script" 2>&1)
  assert_eq "timefmt ($_iso_bash): _iso_epoch parse + round-trip + invalid" \
    "$_iso_expect" "$_iso_out"
done
unset _iso_script _iso_expect _iso_bash _iso_out
