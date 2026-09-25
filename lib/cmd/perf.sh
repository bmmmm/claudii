# lib/cmd/perf.sh — token-performance & API-health dashboard (claudii perf)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail.
#
# Shares the insights data path (lib/cmd/insights.sh helpers: _insights_window,
# _insights_refresh, _insights_merged_json, _insights_model_label, ...). The
# perf signal is the per-response latency list added to the cache in schema v7
# (insights.jq): latency = [{day, model, dt_ms, out, ctx}], dt_ms = assistant.ts -
# parent.ts (main thread only), ctx = input + cache_read + cache_creation tokens
# (context-window occupancy). The merge attaches {repo, sessionId} per sample.
#
# Source abstraction (phase 2): perf reads a fixed shape (latency samples). Today
# that shape comes from transcripts (estimated, no TTFT). When a local OTEL agent
# is configured, claudii-otel will write the SAME shape from api_request events
# (exact duration_ms + status_code errors + ttft). The renderer never changes;
# only the source badge flips transcript -> otel.

# Format milliseconds as a compact duration: "0.8s", "14.3s", "1m05s".
_fmt_ms() {
  local ms="${1:-0}"
  case "$ms" in ''|*[!0-9]*) printf '0s'; return ;; esac
  if (( ms < 60000 )); then
    printf '%d.%ds' $(( ms / 1000 )) $(( (ms % 1000) / 100 ))
  else
    printf '%dm%02ds' $(( ms / 60000 )) $(( (ms % 60000) / 1000 ))
  fi
}

# Perf data source is chosen in _cmd_perf: OTEL when perf.otel.enabled and the
# local OTEL cache has samples in the window, else the transcript estimate.

# One-line API health from the ClaudeStatus cache (bin/claudii-status writes it).
# key=value lines: opus=ok|degraded|down. Absent file -> hint.
_perf_health_line() {
  local green="${CLAUDII_CLR_GREEN}" yellow="${CLAUDII_CLR_YELLOW}" red="${CLAUDII_CLR_RED}"
  local dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}" accent="${CLAUDII_CLR_ACCENT}"
  # Shared parser (lib/helpers.sh): resolves the path, reads the file once and
  # drops the internal _* keys (_incident, _incident_started, _api). Returns 1
  # when the cache is missing or empty — the same "no cache yet" state the
  # `[[ ! -s ]]` guard used to check for itself.
  if ! _status_cache_read; then
    printf '  %sAPI health%s   %s(no status cache — run: claudii status)%s\n' \
      "$accent" "$reset" "$dim" "$reset"
    return
  fi
  local i=0 m st col parts="" lbl
  while (( i < _SC_COUNT )); do
    m="${_SC_KEYS[i]}"; st="${_SC_VALS[i]}"
    i=$(( i + 1 ))
    case "$st" in
      ok)        col="$green" ;;
      degraded)  col="$yellow" ;;
      down)      col="$red" ;;
      *)         col="$dim" ;;
    esac
    # Same call the overview's ClaudeStatus block makes on the same file
    # (lib/cmd/overview.sh, _ov_render_services) — one map, one string.
    lbl=$(_insights_model_label "$m")
    parts+="${col}●${reset} ${lbl} ${dim}${st}${reset}   "
  done
  parts="${parts%   }"
  printf '  %sAPI health%s   %s\n' "$accent" "$reset" "$parts"
}

