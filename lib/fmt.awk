# lib/fmt.awk — shared awk formatting helpers (tokens, bars, repeat).
#
# Pure function definitions, no BEGIN/main/END blocks, so this file composes
# with any awk program that includes it — either via `-f fmt.awk` (trends) or
# string-injection alongside the other awk libs (cost). Keep it free of
# top-level statements for that reason.
#
# Single source of truth for fmt_tok(): was duplicated inline in lib/cmd/cost.sh
# and lib/trends.awk, and mirrored in bash by _fmt_tok (lib/render.sh) — keep the
# three in sync on the K/M/B thresholds.

# Token / large-number short form: K/M/B. One decimal for M/B, rounded K, "" for 0.
# The empty-string-for-zero is load-bearing: trends/cost render "" (no "tok"
# suffix) for days/periods that carry no token data.
#
# Integer/string math, no printf %f — the M/B/K branches are immune to
# LC_NUMERIC (a comma locale would otherwise sprintf "5.2M" as "5,2M", breaking
# jq and the awk==bash parity with _fmt_tok in lib/render.sh). Token counts are
# integers, so the sub-1000 passthrough (t "") is exact too (awk converts an
# integral value via %d, not the locale-sensitive CONVFMT). Rounding mirrors
# _fmt_tok exactly (tenths, half-up): keep the two in lockstep.
function fmt_tok(t,   x) {
  # Promote at the ROUNDED boundary: 999500..999999 → 1.0M (not "1000K"),
  # 999.95M..999.99M → 1.0B. Keep in lockstep with _fmt_tok (lib/render.sh).
  if (t >= 999950000) { x = int((t + 50000000) / 100000000); return int(x / 10) "." (x % 10) "B" }
  if (t >= 999500)    { x = int((t + 50000) / 100000);       return int(x / 10) "." (x % 10) "M" }
  if (t >= 1000)       return int((t + 500) / 1000) "K"
  if (t > 0)           return t ""
  return ""
}

# Repeat string c, n times.
function rep(c, n,   s, i) { s = ""; for (i = 0; i < n; i++) s = s c; return s }

# Format a USD amount with thousands separators: 2367.4 → "$2,367.40".
# Pure integer/string math — no printf %f, so it is immune to LC_NUMERIC
# (a comma-decimal locale would otherwise turn the cents separator into a comma).
function fmt_usd(v,   neg, dollars, cents, s, out, len, i, c) {
  if (v < 0) { neg = 1; v = -v }
  dollars = int(v)
  cents = int((v - dollars) * 100 + 0.5)
  if (cents >= 100) { dollars += 1; cents -= 100 }
  s = dollars ""
  len = length(s); out = ""
  for (i = 1; i <= len; i++) {
    c = substr(s, i, 1)
    out = out c
    if (((len - i) % 3) == 0 && i < len) out = out ","
  }
  return (neg ? "-" : "") "$" out sprintf(".%02d", cents)
}

# Bar of `width` cells, `filled` of them full. full/empty default to the
# visual.sh block glyphs (█ / ░) when passed empty, so callers can write
# bar(f, 24) and still override for a different palette.
function bar(filled, width, full, empty,   s, i) {
  if (full == "")  full  = "\342\226\210"   # U+2588 FULL BLOCK
  if (empty == "") empty = "\342\226\221"   # U+2591 LIGHT SHADE
  if (filled < 0) filled = 0
  if (filled > width) filled = width
  s = ""
  for (i = 0; i < filled; i++)     s = s full
  for (i = filled; i < width; i++) s = s empty
  return s
}

# Filled cells for value/max over `width`, rounded, clamped to 0..width.
# max <= 0 → 0 (avoids div-by-zero on an all-empty group).
function bar_filled(value, max, width,   f) {
  if (max <= 0) return 0
  f = int(value * width / max + 0.5)
  if (f < 0) f = 0
  if (f > width) f = width
  return f
}
