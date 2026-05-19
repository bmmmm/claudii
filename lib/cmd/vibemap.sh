# lib/cmd/vibemap.sh — `claudii vibemap` subcommand.
#
# Renders activity heatmaps from the opt-in vibemap.tsv log written by
# bin/claudii-cc-statusline. Two views (grid + strip), pure aggregation
# delegated to lib/vibemap-{grid,strip}.awk; this module owns presentation.
#
# Sourced by bin/claudii. Depends on lib/vibemap.sh for path resolution.

# Density palette — 5 levels, normalized against max-cell-count per render.
# 0: blank, then ░ (≤25%), ▒ (≤50%), ▓ (≤75%), █ (>75%). Block chars are
# single-cell — alignment stays clean in fixed-width output.
_vibemap_density_char() {
  local count="$1" max="$2"
  if (( count == 0 || max == 0 )); then printf ' '; return; fi
  # Integer math: ratio in tenths.
  local r=$(( count * 100 / max ))
  if   (( r <  25 )); then printf '░'
  elif (( r <  50 )); then printf '▒'
  elif (( r <  75 )); then printf '▓'
  else                     printf '█'
  fi
}

# Read vibemap.{enabled,path} from config. Returns enabled flag and path.
_vibemap_load_config() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json"
  _VIBEMAP_ENABLED="false"
  _VIBEMAP_PATH=""
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    local enabled cfg_path
    enabled=$(jq -r '.vibemap.enabled // false' "$cfg" 2>/dev/null)
    cfg_path=$(jq -r '.vibemap.path // ""' "$cfg" 2>/dev/null)
    [[ "$enabled" == "true" ]] && _VIBEMAP_ENABLED="true"
    _VIBEMAP_PATH="$cfg_path"
  fi
  _VIBEMAP_PATH=$(_vibemap_resolve_path "$_VIBEMAP_PATH")
}

_vibemap_print_path() {
  _vibemap_load_config
  printf '%s\n' "$_VIBEMAP_PATH"
}

_vibemap_show_status() {
  _vibemap_load_config
  printf 'enabled : %s\n' "$_VIBEMAP_ENABLED"
  printf 'path    : %s\n' "$_VIBEMAP_PATH"
  if [[ -f "$_VIBEMAP_PATH" ]]; then
    local lines size_h oldest_epoch oldest_human
    lines=$(wc -l < "$_VIBEMAP_PATH" 2>/dev/null | tr -d ' ')
    size_h=$(stat -f '%z' "$_VIBEMAP_PATH" 2>/dev/null \
            || stat -c '%s' "$_VIBEMAP_PATH" 2>/dev/null \
            || echo 0)
    printf 'entries : %s\n' "${lines:-0}"
    printf 'size    : %s bytes\n' "$size_h"
    oldest_epoch=$(head -1 "$_VIBEMAP_PATH" 2>/dev/null | cut -f1)
    if [[ "$oldest_epoch" =~ ^[0-9]+$ ]]; then
      oldest_human=$(date -r "$oldest_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null \
                  || date -d "@$oldest_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null)
      printf 'oldest  : %s\n' "$oldest_human"
    fi
  else
    printf 'entries : 0 (no file)\n'
  fi
}

_vibemap_clear() {
  _vibemap_load_config
  if [[ -f "$_VIBEMAP_PATH" ]]; then
    rm -f "$_VIBEMAP_PATH" \
      && printf 'vibemap cleared: %s\n' "$_VIBEMAP_PATH" \
      || { printf 'vibemap: failed to remove %s\n' "$_VIBEMAP_PATH" >&2; return 1; }
  else
    printf 'vibemap: nothing to clear\n'
  fi
}

