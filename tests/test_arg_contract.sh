# touches: bin/claudii lib/cmd/insights.sh lib/cmd/skills-cost.sh lib/cmd/week.sh lib/cmd/cost.sh
# test_arg_contract.sh — one argument contract, walked across the whole CLI.
#
# THE CONTRACT
#   An unknown option exits 2 and prints  `claudii <cmd>: unknown option: <arg>`
#   on stderr. rc 2 means "the CLI could not accept your arguments, nothing
#   ran"; rc 1 stays "the command understood you and then failed".
#
# Before this, `claudii <cmd> --bogus` answered 0, 1 or 2 depending on which
# command you asked, under three different message prefixes — and `cost --bogus`
# printed nothing at all and exited 0.
#
# The command list is DERIVED from the dispatch case in bin/claudii, exactly the
# way test_docs.sh derives it. A hand-written array is what let `claudii restart`
# sit in the docs for years with no dispatch arm behind it; here it would let a
# newly added command quietly skip the contract.

_AC_CLI="$CLAUDII_HOME/bin/claudii"

# ── Commands not yet under the contract ──────────────────────────────────────
# Their argument parsers live in lib/cmd/{system,sessions,display,config,omlx,
# vpnii,vibemap,perf}.sh, outside the change that introduced this gate. The list
# is a RATCHET, not an excuse: the loop below asserts that each of these still
# FAILS the contract, so converting one without deleting it from here turns this
# test red. It can only shrink.
_AC_PENDING=" cc-statusline claudestatus config dashboard gc insomnii omlx pin search session session-dashboard sessionline sessions status unpin vibemap vpnii "

# Two arms exec into another command, so the message names the TARGET. That is
# the honest answer for an alias — `claudii layers` IS `claudii explain`.
_ac_expect_name() {
  case "$1" in
    layers|components) printf 'explain' ;;
    *)                 printf '%s' "$1" ;;
  esac
}

# ── Derive the command list from the dispatch case ───────────────────────────
_AC_BLOCK=$(LC_ALL=C sed -n '/^  # System commands$/,/^esac$/p' "$_AC_CLI")
_AC_CMDS=$(LC_ALL=C printf '%s\n' "$_AC_BLOCK" \
  | LC_ALL=C sed -n 's/^  \([a-z0-9|_-][a-z0-9|_-]*\)).*/\1/p' \
  | tr '|' '\n' | LC_ALL=C sort -u)
assert_eq "dispatch case is parseable (>= 30 commands)" "0" \
  "$([ "$(LC_ALL=C printf '%s\n' "$_AC_CMDS" | LC_ALL=C grep -c .)" -ge 30 ] && echo 0 || echo 1)"

# ── Probe harness ────────────────────────────────────────────────────────────
# Every invocation gets its own HOME/XDG/cache, and a PATH whose first entry
# stubs out `claude`, `git` and `brew`: `resume`/`search`/`sessions --resume`
# would otherwise exec the real CLI, and `update` would `git pull` this very
# checkout. The stubs are the safety net for a REGRESSION — under the contract
# none of those handlers is reached at all.
_AC_STUB=$(mktemp -d "${TMPDIR:-/tmp}/claudii_ac_stub.XXXXXX")
for _t in claude git brew; do
  printf '#!/bin/bash\nexit 0\n' > "$_AC_STUB/$_t"
  chmod +x "$_AC_STUB/$_t"
done

# _ac_probe <cmd> -> sets _AC_RC and _AC_ERR (stderr only)
_ac_probe() {
  local _sb
  _sb=$(mktemp -d "${TMPDIR:-/tmp}/claudii_ac.XXXXXX")
  mkdir -p "$_sb/home" "$_sb/cfg" "$_sb/cache"
  # CLAUDII_HOME is pinned: it is exported by tests/run.sh, and without it a
  # worktree's bin/claudii would happily source another checkout's lib/.
  _AC_ERR=$(HOME="$_sb/home" XDG_CONFIG_HOME="$_sb/cfg" XDG_CACHE_HOME="$_sb/cache" \
            CLAUDII_CACHE_DIR="$_sb/cache/claudii" CLAUDII_HOME="$CLAUDII_HOME" \
            PATH="$_AC_STUB:$PATH" \
            bash "$_AC_CLI" "$1" --bogus 2>&1 >/dev/null)
  _AC_RC=$?
  rm -rf "$_sb"
}

# ── The walk ─────────────────────────────────────────────────────────────────
_ac_covered=0
for _ac_cmd in $_AC_CMDS; do
  _ac_probe "$_ac_cmd"
  _ac_want="claudii $(_ac_expect_name "$_ac_cmd"): unknown option: --bogus"
  case "$_AC_PENDING" in
    *" $_ac_cmd "*)
      # Ratchet: a pending command must still MISS the contract. When someone
      # converts it, this goes red until they delete it from _AC_PENDING.
      _ac_hit=1
      [[ "$_AC_RC" == "2" ]] && grep -qF -- "$_ac_want" <<< "$_AC_ERR" && _ac_hit=0
      assert_eq "pending (not yet under the contract): $_ac_cmd" "1" "$_ac_hit"
      ;;
    *)
      _ac_covered=$(( _ac_covered + 1 ))
      assert_eq "$_ac_cmd --bogus: exit 2" "2" "$_AC_RC"
      assert_contains "$_ac_cmd --bogus: contract message" "$_ac_want" "$_AC_ERR"
      ;;
  esac
