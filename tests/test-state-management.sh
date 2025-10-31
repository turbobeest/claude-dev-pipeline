#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - State Management Tests
# =============================================================================
# 
# Comprehensive test suite for atomic state management operations.
# Tests file locking, atomic updates, concurrent access, corruption recovery,
# backup/restore operations, state migration, and data integrity.
#
# Test Categories:
# - File Locking Mechanisms
# - Atomic State Updates
# - Concurrent State Access
# - State Corruption Detection and Recovery
# - Backup and Restore Operations
# - State Migration and Schema Evolution
# - Data Integrity Validation
# - Performance Under Load
#
# =============================================================================

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_TEST_DIR="$TEST_DIR/temp/state-tests"
TEST_STATE_FILE="$TEMP_TEST_DIR/.workflow-state.json"
TEST_BACKUP_DIR="$TEMP_TEST_DIR/.state-backups"
TEST_LOCK_DIR="$TEMP_TEST_DIR/.locks"

# Load libraries
source "$PIPELINE_DIR/lib/state-manager.sh"

# Override paths for testing
export STATE_FILE="$TEST_STATE_FILE"
export BACKUP_DIR="$TEST_BACKUP_DIR"
export LOCK_DIR="$TEST_LOCK_DIR"
export AUDIT_LOG="$TEMP_TEST_DIR/audit.log"

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
    mkdir -p "$TEMP_TEST_DIR" "$TEST_BACKUP_DIR" "$TEST_LOCK_DIR"
    
    # Ensure clean state for each test
    unset CLAUDE_PIPELINE_ROOT
    export PIPELINE_ROOT="$TEMP_TEST_DIR"
}

