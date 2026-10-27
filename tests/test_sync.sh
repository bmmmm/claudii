# touches: lib/cmd/sync.sh lib/insights_stream.sh lib/helpers.sh bin/claudii bin/claudii-insights lib/cmd/insights.sh
# test_sync.sh — claudii sync: two (three) claudii installs, one view.
#
# Every "host" is a separate HOME in the sandbox. A fake ssh (CLAUDII_SSH)
# drops the options and the target and runs the remote command under the
# HOME that target names — the same claudii, a different machine as far as
# the code can tell. The load-bearing assertions:
#   1. a pull carries the source's insights (aggregated from its transcripts
#      at export) and history, and tokens/cost on the receiver count them;
#      CLAUDII_LOCAL_ONLY=1 does not
#   2. the second sync is a delta: no unchanged session, only the new
#      history bytes — the mirror stays byte-identical to the source
#   3. the guards: a claudii never imports itself, one source never under two
#      names, a reset source (new id) replaces its mirror instead of mixing
#   4. push mode: the source sends, the receiver stores it under the
#      sender's sync.name
#   5. a non-bundle is refused without touching the mirror

_SY_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudii_sync.XXXXXX")
trap 'rm -rf "$_SY_ROOT" 2>/dev/null' EXIT

# _sy_home <name> — create a host: HOME with cache, config and a projects dir.
_sy_home() {
  mkdir -p "$_SY_ROOT/$1/.cache" "$_SY_ROOT/$1/.config" "$_SY_ROOT/$1/.claude/projects"
}
_sy_home src; _sy_home dst; _sy_home other

# claudii as host $1
_sy() {
  local h="$1"; shift
  HOME="$_SY_ROOT/$h" XDG_CACHE_HOME="$_SY_ROOT/$h/.cache" XDG_CONFIG_HOME="$_SY_ROOT/$h/.config" \
    CLAUDE_PROJECTS_DIR="$_SY_ROOT/$h/.claude/projects" CLAUDII_SSH="$_SY_ROOT/ssh" \
    bash "$CLAUDII_HOME/bin/claudii" "$@"
}

# Fake ssh: `ssh -o … -o … <target> <command>` runs <command> as host <target>.
cat > "$_SY_ROOT/ssh" <<EOF
#!/bin/bash
while [[ "\$1" == -o ]]; do shift 2; done
_t="\$1"; shift
export HOME="$_SY_ROOT/\$_t" XDG_CACHE_HOME="$_SY_ROOT/\$_t/.cache" XDG_CONFIG_HOME="$_SY_ROOT/\$_t/.config"
export CLAUDE_PROJECTS_DIR="$_SY_ROOT/\$_t/.claude/projects"
unset CLAUDII_CACHE_DIR
[[ -d "\$HOME" ]] || { echo "ssh: Could not resolve hostname \$_t" >&2; exit 255; }
cd "\$HOME" || exit 255
eval "\$*"
EOF
chmod +x "$_SY_ROOT/ssh"
_SY_CMD="$CLAUDII_HOME/bin/claudii"

_sy_iso() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
_SY_T=$(( $(date +%s) - 3600 ))

# _sy_session <host> <sid> <output_tokens> — one transcript with one response.
_sy_session() {
  mkdir -p "$_SY_ROOT/$1/.claude/projects/-work-$1"
  {
    printf '{"type":"user","timestamp":"%s","cwd":"/work/%s","sessionId":"%s","message":{"role":"user","content":"hi"}}\n' \
      "$(_sy_iso "$_SY_T")" "$1" "$2"
    printf '{"type":"assistant","timestamp":"%s","cwd":"/work/%s","sessionId":"%s","requestId":"req_%s","message":{"id":"msg_%s","role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
      "$(_sy_iso $(( _SY_T + 60 )))" "$1" "$2" "$2" "$2" "$3"
  } > "$_SY_ROOT/$1/.claude/projects/-work-$1/$2.jsonl"
}

