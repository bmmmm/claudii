# lib/spinner.sh — terminal loading animations
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail
#
# Usage:
#   _claudii_spinner & _sp=$!
#   ... work ...
#   kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null || true
#   printf '\r\033[K' >&2
#
# Mode selection: env CLAUDII_SPINNER_MODE > "random" (default).
# Resolved once by _spinner_start in bin/claudii (reads config key ui.spinner)
# and exported, so the spinner loop never spawns jq.
#
# To add a new mode: define _claudii_spinner_<mode>() below and add to _CLAUDII_SPINNER_MODES.

# Available randomizable modes (UTF-8). ascii is fallback only.
_CLAUDII_SPINNER_MODES=(beam wave dots pulse bounce arc orbit)

# Entry point — UTF-check, then dispatches to a mode.
_claudii_spinner() {
  if [[ "${TERM:-}" == "dumb" ]] || ! printf '%s' "${LANG:-}" | grep -qi "utf"; then
    _claudii_spinner_ascii
    return
  fi
  local _mode="${CLAUDII_SPINNER_MODE:-random}"
  if [[ "$_mode" == "random" ]]; then
    _mode="${_CLAUDII_SPINNER_MODES[$((RANDOM % ${#_CLAUDII_SPINNER_MODES[@]}))]}"
  fi
  case "$_mode" in
    beam)   _claudii_spinner_beam   ;;
    wave)   _claudii_spinner_wave   ;;
    dots)   _claudii_spinner_dots   ;;
    pulse)  _claudii_spinner_pulse  ;;
    bounce) _claudii_spinner_bounce ;;
    arc)    _claudii_spinner_arc    ;;
    orbit)  _claudii_spinner_orbit  ;;
    ascii)  _claudii_spinner_ascii  ;;
    *)      _claudii_spinner_beam   ;;
  esac
}

# ── ASCII fallback (dumb terminals, no UTF-8) ────────────────────────────────
_claudii_spinner_ascii() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM
  local frames=('|' '/' '-' '\') i=0 _label _prev_label=""
  while true; do
    _label="Loading"
    if [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" && -r "${CLAUDII_SPINNER_LABEL_FILE}" ]]; then
      { IFS= read -r _label || true; } < "$CLAUDII_SPINNER_LABEL_FILE"
      if [[ -z "$_label" ]]; then _label="Loading"
      elif (( ${#_label} > 45 )); then _label="…${_label: -44}"; fi
    fi
    [[ "$_label" != "$_prev_label" && -n "$_prev_label" ]] && printf '\n' >&2
    _prev_label="$_label"
    printf '\r%s %s %s' "${frames[$((i % 4))]}" "$_label" "${frames[$((i % 4))]}" >&2
    sleep 0.1
    (( ++i ))
  done
}

# ── Beam: ⠋ Loading ⠋  with green gradient sweeping left → right ────────────
# Both braille chars cycle independently; their brightness phase-shifts so the
# peak moves left-to-right: left symbol brightens first, right follows 2 frames
# later — giving the feel of a light beam crossing the label.
_claudii_spinner_beam() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM

  local reset=$'\033[0m'

  # 6-step green pulse curve: ramp up to neon peak, ramp back down.
  # Index 0 = very dark  …  index 4 = peak (neon green)  …  index 5 = descending
  local c0=$'\033[38;5;22m'   # very dark green
  local c1=$'\033[38;5;28m'   # dark green
  local c2=$'\033[38;5;34m'   # medium green
  local c3=$'\033[38;5;40m'   # bright green
  local c4=$'\033[38;5;46m'   # peak — neon green
  local c5=$'\033[38;5;34m'   # medium green (descending)

  # Right symbol is PD phases behind left in the color cycle.
  # This means right reaches peak PD frames AFTER left → left-to-right beam.
  local nc=6 pd=2   # nc = number of color phases, pd = beam delay in frames

  local braille=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local nb=10 i=0 _label _prev_label=""  # braille cycle length

  while true; do
    # Dynamic label: file path being processed, or "Loading" as fallback
    _label="Loading"
    if [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" && -r "${CLAUDII_SPINNER_LABEL_FILE}" ]]; then
      { IFS= read -r _label || true; } < "$CLAUDII_SPINNER_LABEL_FILE"
      if [[ -z "$_label" ]]; then _label="Loading"
      elif (( ${#_label} > 45 )); then _label="…${_label: -44}"; fi
    fi
    # New file → new line (creates a scrolling log effect)
    [[ "$_label" != "$_prev_label" && -n "$_prev_label" ]] && printf '\n' >&2
    _prev_label="$_label"

    # Color indices: left at i%nc, right at (i + nc - pd) % nc
    local li=$(( i % nc ))
    local ri=$(( (i + nc - pd) % nc ))

    # Resolve color from individual variables (avoids eval and local -a issues)
    local cl cr
    case $li in 0) cl=$c0;; 1) cl=$c1;; 2) cl=$c2;; 3) cl=$c3;; 4) cl=$c4;; *) cl=$c5;; esac
    case $ri in 0) cr=$c0;; 1) cr=$c1;; 2) cr=$c2;; 3) cr=$c3;; 4) cr=$c4;; *) cr=$c5;; esac

    # Braille: right offset by half-cycle (nb/2) so both chars are at opposite
    # points of the spinner circle — they spin in sync but look mirrored.
    local bl="${braille[$((i % nb))]}"
    local br="${braille[$(( (i + nb / 2) % nb ))]}"

    printf '\r%s%s%s %s %s%s%s' "$cl" "$bl" "$reset" "$_label" "$cr" "$br" "$reset" >&2
    sleep 0.1
    (( ++i ))
  done
}

