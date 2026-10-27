# lib/cmd/sync.sh — claudii sync: one view over several hosts and accounts.
#
# Sourced by bin/claudii — no shebang, no `set -euo pipefail`.
#
# WHAT TRAVELS
#   Never transcripts. Every claudii already condenses its own data into small
#   derived files, and those are what moves:
#     insights/<sid>.json  per-session aggregate (bin/claudii-insights), replaced
#                          whole when its session changed
#     history*.tsv         Flight Recorder (cc-statusline), append-only: only
#                          the bytes the receiver lacks travel
#     session-*            live-session caches (cc-statusline), replaced whole
#     live                 ids of the sessions whose Claude Code process runs at
#                          the source right now
#   Measured on one host (2026-10-27): 635 MB of transcripts → 2 MB of insights
#   caches → 166 KB gzip'd. A sync after that carries only what changed.
#
# PROTOCOL — one round trip over any byte pipe (ssh by default)
#   receiver → source, on the stdin of `claudii sync export`:
#       claudii-sync 1
#       cursor <epoch>          source clock; 0 = everything
#       have <file> <bytes>     one per append-only file the receiver holds
#   source → receiver, on its stdout: a gzip'd tar bundle
#       manifest                format, origin_id, origin, version, exported_at,
#                               since, one `append=<file>:<offset>` per tail
#       insights/ sessions/     files modified since the cursor
#       tail/<file>             the bytes of <file> from <offset> on
#       live
#   The receiver keeps the cursor (the bundle's exported_at) and derives the
#   `have` sizes from its own files. The source keeps no state at all, so any
#   number of receivers can pull from it independently, and the same exchange
#   runs in the other direction (`mode: push`) for a source that can reach the
#   receiver but not the other way round.
#
# RECEIVER LAYOUT  $CACHE/hosts/<name>/{state,live,insights/,sessions/,history*.tsv}
#   _insights_stream (lib/insights_stream.sh) and _collect_history_files
#   (lib/helpers.sh) read every mirror after the local data, so tokens, cost,
#   trends, week, tools, limits, repos, cache and skills-cost show the sum.
#   CLAUDII_LOCAL_ONLY=1 keeps them local. Session ids are UUIDs, so mirrors
#   never collide with each other or with local data; the one way to count a
#   session twice is to sync the same source twice, and import refuses that
#   (same origin_id under a second name, or the bundle comes from itself).

_SYNC_FORMAT=1
_SYNC_RESERVED=" add rm remove status ls export import state help "
_SYNC_NAME_RE='^[A-Za-z0-9][A-Za-z0-9._@-]*$'
_SYNC_HIST_RE='^history(-[0-9][0-9][0-9][0-9]-[0-9][0-9])?\.tsv$'
_SYNC_ID_RE='^[0-9a-f]{32}$'

_sync_cache_dir() { printf '%s' "${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}"; }