cleanup_test_environment() {
    # Clean up locks and temp files
    find "$TEMP_TEST_DIR" -name "*.lock" -delete 2>/dev/null || true
    find "$TEMP_TEST_DIR" -name "*.tmp*" -delete 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup_test_environment EXIT

# =============================================================================
# File Locking Mechanism Tests
# =============================================================================

test_basic_locking() {
    log "Testing basic file locking mechanisms..."
    
    # Test lock acquisition
    if ! lock_state 5; then
        echo "ERROR: Failed to acquire lock"
        return 1
    fi
    
    # Verify lock file exists
    local lock_file="$LOCK_DIR/state.lock"
    if [[ ! -f "$lock_file" ]]; then
        echo "ERROR: Lock file not created"
        return 1
    fi
    
    # Verify lock contains correct PID
    local lock_pid
    lock_pid=$(cat "$lock_file")
    if [[ "$lock_pid" != "$$" ]]; then
        echo "ERROR: Lock file contains wrong PID: expected $$, got $lock_pid"
        return 1
    fi
    
    # Test lock release
    if ! unlock_state; then
        echo "ERROR: Failed to release lock"
        return 1
    fi
    
    # Verify lock file removed
    if [[ -f "$lock_file" ]]; then
        echo "ERROR: Lock file not removed after unlock"
        return 1
    fi
    
    log "Basic locking test passed"
    return 0
}

test_lock_timeout() {
    log "Testing lock timeout mechanism..."
    
    # Acquire lock in background process
    (
        lock_state 30
        sleep 10
        unlock_state
    ) &
    local bg_pid=$!
    
    # Wait a moment for background process to acquire lock
    sleep 1
    
    # Attempt to acquire lock with short timeout (should fail)
    local start_time=$(date +%s)
    if lock_state 2 2>/dev/null; then
        echo "ERROR: Lock acquisition should have timed out"
        kill $bg_pid 2>/dev/null || true
        return 1
    fi
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    # Verify timeout was respected (should be approximately 2 seconds)
    if [[ $elapsed -lt 1 || $elapsed -gt 4 ]]; then
        echo "ERROR: Lock timeout not respected: elapsed ${elapsed}s, expected ~2s"
        kill $bg_pid 2>/dev/null || true
        return 1
    fi
    
    # Clean up background process
    wait $bg_pid 2>/dev/null || true
    
    log "Lock timeout test passed"
    return 0
}

test_stale_lock_cleanup() {
    log "Testing stale lock cleanup..."
    
    # Create stale lock with non-existent PID
    local lock_file="$LOCK_DIR/state.lock"
    echo "99999" > "$lock_file"
    
    # Attempt to acquire lock (should clean up stale lock)
    if ! lock_state 5; then
        echo "ERROR: Failed to acquire lock after stale lock cleanup"
        return 1
    fi
    
    # Verify new lock has correct PID
    local lock_pid
    lock_pid=$(cat "$lock_file")
    if [[ "$lock_pid" != "$$" ]]; then
        echo "ERROR: Stale lock not properly cleaned up"
        return 1
    fi
    
    unlock_state
    
    log "Stale lock cleanup test passed"
    return 0
}

test_aged_lock_cleanup() {
    log "Testing aged lock cleanup..."
    
    # Create old lock file (simulate 6 minutes old)
    local lock_file="$LOCK_DIR/state.lock"
    echo "$$" > "$lock_file"
    
    # Manually set file modification time to 6 minutes ago (macOS compatible)
    touch -t $(date -v-6M +%Y%m%d%H%M.%S) "$lock_file" 2>/dev/null || \
    touch -d "6 minutes ago" "$lock_file" 2>/dev/null || \
    {
        # Fallback: create the test scenario differently
        echo "SKIPPING: Cannot modify file timestamp on this system"
        return 0
    }
    
    # Start background process to simulate lock holder
    sleep 2 &
    local bg_pid=$!
    echo "$bg_pid" > "$lock_file"
    
    # Attempt to acquire lock (should clean up aged lock)
    if ! lock_state 5; then
        echo "ERROR: Failed to acquire lock after aged lock cleanup"
        kill $bg_pid 2>/dev/null || true
        return 1
    fi
    
    # Verify new lock has correct PID
    local lock_pid
    lock_pid=$(cat "$lock_file")
    if [[ "$lock_pid" != "$$" ]]; then
        echo "ERROR: Aged lock not properly cleaned up"
        kill $bg_pid 2>/dev/null || true
        return 1
    fi
    
    unlock_state
    kill $bg_pid 2>/dev/null || true
    
    log "Aged lock cleanup test passed"
    return 0
}

# =============================================================================
# Atomic State Update Tests
# =============================================================================

test_atomic_state_writes() {
    log "Testing atomic state write operations..."
    
    # Test basic write
    local test_state='{
        "phase": "test-phase",
        "completedTasks": ["task1", "task2"],
        "signals": {"signal1": true},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"test": true}
    }'
    
    if ! write_state "$test_state" "test"; then
        echo "ERROR: Failed to write state"
        return 1
    fi
    
    # Verify state file exists and contains expected content
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "ERROR: State file not created"
        return 1
    fi
    
    # Verify JSON structure
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: State file contains invalid JSON"
        return 1
    fi
    
    # Verify specific fields
    local phase
    phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$phase" != "test-phase" ]]; then
        echo "ERROR: Phase not written correctly: expected 'test-phase', got '$phase'"
        return 1
    fi
    
    # Verify metadata was added
    local schema_version
    schema_version=$(jq -r '.schemaVersion' "$STATE_FILE")
    if [[ -z "$schema_version" ]]; then
        echo "ERROR: Schema version not added to state"
        return 1
    fi
    
    log "Atomic state writes test passed"
    return 0
}

