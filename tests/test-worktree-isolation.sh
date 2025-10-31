#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Worktree Isolation Tests
# =============================================================================
# 
# Comprehensive test suite for git worktree management and isolation.
# Tests worktree creation, management, concurrent operations, isolation
# enforcement, merge operations, cleanup, and contamination prevention.
#
# Test Categories:
# - Worktree Creation and Management
# - Isolation Verification
# - Concurrent Operations
# - Merge and Integration
# - Cleanup and State Management
# - Contamination Prevention
# - State Tracking
#
# =============================================================================

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_TEST_DIR="$TEST_DIR/temp/worktree-tests"
REPO_NAME="test-worktree-repo"
TEST_REPO="$TEMP_TEST_DIR/$REPO_NAME"

# Load libraries
source "$PIPELINE_DIR/lib/worktree-manager.sh"
source "$PIPELINE_DIR/lib/state-manager.sh"

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

setup_test_repo() {
    log "Setting up test repository..."
    
    # Clean and create temp directory
    rm -rf "$TEMP_TEST_DIR"
    mkdir -p "$TEMP_TEST_DIR"
    cd "$TEMP_TEST_DIR"
    
    # Initialize test repository
    git init "$REPO_NAME"
    cd "$REPO_NAME"
    
    # Configure git
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config init.defaultBranch main
    
    # Create initial commit
    echo "# Test Repository" > README.md
    echo "test: initial content" > test.txt
    mkdir -p src
    echo "console.log('hello world');" > src/main.js
    
    git add .
    git commit -m "Initial commit"
    
    # Set pipeline environment variables
    export CLAUDE_PIPELINE_ROOT="$(pwd)"
    export WORKTREE_BASE_DIR="$(pwd)/worktrees"
    export WORKTREE_STATE_FILE="$(pwd)/config/worktree-state.json"
    
    # Create necessary directories
    mkdir -p config logs worktrees
    
    log "Test repository setup complete: $(pwd)"
}

cleanup_test_repo() {
    log "Cleaning up test environment..."
    
    # Return to test directory first
    cd "$TEST_DIR" 2>/dev/null || true
    
    # Clean up any remaining worktrees
    if [[ -d "$TEST_REPO" ]]; then
        cd "$TEST_REPO"
        git worktree list --porcelain 2>/dev/null | grep -E '^worktree ' | while read -r _ path; do
            if [[ "$path" != "$(pwd)" ]]; then
                git worktree remove "$path" --force 2>/dev/null || true
            fi
        done
    fi
    
    # Remove temp directory
    rm -rf "$TEMP_TEST_DIR" 2>/dev/null || true
    
    log "Cleanup complete"
}

# Set up cleanup trap
trap cleanup_test_repo EXIT

# =============================================================================
# Worktree Creation and Management Tests
# =============================================================================

test_worktree_creation() {
    log "Testing basic worktree creation..."
    
    cd "$TEST_REPO"
    
    # Test basic creation
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    if [[ ! -d "$worktree_path" ]]; then
        echo "ERROR: Worktree directory not created: $worktree_path"
        return 1
    fi
    
    # Verify worktree is tracked by git
    if ! git worktree list | grep -q "$worktree_path"; then
        echo "ERROR: Worktree not tracked by git"
        return 1
    fi
    
    # Verify state file is updated
    if [[ ! -f "$WORKTREE_STATE_FILE" ]]; then
        echo "ERROR: Worktree state file not created"
        return 1
    fi
    
    # Check state content
    local state_status
    state_status=$(jq -r '.worktrees["phase-1-task-1"].status' "$WORKTREE_STATE_FILE")
    if [[ "$state_status" != "active" ]]; then
        echo "ERROR: Worktree state not set correctly: $state_status"
        return 1
    fi
    
    # Verify worktree content matches main
    cd "$worktree_path"
    if [[ ! -f "README.md" ]] || [[ ! -f "src/main.js" ]]; then
        echo "ERROR: Worktree content not properly initialized"
        return 1
    fi
    
    # Test that we can make changes in worktree
    echo "worktree change" > worktree-test.txt
    git add worktree-test.txt
    git commit -m "Test commit in worktree"
    
    # Verify changes are isolated
    cd "$TEST_REPO"
    if [[ -f "worktree-test.txt" ]]; then
        echo "ERROR: Worktree changes leaked to main repository"
        return 1
    fi
    
    log "Basic worktree creation test passed"
    return 0
}

