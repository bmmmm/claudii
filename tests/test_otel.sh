# touches: bin/claudii-otel lib/otel_rows.jq lib/otel_doc.jq bin/claudii-otel-receiver lib/cmd/perf.sh lib/perf_rows.jq lib/perf_json.jq lib/perf_common.jq bin/claudii-insights

# test_otel.sh — claudii-otel (flat OTEL events → perf-cache shape), the perf
# OTEL source, and the receiver's flatten (OTLP batch → flat records).
#
# Fixtures are the FLAT records bin/claudii-otel-receiver writes under
# events/<kind>-DAY.ndjson: one JSON object per log record / span, attributes
# under their own keys, reserved keys prefixed "_". The receiver's own
# flattening is tested at the end against OTLP batches in Claude Code's real
# wire format (verified against a live http/json capture), and its rows are
# pinned to the rows the pre-events extractor produced from the same batches.
# Repo is resolved from session.id via the insights caches (OTEL events carry
# no cwd). One malformed line and one out-of-window span verify fromjson?
# skipping and the day floor.

_OTEL_TMPDIRS=()
trap 'rm -rf "${_OTEL_TMPDIRS[@]}" 2>/dev/null' EXIT
_OTEL_CACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_CACHE")
mkdir -p "$_OTEL_CACHE/otel/events" "$_OTEL_CACHE/insights"

_NOW=$(date -u +%s)
_NANO="${_NOW}000000000"
_OLD=$(( _NOW - 100 * 86400 )); _OLDNANO="${_OLD}000000000"
_utc_day() { date -u -d "@$1" +%Y-%m-%d 2>/dev/null || date -u -r "$1" +%Y-%m-%d; }
_TODAY=$(_utc_day "$_NOW")
_OLDDAY=$(_utc_day "$_OLD")

# session.id → repo map (OTEL has no cwd; perf's transcript path uses the same caches)
printf '%s\n' '{"sessionId":"otelsess-a","project":{"path":"/x/alpha","repo":"alpha","branch":"main"}}' > "$_OTEL_CACHE/insights/otelsess-a.json"
printf '%s\n' '{"sessionId":"otelsess-b","project":{"path":"/x/beta","repo":"beta","branch":"dev"}}'  > "$_OTEL_CACHE/insights/otelsess-b.json"

# one flat llm_request span: $1=session $2=nano $3=dt_ms $4=ttft $5=out $6=success $7=attempt
_llm() {
  printf '{"_sig":"span","_name":"claude_code.llm_request","_t":"%s","_end":"%s","_trace":"t1","_span":"s1","service.name":"claude-code","model":"claude-opus-4-8","duration_ms":%s,"ttft_ms":%s,"output_tokens":%s,"session.id":"%s","success":%s,"attempt":%s}\n' \
    "$2" "$2" "$3" "$4" "$5" "$1" "$6" "$7"
}
# one flat api_error log record: $1=session $2=nano $3=status_code
_errl() {
  printf '{"_sig":"log","_name":"claude_code.api_error","_t":"%s","service.name":"claude-code","model":"claude-opus-4-8","status_code":%s,"session.id":"%s"}\n' \
    "$2" "$3" "$1"
}

{
  _llm otelsess-a "$_NANO" 2000 1000 200 true 1
  _llm otelsess-a "$_NANO" 4000 2000 400 true 1
  _llm otelsess-a "$_NANO" 6000 3000 600 true 1
  _llm otelsess-b "$_NANO" 8000 4000 800 false 2     # failed + a retry
  _llm ghostsess  "$_NANO" 5000 2500 500 true 1      # no insights cache → repo "?"
  printf '%s\n' 'this is not json — fromjson? must skip it'
} > "$_OTEL_CACHE/otel/events/llm-$_TODAY.ndjson"
# a closed day: compacted (gzip + rows) by the first build
_llm otelsess-a "$_OLDNANO" 9999 9999 9999 true 1 > "$_OTEL_CACHE/otel/events/llm-$_OLDDAY.ndjson"
{
  _errl otelsess-a "$_NANO" 429
  _errl otelsess-b "$_NANO" 529
  # an api_request record must NOT be read as an error, wherever it sits
  printf '{"_sig":"log","_name":"claude_code.api_request","_t":"%s","session.id":"otelsess-a","status_code":0}\n' "$_NANO"
} > "$_OTEL_CACHE/otel/events/err-$_TODAY.ndjson"

_build() { CLAUDII_CACHE_DIR="$_OTEL_CACHE" bash "$CLAUDII_HOME/bin/claudii-otel" "$@"; }

# ── build: shape + windowing ──
_OB=$(_build build --days 7 2>&1)
assert_eq "otel build: well-formed JSON" "0" \
  "$(printf '%s' "$_OB" | jq empty >/dev/null 2>&1; echo $?)"
assert_eq "otel build: source otel" "otel" "$(printf '%s' "$_OB" | jq -r '.source')"
assert_eq "otel build: 5 latency samples (old one filtered)" "5" \
  "$(printf '%s' "$_OB" | jq -r '.latency | length')"
assert_eq "otel build: 2 error samples" "2" \
  "$(printf '%s' "$_OB" | jq -r '.errors | length')"

# ── repo resolution via session.id ──
assert_eq "otel build: otelsess-a → alpha" "alpha" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-a")][0].repo')"
assert_eq "otel build: otelsess-b → beta" "beta" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].repo')"
assert_eq "otel build: unknown session → ?" "?" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="ghostsess")][0].repo')"

# ── exact-field extraction (ttft / success / attempt / status_code) ──
assert_eq "otel build: ttft_ms extracted" "4000" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].ttft_ms')"
assert_eq "otel build: success=false preserved (not dropped by //)" "false" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].success')"
assert_eq "otel build: retry attempt=2" "2" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.sessionId=="otelsess-b")][0].attempt')"
assert_eq "otel build: 4 successes among the in-window samples" "4" \
  "$(printf '%s' "$_OB" | jq -r '[.latency[]|select(.success==true)] | length')"
assert_eq "otel build: error 429 present" "429" \
  "$(printf '%s' "$_OB" | jq -r '[.errors[]|select(.status_code==429)][0].status_code')"
assert_eq "otel build: api_request not counted as error" "0" \
  "$(printf '%s' "$_OB" | jq -r '[.errors[]|select(.status_code==0)] | length')"

# ── the closed day was compacted by that build: gz + rows, today stays plain ──
_has() { compgen -G "$1" >/dev/null; }   # any file matches the glob
assert_eq "otel compact: closed day's event file gzipped, not deleted" "0" \
  "$([ -s "$_OTEL_CACHE/otel/events/llm-$_OLDDAY.ndjson.gz" ] && [ ! -e "$_OTEL_CACHE/otel/events/llm-$_OLDDAY.ndjson" ] && echo 0 || echo 1)"
assert_eq "otel compact: closed day's rows built from the gz" "0" \
  "$([ -s "$_OTEL_CACHE/otel/rows/$_OLDDAY.v1.ndjson" ] && echo 0 || echo 1)"
assert_eq "otel compact: today's files stay plain" "0" \
  "$([ -s "$_OTEL_CACHE/otel/events/llm-$_TODAY.ndjson" ] && [ -s "$_OTEL_CACHE/otel/events/err-$_TODAY.ndjson" ] && echo 0 || echo 1)"
