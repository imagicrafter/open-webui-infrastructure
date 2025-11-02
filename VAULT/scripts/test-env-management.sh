#!/bin/bash

# Test Script for Environment Variable Management
# This script tests the core functionality without requiring a running container

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "╔════════════════════════════════════════╗"
echo "║  Env Management Test Suite             ║"
echo "╚════════════════════════════════════════╝"
echo

# Source the functions
if [ ! -f "${SCRIPT_DIR}/env-manager-functions.sh" ]; then
    echo "❌ Error: env-manager-functions.sh not found"
    exit 1
fi

source "${SCRIPT_DIR}/env-manager-functions.sh"

# Test container name
TEST_CONTAINER="openwebui-test-$(date +%s)"
TEST_ENV_FILE=$(get_custom_env_file "$TEST_CONTAINER")

echo "Test Configuration:"
echo "  Container: $TEST_CONTAINER"
echo "  Env File:  $TEST_ENV_FILE"
echo

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for tests
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "Testing: $test_name ... "

    if eval "$test_command"; then
        echo "✅ PASS"
        ((TESTS_PASSED++))
        return 0
    else
        echo "❌ FAIL"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Basic Functions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 1: Ensure directory
run_test "Create custom env directory" "ensure_custom_env_dir"

# Test 2: File doesn't exist initially
run_test "Custom env file doesn't exist (initial)" "! has_custom_env_file '$TEST_CONTAINER'"

# Test 3: Create env file
run_test "Create custom env file" "create_custom_env_file '$TEST_CONTAINER'"

# Test 4: File exists after creation
run_test "Custom env file exists after creation" "has_custom_env_file '$TEST_CONTAINER'"

# Test 5: File has correct permissions
run_test "Env file has secure permissions (600)" "[ \$(stat -f '%A' '$TEST_ENV_FILE' 2>/dev/null || stat -c '%a' '$TEST_ENV_FILE' 2>/dev/null) = '600' ]"

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Variable Management"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 6: Initial count is 0
run_test "Initial variable count is 0" "[ \$(count_custom_vars '$TEST_CONTAINER') -eq 0 ]"

# Test 7: Set a variable
run_test "Set variable TEST_VAR_1" "set_env_var '$TEST_CONTAINER' 'TEST_VAR_1' 'test_value_1'"

# Test 8: Get variable value
run_test "Get variable value" "[ \$(get_env_var '$TEST_CONTAINER' 'TEST_VAR_1') = 'test_value_1' ]"

# Test 9: Count is now 1
run_test "Variable count is 1" "[ \$(count_custom_vars '$TEST_CONTAINER') -eq 1 ]"

# Test 10: Set another variable
run_test "Set variable TEST_VAR_2" "set_env_var '$TEST_CONTAINER' 'TEST_VAR_2' 'test_value_2'"

# Test 11: Count is now 2
run_test "Variable count is 2" "[ \$(count_custom_vars '$TEST_CONTAINER') -eq 2 ]"

# Test 12: Update existing variable
run_test "Update variable TEST_VAR_1" "set_env_var '$TEST_CONTAINER' 'TEST_VAR_1' 'updated_value_1'"

# Test 13: Verify update
run_test "Verify updated value" "[ \$(get_env_var '$TEST_CONTAINER' 'TEST_VAR_1') = 'updated_value_1' ]"

# Test 14: Count is still 2 (no duplicate)
run_test "Variable count still 2 after update" "[ \$(count_custom_vars '$TEST_CONTAINER') -eq 2 ]"

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: List and Delete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 15: List variable names
echo -n "Testing: List variable names ... "
VAR_LIST=$(list_env_var_names "$TEST_CONTAINER")
if echo "$VAR_LIST" | grep -q "TEST_VAR_1" && echo "$VAR_LIST" | grep -q "TEST_VAR_2"; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
else
    echo "❌ FAIL"
    ((TESTS_FAILED++))
fi

# Test 16: Delete a variable
run_test "Delete variable TEST_VAR_1" "delete_env_var '$TEST_CONTAINER' 'TEST_VAR_1'"

