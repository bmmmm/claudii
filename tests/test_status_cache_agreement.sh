# touches: lib/helpers.sh bin/claudii-cc-statusline lib/statusline.zsh lib/cmd/overview.sh

# test_status_cache_agreement.sh — the three status-models readers agree.
#
# ~/.cache/claudii/status-models is read by three DIFFERENT implementations:
#
#   bash  _status_cache_read/_status_cache_verdict  lib/helpers.sh
#         the one CLI parser — `claudii`, `claudii status`, `claudii perf`
#   bash  the inline block near _seg_claude_status  bin/claudii-cc-statusline
#         the Claude Code statusline; fork-free by requirement
#   zsh   the inline block in _claudii_statusline_render  lib/statusline.zsh
#         the shell RPROMPT; zsh, so it cannot call the bash helper at all
#
# The two statusline copies stay separate on purpose — both render on a hot
# path where a `$(…)` or a `source` of a 600-line bash library costs a visible
# frame. What they must NOT be is unverified: until this file existed, all
# three carried "Kept in sync with …" comments and nothing checked them.
#
# So: one cache in, three renderings out, normalized to the ONE thing they are
# supposed to agree on — the classification. The color vocabularies genuinely
# differ (ANSI SGR vs zsh %F{}) and the glyph sets differ per surface, so the
# normalizers below fold each rendering down to a canonical
# "collapse=… problems=… incident=…" and those are compared.

# lib/visual.sh first: the sourced command files interpolate CLAUDII_CLR_*
# unguarded and run.sh runs test files under `set -u`.
source "$CLAUDII_HOME/lib/visual.sh" 2>/dev/null
source "$CLAUDII_HOME/lib/helpers.sh" 2>/dev/null

_SCA_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudii_sca.XXXXXX")
mkdir -p "$_SCA_TMP/cache" "$_SCA_TMP/config/claudii" "$_SCA_TMP/zdot"
cp "$CLAUDII_HOME/config/defaults.json" "$_SCA_TMP/config/claudii/config.json"
_SCA_CACHE="$_SCA_TMP/cache/status-models"

# ── The three renderers, each reduced to the canonical verdict ────────────────

# 1. The helper. Renders nothing itself — it IS the classification, so the
#    canonical form is read straight off its output variables. Two shapes are
#    normalized away because they are renderer-invisible: _SCV_PROBLEMS is still
#    filled on a uniform all-down/all-degraded verdict (the renderers collapse
#    instead of listing), and an incident that affects no model shows as the
#    neutral note rather than its stage.
_sca_helper() {
  local _models="$1" _p _out _inc
  _status_cache_read "$_SCA_CACHE" || { printf 'collapse=none problems= incident='; return; }
  _status_cache_verdict "$_models"
  _out=""
  if [[ "$_SCV_COLLAPSE" == "problems" ]]; then
    for _p in ${_SCV_PROBLEMS[@]+"${_SCV_PROBLEMS[@]}"}; do
      _out+="${_out:+,}${_p}"
    done
  fi
  _inc="$_SC_INCIDENT"
  if [[ -n "$_inc" && $_SC_ANY_ISSUE -eq 0 ]]; then _inc="note"; fi
  printf 'collapse=%s problems=%s incident=%s' "$_SCV_COLLAPSE" "$_out" "$_inc"
}

# Shared glyph→word normalizer for the two rendered strings. Strips ANSI SGR
# and zsh prompt escapes, then reads the bracketed health chip back out.
#   "[claude ✓] 3m"                 -> collapse=ok
#   "[claude ↓]"                    -> collapse=down
#   "[Opus ↓ Sonnet ~] 3m ⚐"        -> collapse=problems problems=opus=down,sonnet=degraded
# Model names come back capitalized (Opus); lower-cased here so the three forms
# are literally comparable.
_sca_normalize() {
  local _s="$1" _chip _rest _tok _prev="" _probs="" _collapse="none" _inc=""
  # ANSI SGR, then zsh %F{...}/%f/%K{...}/%k.
  _s=$(printf '%s' "$_s" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/%[FK]{[^}]*}//g' -e 's/%[fk]//g')
  case "$_s" in
    *'['*']'*) ;;
    *) printf 'collapse=none problems= incident='; return ;;
  esac
  _chip="${_s#*[}"; _chip="${_chip%%]*}"
  _rest="${_s#*]}"
  case "$_rest" in
    *'‼'*) _inc="investigating" ;;
    *'⚐'*) _inc="identified" ;;
    *'◎'*) _inc="monitoring" ;;
    *'ⓘ'*) _inc="note" ;;   # incident exists, no tracked model affected
  esac
  # The chip is "<name> <glyph>" pairs. ✓/✗/↓/~/⚠ are the per-surface spellings
  # of ok/down/degraded — cc-statusline uses ↓/~, the overview ✗/⚠.
  for _tok in $_chip; do
    case "$_tok" in
      '✓') [[ "$_prev" == "claude" ]] && _collapse="ok" ;;
      '↓'|'✗')
        if [[ "$_prev" == "claude" ]]; then _collapse="down"
        else _collapse="problems"; _probs+="${_probs:+,}$(printf '%s' "$_prev" | tr '[:upper:]' '[:lower:]')=down"
        fi ;;
      '~'|'⚠')
        if [[ "$_prev" == "claude" ]]; then _collapse="degraded"
        else _collapse="problems"; _probs+="${_probs:+,}$(printf '%s' "$_prev" | tr '[:upper:]' '[:lower:]')=degraded"
        fi ;;
      *) _prev="$_tok" ;;
    esac
  done
  printf 'collapse=%s problems=%s incident=%s' "$_collapse" "$_probs" "$_inc"
}

