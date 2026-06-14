# lib/cmd/insights.sh — JSONL-derived insight commands (cache, tools, loop, limits)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail
#
# All commands in this file share the same data path:
#   bin/claudii-insights aggregate         # refresh per-session JSON cache
#   bin/claudii-insights merge --days N    # produce one merged JSON
# Heavy lifting is done in jq; bash only renders bars and labels.

# ── helpers ──────────────────────────────────────────────────────────────────

_insights_run() {
  "$CLAUDII_HOME/bin/claudii-insights" "$@"
}

_insights_refresh() { _insights_run aggregate >/dev/null 2>&1; }

# Merge the per-session caches into one aggregated JSON.
# Args: [days] [until_days]. `until_days` bounds the window from above
# (last_seen < now-until_days) — used by `skills-cost --compare` for the prior
# period; omit it for the usual "last N days" view.
_insights_merged_json() {
  local days="${1:-7}"
  local until_days="${2:-}"
  if [[ -n "$until_days" ]]; then
    _insights_run merge --days "$days" --until-days "$until_days" 2>/dev/null
  else
    _insights_run merge --days "$days" 2>/dev/null
  fi
}

# Render a 20-block bar coloured green-up-to-filled, dim-for-empty.
# Args: filled_count (0..20)
# Echoes the rendered bar (ANSI included).
_insights_bar() {
  local filled="${1:-0}"
  (( filled < 0 ))  && filled=0
  (( filled > 20 )) && filled=20
  local empty=$(( 20 - filled ))
  local f="" e=""
  (( filled > 0 )) && printf -v f "%${filled}s" "" && f="${f// /█}"
  (( empty  > 0 )) && printf -v e "%${empty}s"  "" && e="${e// /░}"
  printf '%s%s%s%s%s' \
    "${CLAUDII_CLR_GREEN}" "$f" \
    "${CLAUDII_CLR_DIM}"   "$e" \
    "${CLAUDII_CLR_RESET}"
}

# Short-number formatting (B/M/K) now lives in lib/render.sh as _fmt_tok
# (pure bash, no per-call awk fork). Call sites below use it directly.

# Map full model id to short label.
# When a new model ships, add its versioned case ABOVE the bare fallback
# (most-specific-first; the bare *opus*/*sonnet*/*haiku* lines must stay last).
# Older versions are kept on purpose so historical cost/insights data still
# resolves to a friendly label. See "When a new Claude model ships" in CLAUDE.md.
_insights_model_label() {
  case "$1" in
    *fable-5*)    printf 'Fable 5'    ;;
    *fable*)      printf 'Fable'      ;;
    *opus-4-8*)   printf 'Opus 4.8'   ;;
    *opus-4-7*)   printf 'Opus 4.7'   ;;
    *opus-4-6*)   printf 'Opus 4.6'   ;;
    *opus*)       printf 'Opus'       ;;
    *sonnet-4-6*) printf 'Sonnet 4.6' ;;
    *sonnet*)     printf 'Sonnet'     ;;
    *haiku-4-5*)  printf 'Haiku 4.5'  ;;
    *haiku*)      printf 'Haiku'      ;;
    '<synthetic>'|synthetic) printf 'synthetic' ;;
    *)            printf '%s' "$1"    ;;
  esac
}

# Map ISO date (YYYY-MM-DD) to a 3-letter weekday or "Today".
# UTC because the aggregator buckets on timestamp[:10] (Z-suffixed ISO).
_insights_day_label() {
  local day="$1"
  local today; today=$(date -u +%Y-%m-%d)
  if [[ "$day" == "$today" ]]; then
    printf 'Today'
  elif date -j -f %Y-%m-%d "$day" +%a >/dev/null 2>&1; then
    date -j -f %Y-%m-%d "$day" +%a
  else
    date -d "$day" +%a 2>/dev/null || printf '%s' "$day"
  fi
}

# ── claudii cache ────────────────────────────────────────────────────────────