# Grid view — 8 three-hour bins × 7 weekdays. Past-bedtime hours rendered
# in dim red so the visual aligns with the cc-statusline bedtime color.
_vibemap_render_grid() {
  _vibemap_load_config
  if [[ ! -f "$_VIBEMAP_PATH" ]]; then
    printf 'vibemap: no data yet — set vibemap.enabled=true in config to start tracking\n'
    return 0
  fi

  local data; data=$(awk -f "$CLAUDII_HOME/lib/vibemap-grid.awk" "$_VIBEMAP_PATH")
  local max=0
  while IFS=$'\t' read -r f1 f2 f3; do
    if [[ "$f1" == "max" ]]; then max="$f2"; fi
  done <<< "$data"

  # Build cell lookup as flat scalars _c_<weekday>_<bin>=<count>.
  # No declare -A: bash 3.2 (macOS /bin/bash) treats "w,b" as the comma
  # operator → 0, so every assignment overwrites the same slot. printf -v
  # rejects non-identifier names — skip rows where the awk emitted
  # unexpected (non-numeric) keys instead of crashing the whole render.
  local _c_var
  while IFS=$'\t' read -r f1 f2 f3; do
    [[ "$f1" == "max" ]] && continue
    [[ "$f1" =~ ^[0-9]+$ && "$f2" =~ ^[0-9]+$ ]] || continue
    _c_var="_c_${f1}_${f2}"
    printf -v "$_c_var" '%s' "$f3"
  done <<< "$data"

  # Read bedtime to mark "past-bedtime" rows in red.
  local bedtime; bedtime=$(jq -r '.statusline.bedtime // "23:00"' \
    "${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json" 2>/dev/null)
  [[ -z "$bedtime" || "$bedtime" == "null" ]] && bedtime="23:00"
  local bt_h="${bedtime%%:*}"
  bt_h="${bt_h#0}"; bt_h="${bt_h:-0}"

  local total
  total=$(wc -l < "$_VIBEMAP_PATH" 2>/dev/null | tr -d ' ')

  printf '%svibemap%s · %s entries · %sbedtime %s%s\n\n' \
    "$CLAUDII_CLR_DIM" "$CLAUDII_CLR_RESET" "$total" "$CLAUDII_CLR_DIM" "$bedtime" "$CLAUDII_CLR_RESET"
  printf '         Mon  Tue  Wed  Thu  Fri  Sat  Sun\n'

  local bins=("00-03" "03-06" "06-09" "09-12" "12-15" "15-18" "18-21" "21-00")
  local b wd bin_start bin_end is_past_bedtime
  local week_order=(1 2 3 4 5 6 0)
  for b in 0 1 2 3 4 5 6 7; do
    bin_start=$(( b * 3 ))
    bin_end=$(( bin_start + 3 ))
    # A bin is "past bedtime" if any of its 3 hours falls in [bedtime,bedtime+8h)
    # — covers the worst-overdue window. We mark the bin if its start hour
    # is within 8 hours after bedtime (mod 24).
    is_past_bedtime=0
    local h
    for (( h = bin_start; h < bin_end; h++ )); do
      local diff=$(( (h - bt_h + 24) % 24 ))
      if (( diff < 6 )); then is_past_bedtime=1; break; fi
    done

    if (( is_past_bedtime )); then
      printf '%s%s%s   ' "$CLAUDII_CLR_RED" "${bins[$b]}" "$CLAUDII_CLR_RESET"
    else
      printf '%s%s%s   ' "$CLAUDII_CLR_DIM" "${bins[$b]}" "$CLAUDII_CLR_RESET"
    fi
    for wd in "${week_order[@]}"; do
      local _ck="_c_${wd}_${b}" c="${!_ck:-0}"
      local ch; ch=$(_vibemap_density_char "$c" "$max")
      if (( is_past_bedtime )) && [[ "$ch" != " " ]]; then
        printf '%s%s%s    ' "$CLAUDII_CLR_RED" "$ch" "$CLAUDII_CLR_RESET"
      else
        printf '%s    ' "$ch"
      fi
    done
    printf '\n'
  done
  printf '\n%s ░ ▒ ▓ █  density (normalized to max=%s) %s\n' "$CLAUDII_CLR_DIM" "$max" "$CLAUDII_CLR_RESET"
}

