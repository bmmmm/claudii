# lib/timefmt.sh — shared relative-time formatters (bash 3.2 compatible)
#
# No dependencies, no top-level side effects beyond the result variables.
# Sourced by bin/claudii (via helpers.sh) and bin/claudii-cc-statusline.
# Results are written to globals (no subshell fork on the render hot paths).

# _fmt_rel <seconds> — countdown/relative span into _REL_FMT.
#   <60s → "<1m" · <1h → "Xm" · <24h → "XhYm" (minutes suppressed when 0)
#   ≥24h → "XdYh" (hours suppressed when 0). Negative/zero → empty string.
# Canonical home for the cron/reset cascade that used to be hand-rolled in
# lib/cmd/sessions.sh (twice) and bin/claudii-cc-statusline.
_fmt_rel() {
  local _s=${1:-0} _h _m _d
  _REL_FMT=""
  (( _s <= 0 )) && return 0
  if   (( _s < 60 ));   then _REL_FMT="<1m"
  elif (( _s < 3600 )); then printf -v _REL_FMT '%dm' $(( _s / 60 ))
  elif (( _s < 86400 )); then
    _h=$(( _s / 3600 )); _m=$(( (_s % 3600) / 60 ))
    if (( _m > 0 )); then printf -v _REL_FMT '%dh%dm' "$_h" "$_m"
    else printf -v _REL_FMT '%dh' "$_h"; fi
  else
    _d=$(( _s / 86400 )); _h=$(( (_s % 86400) / 3600 ))
    if (( _h > 0 )); then printf -v _REL_FMT '%dd%dh' "$_d" "$_h"
    else printf -v _REL_FMT '%dd' "$_d"; fi
  fi
  return 0
}

# _fmt_abs <epoch> [strftime-fmt] — absolute timestamp into _ABS_FMT.
# Honors the configured display timezone via the _CLAUDII_TZ global (set from
# config key display.timezone, e.g. "Europe/Berlin"); empty = system local.
# Portable across BSD (`date -r`) and GNU (`date -d @`). Non-numeric input
# or a failing date → empty _ABS_FMT (caller decides the fallback).
_fmt_abs() {
  local _e=${1:-} _fmt="${2:-%Y-%m-%d %H:%M}"
  _ABS_FMT=""
  [[ "$_e" =~ ^[0-9]+$ ]] || return 0
  # LC_ALL=C, not LC_TIME=C: keep %a/%b weekday/month names English (project
  # rule: English CLI output). LC_TIME alone loses to a set LC_ALL — under
  # LC_ALL=de_DE.UTF-8 this rendered "Mi." instead of "Wed" (same defeat as the
  # LC_NUMERIC/awk case in docs/gotchas.md). Numeric formats are locale-immune
  # anyway, so forcing C costs nothing.
  if [[ -n "${_CLAUDII_TZ:-}" ]]; then
    _ABS_FMT=$(LC_ALL=C TZ="$_CLAUDII_TZ" date -r "$_e" "+$_fmt" 2>/dev/null \
      || LC_ALL=C TZ="$_CLAUDII_TZ" date -d "@$_e" "+$_fmt" 2>/dev/null) || _ABS_FMT=""
  else
    _ABS_FMT=$(LC_ALL=C date -r "$_e" "+$_fmt" 2>/dev/null \
      || LC_ALL=C date -d "@$_e" "+$_fmt" 2>/dev/null) || _ABS_FMT=""
  fi
  return 0
}

# _iso_epoch <iso8601-utc> — parse an ISO-8601 UTC timestamp (e.g.
# "2026-06-07T23:09:27.107Z") to epoch seconds into _EPOCH (empty on failure).
# Strips the trailing Z and any fractional seconds. Portable across BSD
# (`date -j -f`) and GNU (`date -d`). Used for insights timestamps
# (first_seen/last_seen, limit_hits[].timestamp) which are always Z-suffixed UTC.
_iso_epoch() {
  local _iso="${1:-}"
  _EPOCH=""
  [[ -z "$_iso" ]] && return 0
  _iso="${_iso%Z}"; _iso="${_iso%%.*}"   # drop trailing Z, then fractional secs
  _EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$_iso" +%s 2>/dev/null \
    || date -u -d "${_iso/T/ }" +%s 2>/dev/null) || _EPOCH=""
  return 0
}

# _window_cutoffs <days> — rolling-window boundaries, anchored on CLAUDII_NOW
# (epoch seconds) when set, else the live clock — same seam as
# bin/claudii-insights's merge cutoff (claudii#5 follow-up: tokens/repos/perf
# all call this helper for their own "--days N" filtering, so pinning only the
# merge step left `limits` deterministic while those three still read the live
# clock under the same fixture). Sets _WC_CUTOFF (ISO-Z timestamp of now-<days>,
# a last_seen threshold) and _WC_FLOOR (date of now-(<days>-1), the inclusive
# calendar floor for "last N days" day-bucket filters). Both empty on date
# failure (callers no-op on ""). A non-numeric CLAUDII_NOW degrades to the live
# clock rather than failing this helper outright — unlike the merge entry point
# (bin/claudii-insights), a render helper sourced into a dozen callers has no
# CLI-flag boundary of its own to reject at, and this function's contract has
# always been "best-effort, empty on any date trouble".
# `date -d @<epoch>` tried before `-r <epoch>`: GNU's `-r` doubles as "read a
# FILE's mtime", so trying it first could silently return the wrong date on
# GNU if a file happened to be named like the epoch; BSD has no `-d` at all
# (fails fast), so the fallback still reaches `-r` cleanly there.
# The plain "N days ago" probe still lives, unchanged and CLAUDII_NOW-blind, in
# bin/claudii-otel and bin/claudii-insights's `gc` — maintenance/standalone
# paths this seam does not reach; their own comments still point at each other,
# not at this function's new epoch math.
_window_cutoffs() {
  local _days="${1:-7}"
  _WC_CUTOFF=""; _WC_FLOOR=""
  local _now_epoch="${CLAUDII_NOW:-$(date +%s)}"
  [[ "$_now_epoch" =~ ^[0-9]+$ ]] || _now_epoch=$(date +%s)
  _WC_CUTOFF=$(date -u -d "@$(( _now_epoch - _days * 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$(( _now_epoch - _days * 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  _WC_FLOOR=$(date -u -d "@$(( _now_epoch - (_days - 1) * 86400 ))" +%Y-%m-%d 2>/dev/null \
    || date -u -r "$(( _now_epoch - (_days - 1) * 86400 ))" +%Y-%m-%d 2>/dev/null)
  return 0
}

# _fmt_brief <seconds> — single-unit age into _BRIEF_FMT ("Xs"/"Xm"/"Xh"/"Xd").
# Negative input clamps to 0s.
_fmt_brief() {
  local _s=${1:-0}
  (( _s < 0 )) && _s=0
  if   (( _s < 60 ));    then _BRIEF_FMT="${_s}s"
  elif (( _s < 3600 ));  then printf -v _BRIEF_FMT '%dm' $(( _s / 60 ))
  elif (( _s < 86400 )); then printf -v _BRIEF_FMT '%dh' $(( _s / 3600 ))
  else                        printf -v _BRIEF_FMT '%dd' $(( _s / 86400 ))
  fi
  return 0
}