test_write_failure_rollback() {
    log "Testing write failure rollback..."
    
    # Create initial valid state
    local initial_state='{
        "phase": "initial",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    
    write_state "$initial_state" "initial"
    local initial_content
    initial_content=$(cat "$STATE_FILE")
    
    # Attempt to write invalid JSON (should fail and preserve original)
    if write_state "invalid json" "invalid" 2>/dev/null; then
        echo "ERROR: Invalid JSON write should have failed"
        return 1
    fi
    
    # Verify original state preserved
    local current_content
    current_content=$(cat "$STATE_FILE")
    if [[ "$initial_content" != "$current_content" ]]; then
        echo "ERROR: Original state not preserved after failed write"
        return 1
    fi
    
    # Verify state is still valid
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: State corrupted after failed write attempt"
        return 1
    fi
    
    log "Write failure rollback test passed"
    return 0
}

test_temp_file_cleanup() {
    log "Testing temporary file cleanup..."
    
    # Create some temporary files
    touch "$TEMP_TEST_DIR/test.tmp.123"
    touch "$TEMP_TEST_DIR/test.tmp.456"
    touch "$TEMP_TEST_DIR/old.tmp"
    
    # Manually set old timestamp on one file
    touch -t $(date -v-2H +%Y%m%d%H%M.%S) "$TEMP_TEST_DIR/old.tmp" 2>/dev/null || \
    touch -d "2 hours ago" "$TEMP_TEST_DIR/old.tmp" 2>/dev/null || \
    {
        echo "SKIPPING: Cannot modify file timestamp for cleanup test"
        return 0
    }
    
    # Run cleanup
    cleanup_temp_files
    
    # Verify old temp file was cleaned up
    if [[ -f "$TEMP_TEST_DIR/old.tmp" ]]; then
        echo "ERROR: Old temporary file not cleaned up"
        return 1
    fi
    
    log "Temporary file cleanup test passed"
    return 0
}

# =============================================================================
# Concurrent State Access Tests
# =============================================================================

test_concurrent_reads() {
    log "Testing concurrent state reads..."
    
    # Create initial state
    local test_state='{
        "phase": "concurrent-test",
        "completedTasks": ["task1"],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$test_state" "initial"
    
    # Start multiple concurrent readers
    local pids=()
    local results=()
    
    read_state_async() {
        local result_file=$1
        local iteration=$2
        
        if read_state > "$result_file" 2>/dev/null; then
            echo "success-$iteration" >> "$result_file"
        else
            echo "failed-$iteration" >> "$result_file"
        fi
    }
    
    # Start concurrent reads
    for i in {1..5}; do
        local result_file="$TEMP_TEST_DIR/read_result_$i"
        read_state_async "$result_file" "$i" &
        pids+=($!)
        results+=("$result_file")
    done
    
    # Wait for all reads to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Verify all reads succeeded
    local success_count=0
    for result_file in "${results[@]}"; do
        if [[ -f "$result_file" ]] && grep -q "success" "$result_file"; then
            ((success_count++))
        fi
    done
    
    if [[ "$success_count" != "5" ]]; then
        echo "ERROR: Expected 5 successful reads, got $success_count"
        return 1
    fi
    
    # Verify all reads got the same content
    local first_content
    first_content=$(head -n -1 "${results[0]}")  # Remove success line
    
    for result_file in "${results[@]:1}"; do
        local content
        content=$(head -n -1 "$result_file")
        if [[ "$content" != "$first_content" ]]; then
            echo "ERROR: Concurrent reads returned different content"
            return 1
        fi
    done
    
    log "Concurrent reads test passed"
    return 0
}

