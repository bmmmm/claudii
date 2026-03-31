#!/bin/bash
# claudii test runner — simple bash-based E2E tests
# Usage: ./tests/run.sh [test_file]

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
    (( PASS++ ))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected: ${GREEN}$expected${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    (( FAIL++ ))
    ERRORS+=("$desc")
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  # Use grep on here-string — avoids SIGPIPE broken pipe with pipefail on large input (Ubuntu CI)
  # -F: treat needle as literal string (not regex) — use assert_matches for regex
  if grep -qF "$needle" <<< "$haystack"; then
    echo -e "  ${GREEN}✓${NC} $desc"
    (( PASS++ ))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected to contain: ${GREEN}$needle${NC}"
    echo -e "    Got (first 200 chars): ${RED}${haystack:0:200}${NC}"
    (( FAIL++ ))
    ERRORS+=("$desc")
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -qF "$needle" <<< "$haystack"; then
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected NOT to contain: ${RED}$needle${NC}"
    echo -e "    Got (first 200 chars): ${RED}${haystack:0:200}${NC}"
    (( FAIL++ ))
    ERRORS+=("$desc")
  else
    echo -e "  ${GREEN}✓${NC} $desc"
    (( PASS++ ))
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
    (( PASS++ ))
  else
    echo -e "  ${RED}✗${NC} $desc: file not found: $path"
    (( FAIL++ ))
    ERRORS+=("$desc")
  fi
}

assert_no_literal_ansi() {
  local desc="$1" text="$2"
  if echo "$text" | grep -qF '\033'; then
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Output contains literal \\\\033 — ANSI not rendered as ESC bytes"
    (( FAIL++ )); ERRORS+=("$desc")
  else
    echo -e "  ${GREEN}✓${NC} $desc"
    (( PASS++ ))
  fi
}

assert_matches() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -qE "$needle" <<< "$haystack"; then
    echo -e "  ${GREEN}✓${NC} $desc"
    (( PASS++ ))
  else
    echo -e "  ${RED}✗${NC} $desc"
    echo -e "    Expected to match: ${GREEN}$needle${NC}"
    echo -e "    Got (first 200 chars): ${RED}${haystack:0:200}${NC}"
    (( FAIL++ ))
    ERRORS+=("$desc")
  fi
}

# Export for test files
export CLAUDII_HOME TESTS_DIR
export -f assert_eq assert_contains assert_not_contains assert_exit_code assert_file_exists
export -f assert_no_literal_ansi assert_matches

# Run tests
if [[ -n "${1:-}" ]]; then
  # Run specific test file
  echo -e "${YELLOW}Running: $1${NC}"
  source "$1"
else
  # Run all test files
  for test_file in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue
    echo ""
    echo -e "${YELLOW}$(basename "$test_file")${NC}"
    source "$test_file"
  done
fi

# Summary
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

exit $FAIL
