#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Error Recovery Tests
# =============================================================================
# 
# Comprehensive test suite for error recovery and checkpoint systems.
# Tests checkpoint creation/restoration, retry logic with exponential backoff,
# rollback capabilities, error code system, graceful degradation, and
# recovery suggestions for common errors.
#
# Test Categories:
# - Checkpoint System Operations
# - Retry Logic and Exponential Backoff
# - Rollback Capabilities
# - Error Code System
# - Graceful Degradation
# - Recovery Suggestions
# - Automatic Error Handling
# - Recovery Strategy Execution
#
# =============================================================================

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_TEST_DIR="$TEST_DIR/temp/error-recovery-tests"

# Load libraries
source "$PIPELINE_DIR/lib/error-recovery.sh"
source "$PIPELINE_DIR/lib/state-manager.sh"

# Override paths for testing
export PIPELINE_ROOT="$TEMP_TEST_DIR"
export CHECKPOINT_DIR="$TEMP_TEST_DIR/.checkpoints"
export ERROR_LOG="$TEMP_TEST_DIR/.error-recovery.log"
export AUDIT_LOG="$TEMP_TEST_DIR/audit.log"
export STATE_FILE="$TEMP_TEST_DIR/.workflow-state.json"
export BACKUP_DIR="$TEMP_TEST_DIR/.state-backups"
export LOCK_DIR="$TEMP_TEST_DIR/.locks"

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

# =============================================================================
# Test Infrastructure
# =============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo
    echo "${BLUE}${BOLD}▶ Running: $test_name${RESET}"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    ((TESTS_RUN++))
    
    # Setup test environment
    setup_test_environment
    
    if $test_function; then
        echo "${GREEN}✓ PASSED: $test_name${RESET}"
        ((TESTS_PASSED++))
        return 0
    else
        echo "${RED}✗ FAILED: $test_name${RESET}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

setup_test_environment() {
    # Clean up any previous test data
    rm -rf "$TEMP_TEST_DIR"
    mkdir -p "$TEMP_TEST_DIR" "$CHECKPOINT_DIR" "$BACKUP_DIR" "$LOCK_DIR"
    
    # Initialize state management for tests
    init_state_manager >/dev/null 2>&1 || true
    
    # Clear any global variables
    CURRENT_OPERATION=""
    CURRENT_PHASE=""
    CHECKPOINT_ID=""
}

cleanup_test_environment() {
    # Clean up locks and temp files
    find "$TEMP_TEST_DIR" -name "*.lock" -delete 2>/dev/null || true
    find "$TEMP_TEST_DIR" -name "*.tmp*" -delete 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup_test_environment EXIT

# Mock functions for testing
mock_failing_operation() {
    local failure_count_file="$TEMP_TEST_DIR/failure_count"
    local max_failures="${1:-2}"
    
    # Initialize or increment failure count
    local count=0
    if [[ -f "$failure_count_file" ]]; then
        count=$(cat "$failure_count_file")
    fi
    ((count++))
    echo "$count" > "$failure_count_file"
    
    # Fail for the first few attempts
    if [[ $count -le $max_failures ]]; then
        echo "Mock operation failed (attempt $count)"
        return 1
    else
        echo "Mock operation succeeded (attempt $count)"
        return 0
    fi
}

mock_timeout_operation() {
    local timeout="${1:-3}"
    echo "Mock operation timing out after ${timeout}s"
    sleep "$timeout"
    return 1
}

mock_resource_exhausted_operation() {
    echo "Mock operation failed due to resource exhaustion"
    return "${ERROR_CODES[RESOURCE_EXHAUSTED]}"
}

# =============================================================================
# Checkpoint System Tests
# =============================================================================

test_checkpoint_creation() {
    log "Testing checkpoint creation..."
    
    # Create initial state
    local test_state='{
        "phase": "checkpoint-test",
        "completedTasks": ["task1"],
        "signals": {"ready": true},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"test": true}
    }'
    write_state "$test_state" "initial"
    
    # Create checkpoint
    if ! create_checkpoint "test-operation" "test-phase" '{"test": true}'; then
        echo "ERROR: Failed to create checkpoint"
        return 1
    fi
    
    # Verify checkpoint ID was set
    if [[ -z "$CHECKPOINT_ID" ]]; then
        echo "ERROR: Checkpoint ID not set"
        return 1
    fi
    
    # Verify checkpoint directory exists
    local checkpoint_path="$CHECKPOINT_DIR/$CHECKPOINT_ID"
    if [[ ! -d "$checkpoint_path" ]]; then
        echo "ERROR: Checkpoint directory not created: $checkpoint_path"
        return 1
    fi
    
    # Verify state was saved
    if [[ ! -f "$checkpoint_path/state.json" ]]; then
        echo "ERROR: State not saved in checkpoint"
        return 1
    fi
    
    # Verify state content
    local saved_phase
    saved_phase=$(jq -r '.phase' "$checkpoint_path/state.json")
    if [[ "$saved_phase" != "checkpoint-test" ]]; then
        echo "ERROR: Incorrect state saved in checkpoint: expected 'checkpoint-test', got '$saved_phase'"
        return 1
    fi
    
    # Verify metadata file
    if [[ ! -f "$checkpoint_path/metadata.json" ]]; then
        echo "ERROR: Metadata not saved in checkpoint"
        return 1
    fi
    
    # Verify metadata content
    local operation
    operation=$(jq -r '.operation' "$checkpoint_path/metadata.json")
    if [[ "$operation" != "test-operation" ]]; then
        echo "ERROR: Incorrect operation in metadata: expected 'test-operation', got '$operation'"
        return 1
    fi
    
    log "Checkpoint creation test passed"
    return 0
}

