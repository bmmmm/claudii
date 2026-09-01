# lib/cmd/week.sh — claudii week (Anthropic weekly rate-limit window)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

# Observed windows, ascending by first sighting: "reset<TAB>first<TAB>last" rows.
# Empty before this feature shipped (column 11 did not exist yet).
_week_observed() {
  local _dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _collect_history_files "$_dir"
  (( ${#_HIST_FILES[@]} )) || return 1
  LC_ALL=C awk -F'\t' -f "$CLAUDII_HOME/lib/window_bounds.awk" "${_HIST_FILES[@]}" 2>/dev/null \
    | LC_ALL=C sort -t"$(printf '\t')" -k2,2n
}

# Sharpen _WW_START using what was actually observed, and flag a window that
# came in short. Anthropic sometimes ends a weekly window early for technical
# reasons; then the reset it had announced never fires, so "reset minus seven
# days" would invent a start that never existed. The real boundary is where the
# announced reset value changes — the first row carrying the current one.
# Sets _WW_SHORT=1 when the resulting window is materially under seven days.
_WW_SHORT=0
_week_resolve_start() {
  _WW_SHORT=0
  [[ "$_WW_RESET" =~ ^[0-9]+$ ]] || return 1
  local _obs; _obs=$(_week_observed 2>/dev/null)
  [[ -n "$_obs" ]] || return 0
  # The first sighting of the current reset is only the window's start if an
  # EARLIER window was observed too. Otherwise it merely marks when recording
  # began — for the first window after this feature shipped that is today, and
  # trusting it would shrink the window to a few hours.
  local _prev_n
  _prev_n=$(LC_ALL=C awk -F'\t' -v cur="$_WW_RESET" '$1 + 0 < cur {n++} END{print n+0}' <<< "$_obs")
  [[ "$_prev_n" =~ ^[0-9]+$ ]] && (( _prev_n > 0 )) || return 0
  local _first
  _first=$(LC_ALL=C awk -F'\t' -v cur="$_WW_RESET" '$1 + 0 == cur { print $2; exit }' <<< "$_obs")
  [[ "$_first" =~ ^[0-9]+$ ]] || return 0

  # Round down to the hour: a window opens with the first prompt after a reset
  # and the reported reset sits on a whole hour, so the first render we see is
  # a few minutes into it (measured: first prompt 13:06:22, window start 13:00).
  local _cand=$(( _first - _first % 3600 ))
  local _grid=$(( _WW_RESET - 604800 ))
  local _diff=$(( _cand - _grid )); (( _diff < 0 )) && _diff=$(( -_diff ))
  # Within a couple of hours of the 7-day grid it IS the 7-day grid; the grid
  # value is the more precise of the two (it needs no first-sighting luck).
  if (( _diff > 7200 )); then
    _WW_START=$_cand
    (( _WW_RESET - _WW_START < 561600 )) && _WW_SHORT=1   # under 6.5d
  fi
  return 0
}

# Fill _WK_* from lib/window.awk for the window _week_window() found.
# Returns 1 when no window is known (Claude Code drops seven_day once its
# resets_at passes, and until the next API response), so every caller can
# print its own "nothing to show yet" line.
_WK_TOK= _WK_COST= _WK_SESSIONS= _WK_LIMIT= _WK_LIMIT_SRC= _WK_EXHAUST=
_week_stats() {
  _WK_TOK=0 _WK_COST=0 _WK_SESSIONS=0 _WK_LIMIT=0 _WK_LIMIT_SRC="" _WK_EXHAUST=0
  _week_window || return 1
  _week_resolve_start

  local _dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  # Keep a month of run-up: attr_delta() needs a session's earlier rows to hold
  # a correct baseline, and a file is kept whole once its mtime clears the
  # cutoff. Cutting at _WW_START exactly would drop the previous month and
  # mis-book the first in-window row of any session that started there.
  _collect_history_files "$_dir" $(( _WW_START - 2592000 ))
  (( ${#_HIST_FILES[@]} )) || return 1

  local _attr_awk; _attr_awk=$(<"$CLAUDII_HOME/lib/attribution.awk")
  local _win_awk;  _win_awk=$(<"$CLAUDII_HOME/lib/window.awk")

  # LC_ALL=C, not LC_NUMERIC: a comma locale makes onetrueawk truncate
  # "12.34"+0 at the radix, corrupting the cost sum itself — not just its
  # rendering (see the locale+awk lesson).
  local _row
  _row=$(LC_ALL=C awk -F'\t' -v window_start="$_WW_START" \
    "${_attr_awk}
${_win_awk}" "${_HIST_FILES[@]}" 2>/dev/null)
  [[ -n "$_row" ]] || return 1

  local _pct_lo _tok_lo _pct_hi _tok_hi
  IFS=$'\t' read -r _WK_TOK _WK_COST _WK_SESSIONS _pct_lo _tok_lo _pct_hi _tok_hi <<< "$_row"

  # Quota size in tokens. Anthropic never publishes it, so it is inferred:
  #   measured — from Δtokens across a percentage spread inside this window.
  #     Independent of where the window started, so it beats the estimate below,
  #     but the percentages are 1%-grained: a narrow spread amplifies rounding
  #     into a wild figure, hence the >=10 gate.
  #   estimated — tokens-so-far over percent-used. Available from the first run,
  #     but it inherits any error in the window start.
  # Either way it stays an approximation: Anthropic weighs models and cache
  # differently than raw token counts, so this is never billed truth.
  local _calc
  _calc=$(LC_ALL=C awk -v tok="$_WK_TOK" -v pct="${_WW_PCT:-0}" \
    -v plo="$_pct_lo" -v tlo="$_tok_lo" -v phi="$_pct_hi" -v thi="$_tok_hi" \
    -v start="$_WW_START" -v now="$(date +%s)" '
    BEGIN {
      dp = phi - plo
      if (dp >= 10 && thi > tlo) { limit = (thi - tlo) / (dp / 100); src = "measured" }
      else if (pct + 0 > 0)      { limit = tok / (pct / 100);        src = "estimated" }
      else                       { limit = 0; src = "" }

      # Burn-through moment at the pace held so far. Only meaningful while the
      # window has actually run for a bit and the quota is not already spent.
      elapsed = now - start
      exhaust = 0
      if (limit > tok && elapsed > 3600 && tok > 0)
        exhaust = now + (limit - tok) / (tok / elapsed)

      printf "%d\t%s\t%d", limit, src, exhaust
    }')
  IFS=$'\t' read -r _WK_LIMIT _WK_LIMIT_SRC _WK_EXHAUST <<< "$_calc"
  return 0
}

# The window block, shared by `claudii week` and `claudii limits`.
_week_render_block() {
  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" yellow="${CLAUDII_CLR_YELLOW}" green="${CLAUDII_CLR_GREEN}"
  local _now; _now=$(date +%s)

  local _from _to
  _fmt_abs "$_WW_START" '%a %d.%m %H:%M'; _from="$_ABS_FMT"
  _fmt_abs "$_WW_RESET" '%a %d.%m %H:%M'; _to="$_ABS_FMT"

  printf '\n  %sWeekly limit%s  %s(window: %s \342\206\222 %s)%s\n\n' \
    "$accent" "$reset" "$dim" "$_from" "$_to" "$reset"

  # LC_ALL=C for the one float: bash printf follows LC_NUMERIC, so a comma
  # locale rejects the dot-decimal awk handed us ("invalid number") and prints
  # $3206,00. Formatted once here, emitted as a string below.
  local _cost_fmt; LC_ALL=C printf -v _cost_fmt '%.2f' "$_WK_COST"
  printf '    %sUsed%s      %s%s%s tokens \302\267 %s$%s%s \302\267 %d sessions\n' \
    "$dim" "$reset" "$cyan" "$(_fmt_tok "$_WK_TOK")" "$reset" \
    "$cyan" "$_cost_fmt" "$reset" "$_WK_SESSIONS"

  # Colour tracks used%, matching every other rate display in claudii.
  local _pct_int="${_WW_PCT%.*}"; [[ "$_pct_int" =~ ^[0-9]+$ ]] || _pct_int=0
  local _pc="$green"
  (( _pct_int >= 50 )) && _pc="$yellow"
  (( _pct_int >= 80 )) && _pc="${CLAUDII_CLR_RED:-$yellow}"

  if [[ -n "$_WK_LIMIT_SRC" ]] && (( _WK_LIMIT > _WK_TOK )); then
    printf '    %sQuota%s     %s%s%%%s used \302\267 ~%s left %s(%s)%s\n' \
      "$dim" "$reset" "$_pc" "$_pct_int" "$reset" \
      "$(_fmt_tok $(( _WK_LIMIT - _WK_TOK )))" "$dim" "$_WK_LIMIT_SRC" "$reset"
  else
    printf '    %sQuota%s     %s%s%%%s used\n' "$dim" "$reset" "$_pc" "$_pct_int" "$reset"
  fi

  local _rel; _fmt_rel $(( _WW_RESET - _now )); _rel="${_REL_FMT:-now}"
  local _rt; _fmt_abs "$_WW_RESET" '%a %H:%M'; _rt="$_ABS_FMT"
  printf '    %sResets%s    in %s  %s(%s)%s\n' "$dim" "$reset" "$_rel" "$dim" "$_rt" "$reset"

  # An Anthropic-shortened window is worth saying out loud: the quota did not
  # run its usual seven days, so the pace and the estimate below cover less
  # ground than they normally would.
  if (( ${_WW_SHORT:-0} )); then
    printf '    %sNote%s      window is short (%dd) \342\200\224 Anthropic reset it early\n' \
      "$dim" "$reset" "$(( (_WW_RESET - _WW_START) / 86400 ))"
  fi

  # Pace: the daily burn so far, and whether it outruns the reset.
  local _elapsed=$(( _now - _WW_START ))
  if (( _elapsed > 3600 && _WK_TOK > 0 )); then
    local _per_day=$(( _WK_TOK * 86400 / _elapsed ))
    if (( _WK_EXHAUST > 0 && _WK_EXHAUST < _WW_RESET )); then
      local _et; _fmt_abs "$_WK_EXHAUST" '%a %H:%M'; _et="$_ABS_FMT"
      printf '    %sPace%s      %s/day \302\267 %sruns out %s%s \342\232\240\n' \
        "$dim" "$reset" "$(_fmt_tok "$_per_day")" "$yellow" "$_et" "$reset"
    else
      printf '    %sPace%s      %s/day \302\267 %sholds to reset%s\n' \
        "$dim" "$reset" "$(_fmt_tok "$_per_day")" "$green" "$reset"
    fi
  fi
  printf '\n'
}

# Per-window bars over the last N windows. Boundaries come from what was
# observed where possible; older ones are extrapolated on the 7-day grid and
# labelled as such, because Anthropic's early resets mean a grid is an
# assumption about the past, not a fact.
_week_history_render() {
  local _count="${1:-8}"
  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" green="${CLAUDII_CLR_GREEN}" yellow="${CLAUDII_CLR_YELLOW}"

  local _b=() _r _f _l _rounded
  while IFS=$'\t' read -r _r _f _l; do
    [[ "$_f" =~ ^[0-9]+$ ]] || continue
    _rounded=$(( _f - _f % 3600 ))
    (( _rounded < _WW_START )) && _b+=("$_rounded")
  done < <(_week_observed 2>/dev/null)

  # Everything below the SECOND observed boundary is reconstructed: the oldest
  # sighting only marks when recording started, so the window it opens is not
  # actually pinned down (same reasoning as _week_resolve_start).
  local _measured_from="$_WW_START"
  (( ${#_b[@]} >= 2 )) && _measured_from="${_b[1]}"
  _b+=("$_WW_START")
  local _earliest="${_b[0]}"
  while (( ${#_b[@]} < _count )); do
    _earliest=$(( _earliest - 604800 ))
    _b=("$_earliest" "${_b[@]}")
  done
  _b+=("$_WW_RESET")

  local _bounds; _bounds=$(IFS=,; printf '%s' "${_b[*]}")
  local _dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _collect_history_files "$_dir" $(( ${_b[0]} - 2592000 ))
  (( ${#_HIST_FILES[@]} )) || return 1

  local _attr_awk; _attr_awk=$(<"$CLAUDII_HOME/lib/attribution.awk")
  local _hist_awk; _hist_awk=$(<"$CLAUDII_HOME/lib/window_history.awk")
  local _rows
  _rows=$(LC_ALL=C awk -F'\t' -v bounds="$_bounds" \
    "${_attr_awk}
${_hist_awk}" "${_HIST_FILES[@]}" 2>/dev/null)
  [[ -n "$_rows" ]] || return 1

  local _max=0 _s _e _t _c _n
  while IFS=$'\t' read -r _s _e _t _c _n; do
    (( _t > _max )) && _max=$_t
  done <<< "$_rows"
  (( _max > 0 )) || return 1

  printf '\n  %sWeekly limit%s %s— last %d windows%s\n\n' \
    "$accent" "$reset" "$dim" "$_count" "$reset"

  local _now; _now=$(date +%s)
  local _lbl _bar _cost_fmt _mark _from _to
  while IFS=$'\t' read -r _s _e _t _c _n; do
    _fmt_abs "$_s" '%d.%m'; _from="$_ABS_FMT"
    _fmt_abs "$_e" '%d.%m'; _to="$_ABS_FMT"
    _lbl="$_from \342\206\222 $_to"
    LC_ALL=C printf -v _cost_fmt '$%.0f' "$_c"
    # Flag what the data cannot vouch for: a reconstructed boundary, and a
    # window that came in short (an early Anthropic reset).
    _mark=""
    (( _s < _measured_from )) && _mark="${dim}~${reset}"
    (( _e - _s < 561600 )) && _mark="${yellow}short${reset}"
    (( _s == _WW_START )) && _mark="${green}current${reset}"
    printf '  %-16b %s%9s%s  %s  %s%8s%s  %b\n' \
      "$_lbl" "$cyan" "$(_fmt_tok "$_t")" "$reset" \
      "$(_bar_c "$(( _t * 28 / _max ))" 28)" \
      "$dim" "$_cost_fmt" "$reset" "$_mark"
  done <<< "$_rows"

  if (( ${_b[0]} < _measured_from )); then
    printf '\n  %s~ boundary reconstructed on a 7-day grid — Claude Code reports no past\n' "$dim"
    printf '    resets, and Anthropic may end a window early. Measured from %s.%s\n' \
      "$(_fmt_abs "$_measured_from" '%d.%m %H:%M'; printf '%s' "$_ABS_FMT")" "$reset"
  fi
  printf '\n'
}

_week_json() {
  LC_ALL=C jq -n \
    --argjson start "$_WW_START" --argjson reset "$_WW_RESET" \
    --argjson pct "${_WW_PCT:-0}" --argjson tok "$_WK_TOK" \
    --argjson cost "$_WK_COST" --argjson sessions "$_WK_SESSIONS" \
    --argjson limit "$_WK_LIMIT" --arg src "$_WK_LIMIT_SRC" \
    --argjson exhaust "$_WK_EXHAUST" '{
      window_start: $start, window_reset: $reset,
      used_percentage: $pct, tokens: $tok, cost: $cost, sessions: $sessions,
      limit_estimate: (if $limit > 0 then $limit else null end),
      limit_source: (if $src == "" then null else $src end),
      tokens_left: (if $limit > $tok then $limit - $tok else null end),
      exhausts_at: (if $exhaust > 0 then $exhaust else null end)
    }'
}

_cmd_week() {
  _cfg_init

  local _arg _history=0 _count=8
  for _arg in "${@:2}"; do
    case "$_arg" in
      -h|--help)
        printf 'Usage: claudii week [--history [N]] [--json]\n\n'
        printf "Usage inside Anthropic's rolling 7-day rate-limit window — the\n"
        printf 'quota that actually gates work, not the calendar week.\n\n'
        printf '  --history [N]  per-window bars over the last N windows (default 8)\n'
        printf '  --json         machine-readable output\n'
        return 0 ;;
      --json) _FORMAT=json ;;
      --history) _history=1 ;;
      [0-9]|[0-9][0-9]) (( _history )) && _count="$_arg" ;;
      *) printf 'Unknown option: %s\n' "$_arg" >&2; return 1 ;;
    esac
  done

  if ! _week_stats; then
    [[ "${_FORMAT:-}" == "json" ]] && { printf '{}\n'; return 0; }
    printf '\n  %sNo weekly window known yet%s — Claude Code reports it after the\n' \
      "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
    printf '  first API response of a session, and drops it once the quota resets.\n\n'
    return 0
  fi

  [[ "${_FORMAT:-}" == "json" ]] && { _week_json; return 0; }
  if (( _history )); then
    _week_history_render "$_count" && return 0
    printf '\n  %sNot enough history for a per-window view yet.%s\n\n' \
      "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
    return 0
  fi
  _week_render_block
  return 0
}
