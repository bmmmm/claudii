# lib/cmd/display.sh — display/visualization commands (trends, layers, version, changelog, 42)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_trends() {
  _cfg_init
  # Flight Recorder — weekly/daily aggregates from persistent history
  history_file="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/history.tsv"

  if [[ ! -f "$history_file" ]] || [[ ! -s "$history_file" ]]; then
    echo "No history data yet. Start a Claude session with CC-Statusline enabled."
    exit 0
  fi

  # Strategy: bash does date conversions (portable macOS/GNU), awk does
  # all aggregation and formatting (no associative arrays needed in bash).
  now=$(date +%s)

  # Timezone offset in seconds (maps UTC epoch → local day in epoch_to_date)
  local _tz_offset
  _tz_offset=$(date +%z | awk '{
    s = (substr($0,1,1) == "-") ? -1 : 1
    print s * (substr($0,2,2)*3600 + substr($0,4,2)*60)
  }')

  # Read configurable week_start (default: monday)
  local _ws_name _ws_dow
  _ws_name=$(_cfgget cost.week_start)
  _ws_name="${_ws_name:-monday}"
  case "$_ws_name" in
    monday)    _ws_dow=1 ;;
    tuesday)   _ws_dow=2 ;;
    wednesday) _ws_dow=3 ;;
    thursday)  _ws_dow=4 ;;
    friday)    _ws_dow=5 ;;
    saturday)  _ws_dow=6 ;;
    sunday)    _ws_dow=7 ;;
    *)         _ws_dow=1 ;;
  esac

  # Detect macOS vs GNU date
  if date -j -f '%s' "$now" '+%u' >/dev/null 2>&1; then
    _date_cmd="macos"
  else
    _date_cmd="gnu"
  fi

  # Precompute date boundaries (local time + configurable week_start)
  local _days_back
  if [[ "$_date_cmd" == "macos" ]]; then
    today_str=$(date -j -f '%s' "$now" '+%Y-%m-%d')
    today_dow=$(date -j -f '%s' "$now" '+%u')  # 1=Mon..7=Sun
    _days_back=$(( (today_dow - _ws_dow + 7) % 7 ))
    this_monday_ts=$(( now - _days_back * 86400 ))
    this_monday_str=$(date -j -f '%s' "$this_monday_ts" '+%Y-%m-%d')
    last_monday_ts=$(( this_monday_ts - 7 * 86400 ))
    last_monday_str=$(date -j -f '%s' "$last_monday_ts" '+%Y-%m-%d')
    last_sunday_ts=$(( this_monday_ts - 86400 ))
    last_sunday_str=$(date -j -f '%s' "$last_sunday_ts" '+%Y-%m-%d')
    thirty_days_ago_ts=$(( now - 30 * 86400 ))
    thirty_days_ago_str=$(date -j -f '%s' "$thirty_days_ago_ts" '+%Y-%m-%d')
  else
    today_str=$(date -d "@$now" '+%Y-%m-%d')
    today_dow=$(date -d "@$now" '+%u')
    _days_back=$(( (today_dow - _ws_dow + 7) % 7 ))
    this_monday_ts=$(( now - _days_back * 86400 ))
    this_monday_str=$(date -d "@$this_monday_ts" '+%Y-%m-%d')
    last_monday_ts=$(( this_monday_ts - 7 * 86400 ))
    last_monday_str=$(date -d "@$last_monday_ts" '+%Y-%m-%d')
    last_sunday_ts=$(( this_monday_ts - 86400 ))
    last_sunday_str=$(date -d "@$last_sunday_ts" '+%Y-%m-%d')
    thirty_days_ago_ts=$(( now - 30 * 86400 ))
    thirty_days_ago_str=$(date -d "@$thirty_days_ago_ts" '+%Y-%m-%d')
  fi

  # Build week_days string: "date:name,date:name,..." for week-start..today
  _week_days=""
  for (( d=0; d<7; d++ )); do
    day_ts=$(( this_monday_ts + d * 86400 ))
    if [[ "$_date_cmd" == "macos" ]]; then
      _wd=$(date -j -f '%s' "$day_ts" '+%Y-%m-%d')
      _wn=$(date -j -f '%s' "$day_ts" '+%a')
    else
      _wd=$(date -d "@$day_ts" '+%Y-%m-%d')
      _wn=$(date -d "@$day_ts" '+%a')
    fi
    [[ -n "$_week_days" ]] && _week_days+=","
    _week_days+="${_wd}:${_wn}"
    [[ "$_wd" == "$today_str" ]] && break
  done

  # Show spinner for pretty output (not JSON/TSV — those are piped)
  _trends_spinner_pid="" _claudii_spinner_label_file=""
  if ! _plain; then
    _claudii_spinner_label_file=$(mktemp "${TMPDIR:-/tmp}/claudii-spinner.XXXXXX")
    export CLAUDII_SPINNER_LABEL_FILE="$_claudii_spinner_label_file"
    printf '%s' "${history_file/#$HOME/\~}" > "$_claudii_spinner_label_file"
    _claudii_spinner &
    _trends_spinner_pid=$!
  fi

  # Step 1: Convert timestamps to YYYY-MM-DD + normalize model names.
  # Pure-awk epoch_to_date — avoids O(n) date(1) subprocesses.
  _trends_augmented=$(awk -F'\t' -v tz_offset="${_tz_offset:-0}" '
    function is_leap(y,    l) {
      l = 0
      if (y % 4 == 0) l = 1
      if (y % 100 == 0) l = 0
      if (y % 400 == 0) l = 1
      return l
    }
    function epoch_to_date(ts,    days, y, leap, m, mdays) {
      days = int((ts + tz_offset) / 86400); y = 1970
      for (;;) {
        leap = is_leap(y)
        if (days < 365 + leap) break
        days -= 365 + leap; y++
      }
      leap = is_leap(y)
      split("31 " (28+leap) " 31 30 31 30 31 31 30 31 30 31", mdays, " ")
      for (m = 1; m <= 12; m++) { if (days < mdays[m]) break; days -= mdays[m] }
      return sprintf("%04d-%02d-%02d", y, m, days + 1)
    }
    $1 == "timestamp" || $1 == "" || $6 == "" { next }
    {
      ts = $1 + 0; if (ts == 0) next
      day = epoch_to_date(ts)
      model = $2; cost = $3 + 0; sid = $6
      in_tok = ($7 == "" ? 0 : $7 + 0); out_tok = ($8 == "" ? 0 : $8 + 0)
      api_dur = ($9 == "" ? 0 : $9 + 0)
      if      (model ~ /[Oo]pus/)   model = "Opus"
      else if (model ~ /[Ss]onnet/) model = "Sonnet"
      else if (model ~ /[Hh]aiku/)  model = "Haiku"
      print day "\t" model "\t" cost "\t" sid "\t" in_tok "\t" out_tok "\t" api_dur
    }
  ' "$history_file")

  # Kill spinner before output
  if [[ -n "$_trends_spinner_pid" ]]; then
    kill "$_trends_spinner_pid" 2>/dev/null; wait "$_trends_spinner_pid" 2>/dev/null || true
    printf '\r\033[K' >&2
  fi
  if [[ -n "$_claudii_spinner_label_file" ]]; then
    rm -f "$_claudii_spinner_label_file"; unset CLAUDII_SPINNER_LABEL_FILE
  fi

  # Pre-compute daily API duration totals from augmented data (field 7 = api_dur_ms)
  _daily_api=$(echo "$_trends_augmented" | awk -F'\t' '
    NF >= 7 && $7 > 0 { daily[$1] += $7 }
    END { for (d in daily) print d "\t" daily[d] }
  ' | sort)

  # Step 2: awk does dedup, aggregation, and ALL output formatting
  echo "$_trends_augmented" | awk -F'\t' \
    -v today="$today_str" \
    -v this_mon="$this_monday_str" \
    -v last_mon="$last_monday_str" \
    -v last_sun="$last_sunday_str" \
    -v thirty="$thirty_days_ago_str" \
    -v week_days="$_week_days" \
    -v fmt="${_FORMAT:-}" \
    -v cyan="$CLAUDII_CLR_CYAN" \
    -v dim="$CLAUDII_CLR_DIM" \
    -v pink="$CLAUDII_CLR_ACCENT" \
    -v reset="$CLAUDII_CLR_RESET" \
    -v daily_api="$_daily_api" \
    -f "$CLAUDII_HOME/lib/trends.awk"
}

_cmd_version() {
  if [[ "$_FORMAT" == "json" ]]; then
    jq -n --arg v "$VERSION" '{"version": $v}'
  else
    echo "$VERSION"
  fi
}

_cmd_changelog() {
  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}v%s${CLAUDII_CLR_RESET}\n" "$VERSION"
  printf '\n'
  _changelog="$CLAUDII_HOME/CHANGELOG.md"
  if [[ -f "$_changelog" ]]; then
    _notes=$(awk -v ver="$VERSION" '
      /^## \[/ {
        if (found) { exit }
        if ($0 ~ ("\\[" ver "\\]")) { found=1; next }
      }
      found { print }
    ' "$_changelog")
    if [[ -n "$_notes" ]]; then
      while IFS= read -r _rline; do
        printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rline"
      done <<< "$_notes"
    else
      printf "  ${CLAUDII_CLR_DIM}No changelog entry for v%s${CLAUDII_CLR_RESET}\n" "$VERSION"
    fi
  else
    printf "  ${CLAUDII_CLR_DIM}CHANGELOG.md not found${CLAUDII_CLR_RESET}\n"
  fi
  printf '\n'
}

