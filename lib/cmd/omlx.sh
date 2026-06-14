# lib/cmd/omlx.sh — local-LLM integration: discover gateii's omlx-agent state
# and surface it on the cc-statusline. Reads/writes claudii's own config; does
# not touch gateii's files.
# Sourced by bin/claudii — do NOT add shebang or set -euo pipefail
# Requires: visual.sh sourced first (uses CLAUDII_CLR_*)

# Well-known places to look for gateii's data/agents/active.json
_OMLX_DEFAULT_PATHS=(
  "$HOME/offline_coding/gateii/data/agents/active.json"
  "$HOME/coding/gateii/data/agents/active.json"
  "$HOME/projects/gateii/data/agents/active.json"
  "$HOME/dev/gateii/data/agents/active.json"
)

# Find the active.json — env override → config → first existing default
_omlx_resolve_path() {
  if [[ -n "${CLAUDII_OMLX_ACTIVE:-}" ]]; then
    printf '%s' "$CLAUDII_OMLX_ACTIVE"
    return
  fi
  _cfg_init >/dev/null 2>&1 || true
  if [[ -n "${CONFIG:-}" && -f "$CONFIG" ]]; then
    local from_cfg
    from_cfg=$(jq -r '.statusline.omlx_active_path // empty' "$CONFIG" 2>/dev/null)
    if [[ -n "$from_cfg" ]]; then
      printf '%s' "$from_cfg"
      return
    fi
  fi
  for p in "${_OMLX_DEFAULT_PATHS[@]}"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return
    fi
  done
  # No file found — return the first default so the caller can see what we tried
  printf '%s' "${_OMLX_DEFAULT_PATHS[0]}"
}

# Probe an omlx server via curl. Returns 0 + stdout = "<count> models, <gb>GB"
# on success; non-zero with empty stdout on failure.
_omlx_probe_server() {
  local url="${1:-http://localhost:8000}"
  command -v curl >/dev/null || return 1
  local resp
  resp=$(curl -s -m 2 "$url/v1/models/status" 2>/dev/null) || return 1
  [[ -z "$resp" ]] && return 1
  local n gb _omlx_jq
  _omlx_jq=$(jq -r '[.loaded_count // 0, ((.current_model_memory // 0) / 1073741824)] | join("\t")' <<< "$resp" 2>/dev/null) || return 1
  IFS=$'\t' read -r n gb <<< "$_omlx_jq"
  # env LC_ALL=C printf (external), NOT a bash-builtin "LC_ALL=C printf": under
  # macOS /bin/bash 3.2 a var-assignment prefix does not re-setlocale the printf
  # BUILTIN, so a comma locale still renders "1,5 GB" + an "invalid number"
  # warning; routing through external /usr/bin/printf via env applies the locale.
  # (env LC_ALL=C also beats an inherited LC_ALL that would override LC_NUMERIC=C.)
  env LC_ALL=C printf '%s loaded models, %.1f GB' "$n" "$gb"
  return 0
}

# Check whether the EFFECTIVE cc-statusline layout includes the omlx segment.
# Effective = user's .statusline.lines if set, otherwise defaults.json's.
_omlx_in_layout() {
  _cfg_init >/dev/null 2>&1 || true
  local file=""
  if [[ -n "${CONFIG:-}" && -f "$CONFIG" ]]; then
    # `//` binds looser than `!=`, so `.statusline.lines // null != null` parsed
    # as `.statusline.lines // (null != null)` = `… // false` — the `!= null` was
    # dead. Parenthesise to actually test "lines is present".
    if jq -e '(.statusline.lines // null) != null' "$CONFIG" >/dev/null 2>&1; then
      file="$CONFIG"
    fi
  fi
  if [[ -z "$file" && -n "${DEFAULTS:-}" && -f "$DEFAULTS" ]]; then
    file="$DEFAULTS"
  fi
  [[ -z "$file" ]] && return 1
  jq -e '.statusline.lines | tostring | contains("\"omlx\"")' "$file" >/dev/null 2>&1
}

_cmd_omlx() {
  _cfg_init

  local action="${2:-status}"
  case "$action" in
    status|"")  _omlx_show_status ;;
    connect)    _omlx_connect ;;
    disconnect) _omlx_disconnect ;;
    test)       _omlx_test ;;
    -h|--help|help)
      cat <<'EOF'
Usage: claudii omlx [<command>]

Commands:
  status        Show whether omlx integration is wired up (default)
  connect       Walk through the setup: detect gateii path, add omlx
                segment to the cc-statusline lines, verify oMLX server
  disconnect    Remove the omlx segment from the statusline layout
  test          Render the statusline as if an omlx agent were running

