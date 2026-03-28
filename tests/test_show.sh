# test_show.sh — claudii show is removed; use config set statusline.models instead

# Setup: use project-local temp config dir
export XDG_CONFIG_HOME="$CLAUDII_HOME/tmp/test_show"
rm -rf "$XDG_CONFIG_HOME/claudii"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

# show is removed — should exit 1 with redirect message
output=$(bash "$CLAUDII_HOME/bin/claudii" show 2>&1 || true)
assert_contains "show removed: shows config redirect message" "config set" "$output"

# Use config set to manage models instead
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet" >/dev/null 2>&1
stored=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config set statusline.models works" "opus,sonnet" "$stored"

# Reset to defaults
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus,sonnet,haiku" >/dev/null 2>&1

# Cleanup
rm -rf "$XDG_CONFIG_HOME"
unset XDG_CONFIG_HOME
