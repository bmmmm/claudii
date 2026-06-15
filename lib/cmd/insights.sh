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

# Shared rolling-window argument parser for cache/tokens/tools/limits. Lets the
# window be *cycled* without remembering --days: a named window (today/day,
# week, month, quarter, year), a generic <N>d token (e.g. 14d), or the explicit
# --days N / -d N. Sets _IW_DAYS (validated positive int) and _IW_HELP (1 when
# -h/--help was seen, so the caller prints its own usage). Prints an actionable
# error and returns 1 on an unknown token or non-numeric window.
# Args: command-label, then the command's positional "$@" (bin/claudii has
# already stripped --json/--tsv into $_FORMAT before dispatch).
_insights_window() {
  local cmd="$1"; shift
  local days=7
  _IW_HELP=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days|-d)   shift; days="${1:-7}" ;;
      today|day)   days=1   ;;
      week)        days=7   ;;
      month)       days=30  ;;
      quarter)     days=90  ;;
      year)        days=365 ;;
      [0-9]*d)     days="${1%d}" ;;
      -h|--help)   _IW_HELP=1 ;;
      *)
        printf 'claudii: unknown %s argument: %s\n' "$cmd" "$1" >&2
        printf '  try: claudii %s [today|7d|30d|year] [--days N]\n' "$cmd" >&2
        return 1
        ;;
    esac
    shift || break   # value-flag as last arg consumed $@; avoid set -e abort on empty shift
  done
  _IW_DAYS="$days"
  (( _IW_HELP )) && return 0
  if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
    printf 'claudii: --days must be a positive integer (got: %s)\n' "$days" >&2
    return 1
  fi
  return 0
}

# Human window label: "today" for a 1-day window, "last N days" otherwise.
# Keeps the section headers grammatical when a named window resolves to 1 day.
_insights_window_label() {
  if [[ "${1:-}" == "1" ]]; then printf 'today'; else printf 'last %s days' "$1"; fi
}

# ── claudii cache ────────────────────────────────────────────────────────────

