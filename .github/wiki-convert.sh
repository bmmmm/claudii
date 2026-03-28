#!/bin/bash
# Convert man page to clean wiki markdown
set -euo pipefail

MANPAGE="$1"
OUTPUT="$2"
SIDEBAR="$3"

RAW=$(pandoc -f man -t gfm --wrap=none "$MANPAGE")

# Strip NAME/SYNOPSIS (redundant with header) and SEE ALSO/AUTHOR/PROJECT (footer)
BODY=$(echo "$RAW" \
  | sed '/^# CLAUDII/d' \
  | sed '/^# NAME/,/^# /{/^# [^N]/!d}' \
  | sed '/^# SYNOPSIS/,/^# /{/^# [^S]/!d}' \
  | sed '/^# SEE ALSO/,$d' \
  | sed '/^# AUTHOR/,$d' \
)

# Demote all headings by one level
BODY=$(echo "$BODY" | sed 's/^#### /##### /; s/^### /#### /; s/^## /### /; s/^# /## /')

# Add --- separator + extra spacing before ## headings
BODY=$(printf '%s\n' "$BODY" | awk '/^## /{print "\n---\n"} {print}')

# Write Home.md
cat > "$OUTPUT" << 'HEADER'
# claudii ♥

> Fast Claude Code aliases with live model status and session insights.

<sub>Auto-generated from <a href="https://github.com/bmmmm/claudii/blob/main/man/man1/claudii.1"><code>man claudii</code></a> — do not edit directly.</sub>

&nbsp;
HEADER

echo "$BODY" >> "$OUTPUT"

cat >> "$OUTPUT" << 'FOOTER'

---

&nbsp;

## Links

| | |
|---|---|
| GitHub | [bmmmm/claudii](https://github.com/bmmmm/claudii) |
| Install | `brew tap bmmmm/tap && brew install claudii` |
| Releases | [v0.1.0+](https://github.com/bmmmm/claudii/releases) |
| Claude Code Status Line | [wynandw87](https://github.com/wynandw87/claude-code-statusline) |
FOOTER

# Write _Sidebar.md
cat > "$SIDEBAR" << 'EOF'
**claudii** ♥

- [[Home]]
- [README](https://github.com/bmmmm/claudii#readme)
- [Install](https://github.com/bmmmm/claudii#install)
- [Releases](https://github.com/bmmmm/claudii/releases)
- [Contributing](https://github.com/bmmmm/claudii/blob/main/CONTRIBUTING.md)

**Sections**
- [Aliases](#aliases)
- [ClaudeStatus](#claudestatus)
- [Claude Code Status Line](#claude-code-status-line-by-wynandw87)
- [Config](#config)
- [Environment](#environment)
- [Examples](#examples)
EOF
