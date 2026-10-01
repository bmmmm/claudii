# perf_json.jq — the merged shape → the `claudii perf --json` document
# (lib/cmd/perf.sh). Used with `jq -L lib`.
include "perf_common";

def perf_json($days; $floor; $repo; $src):
  perf_latency($floor; $repo) as $L
  | {
      window_days: $days,
      source: $src,
      repo: (if $repo == "" then null else $repo end),
      total_samples: ($L | length),
      summary: ( ([$L[].dt_ms] | sort) as $s | {
        p50_ms: pct($s; 0.5),
        p90_ms: pct($s; 0.9),
        p99_ms: pct($s; 0.99),
        tok_s:  toks(([$L[].out] | add // 0); ([$L[].dt_ms] | add // 0)),
        samples: ($L | length)
      } ),
      by_model: ( $L | group_by(.model | mname)
        | map(perf_group as $g
              | { model: (.[0].model | mname), p50_ms: pct($g.d; 0.5),
                  p90_ms: pct($g.d; 0.9), p99_ms: pct($g.d; 0.99),
                  tok_s: toks($g.o; $g.t), samples: $g.n })
        | sort_by(-.samples) ),
      by_day: ( $L | group_by(.day)
        | map(perf_group as $g | { day: .[0].day, p50_ms: pct($g.d; 0.5), samples: $g.n })
        | sort_by(.day) ),
      by_repo: ( $L | group_by(.repo)
        | map(perf_group as $g
              | { repo: .[0].repo, p50_ms: pct($g.d; 0.5),
                  p90_ms: pct($g.d; 0.9),
                  tok_s: toks($g.o; $g.t), samples: $g.n })
        | sort_by(-.samples) ),
      by_window: ( $L | group_by(wkey_n)
        | map(perf_group as $g
              | { bucket: ({"1":"<50k","2":"50-100k","3":"100-200k","4":"200-400k","5":"400k+","9":"unknown"}[.[0] | wkey_n | tostring]),
                  p50_ms: pct($g.d; 0.5), p90_ms: pct($g.d; 0.9),
                  p99_ms: pct($g.d; 0.99),
                  tok_s: toks($g.o; $g.t), samples: $g.n }) ),
      ttft: ( ([$L[].ttft_ms] | map(select(. != null)) | sort) as $tt
        | if ($tt | length) > 0
          then { p50_ms: pct($tt; 0.5), p90_ms: pct($tt; 0.9), p99_ms: pct($tt; 0.99), samples: ($tt | length) }
          else null end ),
      reliability: ( [$L[] | select(.success != null)] as $sl
        | if ($sl | length) > 0
          then { total: ($sl | length), ok: ([$sl[] | select(.success == true)] | length),
                 retried: ([$sl[] | select((.attempt // 0) > 1)] | length) }
          else null end ),
      errors: ( perf_errors($floor; $repo)
        | group_by(.status_code)
        | map({ status_code: .[0].status_code, count: length }) )
    };
