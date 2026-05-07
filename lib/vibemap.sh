# vibemap.sh — append-only activity tracking, opt-in via vibemap.enabled.
#
# Schema (TSV, 7 fields per line):
#   epoch \t weekday(0-6, Sun=0) \t hour(0-23) \t minute(0-59) \t model \t sid8 \t delta_ms
#
# Append happens at the end of cc-statusline render when vibemap.enabled=true.
# Read by `claudii vibemap` subcommands (lib/cmd/vibemap.sh).
#
# Sourced by: bin/claudii (CLI), bin/claudii-cc-statusline (logging hook).
# No shebang, no `set -euo pipefail` — must not destabilize callers.

# Resolve the active vibemap file path. Empty config → cache-dir default.
# Tilde expansion is done here so callers don't have to.
_vibemap_resolve_path() {
  local cfg_path="${1:-}"
  if [[ -n "$cfg_path" ]]; then
    printf '%s' "${cfg_path/#\~/$HOME}"
  else
    printf '%s' "${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/vibemap.tsv"
  fi
}

# Append one render to the vibemap file. All-bash time formatting via the
# printf %(…)T builtin — no fork, sub-millisecond. Callers must check
# vibemap.enabled themselves; this function does no policy.
#
# Args:
#   $1 path        — pre-resolved vibemap file path (use _vibemap_resolve_path)
#   $2 model       — model display name; first word is stored ("Opus 4.7" → "Opus")
#   $3 sid         — full session id; truncated to 8 chars before write
#   $4 delta_ms    — duration delta vs previous render (0 if unknown)
_vibemap_append() {
  local path="$1" model="$2" sid="$3" delta_ms="${4:-0}"
  [[ -z "$path" ]] && return 1
  local dir="${path%/*}"
  [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 1
  local model_short="${model%% *}"
  local sid8="${sid:0:8}"
  # printf's %(…)T treats \t as literal — so we extract each component
  # separately, then interleave with real tabs in the final printf.
  local _t _wd _hh _mm
  printf -v _t  '%(%s)T' -1
  printf -v _wd '%(%w)T' -1
  printf -v _hh '%(%H)T' -1
  printf -v _mm '%(%M)T' -1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$_t" "$_wd" "$_hh" "$_mm" "$model_short" "$sid8" "$delta_ms" \
    >> "$path" 2>/dev/null
}
