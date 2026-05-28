#!/usr/bin/env bash
# One-shot: consolidate .claude/settings.local.json permissions.
# - Drops exact-match entries that are now subsumed by new wildcards.
# - Adds session-active patterns and consolidating wildcards.
# - Sets the standard deny block (currently empty).
#
# Run with:
#   bash .claude/scripts/apply-perms.sh
#
# Atomic write via mktemp + mv. Backup at .claude/settings.local.json.bak.
set -euo pipefail

FILE=".claude/settings.local.json"
[[ -f "$FILE" ]] || { echo "settings.local.json not found at $FILE — wrong CWD?" >&2; exit 1; }

cp "$FILE" "${FILE}.bak"

TMP=$(mktemp "${FILE}.XXXXXX")

# Heredoc keeps single quotes intact inside the jq filter (no shell expansion thanks to quoted 'JQ').
JQ_FILTER=$(cat <<'JQ'
  .permissions.allow -= [
    "Bash(awk 'NR==44' bin/claudii-cc-statusline)",
    "Bash(awk 'NR==21' bin/claudii-cc-statusline)",
    "Bash(awk 'NR==94' bin/claudii-cc-statusline)",
    "Bash(awk 'NR==28 || NR==94 || NR==485' bin/claudii-cc-statusline)",
    "Bash(awk 'NR==133' /Users/bma/offline_coding/claudii/lib/cmd/vibemap.sh)",
    "Bash(grep -n '^_bedtime=\\\\|^# Worktree\\\\|^fi$' /Users/bma/offline_coding/claudii/bin/claudii-cc-statusline)",
    "Bash(rm -f /Users/bma/.cache/claudii/status-models /Users/bma/.cache/claudii/status-unresolved.json)"
  ]
  | .permissions.allow += [
    "Bash(awk:*)",
    "Bash(grep:*)",
    "Bash(bin/claudii:*)",
    "Bash(bin/claudii-insights:*)",
    "Bash(bash bin/claudii-insights *)",
    "Bash(bash /Users/bma/offline_coding/dotfiles/claude/hooks/*)",
    "Bash(time bash *)",
    "Bash(rm -f /Users/bma/.cache/claudii/*)"
  ]
  | .permissions.deny = [
    "Bash(rm -rf:*)",
    "Bash(rm -fr:*)",
    "Bash(git reset --hard:*)",
    "Bash(git push --force:*)",
    "Bash(git push --force-with-lease:*)",
    "Bash(git config:*)"
  ]
JQ
)

jq "$JQ_FILTER" "$FILE" > "$TMP"

# Sanity: must be parseable JSON with permissions.allow array
jq -e '.permissions.allow | type == "array"' "$TMP" > /dev/null || {
  echo "jq output failed sanity check; aborting. New file at $TMP, backup at ${FILE}.bak" >&2
  exit 1
}

mv "$TMP" "$FILE"
echo "Applied. Backup: ${FILE}.bak"
echo "Allow count: $(jq '.permissions.allow | length' "$FILE")"
echo "Deny count:  $(jq '.permissions.deny | length' "$FILE")"