_SY_SID_A="aaaaaaaa-0000-4000-8000-00000000000a"
_SY_SID_B="bbbbbbbb-0000-4000-8000-00000000000b"
_sy_session src "$_SY_SID_A" 700
_SY_SRC_C="$_SY_ROOT/src/.cache/claudii"
mkdir -p "$_SY_SRC_C"
hist_row "$_SY_SRC_C/history-2026-10.tsv" "$_SY_T" "Opus 5.5" "1.25" 30 10 "$_SY_SID_A" 10 700 900
_SY_MIR="$_SY_ROOT/dst/.cache/claudii/hosts/box"

# ── empty: onboarding, nothing to do ─────────────────────────────────────────
_out=$(_sy dst sync 2>&1); _rc=$?
assert_eq "sync without hosts: exit 0" "0" "$_rc"
assert_contains "sync without hosts: says how to add one" "claudii sync add" "$_out"

# ── argument contract ────────────────────────────────────────────────────────
_err=$(_sy dst sync --bogus 2>&1 >/dev/null); _rc=$?
assert_eq "sync --bogus: exit 2" "2" "$_rc"
assert_contains "sync --bogus: contract message" "claudii sync: unknown option: --bogus" "$_err"
_sy dst sync add 'bad/name' src >/dev/null 2>&1
assert_eq "sync add: a name with / is refused (exit 2)" "2" "$?"
_sy dst sync add status src >/dev/null 2>&1
assert_eq "sync add: a subcommand name is refused (exit 2)" "2" "$?"
_sy dst sync add box -oProxyCommand=x >/dev/null 2>&1
assert_eq "sync add: an ssh target that is an option is refused (exit 2)" "2" "$?"

# ── 1. pull ──────────────────────────────────────────────────────────────────
_sy dst sync add box src --cmd "$_SY_CMD" >/dev/null
assert_eq "sync add: host stored in config" "src" \
  "$(jq -r '.sync.hosts.box.ssh' "$_SY_ROOT/dst/.config/claudii/config.json")"

_out=$(_sy dst sync 2>&1); _rc=$?
assert_eq "pull: exit 0" "0" "$_rc"
assert_file_exists "pull: source session's insights cache mirrored" "$_SY_MIR/insights/$_SY_SID_A.json"
assert_eq "pull: history mirrored byte for byte" "0" \
  "$(cmp -s "$_SY_SRC_C/history-2026-10.tsv" "$_SY_MIR/history-2026-10.tsv"; echo $?)"
assert_contains "pull: status names the origin" "sessions" "$_out"

_tok=$(_sy dst tokens --days 7 --json 2>/dev/null | jq -r '.by_type.output')
assert_eq "tokens on the receiver count the source's session" "700" "$_tok"
_tok=$(CLAUDII_LOCAL_ONLY=1 _sy dst tokens --days 7 --json 2>/dev/null | jq -r '.by_type.output')
assert_eq "CLAUDII_LOCAL_ONLY=1: the mirror is left out" "0" "$_tok"