The omlx integration reads a JSON file written by gateii's scripts/agent
(or scripts/agent-bench) at run time. claudii does not depend on gateii;
this command is a no-op if gateii isn't installed.

Override the source path: set CLAUDII_OMLX_ACTIVE=/path/to/active.json
or run: claudii config set statusline.omlx_active_path "/path/..."
EOF
      ;;
    *)
      echo "Unknown omlx command: $action" >&2
      echo "Try: claudii omlx help" >&2
      exit 1
      ;;
  esac
}

_omlx_show_status() {
  echo -e "${CLAUDII_CLR_BOLD}claudii — omlx integration${CLAUDII_CLR_RESET}"
  echo

  # 1. claudii statusline layout
  printf "  %-22s " "statusline segment"
  if _omlx_in_layout; then
    echo -e "${CLAUDII_CLR_GREEN}✓ omlx is in cc-statusline lines${CLAUDII_CLR_RESET}"
  else
    echo -e "${CLAUDII_CLR_YELLOW}✗ omlx not in lines${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_DIM}(run: claudii omlx connect)${CLAUDII_CLR_RESET}"
  fi

  # 2. active.json source path
  local p; p=$(_omlx_resolve_path)
  printf "  %-22s %s" "active.json path" "$p"
  if [[ -f "$p" ]]; then
    echo -e "  ${CLAUDII_CLR_GREEN}(present)${CLAUDII_CLR_RESET}"
  else
    echo -e "  ${CLAUDII_CLR_DIM}(not present — gateii not installed or not running)${CLAUDII_CLR_RESET}"
  fi

  # 3. omlx server reachability
  printf "  %-22s " "oMLX server"
  local probe
  if probe=$(_omlx_probe_server); then
    echo -e "${CLAUDII_CLR_GREEN}✓ ${probe}${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_DIM}(http://localhost:8000)${CLAUDII_CLR_RESET}"
  else
    echo -e "${CLAUDII_CLR_DIM}not reachable on http://localhost:8000${CLAUDII_CLR_RESET}"
  fi

  # 4. omlx CLI
  printf "  %-22s " "oMLX CLI"
  if command -v omlx >/dev/null 2>&1; then
    echo -e "${CLAUDII_CLR_GREEN}✓ installed${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_DIM}($(command -v omlx))${CLAUDII_CLR_RESET}"
  else
    echo -e "${CLAUDII_CLR_DIM}not on PATH (optional — only needed to manage models)${CLAUDII_CLR_RESET}"
  fi
}

_omlx_connect() {
  echo -e "${CLAUDII_CLR_BOLD}claudii omlx connect${CLAUDII_CLR_RESET}"
  echo

  # 1. Detect a gateii install
  local p="" found=""
  if [[ -n "${CLAUDII_OMLX_ACTIVE:-}" ]]; then
    p="$CLAUDII_OMLX_ACTIVE"
    found="$p"
  else
    for cand in "${_OMLX_DEFAULT_PATHS[@]}"; do
      if [[ -f "$cand" || -d "${cand%/*}" ]]; then
        found="$cand"
        p="$cand"
        break
      fi
    done
  fi

  if [[ -z "$found" ]]; then
    echo -e "  ${CLAUDII_CLR_YELLOW}!${CLAUDII_CLR_RESET} No gateii data dir found at any of:"
    for cand in "${_OMLX_DEFAULT_PATHS[@]}"; do
      echo "    - $cand"
    done
    echo
    echo "  Pick one of these and continue:"
    echo "    a) install gateii (https://github.com/bmmmm/gateii) and re-run \`claudii omlx connect\`"
    echo "    b) point claudii at an existing gateii checkout:"
    echo "         claudii config set statusline.omlx_active_path \"/your/path/data/agents/active.json\""
    echo
    echo "  Aborting setup."
    return 1
  fi

  # 2. If we picked a non-default path, store it
  if [[ "$p" != "${_OMLX_DEFAULT_PATHS[0]}" ]]; then
    _jq_update "$CONFIG" --arg p "$p" '.statusline.omlx_active_path = $p'
    echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} stored .statusline.omlx_active_path = $p"
  else
    echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} using default path: $p"
  fi

  # 3. Add `omlx` segment to lines layout
  # Two cases:
  #   - User has no .statusline.lines → defaults (which now include omlx) apply.
  #     Don't write a lines field; that would freeze the layout against future
  #     defaults updates.
  #   - User has a custom .statusline.lines → append [["omlx"]] only if missing.
  if _omlx_in_layout; then
    echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} omlx segment already in cc-statusline lines"
  else
    local has_custom
    has_custom=$(jq -r '.statusline.lines // empty | tostring' "$CONFIG" 2>/dev/null)
    if [[ -n "$has_custom" && "$has_custom" != "null" ]]; then
      _jq_update "$CONFIG" '.statusline.lines = .statusline.lines + [["omlx"]]'
      echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} appended new line [\"omlx\"] to your custom .statusline.lines"
    else
      echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} using built-in defaults (which already include the omlx line)"
    fi
  fi

  # 4. Probe the oMLX server (optional sanity check)
  local probe
  if probe=$(_omlx_probe_server); then
    echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} oMLX server reachable: ${probe}"
  else
    echo -e "  ${CLAUDII_CLR_YELLOW}!${CLAUDII_CLR_RESET} oMLX server not reachable on http://localhost:8000"
    echo -e "    ${CLAUDII_CLR_DIM}(start it with: omlx serve  — or via the desktop app)${CLAUDII_CLR_RESET}"
    echo -e "    ${CLAUDII_CLR_DIM}claudii's omlx segment will stay empty until gateii's wrapper writes active.json${CLAUDII_CLR_RESET}"
  fi

  # 5. Quick test render
  echo
  echo -e "  ${CLAUDII_CLR_DIM}→ run \`claudii omlx test\` to see how the segment will look${CLAUDII_CLR_RESET}"
  echo -e "  ${CLAUDII_CLR_DIM}→ restart Claude Code to pick up the new statusline layout${CLAUDII_CLR_RESET}"
}

