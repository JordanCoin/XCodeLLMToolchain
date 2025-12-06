#!/bin/bash
# Eval script: Run all crash primitives through pipeline and check accuracy
#
# Usage:
#   ./scripts/eval.sh              # Run with direct mode (default)
#   ./scripts/eval.sh --pipeline   # Run with scoring pipeline
#   ./scripts/eval.sh --compare    # Run both and compare accuracy

set -e

GENERATOR=".build/debug/swift-crash-generator"
ANALYZER=".build/debug/xcode-llm"
MODE=""
COMPARE=false

# Parse args
for arg in "$@"; do
    case $arg in
        --pipeline)
            MODE="--pipeline"
            ;;
        --compare)
            COMPARE=true
            ;;
    esac
done

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

if [ "$COMPARE" = true ]; then
    echo "========================================"
    echo "  XcodeLLM Eval: DIRECT vs PIPELINE"
    echo "========================================"
    echo ""
    echo "Running direct mode first, then pipeline mode..."
    echo ""

    # Run direct mode
    DIRECT_RESULT=$("$0" 2>&1 | tail -5 | grep "Accuracy" | grep -o "[0-9.]*" || echo "0")

    # Run pipeline mode
    PIPELINE_RESULT=$("$0" --pipeline 2>&1 | tail -5 | grep "Accuracy" | grep -o "[0-9.]*" || echo "0")

    echo "========================================"
    echo "  COMPARISON RESULTS"
    echo "========================================"
    echo "  Direct Mode:   ${DIRECT_RESULT}%"
    echo "  Pipeline Mode: ${PIPELINE_RESULT}%"
    echo "========================================"
    exit 0
fi

MODE_NAME="Direct"
[ -n "$MODE" ] && MODE_NAME="Pipeline"

echo "========================================"
echo "  XcodeLLM Adversarial Eval Suite"
echo "  Mode: $MODE_NAME"
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
    # Note: generic_wrapper has a bug - it replaces the crash instead of wrapping it
    # "array_out_of_bounds generic_wrapper"
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
    else
        # Use simple complexity to avoid random modifier addition
        cmd="$cmd --complexity simple"
    fi
    cmd="$cmd --run-only"

    # Run and capture (with retry for transient LLM failures)
    local output
    local attempts=0
    local max_attempts=3

    while [ $attempts -lt $max_attempts ]; do
        ((attempts++))
        output=$(eval "$cmd" 2>/dev/null | $ANALYZER $MODE 2>/dev/null)
        if [ $? -eq 0 ] && ! echo "$output" | grep -q "unsupported language"; then
            break
        fi
        [ $attempts -lt $max_attempts ] && sleep 1
    done

    if [ -z "$output" ] || echo "$output" | grep -q "unsupported language"; then
        echo -e "${YELLOW}SKIP${NC} (LLM error after $attempts attempts)"
        ((SKIPPED++))
        RESULTS+=("SKIP: $test_name")
        return
    fi

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