assert_eq "otel build: a wide window reaches the compacted day" "6" \
  "$(_build build --days 200 2>/dev/null | jq '.latency | length')"

# ── empty / missing data → empty shape ──
_EMPTY="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_EMPTY")
_OE=$(CLAUDII_CACHE_DIR="$_EMPTY" bash "$CLAUDII_HOME/bin/claudii-otel" build 2>&1)
assert_eq "otel build (no data): empty latency" "0" "$(printf '%s' "$_OE" | jq -r '.latency | length')"
assert_eq "otel build (no data): empty errors"  "0" "$(printf '%s' "$_OE" | jq -r '.errors | length')"

# ── bad --days ──
_OBAD=$(_build build --days nope 2>&1; echo "rc=$?")
assert_contains "otel build: rejects non-numeric --days" "positive integer" "$_OBAD"
assert_contains "otel build: exit 1" "rc=1" "$_OBAD"

# ── doctor runs ──
_ODOC=$(_build doctor 2>&1)
assert_contains "otel doctor: reports otel dir" "otel dir" "$_ODOC"
assert_contains "otel doctor: counts samples"  "response" "$_ODOC"
assert_contains "otel doctor: counts today's events per kind" "llm 6" "$_ODOC"
assert_contains "otel doctor: says when no receiver.status exists" "no receiver.status" "$_ODOC"
assert_not_contains "otel doctor: no legacy hint without legacy data" "legacy" "$_ODOC"
# a pre-events capture is not read; doctor prints the exact conversion pipeline
mkdir -p "$_OTEL_CACHE/otel/raw"; printf '{}\n' > "$_OTEL_CACHE/otel/traces.jsonl"
_ODOC=$(_build doctor 2>&1)
assert_contains "otel doctor: flags a legacy single-file capture" "traces.jsonl/logs.jsonl" "$_ODOC"
assert_contains "otel doctor: flags a raw/ day-file capture" "raw/ (day-file layout" "$_ODOC"
assert_contains "otel doctor: prints the conversion command" \
  "claudii-otel-receiver --flatten $_OTEL_CACHE/otel/events --tag conv" "$_ODOC"
assert_contains "otel doctor: the conversion hint starts with the receiver restart" \
  "1. restart the receiver:  launchctl kickstart" "$_ODOC"
rm -rf "$_OTEL_CACHE/otel/raw" "$_OTEL_CACHE/otel/traces.jsonl"

# ── perf renders from the OTEL source when enabled ──
_OTEL_CFG="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_CFG")
_OTEL_EPROJ="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_EPROJ")
mkdir -p "$_OTEL_CFG/claudii"
jq '.perf.otel.enabled = true' "$CLAUDII_HOME/config/defaults.json" > "$_OTEL_CFG/claudii/config.json"
_PO=$(CLAUDII_CACHE_DIR="$_OTEL_CACHE" XDG_CONFIG_HOME="$_OTEL_CFG" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  bash "$CLAUDII_HOME/bin/claudii" perf 7d 2>&1)
assert_contains "perf (otel): source otel"        "source: otel" "$_PO"
assert_contains "perf (otel): TTFT section"        "TTFT"         "$_PO"
assert_contains "perf (otel): reliability line"    "success"      "$_PO"
assert_contains "perf (otel): API errors section"  "API errors"   "$_PO"
assert_contains "perf (otel): http error code"     "529"          "$_PO"
assert_contains "perf (otel): By repo without --repo" "By repo"   "$_PO"
assert_no_literal_ansi "perf (otel): no literal \\033" "$_PO"
_POR=$(CLAUDII_CACHE_DIR="$_OTEL_CACHE" XDG_CONFIG_HOME="$_OTEL_CFG" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  bash "$CLAUDII_HOME/bin/claudii" perf 7d --repo alpha 2>&1)
assert_contains "perf (otel) --repo: By session" "By session" "$_POR"
assert_contains "perf (otel) --repo: session listed" "otelsess" "$_POR"

# ── perf --json carries the OTEL-only blocks ──
_POJ=$(CLAUDII_CACHE_DIR="$_OTEL_CACHE" XDG_CONFIG_HOME="$_OTEL_CFG" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  bash "$CLAUDII_HOME/bin/claudii" perf 7d --json 2>&1)
assert_eq "perf --json (otel): source otel" "otel" "$(printf '%s' "$_POJ" | jq -r '.source')"
assert_eq "perf --json (otel): ttft p50 present" "false" \
  "$(printf '%s' "$_POJ" | jq -r '.ttft == null')"
assert_eq "perf --json (otel): reliability total=5" "5" \
  "$(printf '%s' "$_POJ" | jq -r '.reliability.total')"
assert_eq "perf --json (otel): 2 error buckets" "2" \
  "$(printf '%s' "$_POJ" | jq -r '.errors | length')"
assert_eq "perf --json (otel): by_repo present without --repo" "3" \
  "$(printf '%s' "$_POJ" | jq -r '.by_repo | length')"

# ── setup / off toggle (config flag + fork-free env file + launchd plist) ──
_OTEL_SCFG="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_SCFG")
_OTEL_SCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_SCACHE")
_otel() { CLAUDII_CACHE_DIR="$_OTEL_SCACHE" XDG_CONFIG_HOME="$_OTEL_SCFG" bash "$CLAUDII_HOME/bin/claudii-otel" "$@"; }
_ocli() { XDG_CONFIG_HOME="$_OTEL_SCFG" bash "$CLAUDII_HOME/bin/claudii" "$@"; }

_otel setup >/dev/null 2>&1
assert_eq "otel setup: config flag enabled" "true" "$(_ocli config get perf.otel.enabled 2>/dev/null)"
assert_eq "otel setup: env file written" "0" "$([ -r "$_OTEL_SCACHE/otel.env" ] && echo 0 || echo 1)"
assert_contains "otel setup: env enables telemetry" "CLAUDE_CODE_ENABLE_TELEMETRY=1" "$(<"$_OTEL_SCACHE/otel.env")"
assert_contains "otel setup: env sets http/json" "OTEL_EXPORTER_OTLP_PROTOCOL=http/json" "$(<"$_OTEL_SCACHE/otel.env")"
assert_contains "otel setup: env points at endpoint" "OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318" "$(<"$_OTEL_SCACHE/otel.env")"
assert_eq "otel setup: launchd plist generated" "0" "$([ -s "$_OTEL_SCACHE/otel/com.claudii.otel-receiver.plist" ] && echo 0 || echo 1)"
# default config carries no forward → env/plist/doctor stay local-only
assert_not_contains "otel setup (default): env omits CLAUDII_OTEL_FORWARD" \
  "CLAUDII_OTEL_FORWARD" "$(<"$_OTEL_SCACHE/otel.env")"
assert_not_contains "otel setup (default): plist omits CLAUDII_OTEL_FORWARD" \
  "CLAUDII_OTEL_FORWARD" "$(<"$_OTEL_SCACHE/otel/com.claudii.otel-receiver.plist")"
assert_contains "otel doctor (default): reports local-only" \
  "local-only" "$(_otel doctor 2>&1)"

