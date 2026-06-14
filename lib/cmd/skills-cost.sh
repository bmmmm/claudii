# lib/cmd/skills-cost.sh — per-skill / per-plugin / per-MCP-tool cost breakdown (claudii skills-cost)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail.
#
# Reads attribution_skills / attribution_plugins / attribution_mcp from the insights
# cache — a separate data source from the session-cache commands in sessions.sh, so it
# lives on its own. Token pricing uses a blended Sonnet rate (see the pricing-constants
# note in-function).

# --compare BEFORE:AFTER trend view. Compares the prior window
# [now-(B+A), now-A) against the recent window [now-A, now] so a SKILL.md edit's
# effect can be read. The headline metric is out-tokens/call — output tokens do
# NOT scale with session context size, so unlike $/call (which is structurally
# higher for session-end skills) it isolates "does the skill talk less now?".
# $/call is shown for reference but flagged as context-confounded.
# Args: compare attr_kind attr_key section_label fmt rates_json
_skills_cost_compare() {
  local compare="$1" attr_kind="$2" attr_key="$3" section_label="$4" fmt="$5" _rates="$6"

  if [[ ! "$compare" =~ ^[0-9]+:[0-9]+$ ]]; then
    printf 'claudii: --compare wants BEFORE:AFTER in days, e.g. --compare 30:30 (got: %s)\n' "$compare" >&2
    return 1
  fi
  local _before="${compare%%:*}" _after="${compare##*:}"
  if [[ "$_before" -lt 1 || "$_after" -lt 1 ]]; then
    printf 'claudii: --compare BEFORE and AFTER must both be >= 1 day (got: %s)\n' "$compare" >&2
    return 1
  fi

  # recent = last AFTER days; prior = the BEFORE days immediately before that.
  local _recent _prior
  _recent=$(_insights_merged_json "$_after")
  _prior=$(_insights_merged_json "$(( _before + _after ))" "$_after")
  [[ -z "$_recent" ]] && _recent="{}"
  [[ -z "$_prior"  ]] && _prior="{}"
  # No early-return on empty windows: an empty/no-overlap result flows through to
  # rows=[] so --json still emits a valid {compare, metric, rows:[]} envelope
  # (the session-close Phase 2.7 consumer parses it) and text mode prints the
  # "no comparable activity" line below.

  # Build the joined comparison rows as a JSON array (shared by both renderers).
  # Program lives in lib/skills-cost-compare.jq (pricing + window join);
  # tier() comes from the lib/tier.jq module via -L.
  # No 2>/dev/null: a failing program (broken CLAUDII_HOME, jq without module
  # support) must surface as an error, not masquerade as "no activity".
  local _rows_json
  _rows_json=$(jq -n -L "$CLAUDII_HOME/lib" \
    --arg k "$attr_key" \
    --arg kind "$attr_kind" \
    --argjson rates "$_rates" \
    --argjson prior "$_prior" \
    --argjson recent "$_recent" \
    -f "$CLAUDII_HOME/lib/skills-cost-compare.jq" 2>&1) || {
    printf 'claudii: skills-cost compare program failed (lib/skills-cost-compare.jq):\n%s\n' "$_rows_json" >&2
    return 1
  }

  if [[ -z "$_rows_json" ]]; then _rows_json="[]"; fi

  # JSON mode — emit the joined rows + window/metric metadata.
  if [[ "$fmt" == "json" ]]; then
    jq -n --argjson rows "$_rows_json" --argjson b "$_before" --argjson a "$_after" --arg kind "$attr_kind" \
      '{compare:{kind:$kind, before_days:$b, after_days:$a,
                 windows:"prior = [now-(BEFORE+AFTER), now-AFTER); recent = [now-AFTER, now]"},
        metric:"out_per_call is the context-robust signal (output tokens do not scale with session context size); avg_usd is shown but confounded by per-call context size — do not read it as edit impact",
        rows:$rows}'
    return 0
  fi

  if [[ "$(jq 'length' <<< "$_rows_json" 2>/dev/null)" == "0" ]]; then
    printf '\n  No comparable %s activity across the two windows.\n\n' "$attr_kind"
    return 0
  fi

  # Text table.
  local _col_name_w=22
  [[ "$attr_kind" == "mcp" ]] && _col_name_w=34
  printf '\n'
  printf "${CLAUDII_CLR_CYAN}claudii skills-cost --compare %s${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_DIM}(prior %sd → recent %sd)${CLAUDII_CLR_RESET}\n\n" \
    "$compare" "$_before" "$_after"
  printf "${CLAUDII_CLR_DIM}%-${_col_name_w}s %-13s %-17s %-12s %s${CLAUDII_CLR_RESET}\n" \
    "$section_label" "Calls" "out/call" "Δ out/call" "\$/call (ctx-conf.)"
  local _sep_seg; printf -v _sep_seg '%*s' "$_col_name_w" ''; _sep_seg=${_sep_seg// /─}
  printf "${CLAUDII_CLR_DIM}%s %-13s %-17s %-12s %s${CLAUDII_CLR_RESET}\n" \
    "$_sep_seg" '─────────────' '─────────────────' '────────────' '──────────────────'

  while IFS=$'\t' read -r _name _cp _cr _opcp _opcr _opcd _avgp _avgr; do
    [[ -z "$_name" ]] && continue
    [[ "$attr_kind" == "mcp" ]] && _name="${_name#mcp__}"
    if (( ${#_name} > _col_name_w )); then _name="${_name:0:$(( _col_name_w - 1 ))}…"; fi
    local _opcp_i _opcr_i _opcd_i _avgp_f _avgr_f
    _opcp_i=$(LC_ALL=C awk -v v="$_opcp" 'BEGIN{printf "%.0f", v}')
    _opcr_i=$(LC_ALL=C awk -v v="$_opcr" 'BEGIN{printf "%.0f", v}')
    _opcd_i=$(LC_ALL=C awk -v v="$_opcd" 'BEGIN{printf "%+.0f", v}')
    _avgp_f=$(LC_ALL=C awk -v v="$_avgp" 'BEGIN{printf "%.4f", v}')
    _avgr_f=$(LC_ALL=C awk -v v="$_avgr" 'BEGIN{printf "%.4f", v}')
    # Δ arrow: less output after the edit (↓) is the desired direction.
    local _arrow
    if   LC_ALL=C awk -v v="$_opcd" 'BEGIN{exit !(v < -0.5)}'; then _arrow="${CLAUDII_CLR_GREEN}↓${CLAUDII_CLR_RESET}"
    elif LC_ALL=C awk -v v="$_opcd" 'BEGIN{exit !(v >  0.5)}'; then _arrow="${CLAUDII_CLR_YELLOW}↑${CLAUDII_CLR_RESET}"
    else _arrow="${CLAUDII_CLR_DIM}·${CLAUDII_CLR_RESET}"; fi
    printf "%-${_col_name_w}s %-13s %-17s %b %-10s ${CLAUDII_CLR_DIM}\$%s → \$%s${CLAUDII_CLR_RESET}\n" \
      "$_name" "${_cp} → ${_cr}" "${_opcp_i} → ${_opcr_i}" "$_arrow" "$_opcd_i" "$_avgp_f" "$_avgr_f"
  done < <(jq -r '.[] | [.name, (.calls_prior|tostring), (.calls_recent|tostring),
                          (.out_per_call_prior|tostring), (.out_per_call_recent|tostring), (.out_per_call_delta|tostring),
                          (.avg_usd_prior|tostring), (.avg_usd_recent|tostring)] | @tsv' <<< "$_rows_json")

  printf '\n'
  printf "${CLAUDII_CLR_DIM}out/call is the context-robust signal (output tokens don't scale with session size).${CLAUDII_CLR_RESET}\n"
  printf "${CLAUDII_CLR_DIM}\$/call is confounded by per-call context size — don't read it as edit impact.${CLAUDII_CLR_RESET}\n"
  printf '\n'
}

_cmd_skills_cost() {
  _cfg_init

  local days=30 attr_kind="skill" fmt="${_FORMAT:-}" compare=""
  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days|-d)   shift; days="${1:-30}" ;;
      --compare)   shift; compare="${1:-}" ;;
      --plugins)   attr_kind="plugin" ;;
      --mcp)       attr_kind="mcp" ;;
      --json)      fmt="json" ;;
      -h|--help)
        printf 'Usage: claudii skills-cost [--days N] [--compare BEFORE:AFTER] [--plugins] [--mcp] [--json]\n'
        return 0
        ;;
      *)
        printf 'claudii: unknown skills-cost flag: %s — run claudii skills-cost --help\n' "$1" >&2
        return 1
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
  # this table AND the tier mapping in lib/tier.jq (shared jq module).
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

  # Resolve the attribution block key for the chosen kind.
  local attr_key="attribution_skills"
  local section_label="Skill"
  case "$attr_kind" in
    plugin) attr_key="attribution_plugins"; section_label="Plugin" ;;
    mcp)    attr_key="attribution_mcp";     section_label="MCP Tool" ;;
  esac

  # --compare BEFORE:AFTER → two-window trend comparison (own renderer + merge
  # windows), so session-close Phase 2.7 can ask "did the SKILL.md edit help?".
  if [[ -n "$compare" ]]; then
    _skills_cost_compare "$compare" "$attr_kind" "$attr_key" "$section_label" "$fmt" "$_rates"
    return $?
  fi

  # Aggregate via `claudii-insights merge` (through the shared helper) — the
  # --days cutoff and cross-session summing live there, single source of truth.
  # This function used to re-implement both against the raw cache files.
  local merged
  merged=$(_insights_merged_json "$days")
  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    printf 'No skill attribution data yet — run some sessions or `claudii-insights aggregate --force`.\n'
    return 0
  fi

  # Price each row at real per-model rates — program lives in
  # lib/skills-cost-rows.jq (pricing, residual fallback, dominant model);
  # tier() comes from the lib/tier.jq module via -L.
  # Output: TSV — name\tcalls\ttot_usd\tavg_usd\tmodel\tin\tout\tcr\tcc
  # No 2>/dev/null: a failing program (broken CLAUDII_HOME, jq without module
  # support) must surface as an error, not masquerade as "no data yet".
  local rows_tsv
  rows_tsv=$(jq -r -L "$CLAUDII_HOME/lib" \
    --arg k "$attr_key" \
    --arg kind "$attr_kind" \
    --argjson rates "$_rates" \
    -f "$CLAUDII_HOME/lib/skills-cost-rows.jq" <<< "$merged" 2>&1) || {
    printf 'claudii: skills-cost pricing program failed (lib/skills-cost-rows.jq):\n%s\n' "$rows_tsv" >&2
    return 1
  }

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
  _median_avg=$(printf '%s\n' "${_sc_avg[@]}" | LC_ALL=C sort -n | LC_ALL=C awk '
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
  _threshold=$(LC_ALL=C awk -v m="$_median_avg" 'BEGIN { printf "%.10f", m * 2 }')

  # JSON output mode
  if [[ "$fmt" == "json" ]]; then
    local _json_rows="["
    local _first=1
    for (( _i=0; _i<_sc_count; _i++ )); do
      local _outlier="false"
      _outlier=$(LC_ALL=C awk -v a="${_sc_avg[$_i]}" -v t="$_threshold" -v c="${_sc_calls[$_i]}" -v mc="$_outlier_min_calls" \
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

    _tot_fmt=$(LC_ALL=C awk -v v="${_sc_tot[$_i]}" 'BEGIN { printf "%.4f", v+0 }')
    _avg_fmt=$(LC_ALL=C awk -v v="${_sc_avg[$_i]}" 'BEGIN { printf "%.4f", v+0 }')

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
    _is_outlier=$(LC_ALL=C awk -v a="${_sc_avg[$_i]}" -v t="$_threshold" -v c="$_calls" -v mc="$_outlier_min_calls" \
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
  _med_fmt=$(LC_ALL=C awk -v v="$_median_avg" 'BEGIN { printf "%.4f", v+0 }')
  printf "${CLAUDII_CLR_DIM}Median cost/call: \$%s — rows flagged (!) are ≥2× median with ≥%d calls${CLAUDII_CLR_RESET}\n" "$_med_fmt" "$_outlier_min_calls"
  printf '\n'
}
