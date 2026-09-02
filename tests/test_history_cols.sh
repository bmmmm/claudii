# touches: lib/history_cols.awk lib/history_rows.awk lib/cmd/cost.sh lib/cmd/display.sh lib/trends.awk lib/forecast.awk lib/window.awk lib/window_bounds.awk lib/window_history.awk lib/usage_spark.awk
# test_history_cols.sh — the history TSV schema lives in ONE place.
#
# lib/history_cols.awk declares the column layout; lib/history_rows.awk is the
# single stage-1 normalizer both `claudii cost` and `claudii trends` run. These
# tests pin three things:
#   1. the declared indices (and that hist_row() writes exactly that shape),
#   2. that a TWELFTH column costs one edit — appending a name to HC_SCHEMA is
#      enough for a consumer to read it, and changes nothing that came before,
#   3. that the raw-history readers whose call sites this refactor did not
#      touch (lib/window*.awk, lib/usage_spark.awk) still read the columns the
#      schema declares — a behavioural drift gate, not a grep.

_hcd="$CLAUDII_TEST_TMP/history_cols"
rm -rf "$_hcd"; mkdir -p "$_hcd"
_hclib="$CLAUDII_HOME/lib"

# BEGIN blocks run in -f order, so a second program file sees the maps the
# first one built. This is also exactly how every call site loads it.
cat > "$_hcd/idx.awk" <<'AWK'
BEGIN { print (n in HC) ? HC[n] : "ABSENT" }
AWK
cat > "$_hcd/meta.awk" <<'AWK'
BEGIN { printf "%s %s %s\n", HC_NCOL, HC_MINCOL, HC_KIND["sid"] }
AWK

_hc_idx() { LC_ALL=C awk -v n="$1" -f "$_hclib/history_cols.awk" -f "$_hcd/idx.awk" </dev/null; }

# ── the declared schema ─────────────────────────────────────────────────────
assert_eq "schema: timestamp is column 1"    "1"  "$(_hc_idx ts)"
assert_eq "schema: model is column 2"        "2"  "$(_hc_idx model)"
assert_eq "schema: cost is column 3"         "3"  "$(_hc_idx cost)"
assert_eq "schema: context pct is column 4"  "4"  "$(_hc_idx ctx)"
assert_eq "schema: rate_5h is column 5"      "5"  "$(_hc_idx rate5h)"
assert_eq "schema: session id is column 6"   "6"  "$(_hc_idx sid)"
assert_eq "schema: input tokens are column 7"  "7"  "$(_hc_idx in)"
assert_eq "schema: output tokens are column 8" "8"  "$(_hc_idx out)"
assert_eq "schema: api duration is column 9"   "9"  "$(_hc_idx api)"
assert_eq "schema: rate_7d is column 10"     "10" "$(_hc_idx rate7d)"
assert_eq "schema: reset_7d is column 11"    "11" "$(_hc_idx reset7d)"
assert_eq "schema: an undeclared name is absent, not silently 0" \
  "ABSENT" "$(_hc_idx nosuchcolumn)"

_hc_meta=$(LC_ALL=C awk -f "$_hclib/history_cols.awk" -f "$_hcd/meta.awk" </dev/null)
assert_eq "schema: 11 columns, shortest usable row ends at the session id, sid is a string" \
  "11 6 s" "$_hc_meta"

# The fixture helper and the schema must describe the same file.
_hcf="$_hcd/h.tsv"
hist_row "$_hcf" 1788000001 "claude-opus-4-5" "1.50" 10 5 "sid-a" 1000 200 300 20 1788600000
assert_eq "hist_row() writes exactly HC_NCOL columns" \
  "11" "$(LC_ALL=C awk -F'\t' 'NR==1{print NF}' "$_hcf")"

