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
  # Integer math: ratio as a percent (0-100).
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
  local cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  rm -f "$cache_dir/vibemap-mini.cache" 2>/dev/null
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
# Today's weekday gets a ▶ prefix in accent (pink) on the header — mirroring
# the ▶ today-row idiom from the strip view. Data cells keep their normal
# coloring (bedtime-red or default) so density stays readable.
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

  # Determine today's weekday: date +%w gives 0=Sun..6=Sat.
  # week_order maps column index (0=Mon..6=Sun) to weekday number.
  # We find which column index corresponds to today.
  local _dow; _dow=$(date '+%w' 2>/dev/null); _dow="${_dow:-0}"
  local week_order=(1 2 3 4 5 6 0)
  local today_col=-1 _ci
  for _ci in 0 1 2 3 4 5 6; do
    if (( week_order[_ci] == _dow )); then today_col=$_ci; break; fi
  done

  # Header: 5-col slots aligned with 5-col data cells.
  # Bin label width is "00-03" (5) + 3 trailing spaces = 8 chars leading,
  # so the header also leads with 8 spaces. Each day slot is 5 visible cols:
  # non-today = "Mon  ", today = "▶Wed " — both put a meaningful char at the
  # slot's first column, directly above the data char that lands there.
  local _day_names=("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")
  printf '        '
  for _ci in 0 1 2 3 4 5 6; do
    if (( _ci == today_col )); then
      printf '%s▶%s%s ' "$CLAUDII_CLR_ACCENT" "${_day_names[$_ci]}" "$CLAUDII_CLR_RESET"
    else
      printf '%s  ' "${_day_names[$_ci]}"
    fi
  done
  printf '\n'

  local bins=("00-03" "03-06" "06-09" "09-12" "12-15" "15-18" "18-21" "21-00")
  local b wd bin_start bin_end is_past_bedtime
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
    for _ci in 0 1 2 3 4 5 6; do
      wd="${week_order[$_ci]}"
      local _ck="_c_${wd}_${b}"
      local c="${!_ck:-0}"
      local ch; ch=$(_vibemap_density_char "$c" "$max")
      if (( is_past_bedtime )) && [[ "$ch" != " " ]]; then
        printf '%s%s%s    ' "$CLAUDII_CLR_RED" "$ch" "$CLAUDII_CLR_RESET"
      else
        printf '%s    ' "$ch"
      fi
    done
    printf '\n'
  done
  local _today_marker="${CLAUDII_CLR_ACCENT}▶${CLAUDII_CLR_DIM}"
  printf '\n%s ░ ▒ ▓ █  density (normalized to max=%s, %s = today) %s\n' \
    "$CLAUDII_CLR_DIM" "$max" "$_today_marker" "$CLAUDII_CLR_RESET"
}