# 2. bin/claudii-cc-statusline — run the real script on a claude-status-only
#    layout so nothing but the ClaudeStatus segment reaches stdout.
# CLAUDII_HOME is already exported by run.sh; the script path is hoisted into a
# local so the env prefix below does not also expand it (shellcheck SC2097/98).
_SCA_SL="$CLAUDII_HOME/bin/claudii-cc-statusline"
_SCA_ST_BIN="$CLAUDII_HOME/bin/claudii-status"
_SCA_JSON='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":100,"total_output_tokens":10,"context_window_size":200000},"cost":{"total_cost_usd":0.01}}'
_sca_ccsl() {
  local _cfg="$_SCA_TMP/config-cc"
  mkdir -p "$_cfg/claudii"
  jq --arg m "$1" '.statusline.lines = [["claude-status"]] | .statusline.models = $m' \
    "$CLAUDII_HOME/config/defaults.json" > "$_cfg/claudii/config.json"
  _sca_normalize "$(printf '%s' "$_SCA_JSON" \
    | CLAUDII_CACHE_DIR="$_SCA_TMP/cache" XDG_CONFIG_HOME="$_cfg" \
      /bin/bash "$_SCA_SL" 2>/dev/null)"
}

# 3. lib/statusline.zsh — the real RPROMPT, through the real plugin entry point.
#    _CLAUDII_CMD_RAN=1 so the dashboard path behaves as it does interactively;
#    empty ZDOTDIR so no user .zshrc leaks in.
_sca_zsh() {
  local _cfg="$_SCA_TMP/config-zsh"
  mkdir -p "$_cfg/claudii"
  jq --arg m "$1" '.statusline.models = $m' \
    "$CLAUDII_HOME/config/defaults.json" > "$_cfg/claudii/config.json"
  _sca_normalize "$(
    CLAUDII_CACHE_DIR="$_SCA_TMP/cache" XDG_CONFIG_HOME="$_cfg" \
    ZDOTDIR="$_SCA_TMP/zdot" CLAUDII_HOME="$CLAUDII_HOME" \
    zsh -c "
      source \"\$CLAUDII_HOME/claudii.plugin.zsh\"
      _CLAUDII_CMD_RAN=1
      _claudii_statusline
      printf '%s' \"\$RPROMPT\"
    " 2>/dev/null
  )"
}

# ── The fixtures ─────────────────────────────────────────────────────────────
# Columns: label | cache content (\n escapes) | expected canonical verdict
# The model list is the 4-model default for every row, so all three readers see
# the same set and the file-driven/config-driven difference cannot hide a bug.
_SCA_MODELS="opus,sonnet,haiku,fable"
_SCA_ROWS='
all ok|opus=ok\nsonnet=ok\nhaiku=ok\nfable=ok\n|collapse=ok problems= incident=
one down|opus=down\nsonnet=ok\nhaiku=ok\nfable=ok\n|collapse=problems problems=opus=down incident=
one degraded|opus=ok\nsonnet=degraded\nhaiku=ok\nfable=ok\n|collapse=problems problems=sonnet=degraded incident=
two mixed|opus=down\nsonnet=degraded\nhaiku=ok\nfable=ok\n|collapse=problems problems=opus=down,sonnet=degraded incident=
all down|opus=down\nsonnet=down\nhaiku=down\nfable=down\n|collapse=down problems= incident=
all degraded|opus=degraded\nsonnet=degraded\nhaiku=degraded\nfable=degraded\n|collapse=degraded problems= incident=
incident only|opus=ok\nsonnet=ok\nhaiku=ok\nfable=ok\n_incident=monitoring\n|collapse=ok problems= incident=note
incident + outage|opus=down\nsonnet=ok\nhaiku=ok\nfable=ok\n_incident=identified\n|collapse=problems problems=opus=down incident=identified
api unreachable|opus=ok\nsonnet=ok\nhaiku=ok\nfable=ok\n_api=unreachable\n|collapse=ok problems= incident=
'

