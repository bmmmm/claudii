# lib/helpers.sh — shared helper functions sourced by bin/claudii
#
# Pure bash (3.2 compatible). No top-level side effects — all logic in functions.
# Callers must source visual.sh, spinner.sh first (for CLAUDII_CLR_*/CLAUDII_SYM_*
# and _claudii_spinner) and must set CLAUDII_HOME.

# Shared relative-time formatters (_fmt_rel / _fmt_brief)
# shellcheck source=lib/timefmt.sh
source "$CLAUDII_HOME/lib/timefmt.sh"

# Returns 0 (true) when output should be plain (no ANSI colors):
# either piped without an explicit format flag, or an explicit --json/--tsv flag is set.
_plain() { [[ "${_TTY:-0}" -eq 0 ]] || [[ -n "${_FORMAT:-}" ]]; }

# Validate config key — alphanumeric, dots, hyphens, underscores only (prevents jq injection)
_validate_key() { [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid key: $1 (allowed: alphanumeric, dots, hyphens, underscores)" >&2; return 1; }; }

# File mtime (epoch seconds) — single fork: BSD `stat -f%m`, GNU `stat -c%Y` fallback,
# 0 if both fail. Canonical home for the idiom that was inlined across lib/cmd/*.
# (The zsh hot paths in statusline.zsh/functions.zsh prefer the zstat builtin instead.)
_mtime() { stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0; }

# Atomic jq update — writes to tmp then renames (prevents partial reads on jq error).
# Usage: _jq_update <file> <jq-filter> [jq-args...]
# Example: _jq_update "$CONFIG" '.debug.level = "info"'
# Example: _jq_update "$CONFIG" --argjson v 900 '.status.cache_ttl = $v'
_jq_update() {
  local _file="$1"; shift
  local _tmp; _tmp=$(mktemp) || return 1
  if jq "$@" "$_file" > "$_tmp"; then
    mv -f "$_tmp" "$_file"
    # Config may have changed — drop the _cfgget per-process memo so a
    # write-then-read in the same command never serves a stale value.
    _cfgget_memo_clear
  else
    rm -f "$_tmp"
    return 1
  fi
}

# Config helper — sets CONFIG, CONFIG_DIR, DEFAULTS in calling scope
_cfg_init() {
  CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claudii"
  CONFIG="$CONFIG_DIR/config.json"
  DEFAULTS="$CLAUDII_HOME/config/defaults.json"
  [[ -d "$CONFIG_DIR" ]] || mkdir -p "$CONFIG_DIR"
  [[ -f "$CONFIG" ]] || cp "$DEFAULTS" "$CONFIG"
  _claudii_theme_load
}

# Config value lookup — user config first, falls back to defaults.json
# Builds a properly quoted jq path so hyphenated keys (e.g. session-dashboard.enabled)
# are accessed as ."session-dashboard"."enabled" rather than the invalid .session-dashboard.enabled
# Type-check instead of `// empty`: jq treats boolean false as falsy, so
# `false // empty` would swallow an explicit user `false` and fall through to
# the default (claudestatus off reported "on"). Mirrors _cmd_config get.
#
# Perf: one jq fork per unique key (config + slurped defaults in a single
# invocation, was two forks), and a per-process memo so repeated keys
# (statusline.rate_display is read by se/si/overview alike) fork nothing.
# Memo uses printf -v dynamic vars + a "__set" marker (bash 3.2 has no
# associative arrays and no ${!var+x}); _jq_update clears it on config writes.
_CFGMEMO_VARS=""
_cfgget_memo_clear() {
  local _v
  for _v in $_CFGMEMO_VARS; do unset "$_v"; done
  _CFGMEMO_VARS=""
}
_cfgget() {
  local key="$1" val _jp="" _seg
  _validate_key "$key" || return 1
  local _ck="_CFGMEMO_${key//[^a-zA-Z0-9_]/_}"
  local _cks="${_ck}__set"
  if [[ "${!_cks:-}" == "1" ]]; then
    printf '%s\n' "${!_ck}"
    return 0
  fi
  # Split on '.' and quote each segment: "a.b-c.d" → ."a"."b-c"."d"
  local _IFS_OLD="$IFS"
  IFS='.' read -ra _cfgget_segs <<< "$key"
  IFS="$_IFS_OLD"
  for _seg in "${_cfgget_segs[@]}"; do
    _jp+='."'"$_seg"'"'
  done
  # CONFIG is guaranteed by _cfg_init; if a caller skipped init, query the
  # defaults file twice rather than erroring on a missing input.
  local _cfg_in="$CONFIG"
  [[ -r "$_cfg_in" ]] || _cfg_in="$DEFAULTS"
  val=$(jq -r --slurpfile _d "$DEFAULTS" \
    "if (${_jp} | type) != \"null\" then (${_jp} | tostring) elif (\$_d[0]${_jp} | type) != \"null\" then (\$_d[0]${_jp} | tostring) else empty end" \
    "$_cfg_in" 2>/dev/null)
  printf -v "$_ck" '%s' "$val"
  printf -v "$_cks" '%s' "1"
  _CFGMEMO_VARS+=" $_ck $_cks"
  echo "$val"
}

# Collect history TSV files into _HIST_FILES (history.tsv + monthly history-*.tsv).
# Order matters: the per-session cost-delta math in trends.awk and
# _cmd_cost_from_history assumes rows arrive in chronological order per session.
# That holds because cc-statusline appends in real time (in-file order) and the
# monthly history-*.tsv glob is lexical == chronological (legacy history.tsv,
# pre-rotation, sorts first). A future change to how these files are merged or
# collected must preserve that ordering or add an explicit sort.
_HIST_FILES=()
_collect_history_files() {
  local _dir="$1"
  _HIST_FILES=()
  [[ -f "$_dir/history.tsv" && -s "$_dir/history.tsv" ]] && _HIST_FILES+=("$_dir/history.tsv")
  local _f
  for _f in "$_dir"/history-*.tsv; do
    [[ -f "$_f" && -s "$_f" ]] && _HIST_FILES+=("$_f")
  done
  return 0
}

# Epoch seconds of local calendar midnight (today 00:00:00), echoed to stdout.
# BSD `date -j -f '%Y-%m-%d'` without a time component keeps the current
# time-of-day (cutoff would equal `now`), so 00:00:00 is passed explicitly;
# GNU date fallback for Linux. Echoes 0 if both fail.
_midnight_epoch() {
  date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') 00:00:00" '+%s' 2>/dev/null \
    || date -d "$(date '+%Y-%m-%d')" '+%s' 2>/dev/null \
    || echo 0
}

# Rate-display mode init — sets _RATE_DISP ("used"|"remaining") and _rate_mark
# ("" | "↓") from config. One _cfgget, shared by se/si/overview.
_rate_disp_init() {
  _RATE_DISP=$(_cfgget statusline.rate_display 2>/dev/null)
  [[ "$_RATE_DISP" != "remaining" ]] && _RATE_DISP="used"
  _rate_mark=""
  [[ "$_RATE_DISP" == "remaining" ]] && _rate_mark="↓"
  return 0
}

# Collect session cache files into _SESSION_FILES, dropping atomic-write
# artifacts (session-*.tmp.PID left behind by crashed writers). gc keeps its
# own glob — it needs the .tmp files for the orphan sweep.
_SESSION_FILES=()
_session_files() {
  local _dir="${1:-${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}}" _f
  _SESSION_FILES=()
  shopt -s nullglob
  for _f in "$_dir"/session-*; do
    [[ -f "$_f" ]] || continue
    [[ "$_f" == *.tmp.* ]] && continue
    _SESSION_FILES+=("$_f")
  done
  shopt -u nullglob
  return 0
}

# Local UTC offset in seconds (signed), parsed from `date +%z` ("+HHMM"/"-HHMM").
# Echoes nothing if date +%z yields no output; callers coerce empty → 0.
_tz_offset_secs() {
  date +%z 2>/dev/null | awk '{
    s = (substr($0,1,1) == "-") ? -1 : 1
    print s * (substr($0,2,2)*3600 + substr($0,4,2)*60)
  }'
}

# Date init — sets _DATE_CMD ("macos"|"gnu"), _TZ_OFFSET (seconds), _WS_DOW (1=Mon..7=Sun).
_DATE_CMD="" _TZ_OFFSET="" _WS_DOW=""
_date_init() {
  if date -j -f '%s' "$(date +%s)" '+%Y-%m-%d' >/dev/null 2>&1; then _DATE_CMD="macos"; else _DATE_CMD="gnu"; fi

  _TZ_OFFSET=$(_tz_offset_secs)

  # Read configurable week_start (default: monday).
  local _ws_name
  _ws_name=$(_cfgget cost.week_start)
  case "${_ws_name:-monday}" in
    monday)    _WS_DOW=1 ;; tuesday)   _WS_DOW=2 ;;
    wednesday) _WS_DOW=3 ;; thursday)  _WS_DOW=4 ;;
    friday)    _WS_DOW=5 ;; saturday)  _WS_DOW=6 ;;
    sunday)    _WS_DOW=7 ;; *)         _WS_DOW=1 ;;
  esac
}

