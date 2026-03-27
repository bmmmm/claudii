# test_config.sh — config system E2E tests

# Setup: use project-local temp config dir
export XDG_CONFIG_HOME="$CLAUDII_HOME/tmp/test_config"
rm -rf "$XDG_CONFIG_HOME/claudii"
mkdir -p "$XDG_CONFIG_HOME/claudii"

# config creates from defaults
output=$(bash "$CLAUDII_HOME/bin/claudii" config 2>&1)
assert_contains "config list shows user config path" "config.json" "$output"
assert_file_exists "config.json created from defaults" "$XDG_CONFIG_HOME/claudii/config.json"

# config get
output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.cl.model 2>&1)
assert_eq "config get aliases.cl.model" "sonnet" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.clo.effort 2>&1)
assert_eq "config get aliases.clo.effort" "high" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get fallback.enabled 2>&1)
assert_eq "config get fallback.enabled" "true" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get status.cache_ttl 2>&1)
assert_eq "config get status.cache_ttl" "900" "$output"

# config set string
bash "$CLAUDII_HOME/bin/claudii" config set aliases.cl.model opus >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.cl.model 2>&1)
assert_eq "config set string value" "opus" "$output"

# config set number
bash "$CLAUDII_HOME/bin/claudii" config set status.cache_ttl 600 >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get status.cache_ttl 2>&1)
assert_eq "config set number value" "600" "$output"

# config set boolean
bash "$CLAUDII_HOME/bin/claudii" config set fallback.enabled false >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get fallback.enabled 2>&1)
assert_eq "config set boolean value" "false" "$output"

# config get statusline.models
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config get statusline.models default" "opus,sonnet,haiku" "$output"

# config set statusline.models
bash "$CLAUDII_HOME/bin/claudii" config set statusline.models "opus" >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config set statusline.models" "opus" "$output"

# config reset
bash "$CLAUDII_HOME/bin/claudii" config reset >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get aliases.cl.model 2>&1)
assert_eq "config reset restores defaults" "sonnet" "$output"

output=$(bash "$CLAUDII_HOME/bin/claudii" config get fallback.enabled 2>&1)
assert_eq "config reset restores fallback" "true" "$output"

# Cleanup
rm -rf "$XDG_CONFIG_HOME"
unset XDG_CONFIG_HOME