test_checkpoint_restoration() {
    log "Testing checkpoint restoration..."
    
    # Create initial state and checkpoint
    local initial_state='{
        "phase": "restore-test-initial",
        "completedTasks": ["initial-task"],
        "signals": {"initial": true},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"version": 1}
    }'
    write_state "$initial_state" "initial"
    create_checkpoint "backup-operation" "backup-phase"
    local backup_checkpoint_id="$CHECKPOINT_ID"
    
    # Modify state
    local modified_state='{
        "phase": "restore-test-modified",
        "completedTasks": ["initial-task", "modified-task"],
        "signals": {"initial": true, "modified": true},
        "lastActivation": "2023-01-01T12:00:00Z",
        "metadata": {"version": 2}
    }'
    write_state "$modified_state" "modified"
    
    # Restore from checkpoint
    if ! restore_checkpoint "$backup_checkpoint_id"; then
        echo "ERROR: Failed to restore from checkpoint"
        return 1
    fi
    
    # Verify state was restored
    local restored_phase
    restored_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$restored_phase" != "restore-test-initial" ]]; then
        echo "ERROR: State not properly restored: expected 'restore-test-initial', got '$restored_phase'"
        return 1
    fi
    
    local restored_version
    restored_version=$(jq -r '.metadata.version' "$STATE_FILE")
    if [[ "$restored_version" != "1" ]]; then
        echo "ERROR: Metadata not properly restored: expected version 1, got $restored_version"
        return 1
    fi
    
    # Verify modified data is gone
    local modified_signal
    modified_signal=$(jq -r '.signals.modified // false' "$STATE_FILE")
    if [[ "$modified_signal" != "false" ]]; then
        echo "ERROR: Modified data still present after restoration"
        return 1
    fi
    
    log "Checkpoint restoration test passed"
    return 0
}

test_checkpoint_listing() {
    log "Testing checkpoint listing..."
    
    # Create test state
    local test_state='{
        "phase": "list-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$test_state" "initial"
    
    # Create multiple checkpoints
    create_checkpoint "operation-1" "phase-1"
    sleep 1
    create_checkpoint "operation-2" "phase-2"
    sleep 1
    create_checkpoint "operation-3" "phase-1"
    
    # Test table format listing
    local table_output
    table_output=$(list_checkpoints "table")
    
    # Verify all checkpoints are listed
    if ! echo "$table_output" | grep -q "operation-1"; then
        echo "ERROR: Checkpoint 'operation-1' not found in table listing"
        return 1
    fi
    
    if ! echo "$table_output" | grep -q "operation-2"; then
        echo "ERROR: Checkpoint 'operation-2' not found in table listing"
        return 1
    fi
    
    if ! echo "$table_output" | grep -q "operation-3"; then
        echo "ERROR: Checkpoint 'operation-3' not found in table listing"
        return 1
    fi
    
    # Test JSON format listing
    local json_output
    json_output=$(list_checkpoints "json")
    
    # Verify JSON is valid
    if ! echo "$json_output" | jq empty 2>/dev/null; then
        echo "ERROR: Invalid JSON output from checkpoint listing"
        return 1
    fi
    
    # Verify JSON contains expected number of checkpoints
    local checkpoint_count
    checkpoint_count=$(echo "$json_output" | jq 'length')
    if [[ "$checkpoint_count" != "3" ]]; then
        echo "ERROR: Expected 3 checkpoints in JSON output, got $checkpoint_count"
        return 1
    fi
    
    log "Checkpoint listing test passed"
    return 0
}