_otel off >/dev/null 2>&1
assert_eq "otel off: config flag disabled" "false" "$(_ocli config get perf.otel.enabled 2>/dev/null)"
assert_eq "otel off: env file removed" "1" "$([ -e "$_OTEL_SCACHE/otel.env" ] && echo 0 || echo 1)"

# ── forward / gateway fan-out (perf.otel.forward → receiver tee) ──
# Placeholder host only — never a real internal name in tracked source. The
# socket tee itself isn't testable here (sandbox blocks bind); this pins the
# wiring (env + plist + doctor), the operator smoke-tests the actual forward.
_ocli config set perf.otel.forward "http://nutc.example:4318" >/dev/null 2>&1
_otel setup >/dev/null 2>&1
assert_contains "otel setup (forward): env exports CLAUDII_OTEL_FORWARD" \
  "export CLAUDII_OTEL_FORWARD=http://nutc.example:4318" "$(<"$_OTEL_SCACHE/otel.env")"
assert_contains "otel setup (forward): plist bakes forward into receiver env" \
  "<key>CLAUDII_OTEL_FORWARD</key><string>http://nutc.example:4318</string>" \
  "$(<"$_OTEL_SCACHE/otel/com.claudii.otel-receiver.plist")"
assert_contains "otel doctor (forward): reports the gateway" \
  "http://nutc.example:4318" "$(_otel doctor 2>&1)"

# ── event-file layout: compact / rows / window ──
_OTEL_MCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_MCACHE")
cp -R "$_OTEL_CACHE/otel" "$_OTEL_CACHE/insights" "$_OTEL_MCACHE/"
_mbuild() { CLAUDII_CACHE_DIR="$_OTEL_MCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" "$@"; }
# Row order follows the files; every consumer sorts or buckets, so compare
# order-insensitively.
_onorm() { jq -S -c '.latency |= sort | .errors |= sort'; }
_OM_PRE200=$(_mbuild build --days 200 2>/dev/null | _onorm)
_OM_PRE7=$(_mbuild build --days 7 2>/dev/null | _onorm)

# rows are derived: lost (or of an old OTEL_ROWS_VERSION) → rebuilt from the gz.
rm -f "$_OTEL_MCACHE/otel/rows/$_OLDDAY.v1.ndjson"
printf 'stale\n' > "$_OTEL_MCACHE/otel/rows/$_OLDDAY.v0.ndjson"
assert_eq "otel compact: rows rebuilt from the gzipped day" "$_OM_PRE200" \
  "$(_mbuild build --days 200 2>/dev/null | _onorm)"
assert_eq "otel compact: rows of another version removed" "0" \
  "$([ ! -e "$_OTEL_MCACHE/otel/rows/$_OLDDAY.v0.ndjson" ] && echo 0 || echo 1)"

# A closed day's file of another kind (tool, hook, …) is gzipped WITHOUT
# invalidating that day's rows — only llm/err files feed them.
printf 'sentinel\n' > "$_OTEL_MCACHE/otel/rows/$_OLDDAY.v1.ndjson"
printf '{"_sig":"span","_name":"claude_code.tool","_t":"%s"}\n' "$_OLDNANO" > "$_OTEL_MCACHE/otel/events/tool-$_OLDDAY.ndjson"
_mbuild compact >/dev/null 2>&1
assert_eq "otel compact: a tool-kind file is gzipped" "0" \
  "$([ -s "$_OTEL_MCACHE/otel/events/tool-$_OLDDAY.ndjson.gz" ] && [ ! -e "$_OTEL_MCACHE/otel/events/tool-$_OLDDAY.ndjson" ] && echo 0 || echo 1)"
assert_eq "otel compact: …without rebuilding the day's rows" "sentinel" \
  "$(cat "$_OTEL_MCACHE/otel/rows/$_OLDDAY.v1.ndjson")"
# A new llm/err part for a day that already has rows must reach those rows —
# the stale rows file is replaced.
_errl otelsess-a "$_OLDNANO" 503 > "$_OTEL_MCACHE/otel/events/err-$_OLDDAY.extra.ndjson"
assert_eq "otel compact: a new err part of a compacted day reaches its rows" "1" \
  "$(_mbuild build --days 200 2>/dev/null | jq '[.errors[] | select(.status_code == 503)] | length')"
assert_eq "otel compact: …and the sentinel rows file is gone" "0" \
  "$(grep -c sentinel "$_OTEL_MCACHE/otel/rows/$_OLDDAY.v1.ndjson")"

# The window picks files by name: a rows file far before the floor is never
# opened (it is not even JSON), so build cost follows the window.
_FARDAY=$(_utc_day $(( _NOW - 300 * 86400 )))
printf 'not json\n' > "$_OTEL_MCACHE/otel/rows/$_FARDAY.v1.ndjson"
assert_eq "otel build: rows outside the window are not read" "$_OM_PRE7" \
  "$(_mbuild build --days 7 2>/dev/null | _onorm)"
rm -f "$_OTEL_MCACHE/otel/rows/$_FARDAY.v1.ndjson"

# Yesterday's live file may still take a write that straddled midnight: left
# alone while fresh, compacted once quiet.
_YDAY=$(_utc_day $(( _NOW - 86400 )))
_llm otelsess-a "$(( _NOW - 86400 ))000000000" 1000 500 100 true 1 \
  > "$_OTEL_MCACHE/otel/events/llm-$_YDAY.ndjson"
_mbuild compact >/dev/null 2>&1
assert_eq "otel compact: a fresh file of yesterday is left alone" "0" \
  "$([ -s "$_OTEL_MCACHE/otel/events/llm-$_YDAY.ndjson" ] && echo 0 || echo 1)"
touch -t 200001010000 "$_OTEL_MCACHE/otel/events/llm-$_YDAY.ndjson"
_mbuild compact >/dev/null 2>&1
assert_eq "otel compact: a quiet file of yesterday is compacted" "0" \
  "$([ -s "$_OTEL_MCACHE/otel/events/llm-$_YDAY.ndjson.gz" ] && [ -s "$_OTEL_MCACHE/otel/rows/$_YDAY.v1.ndjson" ] && echo 0 || echo 1)"

# Interrupted compaction: the .gz landed, the plain file was not removed yet.
# The day must count once, not twice (rows come from the .gz files only).
_OTEL_ICACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_ICACHE"); mkdir -p "$_OTEL_ICACHE/otel/events"
_IDAY=$(_utc_day $(( _NOW - 3 * 86400 )))
_llm otelsess-a "$(( _NOW - 3 * 86400 ))000000000" 1000 500 100 true 1 > "$_OTEL_ICACHE/otel/events/llm-$_IDAY.ndjson"
gzip -c "$_OTEL_ICACHE/otel/events/llm-$_IDAY.ndjson" > "$_OTEL_ICACHE/otel/events/llm-$_IDAY.ndjson.gz"
assert_eq "otel compact: an interrupted gzip is not counted twice" "1" \
  "$(CLAUDII_CACHE_DIR="$_OTEL_ICACHE" bash "$CLAUDII_HOME/bin/claudii-otel" build --days 7 2>/dev/null | jq '.latency | length')"
assert_eq "otel compact: …and the leftover plain file is removed" "0" \
  "$([ ! -e "$_OTEL_ICACHE/otel/events/llm-$_IDAY.ndjson" ] && echo 0 || echo 1)"

