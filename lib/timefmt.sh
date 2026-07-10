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
  # LC_TIME=C: keep %a/%b weekday/month names English (project rule: English
  # CLI output). Numeric formats (%Y-%m-%d %H:%M) are locale-immune anyway.
  if [[ -n "${_CLAUDII_TZ:-}" ]]; then
    _ABS_FMT=$(LC_TIME=C TZ="$_CLAUDII_TZ" date -r "$_e" "+$_fmt" 2>/dev/null \
      || LC_TIME=C TZ="$_CLAUDII_TZ" date -d "@$_e" "+$_fmt" 2>/dev/null) || _ABS_FMT=""
  else
    _ABS_FMT=$(LC_TIME=C date -r "$_e" "+$_fmt" 2>/dev/null \
      || LC_TIME=C date -d "@$_e" "+$_fmt" 2>/dev/null) || _ABS_FMT=""
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

# _window_cutoffs <days> — rolling-window boundaries via one BSD/GNU date probe.
# Sets _WC_CUTOFF (ISO-Z timestamp of now-<days>, a last_seen threshold) and
# _WC_FLOOR (date of now-(<days>-1), the inclusive calendar floor for "last N
# days" day-bucket filters). Both empty on date failure (callers no-op on "").
# The same inline probe lives in bin/claudii-otel and bin/claudii-insights —
# standalone scripts that don't source this file; keep those markers in sync.
_window_cutoffs() {
  local _days="${1:-7}"
  _WC_CUTOFF=""; _WC_FLOOR=""
  if date -v -1d +%Y-%m-%d >/dev/null 2>&1; then
    _WC_CUTOFF=$(date -u -v "-${_days}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    _WC_FLOOR=$(date -u -v-"$(( _days - 1 ))"d +%Y-%m-%d 2>/dev/null)
  else
    _WC_CUTOFF=$(date -u -d "${_days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    _WC_FLOOR=$(date -u -d "$(( _days - 1 )) days ago" +%Y-%m-%d 2>/dev/null)
  fi
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