test_concurrent_writes() {
    log "Testing concurrent state writes..."
    
    # Start multiple concurrent writers
    local pids=()
    local results=()
    
    write_state_async() {
        local phase_name=$1
        local result_file=$2
        
        local state="{
            \"phase\": \"$phase_name\",
            \"completedTasks\": [],
            \"signals\": {},
            \"lastActivation\": \"\",
            \"metadata\": {\"writer\": \"$phase_name\"}
        }"
        
        if write_state "$state" "concurrent-$phase_name" 2>/dev/null; then
            echo "success" > "$result_file"
        else
            echo "failed" > "$result_file"
        fi
    }
    
    # Start concurrent writes
    for i in {1..3}; do
        local result_file="$TEMP_TEST_DIR/write_result_$i"
        write_state_async "phase-$i" "$result_file" &
        pids+=($!)
        results+=("$result_file")
    done
    
    # Wait for all writes to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Verify all writes succeeded (due to locking)
    local success_count=0
    for result_file in "${results[@]}"; do
        if [[ -f "$result_file" ]] && [[ "$(cat "$result_file")" == "success" ]]; then
            ((success_count++))
        fi
    done
    
    if [[ "$success_count" != "3" ]]; then
        echo "ERROR: Expected 3 successful writes, got $success_count"
        return 1
    fi
    
    # Verify final state is valid and consistent
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: State file corrupted by concurrent writes"
        return 1
    fi
    
    # Verify final state contains data from last writer
    local final_phase
    final_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ ! "$final_phase" =~ ^phase-[1-3]$ ]]; then
        echo "ERROR: Final state has unexpected phase: $final_phase"
        return 1
    fi
    
    log "Concurrent writes test passed"
    return 0
}

test_read_write_concurrency() {
    log "Testing mixed concurrent read/write operations..."
    
    # Initialize state
    local initial_state='{
        "phase": "read-write-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {"counter": 0}
    }'
    write_state "$initial_state" "initial"
    
    # Mixed operations function
    mixed_operation() {
        local op_type=$1
        local iteration=$2
        local result_file=$3
        
        case "$op_type" in
            "read")
                if read_state >/dev/null 2>&1; then
                    echo "read-success" > "$result_file"
                else
                    echo "read-failed" > "$result_file"
                fi
                ;;
            "write")
                local state
                state=$(read_state 2>/dev/null || echo "$initial_state")
                state=$(echo "$state" | jq --arg iter "$iteration" '.metadata.counter = ($iter | tonumber)')
                
                if write_state "$state" "update-$iteration" 2>/dev/null; then
                    echo "write-success" > "$result_file"
                else
                    echo "write-failed" > "$result_file"
                fi
                ;;
        esac
    }
    
    local pids=()
    local results=()
    
    # Start mixed operations
    for i in {1..6}; do
        local result_file="$TEMP_TEST_DIR/mixed_result_$i"
        local op_type
        if [[ $((i % 2)) -eq 0 ]]; then
            op_type="write"
        else
            op_type="read"
        fi
        
        mixed_operation "$op_type" "$i" "$result_file" &
        pids+=($!)
        results+=("$result_file")
    done
    
    # Wait for completion
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Verify all operations succeeded
    local total_success=0
    for result_file in "${results[@]}"; do
        if [[ -f "$result_file" ]] && grep -q "success" "$result_file"; then
            ((total_success++))
        fi
    done
    
    if [[ "$total_success" != "6" ]]; then
        echo "ERROR: Expected 6 successful operations, got $total_success"
        return 1
    fi
    
    # Verify final state integrity
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: State corrupted by mixed concurrent operations"
        return 1
    fi
    
    log "Read/write concurrency test passed"
    return 0
}

# =============================================================================
# State Corruption Detection and Recovery Tests
# =============================================================================

test_corruption_detection() {
    log "Testing state corruption detection..."
    
    # Create valid state first
    local valid_state='{
        "phase": "corruption-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$valid_state" "initial"
    
    # Test JSON corruption detection
    echo "invalid json {" > "$STATE_FILE"
    if validate_state "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: JSON corruption not detected"
        return 1
    fi
    
    # Test missing required fields
    echo '{"phase": "test"}' > "$STATE_FILE"
    if validate_state "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: Missing required fields not detected"
        return 1
    fi
    
    # Test invalid field types
    echo '{
        "phase": 123,
        "completedTasks": "not-array",
        "signals": "not-object",
        "lastActivation": ""
    }' > "$STATE_FILE"
    if validate_state "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: Invalid field types not detected"
        return 1
    fi
    
    # Test schema version mismatch (should warn but not fail)
    echo '{
        "schemaVersion": "0.1",
        "phase": "test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": ""
    }' > "$STATE_FILE"
    if ! validate_state "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: Schema version mismatch should not fail validation"
        return 1
    fi
    
    log "Corruption detection test passed"
    return 0
}

