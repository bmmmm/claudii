# lib/spinner.sh — terminal loading animations
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail
#
# Usage:
#   _claudii_spinner & _sp=$!
#   ... work ...
#   kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null || true
#   printf '\r\033[K' >&2
#
# To add a new mode: define _claudii_spinner_<mode>() below.
# Future: read mode from config (ui.spinner) and dispatch in _claudii_spinner().

# Entry point — UTF-check, then delegates to beam animation.
_claudii_spinner() {
  if [[ "${TERM:-}" == "dumb" ]] || ! printf '%s' "${LANG:-}" | grep -qi "utf"; then
    _claudii_spinner_ascii
    return
  fi
  _claudii_spinner_beam
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