# Spinner — wraps _claudii_spinner BG job with label-file management.
# Callers can update the live label by writing to $CLAUDII_SPINNER_LABEL_FILE.
_SPINNER_PID=""
_spinner_start() {
  local _label="${1:-}"
  _SPINNER_PID=""
  _plain && return
  local _lf
  _lf=$(mktemp "${TMPDIR:-/tmp}/claudii-spinner.XXXXXX") || return
  chmod 0600 "$_lf"
  export CLAUDII_SPINNER_LABEL_FILE="$_lf"
  [[ -n "$_label" ]] && printf '%s' "$_label" > "$_lf"
  if [[ -z "${CLAUDII_SPINNER_MODE:-}" ]]; then
    local _m; _m=$(_cfgget ui.spinner 2>/dev/null)
    [[ -z "$_m" || "$_m" == "null" ]] && _m="random"
    export CLAUDII_SPINNER_MODE="$_m"
  fi
  _claudii_spinner &
  _SPINNER_PID=$!
}

_spinner_stop() {
  if [[ -n "${_SPINNER_PID:-}" ]]; then
    kill "$_SPINNER_PID" 2>/dev/null
    wait "$_SPINNER_PID" 2>/dev/null || true
    printf '\r\033[K' >&2
    _SPINNER_PID=""
  fi
  if [[ -n "${CLAUDII_SPINNER_LABEL_FILE:-}" ]]; then
    rm -f "$CLAUDII_SPINNER_LABEL_FILE"
    unset CLAUDII_SPINNER_LABEL_FILE
  fi
}