# ── claudii perf ───────────────────────────────────────────────────────────────
_cmd_perf() {
  # --watch [N] — strip before passing args down; loop with tput clear.
  local _watch=0 _a
  local -a _fwd=()
  for _a in "$@"; do
    case "$_a" in
      --watch)    _watch=30 ;;
      --watch=*)  _watch="${_a#--watch=}" ;;
      *)          _fwd+=("$_a") ;;
    esac
  done
  if (( _watch > 0 )); then
    while true; do
      tput clear 2>/dev/null || printf '\033[2J\033[H'
      _cmd_perf "${_fwd[@]+"${_fwd[@]}"}"
      local _dim _reset; _dim=$(tput dim 2>/dev/null || printf '\033[2m'); _reset=$(tput sgr0 2>/dev/null || printf '\033[0m')
      printf '  %s↻  refreshing in %ds — Ctrl-C to exit%s\n\n' "$_dim" "$_watch" "$_reset"
      sleep "$_watch"
    done
    return
  fi

  _cfg_init
  _insights_refresh

  # Pre-extract --repo before _insights_window (which errors on unknown tokens).
  local repo_filter="" _skip=0 _a
  local -a _rest=()
  for _a in "${@:2}"; do
    if (( _skip )); then repo_filter="$_a"; _skip=0; continue; fi
    case "$_a" in
      --repo)   _skip=1 ;;
      --repo=*) repo_filter="${_a#--repo=}" ;;
      *)        _rest+=("$_a") ;;
    esac
  done

  # `|| return $?`, not `|| return 1`: _insights_window already returns the
  # contract's rc 2 for a rejected argument, and downgrading it to 1 was the one
  # thing keeping perf off the contract while it printed the contract message.
  _insights_window perf "${_rest[@]+"${_rest[@]}"}" || return $?
  if (( _IW_HELP )); then
    printf 'Usage: claudii perf [WINDOW] [--repo NAME] [--watch[=N]] [--json]\n\n'
    printf 'WINDOW is one of today, 7d, 30d, 90d, year (or any <N>d).\n'
    printf 'Response-time percentiles (p50/p90/p99), output throughput (tok/s)\n'
    printf 'and a per-day latency trend, by model, context window and repo, plus\n'
    printf 'API health.\n'
    printf 'Latency is estimated from transcript timestamps (assistant minus\n'
    printf 'parent); --repo NAME narrows every section to one repository.\n'
    printf '%s\n' '--watch[=N] refreshes every N seconds (default: 30).'
    return 0
  fi
  local days="$_IW_DAYS"

  local fmt="${_FORMAT:-}"
  [[ "$fmt" == "tsv" ]] && { _insights_reject_tsv perf; return 1; }

  _perf_render
}