test_automatic_recovery() {
    log "Testing automatic state recovery..."
    
    # Create initial valid state and backup
    local valid_state='{
        "phase": "recovery-test",
        "completedTasks": ["task1"],
        "signals": {"ready": true},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"test": true}
    }'
    write_state "$valid_state" "initial"
    backup_state "pre-corruption"
    
    # Corrupt the state file
    echo "corrupted data" > "$STATE_FILE"
    
    # Attempt recovery
    if ! recover_state; then
        echo "ERROR: State recovery failed"
        return 1
    fi
    
    # Verify state is restored and valid
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: Recovered state is not valid"
        return 1
    fi
    
    # Verify content matches original
    local recovered_phase
    recovered_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$recovered_phase" != "recovery-test" ]]; then
        echo "ERROR: Recovered state content incorrect: expected 'recovery-test', got '$recovered_phase'"
        return 1
    fi
    
    log "Automatic recovery test passed"
    return 0
}

test_recovery_with_invalid_backup() {
    log "Testing recovery behavior with invalid backups..."
    
    # Create invalid backup
    mkdir -p "$BACKUP_DIR"
    echo "invalid backup data" > "$BACKUP_DIR/state-20231201-120000-manual.json"
    
    # Remove state file
    rm -f "$STATE_FILE"
    
    # Attempt recovery (should create default state)
    if ! recover_state; then
        echo "ERROR: Recovery should succeed by creating default state"
        return 1
    fi
    
    # Verify default state was created
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "ERROR: Default state file not created"
        return 1
    fi
    
    # Verify default state is valid
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: Default state is not valid"
        return 1
    fi
    
    # Verify default state content
    local phase
    phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$phase" != "pre-init" ]]; then
        echo "ERROR: Default state phase incorrect: expected 'pre-init', got '$phase'"
        return 1
    fi
    
    log "Recovery with invalid backup test passed"
    return 0
}

# =============================================================================
# Backup and Restore Operations Tests
# =============================================================================

test_backup_creation() {
    log "Testing backup creation..."
    
    # Create state to backup
    local test_state='{
        "phase": "backup-test",
        "completedTasks": ["task1", "task2"],
        "signals": {"backup": true},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"backup_test": true}
    }'
    write_state "$test_state" "initial"
    
    # Create backup
    if ! backup_state "manual-test"; then
        echo "ERROR: Backup creation failed"
        return 1
    fi
    
    # Verify backup file exists
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "state-*-manual-test.json" | wc -l)
    if [[ "$backup_count" -eq 0 ]]; then
        echo "ERROR: Backup file not created"
        return 1
    fi
    
    # Verify backup content
    local backup_file
    backup_file=$(find "$BACKUP_DIR" -name "state-*-manual-test.json" | head -1)
    
    if ! jq empty "$backup_file" 2>/dev/null; then
        echo "ERROR: Backup file contains invalid JSON"
        return 1
    fi
    
    local backup_phase
    backup_phase=$(jq -r '.phase' "$backup_file")
    if [[ "$backup_phase" != "backup-test" ]]; then
        echo "ERROR: Backup content incorrect: expected 'backup-test', got '$backup_phase'"
        return 1
    fi
    
    log "Backup creation test passed"
    return 0
}

