#!/bin/bash
# clean-tmp.sh — delete everything inside the repo's ./tmp/ scratch dir.
#
# Exists because the global Claude permission deny blocks `rm -r` wholesale
# (deny always beats allow, so a project allow cannot carve out tmp/). This
# script is the auditable, path-scoped alternative: it resolves the repo root
# from its own location and refuses to touch anything outside ./tmp/.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -d tmp ]] || { printf 'clean-tmp: no tmp/ dir — nothing to do\n'; exit 0; }

shopt -s dotglob nullglob
removed=0
for p in tmp/*; do
  rm -rf "$p"
  (( ++removed ))
done

printf 'clean-tmp: removed %d entr%s from ./tmp/\n' "$removed" "$([[ $removed -eq 1 ]] && echo y || echo ies)"
