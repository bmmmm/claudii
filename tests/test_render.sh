# touches: lib/fmt.awk lib/render.sh

# test_render.sh — shared renderers: lib/fmt.awk (awk) + lib/render.sh (bash).
# fmt_tok lives in two languages (awk for cost/trends, bash for the jq-backed
# commands); these tests pin both and cross-check parity on the K/M/B thresholds.

# ── lib/fmt.awk ──────────────────────────────────────────────────────────────
# Compose the lib the way cost.sh does (string-injection), then a BEGIN probe.
# trends.awk loads the same file via `-f`; the real trends run exercises that path.
_fmtawk() {
  awk "$(cat "$CLAUDII_HOME/lib/fmt.awk")
BEGIN { $1 }" </dev/null
}

assert_eq "fmt.awk: fmt_tok 0 → empty (load-bearing for empty days)" "" "$(_fmtawk 'print fmt_tok(0)')"
assert_eq "fmt.awk: fmt_tok 999 → 999"        "999"    "$(_fmtawk 'print fmt_tok(999)')"
assert_eq "fmt.awk: fmt_tok 1000 → 1K"        "1K"     "$(_fmtawk 'print fmt_tok(1000)')"
assert_eq "fmt.awk: fmt_tok 5200000 → 5.2M"   "5.2M"   "$(_fmtawk 'print fmt_tok(5200000)')"
assert_eq "fmt.awk: fmt_tok 140000000 → 140.0M" "140.0M" "$(_fmtawk 'print fmt_tok(140000000)')"
assert_eq "fmt.awk: fmt_tok 2300000000 → 2.3B" "2.3B"  "$(_fmtawk 'print fmt_tok(2300000000)')"

assert_eq "fmt.awk: rep('-',4) → ----"        "----"   "$(_fmtawk 'print rep("-",4)')"
assert_eq "fmt.awk: rep('x',0) → empty"       ""       "$(_fmtawk 'print rep("x",0)')"

assert_eq "fmt.awk: fmt_usd 375.51 → \$375.51"     '$375.51'   "$(_fmtawk 'print fmt_usd(375.51)')"
assert_eq "fmt.awk: fmt_usd 2367.44 → \$2,367.44"  '$2,367.44' "$(_fmtawk 'print fmt_usd(2367.44)')"
assert_eq "fmt.awk: fmt_usd 13036.07 → \$13,036.07" '$13,036.07' "$(_fmtawk 'print fmt_usd(13036.07)')"
assert_eq "fmt.awk: fmt_usd 0 → \$0.00"            '$0.00'     "$(_fmtawk 'print fmt_usd(0)')"
assert_eq "fmt.awk: fmt_usd 0.555 rounds → \$0.56" '$0.56'     "$(_fmtawk 'print fmt_usd(0.555)')"
assert_eq "fmt.awk: fmt_usd 1000000 → \$1,000,000.00" '$1,000,000.00' "$(_fmtawk 'print fmt_usd(1000000)')"

assert_eq "fmt.awk: bar 3/5"                   "███░░"  "$(_fmtawk 'print bar(3,5)')"
assert_eq "fmt.awk: bar clamps over width"     "█████"  "$(_fmtawk 'print bar(9,5)')"
assert_eq "fmt.awk: bar 0/4 all empty"         "░░░░"   "$(_fmtawk 'print bar(0,4)')"
assert_eq "fmt.awk: bar_filled 50/100 w20"     "10"     "$(_fmtawk 'print bar_filled(50,100,20)')"
assert_eq "fmt.awk: bar_filled rounds 1/3 w20" "7"      "$(_fmtawk 'print bar_filled(1,3,20)')"
assert_eq "fmt.awk: bar_filled max0 → 0 (no div-by-zero)" "0" "$(_fmtawk 'print bar_filled(5,0,20)')"

# ── lib/render.sh ────────────────────────────────────────────────────────────
source "$CLAUDII_HOME/lib/visual.sh"
source "$CLAUDII_HOME/lib/render.sh"

assert_eq "render: _fmt_tok 0 → 0"            "0"      "$(_fmt_tok 0)"
assert_eq "render: _fmt_tok 999 → 999"        "999"    "$(_fmt_tok 999)"
assert_eq "render: _fmt_tok 1000 → 1K"        "1K"     "$(_fmt_tok 1000)"
assert_eq "render: _fmt_tok 5200000 → 5.2M"   "5.2M"   "$(_fmt_tok 5200000)"
assert_eq "render: _fmt_tok 140000000 → 140.0M" "140.0M" "$(_fmt_tok 140000000)"
assert_eq "render: _fmt_tok 2300000000 → 2.3B" "2.3B"  "$(_fmt_tok 2300000000)"
assert_eq "render: _fmt_tok non-numeric → 0"  "0"      "$(_fmt_tok abc)"
assert_eq "render: _fmt_tok empty → 0"        "0"      "$(_fmt_tok '')"

assert_eq "render: _cache_hit_pct 950/50 → 95" "95"    "$(_cache_hit_pct 950 50)"
assert_eq "render: _cache_hit_pct 0/0 → 0 (no div-by-zero)" "0" "$(_cache_hit_pct 0 0)"
assert_eq "render: _cache_hit_pct 1/2 → 33"   "33"     "$(_cache_hit_pct 1 2)"
assert_eq "render: _cache_hit_pct non-numeric → 0" "0" "$(_cache_hit_pct x y)"

