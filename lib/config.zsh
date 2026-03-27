# claudii config — reads ~/.config/claudii/config.json, falls back to defaults

CLAUDII_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claudii"
CLAUDII_CONFIG="$CLAUDII_CONFIG_DIR/config.json"
CLAUDII_DEFAULTS="$CLAUDII_HOME/config/defaults.json"

[[ -d "$CLAUDII_CONFIG_DIR" ]] || mkdir -p "$CLAUDII_CONFIG_DIR"
[[ -f "$CLAUDII_CONFIG" ]] || cp "$CLAUDII_DEFAULTS" "$CLAUDII_CONFIG"

function claudii_config_get {
  local jq_expr="if (.$1 | type) != \"null\" then (.$1 | tostring) else empty end"
  local val=$(jq -r "$jq_expr" "$CLAUDII_CONFIG" 2>/dev/null)
  [[ -z "$val" ]] && val=$(jq -r "$jq_expr" "$CLAUDII_DEFAULTS" 2>/dev/null)
  echo "$val"
}
