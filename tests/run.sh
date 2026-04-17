#!/bin/bash
# claudii test runner — simple bash-based E2E tests
# Usage: ./tests/run.sh [test_file]
#
# Runs each test file as a subprocess (parallel by default).
# Set CLAUDII_TEST_SEQUENTIAL=1 to force sequential execution.

set -uo pipefail
# Note: no set -e — tests may produce non-zero exits intentionally

CLAUDII_HOME="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$CLAUDII_HOME/tests"
PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test helpers
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"
    (( ++PASS ))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected: ${GREEN}$expected${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    (( ++FAIL ))
    ERRORS+=("$desc")
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  # Use grep on here-string — avoids SIGPIPE broken pipe with pipefail on large input (Ubuntu CI)
  # -F: treat needle as literal string (not regex) — use assert_matches for regex
  if grep -qF "$needle" <<< "$haystack"; then
    echo -e "  ${GREEN}✓${NC} $desc"
    (( ++PASS ))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected to contain: ${GREEN}$needle${NC}"
    echo -e "    Got (first 200 chars): ${RED}${haystack:0:200}${NC}"
    (( ++FAIL ))
    ERRORS+=("$desc")
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -qF "$needle" <<< "$haystack"; then
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected NOT to contain: ${RED}$needle${NC}"
    echo -e "    Got (first 200 chars): ${RED}${haystack:0:200}${NC}"
    (( ++FAIL ))
    ERRORS+=("$desc")
  else
    echo -e "  ${GREEN}✓${NC} $desc"
    (( ++PASS ))
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2" cmd="$3"
  local actual _errexit=0
  [[ $- == *e* ]] && _errexit=1
  set +e
  eval "$cmd" >/dev/null 2>&1
  actual=$?
  (( _errexit )) && set -e || true
  assert_eq "$desc" "$expected" "$actual"
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"
    (( ++PASS ))
  else
    echo -e "  ${RED}✗${NC} $desc: file not found: $path"
    (( ++FAIL ))
    ERRORS+=("$desc")
  fi
}

assert_no_literal_ansi() {
  local desc="$1" text="$2"
  if echo "$text" | grep -qF '\033'; then
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Output contains literal \\\\033 — ANSI not rendered as ESC bytes"
    (( ++FAIL )); ERRORS+=("$desc")
  else
    echo -e "  ${GREEN}✓${NC} $desc"
    (( ++PASS ))
  fi
}

assert_matches() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -qE "$needle" <<< "$haystack"; then
    echo -e "  ${GREEN}✓${NC} $desc"
    (( ++PASS ))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected to match: ${GREEN}$needle${NC}"
    echo -e "    Got (first 200 chars): ${RED}${haystack:0:200}${NC}"
    (( ++FAIL ))
    ERRORS+=("$desc")
  fi
}

# Export for test files (subprocess mode)
export CLAUDII_HOME TESTS_DIR
export GREEN RED YELLOW NC
export -f assert_eq assert_contains assert_not_contains assert_exit_code assert_file_exists
export -f assert_no_literal_ansi assert_matches

# ── Subprocess helper ────────────────────────────────────────────────────────
# Runs a single test file in a subshell, writes output + summary line to $out_file.
# Summary line format: CLAUDII_TEST_RESULT:<pass>:<fail>
# Error lines format:  CLAUDII_TEST_ERROR:<description>
_run_single_test() {
  local test_file="$1" out_file="$2"
  (
    PASS=0; FAIL=0; ERRORS=()
    # Isolate zsh subprocesses — empty ZDOTDIR prevents sourcing user's .zshrc/.zshenv
    export ZDOTDIR=$(mktemp -d "${TMPDIR:-/tmp}/claudii_zdotdir.XXXXXX")
    echo -e "${YELLOW}$(basename "$test_file")${NC}"
    source "$test_file"
    echo "CLAUDII_TEST_RESULT:${PASS}:${FAIL}"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
      for err in "${ERRORS[@]}"; do
        echo "CLAUDII_TEST_ERROR:$err"
      done
    fi
    rm -rf "$ZDOTDIR" 2>/dev/null || true
  ) > "$out_file" 2>&1
}

# Parse flags
_for_file=""
_summary_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --for)     _for_file="${2:-}"; shift 2 ;;
    --summary) _summary_only=1; shift ;;
    *) break ;;
  esac
done

# Run tests
if [[ -n "${1:-}" ]]; then
  # Run specific test file — inline (no parallelization)
  export ZDOTDIR=$(mktemp -d "${TMPDIR:-/tmp}/claudii_zdotdir.XXXXXX")
  echo -e "${YELLOW}Running: $1${NC}"
  source "$1"
  rm -rf "$ZDOTDIR" 2>/dev/null || true
else
  # Parallel: launch each test file as a subprocess, aggregate results
  _out_dir=$(mktemp -d "${TMPDIR:-/tmp}/claudii_test_run.XXXXXX")
  _pids=()
  _out_files=()

  for test_file in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue
    # Skip files that don't touch the requested source file
    if [[ -n "$_for_file" ]]; then
      grep -qE "^# touches:.*(^|[[:space:]])${_for_file}([[:space:]]|$)" "$test_file" 2>/dev/null || continue
    fi
    _base=$(basename "$test_file" .sh)
    _out_file="$_out_dir/${_base}.out"
    _out_files+=("$_out_file")

    if [[ "${CLAUDII_TEST_SEQUENTIAL:-0}" == "1" ]]; then
      _run_single_test "$test_file" "$_out_file"
    else
      _run_single_test "$test_file" "$_out_file" &
      _pids+=($!)
    fi
  done

  # Wait for all parallel jobs
  if [[ "${CLAUDII_TEST_SEQUENTIAL:-0}" != "1" ]]; then
    for _pid in "${_pids[@]}"; do
      wait "$_pid" 2>/dev/null || true
    done
  fi

  # Aggregate results — preserve file order
  for _out_file in "${_out_files[@]}"; do
    [[ -f "$_out_file" ]] || continue
    if (( ! _summary_only )); then
      echo ""
      grep -v '^CLAUDII_TEST_RESULT:' "$_out_file" | grep -v '^CLAUDII_TEST_ERROR:' || true
    fi
    _summary=$(grep '^CLAUDII_TEST_RESULT:' "$_out_file" || true)
    if [[ -n "$_summary" ]]; then
      _p=$(echo "$_summary" | cut -d: -f2)
      _f=$(echo "$_summary" | cut -d: -f3)
      PASS=$(( PASS + _p ))
      FAIL=$(( FAIL + _f ))
    fi
    while IFS= read -r _err_line; do
      ERRORS+=("${_err_line#CLAUDII_TEST_ERROR:}")
    done < <(grep '^CLAUDII_TEST_ERROR:' "$_out_file" || true)
  done

  rm -rf "$_out_dir"
fi

# Summary
if (( _summary_only )); then
  if (( FAIL > 0 )); then
    echo -e "${RED}${FAIL} failed${NC} / ${PASS} passed"
    for err in "${ERRORS[@]}"; do echo "  - $err"; done
  else
    echo -e "${GREEN}${PASS} passed${NC}"
  fi
else
  echo ""
  echo "───────────────────"
  echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failures:${NC}"
    for err in "${ERRORS[@]}"; do
      echo "  - $err"
    done
  fi
  echo ""
fi

exit $FAIL
