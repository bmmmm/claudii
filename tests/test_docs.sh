# touches: man/man1/claudii.1 completions/_claudii bin/claudii CHANGELOG.md
# test_docs.sh — man page + autocomplete stay in sync with bin/claudii

MAN="$CLAUDII_HOME/man/man1/claudii.1"
COMP="$CLAUDII_HOME/completions/_claudii"
CLI="$CLAUDII_HOME/bin/claudii"

# ── Version consistency ──
# Single source of truth: VERSION= in bin/claudii
BIN_VERSION=$(grep '^VERSION=' "$CLI" | head -1 | tr -d '"' | cut -d= -f2)
assert_contains "man page version matches bin/claudii" "$BIN_VERSION" "$(cat "$MAN")"

# Top-level commands that must appear in both man page and autocomplete
# (excludes backwards-compat shims like sessionline/components, and easter eggs like 42)
# help is not documented separately — the man page itself is the help
MAN_COMMANDS=(on off status cc-statusline insomnii sessions sessions-inactive session pin unpin cost week trends tokens perf tools repos limits skills-cost config search restart update explain layers version doctor agents changelog claudestatus session-dashboard dashboard vibemap omlx vpnii gc resume cache)
ALL_COMMANDS=(on off status cc-statusline insomnii sessions sessions-inactive session pin unpin cost week trends tokens perf tools repos limits skills-cost config search restart update explain layers version doctor agents changelog claudestatus session-dashboard dashboard vibemap omlx vpnii gc resume cache help)

for cmd in "${MAN_COMMANDS[@]}"; do
  assert_contains "man page documents: $cmd"     "$cmd"  "$(cat "$MAN")"
done
for cmd in "${ALL_COMMANDS[@]}"; do
  assert_contains "autocomplete lists: $cmd"     "$cmd"  "$(cat "$COMP")"
  assert_contains "bin/claudii handles: $cmd"    "$cmd"  "$(cat "$CLI")"
done

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
for cmd in "${MAN_COMMANDS[@]}"; do
  _skip=0
  for _x in "${OV_EXEMPT[@]}"; do [[ "$cmd" == "$_x" ]] && _skip=1; done
  (( _skip )) && continue
  assert_eq "bare claudii lists command: $cmd" "0" \
    "$(printf '%s\n' "$_OV_ITEMS" | LC_ALL=C grep -qx -- "$cmd" && echo 0 || echo 1)"
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
_lint_grepq=$(grep -rn '|[[:space:]]*grep -q' \
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