# A .gz that does not decode yields no rows from its readable prefix, and stays.
printf 'garbage' > "$_OTEL_ICACHE/otel/events/err-$_IDAY.ndjson.gz"
rm -f "$_OTEL_ICACHE/otel/rows/$_IDAY.v1.ndjson"   # rows are rebuilt when missing
_OC_RC=$(CLAUDII_CACHE_DIR="$_OTEL_ICACHE" bash "$CLAUDII_HOME/bin/claudii-otel" compact >/dev/null 2>&1; echo $?)
assert_eq "otel compact: a corrupt .gz fails the day (rc 1)" "1" "$_OC_RC"
assert_eq "otel compact: …writes no rows from a prefix and keeps the .gz" "0" \
  "$([ ! -e "$_OTEL_ICACHE/otel/rows/$_IDAY.v1.ndjson" ] && [ -s "$_OTEL_ICACHE/otel/events/err-$_IDAY.ndjson.gz" ] && echo 0 || echo 1)"
rm -f "$_OTEL_ICACHE/otel/events/err-$_IDAY.ndjson.gz"

# A plain file under an already-gzipped name is renamed, never onto an existing
# file: pre-fill every name the rename could pick this minute with data.
_OTEL_KCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_KCACHE"); mkdir -p "$_OTEL_KCACHE/otel/events"
_KR="$_OTEL_KCACHE/otel/events"
printf '{"_sig":"span"}\n' | gzip -c > "$_KR/other-$_IDAY.ndjson.gz"
_kt=$(date +%s)
for (( _k = _kt; _k < _kt + 60; _k++ )); do
  printf '{"_sig":"span"}\n' | gzip -c > "$_KR/other-$_IDAY.$_k.ndjson.gz"
done
printf '{"_sig":"span","x":2}\n' > "$_KR/other-$_IDAY.ndjson"   # differs from the .gz
CLAUDII_CACHE_DIR="$_OTEL_KCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" compact >/dev/null 2>&1
assert_eq "otel compact: a renamed part never overwrites event data" "62" \
  "$(cat "$_KR"/*.gz | gzip -dc | wc -l | tr -d ' ')"

# Two compacts exclude each other; build still answers, uncompacted.
_OTEL_LCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_LCACHE"); mkdir -p "$_OTEL_LCACHE/otel/events" "$_OTEL_LCACHE/otel/.lock"
# A live holder that looks like claudii-otel to ps (its command line names it).
# `; :` keeps bash itself running — a lone `sleep` would be exec'd in its place
# and ps would show plain "sleep 120".
bash -c 'sleep 120; :' claudii-otel-test-holder &
_OL_HOLDER=$!
printf '%s\n' "$_OL_HOLDER" > "$_OTEL_LCACHE/otel/.lock/pid"
cp "$_OTEL_ICACHE/otel/events/llm-$_IDAY.ndjson.gz" "$_OTEL_LCACHE/otel/events/"
gzip -dc "$_OTEL_LCACHE/otel/events/llm-$_IDAY.ndjson.gz" > "$_OTEL_LCACHE/otel/events/err-$_IDAY.ndjson"
_olb() { CLAUDII_CACHE_DIR="$_OTEL_LCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" "$@"; }
assert_eq "otel lock: compact refuses while another run holds the lock" "1" \
  "$(_olb compact >/dev/null 2>&1; echo $?)"
assert_eq "otel lock: build skips compaction but still answers" "1|0" \
  "$(_olb build --days 7 2>/dev/null | jq '.latency | length')|$([ -e "$_OTEL_LCACHE/otel/events/err-$_IDAY.ndjson" ] && echo 0 || echo 1)"
kill "$_OL_HOLDER" 2>/dev/null; wait "$_OL_HOLDER" 2>/dev/null
sleep 0 & _OL_DEAD=$!; wait "$_OL_DEAD"
printf '%s\n' "$_OL_DEAD" > "$_OTEL_LCACHE/otel/.lock/pid"
assert_eq "otel lock: a dead holder's lock is taken over" "0" \
  "$(_olb compact >/dev/null 2>&1; echo $?)"
# A live pid that belongs to another program is a recycled pid, not a running
# compact. Needs ps (CI has it; some sandboxes deny it — then the lock counts
# as held, which is the conservative side).
if ps -p "$$" -o command= >/dev/null 2>&1; then
  mkdir -p "$_OTEL_LCACHE/otel/.lock"; printf '%s\n' "$$" > "$_OTEL_LCACHE/otel/.lock/pid"
  assert_eq "otel lock: a recycled pid (another program) is taken over" "0" \
    "$(_olb compact >/dev/null 2>&1; echo $?)"
fi

# A failing OTEL build (here a rows file lib/otel_doc.jq cannot process) falls
# back to the transcript estimate instead of aborting perf with no output.
_OTEL_PCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_PCACHE"); mkdir -p "$_OTEL_PCACHE/otel/rows"
printf '{"kind":"lat","day":"%s","model":5,"dt_ms":1,"out":1,"ctx":1,"sessionId":"x","success":true,"attempt":1}\n' \
  "$(_utc_day $(( _NOW - 2 * 86400 )))" > "$_OTEL_PCACHE/otel/rows/$(_utc_day $(( _NOW - 2 * 86400 ))).v1.ndjson"
_PF_OUT=$(CLAUDII_CACHE_DIR="$_OTEL_PCACHE" XDG_CONFIG_HOME="$_OTEL_CFG" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  bash "$CLAUDII_HOME/bin/claudii" perf 7d 2>&1; echo "rc=$?")
assert_contains "perf: a failing OTEL build falls back (transcript, rc 0)" "No insight data yet" "$_PF_OUT"
assert_contains "perf: …and exits 0" "rc=0" "$_PF_OUT"

# The fused render (build --render) equals the two-step pipeline it replaces:
# the full document, then lib/perf_rows.jq / lib/perf_json.jq over it.
_FFLOOR=$(_utc_day $(( _NOW - 6 * 86400 )))
_ofused() { CLAUDII_CACHE_DIR="$_OTEL_CACHE" bash "$CLAUDII_HOME/bin/claudii-otel" build --days 7 "$@" 2>/dev/null; }
assert_eq "otel build --render rows: equals document + perf_rows" \
  "$(_ofused | jq -r -L "$CLAUDII_HOME/lib" --arg f "$_FFLOOR" 'include "perf_rows"; perf_rows($f; "alpha")')" \
  "$(_ofused --render rows --render-floor "$_FFLOOR" --repo alpha)"
assert_eq "otel build --render json: equals document + perf_json" \
  "$(_ofused | jq -L "$CLAUDII_HOME/lib" --arg f "$_FFLOOR" 'include "perf_json"; perf_json(7; $f; ""; "otel")')" \
  "$(_ofused --render json --render-floor "$_FFLOOR")"
assert_eq "otel build --render: rejects an unknown mode" "1" \
  "$(_ofused --render tsv --render-floor "$_FFLOOR" >/dev/null 2>&1; echo $?)"
# perf renders R (by repo) only without --repo and G (by session) only with
# it, so the rows carry exactly the group the caller shows.
_RROWS=$(_ofused --render rows --render-floor "$_FFLOOR")
assert_eq "perf_rows: R rows without --repo, no G rows" "3|0" \
  "$(printf '%s\n' "$_RROWS" | grep -c $'^R\t')|$(printf '%s\n' "$_RROWS" | grep -c $'^G\t')"
