# history_rows.awk — stage 1 of every history aggregation: one raw history row
# in, one normalized row out.
#
# Replaces the two near-identical augment programs that used to live inline in
# lib/cmd/cost.sh and lib/cmd/display.sh. They shared the CR strip, the row
# filter, the epoch→day conversion and the tier collapse, and differed only in
# WHICH fields they printed — so the field list is a parameter now (-v emit)
# instead of a second copy of the program.
#
# Load order (history_cols.awk first — its BEGIN builds HC[]/HC_KIND[]):
#   awk -F'\t' -v tz_offset=<secs> -v emit="<field> …" \
#       -f lib/epoch_to_date.awk -f lib/model_tier.awk \
#       -f lib/history_cols.awk  -f lib/history_rows.awk  <history files>
#
# Variables (-v) this program reads:
#   emit      — REQUIRED. Space-separated output field names, in order; the
#               row is printed tab-separated in exactly that order. An unknown
#               name is a hard error, not a silently empty column.
#   tz_offset — signed local UTC offset in seconds, consumed by epoch_to_date()
#               from lib/epoch_to_date.awk. Defaults to 0 (UTC) there.
#
# Field names: every raw column name declared in HC_SCHEMA
# (lib/history_cols.awk) — ts model cost ctx rate5h sid in out api rate7d
# reset7d — plus two derived ones:
#   day    the row's LOCAL calendar day, epoch_to_date(ts)
#   raw    the model column BEFORE the tier collapse ("Opus 4.6"), which the
#          cost legend needs to show a versioned display name
# `model` is always the tier-collapsed label (tier_label(), lib/model_tier.awk).
# Numeric columns (kind `n` in HC_SCHEMA) read an empty field as 0; string
# columns pass through untouched.
#
# Row filter — the guard that had been copy-pasted into six programs: CR
# stripped (history files synced across platforms carry CRLF), rows shorter
# than HC_MINCOL dropped, the header line dropped, and blank timestamp, blank
# session id or ts == 0 dropped.
#
# Callers must run awk under LC_ALL=C: the cost column is a dot-decimal and a
# comma locale truncates "12.34"+0 to 12 — corrupting the totals themselves,
# not just their rendering (docs/gotchas.md, the locale+awk lesson).

BEGIN {
  if (emit == "") {
    print "history_rows.awk: needs -v emit=\"<field> …\"" > "/dev/stderr"
    exit 2
  }
  _hr_n = split(emit, _hr_out, " ")
  for (_hr_j = 1; _hr_j <= _hr_n; _hr_j++) {
    _hr_name = _hr_out[_hr_j]
    if (_hr_name == "day" || _hr_name == "raw" || (_hr_name in HC)) continue
    print "history_rows.awk: unknown emit field \"" _hr_name "\"" \
          " — see HC_SCHEMA in lib/history_cols.awk" > "/dev/stderr"
    exit 2
  }
}

{ gsub(/\r/, "") }                # CRLF from history files synced across platforms
NF < HC_MINCOL { next }           # short / malformed row
$HC_TS == "timestamp" || $HC_TS == "" || $HC_SID == "" { next }

{
  ts = $HC_TS + 0
  if (ts == 0) next
  day = epoch_to_date(ts)

  _hr_line = ""
  for (_hr_j = 1; _hr_j <= _hr_n; _hr_j++) {
    _hr_name = _hr_out[_hr_j]
    if      (_hr_name == "day")   _hr_v = day
    else if (_hr_name == "raw")   _hr_v = $HC_MODEL
    else if (_hr_name == "model") _hr_v = tier_label($HC_MODEL)
    else if (HC_KIND[_hr_name] == "n")
                                  _hr_v = ($(HC[_hr_name]) == "" ? 0 : $(HC[_hr_name]) + 0)
    else                          _hr_v = $(HC[_hr_name])
    _hr_line = _hr_line (_hr_j > 1 ? "\t" : "") _hr_v
  }
  print _hr_line
}
