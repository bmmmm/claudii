# touches: lib/cmd/insights.sh lib/repos.jq lib/insights.jq bin/claudii-insights lib/timefmt.sh

# test_repos.sh — claudii repos (sessions per repo with real/active duration)
# End-to-end against a synthetic project tree. The load-bearing assertions:
#   1. active time is gap-capped (a 25min pause does NOT count; wall span does)
#   2. sidechain records never contribute to active time (they interleave)
#   3. headless noise (TMPDIR cwd, < 2min activity) folds into the summary
#      line by default, appears with --all, and is always listed in the
#      drilldown of an explicitly named repo.

_RP_TMPDIRS=()
trap 'rm -rf "${_RP_TMPDIRS[@]}" 2>/dev/null' EXIT

_RP_PROJ="$(mktemp -d)"; _RP_TMPDIRS+=("$_RP_PROJ")
_RP_CACHE="$(mktemp -d)"; _RP_TMPDIRS+=("$_RP_CACHE")
mkdir -p "$_RP_PROJ/-test-repos"

# epoch+offset → ISO (BSD/GNU date)
_rp_iso() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
_RP_BASE=$(( $(date +%s) - 7200 ))

# Session A (repo alpha): deltas 120 + 60 + [1500 idle, skipped] + 60 → active 240.
# A trailing sidechain record extends last_seen (span 3300) but not active time.
_RP_SID_A="aaaaaaaa-1111-2222-3333-444444444444"
{
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"user","content":"hi"}}\n'       "$(_rp_iso "$_RP_BASE")" "$_RP_SID_A"
  printf '{"type":"assistant","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$(_rp_iso $(( _RP_BASE + 120 )))" "$_RP_SID_A"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"user","content":"more"}}\n'     "$(_rp_iso $(( _RP_BASE + 180 )))" "$_RP_SID_A"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"user","content":"back"}}\n'     "$(_rp_iso $(( _RP_BASE + 1680 )))" "$_RP_SID_A"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"user","content":"end"}}\n'      "$(_rp_iso $(( _RP_BASE + 1740 )))" "$_RP_SID_A"
  printf '{"type":"assistant","isSidechain":true,"timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"assistant","model":"claude-haiku-4-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$(_rp_iso $(( _RP_BASE + 3300 )))" "$_RP_SID_A"
} > "$_RP_PROJ/-test-repos/$_RP_SID_A.jsonl"

# Session B (TMPDIR cwd → headless regardless of duration): active 200.
_RP_SID_B="bbbbbbbb-1111-2222-3333-444444444444"
{
  printf '{"type":"user","timestamp":"%s","cwd":"/private/var/folders/fy/x/T","sessionId":"%s","message":{"role":"user","content":"h"}}\n' "$(_rp_iso "$_RP_BASE")" "$_RP_SID_B"
  printf '{"type":"user","timestamp":"%s","cwd":"/private/var/folders/fy/x/T","sessionId":"%s","message":{"role":"user","content":"b"}}\n' "$(_rp_iso $(( _RP_BASE + 200 )))" "$_RP_SID_B"
} > "$_RP_PROJ/-test-repos/$_RP_SID_B.jsonl"

# Session D (worktree cwd, current harness style .claude/worktrees/<agent>):
# must roll up under repo beta, never under the throwaway agent name.
_RP_SID_D="dddddddd-1111-2222-3333-444444444444"
{
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/beta/.claude/worktrees/agent-zz9","sessionId":"%s","message":{"role":"user","content":"w"}}\n' "$(_rp_iso $(( _RP_BASE + 100 )))" "$_RP_SID_D"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/beta/.claude/worktrees/agent-zz9","sessionId":"%s","message":{"role":"user","content":"w2"}}\n' "$(_rp_iso $(( _RP_BASE + 250 )))" "$_RP_SID_D"
} > "$_RP_PROJ/-test-repos/$_RP_SID_D.jsonl"

# Session C (repo alpha, micro: 30s active < 2min → headless by default).
_RP_SID_C="cccccccc-1111-2222-3333-444444444444"
{
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"user","content":"q"}}\n' "$(_rp_iso $(( _RP_BASE + 5000 )))" "$_RP_SID_C"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/alpha","sessionId":"%s","message":{"role":"user","content":"a"}}\n' "$(_rp_iso $(( _RP_BASE + 5030 )))" "$_RP_SID_C"
} > "$_RP_PROJ/-test-repos/$_RP_SID_C.jsonl"