test_worktree_name_validation() {
    log "Testing worktree name validation..."
    
    cd "$TEST_REPO"
    
    # Test valid names
    if ! validate_worktree_name "phase-1-task-1"; then
        echo "ERROR: Valid worktree name rejected"
        return 1
    fi
    
    if ! validate_worktree_name "phase-99-task-999"; then
        echo "ERROR: Valid worktree name rejected"
        return 1
    fi
    
    # Test invalid names
    if validate_worktree_name "invalid-name" 2>/dev/null; then
        echo "ERROR: Invalid worktree name accepted"
        return 1
    fi
    
    if validate_worktree_name "phase-1" 2>/dev/null; then
        echo "ERROR: Incomplete worktree name accepted"
        return 1
    fi
    
    if validate_worktree_name "phase-a-task-1" 2>/dev/null; then
        echo "ERROR: Non-numeric phase accepted"
        return 1
    fi
    
    log "Worktree name validation test passed"
    return 0
}

test_multiple_worktree_creation() {
    log "Testing multiple worktree creation..."
    
    cd "$TEST_REPO"
    
    # Create multiple worktrees
    local worktree1 worktree2 worktree3
    worktree1=$(create_worktree 1 1)
    worktree2=$(create_worktree 1 2)
    worktree3=$(create_worktree 2 1)
    
    # Verify all directories exist
    for worktree in "$worktree1" "$worktree2" "$worktree3"; do
        if [[ ! -d "$worktree" ]]; then
            echo "ERROR: Worktree not created: $worktree"
            return 1
        fi
    done
    
    # Verify all are tracked in state
    local count
    count=$(jq '.worktrees | length' "$WORKTREE_STATE_FILE")
    if [[ "$count" != "3" ]]; then
        echo "ERROR: Expected 3 worktrees in state, found $count"
        return 1
    fi
    
    # Verify different branches
    cd "$worktree1"
    local branch1
    branch1=$(git branch --show-current)
    
    cd "$worktree2"
    local branch2
    branch2=$(git branch --show-current)
    
    if [[ "$branch1" == "$branch2" ]]; then
        echo "ERROR: Worktrees using same branch: $branch1"
        return 1
    fi
    
    log "Multiple worktree creation test passed"
    return 0
}

# =============================================================================
# Isolation Verification Tests
# =============================================================================

test_worktree_isolation() {
    log "Testing worktree isolation..."
    
    cd "$TEST_REPO"
    
    # Create two worktrees
    local worktree1 worktree2
    worktree1=$(create_worktree 1 1)
    worktree2=$(create_worktree 1 2)
    
    # Make changes in first worktree
    cd "$worktree1"
    echo "change from worktree 1" > isolation-test-1.txt
    git add isolation-test-1.txt
    git commit -m "Change from worktree 1"
    
    # Make different changes in second worktree
    cd "$worktree2"
    echo "change from worktree 2" > isolation-test-2.txt
    git add isolation-test-2.txt
    git commit -m "Change from worktree 2"
    
    # Verify isolation: changes should not appear in other worktrees
    cd "$worktree1"
    if [[ -f "isolation-test-2.txt" ]]; then
        echo "ERROR: Worktree 2 changes leaked to worktree 1"
        return 1
    fi
    
    cd "$worktree2"
    if [[ -f "isolation-test-1.txt" ]]; then
        echo "ERROR: Worktree 1 changes leaked to worktree 2"
        return 1
    fi
    
    # Verify main repository is isolated
    cd "$TEST_REPO"
    if [[ -f "isolation-test-1.txt" ]] || [[ -f "isolation-test-2.txt" ]]; then
        echo "ERROR: Worktree changes leaked to main repository"
        return 1
    fi
    
    log "Worktree isolation test passed"
    return 0
}