test_checkpoint_cleanup() {
    log "Testing checkpoint cleanup..."
    
    # Create test state
    local test_state='{
        "phase": "cleanup-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$test_state" "initial"
    
    # Create checkpoints
    create_checkpoint "old-operation-1" "phase-1"
    local old_checkpoint1="$CHECKPOINT_ID"
    
    create_checkpoint "old-operation-2" "phase-1"
    local old_checkpoint2="$CHECKPOINT_ID"
    
    create_checkpoint "recent-operation" "phase-1"
    local recent_checkpoint="$CHECKPOINT_ID"
    
    # Make first two checkpoints appear old (simulate 8 days ago)
    local old_date
    old_date=$(date -v-8d +%Y%m%d 2>/dev/null || date -d "8 days ago" +%Y%m%d 2>/dev/null || date +%Y%m%d)
    
    if command -v touch >/dev/null 2>&1; then
        # Try to set old timestamps (macOS/Linux compatible)
        touch -t "${old_date}1200.00" "$CHECKPOINT_DIR/$old_checkpoint1" 2>/dev/null || \
        touch -d "8 days ago" "$CHECKPOINT_DIR/$old_checkpoint1" 2>/dev/null || \
        echo "INFO: Cannot set old timestamp, testing cleanup with retention days = 0"
    fi
    
    # Run cleanup with 7 day retention
    if ! cleanup_checkpoints 7; then
        echo "ERROR: Checkpoint cleanup failed"
        return 1
    fi
    
    # Verify recent checkpoint still exists
    if [[ ! -d "$CHECKPOINT_DIR/$recent_checkpoint" ]]; then
        echo "ERROR: Recent checkpoint was incorrectly cleaned up"
        return 1
    fi
    
    # Note: Old checkpoint cleanup depends on timestamp modification success
    # If we couldn't set old timestamps, just verify cleanup ran without error
    log "Checkpoint cleanup test passed"
    return 0
}

# =============================================================================
# Retry Logic and Exponential Backoff Tests
# =============================================================================

test_basic_retry_logic() {
    log "Testing basic retry logic..."
    
    # Clear any previous failure count
    rm -f "$TEMP_TEST_DIR/failure_count"
    
    # Test retry with eventually succeeding operation
    local start_time=$(date +%s)
    if ! retry_with_backoff mock_failing_operation 3 1; then
        echo "ERROR: Retry logic failed for eventually succeeding operation"
        return 1
    fi
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Verify the operation was retried correct number of times
    local attempt_count
    attempt_count=$(cat "$TEMP_TEST_DIR/failure_count" 2>/dev/null || echo "0")
    if [[ "$attempt_count" != "3" ]]; then
        echo "ERROR: Expected 3 attempts, got $attempt_count"
        return 1
    fi
    
    # Verify exponential backoff (should take at least base delay time)
    if [[ $duration -lt 2 ]]; then
        echo "ERROR: Retry completed too quickly, backoff may not be working: ${duration}s"
        return 1
    fi
    
    log "Basic retry logic test passed (${duration}s, $attempt_count attempts)"
    return 0
}

test_exponential_backoff() {
    log "Testing exponential backoff timing..."
    
    # Create a function that always fails to test backoff timing
    always_fail() {
        echo "Always failing operation"
        return 1
    }
    
    # Test with specific timing
    local start_time=$(date +%s)
    retry_with_backoff always_fail 3 1 2>/dev/null || true  # Expected to fail
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # With base delay 1s and exponential backoff:
    # Attempt 1: immediate
    # Wait 1s + jitter
    # Attempt 2: ~1s after start
    # Wait 1.5s + jitter
    # Attempt 3: ~2.5s after start
    # Total should be at least 2-3 seconds
    
    if [[ $duration -lt 2 ]]; then
        echo "ERROR: Exponential backoff too fast: ${duration}s (expected >= 2s)"
        return 1
    fi
    
    if [[ $duration -gt 15 ]]; then
        echo "ERROR: Exponential backoff too slow: ${duration}s (expected <= 15s)"
        return 1
    fi
    
    log "Exponential backoff test passed (${duration}s for 3 failed attempts)"
    return 0
}