# ── the single stage-1 normalizer ───────────────────────────────────────────
# Same load order the call sites use (lib/cmd/cost.sh, lib/cmd/display.sh).
_hr() {  # <emit list> <file>
  LC_ALL=C awk -F'\t' -v tz_offset=0 -v emit="$1" \
    -f "$_hclib/epoch_to_date.awk" \
    -f "$_hclib/model_tier.awk" \
    -f "$_hclib/history_cols.awk" \
    -f "$_hclib/history_rows.awk" \
    "$2"
}

# `claudii cost` field list — the one that keeps `raw` and `ts`.
_hc_cost_row=$(_hr "day model cost sid raw in out ts" "$_hcf")
assert_eq "cost rows carry eight fields" "8" \
  "$(LC_ALL=C awk -F'\t' '{print NF}' <<< "$_hc_cost_row")"
assert_matches "cost rows start with the local calendar day" \
  '^2026-08-2[89]$' "$(cut -f1 <<< "$_hc_cost_row")"
assert_eq "cost rows carry the tier label, not the raw model" \
  "Opus" "$(cut -f2 <<< "$_hc_cost_row")"
assert_eq "cost rows carry the cost column" "1.5" "$(cut -f3 <<< "$_hc_cost_row")"
assert_eq "cost rows carry the session id" "sid-a" "$(cut -f4 <<< "$_hc_cost_row")"
assert_eq "cost rows keep the raw model name beside the tier" \
  "claude-opus-4-5" "$(cut -f5 <<< "$_hc_cost_row")"
assert_eq "cost rows carry the input tokens"  "1000" "$(cut -f6 <<< "$_hc_cost_row")"
assert_eq "cost rows carry the output tokens" "200"  "$(cut -f7 <<< "$_hc_cost_row")"
assert_eq "cost rows carry the epoch unrounded" "1788000001" "$(cut -f8 <<< "$_hc_cost_row")"

# `claudii trends` field list — the one that keeps `api` instead of raw/ts.
_hc_trends_row=$(_hr "day model cost sid in out api" "$_hcf")
assert_eq "trends rows carry seven fields" "7" \
  "$(LC_ALL=C awk -F'\t' '{print NF}' <<< "$_hc_trends_row")"
assert_eq "trends rows carry the api duration in the last field" \
  "300" "$(cut -f7 <<< "$_hc_trends_row")"
assert_not_contains "trends rows do not widen with the raw model name" \
  "claude-opus-4-5" "$_hc_trends_row"

# ── the row filter, once instead of six times ───────────────────────────────
# Legacy/deviant shapes stay explicit printf (see hist_row()'s note in run.sh).
_hcfilt="$_hcd/filter.tsv"
printf 'timestamp\tmodel\tcost\tctx\trate\tsession_id\tin\tout\tapi\trate7d\treset7d\n' > "$_hcfilt"
printf 'x\ty\tz\n' >> "$_hcfilt"
hist_row "$_hcfilt" 1788000002 "claude-sonnet-4-6" "2.00" 10 5 ""         1000 200 300
hist_row "$_hcfilt" 0          "claude-sonnet-4-6" "2.00" 10 5 "sid-zero" 1000 200 300
hist_row "$_hcfilt" 1788000003 "claude-haiku-4-5"  "3.00" 10 5 "sid-ok"   1000 200 300
assert_eq "header, short, blank-id and zero-epoch rows are all dropped once" \
  "sid-ok" "$(_hr "sid" "$_hcfilt")"

# CRLF: the CR only ever pollutes the LAST field, so pin it on a row whose
# last field is the session id.
printf '1788000005\tclaude-opus-4-5\t5.00\t10\t5\tsid-crlast\r\n' > "$_hcd/crlf.tsv"
assert_eq "a CRLF row survives with its last field stripped of the CR" \
  "sid-crlast" "$(_hr "sid" "$_hcd/crlf.tsv")"

# ── misconfiguration is loud ────────────────────────────────────────────────
_hc_chain="-f '$_hclib/epoch_to_date.awk' -f '$_hclib/model_tier.awk' -f '$_hclib/history_cols.awk' -f '$_hclib/history_rows.awk'"
assert_exit_code "history_rows.awk without -v emit exits 2" 2 \
  "LC_ALL=C awk -F'\t' $_hc_chain </dev/null"
