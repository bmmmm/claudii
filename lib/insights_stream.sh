# lib/insights_stream.sh — stream the per-session insights caches to stdout.
# Sourced by bin/claudii-insights (merge), bin/claudii-otel (repo map) and
# lib/cmd/insights.sh (repos).
#
# Usage: _insights_stream DIR [DAYS]
#
# Three things every consumer needs, kept in one place:
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
# 3. Other hosts. `claudii sync` mirrors their caches into
#    <cache>/hosts/<name>/insights (lib/cmd/sync.sh); when DIR is a cache's
#    insights dir, those mirrors stream with it, so every consumer sums all
#    hosts. Session ids are UUIDs — a mirror never repeats a local session.
#    CLAUDII_LOCAL_ONLY=1 streams DIR alone.
#
# Output order is lexical by path, like the glob it replaces. A file that
# vanishes mid-read (concurrent `gc --yes`) is skipped silently; the consumer's
# jq exit status stays the pipeline's status via the `|| true`.
_insights_stream() {
  local dir="$1" days="${2:-}"
  local -a dirs=() age=()
  _insights_dirs "$dir"
  dirs=(${_INSIGHTS_DIRS[@]+"${_INSIGHTS_DIRS[@]}"})
  (( ${#dirs[@]} )) || return 0
  if [[ "$days" =~ ^[0-9]+$ && -z "${CLAUDII_NOW:-}" ]]; then
    age=(-mmin "-$(( 10#$days * 1440 + 1440 ))")   # 10#: "08" is not octal
  fi
  # -H: follow DIR itself if it is a symlink, as the old glob did.
  find -H "${dirs[@]}" -maxdepth 1 -type f -name '*.json' ${age[@]+"${age[@]}"} -print0 \
    | LC_ALL=C sort -z \
    | { xargs -0 cat 2>/dev/null || true; }
}

# _insights_stream_tagged DIR [DAYS] — the same stream, one directory at a
# time, each preceded by a marker object naming its source:
#   {"_claudii_host":""}        DIR itself (this claudii)
#   {"_claudii_host":"<name>"}  the mirror <cache>/hosts/<name>/insights
# Consumers that keep sessions apart by source (merge --by-host, the insights
# side of `claudii cost`) read the marker and drop it; the plain stream above
# stays marker-free for everyone else. Mirror names passed _SYNC_NAME_RE
# (lib/cmd/sync.sh) when they were added, so they need no JSON escaping.
_insights_stream_tagged() {
  local dir="$1" days="${2:-}" d name
  local -a dirs=() age=()
  _insights_dirs "$dir"
  dirs=(${_INSIGHTS_DIRS[@]+"${_INSIGHTS_DIRS[@]}"})
  (( ${#dirs[@]} )) || return 0
  if [[ "$days" =~ ^[0-9]+$ && -z "${CLAUDII_NOW:-}" ]]; then
    age=(-mmin "-$(( 10#$days * 1440 + 1440 ))")
  fi
  for d in "${dirs[@]}"; do
    name=""
    [[ "$d" == "$dir" ]] || { name="${d%/insights}"; name="${name##*/}"; }
    printf '{"_claudii_host":"%s"}\n' "$name"
    find -H "$d" -maxdepth 1 -type f -name '*.json' ${age[@]+"${age[@]}"} -print0 \
      | LC_ALL=C sort -z \
      | { xargs -0 cat 2>/dev/null || true; }
  done
}

# _insights_dirs DIR → _INSIGHTS_DIRS: DIR (if it exists) plus the host
# mirrors next to it (see 3. above).
_INSIGHTS_DIRS=()
_insights_dirs() {
  local dir="$1" h
  _INSIGHTS_DIRS=()
  [[ -d "$dir" ]] && _INSIGHTS_DIRS+=("$dir")
  if [[ "${dir##*/}" == "insights" && "${CLAUDII_LOCAL_ONLY:-0}" != "1" ]]; then
    for h in "${dir%/*}"/hosts/*/insights; do
      [[ -d "$h" ]] && _INSIGHTS_DIRS+=("$h")
    done
  fi
  return 0
}

# _insights_any DIR — 0 when DIR or one of its host mirrors holds a cache.
# The commands' "no data yet" early return asks this instead of globbing DIR,
# so a machine that only mirrors other hosts still has data.
_insights_any() {
  local d f
  _insights_dirs "$1"
  for d in ${_INSIGHTS_DIRS[@]+"${_INSIGHTS_DIRS[@]}"}; do
    for f in "$d"/*.json; do
      [[ -f "$f" ]] && return 0
      break
    done
  done
  return 1
}
