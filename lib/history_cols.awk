# history_cols.awk — the claudii history TSV schema, declared once.
#
# Every raw history row bin/claudii-cc-statusline appends is described by
# HC_SCHEMA below. Nothing downstream may hard-code a column number; it asks
# HC[] instead. Load this file with -f (or string-interpolate it) BEFORE the
# program that reads history — the maps are built in its BEGIN block:
#
#   awk -f lib/history_cols.awk -f lib/history_rows.awk …
#
# Adding a column is ONE edit: append "<name>:<kind>" to HC_SCHEMA. History
# rows are APPENDED, never inserted, so a new column always lands last and no
# existing index moves. <kind> is `n` (numeric — an empty field reads as 0) or
# `s` (string, passed through verbatim); lib/history_rows.awk uses the kind to
# decide how to coerce the field, so one edit here is enough to make a new
# column emittable.
#
# Exposes (globals, after BEGIN):
#   HC[name]       1-based column index of a raw history column
#   HC_KIND[name]  "n" or "s"
#   HC_NCOL        number of columns in the current schema
#   HC_MINCOL      shortest row still worth parsing — the session-id column.
#                  Every aggregation keys on the session id, so a row that
#                  stops before it carries nothing usable. This replaced the
#                  literal `NF < 6` that had been copied into six programs.
#   HC_TS HC_MODEL HC_COST HC_CTX HC_RATE_5H HC_SID HC_IN HC_OUT HC_API
#   HC_RATE_7D HC_RESET_7D — the same indices as plain scalars, so a reader can
#                  write the readable `$HC_TS` instead of `$(HC["ts"])`.
#
# Variables (-v) this program reads:
#   emit — OPTIONAL, and NOT part of the raw schema. It is the field list
#          lib/history_rows.awk was told to print (see there). When the caller
#          passes the same string to a stage-2 program, HR[name] gives the
#          1-based index of each field in those normalized rows — so the
#          consumer never repeats the layout its producer was configured with.
#          Raw-history readers leave it unset; HR[] then stays empty.
#
# Callers must run awk under LC_ALL=C (see docs/gotchas.md): the cost column is
# a dot-decimal and a comma locale truncates "12.34"+0 to 12.

BEGIN {
  # The 11-column layout bin/claudii-cc-statusline writes, in order. Mirrored
  # by hist_row() in tests/run.sh, which is the only way fixtures may spell it.
  HC_SCHEMA = "ts:n model:s cost:n ctx:n rate5h:n sid:s in:n out:n api:n rate7d:n reset7d:n"

  HC_NCOL = split(HC_SCHEMA, _hc_col, " ")
  for (_hc_i = 1; _hc_i <= HC_NCOL; _hc_i++) {
    split(_hc_col[_hc_i], _hc_p, ":")
    HC[_hc_p[1]]      = _hc_i
    HC_KIND[_hc_p[1]] = _hc_p[2]
  }

  HC_TS      = HC["ts"];     HC_MODEL   = HC["model"];  HC_COST     = HC["cost"]
  HC_CTX     = HC["ctx"];    HC_RATE_5H = HC["rate5h"]; HC_SID      = HC["sid"]
  HC_IN      = HC["in"];     HC_OUT     = HC["out"];    HC_API      = HC["api"]
  HC_RATE_7D = HC["rate7d"]; HC_RESET_7D = HC["reset7d"]
  HC_MINCOL  = HC_SID

  # Normalized stage-1 rows (lib/history_rows.awk), when the caller says so.
  if (emit != "") {
    HR_NCOL = split(emit, _hr_f, " ")
    for (_hr_i = 1; _hr_i <= HR_NCOL; _hr_i++) HR[_hr_f[_hr_i]] = _hr_i
  }
}