# history readers see the mirror (cost reads _collect_history_files)
_files=$(HOME="$_SY_ROOT/dst" XDG_CACHE_HOME="$_SY_ROOT/dst/.cache" bash -c '
  source "$CLAUDII_HOME/lib/helpers.sh"
  _collect_history_files "$XDG_CACHE_HOME/claudii"; printf "%s\n" "${_HIST_FILES[@]}"')
assert_contains "_collect_history_files includes the mirror" "hosts/box/history-2026-10.tsv" "$_files"
_files=$(CLAUDII_LOCAL_ONLY=1 HOME="$_SY_ROOT/dst" XDG_CACHE_HOME="$_SY_ROOT/dst/.cache" bash -c '
  source "$CLAUDII_HOME/lib/helpers.sh"
  _collect_history_files "$XDG_CACHE_HOME/claudii"; printf "%s\n" "${_HIST_FILES[@]+"${_HIST_FILES[@]}"}"')
assert_not_contains "_collect_history_files: CLAUDII_LOCAL_ONLY=1 skips the mirror" "hosts/box" "$_files"

# claudii session finds a mirrored session by id
_out=$(_sy dst session aaaaaaaa 2>&1); _rc=$?
assert_eq "session <id>: a mirrored session resolves" "0" "$_rc"

# ── 2. delta ─────────────────────────────────────────────────────────────────
# Age the source's caches past the cursor slack, then sync: nothing to carry.
touch -t "$(date -r $(( $(date +%s) - 7200 )) +%Y%m%d%H%M 2>/dev/null || date -d "@$(( $(date +%s) - 7200 ))" +%Y%m%d%H%M)" \
  "$_SY_SRC_C"/insights/*.json "$_SY_ROOT/src/.claude/projects/-work-src/"*.jsonl
_sy dst sync >/dev/null 2>&1
_req=$(_sy dst sync state box)
assert_contains "state: the request carries the cursor" "cursor " "$_req"
assert_contains "state: the request names the history file and its size" \
  "have history-2026-10.tsv $(wc -c < "$_SY_SRC_C/history-2026-10.tsv" | tr -d ' ')" "$_req"
_list=$(printf '%s\n' "$_req" | _sy src sync export --no-refresh | tar -tzf - 2>/dev/null)
assert_contains "delta: the export is a bundle (manifest present)" "manifest" "$_list"
assert_not_contains "delta: an unchanged session does not travel" "$_SY_SID_A" "$_list"
assert_not_contains "delta: an unchanged history file does not travel" "tail/history" "$_list"

hist_row "$_SY_SRC_C/history-2026-10.tsv" $(( _SY_T + 120 )) "Opus 5.5" "2.50" 35 12 "$_SY_SID_A" 20 900 950
_list=$(printf '%s\n' "$_req" | _sy src sync export --no-refresh | tar -tzf - 2>/dev/null)
assert_contains "delta: an appended history file travels as a tail" "tail/history-2026-10.tsv" "$_list"
_sy dst sync >/dev/null 2>&1
assert_eq "delta: the appended mirror is byte-identical to the source" "0" \
  "$(cmp -s "$_SY_SRC_C/history-2026-10.tsv" "$_SY_MIR/history-2026-10.tsv"; echo $?)"

_sy_session src "$_SY_SID_B" 300
_sy dst sync >/dev/null 2>&1
assert_file_exists "delta: a new source session arrives" "$_SY_MIR/insights/$_SY_SID_B.json"
_tok=$(_sy dst tokens --days 7 --json 2>/dev/null | jq -r '.by_type.output')
assert_eq "tokens: both mirrored sessions counted once" "1000" "$_tok"

# ── 3. guards ────────────────────────────────────────────────────────────────
_sy dst sync add twin src --cmd "$_SY_CMD" >/dev/null
_err=$(_sy dst sync twin 2>&1 >/dev/null); _rc=$?
assert_eq "same source under a second name: refused" "1" "$_rc"
assert_contains "same source under a second name: names the first" "already synced as box" "$_err"
assert_eq "same source under a second name: no mirror left behind" "1" \
  "$([[ -d "$_SY_ROOT/dst/.cache/claudii/hosts/twin" ]] && echo 0 || echo 1)"
_sy dst sync rm twin >/dev/null

_sy dst sync add me dst --cmd "$_SY_CMD" >/dev/null
_err=$(_sy dst sync me 2>&1 >/dev/null); _rc=$?
assert_eq "syncing this claudii itself: refused" "1" "$_rc"
assert_contains "syncing this claudii itself: says why" "this claudii itself" "$_err"
_sy dst sync rm me >/dev/null

_sy dst sync add gone nowhere --cmd "$_SY_CMD" >/dev/null
_err=$(_sy dst sync gone 2>&1 >/dev/null); _rc=$?
assert_eq "unreachable host: exit 1" "1" "$_rc"
assert_contains "unreachable host (ssh exit 255): says how to check" "ssh to nowhere failed — check: ssh nowhere true" "$_err"
_sy dst sync rm gone >/dev/null

# A wrong --cmd: the remote shell exits 127, and the message says which key to fix.
_sy dst sync add typo src --cmd /nonexistent/claudi >/dev/null
_err=$(_sy dst sync typo 2>&1 >/dev/null); _rc=$?
assert_eq "wrong --cmd: exit 1" "1" "$_rc"
assert_contains "wrong --cmd (exit 127): names the path and the fix" \
  '"/nonexistent/claudi" not found on src — fix: claudii config set sync.hosts.typo.cmd PATH' "$_err"
_sy dst sync rm typo >/dev/null

# The source starts over (new cache → new id): its mirror is replaced whole.
rm -f "$_SY_SRC_C/host-id"
_out=$(_sy dst sync box 2>&1); _rc=$?
assert_eq "source with a new id: sync still succeeds" "0" "$_rc"
assert_contains "source with a new id: says it starts over" "different source" "$_out"
assert_eq "source with a new id: state carries the new id" "$(cat "$_SY_SRC_C/host-id")" \
  "$(sed -n 's/^origin_id=//p' "$_SY_MIR/state")"
_tok=$(_sy dst tokens --days 7 --json 2>/dev/null | jq -r '.by_type.output')
assert_eq "source with a new id: nothing counted twice" "1000" "$_tok"

# ── 5. not a bundle ──────────────────────────────────────────────────────────
_before=$(cat "$_SY_MIR/state")
_err=$(printf 'hello\n' | _sy dst sync import box 2>&1 >/dev/null); _rc=$?
assert_eq "import of a non-bundle: exit 1" "1" "$_rc"
assert_eq "import of a non-bundle: mirror untouched" "$_before" "$(cat "$_SY_MIR/state")"
_left=""
for _d in "$_SY_ROOT/dst/.cache/claudii/hosts"/.[!.]*; do [[ -e "$_d" ]] && _left+="${_d##*/} "; done
assert_eq "import of a non-bundle: no incoming dir left behind" "" "$_left"

# ── 4. push ──────────────────────────────────────────────────────────────────
# sync.name ends up in the remote command line — refused locally, before ssh.
_sy other config set sync.name 'x;touch pwned' >/dev/null
_sy other sync add hub dst --cmd "$_SY_CMD" --push >/dev/null
_sy other sync hub >/dev/null 2>&1
assert_eq "push: a sync.name with shell metacharacters is refused" "1" "$?"
assert_eq "push: ... and nothing ran on the receiver" "1" \
  "$([[ -e "$_SY_ROOT/dst/pwned" || -e "$_SY_ROOT/other/pwned" ]] && echo 0 || echo 1)"
_sy_session other "cccccccc-0000-4000-8000-00000000000c" 50
_sy other config set sync.name laptop >/dev/null
_out=$(_sy other sync 2>&1); _rc=$?
assert_eq "push: exit 0" "0" "$_rc"
assert_file_exists "push: the receiver stores it under the sender's sync.name" \
  "$_SY_ROOT/dst/.cache/claudii/hosts/laptop/insights/cccccccc-0000-4000-8000-00000000000c.json"
_json=$(_sy dst sync status --json)
assert_eq "status --json: a pushed-in host is listed" "push-in" \
  "$(jq -r '.hosts[] | select(.name == "laptop") | .mode' <<< "$_json")"
assert_eq "status --json: session count per host" "2" \
  "$(jq -r '.hosts[] | select(.name == "box") | .sessions' <<< "$_json")"
_tok=$(_sy dst tokens --days 7 --json 2>/dev/null | jq -r '.by_type.output')
assert_eq "tokens: pulled + pushed hosts summed" "1050" "$_tok"

# ── rm ───────────────────────────────────────────────────────────────────────
_sy dst sync rm box >/dev/null
assert_eq "rm: config entry gone" "null" \
  "$(jq -r '.sync.hosts.box' "$_SY_ROOT/dst/.config/claudii/config.json")"
assert_eq "rm: mirror gone" "1" "$([[ -d "$_SY_MIR" ]] && echo 0 || echo 1)"
_sy dst sync rm box >/dev/null 2>&1
assert_eq "rm: unknown host exits 1" "1" "$?"

unset _SY_CMD _SY_T _SY_SID_A _SY_SID_B _SY_SRC_C _SY_MIR _out _err _rc _tok _req _list _files _json _before _left _d
