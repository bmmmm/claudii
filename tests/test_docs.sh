# touches: man/man1/claudii.1 completions/_claudii bin/claudii CHANGELOG.md
# test_docs.sh — man page + autocomplete stay in sync with bin/claudii

MAN="$CLAUDII_HOME/man/man1/claudii.1"
COMP="$CLAUDII_HOME/completions/_claudii"
CLI="$CLAUDII_HOME/bin/claudii"

# ── Version consistency ──
# Single source of truth: VERSION= in bin/claudii
BIN_VERSION=$(grep '^VERSION=' "$CLI" | head -1 | tr -d '"' | cut -d= -f2)
assert_contains "man page version matches bin/claudii" "$BIN_VERSION" "$(cat "$MAN")"

# The GitHub Pages landing page renders a mock overview with a version in it.
# Nothing bumped it, so it sat at v0.25.0 against a 0.26.0 tree. scripts/release.sh
# now rewrites it; this is the gate that says so when it does not.
assert_contains "docs/index.html version matches bin/claudii" ">v$BIN_VERSION<" \
  "$(cat "$CLAUDII_HOME/docs/index.html")"

# ── Command names, derived from the dispatcher ──────────────────────────────
# This used to be two hand-typed arrays checked with a bare substring search
# against the whole file. That is vacuous in both directions: `restart` was in
# the array, in the man page and in the completions, and passed "bin/claudii
# handles: restart" for years — because the word appears in usage() text, while
# the dispatch case had no arm for it and `claudii restart` answered "Unknown
# command". The segment list below was converted to derivation for the same
# reason; this is the other half.
#
# Derived from the main dispatch case (the one after the alias-expansion case),
# and matched on anchors: a `name)` arm, a `'name:` completion entry, a man-page
# line that starts with the name.
_DISPATCH_BLOCK=$(LC_ALL=C sed -n '/^  # System commands$/,/^esac$/p' "$CLI")
DISPATCHED=$(LC_ALL=C printf '%s\n' "$_DISPATCH_BLOCK" \
  | LC_ALL=C sed -n 's/^  \([a-z0-9|_-][a-z0-9|_-]*\)).*/\1/p' \
  | tr '|' '\n' | LC_ALL=C sort -u)
assert_eq "dispatch case is parseable (>= 30 commands)" "0" \
  "$([ "$(LC_ALL=C printf '%s\n' "$DISPATCHED" | LC_ALL=C grep -c .)" -ge 30 ] && echo 0 || echo 1)"

# Shorthand aliases from the first case block — real entry points a user can
# type, so completions may list them, but they are not dispatch targets.
_ALIAS_BLOCK=$(LC_ALL=C sed -n '/^# Shorthand aliases/,/^esac$/p' "$CLI")
ALIASES=$(LC_ALL=C printf '%s\n' "$_ALIAS_BLOCK" \
  | LC_ALL=C sed -n 's/^  \([a-z0-9]*\)).*/\1/p' | LC_ALL=C sort -u)

# Deliberate exemptions. Anything NOT listed here has to be documented — a new
# command forces the choice instead of defaulting to undocumented.
#   help/-h/--help : the man page is the help
#   42             : easter egg
#   sessionline, install-sessionline, components : backwards-compat shims
_UNDOCUMENTED_OK=" help --help -h 42 sessionline install-sessionline components "

# The man page marks commands up in several legitimate roff forms — `.B name`,
# `.BR "name " [on|off]`, `.BI "pin " session-id`, `.SS VPN State (vpnii)`.
# Chasing that with ever-longer regexes is how a gate ends up matching nothing
# and reporting everything as fine (the first draft of this check used BRE
# `\|`, which BSD grep does not support, and "documented" silently became
# "never matched"). Normalise instead: take the macro lines, drop the macro
# name and the roff punctuation, and look for the command as a whole word.
# The trailing `s/$/ /` is load-bearing: ".B changelog" normalises to
# " changelog" with nothing after it, and a " changelog " needle would miss the
# very lines that document the command.
_MAN_WORDS=$(LC_ALL=C grep -E '^\.[A-Z]+ ' "$MAN" | LC_ALL=C sed 's/^\.[A-Z]*//; s/[".,()]/ /g; s/$/ /')
assert_eq "man page macro lines are parseable" "0" \
  "$([ "$(LC_ALL=C printf '%s\n' "$_MAN_WORDS" | LC_ALL=C grep -c .)" -ge 100 ] && echo 0 || echo 1)"