while IFS='|' read -r _lbl _content _want; do
  [[ -z "$_lbl" ]] && continue
  printf '%b' "$_content" > "$_SCA_CACHE"

  _h=$(_sca_helper "$_SCA_MODELS")
  _c=$(_sca_ccsl   "$_SCA_MODELS")
  _z=$(_sca_zsh    "$_SCA_MODELS")

  # 1. Each reader says what this table says it says. Without this the three
  #    could agree on a wrong answer and the file would still be green.
  assert_eq "sca[$_lbl]: helper"        "$_want" "$_h"
  assert_eq "sca[$_lbl]: cc-statusline" "$_want" "$_c"
  assert_eq "sca[$_lbl]: zsh RPROMPT"   "$_want" "$_z"

  # 2. The agreement axis itself, derived from actual output on both sides —
  #    never from the expectation column, or a broken pair could still match it.
  assert_eq "sca[$_lbl]: helper == cc-statusline" "$_h" "$_c"
  assert_eq "sca[$_lbl]: helper == zsh RPROMPT"   "$_h" "$_z"
done <<< "$_SCA_ROWS"

# ── Incident glyph: note vs. stage ───────────────────────────────────────────
# An incident that touches no tracked model shows the neutral note glyph, not
# the stage-colored alarm — the Mythos/Fable false-cascade regression. The
# normalizer above deliberately maps only the stage glyphs, so "incident=" for
# the note case is the assertion, not an omission. Checked on the raw strings
# here because ⓘ is exactly what the canonical form drops.
printf 'opus=ok\nsonnet=ok\nhaiku=ok\nfable=ok\n_incident=monitoring\n' > "$_SCA_CACHE"
_sca_raw_cc() {
  local _cfg="$_SCA_TMP/config-cc"
  printf '%s' "$_SCA_JSON" \
    | CLAUDII_CACHE_DIR="$_SCA_TMP/cache" XDG_CONFIG_HOME="$_cfg" \
      /bin/bash "$_SCA_SL" 2>/dev/null
}
_sca_out=$(_sca_ccsl "$_SCA_MODELS"; _sca_raw_cc)
assert_contains "sca: unaffected incident → note glyph (cc-statusline)" "ⓘ" "$_sca_out"
assert_not_contains "sca: unaffected incident → not the stage glyph" "◎" "$_sca_out"
# The helper carries the same two facts the renderers branch on.
_status_cache_read "$_SCA_CACHE"
assert_eq "sca: helper sees the incident stage" "monitoring" "$_SC_INCIDENT"
assert_eq "sca: helper sees no affected model"  "0"          "$_SC_ANY_ISSUE"

# ── The one DELIBERATE divergence, pinned ────────────────────────────────────
# The two statuslines are keyed on `statusline.models`: a model in the cache but
# not in that list is invisible to them, and a model in the list but not in the
# cache is assumed healthy. The overview is keyed on the CACHE instead, so it
# names an untracked family that is down. Unifying them would either hide a real
# outage from `claudii` or make the RPROMPT report models the user does not use,
# so the two modes live in one function and are asserted apart.
printf 'opus=ok\nsonnet=ok\nhaiku=ok\nfable=ok\nmythos=down\n' > "$_SCA_CACHE"
_status_cache_read "$_SCA_CACHE"
_status_cache_verdict "$_SCA_MODELS"
assert_eq "sca divergence: config-keyed ignores the untracked family" "ok" "$_SCV_COLLAPSE"
_status_cache_verdict ""
assert_eq "sca divergence: cache-keyed names it" "problems" "$_SCV_COLLAPSE"
assert_eq "sca divergence: and it is the one that is down" "mythos=down" \
  "${_SCV_PROBLEMS[0]}"
# And the two statuslines really do stay quiet about it — the divergence is a
# property of the shipped code, not just of the helper's two modes.
assert_eq "sca divergence: cc-statusline stays collapsed" \
  "collapse=ok problems= incident=" "$(_sca_ccsl "$_SCA_MODELS")"
assert_eq "sca divergence: zsh RPROMPT stays collapsed" \
  "collapse=ok problems= incident=" "$(_sca_zsh "$_SCA_MODELS")"