# Live-agents map from `claude agents --json` — populated once per command run.
# Parallel arrays (bash 3.2 compatible — no declare -A).
# Authoritative source of PID liveness, replacing the kill -0 + 24h-recycling guard.
_LIVE_PIDS=()
_LIVE_PIDS_KIND=()
_LIVE_PIDS_STATUS=()
_LIVE_PIDS_INITED=0
# Returns 0 unconditionally — best-effort initialization, callers run under
# `set -euo pipefail` so we must never leak a non-zero exit (claude missing,
# garbage JSON, jq missing, etc. → silently keep arrays empty for fallback).
_live_pids_init() {
  (( _LIVE_PIDS_INITED )) && return 0
  _LIVE_PIDS_INITED=1
  command -v claude >/dev/null 2>&1 || return 0
  local _json _pid _kind _status _i=0
  _json=$(claude agents --json 2>/dev/null) || return 0
  [[ -z "$_json" || "$_json" == "[]" ]] && return 0
  while IFS=$'\t' read -r _pid _kind _status; do
    [[ -z "$_pid" ]] && continue
    _LIVE_PIDS[$_i]="$_pid"
    _LIVE_PIDS_KIND[$_i]="$_kind"
    _LIVE_PIDS_STATUS[$_i]="$_status"
    (( ++_i ))
  done < <(jq -r '.[] | [.pid, (.kind // ""), (.status // "")] | @tsv' <<<"$_json" 2>/dev/null)
  return 0
}