_sync_valid_name() {
  [[ "$1" =~ $_SYNC_NAME_RE ]] || return 1
  (( ${#1} <= 64 )) || return 1
  case "$_SYNC_RESERVED" in *" $1 "*) return 1 ;; esac
  return 0
}

# This claudii's identity: a random id minted once per cache dir. Import uses
# it to tell a new host from the same source under a second name, and from
# itself — both would count every session twice.
_sync_host_id() {
  local cdir="$1" f="$1/host-id" id=""
  [[ -s "$f" ]] && { id=$(<"$f"); } 2>/dev/null
  if ! [[ "$id" =~ $_SYNC_ID_RE ]]; then
    id=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    [[ "$id" =~ $_SYNC_ID_RE ]] || return 1
    mkdir -p "$cdir" && printf '%s\n' "$id" > "$f"
  fi
  printf '%s' "$id"
}

# user@host — the default name this claudii pushes under, and the label shown
# on the receiving side.
_sync_label() {
  local u h
  u=$(id -un 2>/dev/null) || u="${USER:-user}"
  h=$(hostname -s 2>/dev/null) || h=$(uname -n 2>/dev/null) || h="host"
  h="${h%%.*}"
  printf '%s@%s' "$u" "$h"
}

_sync_self_name() {
  local n; n=$(_cfgget sync.name 2>/dev/null) || n=""
  [[ -n "$n" ]] || n=$(_sync_label)
  printf '%s' "$n"
}

# Byte size of a file (0 when absent). wc pads with spaces on BSD.
_sync_size() {
  local s=0
  [[ -f "$1" ]] && { s=$(wc -c < "$1" 2>/dev/null) || s=0; }
  s="${s//[!0-9]/}"
  printf '%s' "${s:-0}"
}

# key=value lookup in a small state/manifest file; prints the value or nothing.
_sync_kv() {
  local file="$1" want="$2" k v
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r k v; do
    [[ "$k" == "$want" ]] && { printf '%s' "$v"; return 0; }
  done < "$file"
  return 0
}

# Copy (or move) every regular file a find selects into DEST in batches — no
# per-file fork, no argv built from the list (xargs splits it). $0 of the inner
# sh is DEST; the guard keeps GNU xargs' empty-input run from failing.
_sync_batch() {
  local verb="$1" dest="$2"
  xargs -0 sh -c 'if [ $# -gt 0 ]; then '"$verb"' "$@" "$0"; fi' "$dest"
}

# ── Request: what the receiver already has ───────────────────────────────────

# Prints the request for mirror NAME on stdout (see PROTOCOL).
_sync_request() {
  local mirror="$1" cursor f
  cursor=$(_sync_kv "$mirror/state" cursor)
  [[ "$cursor" =~ ^[0-9]+$ ]] || cursor=0
  printf 'claudii-sync %s\ncursor %s\n' "$_SYNC_FORMAT" "$cursor"
  for f in "$mirror"/history.tsv "$mirror"/history-*.tsv; do
    [[ -f "$f" ]] || continue
    printf 'have %s %s\n' "${f##*/}" "$(_sync_size "$f")"
  done
  return 0
}

# ── Export: build a bundle on stdout ─────────────────────────────────────────

_sync_export() {
  local refresh=1 full=0 a
  for a in "$@"; do
    case "$a" in
      --no-refresh) refresh=0 ;;
      --full)       full=1 ;;
      *) _cli_unknown_opt "sync export" "$a" '[--full] [--no-refresh]' || return $? ;;
    esac
  done

  local cdir; cdir=$(_sync_cache_dir)
  mkdir -p "$cdir" && chmod 0700 "$cdir"

  # The request. A TTY on stdin means nobody sent one: export everything.
  local cursor=0 haves="" k v1 v2
  if (( ! full )) && [[ ! -t 0 ]]; then
    while read -r k v1 v2; do
      case "$k" in
        cursor) [[ "$v1" =~ ^[0-9]+$ ]] && cursor="$v1" ;;
        have)   [[ "$v1" =~ $_SYNC_HIST_RE && "$v2" =~ ^[0-9]+$ ]] && haves+="$v1 $v2"$'\n' ;;
      esac
    done
  fi

  local id; id=$(_sync_host_id "$cdir") || { printf 'claudii sync: cannot create %s/host-id\n' "$cdir" >&2; return 1; }

  # Bring the insights caches up to date first — a source without a
  # statusline (T3 Code, the Agent SDK) has no other data. Its progress line
  # must not land in the bundle.
  if (( refresh )); then
    "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1 || true
  fi

  local now; now=$(date +%s)
  local stage; stage=$(mktemp -d "${TMPDIR:-/tmp}/claudii-sync.XXXXXX") || return 1
  local rc=0
  _sync_stage "$cdir" "$stage" "$cursor" "$haves" "$now" "$id" || rc=$?
  # COPYFILE_DISABLE: macOS tar would add an AppleDouble ._file for every
  # file with xattrs (import ignores them, but they cost bytes).
  if (( rc == 0 )); then
    # Named members only: the stage also holds the .since reference file.
    COPYFILE_DISABLE=1 tar -czf - -C "$stage" manifest live insights sessions tail || rc=$?
  fi
  rm -rf "$stage"
  return $rc
}

_sync_stage() {
  local cdir="$1" stage="$2" cursor="$3" haves="$4" now="$5" id="$6"
  mkdir -p "$stage/insights" "$stage/sessions" "$stage/tail" || return 1

  # Files modified since the cursor: newer than a reference file stamped one
  # second before it. Stamped in UTC on both ends — a local-time stamp is
  # ambiguous in the repeated DST hour and could land an hour late. -mmin with
  # a minute of slack is the fallback: coarser (it re-sends whatever the last
  # export's insights refresh just rewrote), never a gap.
  local -a age=()
  local ref="$stage/.since" ts
  if (( cursor > 0 && cursor <= now )); then
    ts=$(TZ=UTC date -d "@$(( cursor - 1 ))" +%Y%m%d%H%M.%S 2>/dev/null \
      || TZ=UTC date -r "$(( cursor - 1 ))" +%Y%m%d%H%M.%S 2>/dev/null) || ts=""
    if [[ -n "$ts" ]] && TZ=UTC touch -t "$ts" "$ref" 2>/dev/null; then
      age=(-newer "$ref")
    else
      age=(-mmin "-$(( (now - cursor) / 60 + 2 ))")
    fi
  fi
  if [[ -d "$cdir/insights" ]]; then
    find "$cdir/insights" -maxdepth 1 -type f -name '*.json' ${age[@]+"${age[@]}"} -print0 \
      | _sync_batch 'cp -p' "$stage/insights" || return 1
  fi
  find "$cdir" -maxdepth 1 -type f -name 'session-*' ! -name '*.tmp.*' ${age[@]+"${age[@]}"} -print0 \
    | _sync_batch 'cp -p' "$stage/sessions" || return 1

  # Liveness can change without the cache file changing, so `live` is computed
  # over every session cache, with the same check `claudii se` uses.
  _NOW="$now"
  _live_pids_init
  local f
  : > "$stage/live"
  for f in "$cdir"/session-*; do
    [[ -f "$f" && "$f" != *.tmp.* ]] || continue
    _parse_session_cache "$f"
    if (( _PSC_is_active )) && [[ -n "$_PSC_session_id" ]]; then
      printf '%s\n' "$_PSC_session_id" >> "$stage/live"
    fi
  done

  {
    printf 'format=%s\n' "$_SYNC_FORMAT"
    printf 'origin_id=%s\n' "$id"
    printf 'origin=%s\n' "$(_sync_label)"
    printf 'version=%s\n' "${VERSION:-}"
    printf 'exported_at=%s\n' "$now"
    printf 'since=%s\n' "$cursor"
  } > "$stage/manifest"

  # Append-only files: the tail past what the receiver has. `head -c size`
  # pins the end before the statusline appends more (and, unlike tail|head,
  # never SIGPIPEs). A row is one atomic append, so the cut lands on a line
  # end; if it ever does not, the file waits for the next sync rather than
  # hand the receiver half a row.
  local hf base size have off chunk hn hs
  for hf in "$cdir"/history.tsv "$cdir"/history-*.tsv; do
    [[ -f "$hf" ]] || continue
    base="${hf##*/}"
    size=$(_sync_size "$hf")
    have=0
    while read -r hn hs; do
      [[ "$hn" == "$base" ]] && have="$hs"
    done <<< "$haves"
    (( size == have )) && continue
    off=$have
    (( size < have )) && off=0     # shrank at the source: start over
    chunk="$stage/tail/$base"
    head -c "$size" "$hf" | tail -c "+$(( off + 1 ))" > "$chunk" || return 1
    if [[ -s "$chunk" && -n "$(tail -c 1 "$chunk")" ]]; then
      rm -f "$chunk"; continue
    fi
    printf 'append=%s:%s\n' "$base" "$off" >> "$stage/manifest"
  done
  return 0
}