_GROWS=$(_ofused --render rows --render-floor "$_FFLOOR" --repo alpha)
assert_eq "perf_rows: G rows with --repo, no R rows" "0|1" \
  "$(printf '%s\n' "$_GROWS" | grep -c $'^R\t')|$(printf '%s\n' "$_GROWS" | grep -c $'^G\t')"

# Errors but no latency in the window: a render prints nothing, so perf falls
# back to the transcript estimate (as the old full-document check did).
_OTEL_ECACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_ECACHE"); mkdir -p "$_OTEL_ECACHE/otel/events"
_errl otelsess-a "$_NANO" 429 > "$_OTEL_ECACHE/otel/events/err-$_TODAY.ndjson"
assert_eq "otel build --render: no latency in the window → no output" "" \
  "$(CLAUDII_CACHE_DIR="$_OTEL_ECACHE" bash "$CLAUDII_HOME/bin/claudii-otel" build --days 7 --render rows --render-floor "$_FFLOOR" 2>/dev/null)"

# The session→repo log claudii-insights aggregate maintains is what build
# reads when it exists (here it disagrees with the caches on purpose) …
_OTEL_RCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_RCACHE")
cp -R "$_OTEL_CACHE/otel" "$_OTEL_CACHE/insights" "$_OTEL_RCACHE/"
printf 'otelsess-a\tfromlog\n' > "$_OTEL_RCACHE/insights-repomap.tsv"
assert_contains "otel build: reads the session→repo log when present" '"repo":"fromlog"' \
  "$(CLAUDII_CACHE_DIR="$_OTEL_RCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" build --days 7 2>/dev/null)"
# … a full aggregate run rebuilds it from every cache (orphans included) …
rm -f "$_OTEL_RCACHE/insights-repomap.tsv"
CLAUDII_CACHE_DIR="$_OTEL_RCACHE" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
assert_eq "insights aggregate: rebuilds a missing session→repo log" \
  "$(printf 'otelsess-a\talpha\notelsess-b\tbeta')" "$(sort "$_OTEL_RCACHE/insights-repomap.tsv" 2>/dev/null)"
# … and extends it with every session it aggregates afterwards.
_OTEL_RPROJ="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_RPROJ"); mkdir -p "$_OTEL_RPROJ/-x-gamma"
printf '{"type":"user","timestamp":"%s","sessionId":"otelsess-c","cwd":"/x/gamma","message":{"role":"user","content":"hi"}}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_OTEL_RPROJ/-x-gamma/otelsess-c.jsonl"
CLAUDII_CACHE_DIR="$_OTEL_RCACHE" CLAUDE_PROJECTS_DIR="$_OTEL_RPROJ" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
assert_contains "insights aggregate: appends newly aggregated sessions to the log" \
  "$(printf 'otelsess-c\tgamma')" "$(cat "$_OTEL_RCACHE/insights-repomap.tsv" 2>/dev/null)"
# Re-aggregating active sessions appends each time; once duplicates pass
# twice the cache count (+100) the next run rewrites the log to one line each.
for (( _i = 0; _i < 200; _i++ )); do printf 'otelsess-a\talpha\n'; done >> "$_OTEL_RCACHE/insights-repomap.tsv"
CLAUDII_CACHE_DIR="$_OTEL_RCACHE" CLAUDE_PROJECTS_DIR="$_OTEL_EPROJ" \
  bash "$CLAUDII_HOME/bin/claudii-insights" aggregate >/dev/null 2>&1
assert_eq "insights aggregate: compacts a log bloated by duplicates" "3" \
  "$(wc -l < "$_OTEL_RCACHE/insights-repomap.tsv" | tr -d ' ')"

