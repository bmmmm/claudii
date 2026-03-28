# test_docs.sh — man page + autocomplete stay in sync with bin/claudii

MAN="$CLAUDII_HOME/man/man1/claudii.1"
COMP="$CLAUDII_HOME/completions/_claudii"
CLI="$CLAUDII_HOME/bin/claudii"

# Top-level commands that must appear in both man page and autocomplete
# (excludes backwards-compat aliases like install-sessionline and easter eggs like 42)
# help is not documented separately — the man page itself is the help
MAN_COMMANDS=(on off status show sessionline config debug search metrics restart about version)
ALL_COMMANDS=(on off status show sessionline config debug search metrics restart about version help)

for cmd in "${MAN_COMMANDS[@]}"; do
  assert_contains "man page documents: $cmd"     "$cmd"  "$(cat "$MAN")"
done
for cmd in "${ALL_COMMANDS[@]}"; do
  assert_contains "autocomplete lists: $cmd"     "$cmd"  "$(cat "$COMP")"
  assert_contains "bin/claudii handles: $cmd"    "$cmd"  "$(cat "$CLI")"
done

# config subcommands
CONFIG_SUBS=(get set reset export import)
for sub in "${CONFIG_SUBS[@]}"; do
  assert_contains "man page documents: config $sub"    "$sub"  "$(cat "$MAN")"
  assert_contains "autocomplete lists: config $sub"    "$sub"  "$(cat "$COMP")"
done

# Removed commands must NOT appear as implemented commands
assert_eq "toggle removed from bin/claudii" "" \
  "$(grep -E '^\s+toggle\)' "$CLI" || true)"
assert_eq "update removed from man page" "" \
  "$(grep -E '^\.B update$' "$MAN" || true)"
assert_eq "update removed from autocomplete" "" \
  "$(grep 'update:Pull' "$COMP" || true)"
