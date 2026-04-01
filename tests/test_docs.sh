# touches: man/man1/claudii.1 completions/_claudii bin/claudii
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
MAN_COMMANDS=(on off status cc-statusline sessions sessions-inactive cost trends config search restart update layers version doctor watch agents changelog claudestatus session-dashboard dashboard)
ALL_COMMANDS=(on off status cc-statusline sessions sessions-inactive cost trends config search restart update layers version doctor watch agents changelog claudestatus session-dashboard dashboard help)

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