_cmd_cache() {
  _cfg_init
  _insights_refresh

  local days=7
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days|-d) shift; days="${1:-7}" ;;
      -h|--help)
        printf 'Usage: claudii cache [--days N]\n'
        printf '\n'
        printf 'Show prompt-cache hit rate per day and per model.\n'
        return 0
        ;;
    esac
    shift
  done

  # Validate here — claudii-insights merge also validates, but its stderr is
  # swallowed by _insights_merged_json (2>/dev/null), so a bad --days used to
  # surface as the misleading "No insight data yet".
  if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
    printf 'claudii: --days must be a positive integer (got: %s)\n' "$days" >&2
    return 1
  fi

  local merged; merged=$(_insights_merged_json "$days")
  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    printf '  No insight data yet — run a Claude session and try again.\n'
    return 0
  fi

  printf '\n  %sclaudii cache%s  %sv%s%s\n\n' \
    "${CLAUDII_CLR_CYAN}" "${CLAUDII_CLR_RESET}" \
    "${CLAUDII_CLR_ACCENT}" "${VERSION:-?}" "${CLAUDII_CLR_RESET}"

  # ── Per-day hit rate ──
  printf '  %s●%s %sCache hit rate (%dd)%s\n' \
    "${CLAUDII_CLR_GREEN}" "${CLAUDII_CLR_RESET}" \
    "${CLAUDII_CLR_ACCENT}" "$days" "${CLAUDII_CLR_RESET}"

  local per_day
  per_day=$(jq -r '
    .days
    | to_entries
    | map({day: (.key | split("|")[0]), v: .value})
    | group_by(.day)
    | map({
        day: .[0].day,
        cache_read:   ([.[] | .v.cache_read   // 0] | add),
        cache_create: ([.[] | .v.cache_create // 0] | add),
        in_tok:       ([.[] | .v.in_tok       // 0] | add)
      })
    | map(. + {total: (.cache_read + .cache_create + .in_tok)})
    | map(select(.total > 0))
    | sort_by(.day) | reverse
    | .[] | [.day, .cache_read, .cache_create, .in_tok, .total] | @tsv
  ' <<< "$merged")

  if [[ -z "$per_day" ]]; then
    printf '    %s(no data)%s\n' "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
  else
    while IFS=$'\t' read -r day creads ccreates ins total; do
      [[ -z "$day" ]] && continue
      local pct_int=$(( 100 * creads / total ))
      local filled=$(( (pct_int * 20 + 50) / 100 ))
      local label; label=$(_insights_day_label "$day")
      local bar;   bar=$(_insights_bar "$filled")
      local pct_str; pct_str=$(awk -v r="$creads" -v t="$total" 'BEGIN{printf "%.1f", 100*r/t}')
      local creads_h; creads_h=$(_fmt_tok "$creads")
      local total_h;  total_h=$(_fmt_tok "$total")
      printf '    %-6s %s  %s%5s%%%s  %s%s / %s%s\n' \
        "$label" \
        "$bar" \
        "${CLAUDII_CLR_CYAN}" "$pct_str" "${CLAUDII_CLR_RESET}" \
        "${CLAUDII_CLR_DIM}" "$creads_h" "$total_h" "${CLAUDII_CLR_RESET}"
    done <<< "$per_day"
  fi

  echo

  # ── Per-model hit rate ──
  printf '  %s●%s %sBy model (%dd)%s\n' \
    "${CLAUDII_CLR_GREEN}" "${CLAUDII_CLR_RESET}" \
    "${CLAUDII_CLR_ACCENT}" "$days" "${CLAUDII_CLR_RESET}"

  local per_model
  per_model=$(jq -r '
    .models
    | to_entries
    | map({
        model: .key,
        cache_read:   (.value.cache_read   // 0),
        cache_create: (.value.cache_create // 0),
        in_tok:       (.value.in_tok       // 0)
      })
    | map(. + {total: (.cache_read + .cache_create + .in_tok)})
    | map(select(.total > 0 and .model != "<synthetic>"))
    | sort_by(-.total)
    | .[] | [.model, .cache_read, .total] | @tsv
  ' <<< "$merged")

  if [[ -z "$per_model" ]]; then
    printf '    %s(no data)%s\n' "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
  else
    while IFS=$'\t' read -r model creads total; do
      [[ -z "$model" ]] && continue
      local pct_int=$(( 100 * creads / total ))
      local filled=$(( (pct_int * 20 + 50) / 100 ))
      local label; label=$(_insights_model_label "$model")
      local bar;   bar=$(_insights_bar "$filled")
      local pct_str; pct_str=$(awk -v r="$creads" -v t="$total" 'BEGIN{printf "%.1f", 100*r/t}')
      local total_h; total_h=$(_fmt_tok "$total")
      printf '    %-11s %s  %s%5s%%%s  %s%s%s\n' \
        "$label" \
        "$bar" \
        "${CLAUDII_CLR_CYAN}" "$pct_str" "${CLAUDII_CLR_RESET}" \
        "${CLAUDII_CLR_DIM}" "$total_h" "${CLAUDII_CLR_RESET}"
    done <<< "$per_model"
  fi

  echo

  # ── Summary line ──
  local totals
  totals=$(jq -r '
    ([.days[]? | .cache_read   // 0] | add // 0) as $r
    | ([.days[]? | .cache_create // 0] | add // 0) as $c
    | ([.days[]? | .in_tok       // 0] | add // 0) as $i
    | ($r + $c + $i) as $t
    | "\($r)\t\($c)\t\($i)\t\($t)"
  ' <<< "$merged")
  IFS=$'\t' read -r tot_r tot_c tot_i tot_all <<< "$totals"
  if (( tot_all > 0 )); then
    local hit_pct; hit_pct=$(awk -v r="$tot_r" -v t="$tot_all" 'BEGIN{printf "%.1f", 100*r/t}')
    local saved_h; saved_h=$(_fmt_tok "$tot_r")
    printf '  %s●%s Saved: %s%s%s tokens cached · %s%s%%%s hit rate (%dd)\n' \
      "${CLAUDII_CLR_GREEN}" "${CLAUDII_CLR_RESET}" \
      "${CLAUDII_CLR_CYAN}"  "$saved_h" "${CLAUDII_CLR_RESET}" \
      "${CLAUDII_CLR_CYAN}"  "$hit_pct" "${CLAUDII_CLR_RESET}" \
      "$days"
  fi
  echo
}

# ── claudii tokens ───────────────────────────────────────────────────────────
# "Where do my tokens go." Token breakdown by type / model / day from the
# insights cache. Per-model output comes from the days{} key-split
# ("YYYY-MM-DD|model" carries out_tok, which models{} alone does not).

_cmd_tokens() {
  _cfg_init
  _insights_refresh

  local days=7
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days|-d) shift; days="${1:-7}" ;;
      -h|--help)
        printf 'Usage: claudii tokens [--days N]\n\n'
        printf 'Token breakdown by type, model and day (input+output is the\n'
        printf 'primary figure; cache read/write and hit%% shown alongside).\n'
        return 0
        ;;
    esac
    shift
  done

  if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
    printf 'claudii: --days must be a positive integer (got: %s)\n' "$days" >&2
    return 1
  fi

  local merged; merged=$(_insights_merged_json "$days")
  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    printf '  No insight data yet — run a Claude session and try again.\n'
    return 0
  fi

  local RW=66 BAR_W=34

  # Floor every view at exactly `days` calendar days. The merge windows sessions
  # by last_seen, so a long-running session can drag in day-entries older than
  # the window; without this floor "last 7 days" shows 8+ rows and the bare
  # weekday labels repeat ambiguously. Empty floor (date failed) → no-op (every
  # string >= "").
  local floor
  floor=$(date -u -v-"$(( days - 1 ))"d +%Y-%m-%d 2>/dev/null \
    || date -u -d "$(( days - 1 )) days ago" +%Y-%m-%d 2>/dev/null \
    || printf '')

  local note hpad; note="last ${days} days"
  hpad=$(( RW - 14 - ${#note} )); (( hpad < 1 )) && hpad=1
  printf '\n  %sclaudii tokens%s%*s%s%s%s\n\n' \
    "${CLAUDII_CLR_CYAN}" "${CLAUDII_CLR_RESET}" \
    "$hpad" "" \
    "${CLAUDII_CLR_DIM}" "$note" "${CLAUDII_CLR_RESET}"

  # ── By type (share of throughput) ──
  local bytype
  bytype=$(jq -r --arg floor "$floor" '
    [ .days | to_entries[]
      | (.key | split("|")) as $p
      | select($p[1] != "<synthetic>" and $p[0] >= $floor)
      | .value ] as $v
    | {
        "cache read":  ([$v[].cache_read   // 0] | add // 0),
        "input":       ([$v[].in_tok       // 0] | add // 0),
        "cache write": ([$v[].cache_create // 0] | add // 0),
        "output":      ([$v[].out_tok      // 0] | add // 0)
      }
    | to_entries | sort_by(-.value) | .[] | [.key, .value] | @tsv
  ' <<< "$merged")

  local tp=0 t v
  while IFS=$'\t' read -r t v; do
    [[ -z "$t" ]] && continue
    tp=$(( tp + v ))
  done <<< "$bytype"

  _render_shead "By type" "$(_fmt_tok "$tp") throughput" "$RW"
  if (( tp == 0 )); then
    printf '    %s(no data)%s\n' "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
  else
    while IFS=$'\t' read -r t v; do
      [[ -z "$t" ]] && continue
      local bf pct suf
      bf=$(_bar_filled "$v" "$tp" "$BAR_W")
      pct=$(( v * 100 / tp ))
      printf -v suf '%s%3d%%%s' "${CLAUDII_CLR_CYAN}" "$pct" "${CLAUDII_CLR_RESET}"
      _render_bar_row "$t" 11 "$(_fmt_tok "$v")" 7 "$bf" "$BAR_W" "$suf"
    done <<< "$bytype"
  fi
  echo

  # ── By model (input / output / cache rd / cache wr / hit) — D-grid ──
  local bymodel
  bymodel=$(jq -r --arg floor "$floor" '
    [ .days | to_entries[]
      | (.key | split("|")) as $p
      | select($p[1] != "<synthetic>" and $p[0] >= $floor)
      | {model: $p[1], v: .value} ]
    | group_by(.model)
    | map({
        model:  .[0].model,
        input:  ([.[].v.in_tok       // 0] | add),
        output: ([.[].v.out_tok      // 0] | add),
        cr:     ([.[].v.cache_read   // 0] | add),
        cw:     ([.[].v.cache_create // 0] | add)
      })
    | map(select((.input + .output + .cr + .cw) > 0))
    | sort_by(-(.input + .output))
    | .[] | [.model, .input, .output, .cr, .cw] | @tsv
  ' <<< "$merged")

  printf '  %sBy model%s\n' "${CLAUDII_CLR_ACCENT}" "${CLAUDII_CLR_RESET}"
  if [[ -z "$bymodel" ]]; then
    printf '    %s(no data)%s\n' "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
  else
    local rows="" model inp out cr cw
    while IFS=$'\t' read -r model inp out cr cw; do
      [[ -z "$model" ]] && continue
      local label hit
      label=$(_insights_model_label "$model")
      # Hit rate over the whole input side: cache_read / (read + create + input).
      # cache_read dwarfs raw input, so read/(read+input) alone pins at 100% —
      # cache_create must be in the denominator (matches `claudii cache`).
      hit=$(_cache_hit_pct "$cr" $(( inp + cw )))
      rows+="${label}"$'\x1f'"$(_fmt_tok "$inp")"$'\x1f'"$(_fmt_tok "$out")"$'\x1f'"$(_fmt_tok "$cr")"$'\x1f'"$(_fmt_tok "$cw")"$'\x1f'"${hit}%"$'\n'
    done <<< "$bymodel"
    printf '%s' "$rows" | _render_dgrid "Model" $'input\x1foutput\x1fcache rd\x1fcache wr\x1fhit'
  fi
  echo

  # ── By day (in+out magnitude, normalised to busiest day) — B-bars ──
  local byday
  byday=$(jq -r --arg floor "$floor" '
    [ .days | to_entries[]
      | (.key | split("|")) as $p
      | select($p[1] != "<synthetic>" and $p[0] >= $floor)
      | {day: $p[0], v: .value} ]
    | group_by(.day)
    | map({
        day:   .[0].day,
        inout: (([.[].v.in_tok // 0] | add) + ([.[].v.out_tok // 0] | add)),
        cr:    ([.[].v.cache_read   // 0] | add),
        inp:   ([.[].v.in_tok       // 0] | add),
        cw:    ([.[].v.cache_create // 0] | add)
      })
    | map(select(.inout > 0))
    | sort_by(.day) | reverse
    | .[] | [.day, .inout, .cr, .inp, .cw] | @tsv
  ' <<< "$merged")

  _render_shead "By day" "in+out · cache hit" "$RW"
  if [[ -z "$byday" ]]; then
    printf '    %s(no data)%s\n' "${CLAUDII_CLR_DIM}" "${CLAUDII_CLR_RESET}"
  else
    local today; today=$(date -u +%Y-%m-%d)
    local maxio=0 d io ccr cinp ccw
    while IFS=$'\t' read -r d io ccr cinp ccw; do
      [[ -z "$d" ]] && continue
      (( io > maxio )) && maxio=$io
    done <<< "$byday"
    while IFS=$'\t' read -r d io ccr cinp ccw; do
      [[ -z "$d" ]] && continue
      local wd lbl bf hit suf
      wd=$(date -j -f %Y-%m-%d "$d" +%a 2>/dev/null || date -d "$d" +%a 2>/dev/null || printf '%s' "$d")
      if [[ "$d" == "$today" ]]; then lbl="Today $wd"; else lbl="$wd"; fi
      bf=$(_bar_filled "$io" "$maxio" "$BAR_W")
      hit=$(_cache_hit_pct "$ccr" $(( cinp + ccw )))
      printf -v suf '%s%3d%%%s' "${CLAUDII_CLR_CYAN}" "$hit" "${CLAUDII_CLR_RESET}"
      _render_bar_row "$lbl" 9 "$(_fmt_tok "$io")" 7 "$bf" "$BAR_W" "$suf"
    done <<< "$byday"
  fi
  echo
}
