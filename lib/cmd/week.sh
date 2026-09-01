# lib/cmd/week.sh — claudii week (Anthropic weekly rate-limit window)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

# Fill _WK_* from lib/window.awk for the window _week_window() found.
# Returns 1 when no window is known (Claude Code drops seven_day once its
# resets_at passes, and until the next API response), so every caller can
# print its own "nothing to show yet" line.
_WK_TOK= _WK_COST= _WK_SESSIONS= _WK_LIMIT= _WK_LIMIT_SRC= _WK_EXHAUST=
_week_stats() {
  _WK_TOK=0 _WK_COST=0 _WK_SESSIONS=0 _WK_LIMIT=0 _WK_LIMIT_SRC="" _WK_EXHAUST=0
  _week_window || return 1

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

  local _arg
  for _arg in "${@:2}"; do
    case "$_arg" in
      -h|--help)
        printf 'Usage: claudii week [--json]\n\n'
        printf "Usage inside Anthropic's rolling 7-day rate-limit window — the\n"
        printf 'quota that actually gates work, not the calendar week.\n'
        return 0 ;;
      --json) _FORMAT=json ;;
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
  _week_render_block
  return 0
}