# ── Shared label-read helper ─────────────────────────────────────────────────
# Sets _label from CLAUDII_SPINNER_LABEL_FILE; truncates to 45 chars max.
# If the label changed since last call, prints a newline (scrolling-log effect).
# Caller must declare _label and _prev_label as locals before the loop.
_claudii_spinner_read_label() {
  _label="Loading"
  if [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" && -r "${CLAUDII_SPINNER_LABEL_FILE}" ]]; then
    { IFS= read -r _label || true; } < "$CLAUDII_SPINNER_LABEL_FILE"
    if [[ -z "$_label" ]]; then _label="Loading"
    elif (( ${#_label} > 45 )); then _label="…${_label: -44}"; fi
  fi
  [[ "$_label" != "$_prev_label" && -n "$_prev_label" ]] && printf '\n' >&2
  _prev_label="$_label"
}

# ── Dots: pure braille rotation, dim/cyan ────────────────────────────────────
_claudii_spinner_dots() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM
  local braille=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local clr=$'\033[38;5;73m' reset=$'\033[0m'
  local i=0 _label _prev_label=""
  while true; do
    _claudii_spinner_read_label
    printf '\r%s%s%s %s' "$clr" "${braille[$((i % 10))]}" "$reset" "$_label" >&2
    sleep 0.1
    (( ++i ))
  done
}

# ── Pulse: single ● cycling through a brightness curve ───────────────────────
_claudii_spinner_pulse() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM
  local c0=$'\033[38;5;236m' c1=$'\033[38;5;240m' c2=$'\033[38;5;244m'
  local c3=$'\033[38;5;248m' c4=$'\033[38;5;253m' c5=$'\033[38;5;255m'
  local reset=$'\033[0m'
  local cycle=(c0 c1 c2 c3 c4 c5 c4 c3 c2 c1)
  local i=0 _label _prev_label="" cn cv
  while true; do
    _claudii_spinner_read_label
    cn="${cycle[$((i % 10))]}"; cv="${!cn}"
    printf '\r%s●%s %s' "$cv" "$reset" "$_label" >&2
    sleep 0.1
    (( ++i ))
  done
}

# ── Bounce: a dot pong-bouncing in a fixed-width track ───────────────────────
_claudii_spinner_bounce() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM
  local width=10
  local clr=$'\033[38;5;46m' track=$'\033[2m' reset=$'\033[0m'
  # Positions: 0..9, 8..1 (period 18). Smooth turnaround at endpoints.
  local positions=(0 1 2 3 4 5 6 7 8 9 8 7 6 5 4 3 2 1)
  local i=0 _label _prev_label="" pos j frame
  while true; do
    _claudii_spinner_read_label
    pos="${positions[$((i % 18))]}"
    frame=""
    for (( j=0; j<width; j++ )); do
      if (( j == pos )); then frame+="${clr}●${track}"
      else frame+="·"
      fi
    done
    printf '\r[%s%s%s] %s' "$track" "$frame" "$reset" "$_label" >&2
    sleep 0.07
    (( ++i ))
  done
}

# ── Arc: quarter-circle rotation ─────────────────────────────────────────────
_claudii_spinner_arc() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM
  local arcs=('◜' '◝' '◞' '◟')
  local clr=$'\033[38;5;213m' reset=$'\033[0m'
  local i=0 _label _prev_label=""
  while true; do
    _claudii_spinner_read_label
    printf '\r%s%s%s %s' "$clr" "${arcs[$((i % 4))]}" "$reset" "$_label" >&2
    sleep 0.12
    (( ++i ))
  done
}

# ── Orbit: two dots circling in opposite phase ───────────────────────────────
_claudii_spinner_orbit() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM
  # 8-step orbit using box-drawing line segments
  local frames=('⠁⠈' '⠂⠐' '⠄⠠' '⡀⢀' '⠠⠄' '⠐⠂' '⠈⠁' '⢀⡀')
  local clr=$'\033[38;5;141m' reset=$'\033[0m'
  local i=0 _label _prev_label=""
  while true; do
    _claudii_spinner_read_label
    printf '\r%s%s%s %s' "$clr" "${frames[$((i % 8))]}" "$reset" "$_label" >&2
    sleep 0.1
    (( ++i ))
  done
}

# ── Wave: full-width scrolling block-element hill (previous default) ─────────
# Kept as an alternative mode. Wider visual, more "ambient".
_claudii_spinner_wave() {
  trap 'printf "\r\033[K" >&2' EXIT
  trap 'exit 0' TERM

  local cols="${COLUMNS:-80}"
  local dim="${CLAUDII_CLR_DIM:-}" reset="${CLAUDII_CLR_RESET:-}"
  local braille=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local label=" Loading  "   # 10 chars
  local prefix_len=11
  local wave_cols=$(( cols - prefix_len ))
  (( wave_cols < 4 )) && wave_cols=4

  local wave='▁▂▃▄▅▆▇█▇▆▅▄▃▂▁ '
  local wlen=16
  local pattern=''
  while (( ${#pattern} < wave_cols + wlen )); do
    pattern+="$wave"
  done

  local i=0
  while true; do
    printf '\r%s%s%s%s%s' \
      "$dim" "${braille[$((i % 10))]}" "$label" "${pattern:$i:$wave_cols}" "$reset" >&2
    sleep 0.08
    i=$(( (i + 1) % wlen ))
  done
}
