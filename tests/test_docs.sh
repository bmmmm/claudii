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

# ── Sessionline segments documented in man page ─────────────────────────────
# Every segment in the layout loop must have a row in the man page segments table.
# Update this list whenever a new segment is added to bin/claudii-sessionline.
SL_SEGMENTS=(
  model context-bar rate-5h rate-7d cost tokens lines-changed duration
  api-duration burn-eta delta-5h delta-7d cache-create session-name
  worktree agent ruler claude-status
)
for seg in "${SL_SEGMENTS[@]}"; do
  assert_contains "man page documents segment: $seg" "$seg" "$(cat "$MAN")"
done

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
