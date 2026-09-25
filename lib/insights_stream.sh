# lib/insights_stream.sh — stream the per-session insights caches to stdout.
# Sourced by bin/claudii-insights (merge), bin/claudii-otel (repo map) and
# lib/cmd/insights.sh (repos).
#
# Usage: _insights_stream DIR [DAYS]
#
# Two things every consumer needs, kept in one place:
#
# 1. Never argv. The cache keeps orphans forever; at ~12k files the path list
#    outgrew macOS's 1 MiB ARG_MAX and jq died with "Argument list too long"
#    (rc 126), taking tokens/cache/limits/tools/skills-cost/repos down with it.
#    find | xargs cat has no size limit, and jq reads several files as one
#    concatenated stream anyway, so the input is the same.
#
# 2. Read cost bounded by the window, not by history. A cache is written
#    (tmp + mv) after its session's last record, so last_seen <= mtime: a file
#    older than the window's cutoff cannot pass the consumer's
#    `last_seen >= cutoff` filter. With DAYS set, only files modified within
#    DAYS+1 days are read (one day of slack). Same idea as the mtime gate in
#    _collect_history_files (lib/helpers.sh). Skipped when CLAUDII_NOW pins the
#    clock: a pinned "now" is not comparable to real file mtimes.
#
# Output order is lexical by file name, like the glob it replaces. A file that
# vanishes mid-read (concurrent `gc --yes`) is skipped silently; the consumer's
# jq exit status stays the pipeline's status via the `|| true`.
_insights_stream() {
  local dir="$1" days="${2:-}"
  [[ -d "$dir" ]] || return 0
  local -a age=()
  if [[ "$days" =~ ^[0-9]+$ && -z "${CLAUDII_NOW:-}" ]]; then
    age=(-mmin "-$(( days * 1440 + 1440 ))")
  fi
  find "$dir" -maxdepth 1 -type f -name '*.json' ${age[@]+"${age[@]}"} -print0 \
    | LC_ALL=C sort -z \
    | { xargs -0 cat 2>/dev/null || true; }
}