# Session E (repo gamma) — F1 regression: a main-thread record with an EMPTY
# timestamp (truthy-but-unparseable in jq). It must NOT crash aggregation and
# must NOT credit active time or move the active-time baseline. Deltas: r1
# baseline → [empty, skipped] → r3 60s later → active 60. The empty "" also
# leaks into first_seen (empty string sorts before any real ISO), so this cache
# additionally exercises repos.jq's corrupt-end select-guard: the session is
# dropped from the view instead of crashing the whole `claudii repos` render.
_RP_SID_E="eeeeeeee-1111-2222-3333-444444444444"
{
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/gamma","sessionId":"%s","message":{"role":"user","content":"g1"}}\n' "$(_rp_iso $(( _RP_BASE + 10 )))" "$_RP_SID_E"
  printf '{"type":"user","timestamp":"","cwd":"/opt/tester/gamma","sessionId":"%s","message":{"role":"user","content":"garbage"}}\n' "$_RP_SID_E"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/gamma","sessionId":"%s","message":{"role":"user","content":"g3"}}\n' "$(_rp_iso $(( _RP_BASE + 70 )))" "$_RP_SID_E"
} > "$_RP_PROJ/-test-repos/$_RP_SID_E.jsonl"

# Session F (repo snaptest) — F5 regression: an isSnapshotUpdate record must be
# excluded from active time exactly like a sidechain. Deltas: r1 baseline → r2
# (+130, delta 130 ≤ 600) → snapshot at +190 (60s after r2) → r3 at +900 (gap
# from r2 = 770 > 600, idle → skipped). Active = 130. If the snapshot were
# counted it would add its own 60s delta (130 → 190) AND move the baseline to
# +190, so the assert on 130 fails the moment snapshots leak in. 130 ≥ 120 keeps
# the session non-headless so the existing "headless n=2" asserts stay valid.
_RP_SID_F="ffffffff-1111-2222-3333-444444444444"
{
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/snaptest","sessionId":"%s","message":{"role":"user","content":"s1"}}\n' "$(_rp_iso $(( _RP_BASE + 0 )))" "$_RP_SID_F"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/snaptest","sessionId":"%s","message":{"role":"user","content":"s2"}}\n' "$(_rp_iso $(( _RP_BASE + 130 )))" "$_RP_SID_F"
  printf '{"type":"user","isSnapshotUpdate":true,"timestamp":"%s","cwd":"/opt/tester/snaptest","sessionId":"%s","message":{"role":"user","content":"snap"}}\n' "$(_rp_iso $(( _RP_BASE + 190 )))" "$_RP_SID_F"
  printf '{"type":"user","timestamp":"%s","cwd":"/opt/tester/snaptest","sessionId":"%s","message":{"role":"user","content":"s3"}}\n' "$(_rp_iso $(( _RP_BASE + 900 )))" "$_RP_SID_F"
} > "$_RP_PROJ/-test-repos/$_RP_SID_F.jsonl"

_rp_run() {
  CLAUDE_PROJECTS_DIR="$_RP_PROJ" CLAUDII_CACHE_DIR="$_RP_CACHE" \
    bash "$CLAUDII_HOME/bin/claudii" "$@" 2>&1
}

# ── Aggregator: gap-capped active_by_day, sidechain excluded ──
_RP_OUT=$(_rp_run repos)
_RP_A_JSON="$_RP_CACHE/insights/$_RP_SID_A.json"
assert_eq "repos: session A cache exists" "1" "$([ -s "$_RP_A_JSON" ] && echo 1 || echo 0)"
assert_eq "repos: A active total == 240 (gap>600s skipped, sidechain excluded)" "240" \
  "$(jq '[.active_by_day[]] | add' "$_RP_A_JSON")"
assert_eq "repos: A schema_version == 10" "10" "$(jq '.schema_version' "$_RP_A_JSON")"

# ── F1: empty-timestamp record neither crashes aggregation nor moves baseline ──
_RP_E_JSON="$_RP_CACHE/insights/$_RP_SID_E.json"
assert_eq "repos: F1 session E cache still written (empty ts did not crash agg)" "1" \
  "$([ -s "$_RP_E_JSON" ] && echo 1 || echo 0)"
assert_eq "repos: F1 E active == 60 (empty-ts record skipped, baseline unmoved)" "60" \
  "$(jq '[.active_by_day[]] | add' "$_RP_E_JSON")"
# The corrupt first_seen ("" from the empty-ts record) must not kill the view:
# repos.jq drops session E via its parse-guard, alpha still renders.
assert_contains "repos: F1 view still renders (no aggregation-failed crash)" "alpha" "$_RP_OUT"
assert_not_contains "repos: F1 no aggregation-failed message" "aggregation failed" "$_RP_OUT"

