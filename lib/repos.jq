# repos.jq — per-repo session overview from the per-session insights caches.
# Called from _cmd_repos (lib/cmd/insights.sh) with:
#   jq -n --arg cutoff <iso|""> --arg floor <YYYY-MM-DD|""> --arg repo <name|"">
#      --argjson all <bool> -f lib/repos.jq <cache files...>
#
# cutoff: include sessions with last_seen >= cutoff ("" = no bound, like merge).
# floor:  by_day rows only for day >= floor (keeps --daily inside the window).
# repo:   non-empty = drilldown; sessions[] carries that repo's sessions and
#         headless filtering is suspended (an explicitly named repo shows all).
# all:    true = headless sessions stay in by_repo/by_day instead of the
#         (headless) summary bucket.
#
# "active" is the gap-capped active time (active_by_day, schema v9) — the
# real working time. Pre-v9 orphaned caches (source JSONL gone, can never be
# re-aggregated) lack the field: active stays null there, they are never
# classified as micro, and they are skipped in median/total sums.
def ts: .[0:19] + "Z" | fromdateiso8601;

[ inputs
  | select(type == "object")
  | select((.first_seen // null) != null and (.last_seen // null) != null)
  | select(($cutoff == "") or (.last_seen >= $cutoff))
  | {
      sid:   (.sessionId // ""),
      repo:  (if ((.project.path // "") | test("^(/private)?(/var/folders/|/tmp/)")) then "(tmp)"
              else (.project.repo // "?") end),
      day:   (.first_seen[:10]),
      first: .first_seen,
      last:  .last_seen,
      msgs:  (.messages // 0),
      span:  ((.last_seen | ts) - (.first_seen | ts)),
      # capped at span: truncated millis / rare out-of-order timestamps can
      # push the delta sum a few seconds past the wall clock, which renders
      # as "active > span" after rounding
      active: (if has("active_by_day")
               then ([([.active_by_day[]] | add // 0), ((.last_seen | ts) - (.first_seen | ts))] | min)
               else null end),
      # window-floored variant for by_repo: a session is admitted by last_seen,
      # but activity on days before the window must not inflate the table
      active_win: (if has("active_by_day")
               then ([([.active_by_day | to_entries[] | select(($floor == "") or (.key >= $floor)) | .value] | add // 0),
                      ((.last_seen | ts) - (.first_seen | ts))] | min)
               else null end),
      abd:   (.active_by_day // {})
    }
  # headless = TMPDIR run or micro session (< 2 min real activity)
  | . + {hl: ((.repo == "(tmp)") or (.active != null and .active < 120))}
] as $S
| ($S | map(select($all or (.hl | not)))) as $vis
| {
    by_repo: (
      $vis | group_by(.repo)
      | map((map(.active_win) | map(select(. != null)) | sort) as $act
        | { repo: .[0].repo,
            n: length,
            median_active: (if ($act | length) > 0 then $act[($act | length) / 2 | floor] else null end),
            total_active:  ($act | add // 0),
            total_span:    (map(.span) | add // 0) })
      | sort_by(-.total_active)
    ),
    headless: (
      ($S | map(select(.hl))) as $h
      | {n: ($h | length), total_active: ([$h[].active | select(. != null)] | add // 0)}
    ),
    by_day: (
      [ $vis[]
        # a session counts on every day it was active on; sessions without
        # active data (pre-v9 orphans) count on their start day
        | . as $s
        | (if (.abd | length) > 0 then (.abd | to_entries[] | {day: .key, sec: .value})
           else {day: $s.day, sec: null} end)
        | select(($floor == "") or (.day >= $floor))
        | {day, repo: $s.repo, sec}
      ]
      | group_by([.day, .repo])
      | map({ day: .[0].day, repo: .[0].repo, n: length,
              active: ([.[].sec | select(. != null)] | add // 0) })
      | sort_by(.day) | reverse
    ),
    sessions: (
      if $repo == "" then []
      else
        $S | map(select(.repo == $repo))
        | sort_by(.first) | reverse
        # full-session active here (not active_win): the drilldown row shows
        # the session itself, not its share of the window
        | map({sid, day, first, last, msgs, span, active, headless: .hl})
      end
    )
  }