# ── Import: apply a bundle from stdin ────────────────────────────────────────

# mkdir is the one atomic test-and-set both platforms share. A lock older than
# ten minutes belongs to a run that died and is taken over.
_sync_lock() {
  local lock="$1/.lock" mt now
  mkdir -p "$1" || return 1
  mkdir "$lock" 2>/dev/null && return 0
  mt=$(_mtime "$lock"); now=$(date +%s)
  if (( now - ${mt:-0} > 600 )); then
    rm -rf "$lock"; mkdir "$lock" 2>/dev/null && return 0
  fi
  printf 'claudii sync: %s is being synced by another run\n' "${1##*/}" >&2
  return 1
}

_sync_import() {
  local name="" a
  for a in "$@"; do
    case "$a" in
      -*) _cli_unknown_opt "sync import" "$a" '<name> < bundle' || return $? ;;
      *)  [[ -z "$name" ]] && name="$a" || { printf 'claudii sync import: one name only\n' >&2; return 2; } ;;
    esac
  done
  if [[ -z "$name" ]]; then
    printf 'Usage: claudii sync import <name> < bundle\n' >&2; return 2
  fi
  _sync_valid_name "$name" || { printf 'claudii sync: invalid host name: %s\n' "$name" >&2; return 2; }
  if [[ -t 0 ]]; then
    printf 'claudii sync import: expects a bundle on stdin (from: claudii sync export)\n' >&2; return 2
  fi

  local cdir; cdir=$(_sync_cache_dir)
  local hosts="$cdir/hosts" mirror="$cdir/hosts/$name"
  mkdir -p "$hosts" && chmod 0700 "$hosts"
  _sync_lock "$mirror" || return 1

  # Unpacked next to the mirror (same filesystem → plain renames), in a dot
  # dir that no reader's hosts/*/ glob matches.
  local tmp rc=0
  tmp=$(mktemp -d "$hosts/.incoming.XXXXXX") || { rm -rf "$mirror/.lock"; return 1; }
  if tar -xzf - -C "$tmp" 2>/dev/null && [[ -f "$tmp/manifest" && ! -L "$tmp/manifest" ]]; then
    _sync_apply "$name" "$tmp" "$mirror" "$cdir" || rc=$?
  else
    printf 'claudii sync: %s: not a claudii sync bundle\n' "$name" >&2
    rc=1
  fi
  rm -rf "$tmp" "$mirror/.lock"
  # A refused first import leaves no mirror behind — status would list it as
  # a host that pushes to us.
  if (( rc != 0 )) && [[ ! -f "$mirror/state" ]]; then rm -rf "$mirror"; fi
  return $rc
}

# rc 0 applied · 1 refused · 3 origin changed or cursor gap: mirror reset,
# re-export with a fresh request (pull does that by itself).
_sync_apply() {
  local name="$1" tmp="$2" mirror="$3" cdir="$4"
  local m="$tmp/manifest"
  local fmt oid origin version at since
  fmt=$(_sync_kv "$m" format);      oid=$(_sync_kv "$m" origin_id)
  origin=$(_sync_kv "$m" origin);   version=$(_sync_kv "$m" version)
  at=$(_sync_kv "$m" exported_at);  since=$(_sync_kv "$m" since)

  if [[ "$fmt" != "$_SYNC_FORMAT" ]]; then
    printf 'claudii sync: %s speaks bundle format %s, this claudii %s — update the older one\n' \
      "$name" "${fmt:-?}" "$_SYNC_FORMAT" >&2
    return 1
  fi
  if ! [[ "$oid" =~ $_SYNC_ID_RE && "$at" =~ ^[0-9]+$ && "$since" =~ ^[0-9]+$ ]]; then
    printf 'claudii sync: %s: malformed manifest\n' "$name" >&2
    return 1
  fi

  local self; self=$(_sync_host_id "$cdir") || self=""
  if [[ "$oid" == "$self" ]]; then
    printf 'claudii sync: %s is this claudii itself — syncing it would count every session twice\n' "$name" >&2
    return 1
  fi
  local d other
  for d in "$cdir"/hosts/*/; do
    d="${d%/}"
    [[ "$d" == "$mirror" ]] && continue
    other=$(_sync_kv "$d/state" origin_id)
    if [[ "$other" == "$oid" ]]; then
      printf 'claudii sync: %s (%s) is already synced as %s — one source, one name\n' \
        "$name" "$origin" "${d##*/}" >&2
      return 1
    fi
  done

  # A different source behind the same name: its files replace the old ones,
  # which takes a full bundle. A delta that starts past our cursor (a
  # hand-carried bundle, a request from a newer state) would leave a gap.
  local known cursor
  known=$(_sync_kv "$mirror/state" origin_id)
  cursor=$(_sync_kv "$mirror/state" cursor)
  [[ "$cursor" =~ ^[0-9]+$ ]] || cursor=0
  if [[ -n "$known" && "$known" != "$oid" ]]; then
    _sync_wipe "$mirror"
    if (( since > 0 )); then
      printf 'claudii sync: %s is now a different source (%s) — starting over\n' "$name" "$origin" >&2
      return 3
    fi
    cursor=0
  fi
  if (( since > cursor )); then
    printf 'claudii sync: %s: bundle starts at %s, mirror stands at %s — export again with: claudii sync state %s\n' \
      "$name" "$since" "$cursor" "$name" >&2
    return 3
  fi

  mkdir -p "$mirror/insights" "$mirror/sessions" && chmod 0700 "$mirror" "$mirror/insights" "$mirror/sessions"

  # Only regular files with the expected names make it out of the bundle:
  # -type f skips symlinks and devices, the name filters skip everything else,
  # and mv into a directory keeps nothing but the basename.
  if [[ -d "$tmp/insights" && ! -L "$tmp/insights" ]]; then
    find "$tmp/insights" -maxdepth 1 -type f -name '[0-9A-Za-z]*.json' -print0 \
      | _sync_batch 'mv -f' "$mirror/insights" || return 1
  fi
  if [[ -d "$tmp/sessions" && ! -L "$tmp/sessions" ]]; then
    find "$tmp/sessions" -maxdepth 1 -type f -name 'session-*' -print0 \
      | _sync_batch 'mv -f' "$mirror/sessions" || return 1
  fi

  local k v base off chunk dst have
  while IFS='=' read -r k v; do
    [[ "$k" == "append" ]] || continue
    base="${v%:*}"; off="${v##*:}"
    [[ "$base" =~ $_SYNC_HIST_RE && "$off" =~ ^[0-9]+$ ]] || continue
    chunk="$tmp/tail/$base"
    [[ -f "$chunk" && ! -L "$chunk" ]] || continue
    dst="$mirror/$base"
    if (( off == 0 )); then
      mv -f "$chunk" "$dst"
    else
      have=$(_sync_size "$dst")
      if (( have == off )); then
        cat "$chunk" >> "$dst"
      else
        # Our copy moved since the request (a concurrent run): drop it, the
        # next sync sends the whole file.
        printf 'claudii sync: %s: %s out of step (have %s, bundle starts at %s) — refetching\n' \
          "$name" "$base" "$have" "$off" >&2
        rm -f "$dst"
      fi
    fi
    chmod 0600 "$dst" 2>/dev/null || true
  done < "$m"

  if [[ -f "$tmp/live" && ! -L "$tmp/live" ]]; then
    mv -f "$tmp/live" "$mirror/live"
  fi

  {
    printf 'origin_id=%s\n' "$oid"
    printf 'origin=%s\n' "$origin"
    printf 'version=%s\n' "$version"
    printf 'cursor=%s\n' "$at"
    printf 'synced_at=%s\n' "$(date +%s)"
  } > "$mirror/state.tmp" && mv -f "$mirror/state.tmp" "$mirror/state"
  return 0
}

_sync_wipe() {
  local mirror="$1"
  rm -rf "$mirror/insights" "$mirror/sessions" "$mirror/live" "$mirror/state"
  rm -f "$mirror"/history.tsv "$mirror"/history-*.tsv
}