# ── the receiver: OTLP batch → flat records ──
# One realistic /v1/traces + /v1/logs batch pair in Claude Code's wire format:
# identity constants on every record, a span with events, a link, an
# arrayValue and status code 2, a log record whose duration_ms arrives as a
# STRING (tool_result does), and one whose observedTimeUnixNano differs.
_RCV="$CLAUDII_HOME/bin/claudii-otel-receiver"
_OTEL_FDIR="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_FDIR")
_IDATTRS='{"key":"user.email","value":{"stringValue":"someone@example.invalid"}},{"key":"user.id","value":{"stringValue":"uid-1"}},{"key":"user.account_uuid","value":{"stringValue":"acct-uuid"}},{"key":"user.account_id","value":{"stringValue":"acct-1"}},{"key":"organization.id","value":{"stringValue":"org-1"}}'
_RES='{"attributes":[{"key":"host.arch","value":{"stringValue":"arm64"}},{"key":"service.name","value":{"stringValue":"claude-code"}},{"key":"service.version","value":{"stringValue":"2.1.283"}}]}'
printf '%s\n' '{"resourceSpans":[{"resource":'"$_RES"',"scopeSpans":[{"scope":{"name":"com.anthropic.claude_code.tracing","version":"1.0.0"},"spans":[
 {"traceId":"aa","spanId":"s1","parentSpanId":"p1","name":"claude_code.llm_request","kind":1,"flags":257,"startTimeUnixNano":"1790000000000000000","endTimeUnixNano":"1790000001000000000","attributes":['"$_IDATTRS"',{"key":"session.id","value":{"stringValue":"sess-x"}},{"key":"model","value":{"stringValue":"claude-opus-5-5"}},{"key":"duration_ms","value":{"intValue":1000}},{"key":"success","value":{"boolValue":false}},{"key":"gen_ai.response.finish_reasons","value":{"arrayValue":{"values":[{"stringValue":"tool_use"}]}}},{"key":"_odd","value":{"stringValue":"reserved-prefix"}}],"events":[{"name":"gen_ai.request.attempt","timeUnixNano":"1790000000000000001","attributes":[{"key":"attempt","value":{"intValue":1}}],"droppedAttributesCount":0}],"links":[{"traceId":"bb","spanId":"s0","flags":769,"attributes":[{"key":"link.type","value":{"stringValue":"parent_of"}}]}],"status":{"code":0},"droppedAttributesCount":0},
 {"traceId":"aa","spanId":"s2","name":"claude_code.tool.execution","kind":1,"flags":257,"startTimeUnixNano":"1790000002000000000","endTimeUnixNano":"1790000002500000000","attributes":['"$_IDATTRS"',{"key":"duration_ms","value":{"intValue":500}}],"events":[],"links":[],"status":{"code":2,"message":"ShellError"}},
 {"traceId":"aa","spanId":"s3","name":"claude_code.interaction","kind":1,"flags":769,"startTimeUnixNano":"1790000003000000000","endTimeUnixNano":"1790000003000000000","attributes":[],"status":{"code":0}}
]}]}]}' | tr -d '\n' > "$_OTEL_FDIR/traces.jsonl"; printf '\n' >> "$_OTEL_FDIR/traces.jsonl"
printf '%s\n' '{"resourceLogs":[{"resource":'"$_RES"',"scopeLogs":[{"scope":{"name":"com.anthropic.claude_code.events","version":"2.1.283"},"logRecords":[
 {"timeUnixNano":"1790000004000000000","observedTimeUnixNano":"1790000004000000000","body":{"stringValue":"claude_code.tool_result"},"attributes":['"$_IDATTRS"',{"key":"duration_ms","value":{"stringValue":"42"}},{"key":"success","value":{"stringValue":"true"}}],"flags":1,"traceId":"aa","spanId":"s2","droppedAttributesCount":0},
 {"timeUnixNano":"1790000005000000000","observedTimeUnixNano":"1790000005000000007","body":{"stringValue":"claude_code.hook_execution_start"},"attributes":['"$_IDATTRS"',{"key":"hook_event","value":{"stringValue":"Stop"}}]},
 {"timeUnixNano":"1790000006000000000","observedTimeUnixNano":"1790000006000000000","body":{"stringValue":"claude_code.api_error"},"attributes":['"$_IDATTRS"',{"key":"status_code","value":{"intValue":529}},{"key":"model","value":{"stringValue":"claude-opus-5-5"}},{"key":"session.id","value":{"stringValue":"sess-x"}}]},
 {"timeUnixNano":"1790000007000000000","observedTimeUnixNano":"1790000007000000000","body":{"stringValue":"claude_code.api_request"},"attributes":['"$_IDATTRS"',{"key":"duration_ms","value":{"intValue":7}}]}
]}]}]}' | tr -d '\n' > "$_OTEL_FDIR/logs.jsonl"; printf '\n' >> "$_OTEL_FDIR/logs.jsonl"
# flatten(): the module function every ingest path uses
_FLAT=$(python3 -c '
import importlib.util, json, sys
import importlib.machinery
spec = importlib.util.spec_from_file_location("recv", sys.argv[1], loader=importlib.machinery.SourceFileLoader("recv", sys.argv[1])); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for f in sys.argv[2:]:
    for line in open(f):
        for kind, t, rec in m.flatten(json.loads(line)):
            print(kind + "\t" + rec)
' "$_RCV" "$_OTEL_FDIR/traces.jsonl" "$_OTEL_FDIR/logs.jsonl" 2>/dev/null)
_frec() { printf '%s\n' "$_FLAT" | awk -F'\t' -v k="$1" '$1 == k {print $2}' | jq -c "select(._name == \"$2\")" | head -1; }
assert_eq "flatten: 7 records, kinds llm/tool/other/err/api/hook" "api err hook llm other tool tool" \
  "$(printf '%s\n' "$_FLAT" | cut -f1 | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "flatten: identity constants dropped from every record" "0" \
  "$(printf '%s\n' "$_FLAT" | grep -c 'user\.email\|user\.id\|user\.account_uuid\|user\.account_id\|organization\.id\|someone@example')"
_LLMREC=$(_frec llm claude_code.llm_request)
assert_eq "flatten: span reserved keys (_t/_end/_trace/_span/_parent)" '["1790000000000000000","1790000001000000000","aa","s1","p1"]' \
  "$(printf '%s' "$_LLMREC" | jq -c '[._t, ._end, ._trace, ._span, ._parent]')"
assert_eq "flatten: resource attributes carried on the record" "claude-code|2.1.283|arm64" \
  "$(printf '%s' "$_LLMREC" | jq -r '[."service.name", ."service.version", ."host.arch"] | join("|")')"
assert_eq "flatten: attribute types as received (int, bool false, array)" '[1000,false,["tool_use"]]' \
  "$(printf '%s' "$_LLMREC" | jq -c '[.duration_ms, .success, ."gen_ai.response.finish_reasons"]')"
assert_eq "flatten: events and links flattened, kept only when present" '[[{"_name":"gen_ai.request.attempt","_t":"1790000000000000001","attempt":1}],[{"_trace":"bb","_span":"s0","_flags":769,"link.type":"parent_of"}]]' \
  "$(printf '%s' "$_LLMREC" | jq -c '[._events, ._links]')"
assert_eq "flatten: default kind 1 / flags 257 / status 0 not stored" "0" \
  "$(printf '%s' "$_LLMREC" | jq '[has("_kind"), has("_flags"), has("_status")] | map(select(.)) | length')"
assert_eq "flatten: an attribute key starting with _ is namespaced" "reserved-prefix" \
  "$(printf '%s' "$_LLMREC" | jq -r '.attr_odd')"
assert_eq "flatten: status kept when code != 0" '{"code":2,"message":"ShellError"}' \
  "$(_frec tool claude_code.tool.execution | jq -c '._status')"
assert_eq "flatten: non-default span flags kept" "769" \
  "$(_frec other claude_code.interaction | jq -r '._flags')"
_TRREC=$(_frec tool claude_code.tool_result)
assert_eq "flatten: log reserved keys, string-typed attributes stay strings" '["log","1790000004000000000","aa","s2","42","true"]' \
  "$(printf '%s' "$_TRREC" | jq -c '[._sig, ._t, ._trace, ._span, .duration_ms, .success]')"
assert_eq "flatten: observedTimeUnixNano dropped when equal, kept when it differs" 'null|"1790000005000000007"' \
  "$(printf '%s' "$_TRREC" | jq -c '._observed')|$(_frec hook claude_code.hook_execution_start | jq -c '._observed')"
assert_eq "flatten: default log flags not stored" "false" "$(printf '%s' "$_TRREC" | jq 'has("_flags")')"
# a metrics batch becomes one 'other' record with the identity scrubbed
assert_eq "flatten: a metrics batch → one other record, identity scrubbed" "other|metrics|0|1" \
  "$(python3 -c '
import importlib.util, json, sys
import importlib.machinery
spec = importlib.util.spec_from_file_location("recv", sys.argv[1], loader=importlib.machinery.SourceFileLoader("recv", sys.argv[1])); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
b = {"resourceMetrics":[{"resource":{"attributes":[{"key":"user.email","value":{"stringValue":"x@y"}},{"key":"service.name","value":{"stringValue":"claude-code"}}]},"scopeMetrics":[]}]}
out = m.flatten(b)
rec = json.loads(out[0][2])
s = json.dumps(rec)
print("%s|%s|%d|%d" % (out[0][0], rec["_sig"], s.count("user.email"), s.count("service.name")))
' "$_RCV" 2>/dev/null)"

# --flatten <dir> [--tag TAG]: OTLP batch lines on stdin → event files dated by
# each record's own timestamp, never the live file name. The old receiver's
# empty `_unparsed` markers are skipped; a line that is not JSON is kept in
# unparsed-<day>.<tag>.ndjson.
_OTEL_CDIR="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_CDIR")
_CSTATS=$({ cat "$_OTEL_FDIR/traces.jsonl" "$_OTEL_FDIR/logs.jsonl"
            printf '%s\n' '{"_unparsed":true,"content_type":"application/json","encoding":"","bytes":0}'
            printf '%s\n' 'garbage line'
          } | python3 "$_RCV" --flatten "$_OTEL_CDIR/ev" --tag t 2>/dev/null)
assert_eq "flatten CLI: summary counts" '[4,2,7,1,1]' \
  "$(printf '%s' "$_CSTATS" | jq -c '[.lines, .batches, .records, .skipped_empty, .unparsed]')"
