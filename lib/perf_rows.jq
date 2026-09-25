# perf_rows.jq — the merged shape → tagged TSV rows that `claudii perf`
# renders (lib/cmd/perf.sh): M=model, W=context window, D=day, R=repo,
# G=session, S=summary, T=TTFT, X=reliability, E=API errors.
# All numeric fields are tostring'd and non-empty so @tsv + IFS=$'\t' survive
# (the CLAUDE.md empty-field trap). Used with `jq -r -L lib`.
include "perf_common";

def perf_rows($floor; $repo):
  perf_latency($floor; $repo) as $L
  | perf_errors($floor; $repo) as $E
  | ( $L | group_by(.model | mname)
      | map({k: (.[0].model | mname)} + perf_group)
      | sort_by(-.n)
      | .[] | ["M", .k, (pct(.d; 0.5) | tostring), (pct(.d; 0.9) | tostring),
               (pct(.d; 0.99) | tostring), (toks(.o; .t) | tostring),
               (.n | tostring)] | @tsv ),
    ( $L | group_by(wkey_s)
      | map({k: (.[0] | wkey_s)} + perf_group)
      | sort_by(.k)
      | .[] | ["W", .k, (pct(.d; 0.5) | tostring), (pct(.d; 0.9) | tostring),
               (pct(.d; 0.99) | tostring), (toks(.o; .t) | tostring),
               (.n | tostring)] | @tsv ),
    ( $L | group_by(.day)
      | map({k: .[0].day} + perf_group)
      | sort_by(.k)
      | .[] | ["D", .k, (pct(.d; 0.5) | tostring), (.n | tostring)] | @tsv ),
    ( $L | group_by(.repo)
      | map({k: .[0].repo} + perf_group)
      | sort_by(-.n)
      | .[] | ["R", .k, (pct(.d; 0.5) | tostring), (pct(.d; 0.9) | tostring),
               (toks(.o; .t) | tostring), (.n | tostring)] | @tsv ),
    ( $L | group_by(.sessionId)
      | map({k: .[0].sessionId, rp: (.[0].repo // "?")} + perf_group)
      | sort_by(-.n) | .[:12]
      | .[] | ["G", .k, .rp, (pct(.d; 0.5) | tostring),
               (toks(.o; .t) | tostring), (.n | tostring)] | @tsv ),
    ( ([$L[].dt_ms] | sort) as $s
      | ["S", (pct($s; 0.5) | tostring), (pct($s; 0.9) | tostring),
         (pct($s; 0.99) | tostring),
         (toks(([$L[].out] | add // 0); ([$L[].dt_ms] | add // 0)) | tostring),
         (($L | length) | tostring)] | @tsv ),
    ( ([$L[].ttft_ms] | map(select(. != null)) | sort) as $tt
      | if ($tt | length) > 0 then
          ["T", (pct($tt; 0.5) | tostring), (pct($tt; 0.9) | tostring),
           (pct($tt; 0.99) | tostring), ($tt | length | tostring)] | @tsv
        else empty end ),
    ( [$L[] | select(.success != null)] as $sl
      | if ($sl | length) > 0 then
          ["X", ($sl | length | tostring),
                ([$sl[] | select(.success == true)] | length | tostring),
                ([$sl[] | select((.attempt // 0) > 1)] | length | tostring)] | @tsv
        else empty end ),
    ( $E | group_by(.status_code) | .[]
      | ["E", (.[0].status_code | tostring), (length | tostring)] | @tsv );