for cmd in $DISPATCHED; do
  case "$_UNDOCUMENTED_OK" in *" $cmd "*) continue ;; esac
  assert_contains "man page documents: $cmd" " $cmd " "$_MAN_WORDS"
  assert_eq "autocomplete lists: $cmd" "0" \
    "$(LC_ALL=C grep -q "'$cmd:" "$COMP" && echo 0 || echo 1)"
done

# Reverse direction — the one that would have caught `restart`: every command
# the completions advertise must actually be reachable, as a dispatch arm or as
# a shorthand alias.
_KNOWN=" $(LC_ALL=C printf '%s %s' "$DISPATCHED" "$ALIASES" | tr '\n' ' ') "
# Only the top-level `commands=( … )` array — the file also completes flags and
# per-command subcommands in the same 'name:description' form, and those are not
# dispatch targets.
_COMP_NAMES=$(LC_ALL=C sed -n '/^ *commands=(/,/^ *)/p' "$COMP" \
  | LC_ALL=C sed -n "s/^ *'\([a-z0-9-]*\):.*/\1/p" | LC_ALL=C sort -u)
assert_eq "completion command list is parseable (>= 30 entries)" "0" \
  "$([ "$(LC_ALL=C printf '%s\n' "$_COMP_NAMES" | LC_ALL=C grep -c .)" -ge 30 ] && echo 0 || echo 1)"
_unreachable=""
for cmd in $_COMP_NAMES; do
  case "$_KNOWN" in *" $cmd "*) ;; *) _unreachable="$_unreachable $cmd" ;; esac
done
assert_eq "every completion entry is reachable in bin/claudii" "" "$_unreachable"
# _UNDOCUMENTED_OK and DISPATCHED stay in scope — the overview-list check below
# uses both.
unset _DISPATCH_BLOCK _ALIAS_BLOCK _KNOWN _COMP_NAMES _unreachable _MAN_WORDS

# config subcommands
CONFIG_SUBS=(get set reset export import theme)
for sub in "${CONFIG_SUBS[@]}"; do
  assert_contains "man page documents: config $sub"    "$sub"  "$(cat "$MAN")"
  assert_contains "autocomplete lists: config $sub"    "$sub"  "$(cat "$COMP")"
done

# Removed commands must NOT appear as implemented commands
assert_eq "toggle removed from bin/claudii" "" \
  "$(grep -E '^\s+toggle\)' "$CLI" || true)"

# ── Sessionline segments documented in man page ─────────────────────────────
# The list is read out of the dispatch case in bin/claudii-cc-statusline, not
# retyped here. It used to be a hand-maintained array, which made this gate
# vacuous for exactly the segments nobody remembered to add to it: bumpii,
# omlx and proxy went undocumented that way, two of them shipping in the
# default layout. Derived, a new segment fails the gate on the commit that
# adds it.
#
# The assertion is anchored to the table row (name + TAB), not a bare
# substring — "dir" or "ci" occur all over the page, so a substring check
# passes for a segment that has no row at all.
SL_SEGMENTS=$(LC_ALL=C sed -n '/case "$_seg" in/,/^    esac$/p' "$CLAUDII_HOME/bin/claudii-cc-statusline" \
  | LC_ALL=C sed -n 's/^      \([a-z0-9][a-z0-9-]*\)).*/\1/p')
assert_eq "statusline segment list is derivable from the dispatch case" "0" \
  "$([ "$(printf '%s\n' "$SL_SEGMENTS" | grep -c .)" -ge 20 ] && echo 0 || echo 1)"
for seg in $SL_SEGMENTS; do
  assert_eq "man page has a table row for segment: $seg" "0" \
    "$(LC_ALL=C grep -q "^${seg}$(printf '\t')" "$MAN" && echo 0 || echo 1)"
done
unset seg

# defaults.json must be readable JSON (basic sanity)
assert_eq "config/defaults.json is valid JSON" "0" \
  "$(jq empty "$CLAUDII_HOME/config/defaults.json" >/dev/null 2>&1; echo $?)"

# ── Static lint: (( var++ )) regression ─────────────────────────────────────
# Regression: standalone post-increment (( var++ )) exits 1 under set -e when
# var==0 on bash 5.x (Ubuntu CI). All occurrences must use pre-increment (( ++var )).
# Excludes for-loop increments: for (( i=0; i<n; i++ )) — those are safe.
_lint_postinc=$(grep -rn '^\s*(( [a-zA-Z_][a-zA-Z_0-9]* *++ ))' \
  "$CLAUDII_HOME/lib/" "$CLAUDII_HOME/bin/claudii" 2>/dev/null || true)
