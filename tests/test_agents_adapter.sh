# touches: lib/helpers.sh lib/cmd/sessions.sh
# test_agents_adapter.sh — claude agents --json adapter + fallback paths
#
# Covers three scenarios:
#   1. claude on PATH, returns [] → fallback to kill -0 still works.
#   2. claude on PATH, returns a populated array → _LIVE_PIDS populated,
#      _pid_is_live / _pid_kind work, _PSC_kind picked up by parser.
#   3. claude NOT on PATH → fallback kill -0 + 24h cap kicks in.

# Helper: run a bash one-liner with helpers.sh sourced and an isolated PATH.
# $1: PATH override (so we can hide or stub `claude`)
# $2: bash body to execute (single-quoted)
_aa_run() {
  CLAUDII_HOME="$CLAUDII_HOME" PATH="$1" bash -c "
    source \"\$CLAUDII_HOME/lib/visual.sh\" 2>/dev/null
    source \"\$CLAUDII_HOME/lib/spinner.sh\" 2>/dev/null
    source \"\$CLAUDII_HOME/lib/helpers.sh\"
    $2
  "
}

# ── 1. claude returns [] ─────────────────────────────────────────────────────
_aa_bin1=$(mktemp -d "${TMPDIR:-/tmp}/claudii_aa_bin1.XXXXXX")
cat > "$_aa_bin1/claude" <<'EOF'
#!/bin/bash
echo '[]'
EOF
chmod +x "$_aa_bin1/claude"

_aa_out1=$(_aa_run "$_aa_bin1:$PATH" '
  _live_pids_init
  echo "inited=$_LIVE_PIDS_INITED count=${#_LIVE_PIDS[@]}"
')
assert_contains "claude returns []: _LIVE_PIDS_INITED=1, count=0" "inited=1 count=0" "$_aa_out1"

# ── 2. claude returns populated JSON ────────────────────────────────────────
_aa_bin2=$(mktemp -d "${TMPDIR:-/tmp}/claudii_aa_bin2.XXXXXX")
cat > "$_aa_bin2/claude" <<'EOF'
#!/bin/bash
cat <<JSON
[
  {"pid": 11111, "kind": "background", "status": "idle"},
  {"pid": 22222, "kind": "interactive", "status": "busy"}
]
JSON
EOF
chmod +x "$_aa_bin2/claude"

_aa_out2=$(_aa_run "$_aa_bin2:$PATH" '
  _live_pids_init
  echo "count=${#_LIVE_PIDS[@]}"
  echo "pid0=${_LIVE_PIDS[0]} kind0=${_LIVE_PIDS_KIND[0]}"
  echo "pid1=${_LIVE_PIDS[1]} kind1=${_LIVE_PIDS_KIND[1]}"
  _pid_is_live 11111 && echo "is_live_11111=yes" || echo "is_live_11111=no"
  _pid_is_live 99999 && echo "is_live_99999=yes" || echo "is_live_99999=no"
  echo "kind_22222=$(_pid_kind 22222)"
')
assert_contains "populated JSON: 2 entries"          "count=2"             "$_aa_out2"
assert_contains "populated JSON: pid 11111 captured" "pid0=11111"          "$_aa_out2"
assert_contains "populated JSON: kind background"    "kind0=background"    "$_aa_out2"
assert_contains "populated JSON: pid 22222 captured" "pid1=22222"          "$_aa_out2"
assert_contains "_pid_is_live hit"                   "is_live_11111=yes"   "$_aa_out2"
assert_contains "_pid_is_live miss"                  "is_live_99999=no"    "$_aa_out2"
assert_contains "_pid_kind returns interactive"      "kind_22222=interactive" "$_aa_out2"

# ── 2b. _parse_session_cache lifts kind from live-agents map ─────────────────
_aa_cache=$(mktemp -d "${TMPDIR:-/tmp}/claudii_aa_cache.XXXXXX")
cat > "$_aa_cache/session-bgtest1" <<EOF
model=Sonnet
ppid=11111
ctx_pct=20
cost=0.05
session_id=bg-test-uuid
EOF

_aa_out2b=$(_aa_run "$_aa_bin2:$PATH" "
  _live_pids_init
  _parse_session_cache \"$_aa_cache/session-bgtest1\"
  echo \"active=\$_PSC_is_active kind=\$_PSC_kind\"
")
assert_contains "_parse_session_cache: API hit → active=1" "active=1" "$_aa_out2b"
assert_contains "_parse_session_cache: API hit → kind=background" "kind=background" "$_aa_out2b"

# ── 3. claude NOT on PATH → fallback to kill -0 ──────────────────────────────
# Create a cache file with ppid=$$ (the test process, definitely alive).
cat > "$_aa_cache/session-fallback" <<EOF
model=Opus
ppid=$$
ctx_pct=30
cost=0.10
session_id=fallback-uuid
EOF

# PATH that contains common utils (bash, jq, stat, date, mktemp) but no `claude`.
# We can't use an empty PATH — the subshell needs bash itself to run.
_aa_syspath="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
_aa_out3=$(_aa_run "$_aa_syspath" "
  # Guard: if the system PATH unexpectedly contains a real claude binary, the
  # test would silently exercise the wrong path. Skip with a marker line.
  if command -v claude >/dev/null 2>&1; then
    echo 'SKIP: claude found in system PATH'
    exit
  fi
  _live_pids_init
  _parse_session_cache \"$_aa_cache/session-fallback\"
  echo \"inited=\$_LIVE_PIDS_INITED count=\${#_LIVE_PIDS[@]} active=\$_PSC_is_active kind=[\$_PSC_kind]\"
")
if [[ "$_aa_out3" == SKIP:* ]]; then
  echo "  (skipped fallback test: $_aa_out3)"
else
  assert_contains "claude missing: init still flips _LIVE_PIDS_INITED" "inited=1" "$_aa_out3"
  assert_contains "claude missing: array stays empty"                  "count=0"  "$_aa_out3"
  assert_contains "claude missing: fallback kill -0 marks active"      "active=1" "$_aa_out3"
  assert_contains "claude missing: _PSC_kind stays empty"              "kind=[]"  "$_aa_out3"
fi

# ── 4. claude returns garbage (non-JSON) → safe failure, fallback runs ──────
_aa_bin4=$(mktemp -d "${TMPDIR:-/tmp}/claudii_aa_bin4.XXXXXX")
cat > "$_aa_bin4/claude" <<'EOF'
#!/bin/bash
echo "this is not json, just a friendly message"
EOF
chmod +x "$_aa_bin4/claude"

_aa_out4=$(_aa_run "$_aa_bin4:$PATH" "
  _live_pids_init
  _parse_session_cache \"$_aa_cache/session-fallback\"
  echo \"count=\${#_LIVE_PIDS[@]} active=\$_PSC_is_active\"
")
assert_contains "garbage JSON: _LIVE_PIDS stays empty" "count=0" "$_aa_out4"
assert_contains "garbage JSON: fallback kill -0 still marks active" "active=1" "$_aa_out4"

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf "$_aa_bin1" "$_aa_bin2" "$_aa_bin4" "$_aa_cache"
unset _aa_bin1 _aa_bin2 _aa_bin4 _aa_cache _aa_out1 _aa_out2 _aa_out2b _aa_out3 _aa_out4 _aa_syspath