assert_eq "flatten CLI: files dated by record timestamp (2026-09-21), tagged" \
  "api-2026-09-21.t.ndjson err-2026-09-21.t.ndjson hook-2026-09-21.t.ndjson llm-2026-09-21.t.ndjson other-2026-09-21.t.ndjson tool-2026-09-21.t.ndjson unparsed-$_TODAY.t.ndjson" \
  "$(ls "$_OTEL_CDIR/ev" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "flatten CLI: the unparsed line is kept verbatim" "garbage line" \
  "$(jq -r '.body' "$_OTEL_CDIR/ev/unparsed-$_TODAY.t.ndjson")"
assert_eq "flatten CLI: closed stderr does not fail the conversion" "0" \
  "$(cat "$_OTEL_FDIR/logs.jsonl" | python3 "$_RCV" --flatten "$_OTEL_CDIR/ev2" --tag t >/dev/null 2>&-; echo $?)"
assert_eq "flatten CLI: --flatten without a directory is usage error 2" "2" \
  "$(python3 "$_RCV" --flatten </dev/null >/dev/null 2>&1; echo $?)"
# Files are written as .part and renamed at the end (a concurrent compact never
# sees a half-written file); a second run for the same tag is refused (exit 3)
# — appending again would count every record twice.
assert_eq "flatten CLI: no .part file left behind, finals present" "0|7" \
  "$(find "$_OTEL_CDIR/ev" -name '*.part' | wc -l | tr -d ' ')|$(find "$_OTEL_CDIR/ev" -name '*.t.ndjson' | wc -l | tr -d ' ')"
assert_eq "flatten CLI: a rerun for an existing tag is refused with exit 3, files untouched" "3|$(cat "$_OTEL_CDIR/ev"/*.ndjson | wc -l | tr -d ' ')" \
  "$(cat "$_OTEL_FDIR/logs.jsonl" | python3 "$_RCV" --flatten "$_OTEL_CDIR/ev" --tag t >/dev/null 2>&1; echo $?)|$(cat "$_OTEL_CDIR/ev"/*.ndjson | wc -l | tr -d ' ')"
# A lone surrogate (a JS string cut mid-emoji) cannot be UTF-8 encoded; the
# record is still written (ASCII-escaped), nothing else in the batch is lost.
assert_eq "flatten CLI: a lone-surrogate attribute does not lose the record" "1|1" \
  "$(printf '%s\n' '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"1790000008000000000","body":{"stringValue":"claude_code.user_prompt"},"attributes":[{"key":"prompt","value":{"stringValue":"cut \ud83d"}}]}]}]}]}' \
     | python3 "$_RCV" --flatten "$_OTEL_CDIR/ev3" --tag t 2>/dev/null | jq -r '.records')|$(grep -c 'cut ' "$_OTEL_CDIR/ev3/other-2026-09-21.t.ndjson")"

# Rows from flattened OTLP batches are pinned to the rows the pre-events
# extractor (lib/otel-extract.jq, removed) produced from the same batches.
_OTEL_PDIR="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_PDIR")
_PNANO=1790000000000000000; _POLDNANO=1781360000000000000
_ospan() {  # OTLP wire format: $1=session $2=nano $3=dt_ms $4=ttft $5=out $6=success $7=attempt
  printf '%s\n' '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claude-code"}}]},"scopeSpans":[{"scope":{"name":"com.anthropic.claude_code.tracing"},"spans":[{"name":"claude_code.llm_request","startTimeUnixNano":"'"$2"'","endTimeUnixNano":"'"$2"'","attributes":[{"key":"model","value":{"stringValue":"claude-opus-4-8"}},{"key":"duration_ms","value":{"intValue":'"$3"'}},{"key":"ttft_ms","value":{"intValue":'"$4"'}},{"key":"output_tokens","value":{"intValue":'"$5"'}},{"key":"session.id","value":{"stringValue":"'"$1"'"}},{"key":"success","value":{"boolValue":'"$6"'}},{"key":"attempt","value":{"intValue":'"$7"'}}]}]}]}]}'
}
_oerr() {   # $1=session $2=nano $3=status_code
  printf '%s\n' '{"resourceLogs":[{"resource":{"attributes":[]},"scopeLogs":[{"scope":{"name":"com.anthropic.claude_code.events"},"logRecords":[{"timeUnixNano":"'"$2"'","body":{"stringValue":"claude_code.api_error"},"attributes":[{"key":"model","value":{"stringValue":"claude-opus-4-8"}},{"key":"status_code","value":{"intValue":'"$3"'}},{"key":"session.id","value":{"stringValue":"'"$1"'"}}]}]}]}]}'
}
{
  _ospan otelsess-a "$_PNANO" 2000 1000 200 true 1
  _ospan otelsess-a "$_PNANO" 4000 2000 400 true 1
  _ospan otelsess-a "$_PNANO" 6000 3000 600 true 1
  _ospan otelsess-b "$_PNANO" 8000 4000 800 false 2
  _ospan ghostsess  "$_PNANO" 5000 2500 500 true 1
  printf '%s\n' 'this is not json'
  _ospan otelsess-a "$_POLDNANO" 9999 9999 9999 true 1
  _oerr otelsess-a "$_PNANO" 429
  _oerr otelsess-b "$_PNANO" 529
  printf '%s\n' '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"'"$_PNANO"'","body":{"stringValue":"claude_code.api_request"},"attributes":[{"key":"session.id","value":{"stringValue":"otelsess-a"}}]}]}]}]}'
} | python3 "$_RCV" --flatten "$_OTEL_PDIR/ev" --tag p >/dev/null 2>&1
cat > "$_OTEL_PDIR/expected" <<'EOF'
{"kind":"err","day":"2026-09-21","model":"claude-opus-4-8","status_code":429,"sessionId":"otelsess-a"}
{"kind":"err","day":"2026-09-21","model":"claude-opus-4-8","status_code":529,"sessionId":"otelsess-b"}
{"kind":"lat","day":"2026-06-13","model":"claude-opus-4-8","dt_ms":9999,"ttft_ms":9999,"out":9999,"ctx":0,"sessionId":"otelsess-a","success":true,"attempt":1}
{"kind":"lat","day":"2026-09-21","model":"claude-opus-4-8","dt_ms":2000,"ttft_ms":1000,"out":200,"ctx":0,"sessionId":"otelsess-a","success":true,"attempt":1}
{"kind":"lat","day":"2026-09-21","model":"claude-opus-4-8","dt_ms":4000,"ttft_ms":2000,"out":400,"ctx":0,"sessionId":"otelsess-a","success":true,"attempt":1}
{"kind":"lat","day":"2026-09-21","model":"claude-opus-4-8","dt_ms":5000,"ttft_ms":2500,"out":500,"ctx":0,"sessionId":"ghostsess","success":true,"attempt":1}
{"kind":"lat","day":"2026-09-21","model":"claude-opus-4-8","dt_ms":6000,"ttft_ms":3000,"out":600,"ctx":0,"sessionId":"otelsess-a","success":true,"attempt":1}
{"kind":"lat","day":"2026-09-21","model":"claude-opus-4-8","dt_ms":8000,"ttft_ms":4000,"out":800,"ctx":0,"sessionId":"otelsess-b","success":false,"attempt":2}
EOF
# an empty AnyValue flattens to {} and a string-typed success occurs on some
# records: both must yield a row (0 / success), not a jq error
assert_eq "otel_rows.jq: {} counts as 0 and a non-boolean success reads as true" '[0,true,1]' \
  "$(printf '{"_sig":"span","_name":"claude_code.llm_request","_t":"%s","model":"m","duration_ms":1,"input_tokens":{},"success":"true","attempt":"1"}\n' "$_PNANO" \
     | jq -cnR -f "$CLAUDII_HOME/lib/otel_rows.jq" | jq -c '[.ctx, .success, .attempt]')"