# ── Absent / empty cache ─────────────────────────────────────────────────────
# Both are "nothing known yet", not an error: _status_cache_read returns 1 and
# leaves every output variable at its empty default, so a caller that ignores
# the return value still renders a blank chip rather than stale state.
rm -f "$_SCA_CACHE"
_status_cache_read "$_SCA_CACHE" && assert_eq "sca: missing cache returns 1" "1" "0"
assert_eq "sca: missing cache → no models"   "0" "$_SC_COUNT"
assert_eq "sca: missing cache → no incident" ""  "$_SC_INCIDENT"
assert_eq "sca: missing cache → no issue"    "0" "$_SC_ANY_ISSUE"
: > "$_SCA_CACHE"
_status_cache_read "$_SCA_CACHE" && assert_eq "sca: empty cache returns 1" "1" "0"
assert_eq "sca: empty cache → no models" "0" "$_SC_COUNT"

# ── The parser's own invariants ──────────────────────────────────────────────
# bash 3.2 has no working `declare -A`: it degrades to an indexed array where
# every key lands on arr[0], last write wins. A key=value cache is exactly the
# shape that invites one, so assert the map actually holds distinct keys — a
# reader that silently collapsed to one entry would still pass the render
# comparisons above whenever all models share a state.
printf 'opus=down\nsonnet=degraded\nhaiku=ok\nfable=ok\n_incident=investigating\n_incident_started=1700000000\n_api=unreachable\n' \
  > "$_SCA_CACHE"
_status_cache_read "$_SCA_CACHE"
assert_eq "sca parser: four distinct model keys"  "4" "$_SC_COUNT"
assert_eq "sca parser: keys in file order" "opus sonnet haiku fable" "${_SC_KEYS[*]}"
assert_eq "sca parser: values track their keys" "down degraded ok ok" "${_SC_VALS[*]}"
_status_cache_state opus;   assert_eq "sca parser: lookup opus"   "down"     "$_SC_STATE"
_status_cache_state sonnet; assert_eq "sca parser: lookup sonnet" "degraded" "$_SC_STATE"
_status_cache_state haiku;  assert_eq "sca parser: lookup haiku"  "ok"       "$_SC_STATE"
assert_eq "sca parser: internal keys split out (_incident)" "investigating" "$_SC_INCIDENT"
assert_eq "sca parser: internal keys split out (_incident_started)" "1700000000" "$_SC_INCIDENT_STARTED"
assert_eq "sca parser: internal keys split out (_api)" "unreachable" "$_SC_API"
_status_cache_state _incident && assert_eq "sca parser: _* keys are not models" "1" "0"

# No grep anywhere in the parser: `producer | grep -q` returns 141 under
# pipefail even on a match (docs/gotchas.md #31), and this is the code path
# where that bit — a model kept reading `ok` while it was down.
_SCA_FN=$(declare -f _status_cache_read _status_cache_state _status_cache_verdict _status_cache_file)
assert_not_contains "sca parser: no grep in the parser" "grep" "$_SCA_FN"
assert_not_contains "sca parser: no declare -A in the parser" "declare -A" "$_SCA_FN"

# The per-model grep+cut is gone from `claudii status` too — that site forked
# ten processes to read five lines of key=value.
assert_eq "sca: no per-model grep in _status_render" "0" \
  "$(grep -c 'grep "\^\${_sm}=' "$CLAUDII_HOME/lib/cmd/system.sh" || true)"
assert_eq "sca: no per-model grep in claudii-status" "0" \
  "$(grep -c 'grep "\^\${_\?m}=' "$CLAUDII_HOME/bin/claudii-status" || true)"

# ── The writer reads its own cache back — bin/claudii-status ─────────────────
# claudii-status is both producer and consumer: it decides its exit code and its
# stderr from the cache it just read or wrote. Those two reads used to be a
# `grep`+`cut` per model; they now go through the same parser, and nothing in
# the suite pinned either one (verified by breaking them: the suite stayed
# green), so they are pinned here.
#
# 1. Cache-hit path — a FRESH cache short-circuits before any network. A down
#    model must still make the process exit 1 and name itself on stderr.
_SCA_ST="$_SCA_TMP/writer"
mkdir -p "$_SCA_ST/cache" "$_SCA_ST/config/claudii"
cp "$CLAUDII_HOME/config/defaults.json" "$_SCA_ST/config/claudii/config.json"
# Returns claudii-status's own exit code and leaves its (de-ANSI'd) stderr in
# $_SCA_ST/err.txt. NOT `_sca_out=$(_sca_status …)`: the rc has to survive, and
# a variable set inside a command substitution dies with the subshell.
_sca_status() {   # <cache content> [extra args…]
  printf '%b' "$1" > "$_SCA_ST/cache/status-models"
  shift
  local _rc
  CLAUDII_CACHE_DIR="$_SCA_ST/cache" XDG_CONFIG_HOME="$_SCA_ST/config" \
  CLAUDII_CACHE_TTL=999999 CLAUDII_HOME="$CLAUDII_HOME" \
    /bin/bash "$_SCA_ST_BIN" "$@" \
    2> "$_SCA_ST/err.raw" >/dev/null
  _rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$_SCA_ST/err.raw" > "$_SCA_ST/err.txt"
  return $_rc
}