# Test 17: Count is now 1
run_test "Variable count is 1 after delete" "[ \$(count_custom_vars '$TEST_CONTAINER') -eq 1 ]"

# Test 18: Deleted variable returns empty
run_test "Deleted variable returns empty" "[ -z \$(get_env_var '$TEST_CONTAINER' 'TEST_VAR_1') ]"

# Test 19: Remaining variable still exists
run_test "Remaining variable still exists" "[ \$(get_env_var '$TEST_CONTAINER' 'TEST_VAR_2') = 'test_value_2' ]"

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 20: Valid file passes validation
echo -n "Testing: Valid file passes validation ... "
if validate_env_file "$TEST_CONTAINER" > /dev/null 2>&1; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
else
    echo "❌ FAIL"
    ((TESTS_FAILED++))
fi

# Test 21: Invalid format detected
echo -n "Testing: Invalid format detected ... "
# Add invalid line
echo "INVALID LINE WITHOUT EQUALS" >> "$TEST_ENV_FILE"
if ! validate_env_file "$TEST_CONTAINER" > /dev/null 2>&1; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
else
    echo "❌ FAIL"
    ((TESTS_FAILED++))
fi

# Remove invalid line
sed -i.bak '/INVALID LINE/d' "$TEST_ENV_FILE"
rm -f "${TEST_ENV_FILE}.bak"

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Special Cases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 22: Variable with special characters
run_test "Set variable with URL value" "set_env_var '$TEST_CONTAINER' 'API_ENDPOINT' 'https://api.example.com/v1?key=abc123'"

# Test 23: Retrieve special character value
echo -n "Testing: Retrieve URL value correctly ... "
VALUE=$(get_env_var "$TEST_CONTAINER" "API_ENDPOINT")
if [ "$VALUE" = "https://api.example.com/v1?key=abc123" ]; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
else
    echo "❌ FAIL (got: $VALUE)"
    ((TESTS_FAILED++))
fi

# Test 24: Variable with spaces in value
run_test "Set variable with spaces" "set_env_var '$TEST_CONTAINER' 'DISPLAY_NAME' 'My Test Application'"

# Test 25: Retrieve space value
echo -n "Testing: Retrieve value with spaces ... "
VALUE=$(get_env_var "$TEST_CONTAINER" "DISPLAY_NAME")
if [ "$VALUE" = "My Test Application" ]; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
else
    echo "❌ FAIL (got: $VALUE)"
    ((TESTS_FAILED++))
fi

# Test 26: Empty value (should work)
run_test "Set variable with empty value" "set_env_var '$TEST_CONTAINER' 'EMPTY_VAR' ''"

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: File Content Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

echo "Current env file content:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$TEST_ENV_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 27: File contains expected variables
echo -n "Testing: File contains all expected variables ... "
EXPECTED_COUNT=4  # TEST_VAR_2, API_ENDPOINT, DISPLAY_NAME, EMPTY_VAR
ACTUAL_COUNT=$(count_custom_vars "$TEST_CONTAINER")
if [ "$ACTUAL_COUNT" -eq "$EXPECTED_COUNT" ]; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
else
    echo "❌ FAIL (expected: $EXPECTED_COUNT, got: $ACTUAL_COUNT)"
    ((TESTS_FAILED++))
fi

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Cleanup test files
echo -n "Removing test env file ... "
rm -f "$TEST_ENV_FILE"
if [ ! -f "$TEST_ENV_FILE" ]; then
    echo "✅ DONE"
else
    echo "⚠️  Could not remove file"
fi

echo

echo "╔════════════════════════════════════════╗"
echo "║         Test Results Summary           ║"
echo "╚════════════════════════════════════════╝"
echo

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo "Tests Run:    $TOTAL_TESTS"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ ALL TESTS PASSED!"
    echo
    echo "The env management system is working correctly."
    echo "You can now use it with client-manager.sh"
    exit 0
else
    echo "❌ SOME TESTS FAILED"
    echo
    echo "Please review the failures above."
    echo "Check file permissions and dependencies."
    exit 1
fi
