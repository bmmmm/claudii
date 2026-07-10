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
  local cdir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local f="$cdir/status-models"
  local green="${CLAUDII_CLR_GREEN}" yellow="${CLAUDII_CLR_YELLOW}" red="${CLAUDII_CLR_RED}"
  local dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}" accent="${CLAUDII_CLR_ACCENT}"
  if [[ ! -s "$f" ]]; then
    printf '  %sAPI health%s   %s(no status cache — run: claudii status)%s\n' \
      "$accent" "$reset" "$dim" "$reset"
    return
  fi
  local line m st col parts="" lbl
  while IFS='=' read -r m st; do
    [[ -z "$m" ]] && continue
    [[ "$m" == _* ]] && continue   # skip internal keys (_incident, _incident_started, ...)
    case "$st" in
      ok)        col="$green" ;;
      degraded)  col="$yellow" ;;
      down)      col="$red" ;;
      *)         col="$dim" ;;
    esac
    lbl=$(_insights_model_label "$m")
    parts+="${col}●${reset} ${lbl} ${dim}${st}${reset}   "
  done < "$f"
  parts="${parts%   }"
  printf '  %sAPI health%s   %s\n' "$accent" "$reset" "$parts"
}

# ── --json builder ─────────────────────────────────────────────────────────────
_perf_json() {
  local merged="$1" days="$2" floor="$3" repo="$4" src="$5"
  # merged carries the (large) latency list — pass it on stdin, not --argjson,
  # or jq hits ARG_MAX ("Argument list too long"). Small scalars stay as args.
  jq --argjson days "$days" --arg floor "$floor" \
        --arg repo "$repo" --arg src "$src" '
    def pctms($a;$p): ($a|sort) as $s | ($s|length) as $n
      | if $n==0 then 0 else $s[ ([($n*$p|floor), ($n-1)]|min) ] end;
    def toks($o;$d): if $d>0 then ($o*1000/$d|floor) else 0 end;
    [ (.latency // [])[]
      | select(.model != "<synthetic>" and (.model | startswith("claudii-") | not)
               and (.day >= $floor)
               and (($repo=="") or (.repo==$repo))) ] as $L
    | {
        window_days: $days,
        source: $src,
        repo: (if $repo=="" then null else $repo end),
        total_samples: ($L|length),
        summary: {
          p50_ms: pctms([$L[].dt_ms];0.5),
          p90_ms: pctms([$L[].dt_ms];0.9),
          p99_ms: pctms([$L[].dt_ms];0.99),
          tok_s:  toks(([$L[].out]|add // 0); ([$L[].dt_ms]|add // 0)),
          samples: ($L|length)
        },
        by_model: ( $L | group_by(.model | sub("\\[1m\\]$";""))
          | map({ model:(.[0].model | sub("\\[1m\\]$";"")), p50_ms:pctms([.[].dt_ms];0.5),
                  p90_ms:pctms([.[].dt_ms];0.9), p99_ms:pctms([.[].dt_ms];0.99),
                  tok_s:toks(([.[].out]|add);([.[].dt_ms]|add)), samples:length })
          | sort_by(-.samples) ),
        by_day: ( $L | group_by(.day)
          | map({ day:.[0].day, p50_ms:pctms([.[].dt_ms];0.5), samples:length })
          | sort_by(.day) ),
        by_repo: ( $L | group_by(.repo)
          | map({ repo:.[0].repo, p50_ms:pctms([.[].dt_ms];0.5),
                  p90_ms:pctms([.[].dt_ms];0.9),
                  tok_s:toks(([.[].out]|add);([.[].dt_ms]|add)), samples:length })
          | sort_by(-.samples) ),
        # ctx buckets — keep the boundaries (50k/100k/200k/400k) in sync with the
        # render W-rows in _cmd_perf below; test pins json/render label parity.
        by_window: ( $L | map(. + {wk: ((.ctx // -1)
              | if . < 0 then 9 elif . < 50000 then 1 elif . < 100000 then 2
                elif . < 200000 then 3 elif . < 400000 then 4 else 5 end)})
          | group_by(.wk)
          | map({ bucket:({"1":"<50k","2":"50-100k","3":"100-200k","4":"200-400k","5":"400k+","9":"unknown"}[.[0].wk|tostring]),
                  p50_ms:pctms([.[].dt_ms];0.5), p90_ms:pctms([.[].dt_ms];0.9),
                  p99_ms:pctms([.[].dt_ms];0.99),
                  tok_s:toks(([.[].out]|add);([.[].dt_ms]|add)), samples:length }) ),
        ttft: ( ([$L[].ttft_ms] | map(select(. != null))) as $tt
          | if ($tt|length) > 0
            then { p50_ms:pctms($tt;0.5), p90_ms:pctms($tt;0.9), p99_ms:pctms($tt;0.99), samples:($tt|length) }
            else null end ),
        reliability: ( [$L[] | select(.success != null)] as $sl
          | if ($sl|length) > 0
            then { total:($sl|length), ok:([$sl[]|select(.success==true)]|length),
                   retried:([$sl[]|select((.attempt//0)>1)]|length) }
            else null end ),
        errors: ( [ (.errors // [])[]
                    | select((.day >= $floor) and (($repo=="") or (.repo==$repo))) ]
          | group_by(.status_code)
          | map({ status_code:.[0].status_code, count:length }) )
      }' <<< "$merged"
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

  _insights_window perf "${_rest[@]+"${_rest[@]}"}" || return 1
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

  # Source selection: OTEL when enabled AND it has samples in the window, else
  # the transcript estimate. claudii-otel build emits the same .latency shape
  # plus exact ttft_ms / success / api_error status codes. perf is the only
  # command that needs the (large) latency list — the transcript merge requests
  # it explicitly; cache/tokens/tools/limits use the latency-free merge.
  local merged="" src="transcript"
  if [[ "$(_cfgget perf.otel.enabled 2>/dev/null)" == "true" ]]; then
    local _om; _om=$("$CLAUDII_HOME/bin/claudii-otel" build --days "$days" 2>/dev/null)
    if [[ -n "$_om" ]] && (( $(jq '.latency | length' <<< "$_om" 2>/dev/null || echo 0) > 0 )); then
      merged="$_om"; src="otel"
    fi
  fi
  [[ "$src" == "transcript" ]] && merged=$(_insights_run merge --days "$days" --with-latency 2>/dev/null)

  # Calendar floor identical to `claudii tokens` (shared _window_cutoffs), so
  # "last N days" is exact.
  _window_cutoffs "$days"
  local floor="$_WC_FLOOR"

  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    [[ "$fmt" == "json" ]] && { _perf_json "{}" "$days" "$floor" "$repo_filter" "$src"; return 0; }
    printf '  No insight data yet — run a Claude session and try again.\n'
    return 0
  fi

  if [[ "$fmt" == "json" ]]; then
    _perf_json "$merged" "$days" "$floor" "$repo_filter" "$src"
    return 0
  fi

  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" yellow="${CLAUDII_CLR_YELLOW}" green="${CLAUDII_CLR_GREEN}"
  local red="${CLAUDII_CLR_RED}"
  local RW=66

  # Single jq pass → tagged rows: M=model, D=day, R=repo, G=session, S=summary.
  # All numeric fields tostring'd + non-empty so @tsv + IFS=$'\t' survive (the
  # CLAUDE.md empty-field trap). dt_ms / tok_s computed in jq; bash only renders.
  local _rows
  _rows=$(jq -r --arg floor "$floor" --arg repo "$repo_filter" '
    def pctms($a;$p): ($a|sort) as $s | ($s|length) as $n
      | if $n==0 then 0 else $s[ ([($n*$p|floor), ($n-1)]|min) ] end;
    def toks($o;$d): if $d>0 then ($o*1000/$d|floor) else 0 end;
    [ (.latency // [])[]
      | select(.model != "<synthetic>" and (.model | startswith("claudii-") | not)
               and (.day >= $floor)
               and (($repo=="") or (.repo==$repo))) ] as $L
    | [ (.errors // [])[]
        | select((.day >= $floor) and (($repo=="") or (.repo==$repo))) ] as $E
    | ( $L | map(. + {mn:(.model | sub("\\[1m\\]$";""))}) | group_by(.mn)
        | map({k:.[0].mn, d:[.[].dt_ms], o:([.[].out]|add), n:length})
        | sort_by(-.n)
        | .[] | ["M", .k, (pctms(.d;0.5)|tostring), (pctms(.d;0.9)|tostring),
                 (pctms(.d;0.99)|tostring), (toks(.o;([.d[]]|add))|tostring),
                 (.n|tostring)] | @tsv ),
      # ctx buckets — keep the boundaries (50k/100k/200k/400k) in sync with the
      # by_window block in _perf_json above; test pins json/render label parity.
      ( $L | map(. + {wb: ((.ctx // -1)
              | if . < 0 then "9_unknown" elif . < 50000 then "1_<50k"
                elif . < 100000 then "2_50-100k" elif . < 200000 then "3_100-200k"
                elif . < 400000 then "4_200-400k" else "5_400k+" end)})
        | group_by(.wb)
        | map({k:.[0].wb, d:[.[].dt_ms], o:([.[].out]|add), n:length})
        | sort_by(.k)
        | .[] | ["W", .k, (pctms(.d;0.5)|tostring), (pctms(.d;0.9)|tostring),
                 (pctms(.d;0.99)|tostring), (toks(.o;([.d[]]|add))|tostring),
                 (.n|tostring)] | @tsv ),
      ( $L | group_by(.day)
        | map({k:.[0].day, d:[.[].dt_ms], n:length})
        | sort_by(.k)
        | .[] | ["D", .k, (pctms(.d;0.5)|tostring), (.n|tostring)] | @tsv ),
      ( $L | group_by(.repo)
        | map({k:.[0].repo, d:[.[].dt_ms], o:([.[].out]|add), n:length})
        | sort_by(-.n)
        | .[] | ["R", .k, (pctms(.d;0.5)|tostring), (pctms(.d;0.9)|tostring),
                 (toks(.o;([.d[]]|add))|tostring), (.n|tostring)] | @tsv ),
      ( $L | group_by(.sessionId)
        | map({k:.[0].sessionId, rp:(.[0].repo // "?"), d:[.[].dt_ms], o:([.[].out]|add), n:length})
        | sort_by(-.n) | .[:12]
        | .[] | ["G", .k, .rp, (pctms(.d;0.5)|tostring),
                 (toks(.o;([.d[]]|add))|tostring), (.n|tostring)] | @tsv ),
      ( ["S", (pctms([$L[].dt_ms];0.5)|tostring), (pctms([$L[].dt_ms];0.9)|tostring),
         (pctms([$L[].dt_ms];0.99)|tostring),
         (toks(([$L[].out]|add // 0); ([$L[].dt_ms]|add // 0))|tostring),
         (($L|length)|tostring)] | @tsv ),
      ( ([$L[].ttft_ms] | map(select(. != null))) as $tt
        | if ($tt|length) > 0 then
            ["T", (pctms($tt;0.5)|tostring), (pctms($tt;0.9)|tostring),
             (pctms($tt;0.99)|tostring), ($tt|length|tostring)] | @tsv
          else empty end ),
      ( [$L[] | select(.success != null)] as $sl
        | if ($sl|length) > 0 then
            ["X", ($sl|length|tostring),
                  ([$sl[]|select(.success==true)]|length|tostring),
                  ([$sl[]|select((.attempt//0) > 1)]|length|tostring)] | @tsv
          else empty end ),
      ( $E | group_by(.status_code) | .[]
        | ["E", (.[0].status_code|tostring), (length|tostring)] | @tsv )
  ' <<< "$merged")

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
