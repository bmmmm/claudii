# test_show.sh — claudii show model E2E tests

# Setup: use project-local temp config dir
export XDG_CONFIG_HOME="$CLAUDII_HOME/tmp/test_show"
rm -rf "$XDG_CONFIG_HOME/claudii"
mkdir -p "$XDG_CONFIG_HOME/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$XDG_CONFIG_HOME/claudii/config.json"

# show model — read default
output=$(bash "$CLAUDII_HOME/bin/claudii" show model 2>&1)
assert_contains "show model shows current models" "opus,sonnet,haiku" "$output"

# show model set (replace)
bash "$CLAUDII_HOME/bin/claudii" show model opus sonnet >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" show model 2>&1)
assert_eq "show model set replaces models" "Angezeigte Modelle: opus,sonnet" "$output"

# show model add
bash "$CLAUDII_HOME/bin/claudii" show model add haiku >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" show model 2>&1)
assert_eq "show model add appends model" "Angezeigte Modelle: opus,sonnet,haiku" "$output"

# show model add duplicate
output=$(bash "$CLAUDII_HOME/bin/claudii" show model add haiku 2>&1)
assert_contains "show model add duplicate warns" "bereits" "$output"
output=$(bash "$CLAUDII_HOME/bin/claudii" show model 2>&1)
assert_eq "show model add duplicate does not change list" "Angezeigte Modelle: opus,sonnet,haiku" "$output"

# show model rm
bash "$CLAUDII_HOME/bin/claudii" show model rm sonnet >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" show model 2>&1)
assert_eq "show model rm removes model" "Angezeigte Modelle: opus,haiku" "$output"

# show model rm nonexistent
output=$(bash "$CLAUDII_HOME/bin/claudii" show model rm nonexistent 2>&1 || true)
assert_contains "show model rm nonexistent shows error" "nicht gefunden" "$output"

# show model set single model
bash "$CLAUDII_HOME/bin/claudii" show model opus >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" show model 2>&1)
assert_eq "show model set single model" "Angezeigte Modelle: opus" "$output"

# show model persists to config
stored=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "show model persists to config" "opus" "$stored"

# help mentions show command
output=$(bash "$CLAUDII_HOME/bin/claudii" help 2>&1)
assert_contains "help lists show model command" "show model" "$output"

# Cleanup
rm -rf "$XDG_CONFIG_HOME"
unset XDG_CONFIG_HOME