test_state_isolation() {
    log "Testing state file isolation per worktree..."
    
    cd "$TEST_REPO"
    
    # Create worktree and verify state isolation
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    # Set current context
    export CLAUDE_CURRENT_PHASE=1
    export CLAUDE_CURRENT_TASK=1
    
    # Test isolation enforcement
    cd "$worktree_path"
    if ! enforce_worktree_isolation; then
        echo "ERROR: Worktree isolation enforcement failed in correct worktree"
        return 1
    fi
    
    # Test violation detection
    cd "$TEST_REPO"
    if enforce_worktree_isolation 2>/dev/null; then
        echo "ERROR: Worktree isolation violation not detected"
        return 1
    fi
    
    # Test with wrong worktree
    local wrong_worktree
    wrong_worktree=$(create_worktree 2 1)
    cd "$wrong_worktree"
    if enforce_worktree_isolation 2>/dev/null; then
        echo "ERROR: Wrong worktree isolation violation not detected"
        return 1
    fi
    
    log "State isolation test passed"
    return 0
}

# =============================================================================
# Concurrent Operations Tests
# =============================================================================

test_concurrent_worktree_operations() {
    log "Testing concurrent worktree operations..."
    
    cd "$TEST_REPO"
    
    # Start multiple worktree creation operations concurrently
    local pids=()
    local results=()
    
    # Function to create worktree and report result
    create_worktree_async() {
        local phase=$1
        local task=$2
        local result_file=$3
        
        if create_worktree "$phase" "$task" >/dev/null 2>&1; then
            echo "success" > "$result_file"
        else
            echo "failed" > "$result_file"
        fi
    }
    
    # Start concurrent operations
    for i in {1..3}; do
        local result_file="$TEMP_TEST_DIR/result_$i"
        create_worktree_async 1 "$i" "$result_file" &
        pids+=($!)
        results+=("$result_file")
    done
    
    # Wait for all operations to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Check results
    local success_count=0
    for result_file in "${results[@]}"; do
        if [[ -f "$result_file" ]] && [[ "$(cat "$result_file")" == "success" ]]; then
            ((success_count++))
        fi
    done
    
    if [[ "$success_count" != "3" ]]; then
        echo "ERROR: Expected 3 successful concurrent operations, got $success_count"
        return 1
    fi
    
    # Verify state consistency
    local final_count
    final_count=$(jq '.worktrees | length' "$WORKTREE_STATE_FILE")
    if [[ "$final_count" != "3" ]]; then
        echo "ERROR: State inconsistency after concurrent operations: expected 3, got $final_count"
        return 1
    fi
    
    log "Concurrent worktree operations test passed"
    return 0
}

test_concurrent_state_access() {
    log "Testing concurrent state file access..."
    
    cd "$TEST_REPO"
    
    # Create initial worktree
    create_worktree 1 1 >/dev/null
    
    # Function to update state concurrently
    update_state_async() {
        local worktree_name=$1
        local iteration=$2
        local result_file=$3
        
        if update_worktree_state "$worktree_name" "test-$iteration" "test-branch-$iteration" "/test/path/$iteration"; then
            echo "success" > "$result_file"
        else
            echo "failed" > "$result_file"
        fi
    }
    
    # Start concurrent state updates
    local pids=()
    local results=()
    
    for i in {1..5}; do
        local result_file="$TEMP_TEST_DIR/state_result_$i"
        update_state_async "phase-1-task-1" "$i" "$result_file" &
        pids+=($!)
        results+=("$result_file")
    done
    
    # Wait for completion
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Check results - all should succeed due to locking
    local success_count=0
    for result_file in "${results[@]}"; do
        if [[ -f "$result_file" ]] && [[ "$(cat "$result_file")" == "success" ]]; then
            ((success_count++))
        fi
    done
    
    if [[ "$success_count" != "5" ]]; then
        echo "ERROR: Expected 5 successful state updates, got $success_count"
        return 1
    fi
    
    # Verify state file integrity
    if ! jq empty "$WORKTREE_STATE_FILE" 2>/dev/null; then
        echo "ERROR: State file corrupted by concurrent access"
        return 1
    fi
    
    log "Concurrent state access test passed"
    return 0
}

# =============================================================================
# Merge and Integration Tests
# =============================================================================