_cmd_layers() {
  local_cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _cfg_init

  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii layers${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_ACCENT}──────────────────────────────────────────────────────────${CLAUDII_CLR_RESET}\n"
  printf '\n'

  # ClaudeStatus
  cs_enabled=$(_cfgget statusline.enabled)
  cs_models=$(_cfgget statusline.models)
  cs_ttl=$(_cfgget status.cache_ttl)
  cs_cache="$local_cache/status-models"
  if [[ "$cs_enabled" == "true" ]]; then
    cs_state="${CLAUDII_CLR_GREEN}on${CLAUDII_CLR_RESET}"
  else
    cs_state="${CLAUDII_CLR_YELLOW}off${CLAUDII_CLR_RESET}"
  fi
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}ClaudeStatus${CLAUDII_CLR_RESET}                              Shell RPROMPT\n"
  printf "  ${CLAUDII_CLR_DIM}%.56s${CLAUDII_CLR_RESET}\n" "────────────────────────────────────────────────────────"
  printf '  Model health indicators from status.claude.com\n'
  printf "  Example:  [Opus ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} Sonnet ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} Haiku ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET}] 13m\n"
  printf '\n'
  printf '  Status:   %b\n' "$cs_state"
  printf '  Models:   %s\n' "$cs_models"
  printf '  TTL:      %ss\n' "$cs_ttl"
  if [[ -f "$cs_cache" ]]; then
    printf '  Cache:    %s\n' "$cs_cache"
  else
    printf "  Cache:    ${CLAUDII_CLR_DIM}(not yet created)${CLAUDII_CLR_RESET}\n"
  fi
  printf '  Commands: claudii on/off · claudii status\n'
  printf '\n'

  # SessionBar
  sb_count=0
  for _sf in "$local_cache"/session-*; do
    [[ -f "$_sf" ]] && sb_count=$((sb_count + 1))
  done 2>/dev/null
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Dashboard${CLAUDII_CLR_RESET}                                  Shell, above prompt\n"
  printf "  ${CLAUDII_CLR_DIM}%.56s${CLAUDII_CLR_RESET}\n" "────────────────────────────────────────────────────────"
  printf '  Session data from cache (model, context, cost, rate limits)\n'
  printf "  Example (global line):\n"
  printf "    5h:51%% ${CLAUDII_CLR_DIM}reset 158min │${CLAUDII_CLR_RESET} 7d:92%% ${CLAUDII_CLR_DIM}(+18%%) │${CLAUDII_CLR_RESET} ${CLAUDII_CLR_CYAN}\$24.73${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}today (2 sessions)${CLAUDII_CLR_RESET}\n"
  printf "  Example (session line):\n"
  printf "    ${CLAUDII_CLR_BOLD}Opus${CLAUDII_CLR_RESET} ${CLAUDII_CLR_GREEN}████████${CLAUDII_CLR_RESET}${CLAUDII_CLR_DIM}░░${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}76%%${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}│${CLAUDII_CLR_RESET} ${CLAUDII_CLR_CYAN}\$0.07${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}│ ⚡38%%${CLAUDII_CLR_RESET}\n"
  printf '\n'
  printf '  Source:   CC-Statusline writes cache, Session Dashboard reads it\n'
  printf '  Sessions: %d cache file(s)\n' "$sb_count"
  printf '  Dedup:    only prints when data changes\n'
  printf '\n'

  # CC-Statusline
  settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]] && command -v jq >/dev/null 2>&1; then
    sl_cmd=$(jq -r '.statusLine // empty' "$settings_file" 2>/dev/null)
    if [[ -n "$sl_cmd" && "$sl_cmd" == *claudii* ]]; then
      sl_state="${CLAUDII_CLR_GREEN}aktiv${CLAUDII_CLR_RESET}"
    else
      sl_state="${CLAUDII_CLR_DIM}nicht konfiguriert${CLAUDII_CLR_RESET}"
    fi
  else
    sl_state="${CLAUDII_CLR_DIM}~/.claude/settings.json nicht gefunden${CLAUDII_CLR_RESET}"
  fi
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}CC-Statusline${CLAUDII_CLR_RESET}                             Inside Claude Code\n"
  printf "  ${CLAUDII_CLR_DIM}%.56s${CLAUDII_CLR_RESET}\n" "────────────────────────────────────────────────────────"
  printf '  Info-dense status line rendered inside Claude Code CLI\n'
  printf '  Shows model, context bar, cost, tokens, rate limits, lines, duration\n'
  printf '\n'
  printf '  Status:   %b\n' "$sl_state"
  printf '  API:      Claude Code statusLine (stdin JSON)\n'
  printf '  Handler:  bin/claudii-sessionline (bash+jq)\n'
  printf '  Commands: claudii cc-statusline on/off\n'
  printf '\n'

  # Data flow
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Data Flow${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_DIM}%.56s${CLAUDII_CLR_RESET}\n" "────────────────────────────────────────────────────────"
  printf "  Claude Code ${CLAUDII_CLR_DIM}─JSON→${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}CC-Statusline${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}─cache→${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}Dashboard${CLAUDII_CLR_RESET}\n"
  printf "  status.claude.com ${CLAUDII_CLR_DIM}─bg→${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}ClaudeStatus${CLAUDII_CLR_RESET} (RPROMPT)\n"
  printf '\n'

  # Symbol & field reference
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Symbols & Fields${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_DIM}%.56s${CLAUDII_CLR_RESET}\n" "────────────────────────────────────────────────────────"
  printf '\n'
  printf '  Session Dashboard\n'
  printf '  %-4s %-20s %s\n' "●"   "active"           "session or service is active"
  printf '  %-4s %-20s %s\n' "○"   "inactive"         "session ended or service is off"
  printf '  %-4s %-20s %s\n' "█░"  "context bar"      "context window fill (8 blocks = 100%)"
  printf '  %-4s %-20s %s\n' "⚡"  "cache ratio"      "% of input served from prompt cache"
  printf '  %-4s %-20s %s\n' "│"   "separator"        "field separator (dim)"
  printf '\n'
  printf '  CC-Statusline\n'
  printf '  %-4s %-20s %s\n' "█░"  "context bar"      "context window fill (10 blocks = 100%)"
  printf '  %-4s %-20s %s\n' '$'   "cost"             "session cost USD"
  printf '  %-4s %-20s %s\n' "5h:" "5h rate limit"    "token budget used %"
  printf '  %-4s %-20s %s\n' "7d:" "7d rate limit"    "token budget used %"
  printf '  %-4s %-20s %s\n' "↺"   "reset"            "minutes until rate limit refreshes"
  printf '  %-4s %-20s %s\n' "↑"   "input tokens"     "tokens sent to model this session"
  printf '  %-4s %-20s %s\n' "↓"   "output tokens"    "tokens received from model"
  printf '  %-4s %-20s %s\n' "⚡"  "cache ratio"      "% of input served from prompt cache"
  printf '  %-4s %-20s %s\n' "+/-" "lines changed"    "code added / removed"
  printf '  %-4s %-20s %s\n' ""    "duration"         "total session time"
  printf '\n'
  printf '  ClaudeStatus (RPROMPT)\n'
  printf '  %-4s %-20s %s\n' "✓"  "ok"               "model operational"
  printf '  %-4s %-20s %s\n' "⚠"  "degraded"         "partial outage"
  printf '  %-4s %-20s %s\n' "✗"  "down"             "major outage"
  printf '  %-4s %-20s %s\n' "⟳"  "refreshing"       "background check running"
  printf '  %-4s %-20s %s\n' "?"   "unreachable"      "status.claude.com not reachable"
  printf '\n'
}

_cmd_42() {
  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}✦  The answer is 42.${CLAUDII_CLR_RESET}\n"
  printf '\n'
  printf '  It was also the number of times Opus was down\n'
  printf '  while this tool was being built.\n'
  printf '\n'
  printf "  ${CLAUDII_CLR_ACCENT}(We monitor all three now. You're welcome.)${CLAUDII_CLR_RESET}\n"
  printf '\n'
}
