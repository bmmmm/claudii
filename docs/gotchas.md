# Gotchas

Referenced from CLAUDE.md § "Rules" — one-line triggers live there, the
incident detail and recovery mechanics live here.

## `/bin/bash` 3.2 vs Homebrew bash 5.x (CI)

CI macos-latest runs `/bin/bash` 3.2; local `bash` is Homebrew 5.x and
silently masks 3.2-only breakage (e.g. `${4:-{\}}` → `{\}` on 3.2 vs `{}` on
5.x). A green local `bash tests/run.sh` run is not a green CI run — when a
change touches test fixtures or any shell-quoting/default-arg/expansion
logic, run `/bin/bash tests/run.sh` before pushing.

## No `declare -A` in `bin/`

`/bin/bash` 3.2 silently degrades it to an indexed array (string keys
evaluate as `arr[0]`, last-write-wins). Use `case` for label maps,
`printf -v "_p_${k}" "%s" "$v"` + `${!_p_…}` for sparse 2D lookups, or
parallel indexed arrays; guard new maps with a regression assert that
invokes `/bin/bash` explicitly (the Homebrew-5.x test runner won't catch
it).

## Never string-match `statusLine.command`

Use `_cc_statusline_connected` (`lib/helpers.sh`) instead. The configured
command may be a wrapper chain (`cc-insomnii --after=<user-wrap>` where only
the wrap script invokes `claudii-cc-statusline`); literal matching broke
twice (insomnii wrapper, then user sleep-wrap) and made `claudii on` clobber
the user's chain.

## An awk file carries no semantics of its own

Verify any claim about a `lib/*.awk` program against its `-v` bindings at
the call site (`lib/cmd/*.sh`). Variable names lie: `trends.awk`'s
`week_start` is bound to the *rolling* `seven_ts`, not the calendar week
start. A review finding "confirmed" from the awk side alone produced a
false CONFIRMED once (2026-07-02) — the refutation only surfaced on the
pre-fix re-read of the binding site.