_omlx_disconnect() {
  _cfg_init
  if ! _omlx_in_layout; then
    echo -e "  ${CLAUDII_CLR_DIM}omlx not in lines — nothing to do${CLAUDII_CLR_RESET}"
    return 0
  fi
  # Remove every line that contains the literal "omlx" segment.
  # Lines that mix omlx with other segments lose only the omlx entry; lines
  # that are JUST ["omlx"] are dropped entirely.
  _jq_update "$CONFIG" '
    .statusline.lines |= (
      map(map(select(. != "omlx"))) | map(select(length > 0))
    )
  '
  echo -e "  ${CLAUDII_CLR_GREEN}✓${CLAUDII_CLR_RESET} removed omlx segment from cc-statusline lines"
  echo -e "  ${CLAUDII_CLR_DIM}(restart Claude Code to apply)${CLAUDII_CLR_RESET}"
}

_omlx_test() {
  if ! command -v claudii-cc-statusline >/dev/null 2>&1; then
    echo -e "  ${CLAUDII_CLR_RED}claudii-cc-statusline not on PATH${CLAUDII_CLR_RESET}"
    return 1
  fi
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/claudii-omlx-test.XXXXXX") || return 1
  # Subshell + EXIT trap cleans the temp dir even if a command below aborts under
  # `set -e` (bin/claudii runs set -euo pipefail). A function-level RETURN trap
  # does NOT fire on a set -e abort; an EXIT trap scoped to a subshell does,
  # without clobbering the CLI's own traps.
  (
    trap 'rm -rf "$tmp"' EXIT
    # Synthetic active.json — a fresh entry so the freshness guard accepts it
    cat > "$tmp/active.json" <<EOF
{"task":"commit-msg","model":"Qwen3.5-9B-MLX-4bit","started_epoch":$(($(date +%s)-3)),"pid":99999,"prompt_preview":"refactor scripts/git-tracking.sh"}
EOF
    # Synthetic config — pin a layout that *includes* the omlx segment so the
    # render demo actually shows ⚡ regardless of the user's real config.
    mkdir -p "$tmp/cfg/claudii"
    printf '{"statusline":{"lines":[["model"],["omlx"]],"omlx_active_path":"%s/active.json"}}\n' "$tmp" > "$tmp/cfg/claudii/config.json"

    echo -e "${CLAUDII_CLR_BOLD}claudii omlx test${CLAUDII_CLR_RESET}  ${CLAUDII_CLR_DIM}(simulated active.json + temporary layout)${CLAUDII_CLR_RESET}"
    echo
    # Pin CLAUDII_OMLX_ACTIVE too — it wins over the synthetic config's omlx_active_path
    # (cc-statusline resolves ${CLAUDII_OMLX_ACTIVE:-${_cfg_omlx:-…}}), so a user with it
    # exported would otherwise see their real omlx state instead of this demo.
    echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":15,"context_window_size":200000}}' \
      | CLAUDII_OMLX_ACTIVE="$tmp/active.json" XDG_CONFIG_HOME="$tmp/cfg" claudii-cc-statusline 2>/dev/null
    echo
    echo -e "  ${CLAUDII_CLR_DIM}(this is what your statusline will show while a real omlx agent is running)${CLAUDII_CLR_RESET}"
  )
}