test_backup_rotation() {
    log "Testing backup rotation..."
    
    # Create test state
    local test_state='{
        "phase": "rotation-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$test_state" "initial"
    
    # Create more backups than the limit
    for i in {1..7}; do
        backup_state "rotation-test-$i"
        sleep 1  # Ensure different timestamps
    done
    
    # Verify backup count doesn't exceed maximum
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "state-*.json" | wc -l)
    
    # Should not exceed MAX_BACKUPS (5)
    if [[ "$backup_count" -gt 5 ]]; then
        echo "ERROR: Too many backups retained: $backup_count (max: 5)"
        return 1
    fi
    
    # Verify newest backups are retained
    if ! find "$BACKUP_DIR" -name "*rotation-test-7.json" | grep -q .; then
        echo "ERROR: Newest backup not retained"
        return 1
    fi
    
    if ! find "$BACKUP_DIR" -name "*rotation-test-6.json" | grep -q .; then
        echo "ERROR: Recent backup not retained"
        return 1
    fi
    
    log "Backup rotation test passed"
    return 0
}

test_restore_from_specific_backup() {
    log "Testing restore from specific backup..."
    
    # Create initial state
    local initial_state='{
        "phase": "restore-test-1",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {"version": 1}
    }'
    write_state "$initial_state" "v1"
    backup_state "version-1"
    
    # Create updated state
    local updated_state='{
        "phase": "restore-test-2",
        "completedTasks": ["task1"],
        "signals": {"updated": true},
        "lastActivation": "2023-01-01T12:00:00Z",
        "metadata": {"version": 2}
    }'
    write_state "$updated_state" "v2"
    backup_state "version-2"
    
    # Restore from first backup
    if ! recover_state "version-1"; then
        echo "ERROR: Failed to restore from specific backup"
        return 1
    fi
    
    # Verify restored content
    local restored_phase
    restored_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$restored_phase" != "restore-test-1" ]]; then
        echo "ERROR: Restored wrong backup: expected 'restore-test-1', got '$restored_phase'"
        return 1
    fi
    
    local restored_version
    restored_version=$(jq -r '.metadata.version' "$STATE_FILE")
    if [[ "$restored_version" != "1" ]]; then
        echo "ERROR: Restored backup has wrong version: expected 1, got $restored_version"
        return 1
    fi
    
    log "Restore from specific backup test passed"
    return 0
}

# =============================================================================
# State Migration Tests
# =============================================================================

test_schema_migration() {
    log "Testing state schema migration..."
    
    # Create state with old schema version
    local old_state='{
        "schemaVersion": "0.9",
        "phase": "migration-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {}
    }'
    write_state "$old_state" "old-schema"
    
    # Trigger migration
    if ! migrate_state; then
        echo "ERROR: State migration failed"
        return 1
    fi
    
    # Verify schema version updated
    local new_version
    new_version=$(jq -r '.schemaVersion' "$STATE_FILE")
    if [[ "$new_version" != "$STATE_SCHEMA_VERSION" ]]; then
        echo "ERROR: Schema version not updated: expected '$STATE_SCHEMA_VERSION', got '$new_version'"
        return 1
    fi
    
    # Verify migration metadata added
    local migrated_flag
    migrated_flag=$(jq -r '.metadata.migrated' "$STATE_FILE")
    if [[ "$migrated_flag" != "true" ]]; then
        echo "ERROR: Migration metadata not added"
        return 1
    fi
    
    # Verify original data preserved
    local phase
    phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$phase" != "migration-test" ]]; then
        echo "ERROR: Original data not preserved during migration"
        return 1
    fi
    
    log "Schema migration test passed"
    return 0
}

