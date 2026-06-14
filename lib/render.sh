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

# Repeat a (possibly multi-byte) string `n` times. Used for rules (─) and
# manual padding where a UTF-8 char would defeat printf's byte-based %*s.
_rep() {
  local c="$1" n="${2:-0}" i out=""
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for (( i=0; i<n; i++ )); do out+="$c"; done
  printf '%s' "$out"
}

# Coloured bar: `filled` cyan BAR_FULL cells then dim BAR_EMPTY to `width`.
# Wrapped CYAN…DIM…RESET (matches cost.sh's awk bars). filled clamped 0..width.
_bar_c() {
  local filled="${1:-0}" width="${2:-20}" i
  [[ "$filled" =~ ^[0-9]+$ ]] || filled=0
  (( filled > width )) && filled=$width
  printf '%s' "$CLAUDII_CLR_CYAN"
  for (( i=0; i<filled; i++ ));     do printf '%s' "$CLAUDII_SYM_BAR_FULL"; done
  printf '%s' "$CLAUDII_CLR_DIM"
  for (( i=filled; i<width; i++ )); do printf '%s' "$CLAUDII_SYM_BAR_EMPTY"; done
  printf '%s' "$CLAUDII_CLR_RESET"
}

# B-style section header: accent title left, dim note right, padded to `width`,
# followed by a dim ─ rule. Both strings must be ASCII (byte-width == columns).
_render_shead() {
  local title="$1" note="${2:-}" width="${3:-66}" pad
  pad=$(( width - ${#title} - ${#note} )); (( pad < 2 )) && pad=2
  printf '  %s%s%s%*s%s%s%s\n' \
    "$CLAUDII_CLR_ACCENT" "$title" "$CLAUDII_CLR_RESET" \
    "$pad" "" \
    "$CLAUDII_CLR_DIM" "$note" "$CLAUDII_CLR_RESET"
  printf '  %s%s%s\n' "$CLAUDII_CLR_DIM" "$(_rep '─' "$width")" "$CLAUDII_CLR_RESET"
}

# B-style bar row: `<label LW left>  <val VW right, cyan>   <bar>   <suffix>`.
# label/val must be ASCII (printf widths are byte-based); `suffix` is appended
# verbatim (caller owns its colour). bf/bw are the bar's filled count + width.
# Args: label label_w val val_w bar_filled bar_width suffix
_render_bar_row() {
  local label="$1" lw="$2" val="$3" vw="$4" bf="$5" bw="$6" suffix="${7:-}"
  printf '  %-*s  %s%*s%s   %s   %s\n' \
    "$lw" "$label" \
    "$CLAUDII_CLR_CYAN" "$vw" "$val" "$CLAUDII_CLR_RESET" \
    "$(_bar_c "$bf" "$bw")" \
    "$suffix"
}

# D-style matrix (│/┼ separators, no outer frame) — the bash mirror of cost.sh's
# awk render_dgrid, for jq-backed commands. Column widths track the widest cell
# so the rules line up. Header in accent, row labels dim, cells cyan. All cell
# and header text must be ASCII (use "-" not "—" for blanks).
#   Args:  $1 = label-column header   $2 = US-joined data-column headers
#   Stdin: one row per line = label US cell1 US cell2 …   (US = \x1f / 0x1f)
# A non-whitespace delimiter is used on purpose so empty cells survive the split
# (IFS=$'\t' would collapse them — see CLAUDE.md). Cells are right-aligned.
_render_dgrid() {
  local lhdr="$1" chdr="$2" sep=$'\x1f'
  local -a chead; IFS="$sep" read -r -a chead <<< "$chdr"
  local ncol=${#chead[@]} i line
  local -a cw rlabels rcells
  local lblw=${#lhdr}
  for (( i=0; i<ncol; i++ )); do cw[i]=${#chead[i]}; done
  local nrow=0
  # `|| [[ -n $line ]]` so a final row without a trailing newline is not dropped
  # — _cmd_tokens always terminates rows, but other consumers of this shared
  # renderer may pipe an unterminated stream.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    local -a f; IFS="$sep" read -r -a f <<< "$line"
    local lbl="${f[0]}"
    (( ${#lbl} > lblw )) && lblw=${#lbl}
    rlabels[nrow]="$lbl"
    for (( i=0; i<ncol; i++ )); do
      local cell="${f[$((i+1))]}"
      rcells[$((nrow*ncol+i))]="$cell"
      (( ${#cell} > cw[i] )) && cw[i]=${#cell}
    done
    (( ++nrow ))
  done
  (( nrow == 0 )) && { printf '    %s(none)%s\n' "$CLAUDII_CLR_DIM" "$CLAUDII_CLR_RESET"; return; }

  # Header row (label col carries a trailing space before the first │)
  printf '  %s%-*s%s ' "$CLAUDII_CLR_DIM" "$lblw" "$lhdr" "$CLAUDII_CLR_RESET"
  for (( i=0; i<ncol; i++ )); do
    printf '%s│%s %s%*s%s ' \
      "$CLAUDII_CLR_DIM" "$CLAUDII_CLR_RESET" \
      "$CLAUDII_CLR_ACCENT" "${cw[i]}" "${chead[i]}" "$CLAUDII_CLR_RESET"
  done
  printf '\n'
  # Rule (plain, matches cost.sh's D-grid)
  printf '  %s' "$(_rep '─' $((lblw+1)))"
  for (( i=0; i<ncol; i++ )); do printf '┼%s' "$(_rep '─' $((cw[i]+2)))"; done
  printf '\n'
  # Data rows
  local r
  for (( r=0; r<nrow; r++ )); do
    printf '  %s%-*s%s ' "$CLAUDII_CLR_DIM" "$lblw" "${rlabels[r]}" "$CLAUDII_CLR_RESET"
    for (( i=0; i<ncol; i++ )); do
      printf '%s│%s %s%*s%s ' \
        "$CLAUDII_CLR_DIM" "$CLAUDII_CLR_RESET" \
        "$CLAUDII_CLR_CYAN" "${cw[i]}" "${rcells[$((r*ncol+i))]}" "$CLAUDII_CLR_RESET"
    done
    printf '\n'
  done
}
