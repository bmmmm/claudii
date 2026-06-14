# lib/render.sh — shared display renderers (bash 3.2 compatible).
#
# Sourced by bin/claudii after helpers.sh. Pure function defs, no side effects.
# Callers must have the visual.sh constants in scope (CLAUDII_SYM_BAR_*).
#
# These are the bash-side mirrors of lib/fmt.awk: the awk programs (cost/trends)
# stream large history files and format in-process, while the jq-backed commands
# (cache/tokens/session/tools) aggregate small JSON and render here in bash.
# Keep _fmt_tok's K/M/B thresholds in sync with fmt.awk's fmt_tok().
#
# NOTE: the composite B-style bar ROW (label │ value │ bar │ trail) lands here
# with its first real consumer (`claudii tokens`) so the column API is derived
# from a concrete layout rather than guessed up front.

# Token / large-number short form: K/M/B. Pure integer math — no awk fork (this
# replaces _insights_short_num's per-call `awk`). 0 → "0", sub-1000 → as-is,
# K rounded, M/B rounded to one decimal. Non-numeric input → "0".
_fmt_tok() {
  local n="${1:-0}" t
  case "$n" in ''|*[!0-9]*) printf '0'; return ;; esac
  if (( n >= 1000000000 )); then
    t=$(( (n + 50000000) / 100000000 ))     # tenths of a billion, rounded
    printf '%d.%dB' $(( t / 10 )) $(( t % 10 ))
  elif (( n >= 1000000 )); then
    t=$(( (n + 50000) / 100000 ))           # tenths of a million, rounded
    printf '%d.%dM' $(( t / 10 )) $(( t % 10 ))
  elif (( n >= 1000 )); then
    printf '%dK' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}

# Cache hit percentage: cache_read / (cache_read + input), integer 0..100,
# rounded. Denominator 0 (or non-numeric input) → "0".
_cache_hit_pct() {
  local cr="${1:-0}" inp="${2:-0}" denom
  [[ "$cr"  =~ ^[0-9]+$ ]] || cr=0
  [[ "$inp" =~ ^[0-9]+$ ]] || inp=0
  denom=$(( cr + inp ))
  (( denom <= 0 )) && { printf '0'; return; }
  printf '%d' $(( (cr * 200 / denom + 1) / 2 ))
}

# Bar of `width` cells, `filled` full (BAR_FULL) + the rest empty (BAR_EMPTY).
# Uncoloured — the caller wraps it in colour. Pure string; clamps to 0..width.
_bar() {
  local filled="${1:-0}" width="${2:-20}" i out=""
  [[ "$filled" =~ ^[0-9]+$ ]] || filled=0
  (( filled > width )) && filled=$width
  for (( i=0; i<filled; i++ ));     do out+="$CLAUDII_SYM_BAR_FULL"; done
  for (( i=filled; i<width; i++ )); do out+="$CLAUDII_SYM_BAR_EMPTY"; done
  printf '%s' "$out"
}

# Filled cells for value/max over `width`, rounded, clamped 0..width. max <= 0 → 0.
# Integer math: value*width*2 stays well under 64-bit for any token count.
_bar_filled() {
  local value="${1:-0}" max="${2:-0}" width="${3:-20}"
  [[ "$value" =~ ^[0-9]+$ ]] || value=0
  [[ "$max"   =~ ^[0-9]+$ ]] || max=0
  (( max <= 0 )) && { printf '0'; return; }
  local f=$(( (value * width * 2 / max + 1) / 2 ))
  (( f > width )) && f=$width
  printf '%d' "$f"
}