test_legacy_format_migration() {
    log "Testing legacy format migration..."
    
    # Create legacy format state (missing schema version)
    local legacy_state='{
        "phase": "legacy-test",
        "completedTasks": ["old-task"],
        "signals": {"legacy": true},
        "lastActivation": ""
    }'
    echo "$legacy_state" > "$STATE_FILE"
    
    # Trigger migration
    if ! migrate_state; then
        echo "ERROR: Legacy format migration failed"
        return 1
    fi
    
    # Verify schema version added
    local version
    version=$(jq -r '.schemaVersion' "$STATE_FILE")
    if [[ "$version" != "$STATE_SCHEMA_VERSION" ]]; then
        echo "ERROR: Schema version not added during legacy migration"
        return 1
    fi
    
    # Verify metadata field added
    if ! jq -e '.metadata' "$STATE_FILE" >/dev/null; then
        echo "ERROR: Metadata field not added during legacy migration"
        return 1
    fi
    
    # Verify migration tracking
    local migrated_from
    migrated_from=$(jq -r '.metadata.migratedFrom' "$STATE_FILE")
    if [[ "$migrated_from" != "legacy" ]]; then
        echo "ERROR: Migration tracking not added: expected 'legacy', got '$migrated_from'"
        return 1
    fi
    
    # Verify original data preserved
    local phase
    phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$phase" != "legacy-test" ]]; then
        echo "ERROR: Original data not preserved during legacy migration"
        return 1
    fi
    
    log "Legacy format migration test passed"
    return 0
}

# =============================================================================
# Data Integrity Validation Tests
# =============================================================================

test_comprehensive_validation() {
    log "Testing comprehensive state validation..."
    
    # Test valid state
    local valid_state='{
        "schemaVersion": "'$STATE_SCHEMA_VERSION'",
        "phase": "validation-test",
        "completedTasks": ["task1", "task2"],
        "signals": {"ready": true, "error": false},
        "lastActivation": "2023-01-01T00:00:00Z",
        "metadata": {"test": true}
    }'
    echo "$valid_state" > "$STATE_FILE"
    
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: Valid state failed validation"
        return 1
    fi
    
    # Test various invalid states
    local test_cases=(
        '{"phase": "test"}'  # Missing required fields
        '{"phase": 123, "completedTasks": [], "signals": {}, "lastActivation": ""}'  # Wrong type
        '{"phase": "test", "completedTasks": "not-array", "signals": {}, "lastActivation": ""}'  # Wrong type
        '{"phase": "test", "completedTasks": [], "signals": "not-object", "lastActivation": ""}'  # Wrong type
    )
    
    for test_case in "${test_cases[@]}"; do
        echo "$test_case" > "$STATE_FILE"
        if validate_state "$STATE_FILE" 2>/dev/null; then
            echo "ERROR: Invalid state passed validation: $test_case"
            return 1
        fi
    done
    
    log "Comprehensive validation test passed"
    return 0
}

test_validation_timeout() {
    log "Testing validation timeout handling..."
    
    # Create a very large state file to test timeout
    local large_state='{"phase": "timeout-test", "completedTasks": ['
    for i in {1..1000}; do
        large_state+='"task'$i'"'
        if [[ $i -lt 1000 ]]; then
            large_state+=','
        fi
    done
    large_state+='], "signals": {}, "lastActivation": ""}'
    
    echo "$large_state" > "$STATE_FILE"
    
    # Test with very short timeout (should still work for reasonable sizes)
    local old_timeout=$VALIDATION_TIMEOUT
    export VALIDATION_TIMEOUT=1
    
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: Validation failed with short timeout"
        export VALIDATION_TIMEOUT=$old_timeout
        return 1
    fi
    
    export VALIDATION_TIMEOUT=$old_timeout
    
    log "Validation timeout test passed"
    return 0
}

# =============================================================================
# Performance Under Load Tests
# =============================================================================

test_high_frequency_operations() {
    log "Testing high-frequency state operations..."
    
    # Initialize state
    local initial_state='{
        "phase": "performance-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {"counter": 0}
    }'
    write_state "$initial_state" "initial"
    
    # Perform many rapid operations
    local start_time=$(date +%s)
    for i in {1..20}; do
        local current_state
        current_state=$(read_state)
        current_state=$(echo "$current_state" | jq --arg counter "$i" '.metadata.counter = ($counter | tonumber)')
        write_state "$current_state" "update-$i" >/dev/null
    done
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Verify final state
    local final_counter
    final_counter=$(jq -r '.metadata.counter' "$STATE_FILE")
    if [[ "$final_counter" != "20" ]]; then
        echo "ERROR: High-frequency operations lost data: expected 20, got $final_counter"
        return 1
    fi
    
    # Performance check (should complete within reasonable time)
    if [[ $duration -gt 30 ]]; then
        echo "WARNING: High-frequency operations took too long: ${duration}s"
    fi
    
    log "High-frequency operations test passed (${duration}s for 20 operations)"
    return 0
}