assert_eq "lint: no standalone (( var++ )) post-increments in lib/ or bin/claudii" \
  "" "$_lint_postinc"
unset _lint_postinc

# ── Overview quick reference covers every documented command ────────────────
# The grouped list in _ov_render_commands is the first thing a bare `claudii`
# shows, and nothing pinned it: `week` and `repos` both shipped complete in the
# man page, the completions and the dispatch (all gated above) while never
# appearing there. Gated against MAN_COMMANDS, which CLAUDE.md already makes
# the single place a new command gets registered — so adding one now forces a
# decision: put it in a group, or name it here as deliberately out.
#
# Matching is on the "·"-separated items, not a substring: "session" occurs
# inside "session-dashboard", and a substring check would pass for a command
# that has no entry at all.
OV_EXEMPT=(dashboard sessions sessions-inactive layers)   # aliases; targets are listed
_OV_FN=$(LC_ALL=C sed -n '/^_ov_render_commands()/,/^}/p' "$CLAUDII_HOME/lib/cmd/overview.sh")
_OV_ITEMS=$(printf '%s\n' "$_OV_FN" \
  | LC_ALL=C sed -n 's/.*"\([^"]*\)"[[:space:]]*$/\1/p' \
  | LC_ALL=C tr '·' '\n' | LC_ALL=C tr -d ' ')
assert_eq "overview command list is extractable" "0" \
  "$([ "$(printf '%s\n' "$_OV_ITEMS" | grep -c .)" -ge 25 ] && echo 0 || echo 1)"
for cmd in $DISPATCHED; do
  case "$_UNDOCUMENTED_OK" in *" $cmd "*) continue ;; esac
  _skip=0
  for _x in "${OV_EXEMPT[@]}"; do [[ "$cmd" == "$_x" ]] && _skip=1; done
  (( _skip )) && continue
  assert_eq "bare claudii lists command: $cmd" "0" \
    "$(LC_ALL=C grep -qx -- "$cmd" <<< "$_OV_ITEMS" && echo 0 || echo 1)"
done
unset _OV_FN _OV_ITEMS _skip _x

# ── Static lint: `producer | grep -q` SIGPIPE regression ────────────────────
# `producer | grep -q` returns 141 under `pipefail`: grep -q exits on the match,
# the producer's next write gets EPIPE. It fires when the match lands on an
# early LINE and more than one pipe buffer (64 KiB) still follows — bash
# builtins included; only a single long line is immune (grep must read to the
# line end first). A *present* value then reads as absent. Use a here-string:
#   producer | grep -q X   →   grep -q X <<< "$var"
# Comment lines are exempt (the pattern gets named in prose).
# The prefix alternation is not decoration: this gate first shipped as
# '|[[:space:]]*grep -q' and promptly missed `| LC_ALL=C grep -qx` written into
# this very file, which then failed one leg in four under parallel load — the
# flaky-looking shape SIGPIPE always takes.
_lint_grepq=$(grep -rnE '\|[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*grep -q' \
  "$CLAUDII_HOME/lib/" "$CLAUDII_HOME/bin/" "$CLAUDII_HOME/tests/" 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
assert_eq "lint: no pipe-into-grep-quiet pipelines in lib/, bin/ or tests/" \
  "" "$_lint_grepq"
unset _lint_grepq

# ── CHANGELOG hygiene: [Unreleased] block ───────────────────────────────────
# Entries get appended over weeks; a second "### Added/Changed/Fixed" header in
# the unreleased block ships duplicated sections into the tagged release notes.
_unrel=$(awk '/^## \[Unreleased\]/{f=1;next} f&&/^## /{exit} f' "$CLAUDII_HOME/CHANGELOG.md")
_dup_headers=$(echo "$_unrel" | grep '^### ' | sort | uniq -d)
assert_eq "CHANGELOG [Unreleased] has no duplicate ### section headers" "" "$_dup_headers"
_unknown_headers=$(echo "$_unrel" | grep '^### ' | grep -vE '^### (Added|Changed|Fixed|Removed|Deprecated|Security)$' || true)
assert_eq "CHANGELOG [Unreleased] uses only Keep-a-Changelog section names" "" "$_unknown_headers"
unset _unrel _dup_headers _unknown_headers
