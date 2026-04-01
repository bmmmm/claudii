#!/usr/bin/env bash
# cleanup-worktree.sh <worktree-name>
# Removes a claudii agent worktree + its branch safely.
# Usage: bash scripts/cleanup-worktree.sh agent-abc12345

set -euo pipefail

name="${1:?Usage: bash scripts/cleanup-worktree.sh <worktree-name>}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE_PATH="$REPO/.claude/worktrees/$name"
BRANCH="worktree-$name"

# Remove worktree (--force handles dirty state)
if git -C "$REPO" worktree list --porcelain | grep -q "^worktree $WORKTREE_PATH$"; then
  git -C "$REPO" worktree remove "$WORKTREE_PATH" --force
  echo "Removed worktree: $WORKTREE_PATH"
else
  echo "Worktree not found (already removed?): $WORKTREE_PATH"
fi

# Delete branch if it exists
if git -C "$REPO" branch --list "$BRANCH" | grep -q "$BRANCH"; then
  git -C "$REPO" branch -D "$BRANCH"
  echo "Deleted branch: $BRANCH"
else
  echo "Branch not found (already deleted?): $BRANCH"
fi

git -C "$REPO" worktree prune
echo "Done."