test_large_state_handling() {
    log "Testing large state file handling..."
    
    # Create large state with many tasks
    local large_tasks='['
    for i in {1..500}; do
        large_tasks+='"task-'$i'"'
        if [[ $i -lt 500 ]]; then
            large_tasks+=','
        fi
    done
    large_tasks+=']'
    
    local large_state='{
        "phase": "large-state-test",
        "completedTasks": '$large_tasks',
        "signals": {},
        "lastActivation": "",
        "metadata": {"size": "large"}
    }'
    
    # Test write performance
    local start_time=$(date +%s)
    if ! write_state "$large_state" "large-test"; then
        echo "ERROR: Failed to write large state"
        return 1
    fi
    local write_time=$(($(date +%s) - start_time))
    
    # Test read performance
    start_time=$(date +%s)
    local read_result
    if ! read_result=$(read_state); then
        echo "ERROR: Failed to read large state"
        return 1
    fi
    local read_time=$(($(date +%s) - start_time))
    
    # Verify data integrity
    local task_count
    task_count=$(echo "$read_result" | jq '.completedTasks | length')
    if [[ "$task_count" != "500" ]]; then
        echo "ERROR: Large state data corrupted: expected 500 tasks, got $task_count"
        return 1
    fi
    
    # Performance checks
    if [[ $write_time -gt 5 ]]; then
        echo "WARNING: Large state write took too long: ${write_time}s"
    fi
    
    if [[ $read_time -gt 5 ]]; then
        echo "WARNING: Large state read took too long: ${read_time}s"
    fi
    
    log "Large state handling test passed (write: ${write_time}s, read: ${read_time}s)"
    return 0
}

# =============================================================================
# Main Test Execution
# =============================================================================

print_header() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                    STATE MANAGEMENT TEST SUITE${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Testing atomic state operations, locking, corruption recovery, and data integrity"
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
    
    # File Locking Mechanism Tests
    run_test "Basic File Locking" test_basic_locking
    run_test "Lock Timeout Mechanism" test_lock_timeout
    run_test "Stale Lock Cleanup" test_stale_lock_cleanup
    run_test "Aged Lock Cleanup" test_aged_lock_cleanup
    
    # Atomic State Update Tests
    run_test "Atomic State Writes" test_atomic_state_writes
    run_test "Write Failure Rollback" test_write_failure_rollback
    run_test "Temporary File Cleanup" test_temp_file_cleanup
    
    # Concurrent State Access Tests
    run_test "Concurrent State Reads" test_concurrent_reads
    run_test "Concurrent State Writes" test_concurrent_writes
    run_test "Mixed Read/Write Concurrency" test_read_write_concurrency
    
    # State Corruption Detection and Recovery Tests
    run_test "Corruption Detection" test_corruption_detection
    run_test "Automatic Recovery" test_automatic_recovery
    run_test "Recovery with Invalid Backup" test_recovery_with_invalid_backup
    
    # Backup and Restore Operations Tests
    run_test "Backup Creation" test_backup_creation
    run_test "Backup Rotation" test_backup_rotation
    run_test "Restore from Specific Backup" test_restore_from_specific_backup
    
    # State Migration Tests
    run_test "Schema Migration" test_schema_migration
    run_test "Legacy Format Migration" test_legacy_format_migration
    
    # Data Integrity Validation Tests
    run_test "Comprehensive Validation" test_comprehensive_validation
    run_test "Validation Timeout Handling" test_validation_timeout
    
    # Performance Under Load Tests
    run_test "High-Frequency Operations" test_high_frequency_operations
    run_test "Large State Handling" test_large_state_handling
    
    print_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi