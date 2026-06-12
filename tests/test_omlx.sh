# touches: lib/cmd/omlx.sh bin/claudii

# test_omlx.sh — behavior tests for `claudii omlx` (status/connect/disconnect,
# path precedence, unknown command). No gateii install and no oMLX server are
# required: the probe fails fast on connection-refused and the tests only
# assert on the integration wiring, never on server reachability.

_OMLX_TMPDIRS=()
trap 'rm -rf "${_OMLX_TMPDIRS[@]}" 2>/dev/null' EXIT

_omlx_mktmp() {
  local _base
  _base=$(mktemp -d)
  _OMLX_TMPDIRS+=("$_base")
  mkdir -p "$_base/xdg/claudii" "$_base/cache"
  cp "$CLAUDII_HOME/config/defaults.json" "$_base/xdg/claudii/config.json"
  printf '%s' "$_base"
}

# ── omlx status: exits 0, shows all four checks ───────────────────────────────
_om_base=$(_omlx_mktmp)
_om_out=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx status 2>&1)
_om_exit=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx status >/dev/null 2>&1; echo $?)

assert_eq       "omlx status: exit 0" "0" "$_om_exit"
assert_contains "omlx status: header present"          "omlx integration"   "$_om_out"
assert_contains "omlx status: layout check present"    "statusline segment" "$_om_out"
assert_contains "omlx status: path check present"      "active.json path"   "$_om_out"
assert_contains "omlx status: server check present"    "oMLX server"        "$_om_out"
assert_contains "omlx status: CLI check present"       "oMLX CLI"           "$_om_out"
# Shipped defaults include the omlx segment in .statusline.lines
assert_contains "omlx status: defaults have omlx in lines" "omlx is in cc-statusline lines" "$_om_out"

# ── omlx status (bare `claudii omlx`): same as status ─────────────────────────
_om_bare=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx 2>&1)
assert_contains "omlx (bare): defaults to status" "omlx integration" "$_om_bare"

# ── path precedence: CLAUDII_OMLX_ACTIVE env wins over config ─────────────────
_om_envp="$_om_base/custom-active.json"
_om_out=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  CLAUDII_OMLX_ACTIVE="$_om_envp" bash "$CLAUDII_HOME/bin/claudii" omlx status 2>&1)
assert_contains "omlx status: CLAUDII_OMLX_ACTIVE env path shown" "$_om_envp" "$_om_out"

# ── path precedence: config statusline.omlx_active_path used when no env ──────
jq '.statusline.omlx_active_path = "/cfg/path/active.json"' \
  "$_om_base/xdg/claudii/config.json" > "$_om_base/xdg/claudii/config.json.tmp" \
  && mv "$_om_base/xdg/claudii/config.json.tmp" "$_om_base/xdg/claudii/config.json"
_om_out=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx status 2>&1)
assert_contains "omlx status: config omlx_active_path shown" "/cfg/path/active.json" "$_om_out"

# ── omlx connect with CLAUDII_OMLX_ACTIVE: stores the path in config ──────────
_om_base2=$(_omlx_mktmp)
mkdir -p "$_om_base2/gateii"
printf '{"task":"t","model":"m","started_epoch":0}\n' > "$_om_base2/gateii/active.json"
_om_cexit=$(HOME="$_om_base2" XDG_CONFIG_HOME="$_om_base2/xdg" CLAUDII_CACHE_DIR="$_om_base2/cache" \
  CLAUDII_OMLX_ACTIVE="$_om_base2/gateii/active.json" \
  bash "$CLAUDII_HOME/bin/claudii" omlx connect >/dev/null 2>&1; echo $?)
_om_cfgp=$(jq -r '.statusline.omlx_active_path // ""' "$_om_base2/xdg/claudii/config.json")

assert_eq "omlx connect (env path): exit 0" "0" "$_om_cexit"
assert_eq "omlx connect (env path): path stored in config" "$_om_base2/gateii/active.json" "$_om_cfgp"

# ── omlx connect without any gateii: actionable abort, exit 1 ─────────────────
_om_base3=$(_omlx_mktmp)
_om_cout=$(HOME="$_om_base3" XDG_CONFIG_HOME="$_om_base3/xdg" CLAUDII_CACHE_DIR="$_om_base3/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx connect 2>&1)
_om_cexit=$(HOME="$_om_base3" XDG_CONFIG_HOME="$_om_base3/xdg" CLAUDII_CACHE_DIR="$_om_base3/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx connect >/dev/null 2>&1; echo $?)

assert_eq       "omlx connect (no gateii): exit 1" "1" "$_om_cexit"
assert_contains "omlx connect (no gateii): names the searched paths" "gateii/data/agents/active.json" "$_om_cout"
assert_contains "omlx connect (no gateii): actionable next step" "claudii config set statusline.omlx_active_path" "$_om_cout"

# ── omlx disconnect: surgical removal from custom lines ───────────────────────
# Mixed line loses only the omlx entry; a pure ["omlx"] line is dropped.
_om_base4=$(_omlx_mktmp)
jq '.statusline.lines = [["model","omlx"],["omlx"],["cost"]]' \
  "$_om_base4/xdg/claudii/config.json" > "$_om_base4/xdg/claudii/config.json.tmp" \
  && mv "$_om_base4/xdg/claudii/config.json.tmp" "$_om_base4/xdg/claudii/config.json"

_om_dexit=$(HOME="$_om_base4" XDG_CONFIG_HOME="$_om_base4/xdg" CLAUDII_CACHE_DIR="$_om_base4/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx disconnect >/dev/null 2>&1; echo $?)
_om_lines=$(jq -c '.statusline.lines' "$_om_base4/xdg/claudii/config.json")

assert_eq "omlx disconnect: exit 0" "0" "$_om_dexit"
assert_eq "omlx disconnect: omlx removed, other segments kept" '[["model"],["cost"]]' "$_om_lines"

# Second disconnect is a no-op (idempotent)
_om_dout=$(HOME="$_om_base4" XDG_CONFIG_HOME="$_om_base4/xdg" CLAUDII_CACHE_DIR="$_om_base4/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx disconnect 2>&1)
assert_contains "omlx disconnect: idempotent no-op message" "nothing to do" "$_om_dout"

# ── omlx help / unknown command ───────────────────────────────────────────────
_om_help=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx help 2>&1)
assert_contains "omlx help: usage shown" "Usage: claudii omlx" "$_om_help"

_om_bexit=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx bogus >/dev/null 2>&1; echo $?)
_om_berr=$(HOME="$_om_base" XDG_CONFIG_HOME="$_om_base/xdg" CLAUDII_CACHE_DIR="$_om_base/cache" \
  bash "$CLAUDII_HOME/bin/claudii" omlx bogus 2>&1 >/dev/null)
assert_eq       "omlx bogus: exit 1" "1" "$_om_bexit"
assert_contains "omlx bogus: actionable error" "Try: claudii omlx help" "$_om_berr"

unset _om_base _om_base2 _om_base3 _om_base4 _om_out _om_bare _om_exit _om_envp \
  _om_cout _om_cexit _om_cfgp _om_dexit _om_dout _om_lines _om_help _om_bexit _om_berr
