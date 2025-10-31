#!/bin/bash
# =============================================================================
# State Management System Integration Test
# =============================================================================
# 
# Tests the comprehensive state management system including:
# - State manager functionality
# - Lock manager operations  
# - Error recovery capabilities
# - Hook integration
#
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_LOG="$SCRIPT_DIR/test-state-management.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging function
test_log() {
    local level="$1"
    local message="$2"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [$level] $message" >> "$TEST_LOG"
    
    case "$level" in
        "PASS") echo -e "${GREEN}✓ $message${NC}" ;;
        "FAIL") echo -e "${RED}✗ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ $message${NC}" ;;
        *) echo "$message" ;;
    esac
}

# Test execution function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_RUN++))
    test_log "INFO" "Running test: $test_name"
    
    if eval "$test_command" 2>>"$TEST_LOG"; then
        ((TESTS_PASSED++))
        test_log "PASS" "$test_name"
        return 0
    else
        ((TESTS_FAILED++))
        test_log "FAIL" "$test_name"
        return 1
    fi
}

# Test state manager initialization
test_state_manager_init() {
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    
    if [ ! -f "$lib_path" ]; then
        return 1
    fi
    
    # Test initialization
    if "$lib_path" init >/dev/null 2>&1; then
        # Check if state file was created
        [ -f "$SCRIPT_DIR/.workflow-state.json" ]
    else
        return 1
    fi
}

# Test state manager validation
test_state_manager_validation() {
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    
    # Test validation of existing state
    "$lib_path" validate >/dev/null 2>&1
}

# Test state manager read/write
test_state_manager_read_write() {
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    
    # Read current state
    local current_state
    current_state=$("$lib_path" read 2>/dev/null)
    
    # Verify it's valid JSON
    if echo "$current_state" | jq empty 2>/dev/null; then
        # Check required fields
        echo "$current_state" | jq -e '.phase' >/dev/null 2>&1 && \
        echo "$current_state" | jq -e '.completedTasks' >/dev/null 2>&1 && \
        echo "$current_state" | jq -e '.signals' >/dev/null 2>&1
    else
        return 1
    fi
}

# Test state manager backup
test_state_manager_backup() {
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    
    # Create backup
    "$lib_path" backup "test-backup" >/dev/null 2>&1
    
    # Check if backup was created
    find "$SCRIPT_DIR/.state-backups" -name "*test-backup*.json" -type f | head -1 | grep -q "test-backup"
}

# Test lock manager
test_lock_manager() {
    local lib_path="$SCRIPT_DIR/lib/lock-manager.sh"
    
    if [ ! -f "$lib_path" ]; then
        return 1
    fi
    
    # Test lock acquisition and release
    if "$lib_path" acquire "test-lock" 5 >/dev/null 2>&1; then
        # Check lock status
        local status
        status=$("$lib_path" check "test-lock" 2>/dev/null || echo "unlocked")
        
        if [[ "$status" == "locked:"* ]]; then
            # Release lock
            "$lib_path" release "test-lock" >/dev/null 2>&1
        else
            return 1
        fi
    else
        return 1
    fi
}

# Test error recovery system
test_error_recovery() {
    local lib_path="$SCRIPT_DIR/lib/error-recovery.sh"
    
    if [ ! -f "$lib_path" ]; then
        return 1
    fi
    
    # Test checkpoint creation
    if "$lib_path" checkpoint "test-operation" "test-phase" '{"test": true}' >/dev/null 2>&1; then
        # Check if checkpoint was created
        find "$SCRIPT_DIR/.checkpoints" -name "checkpoint-*test-operation*" -type d | grep -q "test-operation"
    else
        return 1
    fi
}

# Test hook integration
test_hook_integration() {
    local hook_path="$SCRIPT_DIR/hooks/skill-activation-prompt.sh"
    
    if [ ! -f "$hook_path" ]; then
        return 1
    fi
    
    # Test hook with sample input
    local test_input='{"message": "test pipeline status", "contextFiles": []}'
    
    # Run hook and check for errors
    echo "$test_input" | timeout 30s "$hook_path" >/dev/null 2>&1
}