# `claudii sync state <name>` — the request for mirror <name>; a pushing peer
# reads it over ssh before it exports.
_sync_state_cmd() {
  local name="${1:-}"
  case "$name" in -*) _cli_unknown_opt "sync state" "$name" '<name>' || return $? ;; esac
  if [[ -z "$name" || $# -gt 1 ]]; then printf 'Usage: claudii sync state <name>\n' >&2; return 2; fi
  _sync_valid_name "$name" || { printf 'claudii sync: invalid host name: %s\n' "$name" >&2; return 2; }
  _sync_request "$(_sync_cache_dir)/hosts/$name"
}

# ── Transports ───────────────────────────────────────────────────────────────

# CLAUDII_SSH replaces the ssh binary (tests, or a wrapper with its own -F).
# BatchMode: a sync must fail, never sit at a password prompt.
_sync_ssh() {
  local target="$1"; shift
  ${CLAUDII_SSH:-ssh} -o BatchMode=yes -o ConnectTimeout=15 "$target" "$@"
}

# Bundle files live next to the mirrors, in the dot dir readers skip.
_sync_tmpfile() {
  local hosts; hosts="$(_sync_cache_dir)/hosts"
  mkdir -p "$hosts" && chmod 0700 "$hosts"
  mktemp "$hosts/.bundle.XXXXXX"
}

_SYNC_BYTES=0
_sync_pull() {
  local name="$1" target="$2" rcmd="$3"
  local cdir; cdir=$(_sync_cache_dir)
  local req bundle rc=0 try
  for try in 1 2; do
    req=$(_sync_request "$cdir/hosts/$name")
    bundle=$(_sync_tmpfile) || return 1
    if ! printf '%s\n' "$req" | _sync_ssh "$target" "$rcmd sync export" > "$bundle"; then
      rm -f "$bundle"
      printf 'claudii sync: %s: ssh %s "%s sync export" failed\n' "$name" "$target" "$rcmd" >&2
      return 1
    fi
    _SYNC_BYTES=$(_sync_size "$bundle")
    rc=0
    _sync_import "$name" < "$bundle" || rc=$?
    rm -f "$bundle"
    (( rc == 3 )) && continue     # mirror reset: once more, from zero
    return $rc
  done
  return $rc
}

_sync_push() {
  local name="$1" target="$2" rcmd="$3" as="$4"
  local req bundle rc=0 try
  # $as goes into the remote command line: it must be a plain name here, not
  # only once the remote claudii parses it.
  if ! _sync_valid_name "$as"; then
    printf 'claudii sync: sync.name %s is not a valid host name (letters, digits, . _ @ -)\n' "$as" >&2
    return 2
  fi
  for try in 1 2; do
    if ! req=$(_sync_ssh "$target" "$rcmd sync state $as" < /dev/null); then
      printf 'claudii sync: %s: ssh %s "%s sync state" failed\n' "$name" "$target" "$rcmd" >&2
      return 1
    fi
    bundle=$(_sync_tmpfile) || return 1
    printf '%s\n' "$req" | _sync_export > "$bundle" || { rm -f "$bundle"; return 1; }
    _SYNC_BYTES=$(_sync_size "$bundle")
    rc=0
    _sync_ssh "$target" "$rcmd sync import $as" < "$bundle" || rc=$?
    rm -f "$bundle"
    # rc 3: the receiver reset its mirror of us — its next request starts at 0.
    (( rc == 3 )) && continue
    break
  done
  (( rc == 0 )) || printf 'claudii sync: %s: ssh %s "%s sync import" failed\n' "$name" "$target" "$rcmd" >&2
  return $rc
}

# ── Configured hosts ─────────────────────────────────────────────────────────

# Fills parallel arrays (bash 3.2: no declare -A) from config.json sync.hosts.
_SH_NAMES=() _SH_SSH=() _SH_CMD=() _SH_MODE=()
_sync_hosts_load() {
  _SH_NAMES=() _SH_SSH=() _SH_CMD=() _SH_MODE=()
  local n s c m i=0
  [[ -f "$CONFIG" ]] || return 0
  while IFS=$'\t' read -r n s c m; do
    [[ -n "$n" ]] || continue
    _SH_NAMES[$i]="$n"; _SH_SSH[$i]="$s"; _SH_CMD[$i]="${c:-claudii}"; _SH_MODE[$i]="${m:-pull}"
    (( ++i ))
  done < <(jq -r '(.sync.hosts // {}) | to_entries[]
                  | [.key, (.value.ssh // ""), (.value.cmd // "claudii"), (.value.mode // "pull")]
                  | @tsv' "$CONFIG" 2>/dev/null)
  return 0
}

_sync_host_index() {
  local i
  for (( i=0; i<${#_SH_NAMES[@]}; i++ )); do
    [[ "${_SH_NAMES[$i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

_sync_add() {
  local name="" target="" rcmd="" mode="pull" a
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cmd)    rcmd="${2:-}"; [[ -n "$rcmd" ]] || { printf 'claudii sync add: --cmd needs a value\n' >&2; return 2; }; shift ;;
      --cmd=*)  rcmd="${1#--cmd=}" ;;
      --pull)   mode="pull" ;;
      --push)   mode="push" ;;
      --both)   mode="both" ;;
      -*)       _cli_unknown_opt "sync add" "$1" '<name> <ssh-target> [--cmd PATH] [--pull|--push|--both]' || return $? ;;
      *)        if [[ -z "$name" ]]; then name="$1"
                elif [[ -z "$target" ]]; then target="$1"
                else printf 'claudii sync add: unexpected argument: %s\n' "$1" >&2; return 2; fi ;;
    esac
    shift
  done
  if [[ -z "$name" || -z "$target" ]]; then
    printf 'Usage: claudii sync add <name> <ssh-target> [--cmd PATH] [--pull|--push|--both]\n' >&2
    return 2
  fi
  if ! _sync_valid_name "$name"; then
    printf 'claudii sync add: invalid name: %s (letters, digits, . _ @ -; not a subcommand)\n' "$name" >&2
    return 2
  fi
  case "$target" in
    -*|*[[:space:]]*) printf 'claudii sync add: invalid ssh target: %s\n' "$target" >&2; return 2 ;;
  esac
  local obj
  obj=$(jq -cn --arg s "$target" --arg c "$rcmd" --arg m "$mode" \
    '{ssh: $s, mode: $m} + (if $c == "" then {} else {cmd: $c} end)')
  _jq_update "$CONFIG" --arg n "$name" --argjson h "$obj" '.sync.hosts[$n] = $h' || return 1
  printf 'sync: %s → %s (%s%s)\n' "$name" "$target" "$mode" "${rcmd:+, cmd: $rcmd}"
  printf '  run: claudii sync %s\n' "$name"
}

_sync_rm() {
  local name="${1:-}"
  case "$name" in -*) _cli_unknown_opt "sync rm" "$name" '<name>' || return $? ;; esac
  if [[ -z "$name" || $# -gt 1 ]]; then printf 'Usage: claudii sync rm <name>\n' >&2; return 2; fi
  _sync_valid_name "$name" || { printf 'claudii sync: invalid host name: %s\n' "$name" >&2; return 2; }
  local mirror; mirror="$(_sync_cache_dir)/hosts/$name"
  local did=0
  if jq -e --arg n "$name" '.sync.hosts[$n] // empty' "$CONFIG" >/dev/null 2>&1; then
    _jq_update "$CONFIG" --arg n "$name" 'del(.sync.hosts[$n])' || return 1
    printf 'sync: %s removed from config\n' "$name"; did=1
  fi
  if [[ -d "$mirror" ]]; then
    rm -rf "$mirror"
    printf 'sync: %s data removed (%s)\n' "$name" "$mirror"; did=1
  fi
  (( did )) || { printf 'claudii sync: no host named %s\n' "$name" >&2; return 1; }
  return 0
}

# ── claudii sync [NAME…] ─────────────────────────────────────────────────────

_sync_run() {
  local quiet=0 a
  local -a want=()
  for a in "$@"; do
    case "$a" in
      -q|--quiet) quiet=1 ;;
      -*) _cli_unknown_opt sync "$a" '[NAME…] [--quiet] | status | add | rm' || return $? ;;
      *)  want+=("$a") ;;
    esac
  done
  _sync_hosts_load
  if (( ${#_SH_NAMES[@]} == 0 )); then
    (( quiet )) && return 0
    _sync_status
    return 0
  fi
  local -a idx=()
  local i w
  if (( ${#want[@]} )); then
    for w in "${want[@]}"; do
      i=$(_sync_host_index "$w") || { printf 'claudii sync: no host named %s — list: claudii sync status\n' "$w" >&2; return 1; }
      idx+=("$i")
    done
  else
    for (( i=0; i<${#_SH_NAMES[@]}; i++ )); do idx+=("$i"); done
  fi

  local as; as=$(_sync_self_name)
  local fails=0 n t c m rc t0 dt
  for i in "${idx[@]}"; do
    n="${_SH_NAMES[$i]}"; t="${_SH_SSH[$i]}"; c="${_SH_CMD[$i]}"; m="${_SH_MODE[$i]}"
    if [[ -z "$t" ]]; then
      printf 'claudii sync: %s has no ssh target (sync.hosts.%s.ssh)\n' "$n" "$n" >&2
      (( ++fails )); continue
    fi
    if [[ "$m" == "pull" || "$m" == "both" ]]; then
      t0=$(date +%s); rc=0
      _sync_pull "$n" "$t" "$c" || rc=$?
      dt=$(( $(date +%s) - t0 ))
      if (( rc == 0 )); then
        (( quiet )) || printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_OK}${CLAUDII_CLR_RESET} %s ${CLAUDII_CLR_DIM}⇣ %s in %ss${CLAUDII_CLR_RESET}\n" "$n" "$(_sync_fmt_bytes "$_SYNC_BYTES")" "$dt"
      else
        (( ++fails ))
        (( quiet )) || printf "  ${CLAUDII_CLR_RED}${CLAUDII_SYM_ERROR}${CLAUDII_CLR_RESET} %s ${CLAUDII_CLR_DIM}pull failed${CLAUDII_CLR_RESET}\n" "$n"
      fi
    fi
    if [[ "$m" == "push" || "$m" == "both" ]]; then
      t0=$(date +%s); rc=0
      _sync_push "$n" "$t" "$c" "$as" || rc=$?
      dt=$(( $(date +%s) - t0 ))
      if (( rc == 0 )); then
        (( quiet )) || printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_OK}${CLAUDII_CLR_RESET} %s ${CLAUDII_CLR_DIM}⇡ %s as %s in %ss${CLAUDII_CLR_RESET}\n" "$n" "$(_sync_fmt_bytes "$_SYNC_BYTES")" "$as" "$dt"
      else
        (( ++fails ))
        (( quiet )) || printf "  ${CLAUDII_CLR_RED}${CLAUDII_SYM_ERROR}${CLAUDII_CLR_RESET} %s ${CLAUDII_CLR_DIM}push failed${CLAUDII_CLR_RESET}\n" "$n"
      fi
    fi
  done
  (( quiet )) || _sync_status
  (( fails == 0 ))
}

_sync_fmt_bytes() {
  local b="${1:-0}"
  if   (( b < 1024 ));    then printf '%d B' "$b"
  elif (( b < 1048576 )); then printf '%d KB' $(( (b + 512) / 1024 ))
  else printf '%d.%d MB' $(( b / 1048576 )) $(( (b % 1048576) * 10 / 1048576 ))
  fi
}

# ── claudii sync status ──────────────────────────────────────────────────────

# One mirror's numbers, tab-separated: sessions, history rows, last activity
# (epoch, 0 = none), live count. Last activity reads only the caches written
# in the last two days — the newest session is among them.
_sync_mirror_stats() {
  local mirror="$1" sessions=0 rows=0 last=0 live=0 f
  if [[ -d "$mirror/insights" ]]; then
    sessions=$(find "$mirror/insights" -maxdepth 1 -type f -name '*.json' | wc -l)
    sessions="${sessions//[!0-9]/}"
    last=$(find "$mirror/insights" -maxdepth 1 -type f -name '*.json' -mmin -2880 -print0 \
      | { xargs -0 cat 2>/dev/null || true; } \
      | jq -n 'reduce inputs as $s (0;
                 ($s.last_seen // "" | sub("\\.[0-9]+Z$"; "Z")
                  | (try fromdateiso8601 catch 0)) as $t
                 | if $t > . then $t else . end)' 2>/dev/null) || last=0
  fi
  for f in "$mirror"/history.tsv "$mirror"/history-*.tsv; do
    [[ -f "$f" ]] || continue
    rows=$(( rows + $(wc -l < "$f") ))
  done
  if [[ -f "$mirror/live" ]]; then
    live=$(grep -c . "$mirror/live" 2>/dev/null) || live=0
  fi
  printf '%s\t%s\t%s\t%s\n' "${sessions:-0}" "$rows" "${last:-0}" "$live"
}

# Live sessions of one mirror: model, ctx%, project dir — from the mirrored
# session caches whose id the source listed as live. US-delimited, not tab: an
# empty ctx% would collapse under IFS=$'\t' and shift the project into it.
_SYNC_US=$'\037'
_sync_live_rows() {
  local mirror="$1" f sid model ctx proj
  [[ -s "$mirror/live" && -d "$mirror/sessions" ]] || return 0
  local live; live=$'\n'"$(<"$mirror/live")"$'\n'
  for f in "$mirror"/sessions/session-*; do
    [[ -f "$f" ]] || continue
    sid=$(_sync_kv "$f" session_id)
    [[ -n "$sid" ]] || continue
    case "$live" in *$'\n'"$sid"$'\n'*) ;; *) continue ;; esac
    model=$(_sync_kv "$f" model); ctx=$(_sync_kv "$f" ctx_pct); proj=$(_sync_kv "$f" project_path)
    printf '%s\n' "$sid$_SYNC_US${model%% (*}$_SYNC_US$ctx$_SYNC_US${proj##*/}"
  done
}

_sync_status() {
  local a
  for a in "$@"; do
    _cli_unknown_opt "sync status" "$a" '[--json]' || return $?
  done
  _sync_hosts_load
  local cdir; cdir=$(_sync_cache_dir)
  local self_id; self_id=$(_sync_host_id "$cdir") || self_id=""
  local self_name; self_name=$(_sync_self_name)
  local now; now=$(date +%s)

  # Every configured host plus every mirror on disk — a peer that pushes to us
  # has a mirror but no config entry.
  local -a names=()
  local i d n
  for (( i=0; i<${#_SH_NAMES[@]}; i++ )); do names+=("${_SH_NAMES[$i]}"); done
  for d in "$cdir"/hosts/*/; do
    [[ -d "$d" ]] || continue
    n="${d%/}"; n="${n##*/}"
    _sync_host_index "$n" >/dev/null || names+=("$n")
  done

  local mirror stats sessions rows last live origin synced ssh mode cmd
  if [[ "$_FORMAT" == "json" ]]; then
    local rows_json="" one live_json
    for n in ${names[@]+"${names[@]}"}; do
      mirror="$cdir/hosts/$n"
      IFS=$'\t' read -r sessions rows last live <<< "$(_sync_mirror_stats "$mirror")"
      origin=$(_sync_kv "$mirror/state" origin); synced=$(_sync_kv "$mirror/state" synced_at)
      ssh="" mode="push-in" cmd=""
      if i=$(_sync_host_index "$n"); then ssh="${_SH_SSH[$i]}"; mode="${_SH_MODE[$i]}"; cmd="${_SH_CMD[$i]}"; fi
      live_json=$(_sync_live_rows "$mirror" | jq -Rsc 'split("\n") | map(select(. != "") | split("\u001f")
                    | {session_id: .[0], model: .[1], ctx_pct: (.[2] | tonumber? // null), project: .[3]})')
      one=$(jq -cn --arg n "$n" --arg ssh "$ssh" --arg mode "$mode" --arg cmd "$cmd" --arg origin "$origin" \
        --arg synced "${synced:-0}" --arg s "${sessions:-0}" --arg r "${rows:-0}" --arg l "${last:-0}" \
        --argjson live "${live_json:-[]}" \
        '{name: $n, ssh: (if $ssh == "" then null else $ssh end), mode: $mode,
          cmd: (if $cmd == "" then null else $cmd end), origin: (if $origin == "" then null else $origin end),
          synced_at: (($synced | tonumber) | if . == 0 then null else . end),
          sessions: ($s | tonumber), history_rows: ($r | tonumber),
          last_active: (($l | tonumber) | if . == 0 then null else . end), live: $live}')
      rows_json+="$one"$'\n'
    done
    printf '%s' "$rows_json" | jq -s --arg name "$self_name" --arg id "$self_id" \
      '{self: {name: $name, id: $id}, hosts: .}'
    return 0
  fi

  local dim="$CLAUDII_CLR_DIM" rst="$CLAUDII_CLR_RESET" acc="$CLAUDII_CLR_ACCENT"
  printf '\n'
  printf "  ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${rst} ${acc}Sync${rst} ${dim}this claudii: %s · id %s${rst}\n" \
    "$self_name" "${self_id:0:8}"
  if (( ${#names[@]} == 0 )); then
    printf '\n'
    printf "    No hosts yet. Add one this machine can reach over ssh:\n"
    printf "      claudii sync add server server.example  ${dim}# pull its sessions here${rst}\n"
    printf "      claudii sync add laptop laptop --push   ${dim}# or send ours to it${rst}\n"
    printf "      claudii sync                            ${dim}# run every configured host${rst}\n"
    printf '\n'
    printf "    ${dim}The other side needs claudii too (and jq); --cmd PATH if it is not on the ssh PATH.${rst}\n"
    printf '\n'
    return 0
  fi
  printf '\n'
  local arrow ago lr sid model ctx proj
  for n in "${names[@]}"; do
    mirror="$cdir/hosts/$n"
    IFS=$'\t' read -r sessions rows last live <<< "$(_sync_mirror_stats "$mirror")"
    origin=$(_sync_kv "$mirror/state" origin); synced=$(_sync_kv "$mirror/state" synced_at)
    ssh="" mode="push-in"
    if i=$(_sync_host_index "$n"); then ssh="${_SH_SSH[$i]}"; mode="${_SH_MODE[$i]}"; fi
    case "$mode" in
      pull) arrow="⇣" ;; push) arrow="⇡" ;; both) arrow="⇅" ;; *) arrow="⇠" ;;
    esac
    if [[ "$synced" =~ ^[0-9]+$ ]]; then
      _fmt_rel $(( now - synced )); ago="synced ${_REL_FMT:-<1m} ago"
    elif [[ "$mode" == "push" ]]; then
      ago="pushes to it (its own status shows the result)"
    else
      ago="never synced"
    fi
    printf "    ${acc}%-14s${rst} %s %-5s ${dim}%-16s${rst} %s\n" "$n" "$arrow" "$mode" "${ssh:-—}" "$ago"
    if [[ -n "$origin" ]]; then
      lr=""
      if [[ "$last" =~ ^[0-9]+$ ]] && (( last > 0 )); then _fmt_rel $(( now - last )); lr=" · last active ${_REL_FMT:-<1m} ago"; fi
      printf "    ${dim}%-14s   %s · %s sessions · %s history rows%s${rst}\n" "" "$origin" "$sessions" "$rows" "$lr"
    fi
    if (( ${live:-0} > 0 )); then
      while IFS="$_SYNC_US" read -r sid model ctx proj; do
        [[ -n "$sid" ]] || continue
        printf "    %-14s   ${CLAUDII_CLR_GREEN}${CLAUDII_SYM_ACTIVE}${rst} %s ${dim}%s%s · %s${rst}\n" "" \
          "${model:-?}" "${ctx:+ctx $ctx% · }" "${proj:-?}" "${sid:0:8}"
      done <<< "$(_sync_live_rows "$mirror")"
    fi
  done
  printf '\n'
  printf "    ${dim}tokens · cost · trends · week · tools · repos … include these hosts (CLAUDII_LOCAL_ONLY=1: local only)${rst}\n"
  printf '\n'
  return 0
}

_sync_usage() {
  cat <<'EOF'
Usage: claudii sync [NAME…] [--quiet]        sync every (or the named) configured host
       claudii sync status [--json]           hosts, last sync, sessions, live sessions
       claudii sync add <name> <ssh-target> [--cmd PATH] [--pull|--push|--both]
       claudii sync rm <name>                 forget the host and drop its data
Plumbing (any byte pipe, e.g. a file carried by hand):
       claudii sync export [--full] [--no-refresh] > bundle   (request on stdin)
       claudii sync import <name> < bundle
       claudii sync state <name>              the request for <name>'s mirror
EOF
}

_cmd_sync() {
  _cfg_init
  # Bundles, mirrors and state hold other hosts' session data: owner-only,
  # like everything cc-statusline writes.
  umask 077
  case "${1:-}" in
    status|ls)       shift; _sync_status "$@" ;;
    add)             shift; _sync_add "$@" ;;
    rm|remove)       shift; _sync_rm "$@" ;;
    export)          shift; _sync_export "$@" ;;
    import)          shift; _sync_import "$@" ;;
    state)           shift; _sync_state_cmd "$@" ;;
    help|-h|--help)  _sync_usage ;;
    *)               _sync_run "$@" ;;
  esac
}