# ── F5: isSnapshotUpdate record excluded from active time ──
_RP_F_JSON="$_RP_CACHE/insights/$_RP_SID_F.json"
assert_eq "repos: F5 session F cache exists" "1" \
  "$([ -s "$_RP_F_JSON" ] && echo 1 || echo 0)"
assert_eq "repos: F5 F active == 130 (snapshot excluded; counted would give 190)" "130" \
  "$(jq '[.active_by_day[]] | add' "$_RP_F_JSON")"

# ── Default view: repo table, headless folded ──
assert_contains "repos: header"            "claudii repos"  "$_RP_OUT"
assert_contains "repos: default window"    "last 30 days"   "$_RP_OUT"
assert_contains "repos: alpha row"         "alpha"          "$_RP_OUT"
assert_contains "repos: median column"     "median"         "$_RP_OUT"
assert_contains "repos: active 4m (240s)"  "4m"             "$_RP_OUT"
assert_contains "repos: headless summary (B tmp + C micro)" "(headless) 2 runs" "$_RP_OUT"
assert_not_contains "repos: no (tmp) row by default" "(tmp)" "$_RP_OUT"
assert_no_literal_ansi "repos: no literal \\033" "$_RP_OUT"

# ── --all: headless rows inline, no summary line ──
_RP_ALL=$(_rp_run repos --all)
assert_contains "repos --all: (tmp) row shown"      "(tmp)"      "$_RP_ALL"
assert_not_contains "repos --all: no summary line"  "(headless)" "$_RP_ALL"

# ── --json: exact numbers ──
_RP_JSON=$(_rp_run repos --json)
assert_eq "repos --json: well-formed" "0" "$(printf '%s' "$_RP_JSON" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "repos --json: window_days=30" "30" "$(printf '%s' "$_RP_JSON" | jq -r '.window_days')"
assert_eq "repos --json: alpha n=1 (micro C filtered)" "1" \
  "$(printf '%s' "$_RP_JSON" | jq -r '.by_repo[] | select(.repo=="alpha") | .n')"
assert_eq "repos --json: alpha total_active=240" "240" \
  "$(printf '%s' "$_RP_JSON" | jq -r '.by_repo[] | select(.repo=="alpha") | .total_active')"
assert_eq "repos --json: alpha total_span=3300 (sidechain extends span, not active)" "3300" \
  "$(printf '%s' "$_RP_JSON" | jq -r '.by_repo[] | select(.repo=="alpha") | .total_span')"
assert_eq "repos --json: headless n=2" "2" "$(printf '%s' "$_RP_JSON" | jq -r '.headless.n')"
assert_eq "repos --json: worktree D rolls up under beta" "1" \
  "$(printf '%s' "$_RP_JSON" | jq -r '.by_repo[] | select(.repo=="beta") | .n')"
assert_eq "repos --json: no agent-* repo row" "" \
  "$(printf '%s' "$_RP_JSON" | jq -r '.by_repo[] | select(.repo | startswith("agent-")) | .repo')"

# ── Drilldown: named repo lists ALL its sessions incl. micro ──
_RP_DRILL=$(_rp_run repos alpha)
assert_contains "repos alpha: session A id"        "${_RP_SID_A:0:8}" "$_RP_DRILL"
assert_contains "repos alpha: micro C listed"      "${_RP_SID_C:0:8}" "$_RP_DRILL"
assert_contains "repos alpha: micro C marked"      "headless"         "$_RP_DRILL"
assert_contains "repos alpha: span shown"          "span"             "$_RP_DRILL"

# ── --daily: per-day rows with repo · count · duration ──
# The expected label is computed, not hardcoded "Today": shortly after UTC
# midnight the fixture's timestamps (base = now-2h) land on the PREVIOUS UTC
# day, and a hardcoded assert would fail deterministically in that window.
_RP_DAY_A=$(date -u -r $(( _RP_BASE + 1740 )) +%Y-%m-%d 2>/dev/null \
  || date -u -d "@$(( _RP_BASE + 1740 ))" +%Y-%m-%d)
if [[ "$_RP_DAY_A" == "$(date -u +%Y-%m-%d)" ]]; then
  _RP_LBL="Today"
else
  _RP_LBL=$(LC_TIME=C date -j -f %Y-%m-%d "$_RP_DAY_A" +'%a %d %b' 2>/dev/null \
    || LC_TIME=C date -d "$_RP_DAY_A" +'%a %d %b' 2>/dev/null)
fi
_RP_DAILY=$(_rp_run repos --daily)
assert_contains "repos --daily: day label"     "$_RP_LBL" "$_RP_DAILY"
assert_contains "repos --daily: alpha listed"  "alpha"    "$_RP_DAILY"
assert_contains "repos --daily: session count" "1×"       "$_RP_DAILY"

