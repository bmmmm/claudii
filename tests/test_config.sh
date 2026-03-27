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

# config export — stdout
output=$(bash "$CLAUDII_HOME/bin/claudii" config export 2>&1)
assert_contains "config export outputs JSON" "statusline" "$output"
echo "$output" | jq '.' >/dev/null 2>&1 && assert_eq "config export is valid JSON" "true" "true" \
  || assert_eq "config export is valid JSON" "valid" "invalid"

# config export — to file
export_file="$XDG_CONFIG_HOME/claudii/export.json"
bash "$CLAUDII_HOME/bin/claudii" config export "$export_file" >/dev/null 2>&1
assert_file_exists "config export creates file" "$export_file"
models_in_export=$(jq -r '.statusline.models' "$export_file")
assert_eq "config export file has correct content" "opus,sonnet,haiku" "$models_in_export"

# config import
import_file="$XDG_CONFIG_HOME/claudii/import.json"
jq '.statusline.models = "opus"' "$CLAUDII_HOME/config/defaults.json" > "$import_file"
bash "$CLAUDII_HOME/bin/claudii" config import "$import_file" >/dev/null 2>&1
output=$(bash "$CLAUDII_HOME/bin/claudii" config get statusline.models 2>&1)
assert_eq "config import replaces config" "opus" "$output"

# config import creates .bak
assert_file_exists "config import creates backup" "$XDG_CONFIG_HOME/claudii/config.json.bak"

# config import — invalid JSON rejected
echo "not json" > "$XDG_CONFIG_HOME/claudii/bad.json"
output=$(bash "$CLAUDII_HOME/bin/claudii" config import "$XDG_CONFIG_HOME/claudii/bad.json" 2>&1 || true)
assert_contains "config import rejects invalid JSON" "gültiges JSON" "$output"

# config import — missing file rejected
output=$(bash "$CLAUDII_HOME/bin/claudii" config import /nonexistent/file.json 2>&1 || true)
assert_contains "config import rejects missing file" "nicht gefunden" "$output"

# Cleanup
rm -rf "$XDG_CONFIG_HOME"
unset XDG_CONFIG_HOME
