#!/usr/bin/env bash
# cleanup-worktree.sh <worktree-name|--all>
# Removes a claudii agent worktree + its branch safely.
# Handles both registered worktrees and zombie dirs (no .git file).
#
# Safety rules:
#   - Zombie dirs (no .git file): always removed — not tracked by git
#   - Registered worktrees: only removed when safe:
#       * no unmerged commits ahead of main
#       * no uncommitted changes
#     Unsafe worktrees are skipped with a warning — use --force to override.
#
# Usage:
#   bash scripts/cleanup-worktree.sh agent-abc12345          # single
#   bash scripts/cleanup-worktree.sh --all                    # all safe agent-* dirs
#   bash scripts/cleanup-worktree.sh --all --force            # all, including active

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
FORCE=false

_is_safe_to_remove() {
  local worktree_path="$1" branch="$2"

  # Uncommitted changes?
  if ! git -C "$worktree_path" diff --quiet 2>/dev/null || \
     ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
    echo "SKIP (uncommitted changes): $(basename "$worktree_path")" >&2
    return 1
  fi

  # Unmerged commits ahead of main?
  local ahead
  ahead=$(git -C "$REPO" rev-list --count "main..${branch}" 2>/dev/null || echo "0")
  if [[ "$ahead" -gt 0 ]]; then
    echo "SKIP ($ahead unmerged commit(s)): $(basename "$worktree_path")" >&2
    return 1
  fi

  return 0
}

_cleanup_one() {
  local name="$1"
  local worktree_path="$REPO/.claude/worktrees/$name"
  local branch="worktree-$name"

  if [[ ! -d "$worktree_path" ]]; then
    echo "Not found, skipping: $name"
    return
  fi

  # Zombie: physical dir exists but not registered — always safe to remove
  if ! git -C "$REPO" worktree list --porcelain | grep -q "^worktree $worktree_path$"; then
    rm -rf "$worktree_path"
    echo "Removed zombie dir: $name"
    return
  fi

  # Registered worktree — safety check unless --force
  if ! $FORCE && ! _is_safe_to_remove "$worktree_path" "$branch"; then
    return
  fi

  git -C "$REPO" worktree remove "$worktree_path" --force
  echo "Removed worktree: $name"

  if git -C "$REPO" branch --list "$branch" | grep -q "$branch"; then
    git -C "$REPO" branch -D "$branch"
    echo "Deleted branch: $branch"
  fi
}

# Parse args
args=()
for a in "$@"; do
  case "$a" in
    --force) FORCE=true ;;
    *)       args+=("$a") ;;
  esac
done

arg="${args[0]:?Usage: bash scripts/cleanup-worktree.sh <worktree-name|--all> [--force]}"

if [[ "$arg" == "--all" ]]; then
  shopt -s nullglob
  dirs=("$REPO/.claude/worktrees/agent-"*/)
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No agent worktrees found."
  else
    for d in "${dirs[@]}"; do
      _cleanup_one "$(basename "$d")"
    done
  fi
else
  _cleanup_one "$arg"
fi

git -C "$REPO" worktree prune
echo "Done."