done

# The gate must not pass by covering nothing: 27 commands were converted, so a
# refactor that quietly drops arms out of the walk shows up here.
assert_eq "the contract covers at least 25 dispatched commands" "0" \
  "$([ "$_ac_covered" -ge 25 ] && echo 0 || echo 1)"

# Every name in _AC_PENDING must still be a real dispatch arm — otherwise a
# renamed or deleted command leaves a stale exemption behind that silently
# excuses whatever takes its name next.
_ac_stale=""
for _ac_p in $_AC_PENDING; do
  LC_ALL=C grep -qx -- "$_ac_p" <<< "$_AC_CMDS" || _ac_stale="$_ac_stale $_ac_p"
done
assert_eq "no stale entries in the pending list" "" "$_ac_stale"

# ── stdout stays clean ───────────────────────────────────────────────────────
# The error belongs on stderr: `claudii tokens --bogus --json | jq` must not be
# handed a usage line to parse.
_AC_SB=$(mktemp -d "${TMPDIR:-/tmp}/claudii_ac_out.XXXXXX")
mkdir -p "$_AC_SB/home" "$_AC_SB/cfg" "$_AC_SB/cache"
_ac_stdout=$(HOME="$_AC_SB/home" XDG_CONFIG_HOME="$_AC_SB/cfg" XDG_CACHE_HOME="$_AC_SB/cache" \
  CLAUDII_CACHE_DIR="$_AC_SB/cache/claudii" CLAUDII_HOME="$CLAUDII_HOME" \
  bash "$_AC_CLI" tokens --bogus 2>/dev/null)
assert_eq "unknown option writes nothing to stdout" "" "$_ac_stdout"

# ── A handler must RETURN, not exit ──────────────────────────────────────────
# lib/cmd/*.sh are sourced into bin/claudii; an `exit 2` in a parser would tear
# the process down mid-render (and skip _spinner_stop). Proof is the line after
# the failing call: under `exit` the subshell dies and SURVIVED never prints.
_ac_ret=$(bash -c '
  source "$CLAUDII_HOME/lib/visual.sh"
  source "$CLAUDII_HOME/lib/spinner.sh"
  source "$CLAUDII_HOME/lib/helpers.sh"
  source "$CLAUDII_HOME/lib/render.sh"
  source "$CLAUDII_HOME/lib/cmd/insights.sh"
  source "$CLAUDII_HOME/lib/cmd/cost.sh"
  source "$CLAUDII_HOME/lib/cmd/week.sh"
  _cmd_cost --bogus >/dev/null 2>&1; printf "COST rc=%s\n" "$?"
  _cmd_week --bogus >/dev/null 2>&1; printf "WEEK rc=%s\n" "$?"
  _insights_window tokens --bogus >/dev/null 2>&1; printf "IW rc=%s\n" "$?"
  printf "SURVIVED\n"
' 2>&1)
assert_contains "sourced parser: cost returns 2 instead of exiting" "COST rc=2" "$_ac_ret"
assert_contains "sourced parser: week returns 2 instead of exiting" "WEEK rc=2" "$_ac_ret"
assert_contains "sourced parser: _insights_window returns 2"       "IW rc=2"   "$_ac_ret"
assert_contains "sourced parser: the shell is still alive afterwards" "SURVIVED" "$_ac_ret"

# ── The dispatcher's no-argument gate is not a hand-maintained fiction ───────
# Every command whose dispatch arm calls its handler with NO arguments must be
# named in the guard's case above the dispatch — that is the only thing that
# can reject an extra token for them. Derived, so a new no-arg command fails
# here on the commit that adds it rather than silently swallowing flags.
_AC_NOARG=$(LC_ALL=C printf '%s\n' "$_AC_BLOCK" \
  | LC_ALL=C sed -n 's/^  \([a-z0-9|_-][a-z0-9|_-]*\))  *_cmd_[a-z0-9_]*  *;;.*/\1/p' \
  | tr '|' '\n' | LC_ALL=C sort -u)
assert_eq "no-arg dispatch arms are derivable" "0" \
  "$([ "$(LC_ALL=C printf '%s\n' "$_AC_NOARG" | LC_ALL=C grep -c .)" -ge 8 ] && echo 0 || echo 1)"
_AC_GUARD=$(LC_ALL=C sed -n '/^# Commands that take no arguments at all/,/^esac$/p' "$_AC_CLI")
_ac_ungated=""
for _ac_n in $_AC_NOARG; do
  LC_ALL=C grep -qF -- "|$_ac_n|" <<< "|$(LC_ALL=C sed -n 's/^  \(.*\))$/\1/p' <<< "$_AC_GUARD")|" \
    || _ac_ungated="$_ac_ungated $_ac_n"
done
assert_eq "every no-arg command is named in the dispatcher's no-arg gate" "" "$_ac_ungated"

rm -rf "$_AC_STUB" "$_AC_SB"
unset _AC_CLI _AC_PENDING _AC_BLOCK _AC_CMDS _AC_STUB _AC_SB _AC_RC _AC_ERR _AC_NOARG _AC_GUARD
unset _ac_covered _ac_cmd _ac_want _ac_hit _ac_stale _ac_p _ac_stdout _ac_ret
unset _ac_n _ac_ungated _t