# ── Window / arg validation ──
_RP_BAD=$(_rp_run repos --frobnicate; echo "rc=$?")
assert_contains "repos --frobnicate: names bad option" "unknown repos option" "$_RP_BAD"
assert_contains "repos --frobnicate: exit 1" "rc=1" "$_RP_BAD"

# Bare number is a window typo, not a repo drilldown → actionable error
_RP_NUM=$(_rp_run repos 14; echo "rc=$?")
assert_contains "repos 14: suggests 14d"  "did you mean 14d" "$_RP_NUM"
assert_contains "repos 14: exit 1"        "rc=1"             "$_RP_NUM"

# Trailing value-less --days errors instead of silently becoming 7d
_RP_ND=$(_rp_run repos --days; echo "rc=$?")
assert_contains "repos --days (no value): actionable error" "needs a value" "$_RP_ND"
assert_contains "repos --days (no value): exit 1"           "rc=1"          "$_RP_ND"

# --daily must NOT be swallowed as the --days value (was: "got: --daily")
_RP_NDF=$(_rp_run repos --days --daily; echo "rc=$?")
assert_contains "repos --days --daily: needs a value (flag not consumed)" "needs a value" "$_RP_NDF"
assert_contains "repos --days --daily: exit 1"                            "rc=1"          "$_RP_NDF"

# ── Shared-parser coverage: the same guards now protect tokens/tools/etc. ──
# value-less --days is an actionable error, not a silent 7d fallback.
_RP_TND=$(_rp_run tokens --days; echo "rc=$?")
assert_contains "tokens --days (no value): needs a value" "needs a value" "$_RP_TND"
assert_contains "tokens --days (no value): exit 1"        "rc=1"          "$_RP_TND"

# a bare number is a window typo for tokens too, not a generic unknown-arg.
_RP_T14=$(_rp_run tokens 14; echo "rc=$?")
assert_contains "tokens 14: suggests 14d" "did you mean 14d" "$_RP_T14"
assert_contains "tokens 14: exit 1"       "rc=1"             "$_RP_T14"

# ── Drilldown escape hatch: window FIRST, then a repo name that looks like a
# window — "year" is captured as the positional, so we drill into repo "year". ──
_RP_ESC=$(_rp_run repos 365d year)
assert_contains "repos 365d year: 'year' is the repo positional, not the window" \
  "no sessions for year" "$_RP_ESC"

_RP_HELP=$(bash "$CLAUDII_HOME/bin/claudii" repos --help 2>&1)
assert_contains "repos --help: usage line" "Usage: claudii repos" "$_RP_HELP"

# ── Empty cache: message + same-shape JSON envelope ──
_RP_EPROJ="$(mktemp -d)"; _RP_TMPDIRS+=("$_RP_EPROJ")
_RP_ECACHE="$(mktemp -d)"; _RP_TMPDIRS+=("$_RP_ECACHE")
_RP_EOUT=$(CLAUDE_PROJECTS_DIR="$_RP_EPROJ" CLAUDII_CACHE_DIR="$_RP_ECACHE" \
  bash "$CLAUDII_HOME/bin/claudii" repos 2>&1)
assert_contains "repos (empty): empty-state message" "No insight data" "$_RP_EOUT"
_RP_EJSON=$(CLAUDE_PROJECTS_DIR="$_RP_EPROJ" CLAUDII_CACHE_DIR="$_RP_ECACHE" \
  bash "$CLAUDII_HOME/bin/claudii" repos --json 2>&1)
assert_eq "repos --json (empty): well-formed, by_repo []" "0" \
  "$(printf '%s' "$_RP_EJSON" | jq -r '.by_repo | length')"

# --tsv rejected with pointer
_RP_TSV=$(_rp_run repos --tsv; echo "rc=$?")
assert_contains "repos --tsv: rejected, points to --json" "use --json" "$_RP_TSV"

unset _RP_PROJ _RP_CACHE _RP_BASE _RP_SID_A _RP_SID_B _RP_SID_C _RP_SID_D _RP_SID_E _RP_SID_F _RP_A_JSON _RP_E_JSON _RP_F_JSON
unset _RP_OUT _RP_ALL _RP_JSON _RP_DRILL _RP_DAILY _RP_DAY_A _RP_LBL _RP_BAD _RP_NUM _RP_ND _RP_HELP
unset _RP_NDF _RP_TND _RP_T14 _RP_ESC
unset _RP_EPROJ _RP_ECACHE _RP_EOUT _RP_EJSON _RP_TSV
unset -f _rp_iso _rp_run
