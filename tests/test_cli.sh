# test_cli.sh — claudii CLI E2E tests

# version
_bin_version=$(grep '^VERSION=' "$CLAUDII_HOME/bin/claudii" | head -1 | tr -d '"' | cut -d= -f2)
output=$(bash "$CLAUDII_HOME/bin/claudii" version 2>&1)
assert_contains "claudii version shows version" "v$_bin_version" "$output"
unset _bin_version

# help
output=$(bash "$CLAUDII_HOME/bin/claudii" help 2>&1)
assert_contains "help shows usage" "claudii" "$output"
assert_contains "help lists status command" "status" "$output"
assert_contains "help lists config command" "config" "$output"
assert_contains "help lists search command" "search" "$output"

# unknown command
output=$(bash "$CLAUDII_HOME/bin/claudii" nonexistent 2>&1 || true)
assert_contains "unknown command shows error" "Unknown command" "$output"