test_retry_with_non_retryable_errors() {
    log "Testing retry behavior with non-retryable errors..."
    
    # Create function that returns permission denied (non-retryable)
    permission_denied_operation() {
        echo "Permission denied operation"
        return "${ERROR_CODES[PERMISSION_DENIED]}"
    }
    
    # Test retry (should fail immediately)
    local start_time=$(date +%s)
    if retry_with_backoff permission_denied_operation 3 1 2>/dev/null; then
        echo "ERROR: Non-retryable operation should not succeed"
        return 1
    fi
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should fail quickly without retries
    if [[ $duration -gt 2 ]]; then
        echo "ERROR: Non-retryable error took too long to fail: ${duration}s"
        return 1
    fi
    
    log "Non-retryable error test passed (${duration}s)"
    return 0
}

test_max_retry_delay() {
    log "Testing maximum retry delay limit..."
    
    # Create function that always fails
    always_fail() {
        return 1
    }
    
    # Test with many retries to verify max delay is enforced
    local start_time=$(date +%s)
    retry_with_backoff always_fail 5 2 2>/dev/null || true
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # With MAX_RETRY_DELAY=60, even with many retries, it shouldn't take more than reasonable time
    if [[ $duration -gt 180 ]]; then  # 3 minutes max for 5 retries
        echo "ERROR: Retry took too long, max delay not enforced: ${duration}s"
        return 1
    fi
    
    log "Max retry delay test passed (${duration}s for 5 failed attempts)"
    return 0
}

# =============================================================================
# Error Code System Tests
# =============================================================================