_sca_status 'opus=ok\nsonnet=ok\nhaiku=ok\nfable=ok\n' --quiet
assert_eq "writer: fresh all-ok cache exits 0" "0" "$?"
_sca_status 'opus=down\nsonnet=ok\nhaiku=ok\nfable=ok\n' --quiet
assert_eq "writer: fresh cache with a down model exits 1" "1" "$?"
_sca_status 'opus=ok\nsonnet=degraded\nhaiku=ok\nfable=ok\n' --quiet
assert_eq "writer: fresh cache with a degraded model exits 1" "1" "$?"
assert_eq "writer: --quiet stays silent about it" "" "$(cat "$_SCA_ST/err.txt")"
# Non-quiet: the cache-hit branch names each unhealthy model, and only those.
_sca_status 'opus=down\nsonnet=degraded\nhaiku=ok\nfable=ok\n_incident=identified\n' || true
_sca_out=$(cat "$_SCA_ST/err.txt")
assert_contains "writer: cache-hit names the down model"     "opus down"       "$_sca_out"
assert_contains "writer: cache-hit names the degraded model" "sonnet degraded" "$_sca_out"
assert_not_contains "writer: cache-hit stays quiet about healthy models" "haiku" "$_sca_out"
assert_not_contains "writer: cache-hit does not report internal keys" "_incident" "$_sca_out"

# 2. Post-fetch path — _write_incidents re-reads the cache it just wrote to
#    build the summary, the stderr lines and the exit code. curl is mocked, so
#    this exercises the real fetch → write → read-back round trip offline.
_SCA_MOCK="$_SCA_TMP/mock"
mkdir -p "$_SCA_MOCK"
cat > "$_SCA_MOCK/unresolved.json" <<'JSON'
{"incidents":[{
  "name":"Elevated errors on Claude Opus",
  "status":"investigating","impact":"major",
  "incident_updates":[{"body":"Opus requests are failing."}],
  "components":[{"name":"Claude Opus"}]
}]}
JSON
cat > "$_SCA_MOCK/curl" <<EOF
#!/bin/bash
for arg in "\$@"; do
  case "\$arg" in
    *unresolved.json*) cat "$_SCA_MOCK/unresolved.json"; exit 0 ;;
  esac
done
exit 22
EOF
chmod +x "$_SCA_MOCK/curl"
rm -f "$_SCA_ST/cache/status-models" "$_SCA_ST/cache/status-unresolved.json"
_sca_out=$(PATH="$_SCA_MOCK:$PATH" CLAUDII_CACHE_DIR="$_SCA_ST/cache" \
  XDG_CONFIG_HOME="$_SCA_ST/config" CLAUDII_HOME="$CLAUDII_HOME" \
  /bin/bash "$_SCA_ST_BIN" 2>&1 >/dev/null)
_SCA_RC=$?
_sca_out=$(printf '%s' "$_sca_out" | sed 's/\x1b\[[0-9;]*m//g')
assert_eq "writer: an outage it just wrote makes it exit 1" "1" "$_SCA_RC"
assert_contains "writer: post-fetch summary names the affected model" "Opus down" "$_sca_out"
assert_not_contains "writer: post-fetch summary spares the healthy ones" "Sonnet down" "$_sca_out"
assert_contains "writer: and the cache it wrote agrees" "opus=down" \
  "$(cat "$_SCA_ST/cache/status-models")"
assert_contains "writer: healthy models written as ok" "sonnet=ok" \
  "$(cat "$_SCA_ST/cache/status-models")"

rm -rf "$_SCA_TMP"
unset _SCA_TMP _SCA_CACHE _SCA_ROWS _SCA_MODELS _SCA_FN _SCA_SL _SCA_JSON \
      _SCA_ST _SCA_MOCK _SCA_RC _sca_out _lbl _content _want _h _c _z