test_worktree_merge() {
    log "Testing worktree merge operations..."
    
    cd "$TEST_REPO"
    
    # Create worktree and make changes
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    cd "$worktree_path"
    echo "Feature implementation" > feature.txt
    git add feature.txt
    git commit -m "Implement feature in worktree"
    
    # Test merge
    cd "$TEST_REPO"
    if ! merge_worktree "phase-1-task-1" "main" "false"; then
        echo "ERROR: Worktree merge failed"
        return 1
    fi
    
    # Verify merge result
    if [[ ! -f "feature.txt" ]]; then
        echo "ERROR: Merged changes not present in main branch"
        return 1
    fi
    
    # Verify state update
    local status
    status=$(jq -r '.worktrees["phase-1-task-1"].status' "$WORKTREE_STATE_FILE")
    if [[ "$status" != "merged" ]]; then
        echo "ERROR: Worktree status not updated after merge: $status"
        return 1
    fi
    
    log "Worktree merge test passed"
    return 0
}

test_merge_conflict_handling() {
    log "Testing merge conflict handling..."
    
    cd "$TEST_REPO"
    
    # Modify main branch
    echo "main branch change" > conflict.txt
    git add conflict.txt
    git commit -m "Change in main branch"
    
    # Create worktree with conflicting change
    local worktree_path
    worktree_path=$(create_worktree 1 1 "HEAD~1")  # Create from previous commit
    
    cd "$worktree_path"
    echo "worktree branch change" > conflict.txt
    git add conflict.txt
    git commit -m "Conflicting change in worktree"
    
    # Attempt merge (should fail gracefully)
    cd "$TEST_REPO"
    if merge_worktree "phase-1-task-1" "main" "false" 2>/dev/null; then
        echo "ERROR: Merge should have failed due to conflicts"
        return 1
    fi
    
    # Verify repository is left in clean state
    local status
    status=$(git status --porcelain)
    if [[ -n "$status" ]]; then
        echo "ERROR: Repository left in dirty state after failed merge"
        return 1
    fi
    
    log "Merge conflict handling test passed"
    return 0
}

# =============================================================================
# Cleanup and State Management Tests
# =============================================================================

test_worktree_cleanup() {
    log "Testing worktree cleanup operations..."
    
    cd "$TEST_REPO"
    
    # Create and complete worktree
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    cd "$worktree_path"
    echo "completed work" > completed.txt
    git add completed.txt
    git commit -m "Completed work"
    
    # Mark as completed
    cd "$TEST_REPO"
    update_worktree_state "phase-1-task-1" "completed" "feature/phase-1-task-1" "$worktree_path"
    
    # Test cleanup
    if ! cleanup_worktree "phase-1-task-1"; then
        echo "ERROR: Worktree cleanup failed"
        return 1
    fi
    
    # Verify worktree removed
    if [[ -d "$worktree_path" ]]; then
        echo "ERROR: Worktree directory not removed: $worktree_path"
        return 1
    fi
    
    # Verify git worktree tracking removed
    if git worktree list | grep -q "$worktree_path"; then
        echo "ERROR: Worktree still tracked by git after cleanup"
        return 1
    fi
    
    # Verify state cleaned up
    local count
    count=$(jq '.worktrees | length' "$WORKTREE_STATE_FILE")
    if [[ "$count" != "0" ]]; then
        echo "ERROR: Worktree not removed from state file"
        return 1
    fi
    
    log "Worktree cleanup test passed"
    return 0
}

test_bulk_cleanup() {
    log "Testing bulk cleanup of completed worktrees..."
    
    cd "$TEST_REPO"
    
    # Create multiple completed worktrees
    for i in {1..3}; do
        local worktree_path
        worktree_path=$(create_worktree 1 "$i")
        update_worktree_state "phase-1-task-$i" "completed" "feature/phase-1-task-$i" "$worktree_path"
    done
    
    # Create one active worktree
    create_worktree 2 1 >/dev/null
    
    # Verify initial state
    local total_count
    total_count=$(jq '.worktrees | length' "$WORKTREE_STATE_FILE")
    if [[ "$total_count" != "4" ]]; then
        echo "ERROR: Expected 4 worktrees before cleanup, found $total_count"
        return 1
    fi
    
    # Run bulk cleanup
    if ! cleanup_completed_worktrees; then
        echo "ERROR: Bulk cleanup failed"
        return 1
    fi
    
    # Verify only active worktree remains
    local remaining_count
    remaining_count=$(jq '.worktrees | length' "$WORKTREE_STATE_FILE")
    if [[ "$remaining_count" != "1" ]]; then
        echo "ERROR: Expected 1 remaining worktree after cleanup, found $remaining_count"
        return 1
    fi
    
    # Verify remaining worktree is the active one
    local remaining_status
    remaining_status=$(jq -r '.worktrees["phase-2-task-1"].status' "$WORKTREE_STATE_FILE")
    if [[ "$remaining_status" != "active" ]]; then
        echo "ERROR: Remaining worktree is not active: $remaining_status"
        return 1
    fi
    
    log "Bulk cleanup test passed"
    return 0
}