# Strip view — last N days × 24 hours. Each row = one calendar day.
_vibemap_render_strip() {
  local days="${1:-14}"
  if [[ ! "$days" =~ ^[0-9]+$ ]] || (( days < 1 || days > 90 )); then
    printf 'vibemap: --days must be 1..90 (got %s)\n' "$days" >&2
    return 2
  fi

  _vibemap_load_config
  if [[ ! -f "$_VIBEMAP_PATH" ]]; then
    printf 'vibemap: no data yet — set vibemap.enabled=true in config to start tracking\n'
    return 0
  fi

  local now; now=$(date +%s)
  local data
  data=$(awk -v now="$now" -v maxdays="$days" \
    -f "$CLAUDII_HOME/lib/vibemap-strip.awk" "$_VIBEMAP_PATH")

  local max=0
  # Same bash 3.2 workaround as the grid view — flat scalars _c_<day>_<hour>.
  local _c_var
  while IFS=$'\t' read -r f1 f2 f3; do
    if [[ "$f1" == "max" ]]; then max="$f2"; continue; fi
    [[ "$f1" =~ ^[0-9]+$ && "$f2" =~ ^[0-9]+$ ]] || continue
    _c_var="_c_${f1}_${f2}"
    printf -v "$_c_var" '%s' "$f3"
  done <<< "$data"

  local bedtime bt_h
  bedtime=$(jq -r '.statusline.bedtime // "23:00"' \
    "${XDG_CONFIG_HOME:-$HOME/.config}/claudii/config.json" 2>/dev/null)
  [[ -z "$bedtime" || "$bedtime" == "null" ]] && bedtime="23:00"
  bt_h="${bedtime%%:*}"; bt_h="${bt_h#0}"; bt_h="${bt_h:-0}"

  local total
  total=$(wc -l < "$_VIBEMAP_PATH" 2>/dev/null | tr -d ' ')

  printf '%svibemap%s · last %s days · %s entries · %sbedtime %s%s\n\n' \
    "$CLAUDII_CLR_DIM" "$CLAUDII_CLR_RESET" "$days" "$total" "$CLAUDII_CLR_DIM" "$bedtime" "$CLAUDII_CLR_RESET"
  printf '              00 03 06 09 12 15 18 21\n'

  local d label epoch_for_day h c ch row_today_marker
  for (( d = days - 1; d >= 0; d-- )); do
    epoch_for_day=$(( now - d * 86400 ))
    label=$(date -r "$epoch_for_day" '+%a %d %b' 2>/dev/null \
         || date -d "@$epoch_for_day" '+%a %d %b' 2>/dev/null \
         || printf '-%dd' "$d")
    row_today_marker=""
    if (( d == 0 )); then row_today_marker="${CLAUDII_CLR_DIM}*${CLAUDII_CLR_RESET}"; fi
    printf '%-12s %s ' "$label" "$row_today_marker"
    for (( h = 0; h < 24; h++ )); do
      local _ck="_c_${d}_${h}"; c="${!_ck:-0}"
      ch=$(_vibemap_density_char "$c" "$max")
      local diff=$(( (h - bt_h + 24) % 24 ))
      if (( diff < 6 )) && [[ "$ch" != " " ]]; then
        printf '%s%s%s' "$CLAUDII_CLR_RED" "$ch" "$CLAUDII_CLR_RESET"
      else
        printf '%s' "$ch"
      fi
    done
    printf '\n'
  done
  printf '\n%s ░ ▒ ▓ █  density (normalized to max=%s, red = past bedtime)%s\n' "$CLAUDII_CLR_DIM" "$max" "$CLAUDII_CLR_RESET"
}

_vibemap_usage() {
  cat <<'EOF'
Usage: claudii vibemap [<subcommand>] [options]

Heatmap of your prompt activity, opt-in via vibemap.enabled (default false).
Logs one line per cc-statusline render to ~/.cache/claudii/vibemap.tsv —
local file only, never transmitted, no prompt content stored.

Subcommands:
  (none) | grid       Default view: weekday × 3-hour bin grid
  strip [--days N]    Last N days × 24 hours strip (default 14, max 90)
  status              Show enabled/path/entries/oldest entry
  path                Print the vibemap file path
  clear               Delete the vibemap file (with no confirmation)
  -h, --help          This help

Enable:
  claudii config set vibemap.enabled true
EOF
}

_cmd_vibemap() {
  shift  # remove "vibemap" itself
  case "${1:-}" in
    ""|grid)              _vibemap_render_grid ;;
    strip|--recent)
      shift
      local days=14
      if [[ "${1:-}" == "--days" ]]; then days="${2:-14}"; fi
      _vibemap_render_strip "$days"
      ;;
    --days)               _vibemap_render_strip "${2:-14}" ;;
    clear)                _vibemap_clear ;;
    path)                 _vibemap_print_path ;;
    status)               _vibemap_show_status ;;
    -h|--help|help)       _vibemap_usage ;;
    *)
      printf 'claudii vibemap: unknown subcommand %s — try `claudii vibemap help`\n' "$1" >&2
      return 2
      ;;
  esac
}
