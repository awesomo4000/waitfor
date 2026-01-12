#!/bin/bash
#
# Integration tests for waitfor
#
# Usage: ./tests/test_waitfor.sh [path-to-waitfor-binary]
#

set -e

WAITFOR="${1:-./zig-out/bin/waitfor}"
TEST_DIR="/tmp/waitfor-test-$$"
PASSED=0
FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

setup() {
    mkdir -p "$TEST_DIR"
}

cleanup() {
    rm -rf "$TEST_DIR"
}

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

# Test 1: Existing file returns immediately with exit 0
test_existing_file() {
    local name="existing file returns 0"
    touch "$TEST_DIR/exists"

    if "$WAITFOR" "$TEST_DIR/exists"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 2: Non-existent file with timeout returns exit 1
test_nonexistent_timeout() {
    local name="non-existent file times out with exit 1"

    if "$WAITFOR" -t 0.3 "$TEST_DIR/does-not-exist"; then
        fail "$name (should have timed out)"
    else
        local code=$?
        if [ "$code" -eq 1 ]; then
            pass "$name"
        else
            fail "$name (expected exit 1, got $code)"
        fi
    fi
}

# Test 3: Wait for file to appear (main use case!)
test_wait_for_file_appear() {
    local name="wait for file to appear"
    local testfile="$TEST_DIR/will-appear"

    # Start waitfor in background with 5 second timeout
    "$WAITFOR" -t 5 "$testfile" &
    local pid=$!

    # Wait a moment, then create the file
    sleep 0.3
    touch "$testfile"

    # Wait for waitfor to exit
    if wait $pid; then
        pass "$name"
    else
        local code=$?
        fail "$name (exit code: $code)"
    fi
}

# Test 4: -d flag with non-existent file returns immediately
test_deletion_nonexistent() {
    local name="-d flag with non-existent file returns 0"

    if "$WAITFOR" -d "$TEST_DIR/never-existed"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 5: -d flag with existing file times out
test_deletion_existing_timeout() {
    local name="-d flag with existing file times out"
    touch "$TEST_DIR/exists-for-deletion"

    if "$WAITFOR" -d -t 0.3 "$TEST_DIR/exists-for-deletion"; then
        fail "$name (should have timed out)"
    else
        local code=$?
        if [ "$code" -eq 1 ]; then
            pass "$name"
        else
            fail "$name (expected exit 1, got $code)"
        fi
    fi
}

# Test 6: Wait for file to be deleted (opposite of test 3)
test_wait_for_file_deletion() {
    local name="wait for file to be deleted"
    local testfile="$TEST_DIR/will-disappear"
    touch "$testfile"

    # Start waitfor -d in background
    "$WAITFOR" -d -t 5 "$testfile" &
    local pid=$!

    # Wait a moment, then delete the file
    sleep 0.3
    rm "$testfile"

    # Wait for waitfor to exit
    if wait $pid; then
        pass "$name"
    else
        local code=$?
        fail "$name (exit code: $code)"
    fi
}

# Test 7: Multiple paths - all must exist
test_multiple_paths_all_exist() {
    local name="multiple paths - all exist"
    touch "$TEST_DIR/file1"
    touch "$TEST_DIR/file2"
    touch "$TEST_DIR/file3"

    if "$WAITFOR" "$TEST_DIR/file1" "$TEST_DIR/file2" "$TEST_DIR/file3"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 8: Multiple paths - one missing times out
test_multiple_paths_one_missing() {
    local name="multiple paths - one missing times out"
    touch "$TEST_DIR/exists1"
    touch "$TEST_DIR/exists2"
    # Don't create exists3

    if "$WAITFOR" -t 0.3 "$TEST_DIR/exists1" "$TEST_DIR/exists2" "$TEST_DIR/exists3"; then
        fail "$name (should have timed out)"
    else
        local code=$?
        if [ "$code" -eq 1 ]; then
            pass "$name"
        else
            fail "$name (expected exit 1, got $code)"
        fi
    fi
}

# Test 9: Relative path
test_relative_path() {
    local name="relative path works"
    local old_pwd=$(pwd)
    local abs_waitfor="$(cd "$(dirname "$WAITFOR")" && pwd)/$(basename "$WAITFOR")"
    cd "$TEST_DIR"
    touch "relative-file"

    if "$abs_waitfor" "relative-file"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi

    cd "$old_pwd"
}

# Test 10: Directory (not just files)
test_directory() {
    local name="works with directories"
    mkdir -p "$TEST_DIR/subdir"

    if "$WAITFOR" "$TEST_DIR/subdir"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 11: Help flag
test_help_flag() {
    local name="--help returns 0"

    if "$WAITFOR" --help >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 12: No arguments returns error
test_no_arguments() {
    local name="no arguments returns error"

    if "$WAITFOR" >/dev/null 2>&1; then
        fail "$name (should have failed)"
    else
        local code=$?
        if [ "$code" -eq 3 ]; then
            pass "$name"
        else
            fail "$name (expected exit 3, got $code)"
        fi
    fi
}

# Test 13: -t 0 means wait forever (same as no -t)
test_explicit_infinite_timeout() {
    local name="-t 0 means wait forever"
    touch "$TEST_DIR/exists-for-t0"

    # With -t 0, should return immediately since file exists
    if "$WAITFOR" -t 0 "$TEST_DIR/exists-for-t0"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 14: Invalid option returns error
test_invalid_option() {
    local name="invalid option returns error"

    if "$WAITFOR" -x /tmp >/dev/null 2>&1; then
        fail "$name (should have failed)"
    else
        local code=$?
        if [ "$code" -eq 3 ]; then
            pass "$name"
        else
            fail "$name (expected exit 3, got $code)"
        fi
    fi
}

# Test 15: Invalid timeout value returns error
test_invalid_timeout_value() {
    local name="invalid timeout value returns error"

    if "$WAITFOR" -t abc /tmp >/dev/null 2>&1; then
        fail "$name (should have failed)"
    else
        local code=$?
        if [ "$code" -eq 3 ]; then
            pass "$name"
        else
            fail "$name (expected exit 3, got $code)"
        fi
    fi
}

# Test 16: -t followed by flag means wait forever (quick check)
test_missing_timeout_value() {
    local name="-t followed by -d means wait forever"

    # -t -d with non-existent file: -t means wait forever, -d means wait for deletion
    # File doesn't exist, so -d condition is already met, should exit 0 immediately
    if "$WAITFOR" -t -d "$TEST_DIR/t-flag-test"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 17: Decimal timeout works
test_decimal_timeout() {
    local name="decimal timeout works"

    # 0.2 seconds should be enough to timeout on non-existent file
    if "$WAITFOR" -t 0.2 "$TEST_DIR/decimal-test" 2>/dev/null; then
        fail "$name (should have timed out)"
    else
        local code=$?
        if [ "$code" -eq 1 ]; then
            pass "$name"
        else
            fail "$name (expected exit 1, got $code)"
        fi
    fi
}

# Test 18: Flag order -d -t works
test_flag_order_d_first() {
    local name="flag order -d -t works"

    # -d with non-existent file should return immediately
    if "$WAITFOR" -d -t 5 "$TEST_DIR/flag-order-1"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 19: Flag order -t -d works
test_flag_order_t_first() {
    local name="flag order -t -d works"

    # -d with non-existent file should return immediately
    if "$WAITFOR" -t 5 -d "$TEST_DIR/flag-order-2"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 20: Default (no -t) waits forever - use shell timeout to verify
test_wait_forever_default() {
    local name="default waits forever (no -t)"

    # Without -t, waitfor should wait forever for non-existent file
    # Use timeout to kill it after 0.5s - should exit 124 (timeout's exit code)
    if timeout 0.5 "$WAITFOR" "$TEST_DIR/forever-default" 2>/dev/null; then
        fail "$name (should have been killed by timeout)"
    else
        local code=$?
        if [ "$code" -eq 124 ]; then
            pass "$name"
        else
            fail "$name (expected timeout exit 124, got $code)"
        fi
    fi
}

# Test 21: -t 0 waits forever - use shell timeout to verify
test_wait_forever_t_zero() {
    local name="-t 0 waits forever"

    # -t 0 should mean wait forever
    if timeout 0.5 "$WAITFOR" -t 0 "$TEST_DIR/forever-t0" 2>/dev/null; then
        fail "$name (should have been killed by timeout)"
    else
        local code=$?
        if [ "$code" -eq 124 ]; then
            pass "$name"
        else
            fail "$name (expected timeout exit 124, got $code)"
        fi
    fi
}

# Test 22: -t alone (at end) waits forever - use shell timeout to verify
test_wait_forever_t_alone() {
    local name="-t at end waits forever"
    touch "$TEST_DIR/forever-t-alone"
    rm "$TEST_DIR/forever-t-alone"  # ensure it doesn't exist

    # -t at end of args should mean wait forever
    if timeout 0.5 "$WAITFOR" "$TEST_DIR/forever-t-alone" -t 2>/dev/null; then
        fail "$name (should have been killed by timeout)"
    else
        local code=$?
        if [ "$code" -eq 124 ]; then
            pass "$name"
        else
            fail "$name (expected timeout exit 124, got $code)"
        fi
    fi
}

# Test 23: Numeric filename (e.g., file named "123")
test_numeric_filename() {
    local name="numeric filename works"
    touch "$TEST_DIR/123"

    # "123" should be treated as a path, not a PID or timeout
    if "$WAITFOR" "$TEST_DIR/123"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 24: Numeric filename with explicit timeout
test_numeric_filename_with_timeout() {
    local name="numeric filename with timeout"
    touch "$TEST_DIR/456"

    # -t 1 sets timeout, "456" is the path
    if "$WAITFOR" -t 1 "$TEST_DIR/456"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Test 25: Empty path returns error
test_empty_path() {
    local name="empty path returns error"

    if "$WAITFOR" "" 2>/dev/null; then
        fail "$name (should have failed)"
    else
        local code=$?
        if [ "$code" -eq 3 ]; then
            pass "$name"
        else
            fail "$name (expected exit 3, got $code)"
        fi
    fi
}

# Test 26: Huge timeout treated as forever (no overflow panic)
test_huge_timeout() {
    local name="huge timeout treated as forever"

    # 1e999 should be treated as "wait forever", not panic
    # Use shell timeout to verify it waits
    if timeout 0.5 "$WAITFOR" -t 1e999 "$TEST_DIR/huge-timeout" 2>/dev/null; then
        fail "$name (should have been killed by timeout)"
    else
        local code=$?
        if [ "$code" -eq 124 ]; then
            pass "$name"
        else
            fail "$name (expected timeout 124, got $code - may have panicked)"
        fi
    fi
}

# Test 27: Double -d flag is idempotent
test_double_d_flag() {
    local name="double -d flag works"

    # -d -d should work same as single -d
    if "$WAITFOR" -d -d "$TEST_DIR/double-d-test"; then
        pass "$name"
    else
        fail "$name (exit code: $?)"
    fi
}

# Main
main() {
    echo "============================================"
    echo "waitfor integration tests"
    echo "Binary: $WAITFOR"
    echo "Test dir: $TEST_DIR"
    echo "============================================"
    echo ""

    # Check binary exists
    if [ ! -x "$WAITFOR" ]; then
        echo -e "${RED}ERROR${NC}: Binary not found or not executable: $WAITFOR"
        echo "Run 'zig build' first"
        exit 1
    fi

    setup
    trap cleanup EXIT

    test_existing_file
    test_nonexistent_timeout
    test_wait_for_file_appear
    test_deletion_nonexistent
    test_deletion_existing_timeout
    test_wait_for_file_deletion
    test_multiple_paths_all_exist
    test_multiple_paths_one_missing
    test_relative_path
    test_directory
    test_help_flag
    test_no_arguments
    test_explicit_infinite_timeout
    test_invalid_option
    test_invalid_timeout_value
    test_missing_timeout_value
    test_decimal_timeout
    test_flag_order_d_first
    test_flag_order_t_first
    test_wait_forever_default
    test_wait_forever_t_zero
    test_wait_forever_t_alone
    test_numeric_filename
    test_numeric_filename_with_timeout
    test_empty_path
    test_huge_timeout
    test_double_d_flag

    echo ""
    echo "============================================"
    echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
    echo "============================================"

    if [ "$FAILED" -gt 0 ]; then
        exit 1
    fi
}

main