assert_eq "otel_rows.jq: rows of flattened OTLP batches == the pre-events extractor's rows" \
  "$(<"$_OTEL_PDIR/expected")" \
  "$(cat "$_OTEL_PDIR"/ev/llm-*.ndjson "$_OTEL_PDIR"/ev/err-*.ndjson | jq -cnR -f "$CLAUDII_HOME/lib/otel_rows.jq" | sort)"

# receiver.status: sha of the running receiver file, atomic (no .tmp left);
# a failed write (here the events dir is a FILE) is counted, never raised.
_OTEL_SDIR="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_SDIR")
_SRES=$(CLAUDII_OTEL_DIR="$_OTEL_SDIR" CLAUDII_OTEL_FORWARD= python3 -c '
import importlib.util, json, os, sys
import importlib.machinery
spec = importlib.util.spec_from_file_location("recv", sys.argv[1], loader=importlib.machinery.SourceFileLoader("recv", sys.argv[1])); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.status_write(force=True)
st = json.load(open(m.STATUS_FILE))
print(st["sha"], os.path.exists(m.STATUS_FILE + ".tmp"), st["batches"], st["forward"]["enabled"])
import time
rec = b"{\"resourceLogs\":[{\"scopeLogs\":[{\"logRecords\":[{\"timeUnixNano\":\"1\",\"body\":{\"stringValue\":\"x\"}}]}]}]}"
open(m.EVENTS_DIR, "w").close()          # events/ is a file: the dir cannot be made
n, u = m.persist(rec, "/v1/logs", "application/json", "")
os.unlink(m.EVENTS_DIR)                  # events/ exists, but the target NAME is a directory
os.makedirs(os.path.join(m.EVENTS_DIR, "other-%s.ndjson" % time.strftime("%Y-%m-%d", time.gmtime())))
n2, u2 = m.persist(rec, "/v1/logs", "application/json", "")
print(m._STATUS["write_failed"], m._STATUS["batches"], n, u, n2, u2)
# live fallbacks: a body that is not JSON, gzip that does not decode, and a
# gzip body that does — each filed under unparsed or flattened, never dropped
import gzip, shutil
shutil.rmtree(m.EVENTS_DIR)
r1 = m.persist(b"\xff\xfeprotobuf", "/v1/traces", "application/x-protobuf", "")
r2 = m.persist(b"not gzip at all", "/v1/logs", "application/json", "gzip")
r3 = m.persist(gzip.compress(rec), "/v1/logs", "application/json", "gzip")
r4 = m.persist(gzip.compress(b"plain text"), "/v1/logs", "text/plain", "gzip")   # decodes, is not JSON
unp = [json.loads(l) for l in open(os.path.join(m.EVENTS_DIR, "unparsed-%s.ndjson" % time.strftime("%Y-%m-%d", time.gmtime())))]
print(r1, r2, r3, r4, len(unp), unp[0]["bytes"], "body_b64" in unp[0], unp[1]["body"], unp[1]["encoding"], unp[2]["body"], repr(unp[2]["encoding"]))
' "$_RCV" 2>/dev/null)
assert_eq "receiver: non-JSON, undecodable gzip and gzip bodies are filed, never dropped (decoded body not labelled gzip)" \
  "(0, 1) (0, 1) (1, 0) (0, 1) 3 10 True not gzip at all gzip plain text ''" \
  "$(printf '%s\n' "$_SRES" | sed -n 3p)"
assert_eq "receiver.status: sha == sha256 of the receiver file, no .tmp, counters start at 0" \
  "$(shasum -a 256 "$_RCV" 2>/dev/null | cut -d' ' -f1 || sha256sum "$_RCV" | cut -d' ' -f1) False 0 False" \
  "$(printf '%s\n' "$_SRES" | sed -n 1p)"
assert_eq "receiver: failed writes (no dir, unwritable file) are counted, batches still count, no exception" "2 2 1 0 1 0" \
  "$(printf '%s\n' "$_SRES" | sed -n 2p)"
# doctor reads that status file: matching sha → ok, other sha → DRIFT
_OTEL_DCACHE="$(mktemp -d)"; _OTEL_TMPDIRS+=("$_OTEL_DCACHE"); mkdir -p "$_OTEL_DCACHE/otel"
# the python process that wrote it is gone — a live pid (this shell) stands in
jq -c --argjson p "$$" '.pid = $p' "$_OTEL_SDIR/receiver.status" > "$_OTEL_DCACHE/otel/receiver.status"
_DDOC=$(CLAUDII_CACHE_DIR="$_OTEL_DCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" doctor 2>&1)
assert_contains "otel doctor: sha of the running receiver matches" "sha matches" "$_DDOC"
assert_contains "otel doctor: forward counters shown when forwarding" "ok 0 · failed 0 · dropped 0" \
  "$(jq -c --argjson p "$$" '.pid = $p | .forward.enabled = true | .last_batch = (now | floor)' "$_OTEL_SDIR/receiver.status" > "$_OTEL_DCACHE/otel/receiver.status"; \
     CLAUDII_CACHE_DIR="$_OTEL_DCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" doctor 2>&1)"
jq -c --argjson p "$$" '.pid = $p | .sha = "0000"' "$_OTEL_SDIR/receiver.status" > "$_OTEL_DCACHE/otel/receiver.status"
assert_contains "otel doctor: a stale receiver copy is reported as DRIFT" "DRIFT" \
  "$(CLAUDII_CACHE_DIR="$_OTEL_DCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" doctor 2>&1)"
# an empty field must not shift the ones after it (IFS=tab collapses empties)
jq -c --argjson p "$$" '.pid = $p | .sha = "" | .forward.enabled = true | .forward.failed = 7' "$_OTEL_SDIR/receiver.status" > "$_OTEL_DCACHE/otel/receiver.status"
assert_contains "otel doctor: an empty sha does not shift the forward counters" "ok 0 · failed 7 · dropped 0" \
  "$(CLAUDII_CACHE_DIR="$_OTEL_DCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" doctor 2>&1)"
# the status file of a receiver that is gone
sleep 0 & _RS_DEAD=$!; wait "$_RS_DEAD"
jq -c --argjson p "$_RS_DEAD" '.pid = $p' "$_OTEL_SDIR/receiver.status" > "$_OTEL_DCACHE/otel/receiver.status"
assert_contains "otel doctor: a dead receiver pid is reported as NOT RUNNING" "NOT RUNNING" \
  "$(CLAUDII_CACHE_DIR="$_OTEL_DCACHE" bash "$CLAUDII_HOME/bin/claudii-otel" doctor 2>&1)"

unset _NOW _NANO _OLD _OLDNANO _OB _OE _OBAD _ODOC _PO _POR _POJ _FLAT _LLMREC _TRREC _CSTATS _SRES _DDOC _RROWS _GROWS
