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

_insights_merged_json() {
  local days="${1:-7}"
  _insights_run merge --days "$days" 2>/dev/null
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

# Convert byte-count style integer to short form (B/M/K).
_insights_short_num() {
  local n="${1:-0}"
  awk -v n="$n" '
    BEGIN {
      if      (n >= 1e9) printf "%.1fB", n/1e9
      else if (n >= 1e6) printf "%.1fM", n/1e6
      else if (n >= 1e3) printf "%.0fK", n/1e3
      else               printf "%d", n
    }
  '
}

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
      local creads_h; creads_h=$(_insights_short_num "$creads")
      local total_h;  total_h=$(_insights_short_num "$total")
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
      local total_h; total_h=$(_insights_short_num "$total")
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
    local saved_h; saved_h=$(_insights_short_num "$tot_r")
    printf '  %s●%s Saved: %s%s%s tokens cached · %s%s%%%s hit rate (%dd)\n' \
      "${CLAUDII_CLR_GREEN}" "${CLAUDII_CLR_RESET}" \
      "${CLAUDII_CLR_CYAN}"  "$saved_h" "${CLAUDII_CLR_RESET}" \
      "${CLAUDII_CLR_CYAN}"  "$hit_pct" "${CLAUDII_CLR_RESET}" \
      "$days"
  fi
  echo
}