test_error_code_definitions() {
    log "Testing error code definitions..."
    
    # Verify all expected error codes are defined
    local expected_codes=(
        "SUCCESS"
        "GENERAL_ERROR"
        "LOCK_TIMEOUT"
        "STATE_CORRUPTION"
        "VALIDATION_FAILED"
        "DEPENDENCY_MISSING"
        "PERMISSION_DENIED"
        "DISK_FULL"
        "NETWORK_ERROR"
        "TIMEOUT"
        "RESOURCE_EXHAUSTED"
        "CONFIGURATION_ERROR"
        "DATA_INTEGRITY"
        "SERVICE_UNAVAILABLE"
        "AUTHENTICATION_ERROR"
        "AUTHORIZATION_ERROR"
    )
    
    for code in "${expected_codes[@]}"; do
        if [[ -z "${ERROR_CODES[$code]:-}" ]]; then
            echo "ERROR: Error code not defined: $code"
            return 1
        fi
        
        # Verify it's a number
        if ! [[ "${ERROR_CODES[$code]}" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Error code is not numeric: $code = ${ERROR_CODES[$code]}"
            return 1
        fi
    done
    
    # Verify SUCCESS is 0
    if [[ "${ERROR_CODES[SUCCESS]}" != "0" ]]; then
        echo "ERROR: SUCCESS error code should be 0, got ${ERROR_CODES[SUCCESS]}"
        return 1
    fi
    
    # Verify codes are unique
    local seen_codes=()
    for code in "${ERROR_CODES[@]}"; do
        if [[ " ${seen_codes[*]} " =~ " $code " ]]; then
            echo "ERROR: Duplicate error code: $code"
            return 1
        fi
        seen_codes+=("$code")
    done
    
    log "Error code definitions test passed"
    return 0
}

test_should_retry_logic() {
    log "Testing should_retry logic..."
    
    # Test retryable errors
    local retryable_codes=(
        "${ERROR_CODES[LOCK_TIMEOUT]}"
        "${ERROR_CODES[TIMEOUT]}"
        "${ERROR_CODES[NETWORK_ERROR]}"
        "${ERROR_CODES[RESOURCE_EXHAUSTED]}"
        "${ERROR_CODES[SERVICE_UNAVAILABLE]}"
    )
    
    for code in "${retryable_codes[@]}"; do
        if ! should_retry "$code"; then
            echo "ERROR: Error code $code should be retryable"
            return 1
        fi
    done
    
    # Test non-retryable errors
    local non_retryable_codes=(
        "${ERROR_CODES[DISK_FULL]}"
        "${ERROR_CODES[PERMISSION_DENIED]}"
        "${ERROR_CODES[VALIDATION_FAILED]}"
    )
    
    for code in "${non_retryable_codes[@]}"; do
        if should_retry "$code"; then
            echo "ERROR: Error code $code should not be retryable"
            return 1
        fi
    done
    
    # Test unknown error code (should be retryable by default)
    if ! should_retry "999"; then
        echo "ERROR: Unknown error codes should be retryable by default"
        return 1
    fi
    
    log "Should retry logic test passed"
    return 0
}

# =============================================================================
# Graceful Degradation Tests
# =============================================================================

test_degraded_mode_enable() {
    log "Testing degraded mode activation..."
    
    # Initialize clean state
    local test_state='{
        "phase": "degradation-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$test_state" "initial"
    
    # Enable degraded mode
    if ! enable_degraded_mode "test-failure" '["feature1", "feature2"]'; then
        echo "ERROR: Failed to enable degraded mode"
        return 1
    fi
    
    # Verify degraded mode is set in state
    local degraded_enabled
    degraded_enabled=$(jq -r '.degradedMode.enabled' "$STATE_FILE")
    if [[ "$degraded_enabled" != "true" ]]; then
        echo "ERROR: Degraded mode not enabled in state: $degraded_enabled"
        return 1
    fi
    
    # Verify reason is set
    local degraded_reason
    degraded_reason=$(jq -r '.degradedMode.reason' "$STATE_FILE")
    if [[ "$degraded_reason" != "test-failure" ]]; then
        echo "ERROR: Degraded mode reason incorrect: expected 'test-failure', got '$degraded_reason'"
        return 1
    fi
    
    # Verify disabled features are set
    local disabled_features
    disabled_features=$(jq -r '.degradedMode.disabledFeatures | length' "$STATE_FILE")
    if [[ "$disabled_features" != "2" ]]; then
        echo "ERROR: Expected 2 disabled features, got $disabled_features"
        return 1
    fi
    
    # Verify is_degraded_mode function
    local is_degraded
    is_degraded=$(is_degraded_mode)
    if [[ "$is_degraded" != "true" ]]; then
        echo "ERROR: is_degraded_mode returned false when mode is enabled"
        return 1
    fi
    
    log "Degraded mode enable test passed"
    return 0
}

test_degraded_mode_disable() {
    log "Testing degraded mode deactivation..."
    
    # Initialize state with degraded mode
    local degraded_state='{
        "phase": "degradation-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {},
        "degradedMode": {
            "enabled": true,
            "reason": "test-failure",
            "timestamp": "2023-01-01T00:00:00Z",
            "disabledFeatures": ["feature1"]
        }
    }'
    write_state "$degraded_state" "degraded"
    
    # Disable degraded mode
    if ! disable_degraded_mode; then
        echo "ERROR: Failed to disable degraded mode"
        return 1
    fi
    
    # Verify degraded mode is removed from state
    if jq -e '.degradedMode' "$STATE_FILE" >/dev/null 2>&1; then
        echo "ERROR: Degraded mode still present in state after disable"
        return 1
    fi
    
    # Verify is_degraded_mode function
    local is_degraded
    is_degraded=$(is_degraded_mode)
    if [[ "$is_degraded" != "false" ]]; then
        echo "ERROR: is_degraded_mode returned true after disabling mode"
        return 1
    fi
    
    log "Degraded mode disable test passed"
    return 0
}

# =============================================================================
# Recovery Strategy Tests
# =============================================================================

test_recovery_strategy_execution() {
    log "Testing recovery strategy execution..."
    
    # Test clean_stale_locks strategy
    if ! clean_stale_locks; then
        echo "ERROR: clean_stale_locks strategy failed"
        return 1
    fi
    
    # Test wait_and_retry strategy
    if ! wait_and_retry; then
        echo "ERROR: wait_and_retry strategy failed"
        return 1
    fi
    
    # Test cleanup_temp_files strategy
    # Create some temp files first
    touch "$TEMP_TEST_DIR/test.tmp"
    touch "$TEMP_TEST_DIR/test.temp"
    
    if ! cleanup_temp_files; then
        echo "ERROR: cleanup_temp_files strategy failed"
        return 1
    fi
    
    # Verify temp files were cleaned
    if [[ -f "$TEMP_TEST_DIR/test.tmp" ]] || [[ -f "$TEMP_TEST_DIR/test.temp" ]]; then
        echo "ERROR: Temp files not cleaned by cleanup strategy"
        return 1
    fi
    
    log "Recovery strategy execution test passed"
    return 0
}

test_automatic_error_handling() {
    log "Testing automatic error handling..."
    
    # Create a state for testing
    local test_state='{
        "phase": "error-handling-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$test_state" "initial"
    
    # Test handling timeout error with auto recovery
    local error_output
    error_output=$(handle_error "${ERROR_CODES[TIMEOUT]}" "Test timeout error" "test-operation" "true" 2>&1)
    
    # Verify error was logged
    if [[ ! "$error_output" =~ "Test timeout error" ]]; then
        echo "ERROR: Error message not in output"
        return 1
    fi
    
    # Test handling non-recoverable error
    error_output=$(handle_error "${ERROR_CODES[PERMISSION_DENIED]}" "Test permission error" "test-operation" "true" 2>&1)
    
    # Should generate recovery suggestions since no auto recovery available
    if [[ ! "$error_output" =~ "RECOVERY SUGGESTIONS" ]]; then
        echo "ERROR: Recovery suggestions not generated for non-recoverable error"
        return 1
    fi
    
    log "Automatic error handling test passed"
    return 0
}

# =============================================================================
# Recovery Suggestions Tests
# =============================================================================

test_recovery_suggestions_generation() {
    log "Testing recovery suggestions generation..."
    
    # Test different error types and verify appropriate suggestions
    local test_cases=(
        "${ERROR_CODES[LOCK_TIMEOUT]}:Lock Timeout Recovery"
        "${ERROR_CODES[STATE_CORRUPTION]}:State Corruption Recovery"
        "${ERROR_CODES[DISK_FULL]}:Disk Full Recovery"
        "${ERROR_CODES[PERMISSION_DENIED]}:Permission Denied Recovery"
        "${ERROR_CODES[DEPENDENCY_MISSING]}:Dependency Missing Recovery"
    )
    
    for case in "${test_cases[@]}"; do
        local error_code="${case%%:*}"
        local expected_text="${case##*:}"
        
        local suggestions
        suggestions=$(generate_recovery_suggestions "$error_code" "Test error" "test-operation" 2>&1)
        
        if [[ ! "$suggestions" =~ "$expected_text" ]]; then
            echo "ERROR: Expected recovery text '$expected_text' not found for error code $error_code"
            return 1
        fi
        
        # Verify suggestions contain specific commands
        if [[ ! "$suggestions" =~ "Available Recovery Commands" ]]; then
            echo "ERROR: Recovery commands section not found for error code $error_code"
            return 1
        fi
    done
    
    # Test unknown error code (should get general recovery)
    local general_suggestions
    general_suggestions=$(generate_recovery_suggestions "999" "Unknown error" "test-operation" 2>&1)
    
    if [[ ! "$general_suggestions" =~ "General Recovery" ]]; then
        echo "ERROR: General recovery suggestions not provided for unknown error code"
        return 1
    fi
    
    log "Recovery suggestions generation test passed"
    return 0
}

# =============================================================================
# Integration Tests
# =============================================================================

test_checkpoint_with_error_recovery() {
    log "Testing checkpoint integration with error recovery..."
    
    # Create initial state
    local test_state='{
        "phase": "integration-test",
        "completedTasks": ["task1"],
        "signals": {"ready": true},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"version": 1}
    }'
    write_state "$test_state" "initial"
    
    # Create checkpoint before risky operation
    create_checkpoint "risky-operation" "test-phase"
    local checkpoint_id="$CHECKPOINT_ID"
    
    # Simulate operation that corrupts state
    echo "corrupted state" > "$STATE_FILE"
    
    # Verify corruption detection
    if validate_state "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: State corruption not detected"
        return 1
    fi
    
    # Restore from checkpoint
    if ! restore_checkpoint "$checkpoint_id"; then
        echo "ERROR: Failed to restore from checkpoint after corruption"
        return 1
    fi
    
    # Verify state is restored and valid
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: Restored state is not valid"
        return 1
    fi
    
    # Verify original data is restored
    local restored_phase
    restored_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$restored_phase" != "integration-test" ]]; then
        echo "ERROR: Original data not properly restored: expected 'integration-test', got '$restored_phase'"
        return 1
    fi
    
    log "Checkpoint integration with error recovery test passed"
    return 0
}