# Test concurrent access
test_concurrent_access() {
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    
    # Start multiple processes trying to access state
    local pids=()
    
    for i in {1..3}; do
        (
            for j in {1..5}; do
                "$lib_path" read >/dev/null 2>&1
                sleep 0.1
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all processes to complete
    local all_passed=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_passed=false
        fi
    done
    
    $all_passed
}

# Test system recovery from corruption
test_corruption_recovery() {
    local state_file="$SCRIPT_DIR/.workflow-state.json"
    local backup_file="${state_file}.test-backup"
    
    # Backup current state
    cp "$state_file" "$backup_file" 2>/dev/null || true
    
    # Corrupt state file
    echo "invalid json content" > "$state_file"
    
    # Test recovery
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    
    if "$lib_path" init >/dev/null 2>&1; then
        # Restore original state
        mv "$backup_file" "$state_file" 2>/dev/null || true
        return 0
    else
        # Restore original state
        mv "$backup_file" "$state_file" 2>/dev/null || true
        return 1
    fi
}

# Performance test
test_performance() {
    local lib_path="$SCRIPT_DIR/lib/state-manager.sh"
    local start_time
    local end_time
    
    start_time=$(date +%s.%N)
    
    # Perform multiple operations
    for i in {1..10}; do
        "$lib_path" read >/dev/null 2>&1 || return 1
    done
    
    end_time=$(date +%s.%N)
    
    # Check if operations completed within reasonable time (5 seconds)
    local duration
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "5.1")
    
    [ "$(echo "$duration < 5.0" | bc 2>/dev/null || echo 0)" = "1" ]
}

# Cleanup function
cleanup() {
    test_log "INFO" "Cleaning up test artifacts"
    
    # Remove test locks
    find "$SCRIPT_DIR/.locks" -name "*test*" -delete 2>/dev/null || true
    
    # Remove test checkpoints
    find "$SCRIPT_DIR/.checkpoints" -name "*test*" -exec rm -rf {} + 2>/dev/null || true
    
    # Remove test backups
    find "$SCRIPT_DIR/.state-backups" -name "*test*" -delete 2>/dev/null || true
}

# Main test suite
main() {
    echo "================================================================================"
    echo "State Management System Integration Test"
    echo "================================================================================"
    echo ""
    
    # Clear log file
    > "$TEST_LOG"
    
    test_log "INFO" "Starting state management system tests"
    
    # Run all tests
    run_test "State Manager Initialization" "test_state_manager_init"
    run_test "State Manager Validation" "test_state_manager_validation" 
    run_test "State Manager Read/Write" "test_state_manager_read_write"
    run_test "State Manager Backup" "test_state_manager_backup"
    run_test "Lock Manager Operations" "test_lock_manager"
    run_test "Error Recovery System" "test_error_recovery"
    run_test "Hook Integration" "test_hook_integration"
    run_test "Concurrent Access" "test_concurrent_access"
    run_test "Corruption Recovery" "test_corruption_recovery"
    run_test "Performance Test" "test_performance"
    
    # Cleanup
    cleanup
    
    # Report results
    echo ""
    echo "================================================================================"
    echo "Test Results"
    echo "================================================================================"
    echo "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed! ✓${NC}"
        echo ""
        echo "State management system is ready for production use."
    else
        echo -e "\n${RED}Some tests failed! ✗${NC}"
        echo ""
        echo "Please review the test log: $TEST_LOG"
    fi
    
    echo ""
    echo "Log file: $TEST_LOG"
    
    # Show system status
    echo ""
    echo "================================================================================"
    echo "System Status"
    echo "================================================================================"
    
    if [ -f "$SCRIPT_DIR/lib/state-manager.sh" ]; then
        "$SCRIPT_DIR/lib/state-manager.sh" status
    fi
    
    exit $TESTS_FAILED
}

# Run main function
main "$@"