assert_exit_code "history_rows.awk with an unknown emit field exits 2" 2 \
  "LC_ALL=C awk -F'\t' -v emit='day bogus' $_hc_chain </dev/null"
_hc_err=$(LC_ALL=C awk -F'\t' -v emit='day bogus' \
  -f "$_hclib/epoch_to_date.awk" -f "$_hclib/model_tier.awk" \
  -f "$_hclib/history_cols.awk" -f "$_hclib/history_rows.awk" </dev/null 2>&1 || true)
assert_contains "the unknown-field error points at the schema" \
  "HC_SCHEMA in lib/history_cols.awk" "$_hc_err"

# trends.awk indexes its input through HR[]; without it every field read would
# silently become $0 and the report would be wrong rather than absent.
_hc_trends_chain="-f '$_hclib/attribution.awk' -f '$_hclib/fmt.awk' -f '$_hclib/trends.awk'"
assert_exit_code "trends.awk without the emit layout exits 2 instead of reporting \$0" 2 \
  "LC_ALL=C awk -F'\t' $_hc_trends_chain </dev/null"
assert_exit_code "trends.awk with the emit layout runs" 0 \
  "LC_ALL=C awk -F'\t' -v emit='day model cost sid in out api' -f '$_hclib/history_cols.awk' $_hc_trends_chain </dev/null"

# Same for forecast.awk, which reads raw history through HC[].
_hc_fc_chain="-f '$_hclib/epoch_to_date.awk' -f '$_hclib/attribution.awk' -f '$_hclib/fmt.awk' -f '$_hclib/forecast.awk'"
assert_exit_code "forecast.awk without the schema exits 2 instead of reporting \$0" 2 \
  "LC_ALL=C awk -F'\t' -v fmt=tsv $_hc_fc_chain </dev/null"
assert_exit_code "forecast.awk with the schema runs" 0 \
  "LC_ALL=C awk -F'\t' -v fmt=tsv -f '$_hclib/history_cols.awk' $_hc_fc_chain </dev/null"

# ── a twelfth column costs ONE edit ─────────────────────────────────────────
# Append a name to HC_SCHEMA — nothing else — and a consumer can emit it.
_hc12="$_hcd/history_cols_12.awk"
sed 's/^  HC_SCHEMA = "\(.*\)"$/  HC_SCHEMA = "\1 cachehit:n"/' \
  "$_hclib/history_cols.awk" > "$_hc12"
assert_eq "one edit in HC_SCHEMA declares the twelfth column" \
  "12" "$(LC_ALL=C awk -v n=cachehit -f "$_hc12" -f "$_hcd/idx.awk" </dev/null)"

_hc11f="$_hcd/h11.tsv"
hist_row "$_hc11f" 1788000006 "claude-sonnet-4-6" "6.00" 10 5 "sid-12" 1000 200 300 20 1788600000
_hc12f="$_hcd/h12.tsv"
LC_ALL=C awk -F'\t' '{ print $0 "\t" 4242 }' "$_hc11f" > "$_hc12f"

_hc12_row=$(LC_ALL=C awk -F'\t' -v tz_offset=0 -v emit="sid cachehit" \
  -f "$_hclib/epoch_to_date.awk" -f "$_hclib/model_tier.awk" \
  -f "$_hc12" -f "$_hclib/history_rows.awk" "$_hc12f")
assert_eq "a consumer reads the twelfth column by name, no second edit" \
  "$(printf 'sid-12\t4242')" "$_hc12_row"

# …and the columns before it do not move (rows are appended, never inserted).
assert_eq "appending a column changes no existing field" \
  "$(_hr "day model cost sid raw in out ts" "$_hc11f")" \
  "$(_hr "day model cost sid raw in out ts" "$_hc12f")"

# ── drift gate: raw-history readers still read the declared columns ─────────
# lib/window*.awk and lib/usage_spark.awk are loaded from lib/cmd/week.sh and
# lib/cmd/overview.sh, which this change did not touch, so they still index by
# position. These assertions fail the moment either side moves.
_hcwb="$_hcd/wb.tsv"
for _hc_i in 1 2 3; do
  hist_row "$_hcwb" $(( 1788000000 + _hc_i )) "claude-opus-4-5" "1.00" 10 5 "sid-wb" \
    1000 200 300 20 1788600000
done
assert_eq "window_bounds.awk reads reset_7d from the declared column" \
  "1788600000" \
  "$(LC_ALL=C awk -F'\t' -f "$_hclib/window_bounds.awk" "$_hcwb" | cut -f1)"

_hcw="$_hcd/w.tsv"
hist_row "$_hcw" 1788000100 "claude-opus-4-5" "1.00" 10 5 "sid-w" 1000 200 300
hist_row "$_hcw" 1788000200 "claude-opus-4-5" "3.50" 10 5 "sid-w" 4000 800 300
_hcw_row=$(LC_ALL=C awk -F'\t' -v window_start=1788000000 \
  -f "$_hclib/attribution.awk" -f "$_hclib/window.awk" "$_hcw")
assert_eq "window.awk sums the declared input+output token columns" \
  "4800" "$(cut -f1 <<< "$_hcw_row")"
assert_eq "window.awk sums the declared cost column" \
  "350" "$(cut -f8 <<< "$_hcw_row")"

_hcus="$_hcd/us.tsv"
hist_row "$_hcus" 1787999900 "claude-opus-4-5" "1.00" 10 5 "sid-us" 1000 200 300
_hcus_out=$(LC_ALL=C awk -v today_epoch=1788000000 -v tz_offset=0 -v ndays=3 \
  -f "$_hclib/attribution.awk" -f "$_hclib/usage_spark.awk" "$_hcus")
assert_eq "usage_spark.awk totals the declared input+output token columns" \
  "1200" "$(sed -n '2p' <<< "$_hcus_out" | cut -f3)"

# forecast.awk was converted to the named indices; pin the two columns it reads
# beyond the timestamp — rate_5h (the burn slope) and cost (the month total).
_hcfc="$_hcd/fc.tsv"
hist_row "$_hcfc" 1787999400 "claude-opus-4-5" "1.00" 10 10 "sid-fc" 1000 200 300
hist_row "$_hcfc" 1787999700 "claude-opus-4-5" "2.00" 10 40 "sid-fc" 2000 400 300
_hcfc_out=$(LC_ALL=C awk -F'\t' \
  -v now=1788000000 -v tz_offset=0 -v reset5h=1788003600 -v rate_now=40 -v have5h=1 \
  -v today="2026-08-29" -v thismon="2026-08" -v lastmon="2026-07" -v monname="Aug" \
  -v dom=29 -v ndays=31 -v burnwin=1200 -v fmt=tsv \
  -f "$_hclib/history_cols.awk" -f "$_hclib/epoch_to_date.awk" \
  -f "$_hclib/attribution.awk" -f "$_hclib/fmt.awk" -f "$_hclib/forecast.awk" "$_hcfc")
assert_contains "forecast.awk reads rate_5h from the declared column" \
  "$(printf '5h_burn_pct_per_min\t6.000')" "$_hcfc_out"
assert_contains "forecast.awk reads cost from the declared column" \
  "$(printf 'month_spent\t2.00')" "$_hcfc_out"

rm -rf "$_hcd"
unset _hcd _hclib _hcf _hcfilt _hc11f _hc12f _hc12 _hcwb _hcw _hcus _hcfc
unset _hc_meta _hc_cost_row _hc_trends_row _hc_chain _hc_err _hc12_row _hcw_row
unset _hcus_out _hcfc_out _hc_i _hc_trends_chain _hc_fc_chain
unset -f _hc_idx _hr
