# lib/cmd/week.sh — claudii week (Anthropic weekly rate-limit window)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

# A window materially under seven days — Anthropic ended it early. One name,
# because the same threshold decides _WW_SHORT, the `short` marker on a history
# bar, and the `short` flag in --json; three literals would drift apart.
_WEEK_SHORT_SECS=561600   # 6.5d

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
  #
  # Sanity guards. The observed boundary is only as good as column 11, and a
  # corrupt value there would otherwise move the window somewhere impossible —
  # a start in the future, or weeks back — silently rebasing every number in
  # the block. A rejected candidate is not an error: _WW_START simply stays on
  # the reset-minus-7d grid, which is what it was before this feature existed.
  #   * the window must have started (_cand < now)
  #   * the window must not already be over (_WW_RESET > now) — a stale
  #     session cache can carry a reset that has since passed
  #   * its length must be plausible (1h .. 8d); Anthropic shortens windows,
  #     but never to minutes, and never past the announced seven days
  # The upper bound is belt-and-braces: window_bounds.awk already drops a row
  # whose announced reset is more than eight days out, so _first cannot be
  # older than that. It is 8d PLUS an hour because _cand is _first floored to
  # the hour — without the slack, flooring alone could push a legitimate
  # eight-day boundary over the line.
  local _now; _now=$(date +%s)
  local _len=$(( _WW_RESET - _cand ))
  if (( _diff > 7200 )) && (( _cand < _now )) && (( _WW_RESET > _now )) \
     && (( _len >= 3600 )) && (( _len <= 694800 )); then
    _WW_START=$_cand
    (( _WW_RESET - _WW_START < _WEEK_SHORT_SECS )) && _WW_SHORT=1
  fi
  return 0
}

# Fill _WK_* from lib/window.awk for the window _week_window() found.
# Returns 1 when no window is known (Claude Code drops seven_day once its
# resets_at passes, and until the next API response), so every caller can
# print its own "nothing to show yet" line.
_WK_TOK= _WK_COST= _WK_SESSIONS= _WK_LIMIT= _WK_LIMIT_SRC= _WK_EXHAUST= _WK_CENTS=
_WK_LIMIT_LO= _WK_LIMIT_HI=

# Integer cents -> "1234.56". Locale-immune by construction: no %f anywhere on
# the pretty path, because a VAR=C prefix on bash's printf builtin does not
# reliably reload the locale — it worked locally and silently kept a comma
# locale on CI, aborting the render mid-block.
_usd_from_cents() {
  local _c="${1:-0}" _neg=""
  [[ "$_c" =~ ^-?[0-9]+$ ]] || _c=0
  if (( _c < 0 )); then _neg="-"; _c=$(( -_c )); fi
  printf '%s%d.%02d' "$_neg" $(( _c / 100 )) $(( _c % 100 ))
}