# =============================================================================
# Contamination Prevention Tests
# =============================================================================

test_cross_worktree_contamination_prevention() {
    log "Testing cross-worktree contamination prevention..."
    
    cd "$TEST_REPO"
    
    # Create two worktrees
    local worktree1 worktree2
    worktree1=$(create_worktree 1 1)
    worktree2=$(create_worktree 1 2)
    
    # Set up phase/task context for first worktree
    export CLAUDE_CURRENT_PHASE=1
    export CLAUDE_CURRENT_TASK=1
    
    # Test working in correct worktree
    cd "$worktree1"
    if ! enforce_worktree_isolation; then
        echo "ERROR: Isolation enforcement failed in correct worktree"
        return 1
    fi
    
    # Test contamination detection when working in wrong worktree
    cd "$worktree2"
    if enforce_worktree_isolation 2>/dev/null; then
        echo "ERROR: Contamination not detected when in wrong worktree"
        return 1
    fi
    
    # Test main repository contamination detection
    cd "$TEST_REPO"
    if enforce_worktree_isolation 2>/dev/null; then
        echo "ERROR: Main repository contamination not detected"
        return 1
    fi
    
    # Test with changed context
    export CLAUDE_CURRENT_PHASE=1
    export CLAUDE_CURRENT_TASK=2
    
    cd "$worktree2"
    if ! enforce_worktree_isolation; then
        echo "ERROR: Isolation enforcement failed after context change"
        return 1
    fi
    
    cd "$worktree1"
    if enforce_worktree_isolation 2>/dev/null; then
        echo "ERROR: Contamination not detected after context change"
        return 1
    fi
    
    log "Cross-worktree contamination prevention test passed"
    return 0
}

test_state_contamination_prevention() {
    log "Testing state file contamination prevention..."
    
    cd "$TEST_REPO"
    
    # Create worktrees
    create_worktree 1 1 >/dev/null
    create_worktree 1 2 >/dev/null
    
    # Test state access patterns
    local original_state
    original_state=$(cat "$WORKTREE_STATE_FILE")
    
    # Simulate concurrent state modifications
    local temp_state="$TEMP_TEST_DIR/temp_state.json"
    echo "$original_state" | jq '.worktrees["phase-1-task-1"].contaminated = true' > "$temp_state"
    
    # Attempt to overwrite state file directly (should be prevented by validation)
    if ! cp "$temp_state" "$WORKTREE_STATE_FILE"; then
        echo "ERROR: Failed to set up contamination test"
        return 1
    fi
    
    # Verify state validation catches contamination
    if validate_worktree "phase-1-task-1" 2>/dev/null; then
        echo "ERROR: State contamination not detected by validation"
        return 1
    fi
    
    # Restore clean state
    echo "$original_state" > "$WORKTREE_STATE_FILE"
    
    # Verify recovery
    if ! validate_worktree "phase-1-task-1"; then
        echo "ERROR: State not properly restored after contamination"
        return 1
    fi
    
    log "State contamination prevention test passed"
    return 0
}

# =============================================================================
# State Tracking Tests
# =============================================================================