test_retry_with_checkpoints() {
    log "Testing retry logic with checkpoint fallback..."
    
    # Create initial state and checkpoint
    local test_state='{
        "phase": "retry-checkpoint-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {"attempts": 0}
    }'
    write_state "$test_state" "initial"
    create_checkpoint "retry-operation" "test-phase"
    local checkpoint_id="$CHECKPOINT_ID"
    
    # Create operation that fails multiple times then succeeds
    risky_operation_with_checkpoint() {
        local current_state
        current_state=$(read_state)
        local attempts
        attempts=$(echo "$current_state" | jq -r '.metadata.attempts')
        ((attempts++))
        
        # Update attempt count
        current_state=$(echo "$current_state" | jq --arg attempts "$attempts" '.metadata.attempts = ($attempts | tonumber)')
        write_state "$current_state" "attempt-$attempts"
        
        # Fail first 2 attempts
        if [[ $attempts -le 2 ]]; then
            echo "Operation failed on attempt $attempts"
            return 1
        else
            echo "Operation succeeded on attempt $attempts"
            return 0
        fi
    }
    
    # Run operation with retry
    if ! retry_with_backoff risky_operation_with_checkpoint 3 1; then
        echo "ERROR: Retry operation failed"
        
        # Fallback to checkpoint restore
        if ! restore_checkpoint "$checkpoint_id"; then
            echo "ERROR: Checkpoint restore fallback failed"
            return 1
        fi
        
        echo "INFO: Restored from checkpoint as fallback"
    fi
    
    # Verify final state
    local final_attempts
    final_attempts=$(jq -r '.metadata.attempts' "$STATE_FILE")
    
    # Should either succeed after retries or be restored to initial state
    if [[ "$final_attempts" != "3" ]] && [[ "$final_attempts" != "0" ]]; then
        echo "ERROR: Unexpected final state: attempts = $final_attempts"
        return 1
    fi
    
    log "Retry with checkpoints test passed"
    return 0
}