_week_stats() {
  _WK_TOK=0 _WK_COST=0 _WK_SESSIONS=0 _WK_LIMIT=0 _WK_LIMIT_SRC="" _WK_EXHAUST=0 _WK_CENTS=0
  _WK_LIMIT_LO=0 _WK_LIMIT_HI=0
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

  local _lim_lo _lim_med _lim_hi _lim_pairs
  IFS=$'\t' read -r _WK_TOK _WK_COST _WK_SESSIONS _lim_lo _lim_med _lim_hi _lim_pairs \
    _WK_CENTS <<< "$_row"

  # Quota size in tokens. Anthropic never publishes it, so it is inferred:
  #   measured — the Theil-Sen median of the per-pair slopes window.awk found
  #     inside this window. Independent of where the window started, so it
  #     beats the estimate below.
  #   estimated — tokens-so-far over percent-used. Available from the first run,
  #     but it inherits any error in the window start.
  # Either way it stays an approximation: Anthropic weighs models and cache
  # differently than raw token counts, so this is never billed truth. Which is
  # the point of the band: _WK_LIMIT_LO/_HI are the extreme slopes, so the
  # display can admit the spread instead of printing one confident number over
  # data that disagrees with itself. Whether Anthropic counts proportionally to
  # raw tokens at all is answered by that width — no separate probe needed.
  local _calc
  _calc=$(LC_ALL=C awk -v tok="$_WK_TOK" -v pct="${_WW_PCT:-0}" \
    -v lo="$_lim_lo" -v med="$_lim_med" -v hi="$_lim_hi" \
    -v start="$_WW_START" -v now="$(date +%s)" '
    BEGIN {
      if (med + 0 > 0)      { limit = med; src = "measured" }
      else if (pct + 0 > 0) { limit = tok / (pct / 100); src = "estimated" }
      else                  { limit = 0; src = "" }

      # Collapse a band narrower than 10% of the estimate: the support points
      # agree, and a range would then suggest an uncertainty that is not there.
      blo = 0; bhi = 0
      if (limit > 0 && hi + 0 > lo + 0 && (hi - lo) * 100 / limit >= 10) {
        blo = lo; bhi = hi
      }

      # Burn-through moment at the pace held so far. Only meaningful while the
      # window has actually run for a bit and the quota is not already spent.
      elapsed = now - start
      exhaust = 0
      if (limit > tok && elapsed > 3600 && tok > 0)
        exhaust = now + (limit - tok) / (tok / elapsed)

      printf "%d\t%s\t%d\t%d\t%d", limit, src, exhaust, blo, bhi
    }')
  IFS=$'\t' read -r _WK_LIMIT _WK_LIMIT_SRC _WK_EXHAUST _WK_LIMIT_LO _WK_LIMIT_HI <<< "$_calc"
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

  local _cost_fmt; _cost_fmt=$(_usd_from_cents "$_WK_CENTS")
  printf '    %sUsed%s      %s%s%s tokens \302\267 %s$%s%s \302\267 %d sessions\n' \
    "$dim" "$reset" "$cyan" "$(_fmt_tok "$_WK_TOK")" "$reset" \
    "$cyan" "$_cost_fmt" "$reset" "$_WK_SESSIONS"

  # Colour tracks used%, matching every other rate display in claudii.
  local _pct_int="${_WW_PCT%.*}"; [[ "$_pct_int" =~ ^[0-9]+$ ]] || _pct_int=0
  local _pc="$green"
  (( _pct_int >= 50 )) && _pc="$yellow"
  (( _pct_int >= 80 )) && _pc="${CLAUDII_CLR_RED:-$yellow}"

  if [[ -n "$_WK_LIMIT_SRC" ]] && (( _WK_LIMIT > _WK_TOK )); then
    # A band, when the support points disagree by more than 10% — printing one
    # number over data that spread that wide would claim a precision the
    # percentages cannot carry. Collapses to the point estimate when they agree,
    # and when the low end is already spent (a "left" range starting below zero
    # says nothing the point estimate does not).
    if (( ${_WK_LIMIT_LO:-0} > _WK_TOK )); then
      printf '    %sQuota%s     %s%s%%%s used \302\267 ~%s\342\200\223%s left %s(%s)%s\n' \
        "$dim" "$reset" "$_pc" "$_pct_int" "$reset" \
        "$(_fmt_tok $(( _WK_LIMIT_LO - _WK_TOK )))" \
        "$(_fmt_tok $(( _WK_LIMIT_HI - _WK_TOK )))" "$dim" "$_WK_LIMIT_SRC" "$reset"
    else
      printf '    %sQuota%s     %s%s%%%s used \302\267 ~%s left %s(%s)%s\n' \
        "$dim" "$reset" "$_pc" "$_pct_int" "$reset" \
        "$(_fmt_tok $(( _WK_LIMIT - _WK_TOK )))" "$dim" "$_WK_LIMIT_SRC" "$reset"
    fi
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
# Boundary + per-window aggregation, with no rendering in it. Split out so the
# bars and --json are two views of ONE computation: the entangled version was
# why --json silently ignored --history for a whole release.
# Sets _WH_ROWS (TSV: start end tokens cost_cents sessions) and
# _WH_MEASURED_FROM; returns 1 when there is nothing to show.
_WH_ROWS= _WH_MEASURED_FROM= _WH_EARLIEST=
# Accepts either form of span: "30d" selects every window OVERLAPPING the last
# 30 days, a bare "6" selects six windows. Days is the default because it is
# what the rest of claudii speaks (repos/cost/trends all default to 30d), and
# because a window count is a poor proxy for a period once Anthropic ends one
# early. A window is never sliced: the oldest bar may reach back past the
# cutoff, and its label says so.
_week_history_rows() {
  local _spec="${1:-30d}"
  _WH_ROWS= _WH_MEASURED_FROM= _WH_EARLIEST= _WH_LABEL=

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
  if [[ "$_spec" == *d ]]; then
    local _days="${_spec%d}"
    local _cutoff=$(( $(date +%s) - _days * 86400 ))
    # Reach back past the cutoff on the 7-day grid where nothing was observed,
    # then drop the windows that ended before it — those lie fully outside the
    # period. The guard keeps the running window even for a tiny span.
    while (( _earliest > _cutoff )); do
      _earliest=$(( _earliest - 604800 ))
      _b=("$_earliest" "${_b[@]}")
    done
    while (( ${#_b[@]} > 1 )) && (( ${_b[1]} <= _cutoff )); do
      _b=("${_b[@]:1}")
    done
    _WH_LABEL="last $_days days"
  else
    while (( ${#_b[@]} < _spec )); do
      _earliest=$(( _earliest - 604800 ))
      _b=("$_earliest" "${_b[@]}")
    done
    _WH_LABEL="last $_spec windows"
  fi
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

  _WH_ROWS="$_rows"
  _WH_MEASURED_FROM="$_measured_from"
  _WH_EARLIEST="${_b[0]}"
  return 0
}

_week_history_render() {
  local _spec="${1:-30d}"
  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" green="${CLAUDII_CLR_GREEN}" yellow="${CLAUDII_CLR_YELLOW}"

  _week_history_rows "$_spec" || return 1
  local _rows="$_WH_ROWS" _measured_from="$_WH_MEASURED_FROM"

  local _max=0 _s _e _t _c _n
  while IFS=$'\t' read -r _s _e _t _c _n; do
    (( _t > _max )) && _max=$_t
  done <<< "$_rows"
  (( _max > 0 )) || return 1

  printf '\n  %sWeekly limit%s %s— %s%s\n\n' \
    "$accent" "$reset" "$dim" "$_WH_LABEL" "$reset"

  local _now; _now=$(date +%s)
  local _lbl _bar _cost_fmt _mark _from _to
  while IFS=$'\t' read -r _s _e _t _c _n; do
    _fmt_abs "$_s" '%d.%m'; _from="$_ABS_FMT"
    _fmt_abs "$_e" '%d.%m'; _to="$_ABS_FMT"
    _lbl="$_from \342\206\222 $_to"
    _cost_fmt="\$$(( _c / 100 ))"
    # Flag what the data cannot vouch for: a reconstructed boundary, and a
    # window that came in short (an early Anthropic reset).
    _mark=""
    (( _s < _measured_from )) && _mark="${dim}~${reset}"
    (( _e - _s < _WEEK_SHORT_SECS )) && _mark="${yellow}short${reset}"
    (( _s == _WW_START )) && _mark="${green}current${reset}"
    printf '  %-16b %s%9s%s  %s  %s%8s%s  %b\n' \
      "$_lbl" "$cyan" "$(_fmt_tok "$_t")" "$reset" \
      "$(_bar_c "$(( _t * 28 / _max ))" 28)" \
      "$dim" "$_cost_fmt" "$reset" "$_mark"
  done <<< "$_rows"

  if (( _WH_EARLIEST < _measured_from )); then
    printf '\n  %s~ boundary reconstructed on a 7-day grid — Claude Code reports no past\n' "$dim"
    printf '    resets, and Anthropic may end a window early. Measured from %s.%s\n' \
      "$(_fmt_abs "$_measured_from" '%d.%m %H:%M'; printf '%s' "$_ABS_FMT")" "$reset"
  fi
  printf '\n'
}

# The bars, machine-readable. Same rows, same boundary reasoning — the flags
# are emitted as three independent booleans rather than the display's single
# marker, whose last-wins precedence (reconstructed -> short -> current) is a
# rendering choice, not a fact about the window.
_week_history_json() {
  local _spec="${1:-30d}"
  if ! _week_history_rows "$_spec"; then
    printf '{"windows":[],"measured_from":null}\n'
    return 0
  fi
  # Cost is integer cents from window_history.awk; jq divides, so no %f ever
  # touches a shell printf (see the locale note above _usd_from_cents).
  LC_ALL=C jq -R -n \
    --argjson mf "$_WH_MEASURED_FROM" \
    --argjson cur "$_WW_START" \
    --argjson shortsecs "$_WEEK_SHORT_SECS" \
    '{ windows: [ inputs | split("\t") |
         { window_start: (.[0] | tonumber),
           window_reset: (.[1] | tonumber),
           tokens:       (.[2] | tonumber),
           cost:         ((.[3] | tonumber) / 100),
           sessions:     (.[4] | tonumber) }
         | . + { reconstructed: (.window_start < $mf),
                 short:         ((.window_reset - .window_start) < $shortsecs),
                 current:       (.window_start == $cur) } ],
       measured_from: $mf }' <<< "$_WH_ROWS"
}

_week_json() {
  LC_ALL=C jq -n \
    --argjson start "$_WW_START" --argjson reset "$_WW_RESET" \
    --argjson pct "${_WW_PCT:-0}" --argjson tok "$_WK_TOK" \
    --argjson cost "$_WK_COST" --argjson sessions "$_WK_SESSIONS" \
    --argjson limit "$_WK_LIMIT" --arg src "$_WK_LIMIT_SRC" \
    --argjson llo "${_WK_LIMIT_LO:-0}" --argjson lhi "${_WK_LIMIT_HI:-0}" \
    --argjson exhaust "$_WK_EXHAUST" '{
      window_start: $start, window_reset: $reset,
      used_percentage: $pct, tokens: $tok, cost: $cost, sessions: $sessions,
      limit_estimate: (if $limit > 0 then $limit else null end),
      limit_low: (if $llo > 0 then $llo else null end),
      limit_high: (if $lhi > 0 then $lhi else null end),
      limit_source: (if $src == "" then null else $src end),
      tokens_left: (if $limit > $tok then $limit - $tok else null end),
      exhausts_at: (if $exhaust > 0 then $exhaust else null end)
    }'
}

_cmd_week() {
  _cfg_init

  # "$@" is this command's own arguments — bin/claudii dispatches "${@:2}", so
  # no handler re-skips the command name any more.
  #
  # week deliberately does NOT route through _insights_window: it has no rolling
  # window to cycle (the window is Anthropic's, not a --days span), and its SPAN
  # is allowed to be a bare window COUNT — `--history 8` — which _insights_window
  # rejects on purpose ("bare number is not a window"). It shares the contract,
  # not the vocabulary: unknown option → _cli_unknown_opt → rc 2.
  #
  # There is no `--json` arm here: bin/claudii strips --json/--tsv into $_FORMAT
  # before dispatch, so one could never be entered (the one that used to sit
  # here was dead code — instrumenting it showed `claudii week --json` emitting
  # JSON without ever reaching the arm).
  local _arg _history=0 _spec=30d
  for _arg in "$@"; do
    case "$_arg" in
      -h|--help)
        printf 'Usage: claudii week [--history [SPAN]] [--json]\n\n'
        printf "Usage inside Anthropic's rolling 7-day rate-limit window — the\n"
        printf 'quota that actually gates work, not the calendar week.\n\n'
        printf '  --history [SPAN]  per-window bars. SPAN is a period (30d, 90d —\n'
        printf '                    default 30d) or a plain window count (8).\n'
        printf '                    A period keeps every window that overlaps it,\n'
        printf '                    so the oldest bar may start before the cutoff.\n'
        printf '  --json            machine-readable output (combines with --history)\n'
        return 0 ;;
      --history) _history=1 ;;
      # A SPAN without --history is ignored, as before. Spelled as an `if` and
      # not `(( _history )) && _spec=…`: as the arm's last command that yields 1
      # on the final loop pass, which `set -e` turns into a silent abort.
      [0-9]|[0-9][0-9]|[0-9][0-9][0-9])
        if (( _history )); then _spec="$_arg"; fi ;;
      [0-9]d|[0-9][0-9]d|[0-9][0-9][0-9]d|[0-9][0-9][0-9][0-9]d)
        if (( _history )); then _spec="$_arg"; fi ;;
      *) _cli_unknown_opt week "$_arg" '[--history [SPAN]]' || return $? ;;
    esac
  done

  if ! _week_stats; then
    [[ "${_FORMAT:-}" == "json" ]] && { printf '{}\n'; return 0; }
    printf '\n  %sNo weekly window known yet%s — Claude Code reports it after the\n' \
      "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
    printf '  first API response of a session, and drops it once the quota resets.\n\n'
    return 0
  fi

  # --history first: it selects the VIEW, --json only its encoding. The other
  # order made `week --history --json` answer with the current window instead.
  if (( _history )); then
    [[ "${_FORMAT:-}" == "json" ]] && { _week_history_json "$_spec"; return 0; }
    _week_history_render "$_spec" && return 0
    printf '\n  %sNot enough history for a per-window view yet.%s\n\n' \
      "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
    return 0
  fi
  [[ "${_FORMAT:-}" == "json" ]] && { _week_json; return 0; }
  _week_render_block
  return 0
}