# Strip view — last N days × 24 hours. Each row = one calendar day.
#
# Today-row special treatment:
#   - Label rendered in CLAUDII_CLR_ACCENT (pink) with ▶ marker instead of *.
#   - Future hours (strictly past current local hour) render as a space.
#   - Current hour replaced by the cursor character │ in accent color.
#     Alignment choice: the cursor occupies exactly 1 column (replacing the
#     density char for the current hour), so the total row width stays 24
#     columns — matching the header `00 03 06 09 12 15 18 21`.
_vibemap_render_strip() {
  local days="${1:-30}"
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
  local tz_off; tz_off=$(_tz_offset_secs)   # bucket by local calendar day
  # Current local hour for today-row cursor placement.
  local cur_hour; cur_hour=$(date '+%H' 2>/dev/null); cur_hour="${cur_hour#0}"; cur_hour="${cur_hour:-0}"
  local data
  data=$(awk -v now="$now" -v maxdays="$days" -v tz_offset="${tz_off:-0}" \
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

  local d label epoch_for_day h c ch
  for (( d = days - 1; d >= 0; d-- )); do
    epoch_for_day=$(( now - d * 86400 ))
    label=$(date -r "$epoch_for_day" '+%a %d %b' 2>/dev/null \
         || date -d "@$epoch_for_day" '+%a %d %b' 2>/dev/null \
         || printf '-%dd' "$d")

    if (( d == 0 )); then
      # Today-row: accent label + ▶ marker, cursor at current hour.
      printf '%s%-12s ▶%s ' "$CLAUDII_CLR_ACCENT" "$label" "$CLAUDII_CLR_RESET"
      for (( h = 0; h < 24; h++ )); do
        if (( h == cur_hour )); then
          # Current hour: show accent cursor │ instead of density char.
          printf '%s│%s' "$CLAUDII_CLR_ACCENT" "$CLAUDII_CLR_RESET"
        elif (( h > cur_hour )); then
          # Future hours: blank space — not yet elapsed.
          printf ' '
        else
          # Past hours: normal density char (bedtime coloring applies).
          local _ck="_c_${d}_${h}"; c="${!_ck:-0}"
          ch=$(_vibemap_density_char "$c" "$max")
          local diff=$(( (h - bt_h + 24) % 24 ))
          if (( diff < 6 )) && [[ "$ch" != " " ]]; then
            printf '%s%s%s' "$CLAUDII_CLR_RED" "$ch" "$CLAUDII_CLR_RESET"
          else
            printf '%s' "$ch"
          fi
        fi
      done
    else
      # Past days: unchanged rendering.
      printf '%-12s   ' "$label"
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
    fi
    printf '\n'
  done
  printf '\n%s ░ ▒ ▓ █  density (normalized to max=%s, red = past bedtime)%s\n' "$CLAUDII_CLR_DIM" "$max" "$CLAUDII_CLR_RESET"
}

# Mini-vibemap strip for the bare `claudii` overview.
# Renders a one-line 43-char strip (rightmost = today, leftmost = oldest day).
# Each position is the maximum density char for that calendar day.
# Does NOT produce output when vibemap.enabled=false or no data exists —
# callers check $? or pass the return via _vibemap_overview_segment().
#
# Writes directly to stdout; caller wraps with the section header.
_vibemap_mini_strip() {
  _vibemap_load_config
  [[ "$_VIBEMAP_ENABLED" != "true" ]] && return 1
  [[ ! -f "$_VIBEMAP_PATH" ]] && return 1

  # TTL cache — overview renders frequently, mini-strip output changes rarely
  # (density chars are normalized to max, so single new entries don't shift
  # them). 60s feels live without paying the ~60ms awk+aggregate cost each
  # time. Cache lives next to the vibemap file under the cache dir.
  local cache_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  local cache_file="$cache_dir/vibemap-mini.cache"
  # Compute `now` unconditionally — a cold cache (file absent) used to leave the
  # `local mt now_s` unassigned, and `local now="$now_s"` then tripped `set -u` on
  # bash 5.x (Linux/CI) → the mini-strip crashed and the caller's 2>/dev/null routed
  # to the disabled placeholder. (macOS /bin/bash 3.2 treats `local now_s` as set-empty,
  # so it was masked there.) Compute once, use for both the TTL check and the render.
  local now; now=$(date +%s)
  if [[ -f "$cache_file" ]]; then
    local mt; mt=$(_mtime "$cache_file")
    if (( now - mt < 60 )); then
      cat "$cache_file"
      return 0
    fi
  fi
  local tz_off; tz_off=$(_tz_offset_secs)   # bucket by local calendar day
  # Width matches the "last 43d · …" caption below the strip in the overview —
  # no point keeping the bar artificially narrow when the caption is wider.
  local minidays=43
  local data
  data=$(awk -v now="$now" -v maxdays="$minidays" -v tz_offset="${tz_off:-0}" \
    -f "$CLAUDII_HOME/lib/vibemap-strip.awk" "$_VIBEMAP_PATH")

  local max=0 has_data=0
  local _c_var
  while IFS=$'\t' read -r f1 f2 f3; do
    if [[ "$f1" == "max" ]]; then max="$f2"; continue; fi
    [[ "$f1" =~ ^[0-9]+$ && "$f2" =~ ^[0-9]+$ ]] || continue
    _c_var="_c_${f1}_${f2}"
    printf -v "$_c_var" '%s' "$f3"
    has_data=1
  done <<< "$data"

  (( has_data == 0 )) && return 1

  # Build the strip: for each day d (minidays-1 = oldest, 0 = today), pick
  # the maximum density char seen across all 24 hours of that day.
  # Today (d=0, rightmost) is rendered in accent (pink) — mirroring the ▶
  # today-row idiom from the strip view. The logical length stays minidays;
  # ANSI escapes are invisible to terminal width counting.
  local strip=""
  local d h best_count best_ch c
  for (( d = minidays - 1; d >= 0; d-- )); do
    best_count=0
    for (( h = 0; h < 24; h++ )); do
      local _ck="_c_${d}_${h}"; c="${!_ck:-0}"
      (( c > best_count )) && best_count=$c
    done
    best_ch=$(_vibemap_density_char "$best_count" "$max")
    if (( d == 0 )); then
      # Today: wrap density char in accent color so it stands out visually.
      strip+="${CLAUDII_CLR_ACCENT}${best_ch}${CLAUDII_CLR_RESET}"
    else
      strip+="$best_ch"
    fi
  done

  mkdir -p "$cache_dir" 2>/dev/null
  printf '%s\n' "$strip" > "$cache_file" 2>/dev/null
  printf '%s\n' "$strip"
  return 0
}

_vibemap_usage() {
  cat <<'EOF'
Usage: claudii vibemap [<subcommand>] [options]

Heatmap of your prompt activity, opt-in via vibemap.enabled (default false).
Logs one line per cc-statusline render to ~/.cache/claudii/vibemap.tsv —
local file only, never transmitted, no prompt content stored.

Subcommands:
  (none)              Default view: last 30 days × 24 hours
  strip [--days N]    Same strip with a custom window (default 30, max 90)
  grid                Weekday × 3-hour bin grid
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
    "")                   _vibemap_render_strip 30 ;;
    grid)                 _vibemap_render_grid ;;
    strip|--recent)
      shift
      local days=30
      if [[ "${1:-}" == "--days" ]]; then days="${2:-30}"; fi
      _vibemap_render_strip "$days"
      ;;
    --days)               _vibemap_render_strip "${2:-30}" ;;
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