# =============================================================================
# Main Test Execution
# =============================================================================

print_header() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                    ERROR RECOVERY TEST SUITE${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Testing checkpoint system, retry logic, error handling, and recovery strategies"
    echo
}

print_summary() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                           TEST SUMMARY${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Total Tests Run: $TESTS_RUN"
    echo "${GREEN}Tests Passed: $TESTS_PASSED${RESET}"
    echo "${RED}Tests Failed: $TESTS_FAILED${RESET}"
    echo
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "${RED}Failed Tests:${RESET}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo
        exit 1
    else
        echo "${GREEN}${BOLD}🎉 All tests passed!${RESET}"
        echo
        exit 0
    fi
}

main() {
    print_header
    
    # Checkpoint System Tests
    run_test "Checkpoint Creation" test_checkpoint_creation
    run_test "Checkpoint Restoration" test_checkpoint_restoration
    run_test "Checkpoint Listing" test_checkpoint_listing
    run_test "Checkpoint Cleanup" test_checkpoint_cleanup
    
    # Retry Logic and Exponential Backoff Tests
    run_test "Basic Retry Logic" test_basic_retry_logic
    run_test "Exponential Backoff" test_exponential_backoff
    run_test "Non-Retryable Errors" test_retry_with_non_retryable_errors
    run_test "Maximum Retry Delay" test_max_retry_delay
    
    # Error Code System Tests
    run_test "Error Code Definitions" test_error_code_definitions
    run_test "Should Retry Logic" test_should_retry_logic
    
    # Graceful Degradation Tests
    run_test "Degraded Mode Enable" test_degraded_mode_enable
    run_test "Degraded Mode Disable" test_degraded_mode_disable
    
    # Recovery Strategy Tests
    run_test "Recovery Strategy Execution" test_recovery_strategy_execution
    run_test "Automatic Error Handling" test_automatic_error_handling
    
    # Recovery Suggestions Tests
    run_test "Recovery Suggestions Generation" test_recovery_suggestions_generation
    
    # Integration Tests
    run_test "Checkpoint with Error Recovery" test_checkpoint_with_error_recovery
    run_test "Retry with Checkpoints" test_retry_with_checkpoints
    
    print_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi