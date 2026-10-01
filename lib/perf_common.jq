# perf_common.jq — helpers shared by lib/perf_rows.jq and lib/perf_json.jq
# (both `include "perf_common";`, found via `jq -L "$CLAUDII_HOME/lib"`).
#
# Input of the perf_* programs: the merged shape {latency:[…], errors:[…]} —
# from `claudii-insights merge --with-latency` (transcript estimate) or from
# lib/otel_doc.jq (OTEL).

# pct takes an already SORTED list: each list is sorted once, not once per
# percentile (three percentiles of 200k samples sorted the same list 3×).
def pct($s; $p): ($s | length) as $n
  | if $n == 0 then 0 else $s[ ([($n * $p | floor), ($n - 1)] | min) ] end;
def toks($o; $d): if $d > 0 then ($o * 1000 / $d | floor) else 0 end;
# Model name without the "[1m]" context-window suffix (endswith/slice instead
# of a regex per row).
def mname: if endswith("[1m]") then .[:-4] else . end;
# Context-window bucket of a sample — numeric key for --json, sortable label
# for the rendered rows. Keep the boundaries (50k/100k/200k/400k) in sync;
# tests pin json/render label parity.
def wkey_n: (.ctx // -1)
  | if . < 0 then 9 elif . < 50000 then 1 elif . < 100000 then 2
    elif . < 200000 then 3 elif . < 400000 then 4 else 5 end;
def wkey_s: (.ctx // -1)
  | if . < 0 then "9_unknown" elif . < 50000 then "1_<50k"
    elif . < 100000 then "2_50-100k" elif . < 200000 then "3_100-200k"
    elif . < 400000 then "4_200-400k" else "5_400k+" end;
# The samples perf reports on: inside the window, optionally one repo, no
# synthetic or claudii-internal models.
def perf_latency($floor; $repo):
  [ (.latency // [])[]
    | select(.model != "<synthetic>" and (.model | startswith("claudii-") | not)
             and (.day >= $floor)
             and (($repo == "") or (.repo == $repo))) ];
def perf_errors($floor; $repo):
  [ (.errors // [])[]
    | select((.day >= $floor) and (($repo == "") or (.repo == $repo))) ];
# One group's stats: sorted durations for the percentiles, their sum in input
# order (a float sum must not change with the order), output tokens, count.
def perf_group: { d: ([.[].dt_ms] | sort), t: ([.[].dt_ms] | add),
                  o: ([.[].out] | add), n: length };
