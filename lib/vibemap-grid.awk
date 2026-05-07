# vibemap-grid.awk — aggregate vibemap.tsv into a (weekday × 3-hour-bin) grid.
#
# Input:  TSV with fields epoch, weekday(0-6, Sun=0), hour(0-23), minute,
#         model, sid8, delta_ms (one render per line).
# Output: TSV with fields weekday(0-6), bin(0-7), count.
#         Plus one final line: "max\t<n>" — the maximum cell count, used
#         by the shell renderer for density normalization.
#
# Bins: 8 three-hour blocks (00-03, 03-06, …, 21-00). Reads the whole file
# in one pass, no sorting required.

BEGIN { FS = "\t"; max = 0 }

NF >= 4 {
  wd = $2 + 0
  h  = $3 + 0
  if (wd < 0 || wd > 6 || h < 0 || h > 23) next
  bin = int(h / 3)
  count[wd, bin]++
  if (count[wd, bin] > max) max = count[wd, bin]
}

END {
  for (key in count) {
    split(key, parts, SUBSEP)
    printf "%s\t%s\t%d\n", parts[1], parts[2], count[key]
  }
  printf "max\t%d\n", max
}