# Returns 0 iff $1 appears in _LIVE_PIDS (no fallback to kill -0 here — caller decides).
_pid_is_live() {
  local _p="$1" _i
  for (( _i=0; _i<${#_LIVE_PIDS[@]}; _i++ )); do
    [[ "${_LIVE_PIDS[$_i]}" == "$_p" ]] && return 0
  done
  return 1
}

# Looks up the `kind` for a known-live pid; echoes empty string if not found.
# Always returns 0 — caller captures via command substitution under `set -e`,
# so a non-zero exit (empty _LIVE_PIDS, no match) would abort the script.
_pid_kind() {
  local _p="$1" _i
  for (( _i=0; _i<${#_LIVE_PIDS[@]}; _i++ )); do
    if [[ "${_LIVE_PIDS[$_i]}" == "$_p" ]]; then
      printf '%s' "${_LIVE_PIDS_KIND[$_i]}"
      return 0
    fi
  done
  return 0
}

# Session JSONL map — build once, O(1) lookup per session.
# Uses parallel arrays (bash 3.2 compatible — no declare -A).
_SID_MAP_KEYS=()
_SID_MAP_VALS=()
_session_build_map() {
  _SID_MAP_KEYS=()
  _SID_MAP_VALS=()
  local _jsonl _sid _i=0
  for _jsonl in "$HOME/.claude/projects"/*/*.jsonl; do
    [[ -f "$_jsonl" ]] || continue
    _sid="${_jsonl##*/}"
    _sid="${_sid%.jsonl}"
    _SID_MAP_KEYS[$_i]="$_sid"
    _SID_MAP_VALS[$_i]="$_jsonl"
    (( ++_i ))
  done
}

# Resolve JSONL path for a session_id (uses map if built, falls back to scan).
_session_jsonl() {
  local sid="$1" _j
  [[ -z "$sid" ]] && return
  # Map lookup
  for (( _j=0; _j<${#_SID_MAP_KEYS[@]}; _j++ )); do
    if [[ "${_SID_MAP_KEYS[$_j]}" == "$sid" ]]; then
      echo "${_SID_MAP_VALS[$_j]}"
      return
    fi
  done
  # Fallback: direct scan
  for _d in "$HOME/.claude/projects"/*/; do
    [[ -f "${_d}${sid}.jsonl" ]] && echo "${_d}${sid}.jsonl" && return
  done
}

# Single-pass JSONL resolver: extracts name, fingerprint, last_message, cwd in one
# awk. Output: 4 lines (name\nfingerprint\nlast_message\ncwd), any may be empty.
# cwd is the raw project path (first "cwd" seen); the caller shortens it.
_session_resolve() {
  local sid="$1" jsonl
  jsonl=$(_session_jsonl "$sid")
  [[ -z "$jsonl" ]] && { printf '\n\n\n\n'; return; }
  awk '
    # Session name: last "Session renamed to:" match
    match($0, /"Session renamed to: [^"\\]*"/) {
      name = substr($0, RSTART+21, RLENGTH-22)
      # Strip ANSI escapes
      gsub(/\033\[[0-9;]*m/, "", name)
      gsub(/\\033\[[0-9;]*m/, "", name)
      gsub(/\\e\[[0-9;]*m/, "", name)
    }
    # First cwd seen → project path (folds in the old _session_project_path
    # grep|head|grep|sed pipe; same "first cwd" semantics). `"cwd":"` is 7 chars.
    cwd == "" && match($0, /"cwd":"[^"]*"/) { cwd = substr($0, RSTART+7, RLENGTH-8) }
    # Fingerprint: collect file_path occurrences
    {
      pos = 0
      s = $0
      while (match(s, /"file_path":"[^"]*"/)) {
        fp = substr(s, RSTART+13, RLENGTH-14)
        # basename
        n = split(fp, parts, "/")
        bn = parts[n]
        files[bn]++
        s = substr(s, RSTART + RLENGTH)
      }
    }
    # Last user message
    /"role":"user"/ { last_user = $0 }
    END {
      # Name (max 60 chars)
      if (length(name) > 60) name = substr(name, 1, 60)
      print name

      # Fingerprint: top-5 by count
      n = 0
      for (f in files) { n++; fnames[n] = f; fcounts[n] = files[f] }
      # Simple selection sort (max 5 from n)
      fp_out = ""
      for (i = 1; i <= 5 && i <= n; i++) {
        max_idx = i
        for (j = i+1; j <= n; j++) {
          if (fcounts[j] > fcounts[max_idx]) max_idx = j
        }
        if (max_idx != i) {
          tmp = fnames[i]; fnames[i] = fnames[max_idx]; fnames[max_idx] = tmp
          tmp = fcounts[i]; fcounts[i] = fcounts[max_idx]; fcounts[max_idx] = tmp
        }
        fp_out = fp_out (fp_out == "" ? "" : " ") fnames[i] "(" fcounts[i] ")"
      }
      print fp_out

      # Last user message (max 80 chars)
      msg = ""
      if (last_user != "") {
        if (match(last_user, /"text":"[^"]*"/)) {
          msg = substr(last_user, RSTART+7, RLENGTH-8)
        }
        if (length(msg) > 80) msg = substr(msg, 1, 80)
      }
      print msg

      # Project path (raw cwd; caller shortens $HOME→~ + truncates)
      print cwd
    }
  ' "$jsonl" 2>/dev/null || printf '\n\n\n\n'
}

# Parse session cache file (key=value lines) into _PSC_* variables.
_parse_session_cache() {
  _PSC_model= _PSC_ctx_pct= _PSC_cost= _PSC_rate_5h= _PSC_rate_7d=
  _PSC_reset_5h= _PSC_reset_7d= _PSC_session_id= _PSC_ppid=
  _PSC_worktree= _PSC_agent= _PSC_cache_pct= _PSC_rate_7d_start=
  _PSC_rate_5h_start= _PSC_project_path=
  _PSC_pinned= _PSC_kind= _PSC_pace= _PSC_cron= _PSC_bg_tasks=
  while IFS='=' read -r _k _v; do
    case "$_k" in
      model)          _PSC_model="$_v" ;;
      ctx_pct)        _PSC_ctx_pct="$_v" ;;
      cost)           _PSC_cost="$_v" ;;
      rate_5h)        _PSC_rate_5h="$_v" ;;
      rate_7d)        _PSC_rate_7d="$_v" ;;
      reset_5h)       _PSC_reset_5h="$_v" ;;
      reset_7d)       _PSC_reset_7d="$_v" ;;
      session_id)     _PSC_session_id="$_v" ;;
      ppid)           _PSC_ppid="$_v" ;;
      worktree)       _PSC_worktree="$_v" ;;
      agent)          _PSC_agent="$_v" ;;
      cache_pct)      _PSC_cache_pct="$_v" ;;
      rate_7d_start)  _PSC_rate_7d_start="$_v" ;;
      rate_5h_start)  _PSC_rate_5h_start="$_v" ;;
      project_path)   _PSC_project_path="$_v" ;;
      pinned)         _PSC_pinned="$_v" ;;
      pace)           _PSC_pace="$_v" ;;
      next_cron_at)   _PSC_cron="$_v" ;;
      bg_tasks)       _PSC_bg_tasks="$_v" ;;
    esac
  done < "$1"
  _PSC_mtime=$(_mtime "$1")
  # _NOW is set once per command by callers (_cmd_sessions / _cmd_sessions_inactive /
  # _cmd_default) so this per-session helper doesn't fork `date` each loop iteration;
  # falls back to a fork when unset (standalone call).
  _PSC_age=$(( ${_NOW:-$(date +%s)} - _PSC_mtime ))
  # Active = Claude Code process (ppid) is still running.
  # API path: ppid is listed by `claude agents --json` (caller ran _live_pids_init).
  # Authoritative when it matches — no PID-recycling risk, also reveals _PSC_kind.
  # Fallback: kill -0 + 24h age cap. Runs even when the API is populated because
  # `claude agents --json` deliberately omits the CURRENT interactive session —
  # without this fallback, `claudii se` from inside a live session would mark
  # its own row as inactive.
  _PSC_is_active=0
  if [[ "$_PSC_ppid" =~ ^[0-9]+$ ]] && [[ "$_PSC_ppid" != "0" ]]; then
    if (( _LIVE_PIDS_INITED )) && _pid_is_live "$_PSC_ppid"; then
      _PSC_is_active=1
      _PSC_kind=$(_pid_kind "$_PSC_ppid")
    elif (( _PSC_age < 86400 )) && kill -0 "$_PSC_ppid" 2>/dev/null; then
      _PSC_is_active=1
    fi
  fi
}

# Render 8-block context bar into _CTX_BAR.
_render_ctx_bar() {
  local _pct=${1:-0}
  local _filled=$(( _pct * 8 / 100 ))
  [[ $_filled -gt 8 ]] && _filled=8
  local _empty=$(( 8 - _filled ))
  local _clr
  if   [[ $_pct -ge 90 ]]; then _clr=$CLAUDII_CLR_RED
  elif [[ $_pct -ge 70 ]]; then _clr=$CLAUDII_CLR_YELLOW
  else                          _clr=$CLAUDII_CLR_GREEN
  fi
  local _bar="" i
  for ((i=0; i<_filled; i++)); do _bar+="$CLAUDII_SYM_BAR_FULL"; done
  for ((i=0; i<_empty;  i++)); do _bar+="$CLAUDII_SYM_BAR_EMPTY"; done
  _CTX_BAR="${_clr}${_bar}${CLAUDII_CLR_RESET}"
}

# Render age (seconds) into _AGE_STR ("Xs ago" … "Xd ago").
_render_age() {
  _fmt_brief "${1:-0}"
  _AGE_STR="${_BRIEF_FMT} ago"
}
