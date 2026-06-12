# lib/cmd/skills-cost.sh — per-skill / per-plugin / per-MCP-tool cost breakdown (claudii skills-cost)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail.
#
# Reads attribution_skills / attribution_plugins / attribution_mcp from the insights
# cache — a separate data source from the session-cache commands in sessions.sh, so it
# lives on its own. Token pricing uses a blended Sonnet rate (see the pricing-constants
# note in-function).

_cmd_skills_cost() {
  _cfg_init

  local days=30 attr_kind="skill" fmt="${_FORMAT:-}"
  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days|-d)   shift; days="${1:-30}" ;;
      --plugins)   attr_kind="plugin" ;;
      --mcp)       attr_kind="mcp" ;;
      --json)      fmt="json" ;;
      -h|--help)
        printf 'Usage: claudii skills-cost [--days N] [--plugins] [--mcp] [--json]\n'
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

  # Per-token pricing (USD), per model tier. These are the only hardcoded rates
  # in claudii (`claudii cost` reads costUSD from history instead). Per MTok:
  # Opus $5/$25, Sonnet $3/$15, Haiku $1/$5, Fable $10/$50; cache_read = 0.1×
  # input, cache_create (5m TTL) = 1.25× input. On a tier price change, update
  # this table AND the bare-tier fallback in the jq `tier()` def below.
  #
  # tot_usd uses real per-model token attribution (schema v5, attribution_models).
  # Pre-v5 / orphaned caches carry no per-model token split; their residual
  # tokens (aggregate minus per-model-covered) are priced at the flat Sonnet rate
  # — matching the old behavior, so old data degrades gracefully rather than
  # vanishing from the dollar totals.
  local _rates='{
    "opus":   {"in":0.000005, "out":0.000025, "cr":0.0000005, "cc":0.00000625},
    "sonnet": {"in":0.000003, "out":0.000015, "cr":0.0000003, "cc":0.00000375},
    "haiku":  {"in":0.000001, "out":0.000005, "cr":0.0000001, "cc":0.00000125},
    "fable":  {"in":0.00001,  "out":0.00005,  "cr":0.000001,  "cc":0.0000125}
  }'

  # Aggregate via `claudii-insights merge` (through the shared helper) — the
  # --days cutoff and cross-session summing live there, single source of truth.
  # This function used to re-implement both against the raw cache files.
  local merged
  merged=$(_insights_merged_json "$days")
  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    printf 'No skill attribution data yet — run some sessions or `claudii-insights aggregate --force`.\n'
    return 0
  fi

  # Extract the right attribution block key.
  local attr_key="attribution_skills"
  local section_label="Skill"
  case "$attr_kind" in
    plugin) attr_key="attribution_plugins"; section_label="Plugin" ;;
    mcp)    attr_key="attribution_mcp";     section_label="MCP Tool" ;;
  esac

  # Price each row at real per-model rates: every per-model token bucket in
  # attribution_models is priced at its own tier, and any residual not covered by
  # per-model data (pre-v5 orphans) is priced at the flat Sonnet rate. The
  # dominant model per row comes from the per-model call counts: the top model
  # needs ≥80% of the row's attributed calls, otherwise "mixed".
  # Output: TSV — name\tcalls\ttot_usd\tavg_usd\tmodel\tin\tout\tcr\tcc
  local rows_tsv
  rows_tsv=$(jq -r \
    --arg k "$attr_key" \
    --arg kind "$attr_kind" \
    --argjson rates "$_rates" \
    '
    # Map a raw model id to a rate-table tier (most-specific first; unknown →
    # sonnet, the historical blended default). Keep in sync with the rate table.
    def tier($m):
      ($m // "" | ascii_downcase) as $l
      | if   ($l | test("fable|mythos")) then "fable"
        elif ($l | test("opus"))         then "opus"
        elif ($l | test("haiku"))        then "haiku"
        elif ($l | test("sonnet"))       then "sonnet"
        else "sonnet" end;
    ($rates.sonnet) as $sonnet
    | (.attribution_models // {} | to_entries
        | map((.key | split("|")) as $p
            | select($p[0] == $kind)
            | {name: ($p[1] // ""), model: ($p[2] // "unknown"),
               calls:        (.value.calls        // 0),
               in_tok:       (.value.in_tok       // 0),
               out_tok:      (.value.out_tok      // 0),
               cache_read:   (.value.cache_read   // 0),
               cache_create: (.value.cache_create // 0)})
      ) as $am
    | .[$k] // {}
    | to_entries
    | map({
        name:         .key,
        calls:        (.value.calls        // 0),
        in_tok:       (.value.in_tok       // 0),
        out_tok:      (.value.out_tok      // 0),
        cache_read:   (.value.cache_read   // 0),
        cache_create: (.value.cache_create // 0)
      })
    | map(. as $row
        | ([$am[] | select(.name == $row.name)]) as $cand
        # per-model priced cost (schema-v5 token attribution)
        | ($cand | map(($rates[tier(.model)]) as $r
            | (.in_tok * $r.in + .out_tok * $r.out + .cache_read * $r.cr + .cache_create * $r.cc)
          ) | add // 0) as $model_usd
        # residual = aggregate − per-model-covered tokens (pre-v5 orphans), flat Sonnet
        | (([$row.in_tok       - ($cand | map(.in_tok)       | add // 0), 0] | max)) as $res_in
        | (([$row.out_tok      - ($cand | map(.out_tok)      | add // 0), 0] | max)) as $res_out
        | (([$row.cache_read   - ($cand | map(.cache_read)   | add // 0), 0] | max)) as $res_cr
        | (([$row.cache_create - ($cand | map(.cache_create) | add // 0), 0] | max)) as $res_cc
        | ($res_in * $sonnet.in + $res_out * $sonnet.out + $res_cr * $sonnet.cr + $res_cc * $sonnet.cc) as $res_usd
        | $row + {tot_usd: ($model_usd + $res_usd)}
      )
    | map(. + {avg_usd: (if .calls > 0 then .tot_usd / .calls else 0 end)})
    | map(. as $row | $row + {model: (
        [$am[] | select(.name == $row.name)] as $cand
        | ($cand | map(.calls) | add // 0) as $tot
        | if $tot <= 0 then "mixed"
          else ($cand | max_by(.calls)) as $top
            | (if ($top.calls / $tot) >= 0.8 then $top.model else "mixed" end)
          end
      )})
    | sort_by(-.tot_usd)
    | .[]
    | [.name, (.calls | tostring), (.tot_usd | tostring), (.avg_usd | tostring), .model,
       (.in_tok | tostring), (.out_tok | tostring), (.cache_read | tostring), (.cache_create | tostring)]
    | @tsv
    ' <<< "$merged" 2>/dev/null)

  if [[ -z "$rows_tsv" ]]; then
    printf 'No skill attribution data yet — run some sessions or `claudii-insights aggregate --force`.\n'
    return 0
  fi

  # Load rows into parallel arrays (bash 3.2 compatible — no declare -A)
  local _sc_names=() _sc_calls=() _sc_tot=() _sc_avg=() _sc_model=()
  local _sc_in=() _sc_out=() _sc_cr=() _sc_cc=()
  local _sc_count=0
  while IFS=$'\t' read -r _rname _rcalls _rtot _ravg _rmodel _rin _rout _rcr _rcc; do
    [[ -z "$_rname" ]] && continue
    _sc_names[$_sc_count]="$_rname"
    _sc_calls[$_sc_count]="$_rcalls"
    _sc_tot[$_sc_count]="$_rtot"
    _sc_avg[$_sc_count]="$_ravg"
    _sc_model[$_sc_count]="${_rmodel:-mixed}"
    _sc_in[$_sc_count]="${_rin:-0}"
    _sc_out[$_sc_count]="${_rout:-0}"
    _sc_cr[$_sc_count]="${_rcr:-0}"
    _sc_cc[$_sc_count]="${_rcc:-0}"
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

  # Outlier rule: avg ≥ 2× median AND ≥ 10 calls. The original 3× threshold
  # never fired on real data (max observed was 2.1×); the calls floor keeps
  # rarely-used skills from tripping the flag on noise.
  local _outlier_min_calls=10
  local _threshold
  _threshold=$(awk -v m="$_median_avg" 'BEGIN { printf "%.10f", m * 2 }')

  # JSON output mode
  if [[ "$fmt" == "json" ]]; then
    local _json_rows="["
    local _first=1
    for (( _i=0; _i<_sc_count; _i++ )); do
      local _outlier="false"
      _outlier=$(awk -v a="${_sc_avg[$_i]}" -v t="$_threshold" -v c="${_sc_calls[$_i]}" -v mc="$_outlier_min_calls" \
        'BEGIN { print (a+0 >= t+0 && c+0 >= mc+0) ? "true" : "false" }')
      [[ "$_first" -eq 0 ]] && _json_rows+=","
      # Token split per row: the judgment signal consumers need — out-heavy
      # ("skill talks too much" → reply-cap helps) vs cache_read-heavy ("runs
      # in fat sessions" → SKILL.md edits won't move the needle).
      _json_rows+=$(jq -n \
        --arg name "${_sc_names[$_i]}" \
        --arg calls "${_sc_calls[$_i]}" \
        --arg tot "${_sc_tot[$_i]}" \
        --arg avg "${_sc_avg[$_i]}" \
        --arg model "${_sc_model[$_i]}" \
        --arg itok "${_sc_in[$_i]}" \
        --arg otok "${_sc_out[$_i]}" \
        --arg cr "${_sc_cr[$_i]}" \
        --arg cc "${_sc_cc[$_i]}" \
        --argjson outlier "$_outlier" \
        '{name:$name, calls:($calls|tonumber), tot_usd:($tot|tonumber), avg_usd:($avg|tonumber), model:$model, outlier:$outlier,
          in_tok:($itok|tonumber), out_tok:($otok|tonumber), cache_read:($cr|tonumber), cache_create:($cc|tonumber)}')
      _first=0
    done
    _json_rows+="]"
    local _meta
    _meta=$(jq -n --arg med "$_median_avg" --arg d "$days" --arg mc "$_outlier_min_calls" \
      '{median_avg_usd:($med|tonumber),days:($d|tonumber),outlier_rule:("avg >= 2x median, calls >= " + $mc),
        pricing:"per-model rates from schema-v5 token attribution (Opus $5/$25/M, Sonnet $3/$15/M, Haiku $1/$5/M, Fable $10/$50/M; cache_read 0.1x, cache_create 1.25x input). Pre-v5 / orphaned caches lack the per-model token split; their residual tokens are priced at the flat Sonnet rate"}')
    printf '%s\n' "{\"rows\":${_json_rows},\"meta\":${_meta}}"
    return 0
  fi

  # Pretty output. MCP tool names are long — widen the name column and drop
  # the redundant mcp__ prefix for display (data keeps the full name).
  local _col_name_w=27
  [[ "$attr_kind" == "mcp" ]] && _col_name_w=40
  local _hdr_fmt="%-${_col_name_w}s %7s %8s %8s %-12s %s\n"
  local _row_fmt="%-${_col_name_w}s %7s %8s %8s %-12s %s\n"
  local _sep_seg
  printf -v _sep_seg '%*s' "$_col_name_w" ''
  _sep_seg=${_sep_seg// /─}
  local _sep_line
  printf -v _sep_line '%s %-7s %-8s %-8s %-12s %-4s' \
    "$_sep_seg" '───────' '────────' '────────' '────────────' '────'

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

    # Calls may be fractional-free but MCP rows can carry float token sums;
    # the calls column itself is always an integer count.
    [[ "$attr_kind" == "mcp" ]] && _name="${_name#mcp__}"

    # Truncate name if too long
    if (( ${#_name} > _col_name_w )); then
      _name="${_name:0:$(( _col_name_w - 1 ))}…"
    fi

    # Model label: dominant model id → friendly label, "mixed" stays as-is
    local _model="${_sc_model[$_i]}"
    [[ "$_model" != "mixed" ]] && _model=$(_insights_model_label "$_model")

    # Outlier flag
    local _is_outlier
    _is_outlier=$(awk -v a="${_sc_avg[$_i]}" -v t="$_threshold" -v c="$_calls" -v mc="$_outlier_min_calls" \
      'BEGIN { print (a+0 >= t+0 && c+0 >= mc+0) ? "1" : "0" }')
    [[ "$_is_outlier" == "1" ]] && _flag="${CLAUDII_CLR_YELLOW}!${CLAUDII_CLR_RESET}"

    printf "${_row_fmt}" \
      "$_name" \
      "$_calls" \
      "\$${_tot_fmt}" \
      "\$${_avg_fmt}" \
      "$_model" \
      "$_flag"
  done

  printf '\n'
  local _med_fmt
  _med_fmt=$(awk -v v="$_median_avg" 'BEGIN { printf "%.4f", v+0 }')
  printf "${CLAUDII_CLR_DIM}Median cost/call: \$%s — rows flagged (!) are ≥2× median with ≥%d calls${CLAUDII_CLR_RESET}\n" "$_med_fmt" "$_outlier_min_calls"
  printf '\n'
}
