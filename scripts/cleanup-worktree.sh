#!/usr/bin/env bash
# cleanup-worktree.sh <worktree-name|--all>
# Removes a claudii agent worktree + its branch safely.
# Handles both registered worktrees and zombie dirs (no .git file).
#
# Usage:
#   bash scripts/cleanup-worktree.sh agent-abc12345   # single
#   bash scripts/cleanup-worktree.sh --all             # all agent-* dirs

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

_cleanup_one() {
  local name="$1"
  local worktree_path="$REPO/.claude/worktrees/$name"
  local branch="worktree-$name"

  if [[ ! -d "$worktree_path" ]]; then
    echo "Not found, skipping: $name"
    return
  fi

  # Registered worktree → use git worktree remove
  if git -C "$REPO" worktree list --porcelain | grep -q "^worktree $worktree_path$"; then
    git -C "$REPO" worktree remove "$worktree_path" --force
    echo "Removed worktree: $name"
  else
    # Zombie: physical dir exists but not registered — remove directly
    rm -rf "$worktree_path"
    echo "Removed zombie dir: $name"
  fi

  # Delete branch if it exists
  if git -C "$REPO" branch --list "$branch" | grep -q "$branch"; then
    git -C "$REPO" branch -D "$branch"
    echo "Deleted branch: $branch"
  fi
}

arg="${1:?Usage: bash scripts/cleanup-worktree.sh <worktree-name|--all>}"

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
