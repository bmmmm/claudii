# lib/cmd/vpnii.sh — VPN state file management.
#
# Wraps the cache-file write/clear that wg-quick PostUp/PreDown trigger,
# but ensures the file is always owned by the real user even when invoked
# from a root context (wg-quick runs PostUp/PreDown as root). That way
# `rm` from the user shell never needs sudo.
#
# Sourced by bin/claudii — no shebang, no `set -euo pipefail`.

# Resolve the unprivileged user this state file should belong to.
# Order: explicit --user flag → SUDO_USER (set by `sudo …`) → CLAUDII_USER
# env → /dev/console owner (GUI session on macOS) → current $USER.
# Returns "root" only when nothing else makes sense (single-user root box).
_vpnii_resolve_user() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"; return
  fi
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    printf '%s' "$SUDO_USER"; return
  fi
  if [[ -n "${CLAUDII_USER:-}" ]]; then
    printf '%s' "$CLAUDII_USER"; return
  fi
  # macOS GUI session — /dev/console is owned by the logged-in user
  local console_user
  console_user=$(stat -f '%Su' /dev/console 2>/dev/null || stat -c '%U' /dev/console 2>/dev/null || true)
  if [[ -n "$console_user" && "$console_user" != "root" ]]; then
    printf '%s' "$console_user"; return
  fi
  printf '%s' "${USER:-root}"
}

_vpnii_user_home() {
  # Resolve home directory for an arbitrary user without `eval ~$user`.
  local u="$1" home=""
  if command -v dscl >/dev/null 2>&1; then
    home=$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  fi
  if [[ -z "$home" ]]; then
    home=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
  fi
  printf '%s' "$home"
}

_vpnii_path_for_user() {
  local u="$1"
  if [[ "$u" == "${USER:-}" || -z "$u" ]]; then
    printf '%s' "${CLAUDII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claudii}/vpnii"
    return
  fi
  local home; home=$(_vpnii_user_home "$u")
  if [[ -z "$home" ]]; then
    echo "claudii vpnii: cannot resolve home for user '$u'" >&2
    return 1
  fi
  printf '%s' "$home/.cache/claudii/vpnii"
}

# Write `name` to the vpnii state file as the unprivileged user.
# When invoked as root, drops to `--user` (resolved). When invoked as the
# user already, writes directly — no sudo, no privilege change.
_vpnii_set() {
  local name="" user_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) user_override="${2:-}"; shift 2 ;;
      --user=*) user_override="${1#--user=}"; shift ;;
      -*)     echo "claudii vpnii set: unknown flag '$1'" >&2; return 2 ;;
      *)      [[ -z "$name" ]] && name="$1" || { echo "claudii vpnii set: extra arg '$1'" >&2; return 2; }; shift ;;
    esac
  done
  if [[ -z "$name" ]]; then
    echo "Usage: claudii vpnii set <tunnel-name> [--user <name>]" >&2
    return 2
  fi

  local target_user; target_user=$(_vpnii_resolve_user "$user_override")
  local target_path; target_path=$(_vpnii_path_for_user "$target_user") || return 1
  local target_dir="${target_path%/*}"

  if [[ "$(id -un)" == "$target_user" ]]; then
    mkdir -p "$target_dir" && chmod 0700 "$target_dir"
    printf '%s\n' "$name" > "$target_path"
  else
    # Drop to the target user. `sudo -u` works whether we're root or another
    # user with sudo rights; non-root → non-target without sudo will fail.
    sudo -n -u "$target_user" mkdir -p "$target_dir" 2>/dev/null \
      || { echo "claudii vpnii: cannot mkdir $target_dir as $target_user (need sudo or matching uid)" >&2; return 1; }
    printf '%s\n' "$name" | sudo -n -u "$target_user" tee "$target_path" >/dev/null \
      || { echo "claudii vpnii: write to $target_path as $target_user failed" >&2; return 1; }
  fi
}

_vpnii_clear() {
  local user_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) user_override="${2:-}"; shift 2 ;;
      --user=*) user_override="${1#--user=}"; shift ;;
      *) echo "claudii vpnii clear: unexpected arg '$1'" >&2; return 2 ;;
    esac
  done
  local target_user; target_user=$(_vpnii_resolve_user "$user_override")
  local target_path; target_path=$(_vpnii_path_for_user "$target_user") || return 1
  [[ -e "$target_path" ]] || return 0
  if [[ "$(id -un)" == "$target_user" ]]; then
    rm -f "$target_path"
  else
    sudo -n -u "$target_user" rm -f "$target_path" \
      || { echo "claudii vpnii: rm $target_path as $target_user failed" >&2; return 1; }
  fi
}

_vpnii_show() {
  local target_user; target_user=$(_vpnii_resolve_user "")
  local target_path; target_path=$(_vpnii_path_for_user "$target_user") || return 1
  if [[ -f "$target_path" ]]; then
    cat "$target_path"
  else
    echo "no tunnel"
    return 1
  fi
}

_cmd_vpnii() {
  local sub="${2:-show}"
  case "$sub" in
    set)              _vpnii_set "${@:3}"   ;;
    clear|down|off)   _vpnii_clear "${@:3}" ;;
    show|status)      _vpnii_show           ;;
    -h|--help|help)
      cat <<'EOF'
Usage: claudii vpnii <subcommand>

  set <name>   Mark VPN tunnel <name> as active. Writes ~/.cache/claudii/vpnii
               as the real user even when invoked from root (e.g. wg-quick
               PostUp). Use this in your wg conf:
                 PostUp = claudii vpnii set HomeLab
  clear        Mark VPN as down. Use in wg conf:
                 PreDown = claudii vpnii clear
  show         Print current tunnel name (or "no tunnel").

Flags: --user <name> overrides auto-detection (SUDO_USER → console → $USER).
EOF
      ;;
    *)
      echo "claudii vpnii: unknown subcommand '$sub' — try 'claudii vpnii help'" >&2
      return 2
      ;;
  esac
}