assert_eq "render: _bar 3/5"                   "███░░"  "$(_bar 3 5)"
assert_eq "render: _bar clamps over width"     "█████"  "$(_bar 9 5)"
assert_eq "render: _bar_filled 50/100 w20 → 10" "10"    "$(_bar_filled 50 100 20)"
assert_eq "render: _bar_filled max0 → 0"       "0"      "$(_bar_filled 5 0 20)"
assert_eq "render: _bar_filled clamps to width" "20"    "$(_bar_filled 999 100 20)"

# ── composite renderers: _rep / _bar_c / _render_bar_row / _render_dgrid ──────
assert_eq "render: _rep '-' 5 → -----"  "-----" "$(_rep '-' 5)"
assert_eq "render: _rep x 0 → empty"    ""      "$(_rep x 0)"
assert_eq "render: _rep ─ 3 (multibyte)" "───"  "$(_rep '─' 3)"

_bc=$(_bar_c 3 5)
assert_contains "render: _bar_c full blocks"  "███" "$_bc"
assert_contains "render: _bar_c empty blocks" "░░"  "$_bc"

_br=$(_render_bar_row "input" 11 "15.2M" 7 5 20 "9%")
assert_contains "render: _render_bar_row label"  "input" "$_br"
assert_contains "render: _render_bar_row value"  "15.2M" "$_br"
assert_contains "render: _render_bar_row bar"    "█"     "$_br"
assert_contains "render: _render_bar_row suffix" "9%"    "$_br"

# _render_dgrid: column widths track the widest cell so │/┼ line up.
_dg=$(printf '%s' $'Opus 4.8\x1f11.0M\x1f96%\nHaiku 4.5\x1f600K\x1f90%\n' \
  | _render_dgrid "Model" $'tokens\x1fhit')
assert_contains "render: _render_dgrid vertical rule" "│"         "$_dg"
assert_contains "render: _render_dgrid cross rule"    "┼"         "$_dg"
assert_contains "render: _render_dgrid label header"  "Model"     "$_dg"
assert_contains "render: _render_dgrid column header" "tokens"    "$_dg"
assert_contains "render: _render_dgrid row label"     "Haiku 4.5" "$_dg"
assert_contains "render: _render_dgrid cell value"    "11.0M"     "$_dg"

# A final row without a trailing newline must survive (shared-renderer robustness
# — future consumers may pipe an unterminated stream).
_dgnt=$(printf '%s' $'A\x1f1\nB\x1f22' | _render_dgrid "L" "C")
assert_contains "render: _render_dgrid keeps unterminated final row" "22" "$_dgnt"
unset _bc _br _dg _dgnt

# ── awk ↔ bash parity (non-boundary values; 0 differs by design: awk "" / bash 0) ──
for _v in 500 1000 5000 250000 5200000 140000000 2300000000; do
  _a=$(_fmtawk "print fmt_tok($_v)")
  _b=$(_fmt_tok "$_v")
  assert_eq "fmt parity awk==bash for $_v" "$_a" "$_b"
done
unset _v _a _b

# ── bash 3.2 regression (macOS /bin/bash) — render.sh must run under the CI shell ──
# Local `bash` is Homebrew 5.x; CI macos-latest runs /bin/bash 3.2. Invoke it
# explicitly so a 3.2-only breakage (arithmetic, [[ =~ ]], param expansion) is
# caught here instead of only on CI.
if [[ -x /bin/bash ]]; then
  _r32=$(/bin/bash -c '
    source "'"$CLAUDII_HOME"'/lib/visual.sh"
    source "'"$CLAUDII_HOME"'/lib/render.sh"
    printf "%s|%s|%s" "$(_fmt_tok 5200000)" "$(_bar 3 5)" "$(_cache_hit_pct 950 50)"
  ' 2>&1)
  assert_eq "render: works under /bin/bash 3.2" "5.2M|███░░|95" "$_r32"
  unset _r32

  # _render_dgrid uses arrays + IFS=$'\x1f' read -a + flattened indices — all
  # 3.2-safe in theory; assert it under the CI shell. The 0x1f-delimited input
  # is written by THIS (5.x) shell into a temp file so /bin/bash never has to
  # printf \x1f itself.
  _dgfile="$(mktemp)"
  printf '%s' $'Opus\x1f11.0M\nHaiku\x1f600K\n' > "$_dgfile"
  _r32d=$(/bin/bash -c '
    source "'"$CLAUDII_HOME"'/lib/visual.sh"
    source "'"$CLAUDII_HOME"'/lib/render.sh"
    _render_dgrid "Model" "tokens" < "'"$_dgfile"'"
  ' 2>&1)
  assert_contains "render: _render_dgrid under /bin/bash 3.2 (┼ rule)" "┼"     "$_r32d"
  assert_contains "render: _render_dgrid 3.2 widest cell aligned"      "11.0M" "$_r32d"
  rm -f "$_dgfile"
  unset _r32d _dgfile
fi
