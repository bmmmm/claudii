# lib/cmd/skills-cost.sh — per-skill / per-plugin cost breakdown (claudii skills-cost)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail.
#
# Reads attribution_skills / attribution_plugins from the insights cache — a separate
# data source from the session-cache commands in sessions.sh, so it lives on its own.
# Token pricing uses a blended Sonnet rate (see the pricing-constants note in-function).

_cmd_skills_cost() {
  _cfg_init

  local days=30 show_plugins=0 fmt="${_FORMAT:-}"
  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days|-d)   shift; days="${1:-30}" ;;
      --plugins)   show_plugins=1 ;;
      --json)      fmt="json" ;;
      -h|--help)
        printf 'Usage: claudii skills-cost [--days N] [--plugins] [--json]\n'
        return 0
        ;;
    esac
    shift
  done

  # --days must be a positive integer. A non-numeric value previously slipped the
  # `[[ "$days" -gt 0 ]] 2>/dev/null` guard and silently became "no cutoff" (all
  # time), and also broke the downstream jq `($d|tonumber)` and `printf "%d"`.
  if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
    printf 'claudii: --days must be a positive integer (got: %s)\n' "$days" >&2
    return 1
  fi

  # Pricing constants (per-token, in USD).
  # Skills run across mixed models; we use Sonnet rates as a conservative blended rate.
  # Model column shows "mixed" to signal this Wave-1 limitation.
  # Rates: Sonnet 4.x — in=$3/M out=$15/M cache_read=$0.3/M cache_create=$3.75/M
  local _P_IN="0.000003"      # $3/M input
  local _P_OUT="0.000015"     # $15/M output
  local _P_CR="0.0000003"     # $0.3/M cache_read
  local _P_CC="0.00000375"    # $3.75/M cache_create

  # Locate insights cache directory.
  local _cache_base="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local _insights_dir="$_cache_base/insights"

  # Gather cache files; filter by --days cutoff using last_seen field.
  # days is a validated positive integer (above), so compute the cutoff directly.
  local _cutoff_iso
  if date -v -1d +%Y-%m-%d >/dev/null 2>&1; then
    _cutoff_iso=$(date -u -v "-${days}d" +%Y-%m-%dT%H:%M:%SZ)
  else
    _cutoff_iso=$(date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
  fi

  shopt -s nullglob
  local _sc_files=("$_insights_dir"/*.json)
  shopt -u nullglob

  if [[ ${#_sc_files[@]} -eq 0 ]]; then
    printf 'No skill attribution data yet — run some sessions or `claudii-insights aggregate --force`.\n'
    return 0
  fi

  # Extract the right attribution block key.
  local attr_key="attribution_skills"
  local section_label="Skill"
  if [[ "$show_plugins" -eq 1 ]]; then
    attr_key="attribution_plugins"
    section_label="Plugin"
  fi

  # Aggregate attribution data across all cache files.
  # Output: TSV — name\tcalls\tin_tok\tout_tok\tcache_read\tcache_create
  local rows_tsv
  rows_tsv=$(jq -rn \
    --arg cutoff "$_cutoff_iso" \
    --arg k "$attr_key" \
    --arg pin "$_P_IN" \
    --arg pout "$_P_OUT" \
    --arg pcr "$_P_CR" \
    --arg pcc "$_P_CC" \
    '
    # Read all input files, filter by cutoff, aggregate attribution by name
    [inputs
      | select(($cutoff == "") or ((.last_seen // "") >= $cutoff))
      | .[$k] // {}
      | to_entries[]
      | {name: .key, v: .value}
    ]
    | group_by(.name)
    | map({
        name:         .[0].name,
        calls:        ([.[] | .v.calls         // 0] | add),
        in_tok:       ([.[] | .v.in_tok        // 0] | add),
        out_tok:      ([.[] | .v.out_tok       // 0] | add),
        cache_read:   ([.[] | .v.cache_read    // 0] | add),
        cache_create: ([.[] | .v.cache_create  // 0] | add)
      })
    | map(. + {
        tot_usd: (
          (.in_tok       | tonumber) * ($pin  | tonumber)
          + (.out_tok    | tonumber) * ($pout | tonumber)
          + (.cache_read | tonumber) * ($pcr  | tonumber)
          + (.cache_create | tonumber) * ($pcc | tonumber)
        )
      })
    | map(. + {avg_usd: (if .calls > 0 then .tot_usd / .calls else 0 end)})
    | sort_by(-.tot_usd)
    | .[]
    | [.name, (.calls | tostring), (.tot_usd | tostring), (.avg_usd | tostring)]
    | @tsv
    ' "${_sc_files[@]}" 2>/dev/null)

  if [[ -z "$rows_tsv" ]]; then
    printf 'No skill attribution data yet — run some sessions or `claudii-insights aggregate --force`.\n'
    return 0
  fi

  # Load rows into parallel arrays (bash 3.2 compatible — no declare -A)
  local _sc_names=() _sc_calls=() _sc_tot=() _sc_avg=()
  local _sc_count=0
  while IFS=$'\t' read -r _rname _rcalls _rtot _ravg; do
    [[ -z "$_rname" ]] && continue
    _sc_names[$_sc_count]="$_rname"
    _sc_calls[$_sc_count]="$_rcalls"
    _sc_tot[$_sc_count]="$_rtot"
    _sc_avg[$_sc_count]="$_ravg"
    (( ++_sc_count ))
  done <<< "$rows_tsv"

  if [[ "$_sc_count" -eq 0 ]]; then
    printf 'No skill attribution data yet — run some sessions or `claudii-insights aggregate --force`.\n'
    return 0
  fi

  # Compute median avg_usd (sort numerically, pick middle)
  local _median_avg
  _median_avg=$(printf '%s\n' "${_sc_avg[@]}" | sort -n | awk '
    { vals[NR] = $1 }
    END {
      n = NR
      if (n == 0) { print 0; exit }
      if (n % 2 == 1) print vals[int(n/2) + 1]
      else print (vals[n/2] + vals[n/2 + 1]) / 2
    }
  ')

  # Threshold: 3× median
  local _threshold
  _threshold=$(awk -v m="$_median_avg" 'BEGIN { printf "%.10f", m * 3 }')

  # JSON output mode
  if [[ "$fmt" == "json" ]]; then
    local _json_rows="["
    local _first=1
    for (( _i=0; _i<_sc_count; _i++ )); do
      local _outlier="false"
      _outlier=$(awk -v a="${_sc_avg[$_i]}" -v t="$_threshold" 'BEGIN { print (a+0 >= t+0) ? "true" : "false" }')
      [[ "$_first" -eq 0 ]] && _json_rows+=","
      _json_rows+=$(jq -n \
        --arg name "${_sc_names[$_i]}" \
        --arg calls "${_sc_calls[$_i]}" \
        --arg tot "${_sc_tot[$_i]}" \
        --arg avg "${_sc_avg[$_i]}" \
        --argjson outlier "$_outlier" \
        '{name:$name, calls:($calls|tonumber), tot_usd:($tot|tonumber), avg_usd:($avg|tonumber), model:"mixed", outlier:$outlier}')
      _first=0
    done
    _json_rows+="]"
    local _meta
    _meta=$(jq -n --arg med "$_median_avg" --arg d "$days" '{median_avg_usd:($med|tonumber),days:($d|tonumber)}')
    printf '%s\n' "{\"rows\":${_json_rows},\"meta\":${_meta}}"
    return 0
  fi

  # Pretty output
  local _col_name_w=27
  local _hdr_fmt="%-${_col_name_w}s %7s %8s %8s %-12s %s\n"
  local _row_fmt="%-${_col_name_w}s %7s %8s %8s %-12s %s\n"
  local _sep_line
  printf -v _sep_line '%-27s %-7s %-8s %-8s %-12s %-4s' \
    '───────────────────────────' '───────' '────────' '────────' '────────────' '────'

  printf '\n'
  printf "${CLAUDII_CLR_CYAN}claudii skills-cost${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_DIM}(%d days)${CLAUDII_CLR_RESET}\n\n" "$days"
  printf "${CLAUDII_CLR_DIM}${_hdr_fmt}${CLAUDII_CLR_RESET}" \
    "$section_label" "Calls" "Tot \$" "Avg \$" "Model" "Flag"
  printf "${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_sep_line"

  for (( _i=0; _i<_sc_count; _i++ )); do
    local _name="${_sc_names[$_i]}"
    local _calls="${_sc_calls[$_i]}"
    local _tot_fmt _avg_fmt _flag=""

    _tot_fmt=$(awk -v v="${_sc_tot[$_i]}" 'BEGIN { printf "%.4f", v+0 }')
    _avg_fmt=$(awk -v v="${_sc_avg[$_i]}" 'BEGIN { printf "%.4f", v+0 }')

    # Truncate name if too long
    if (( ${#_name} > _col_name_w )); then
      _name="${_name:0:$(( _col_name_w - 1 ))}…"
    fi

    # Outlier flag
    local _is_outlier
    _is_outlier=$(awk -v a="${_sc_avg[$_i]}" -v t="$_threshold" 'BEGIN { print (a+0 >= t+0) ? "1" : "0" }')
    [[ "$_is_outlier" == "1" ]] && _flag="${CLAUDII_CLR_YELLOW}!${CLAUDII_CLR_RESET}"

    printf "${_row_fmt}" \
      "$_name" \
      "$_calls" \
      "\$${_tot_fmt}" \
      "\$${_avg_fmt}" \
      "mixed" \
      "$_flag"
  done

  printf '\n'
  local _med_fmt
  _med_fmt=$(awk -v v="$_median_avg" 'BEGIN { printf "%.4f", v+0 }')
  printf "${CLAUDII_CLR_DIM}Median cost/call: \$%s — rows flagged (!) are ≥3× median${CLAUDII_CLR_RESET}\n" "$_med_fmt"
  printf '\n'
}