_cmd_cache() {
  _cfg_init
  _insights_refresh

  # Window parsing + validation is centralized in _insights_window (the merge
  # also validates, but _insights_merged_json swallows its stderr, so a bad
  # value used to surface as the misleading "No insight data yet").
  _insights_window cache "${@:2}" || return 1
  if (( _IW_HELP )); then
    printf 'Usage: claudii cache [WINDOW] [--days N]\n\n'
    printf 'WINDOW is one of today, 7d, 30d, 90d, year (or any <N>d).\n'
    printf 'Show prompt-cache hit rate per day and per model.\n'
    return 0
  fi
  local days="$_IW_DAYS"

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
      local pct_str; pct_str=$(LC_ALL=C awk -v r="$creads" -v t="$total" 'BEGIN{printf "%.1f", 100*r/t}')
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
      local pct_str; pct_str=$(LC_ALL=C awk -v r="$creads" -v t="$total" 'BEGIN{printf "%.1f", 100*r/t}')
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
    local hit_pct; hit_pct=$(LC_ALL=C awk -v r="$tot_r" -v t="$tot_all" 'BEGIN{printf "%.1f", 100*r/t}')
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

  _insights_window tokens "${@:2}" || return 1
  if (( _IW_HELP )); then
    printf 'Usage: claudii tokens [WINDOW] [--days N] [--json]\n\n'
    printf 'WINDOW is one of today, 7d, 30d, 90d, year (or any <N>d).\n'
    printf 'Token breakdown by type, model and day (input+output is the\n'
    printf 'primary figure; cache read/write and hit%% shown alongside).\n'
    return 0
  fi
  local days="$_IW_DAYS"

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

  local note hpad; note=$(_insights_window_label "$days")
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

# ── claudii session <id> ─────────────────────────────────────────────────────
# Per-session drilldown: token split, tools, subagents, stop reasons, limit hits
# from the per-session insights cache (keyed by sessionId, substring match like
# pin). Live ctx%/model/project come from the session-* cache when one still
# exists — ended sessions keep only the insights cache, so those degrade
# gracefully (dominant model from the token data, no ctx bar, repo basename).

_cmd_session() {
  _cfg_init
  _insights_refresh

  local needle="${1:-}"
  case "$needle" in
    ''|-h|--help)
      printf 'Usage: claudii session <id>\n\n'
      printf 'Per-session token / tool / subagent drilldown. <id> is a session-id\n'
      printf 'substring (first match wins); list ids with: claudii se\n'
      [[ -z "$needle" ]] && return 1 || return 0
      ;;
  esac

  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" green="${CLAUDII_CLR_GREEN}" yellow="${CLAUDII_CLR_YELLOW}"
  local cdir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local idir="$cdir/insights"

  # Match insights cache by sessionId substring (first wins).
  local jf="" sid="" f
  for f in "$idir"/*"$needle"*.json; do
    [[ -e "$f" ]] || continue
    jf="$f"; sid="${f##*/}"; sid="${sid%.json}"; break
  done
  if [[ -z "$jf" ]]; then
    printf 'claudii: no session matching %s — list ids with: claudii se\n' "$needle" >&2
    return 1
  fi

  # Enrichment: live session-* cache for ctx%/model/project (often absent).
  local have_live=0 sf s2 ln
  for sf in "$cdir"/session-*; do
    [[ -e "$sf" ]] || continue
    s2=""; while IFS= read -r ln; do s2="${ln#*=}"; break; done < <(grep '^session_id=' "$sf" 2>/dev/null)
    if [[ "$s2" == "$sid" ]]; then _parse_session_cache "$sf"; have_live=1; break; fi
  done

  # Scalars: first_seen, last_seen, thinking blocks, total tool calls + errors.
  # first_seen/last_seen can be "" (a degenerate cache may lack them), so the
  # fields are US-joined (0x1f), NOT tab — a leading empty tab-field collapses
  # under IFS-whitespace and shifts every column left (the CLAUDE.md IFS trap).
  local meta; meta=$(jq -r '
    [ (.first_seen // ""),
      (.last_seen // ""),
      ((.thinking_blocks // 0) | tostring),
      (([.tools[]?] | add // 0) | tostring),
      (([.tool_errors[]?] | add // 0) | tostring) ] | join([31] | implode)
  ' "$jf")
  local first_seen last_seen think tcalls terrs
  IFS=$'\x1f' read -r first_seen last_seen think tcalls terrs <<< "$meta"

  # Duration = last_seen - first_seen.
  local dur="—" e0 e1
  if [[ -n "$first_seen" && -n "$last_seen" ]]; then
    _iso_epoch "$first_seen"; e0="$_EPOCH"
    _iso_epoch "$last_seen";  e1="$_EPOCH"
    if [[ "$e0" =~ ^[0-9]+$ && "$e1" =~ ^[0-9]+$ ]] && (( e1 >= e0 )); then
      _fmt_rel $(( e1 - e0 )); [[ -n "$_REL_FMT" ]] && dur="$_REL_FMT"
    fi
  fi

  # Model: live (stripped) else the dominant model by in+out tokens.
  local model_lbl
  if (( have_live )) && [[ -n "${_PSC_model:-}" ]]; then
    model_lbl=$(_strip_model_name "$_PSC_model")
  else
    local dom; dom=$(jq -r '
      [ .days | to_entries[] | (.key|split("|")) as $p
        | select($p[1] != "<synthetic>")
        | {m: $p[1], t: ((.value.in_tok // 0) + (.value.out_tok // 0))} ]
      | group_by(.m) | map({m: .[0].m, t: ([.[].t] | add)})
      | (max_by(.t).m) // "" ' "$jf")
    model_lbl=$(_insights_model_label "$dom")
  fi

  # Project: live path (shortened) else the repo basename from the transcript dir.
  local proj="" pdir d enc
  if (( have_live )) && [[ -n "${_PSC_project_path:-}" ]]; then
    proj="${_PSC_project_path/#$HOME/~}"
  else
    pdir="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
    for d in "$pdir"/*/; do
      if [[ -e "$d$sid.jsonl" ]]; then enc="${d%/}"; enc="${enc##*/}"; proj="${enc##*-}"; break; fi
    done
  fi

  # ── Header ──
  printf '\n  %sclaudii session%s  %s%s%s' \
    "$cyan" "$reset" "$accent" "${sid:0:8}" "$reset"
  [[ -n "$proj" ]] && printf '  %s·  %s%s' "$dim" "$proj" "$reset"
  printf '\n\n'

  # ── Status: ● model · duration [· ctx bar] ──
  printf '  %s●%s %s%s%s   %s·%s   %s%s%s' \
    "$green" "$reset" "$accent" "$model_lbl" "$reset" \
    "$dim" "$reset" "$cyan" "$dur" "$reset"
  if (( have_live )) && [[ "${_PSC_ctx_pct:-}" =~ ^[0-9]+$ ]]; then
    local cf; cf=$(_bar_filled "$_PSC_ctx_pct" 100 16)
    printf '   %s·%s   %s  %s%d%% ctx%s' \
      "$dim" "$reset" "$(_bar_c "$cf" 16)" "$cyan" "$_PSC_ctx_pct" "$reset"
  fi
  printf '\n\n'

  local RW=66 BAR_W=34

  # ── Tokens (share over input+output+cache-write; cache read shown separately) ──
  local toks; toks=$(jq -r '
    [ .days | to_entries[] | select((.key|split("|")[1]) != "<synthetic>") | .value ] as $v
    | [ ([$v[].in_tok//0]|add//0), ([$v[].out_tok//0]|add//0),
        ([$v[].cache_read//0]|add//0), ([$v[].cache_create//0]|add//0) ] | @tsv
  ' "$jf")
  local t_in t_out t_cr t_cw
  IFS=$'\t' read -r t_in t_out t_cr t_cw <<< "$toks"
  local work=$(( t_in + t_out + t_cw ))

  _render_shead "Tokens" "share" "$RW"
  if (( work == 0 )); then
    printf '    %s(no token data)%s\n' "$dim" "$reset"
  else
    local pair _sl _sv bf pct suf
    for pair in "input:$t_in" "output:$t_out" "cache write:$t_cw"; do
      _sl="${pair%%:*}"; _sv="${pair##*:}"
      bf=$(_bar_filled "$_sv" "$work" "$BAR_W")
      pct=$(( _sv * 100 / work ))
      printf -v suf '%s%3d%%%s' "$cyan" "$pct" "$reset"
      _render_bar_row "$_sl" 11 "$(_fmt_tok "$_sv")" 7 "$bf" "$BAR_W" "$suf"
    done
    printf '  %s%s%s\n' "$dim" "$(_rep '─' "$RW")" "$reset"
    local hit; hit=$(_cache_hit_pct "$t_cr" $(( t_in + t_cw )))
    printf '  %-11s  %s%7s%s   %s%d%% hit%s\n' \
      "cache read" "$cyan" "$(_fmt_tok "$t_cr")" "$reset" "$dim" "$hit" "$reset"
    if [[ "$think" =~ ^[0-9]+$ ]] && (( think > 0 )); then
      printf '  %-11s  %sin %d blocks%s\n' "thinking" "$dim" "$think" "$reset"
    fi
  fi
  echo

  # ── Tools (top 8 by count, normalized bars, error markers) ──
  local tnote="${tcalls} calls"
  [[ "$terrs" =~ ^[0-9]+$ ]] && (( terrs > 0 )) && tnote="$tnote · $terrs err"
  _render_shead "Tools" "$tnote" "$RW"
  local toolrows; toolrows=$(jq -r '
    (.tool_errors // {}) as $e
    | (.tools // {}) | to_entries
    | map(select(.key != "") | {name: .key, n: .value, e: ($e[.key] // 0)})
    | sort_by(-.n) | .[:8]
    | .[] | [.name, .n, .e] | @tsv
  ' "$jf")
  if [[ -z "$toolrows" ]]; then
    printf '    %s(no tool calls)%s\n' "$dim" "$reset"
  else
    local maxn=0 nm cnt ec
    while IFS=$'\t' read -r nm cnt ec; do
      [[ -z "$nm" ]] && continue
      (( cnt > maxn )) && maxn=$cnt
    done <<< "$toolrows"
    while IFS=$'\t' read -r nm cnt ec; do
      [[ -z "$nm" ]] && continue
      local tbf tsuf=""
      tbf=$(_bar_filled "$cnt" "$maxn" "$BAR_W")
      if [[ "$ec" =~ ^[0-9]+$ ]] && (( ec > 0 )); then
        printf -v tsuf '%s⚠ %d err%s' "$yellow" "$ec" "$reset"
      fi
      _render_bar_row "$nm" 16 "$cnt" 5 "$tbf" "$BAR_W" "$tsuf"
    done <<< "$toolrows"
  fi
  echo

  # ── Subagents / Stop reasons / Limit hits (compact one-liners) ──
  local sub_tot sub_str
  IFS=$'\t' read -r sub_tot sub_str < <(jq -r '
    .subagent_types // {} | to_entries | sort_by(-.value)
    | ((map(.value) | add // 0) | tostring) + "\t"
      + ((map("\(.key) ×\(.value)")) | join(" · "))
  ' "$jf")
  if [[ "$sub_tot" =~ ^[0-9]+$ ]] && (( sub_tot > 0 )); then
    printf '  %s%-12s%s %s%3d%s   %s%s%s\n' \
      "$accent" "Subagents" "$reset" "$cyan" "$sub_tot" "$reset" "$dim" "$sub_str" "$reset"
  fi

  local stop_str; stop_str=$(jq -r '
    .stop_reasons // {} | to_entries | sort_by(-.value)
    | (map("\(.key) ×\(.value)")) | join(" · ")
  ' "$jf")
  if [[ -n "$stop_str" ]]; then
    printf '  %s%-12s%s     %s%s%s\n' \
      "$accent" "Stop reasons" "$reset" "$dim" "$stop_str" "$reset"
  fi

  local lh; lh=$(jq -r '.limit_hits // [] | .[] | [(.timestamp // ""), (.model // "")] | @tsv' "$jf")
  if [[ -n "$lh" ]]; then
    local lcount=0 lt lm last_ts="" last_m=""
    while IFS=$'\t' read -r lt lm; do
      [[ -z "$lt" ]] && continue
      last_ts="$lt"; last_m="$lm"; (( ++lcount ))
    done <<< "$lh"
    local labs="—"; _iso_epoch "$last_ts"
    if [[ "$_EPOCH" =~ ^[0-9]+$ ]]; then _fmt_abs "$_EPOCH" '%a %H:%M'; [[ -n "$_ABS_FMT" ]] && labs="$_ABS_FMT"; fi
    # The model is "what ran when the cap hit", not "what is to blame" (the 5h
    # budget is account-wide). Drop the clause when it did not resolve.
    local during=""
    [[ -n "$last_m" && "$last_m" != "unknown" ]] && during=" · during $(_insights_model_label "$last_m")"
    printf '  %s⚠ Limit hits%s %s%3d%s   %s5h budget reached %s%s  (account-wide)%s\n' \
      "$yellow" "$reset" "$cyan" "$lcount" "$reset" "$dim" "$labs" "$during" "$reset"
  fi
  echo
}

# ── claudii tools ────────────────────────────────────────────────────────────
# Tool / efficiency lens over the rolling window: call counts + error rates,
# subagents spawned, thinking volume. The throughput/reliability companion to
# skills-cost (which is $-focused). MCP tool names are shortened to their tool
# segment; the long tail is folded into a "+N more" line.

_cmd_tools() {
  _cfg_init
  _insights_refresh

  _insights_window tools "${@:2}" || return 1
  if (( _IW_HELP )); then
    printf 'Usage: claudii tools [WINDOW] [--days N] [--json]\n\n'
    printf 'WINDOW is one of today, 7d, 30d, 90d, year (or any <N>d).\n'
    printf 'Tool call counts, error rates, subagents and thinking volume\n'
    printf 'for the rolling window.\n'
    return 0
  fi
  local days="$_IW_DAYS"

  local merged; merged=$(_insights_merged_json "$days")
  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    printf '  No insight data yet — run a Claude session and try again.\n'
    return 0
  fi

  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" yellow="${CLAUDII_CLR_YELLOW}"
  local RW=66 BAR_W=28

  # Totals (both always numeric → @tsv safe).
  local totcalls toterrs
  IFS=$'\t' read -r totcalls toterrs < <(jq -r '
    [ ([.tools[]? ] | add // 0), ([.tool_errors[]? ] | add // 0) ] | @tsv
  ' <<< "$merged")
  (( totcalls == 0 )) && { printf '  No tool calls recorded in the last %dd.\n\n' "$days"; return 0; }
  local okpct; okpct=$(LC_ALL=C awk -v c="$totcalls" -v e="$toterrs" 'BEGIN{printf "%.1f", 100*(c-e)/c}')

  local note hpad; printf -v note '%s · %s calls · %s%% ok' "$(_insights_window_label "$days")" "$totcalls" "$okpct"
  hpad=$(( RW - 13 - ${#note} )); (( hpad < 1 )) && hpad=1
  printf '\n  %sclaudii tools%s%*s%s%s%s\n\n' \
    "$cyan" "$reset" "$hpad" "" "$dim" "$note" "$reset"

  # ── Tool table (top 15 by calls; rest folded) ──
  _render_shead "Tool" "calls · share · errors" "$RW"
  local toolrows; toolrows=$(jq -r '
    (.tool_errors // {}) as $e
    | (.tools // {}) | to_entries
    | map(select(.key != "") | {name: .key, n: .value, e: ($e[.key] // 0)})
    | sort_by(-.n) | .[] | [.name, .n, .e] | @tsv
  ' <<< "$merged")
  local maxn=0 idx=0 rest_n=0 rest_c=0 nm cnt ec
  while IFS=$'\t' read -r nm cnt ec; do
    [[ -z "$nm" ]] && continue
    (( idx == 0 )) && maxn=$cnt
    if (( idx < 15 )); then
      local disp="$nm"
      case "$nm" in mcp__*) disp="${nm##*__}"; [[ -z "$disp" ]] && disp="$nm" ;; esac
      (( ${#disp} > 18 )) && disp="${disp:0:18}"
      local bf share suf err_str
      bf=$(_bar_filled "$cnt" "$maxn" "$BAR_W")
      share=$(( cnt * 100 / totcalls ))
      if [[ "$ec" =~ ^[0-9]+$ ]] && (( ec > 0 )); then
        local erate hi=""; erate=$(LC_ALL=C awk -v e="$ec" -v n="$cnt" 'BEGIN{printf "%.1f", 100*e/n}')
        LC_ALL=C awk -v e="$ec" -v n="$cnt" 'BEGIN{exit !(100*e/n > 5)}' && hi=" ${yellow}⚠${reset}"
        printf -v err_str '%s%d err · %s%%%s%s' "$dim" "$ec" "$erate" "$reset" "$hi"
      else
        printf -v err_str '%s—%s' "$dim" "$reset"
      fi
      printf -v suf '%s%3d%%%s   %s' "$cyan" "$share" "$reset" "$err_str"
      _render_bar_row "$disp" 18 "$cnt" 6 "$bf" "$BAR_W" "$suf"
    else
      (( ++rest_n )); rest_c=$(( rest_c + cnt ))
    fi
    (( ++idx ))
  done <<< "$toolrows"
  if (( rest_n > 0 )); then
    printf '  %s+%d more tools · %s calls%s\n' "$dim" "$rest_n" "$(_fmt_tok "$rest_c")" "$reset"
  fi
  echo

  # ── Subagents (spawned types) ──
  local subrows; subrows=$(jq -r '
    .subagent_types // {} | to_entries | map(select(.key != "")) | sort_by(-.value)
    | .[] | [.key, .value] | @tsv
  ' <<< "$merged")
  if [[ -n "$subrows" ]]; then
    local subtot; subtot=$(jq -r '[.subagent_types[]?] | add // 0' <<< "$merged")
    _render_shead "Subagents" "$subtot spawned" "$RW"
    local smax=0 sidx=0 stype scnt
    while IFS=$'\t' read -r stype scnt; do
      [[ -z "$stype" ]] && continue
      (( sidx == 0 )) && smax=$scnt
      local sbf; sbf=$(_bar_filled "$scnt" "$smax" "$BAR_W")
      _render_bar_row "$stype" 18 "$scnt" 6 "$sbf" "$BAR_W" ""
      (( ++sidx ))
    done <<< "$subrows"
    echo
  fi

  # ── Thinking volume + error-rate warning ──
  local think; think=$(jq -r '.thinking_blocks // 0' <<< "$merged")
  if [[ "$think" =~ ^[0-9]+$ ]] && (( think > 0 )); then
    printf '  %sThinking%s     %s%s blocks%s\n' "$accent" "$reset" "$cyan" "$(_fmt_tok "$think")" "$reset"
  fi
  local worst; worst=$(jq -r '
    (.tool_errors // {}) as $e
    | (.tools // {}) | to_entries
    | map(select(.key != "") | {name: .key, n: .value, e: ($e[.key] // 0)})
    | map(select(.n >= 20)) | map(. + {rate: (.e * 100 / .n)})
    | (max_by(.rate) // empty) | select(.rate > 5)
    | [.name, (.rate | floor)] | @tsv
  ' <<< "$merged")
  if [[ -n "$worst" ]]; then
    local wname wrate _w; IFS=$'\t' read -r wname wrate <<< "$worst"
    case "$wname" in mcp__*) _w="${wname##*__}"; [[ -n "$_w" ]] && wname="$_w" ;; esac
    printf '  %s⚠ %s has the highest error rate (%s%%) — worth a look%s\n' \
      "$yellow" "$wname" "$wrate" "$reset"
  fi
  echo
}

# ── claudii limits ───────────────────────────────────────────────────────────
# Rate-limit hits over the rolling window from limit_hits[]. Time + model only
# (the data carries no %, and the budget is account-wide — the model is "what
# ran when the cap hit", not "what is to blame"). An hour strip shows when hits
# cluster, since pacing total throughput across time is the only lever.

_cmd_limits() {
  _cfg_init
  _insights_refresh

  _insights_window limits "${@:2}" || return 1
  if (( _IW_HELP )); then
    printf 'Usage: claudii limits [WINDOW] [--days N] [--json]\n\n'
    printf 'WINDOW is one of today, 7d, 30d, 90d, year (or any <N>d).\n'
    printf 'Rate-limit hits in the rolling window: when they happened and\n'
    printf 'which model was running (the 5h budget is account-wide).\n'
    return 0
  fi
  local days="$_IW_DAYS"

  local merged; merged=$(_insights_merged_json "$days")
  if [[ -z "$merged" || "$merged" == "{}" ]]; then
    printf '  No insight data yet — run a Claude session and try again.\n'
    return 0
  fi

  local cyan="${CLAUDII_CLR_CYAN}" dim="${CLAUDII_CLR_DIM}" reset="${CLAUDII_CLR_RESET}"
  local accent="${CLAUDII_CLR_ACCENT}" yellow="${CLAUDII_CLR_YELLOW}" green="${CLAUDII_CLR_GREEN}"
  local RW=66

  # Most-recent-first; timestamp is always present (leading field) → @tsv safe.
  local hits; hits=$(jq -r '
    .limit_hits // [] | sort_by(.timestamp) | reverse
    | .[] | [(.timestamp // ""), (.model // "")] | @tsv
  ' <<< "$merged")

  if [[ -z "$hits" ]]; then
    printf '\n  %s●%s %sNo rate-limit hits (%s)%s — clear runway.\n\n' \
      "$green" "$reset" "$dim" "$(_insights_window_label "$days")" "$reset"
    return 0
  fi

  # Single pass: count, hour buckets, model tally, recent list.
  local total=0 ts model labs lH lhour modacc="" listed=0 list=""
  local -a hours
  while IFS=$'\t' read -r ts model; do
    [[ -z "$ts" ]] && continue
    (( ++total ))
    _iso_epoch "$ts"
    if [[ "$_EPOCH" =~ ^[0-9]+$ ]]; then
      _fmt_abs "$_EPOCH" '%H'; lhour="$_ABS_FMT"
      # Assignment form (not (( ++x ))): incrementing an unset array element
      # trips set -u; the ${x:-0} default keeps it bound and exit-0.
      if [[ "$lhour" =~ ^[0-9]+$ ]]; then
        local _hb=$(( 10#$lhour )); hours[_hb]=$(( ${hours[_hb]:-0} + 1 ))
      fi
    fi
    modacc+="$(_insights_model_label "$model")"$'\n'
    if (( listed < 10 )); then
      labs="?"; lH=""
      if [[ "$_EPOCH" =~ ^[0-9]+$ ]]; then
        _fmt_abs "$_EPOCH" '%a %d %b'; labs="$_ABS_FMT"
        _fmt_abs "$_EPOCH" '%H:%M';    lH="$_ABS_FMT"
      fi
      printf -v list '%s  %s%-10s%s  %s%5s%s   %s%s%s\n' "$list" \
        "$dim" "$labs" "$reset" "$cyan" "$lH" "$reset" \
        "$accent" "$(_insights_model_label "$model")" "$reset"
      (( ++listed ))
    fi
  done <<< "$hits"

  printf '\n  %s⚠ Rate limits%s   %s%d×%s %s· %s · 5h budget (account-wide)%s\n' \
    "$yellow" "$reset" "$cyan" "$total" "$reset" "$dim" "$(_insights_window_label "$days")" "$reset"
  printf '  %s%s%s\n' "$dim" "$(_rep '─' "$RW")" "$reset"
  printf '%s' "$list"
  (( total > listed )) && printf '  %s+%d earlier%s\n' "$dim" "$(( total - listed ))" "$reset"
  echo

  # Hour strip (00..23): accent block where a hit landed, dim otherwise.
  local strip="" h busiest=0 busiest_n=0
  for (( h=0; h<24; h++ )); do
    if (( ${hours[h]:-0} > 0 )); then
      strip+="${accent}${CLAUDII_SYM_BAR_FULL}"
      (( ${hours[h]:-0} > busiest_n )) && { busiest_n=${hours[h]:-0}; busiest=$h; }
    else
      strip+="${dim}${CLAUDII_SYM_BAR_EMPTY}"
    fi
  done
  strip+="$reset"
  printf '  %swhen%s   %s\n' "$accent" "$reset" "$strip"
  printf '         %s%s%s\n' "$dim" "0     6     12    18  23" "$reset"

  # Model tally (sorted desc) — "N× Label · ...".
  local tally; tally=$(printf '%s' "$modacc" | sort | uniq -c | sort -rn \
    | awk '{c=$1; $1=""; sub(/^ +/,""); printf "%s\303\227 %s \302\267 ", c, $0}')
  tally="${tally% · }"
  [[ -n "$tally" ]] && printf '  %smodels%s %s%s%s\n' "$accent" "$reset" "$dim" "$tally" "$reset"

  # Insight: clustering note when the busiest hour holds 2+ hits.
  if (( busiest_n >= 2 )); then
    printf '  %s→ hits cluster around %02d:00 — the 5h budget is account-wide, so pacing total throughput helps most%s\n' \
      "$dim" "$busiest" "$reset"
  fi
  echo
}