# Everything after argument parsing; reads days/fmt/repo_filter from _cmd_perf
# (bash dynamic scope).
#
# The merged latency data (tens of MB for a long window) never passes through
# bash: /bin/bash 3.2 under a UTF-8 locale spent 22 s on a single
# `[[ "$merged" == "{}" ]]` over it (its multibyte pattern matcher) and ~8 s
# copying it through variables and here-strings — 30 of perf 90d's 47 s,
# invisible under bash 5 or LC_ALL=C. Instead jq reduces it to what perf shows
# (lib/perf_rows.jq, lib/perf_json.jq) right where it is produced: in
# `claudii-otel build --render` for OTEL, in a pipe after the transcript merge.
_perf_render() {
  # Calendar floor identical to `claudii tokens` (shared _window_cutoffs), so
  # "last N days" is exact.
  _window_cutoffs "$days"
  local floor="$_WC_FLOOR"
  local mode="rows"; [[ "$fmt" == "json" ]] && mode="json"
  local lib="$CLAUDII_HOME/lib"

  # Source selection: OTEL when enabled AND it has samples in the window, else
  # the transcript estimate. A render prints nothing when the OTEL window holds
  # no latency sample — or when build fails — and perf falls back. perf is the
  # only command that needs the (large) latency list — the transcript merge
  # requests it explicitly; cache/tokens/tools/limits use the latency-free merge.
  local src="transcript" _rows=""
  if [[ "$(_cfgget perf.otel.enabled 2>/dev/null)" == "true" ]]; then
    _rows=$("$CLAUDII_HOME/bin/claudii-otel" build --days "$days" --render "$mode" \
              --render-floor "$floor" --repo "$repo_filter" 2>/dev/null) || _rows=""
    [[ -n "$_rows" ]] && src="otel"
  fi
  if [[ "$src" == "transcript" ]]; then
    if [[ "$mode" == "json" ]]; then
      _rows=$(_insights_run merge --days "$days" --with-latency 2>/dev/null \
        | jq -L "$lib" --argjson days "$days" --arg floor "$floor" --arg repo "$repo_filter" '
            include "perf_json"; perf_json($days; $floor; $repo; "transcript")' 2>/dev/null) || _rows=""
      [[ -z "$_rows" ]] && _rows=$(jq -n -L "$lib" --argjson days "$days" --arg floor "$floor" \
        --arg repo "$repo_filter" 'include "perf_json"; {} | perf_json($days; $floor; $repo; "transcript")')
    else
      # A bare {} is the merge of an empty cache.
      _rows=$(_insights_run merge --days "$days" --with-latency 2>/dev/null \
        | jq -r -L "$lib" --arg floor "$floor" --arg repo "$repo_filter" '
            include "perf_rows"; if . == {} then empty else perf_rows($floor; $repo) end' 2>/dev/null) || _rows=""
      if [[ -z "$_rows" ]]; then
        printf '  No insight data yet — run a Claude session and try again.\n'
        return 0
      fi
    fi
  fi

  if [[ "$mode" == "json" ]]; then
    printf '%s\n' "$_rows"
    return 0
  fi

  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" yellow="${CLAUDII_CLR_YELLOW}" green="${CLAUDII_CLR_GREEN}"
  local red="${CLAUDII_CLR_RED}"
  local RW=66

  local -a _m_rows=() _w_rows=() _d_rows=() _r_rows=() _g_rows=() _e_rows=()
  local _s_row="" _t_row="" _x_row="" _ln _tag
  while IFS= read -r _ln; do
    [[ -z "$_ln" ]] && continue
    _tag="${_ln%%$'\t'*}"
    case "$_tag" in
      M) _m_rows+=("${_ln#M$'\t'}") ;;
      W) _w_rows+=("${_ln#W$'\t'}") ;;
      D) _d_rows+=("${_ln#D$'\t'}") ;;
      R) _r_rows+=("${_ln#R$'\t'}") ;;
      G) _g_rows+=("${_ln#G$'\t'}") ;;
      S) _s_row="${_ln#S$'\t'}" ;;
      T) _t_row="${_ln#T$'\t'}" ;;
      X) _x_row="${_ln#X$'\t'}" ;;
      E) _e_rows+=("${_ln#E$'\t'}") ;;
    esac
  done <<< "$_rows"

  # ── Header ──
  local total_n=0 s_p50=0 s_p90=0 s_p99=0 s_toks=0
  [[ -n "$_s_row" ]] && IFS=$'\t' read -r s_p50 s_p90 s_p99 s_toks total_n <<< "$_s_row"

  local note; printf -v note '%s · %s responses · source: %s' \
    "$(_insights_window_label "$days")" "$total_n" "$src"
  [[ -n "$repo_filter" ]] && note="repo: $repo_filter · $note"
  # Left-aligned note after the title: a right-justified pad over a `·`-laden
  # string mis-counts column width under LC_ALL=C (U+00B7 is 2 bytes) and breaks
  # the de_DE/C CI matrix — keep it ASCII-safe, no ${#note} math.
  printf '\n  %sclaudii perf%s   %s%s%s\n\n' \
    "$cyan" "$reset" "$dim" "$note" "$reset"

  if (( total_n == 0 )); then
    printf '  %sNo response-time data in this window%s — latency needs assistant\n' "$dim" "$reset"
    printf '  responses with a resolvable parent timestamp. Try a wider window.\n\n'
    _perf_health_line
    echo
    return 0
  fi

  # ── Summary line ──
  printf '  %s●%s p50 %s%s%s   p90 %s%s%s   p99 %s%s%s   %s%s tok/s%s\n' \
    "$green" "$reset" \
    "$cyan" "$(_fmt_ms "$s_p50")" "$reset" \
    "$cyan" "$(_fmt_ms "$s_p90")" "$reset" \
    "$cyan" "$(_fmt_ms "$s_p99")" "$reset" \
    "$cyan" "$s_toks" "$reset"

  # ── TTFT ("lag") + reliability — OTEL only (transcripts can't measure these) ──
  if [[ -n "$_t_row" ]]; then
    local t_p50 t_p90 t_p99 t_n
    IFS=$'\t' read -r t_p50 t_p90 t_p99 t_n <<< "$_t_row"
    printf '  %s○%s TTFT p50 %s%s%s   p90 %s%s%s   p99 %s%s%s   %stime to first token%s\n' \
      "$cyan" "$reset" \
      "$cyan" "$(_fmt_ms "$t_p50")" "$reset" \
      "$cyan" "$(_fmt_ms "$t_p90")" "$reset" \
      "$cyan" "$(_fmt_ms "$t_p99")" "$reset" \
      "$dim" "$reset"
  fi
  if [[ -n "$_x_row" ]]; then
    local x_total=0 x_ok=0 x_retry=0 x_pct=100
    IFS=$'\t' read -r x_total x_ok x_retry <<< "$_x_row"
    (( x_total > 0 )) && x_pct=$(( x_ok * 100 / x_total ))
    local xcol="$green"; (( x_pct < 99 )) && xcol="$yellow"; (( x_pct < 95 )) && xcol="$red"
    printf '  %s✓%s success %s%d%%%s   %sretried%s %s%d%s %sof %d responses%s\n' \
      "$xcol" "$reset" "$xcol" "$x_pct" "$reset" \
      "$dim" "$reset" "$cyan" "$x_retry" "$reset" "$dim" "$x_total" "$reset"
  fi
  echo

  # ── By model (p50/p90/p99/tok-s/n) — D-grid ──
  printf '  %sBy model%s\n' "$accent" "$reset"
  if (( ${#_m_rows[@]} == 0 )); then
    printf '    %s(no data)%s\n' "$dim" "$reset"
  else
    local rows="" _mr model p50 p90 p99 toks n label
    for _mr in "${_m_rows[@]}"; do
      IFS=$'\t' read -r model p50 p90 p99 toks n <<< "$_mr"
      label=$(_insights_model_label "$model")
      rows+="${label}"$'\x1f'"$(_fmt_ms "$p50")"$'\x1f'"$(_fmt_ms "$p90")"$'\x1f'"$(_fmt_ms "$p99")"$'\x1f'"${toks}/s"$'\x1f'"${n}"$'\n'
    done
    printf '%s' "$rows" | _render_dgrid "Model" $'p50\x1fp90\x1fp99\x1ftok/s\x1fn'
  fi
  echo

  # ── By context window (latency vs context-window occupancy) ──
  # Buckets responses by context size (input + cache_read + cache_creation tokens)
  # so the latency cost of a large window is visible — bigger windows run slower
  # (higher p50/p90/p99), the central "do big contexts hurt?" signal.
  printf '  %sBy context window%s\n' "$accent" "$reset"
  if (( ${#_w_rows[@]} == 0 )); then
    printf '    %s(no data)%s\n' "$dim" "$reset"
  else
    local wrows="" _wr wb wp50 wp90 wp99 wtoks wn wlabel
    for _wr in "${_w_rows[@]}"; do
      IFS=$'\t' read -r wb wp50 wp90 wp99 wtoks wn <<< "$_wr"
      wlabel="${wb#*_}"   # strip the sort-key prefix: "4_200-400k" -> "200-400k"
      wrows+="${wlabel}"$'\x1f'"$(_fmt_ms "$wp50")"$'\x1f'"$(_fmt_ms "$wp90")"$'\x1f'"$(_fmt_ms "$wp99")"$'\x1f'"${wtoks}/s"$'\x1f'"${wn}"$'\n'
    done
    printf '%s' "$wrows" | _render_dgrid "Window" $'p50\x1fp90\x1fp99\x1ftok/s\x1fn'
  fi
  echo

  # ── Latency trend (per-day p50 sparkline + today vs baseline) ──
  _render_shead "Latency trend" "p50 per day" "$RW"
  if (( ${#_d_rows[@]} == 0 )); then
    printf '    %s(no data)%s\n' "$dim" "$reset"
  else
    local series="" maxp=0 _dr dday dp50 dn sum=0 cnt=0 last_p50=0
    for _dr in "${_d_rows[@]}"; do
      IFS=$'\t' read -r dday dp50 dn <<< "$_dr"
      series+="$dp50 "
      (( dp50 > maxp )) && maxp=$dp50
      sum=$(( sum + dp50 )); (( ++cnt )); last_p50=$dp50
    done
    local spark; spark=$(_sparkline "$series" "$maxp")
    printf '  %s%s%s   %s%s..%s%s\n' \
      "$cyan" "$spark" "$reset" \
      "$dim" "$(_fmt_ms 0)" "$(_fmt_ms "$maxp")" "$reset"
    # Early-warning: today's p50 vs the window baseline (mean of prior days).
    if (( cnt >= 2 )); then
      local base=$(( (sum - last_p50) / (cnt - 1) ))
      if (( base > 0 )); then
        local delta=$(( (last_p50 - base) * 100 / base )) arrow col
        if   (( delta >  15 )); then arrow="▲"; col="$yellow"
        elif (( delta < -15 )); then arrow="▼"; col="$green"
        else arrow="·"; col="$dim"; fi
        printf '  %stoday %s%s   %sbaseline %s%s   %s%s%+d%%%s\n' \
          "$dim" "$(_fmt_ms "$last_p50")" "$reset" \
          "$dim" "$(_fmt_ms "$base")" "$reset" \
          "$col" "$arrow " "$delta" "$reset"
      fi
    fi
  fi
  echo

  # ── By repo (no filter) OR By session (within a --repo) ──
  if [[ -z "$repo_filter" ]]; then
    _render_shead "By repo" "p50 · p90 · tok/s · n" "$RW"
    if (( ${#_r_rows[@]} == 0 )); then
      printf '    %s(no data)%s\n' "$dim" "$reset"
    else
      local rrows="" _rr repo rp50 rp90 rtoks rn i=0
      for _rr in "${_r_rows[@]}"; do
        (( i >= 8 )) && break
        IFS=$'\t' read -r repo rp50 rp90 rtoks rn <<< "$_rr"
        rrows+="${repo}"$'\x1f'"$(_fmt_ms "$rp50")"$'\x1f'"$(_fmt_ms "$rp90")"$'\x1f'"${rtoks}/s"$'\x1f'"${rn}"$'\n'
        (( ++i ))
      done
      printf '%s' "$rrows" | _render_dgrid "Repo" $'p50\x1fp90\x1ftok/s\x1fn'
      (( ${#_r_rows[@]} > 8 )) && printf '  %s+%d more repos%s\n' "$dim" "$(( ${#_r_rows[@]} - 8 ))" "$reset"
    fi
  else
    _render_shead "By session" "p50 · tok/s · n" "$RW"
    if (( ${#_g_rows[@]} == 0 )); then
      printf '    %s(no data)%s\n' "$dim" "$reset"
    else
      local grows="" _gr gsid grepo gp50 gtoks gn
      for _gr in "${_g_rows[@]}"; do
        IFS=$'\t' read -r gsid grepo gp50 gtoks gn <<< "$_gr"
        grows+="${gsid:0:8}"$'\x1f'"$(_fmt_ms "$gp50")"$'\x1f'"${gtoks}/s"$'\x1f'"${gn}"$'\n'
      done
      printf '%s' "$grows" | _render_dgrid "Session" $'p50\x1ftok/s\x1fn'
    fi
  fi
  echo

  # ── API errors (OTEL only — transcripts carry no error signal) ──
  if [[ "$src" == "otel" ]]; then
    if (( ${#_e_rows[@]} > 0 )); then
      _render_shead "API errors" "by status code" "$RW"
      local _er ecode ecount
      for _er in "${_e_rows[@]}"; do
        IFS=$'\t' read -r ecode ecount <<< "$_er"
        printf '  %s●%s HTTP %s   %s%s error(s)%s\n' "$red" "$reset" "$ecode" "$dim" "$ecount" "$reset"
      done
    else
      printf '  %s✓ no API errors in window%s\n' "$green" "$reset"
    fi
    echo
  fi

  # ── API health ──
  _perf_health_line
  echo

  # ── Source note ──
  if [[ "$src" == "otel" ]]; then
    printf '  %sExact duration_ms + TTFT from OTEL traces (claude_code.llm_request);\n' "$dim"
    printf '  errors from api_error events. tok/s is output ÷ duration_ms.%s\n\n' "$reset"
  else
    printf '  %stok/s is output ÷ end-to-end time (includes wait). Transcript\n' "$dim"
    printf '  estimate — enable OTEL for exact duration_ms, errors and TTFT.%s\n\n' "$reset"
  fi
}