test_worktree_state_tracking() {
    log "Testing comprehensive worktree state tracking..."
    
    cd "$TEST_REPO"
    
    # Test state transitions
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    # Verify initial state
    local status
    status=$(get_worktree_status "phase-1-task-1")
    if [[ "$status" != "active" ]]; then
        echo "ERROR: Initial worktree status incorrect: $status"
        return 1
    fi
    
    # Test status updates
    update_worktree_state "phase-1-task-1" "in_progress" "feature/phase-1-task-1" "$worktree_path"
    status=$(get_worktree_status "phase-1-task-1")
    if [[ "$status" != "in_progress" ]]; then
        echo "ERROR: Status update failed: expected 'in_progress', got '$status'"
        return 1
    fi
    
    # Test active worktree tracking
    set_active_worktree "phase-1-task-1"
    local active
    active=$(get_active_worktree)
    if [[ "$active" != "phase-1-task-1" ]]; then
        echo "ERROR: Active worktree not set correctly: $active"
        return 1
    fi
    
    # Test current worktree detection
    cd "$worktree_path"
    local current
    current=$(get_current_worktree)
    if [[ "$current" != "phase-1-task-1" ]]; then
        echo "ERROR: Current worktree detection failed: $current"
        return 1
    fi
    
    # Test state file format
    if ! jq -e '.worktrees["phase-1-task-1"] | has("status") and has("branch") and has("path") and has("created_at") and has("updated_at")' "$WORKTREE_STATE_FILE" >/dev/null; then
        echo "ERROR: State file missing required fields"
        return 1
    fi
    
    log "Worktree state tracking test passed"
    return 0
}

test_state_persistence() {
    log "Testing state persistence across sessions..."
    
    cd "$TEST_REPO"
    
    # Create worktree and capture state
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    local original_state
    original_state=$(cat "$WORKTREE_STATE_FILE")
    
    # Simulate pipeline restart by clearing environment and reloading
    unset CLAUDE_PIPELINE_ROOT WORKTREE_BASE_DIR WORKTREE_STATE_FILE
    
    # Reload environment
    export CLAUDE_PIPELINE_ROOT="$(pwd)"
    export WORKTREE_BASE_DIR="$(pwd)/worktrees"
    export WORKTREE_STATE_FILE="$(pwd)/config/worktree-state.json"
    
    # Verify state persistence
    local restored_state
    restored_state=$(cat "$WORKTREE_STATE_FILE")
    
    if [[ "$original_state" != "$restored_state" ]]; then
        echo "ERROR: State not persistent across sessions"
        return 1
    fi
    
    # Verify worktree validation still works
    if ! validate_worktree "phase-1-task-1"; then
        echo "ERROR: Worktree validation failed after session restart"
        return 1
    fi
    
    # Verify worktree operations still work
    if ! list_worktrees >/dev/null; then
        echo "ERROR: Worktree listing failed after session restart"
        return 1
    fi
    
    log "State persistence test passed"
    return 0
}

# =============================================================================
# Main Test Execution
# =============================================================================

print_header() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                    WORKTREE ISOLATION TEST SUITE${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Testing worktree creation, management, isolation, and contamination prevention"
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
    
    # Setup
    setup_test_repo
    
    # Worktree Creation and Management Tests
    run_test "Basic Worktree Creation" test_worktree_creation
    run_test "Worktree Name Validation" test_worktree_name_validation
    run_test "Multiple Worktree Creation" test_multiple_worktree_creation
    
    # Isolation Verification Tests
    run_test "Worktree Isolation" test_worktree_isolation
    run_test "State Isolation" test_state_isolation
    
    # Concurrent Operations Tests
    run_test "Concurrent Worktree Operations" test_concurrent_worktree_operations
    run_test "Concurrent State Access" test_concurrent_state_access
    
    # Merge and Integration Tests
    run_test "Worktree Merge" test_worktree_merge
    run_test "Merge Conflict Handling" test_merge_conflict_handling
    
    # Cleanup and State Management Tests
    run_test "Worktree Cleanup" test_worktree_cleanup
    run_test "Bulk Cleanup" test_bulk_cleanup
    
    # Contamination Prevention Tests
    run_test "Cross-Worktree Contamination Prevention" test_cross_worktree_contamination_prevention
    run_test "State Contamination Prevention" test_state_contamination_prevention
    
    # State Tracking Tests
    run_test "Worktree State Tracking" test_worktree_state_tracking
    run_test "State Persistence" test_state_persistence
    
    print_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi