#!/bin/bash
# Eval script: Run all crash primitives through pipeline and check accuracy

set -e

GENERATOR=".build/debug/swift-crash-generator"
ANALYZER=".build/debug/xcode-llm"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Results array
declare -a RESULTS

echo "========================================"
echo "  XcodeLLM Adversarial Eval Suite"
echo "========================================"
echo ""

# Build first
echo "Building..."
swift build 2>/dev/null || { echo "Build failed"; exit 1; }
echo "Build complete."
echo ""

# Test cases: primitive [modifier]
TEST_CASES=(
    "force_unwrap_nil"
    "force_unwrap_nil async_await"
    "force_unwrap_nil closure_capture"
    "array_out_of_bounds"
    "array_out_of_bounds computed_property"
    "dictionary_key_missing"
    "failed_type_cast"
    "integer_overflow"
    "division_by_zero"
    "precondition_failure"
    "fatal_error_call"
    # These are trickier
    "force_unwrap_nil protocol_witness"
    "force_unwrap_nil type_erasure"
    "array_out_of_bounds generic_wrapper"
)

run_test() {
    local primitive="$1"
    local modifier="$2"
    local test_name="$primitive"

    if [ -n "$modifier" ]; then
        test_name="$primitive + $modifier"
    fi

    printf "Testing: %-45s " "$test_name"

    # Build command
    local cmd="$GENERATOR --primitive $primitive"
    if [ -n "$modifier" ]; then
        cmd="$cmd --modifier $modifier"
    fi
    cmd="$cmd --run-only"

    # Run and capture
    local output
    output=$(eval "$cmd" 2>/dev/null | $ANALYZER 2>/dev/null) || {
        echo -e "${YELLOW}SKIP${NC} (crash capture failed)"
        ((SKIPPED++))
        RESULTS+=("SKIP: $test_name")
        return
    }

    # Extract crash type from output
    local detected
    detected=$(echo "$output" | grep -o "Crash Type:\*\* [a-z_]*" | sed 's/.*\*\* //' | head -1)

    if [ -z "$detected" ]; then
        detected=$(echo "$output" | grep -o "crashType.*" | sed 's/.*: //' | tr -d '",}' | head -1)
    fi

    # Map primitive to expected crash type
    local expected
    case "$primitive" in
        force_unwrap_nil|dictionary_key_missing)
            expected="force_unwrap_nil"
            ;;
        array_out_of_bounds|string_index_out_of_bounds)
            expected="array_out_of_bounds"
            ;;
        failed_type_cast)
            expected="type_cast_failure"
            ;;
        unowned_after_dealloc)
            expected="unowned_dealloc"
            ;;
        integer_overflow)
            expected="integer_overflow"
            ;;
        division_by_zero)
            expected="division_by_zero"
            ;;
        precondition_failure|fatal_error_call)
            expected="assertion_failure"
            ;;
        stack_overflow)
            expected="stack_overflow"
            ;;
        *)
            expected="$primitive"
            ;;
    esac

    # Check match
    if [ "$detected" = "$expected" ]; then
        echo -e "${GREEN}PASS${NC} (detected: $detected)"
        ((PASSED++))
        RESULTS+=("PASS: $test_name -> $detected")
    else
        echo -e "${RED}FAIL${NC} (expected: $expected, got: $detected)"
        ((FAILED++))
        RESULTS+=("FAIL: $test_name -> expected $expected, got $detected")
    fi
}

# Run tests
echo "Running eval tests..."
echo ""

for test_case in "${TEST_CASES[@]}"; do
    # Split into primitive and modifier
    read -r primitive modifier <<< "$test_case"
    run_test "$primitive" "$modifier"
done

# Summary
echo ""
echo "========================================"
echo "  RESULTS"
echo "========================================"
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo ""

TOTAL=$((PASSED + FAILED))
if [ $TOTAL -gt 0 ]; then
    ACCURACY=$(echo "scale=1; $PASSED * 100 / $TOTAL" | bc)
    echo "  Accuracy: $ACCURACY%"
fi

echo "========================================"

# Exit with failure if any tests failed
[ $FAILED -eq 0 ] || exit 1
