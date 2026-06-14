# lib/cmd/display.sh — display/visualization commands (trends, explain, version, changelog, 42)
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail

_cmd_trends() {
  _cfg_init
  # Flight Recorder — weekly/daily aggregates from persistent history
  # Monthly rotation: read history-*.tsv + legacy history.tsv
  local _hist_dir="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _collect_history_files "$_hist_dir"

  if [[ ${#_HIST_FILES[@]} -eq 0 ]]; then
    echo "No history data yet. Start a Claude session with CC-Statusline enabled."
    exit 0
  fi

  # Strategy: one awk pass (epoch_to_date + a weekday table) computes every date
  # boundary and the rolling 7-day window, replacing ~21 `date` subprocess spawns
  # plus the macOS/GNU branching. awk does all aggregation/formatting afterwards.
  now=$(date +%s)

  _date_init
  local _tz_offset="$_TZ_OFFSET" _ws_dow="$_WS_DOW"
  local _epoch_awk
  _epoch_awk=$(<"$CLAUDII_HOME/lib/epoch_to_date.awk")

  # All boundaries in ONE BEGIN-only awk (reads no input). Fixed tz_offset (from
  # now) — the same basis as the data-augment pass below, so boundary dates and
  # the bucketed data days compare consistently (d >= week_start). DST edges can
  # shift a boundary by <=1 day twice a year, matching the augment's approximation.
  local _bnd
  _bnd=$(awk -v now="$now" -v tz_offset="${_tz_offset:-0}" -v ws_dow="${_ws_dow:-1}" "
${_epoch_awk}
"'
    BEGIN {
      split("Sun Mon Tue Wed Thu Fri Sat", _wn, " ")
      today_day = int((now + tz_offset) / 86400)
      dow_u     = ((today_day + 3) % 7) + 1        # %u: Mon=1..Sun=7 (epoch day 0 = Thu)
      days_back = (dow_u - ws_dow + 7) % 7
      this_week_ts = now - days_back * 86400        # current week start (per ws_dow)
      last_mon_ts  = this_week_ts - 7 * 86400       # previous full week start
      last_sun_ts  = this_week_ts - 86400           # previous full week end
      thirty_ts    = now - 30 * 86400
      seven_ts     = now - 6 * 86400                # rolling 7-day window start
      wd = ""
      for (i = 0; i < 7; i++) {
        ts = seven_ts + i * 86400
        ld = int((ts + tz_offset) / 86400)
        wd = wd (wd == "" ? "" : ",") epoch_to_date(ts) ":" _wn[((ld + 4) % 7) + 1]
      }
      printf "%s\t%s\t%s\t%s\t%s\n", \
        epoch_to_date(now), epoch_to_date(seven_ts), epoch_to_date(last_mon_ts), \
        epoch_to_date(last_sun_ts), epoch_to_date(thirty_ts)
      printf "%s\n", wd
    }
  ' </dev/null)
  { IFS=$'\t' read -r today_str week_start_str last_monday_str last_sunday_str thirty_days_ago_str
    IFS= read -r _week_days; } <<< "$_bnd" || true

  # Show spinner for pretty output (not JSON/TSV — those are piped)
  _spinner_start "${_hist_dir/#$HOME/~}/history-*.tsv"

  # Step 1: Convert timestamps to YYYY-MM-DD + normalize model names.
  # Shared epoch_to_date from lib/epoch_to_date.awk (read above).
  _trends_augmented=$(LC_ALL=C awk -F'\t' -v tz_offset="${_tz_offset:-0}" "
${_epoch_awk}
$(<"$CLAUDII_HOME/lib/model_tier.awk")
"'
    { gsub(/\r/, "") }  # strip CR for cross-platform TSV (CRLF from synced files)
    NF < 6 { next }     # guard against short/malformed rows
    $1 == "timestamp" || $1 == "" || $6 == "" { next }
    {
      ts = $1 + 0; if (ts == 0) next
      day = epoch_to_date(ts)
      model = $2; cost = $3 + 0; sid = $6
      in_tok = ($7 == "" ? 0 : $7 + 0); out_tok = ($8 == "" ? 0 : $8 + 0)
      api_dur = ($9 == "" ? 0 : $9 + 0)
      model = tier_label(model)   # shared tier collapse (lib/model_tier.awk)
      print day "\t" model "\t" cost "\t" sid "\t" in_tok "\t" out_tok "\t" api_dur
    }
  ' "${_HIST_FILES[@]}")

  # Kill spinner before output
  _spinner_stop

  # Step 2: awk does dedup, aggregation, and ALL output formatting
  # (daily API totals are folded into trends.awk's main pass — field 7 = api_dur_ms)
  #
  # Both awk stages run under LC_ALL=C, unconditionally. Step 1 already parses the
  # history cost ($3) and step 2 re-parses it from the pipe; a comma locale
  # truncates "12.34"+0 to 12 at the radix (onetrueawk), corrupting pretty AND
  # json totals. trends.awk emits ASCII / UTF-8 bars via octal escapes and
  # length() is byte-based, so C is safe in the pretty branch too.
  echo "$_trends_augmented" | LC_ALL=C awk -F'\t' \
    -v today="$today_str" \
    -v week_start="$week_start_str" \
    -v last_mon="$last_monday_str" \
    -v last_sun="$last_sunday_str" \
    -v thirty="$thirty_days_ago_str" \
    -v week_days="$_week_days" \
    -v fmt="${_FORMAT:-}" \
    -v cyan="$CLAUDII_CLR_CYAN" \
    -v dim="$CLAUDII_CLR_DIM" \
    -v pink="$CLAUDII_CLR_ACCENT" \
    -v reset="$CLAUDII_CLR_RESET" \
    -f "$CLAUDII_HOME/lib/attribution.awk" \
    -f "$CLAUDII_HOME/lib/fmt.awk" \
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
    # Literal substring match (not regex — VERSION dots must not act as any-char)
    # and accept both "[0.19.0]" and the v-prefixed "[v0.19.0]" header form.
    _notes=$(awk -v ver="$VERSION" '
      /^## \[/ {
        if (found) { exit }
        if (index($0, "[" ver "]") > 0 || index($0, "[v" ver "]") > 0) { found=1; next }
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

_cmd_explain() {
  local_cache="${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"
  _cfg_init
  # 56-column rule built char-aware (_rep). `%.56s` truncates the multibyte ─ at
  # byte 56 under LC_ALL=C (mid-codepoint → garbled glyph in the CI locale).
  local _rule; _rule=$(_rep '─' 56)

  printf '\n'
  printf "  ${CLAUDII_CLR_CYAN}claudii explain${CLAUDII_CLR_RESET}\n"
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
  printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rule"
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
    [[ -f "$_sf" ]] || continue
    [[ "$_sf" == *.tmp.* ]] && continue
    sb_count=$((sb_count + 1))
  done 2>/dev/null
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Dashboard${CLAUDII_CLR_RESET}                                  Shell, above prompt\n"
  printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rule"
  printf '  Session data from cache (model, context, tokens, rate limits)\n'
  printf "  Example (overview account line):\n"
  printf "    5h:51%% ${CLAUDII_CLR_DIM}reset 158min │${CLAUDII_CLR_RESET} 7d:92%% ${CLAUDII_CLR_DIM}(+18%%) │${CLAUDII_CLR_RESET} ${CLAUDII_CLR_ACCENT}5.2M tok${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}today (2 sessions)${CLAUDII_CLR_RESET}\n"
  printf "  Example (session line):\n"
  printf "    ${CLAUDII_CLR_DIM}Opus${CLAUDII_CLR_RESET} ${CLAUDII_CLR_GREEN}████████${CLAUDII_CLR_RESET}${CLAUDII_CLR_DIM}░░ 76%%  5.2M tok  ${CLAUDII_CLR_RESET}${CLAUDII_CLR_GREEN}5h:28%%${CLAUDII_CLR_RESET}\n"
  printf '\n'
  printf '  Source:   CC-Statusline writes cache, Session Dashboard reads it\n'
  printf '  Sessions: %d cache file(s)\n' "$sb_count"
  printf '  Dedup:    only prints when data changes\n'
  printf '\n'

  # CC-Statusline
  settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]] && command -v jq >/dev/null 2>&1; then
    sl_cmd=$(jq -r '.statusLine.command // empty' "$settings_file" 2>/dev/null)
    if [[ -n "$sl_cmd" ]] && _cc_statusline_connected "$sl_cmd"; then
      sl_state="${CLAUDII_CLR_GREEN}active${CLAUDII_CLR_RESET}"
    else
      sl_state="${CLAUDII_CLR_DIM}not configured${CLAUDII_CLR_RESET}"
    fi
  else
    sl_state="${CLAUDII_CLR_DIM}~/.claude/settings.json not found${CLAUDII_CLR_RESET}"
  fi
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}CC-Statusline${CLAUDII_CLR_RESET}                             Inside Claude Code\n"
  printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rule"
  printf '  Info-dense status line rendered inside Claude Code CLI\n'
  printf '  Shows model, context bar, tokens, cache ratio, rate limits, cost (dim), lines\n'
  printf '\n'
  printf '  Status:   %b\n' "$sl_state"
  printf '  API:      Claude Code statusLine (stdin JSON)\n'
  printf '  Handler:  bin/claudii-cc-statusline (bash+jq)\n'
  printf '  Commands: claudii cc-statusline on/off\n'
  printf '\n'

  # Clock segment — delegated to insomnii(1).
  _bt_val=$(_cfgget statusline.bedtime)
  _ins_mode=$(_cfgget statusline.insomnii)
  [[ "$_ins_mode" != "off" && "$_ins_mode" != "on" ]] && _ins_mode="auto"
  if command -v cc-insomnii >/dev/null 2>&1; then
    _ins_path=$(command -v cc-insomnii)
    _ins_state="${CLAUDII_CLR_GREEN}detected${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}($_ins_path)${CLAUDII_CLR_RESET}"
  else
    _ins_state="${CLAUDII_CLR_DIM}not installed${CLAUDII_CLR_RESET}"
  fi
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Clock${CLAUDII_CLR_RESET}                                      CC-Statusline clock segment\n"
  printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rule"
  printf '  Bedtime nudge / shame / motivation rendering is delegated to the\n'
  printf '  standalone cc-insomnii(1) plugin. claudii pipes the upstream JSON to it\n'
  printf '  and forwards statusline.bedtime as CC_INSOMNII_BEDTIME.\n'
  printf '\n'
  printf '  Bedtime:   %s\n' "$_bt_val"
  printf '  Mode:      %s\n' "$_ins_mode"
  printf '  cc-insomnii:  %b\n' "$_ins_state"
  printf '\n'

  # Data flow
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Data Flow${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rule"
  printf "  Claude Code ${CLAUDII_CLR_DIM}─JSON→${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}CC-Statusline${CLAUDII_CLR_RESET} ${CLAUDII_CLR_DIM}─cache→${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}Dashboard${CLAUDII_CLR_RESET}\n"
  printf "  status.claude.com ${CLAUDII_CLR_DIM}─bg→${CLAUDII_CLR_RESET} ${CLAUDII_CLR_BOLD}ClaudeStatus${CLAUDII_CLR_RESET} (RPROMPT)\n"
  printf '\n'

  # Symbol & field reference
  printf "  ${CLAUDII_CLR_BOLD}${CLAUDII_CLR_CYAN}Symbols & Fields${CLAUDII_CLR_RESET}\n"
  printf "  ${CLAUDII_CLR_DIM}%s${CLAUDII_CLR_RESET}\n" "$_rule"
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
