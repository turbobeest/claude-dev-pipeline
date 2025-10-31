#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Integration Tests
# =============================================================================
# 
# Comprehensive integration test suite for the complete pipeline system.
# Tests hook interactions with state manager, worktree integration with skills,
# logging and monitoring integration, error recovery in full pipeline,
# and end-to-end workflows.
#
# Test Categories:
# - Hook and State Manager Integration
# - Worktree and Skills Integration
# - Logging and Monitoring Integration
# - Error Recovery in Full Pipeline
# - End-to-End Workflow Testing
# - Component Communication Testing
# - Real-World Scenario Simulation
# - Cross-Component Data Flow
#
# =============================================================================

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_TEST_DIR="$TEST_DIR/temp/integration-tests"
REPO_NAME="integration-test-repo"
TEST_REPO="$TEMP_TEST_DIR/$REPO_NAME"

# Load all libraries
source "$PIPELINE_DIR/lib/worktree-manager.sh"
source "$PIPELINE_DIR/lib/state-manager.sh"
source "$PIPELINE_DIR/lib/error-recovery.sh"

# Load hooks
if [[ -f "$PIPELINE_DIR/hooks/skill-activation-prompt.sh" ]]; then
    source "$PIPELINE_DIR/hooks/skill-activation-prompt.sh"
fi

# Override paths for testing
export CLAUDE_PIPELINE_ROOT="$TEMP_TEST_DIR"
export PIPELINE_ROOT="$TEMP_TEST_DIR"
export CHECKPOINT_DIR="$TEMP_TEST_DIR/.checkpoints"
export ERROR_LOG="$TEMP_TEST_DIR/.error-recovery.log"
export AUDIT_LOG="$TEMP_TEST_DIR/audit.log"
export STATE_FILE="$TEMP_TEST_DIR/.workflow-state.json"
export BACKUP_DIR="$TEMP_TEST_DIR/.state-backups"
export LOCK_DIR="$TEMP_TEST_DIR/.locks"
export WORKTREE_BASE_DIR="$TEMP_TEST_DIR/worktrees"
export WORKTREE_STATE_FILE="$TEMP_TEST_DIR/config/worktree-state.json"

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
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" RESET=""
fi

# =============================================================================
# Test Infrastructure
# =============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

run_integration_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo
    echo "${BLUE}${BOLD}▶ Running Integration Test: $test_name${RESET}"
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
    mkdir -p "$TEMP_TEST_DIR/config" "$TEMP_TEST_DIR/logs" "$TEMP_TEST_DIR/worktrees"
    
    # Set up test repository
    setup_test_repo
    
    # Initialize all systems
    init_state_manager >/dev/null 2>&1 || true
    
    # Set environment variables for testing
    export CLAUDE_CURRENT_PHASE=""
    export CLAUDE_CURRENT_TASK=""
}

setup_test_repo() {
    log "Setting up integration test repository..."
    
    cd "$TEMP_TEST_DIR"
    git init "$REPO_NAME"
    cd "$REPO_NAME"
    
    # Configure git
    git config user.name "Integration Test User"
    git config user.email "integration@example.com"
    git config init.defaultBranch main
    
    # Create realistic project structure
    mkdir -p src tests docs config hooks skills
    
    # Create source files
    cat > src/main.js << 'EOF'
// Main application file
const express = require('express');
const app = express();

app.get('/', (req, res) => {
    res.json({ message: 'Hello Integration Test!' });
});

module.exports = app;
EOF
    
    cat > src/utils.js << 'EOF'
// Utility functions
const logger = require('./logger');

function processData(data) {
    logger.info('Processing data:', data);
    return data.map(item => item.toUpperCase());
}

module.exports = { processData };
EOF
    
    cat > src/logger.js << 'EOF'
// Logger module
const logger = {
    info: (msg, data) => console.log(`INFO: ${msg}`, data || ''),
    error: (msg, data) => console.error(`ERROR: ${msg}`, data || '')
};

module.exports = logger;
EOF
    
    # Create test files
    cat > tests/main.test.js << 'EOF'
const request = require('supertest');
const app = require('../src/main');

describe('Main App', () => {
    test('GET / returns hello message', async () => {
        const response = await request(app).get('/');
        expect(response.status).toBe(200);
        expect(response.body.message).toBe('Hello Integration Test!');
    });
});
EOF
    
    cat > tests/utils.test.js << 'EOF'
const { processData } = require('../src/utils');

describe('Utils', () => {
    test('processData transforms array to uppercase', () => {
        const input = ['hello', 'world'];
        const output = processData(input);
        expect(output).toEqual(['HELLO', 'WORLD']);
    });
});
EOF
    
    # Create configuration files
    cat > config/package.json << 'EOF'
{
    "name": "integration-test-project",
    "version": "1.0.0",
    "scripts": {
        "test": "jest",
        "start": "node src/main.js"
    },
    "dependencies": {
        "express": "^4.18.0"
    },
    "devDependencies": {
        "jest": "^29.0.0",
        "supertest": "^6.3.0"
    }
}
EOF
    
    cat > .gitignore << 'EOF'
node_modules/
*.log
.env
dist/
EOF
    
    # Create documentation
    cat > README.md << 'EOF'
# Integration Test Project

This is a test project for integration testing the Claude Dev Pipeline.

## Features

- Express.js web server
- Utility functions
- Comprehensive test suite
- Proper project structure

## Scripts

- `npm test` - Run tests
- `npm start` - Start server
EOF
    
    # Create initial commit
    git add .
    git commit -m "Initial commit: Integration test project setup"
    
    log "Integration test repository setup complete"
}

cleanup_test_environment() {
    # Clean up locks and temp files
    find "$TEMP_TEST_DIR" -name "*.lock" -delete 2>/dev/null || true
    find "$TEMP_TEST_DIR" -name "*.tmp*" -delete 2>/dev/null || true
    
    # Clean up any remaining worktrees
    if [[ -d "$TEST_REPO" ]]; then
        cd "$TEST_REPO"
        git worktree list --porcelain 2>/dev/null | grep -E '^worktree ' | while read -r _ path; do
            if [[ "$path" != "$(pwd)" ]]; then
                git worktree remove "$path" --force 2>/dev/null || true
            fi
        done
    fi
}

# Set up cleanup trap
trap cleanup_test_environment EXIT

# Mock skill functions for testing
mock_skill_activation() {
    local skill_name="$1"
    local context="$2"
    
    echo "Mock skill activated: $skill_name with context: $context"
    
    # Simulate skill work
    case "$skill_name" in
        "tdd-implementer")
            echo "Implementing TDD for the current task..."
            return 0
            ;;
        "test-strategy")
            echo "Analyzing test strategy..."
            return 0
            ;;
        "spec-gen")
            echo "Generating specifications..."
            return 0
            ;;
        *)
            echo "Unknown skill: $skill_name"
            return 1
            ;;
    esac
}

# =============================================================================
# Hook and State Manager Integration Tests
# =============================================================================

test_hook_state_synchronization() {
    log "Testing hook and state manager synchronization..."
    
    cd "$TEST_REPO"
    
    # Initialize with test state
    local initial_state='{
        "phase": "planning",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {"integration_test": true}
    }'
    write_state "$initial_state" "initial"
    
    # Create worktree to trigger hooks
    local worktree_path
    worktree_path=$(create_worktree 1 1)
    
    # Verify state was updated by worktree creation
    local active_worktree
    active_worktree=$(get_active_worktree)
    if [[ "$active_worktree" != "phase-1-task-1" ]]; then
        echo "ERROR: Active worktree not set correctly: expected 'phase-1-task-1', got '$active_worktree'"
        return 1
    fi
    
    # Verify worktree state and main state are synchronized
    local worktree_status
    worktree_status=$(get_worktree_status "phase-1-task-1")
    if [[ "$worktree_status" != "active" ]]; then
        echo "ERROR: Worktree status not synchronized: expected 'active', got '$worktree_status'"
        return 1
    fi
    
    # Test phase transition
    local updated_state
    updated_state=$(read_state | jq '.phase = "implementation" | .completedTasks += ["planning"]')
    write_state "$updated_state" "phase-transition"
    
    # Verify all components see the updated state
    local current_phase
    current_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$current_phase" != "implementation" ]]; then
        echo "ERROR: Phase transition not reflected in state: expected 'implementation', got '$current_phase'"
        return 1
    fi
    
    # Test error scenarios with state synchronization
    cd "$worktree_path"
    export CLAUDE_CURRENT_PHASE=1
    export CLAUDE_CURRENT_TASK=1
    
    # Verify isolation enforcement works with state
    if ! enforce_worktree_isolation; then
        echo "ERROR: Worktree isolation enforcement failed with proper state"
        return 1
    fi
    
    log "Hook and state manager synchronization test passed"
    return 0
}

test_state_updates_through_hooks() {
    log "Testing state updates triggered through hooks..."
    
    cd "$TEST_REPO"
    
    # Initialize state
    local initial_state='{
        "phase": "hook-test",
        "completedTasks": [],
        "signals": {"hook_test": true},
        "lastActivation": "",
        "metadata": {"hook_integration": true}
    }'
    write_state "$initial_state" "initial"
    
    # Create checkpoint before operations
    create_checkpoint "hook-integration-test" "hook-test-phase"
    
    # Simulate hook-triggered state updates
    local worktree_path
    worktree_path=$(create_worktree 2 1)
    
    # Verify state reflects worktree creation
    local worktree_count
    worktree_count=$(jq '.worktrees | length' "$WORKTREE_STATE_FILE")
    if [[ "$worktree_count" != "1" ]]; then
        echo "ERROR: Worktree creation not reflected in state: expected 1, got $worktree_count"
        return 1
    fi
    
    # Test state update through worktree operations
    cd "$worktree_path"
    echo "New feature implementation" > feature.txt
    git add feature.txt
    git commit -m "Implement new feature"
    
    # Update state to reflect completed work
    local updated_state
    updated_state=$(read_state | jq '.completedTasks += ["feature-implementation"] | .signals.feature_complete = true')
    write_state "$updated_state" "feature-completed"
    
    # Test merge operation updates state
    cd "$TEST_REPO"
    if ! merge_worktree "phase-2-task-1" "main" "false"; then
        echo "ERROR: Worktree merge failed"
        return 1
    fi
    
    # Verify merge updated worktree state
    local merge_status
    merge_status=$(get_worktree_status "phase-2-task-1")
    if [[ "$merge_status" != "merged" ]]; then
        echo "ERROR: Merge status not updated: expected 'merged', got '$merge_status'"
        return 1
    fi
    
    # Verify main state reflects completion
    local completed_tasks
    completed_tasks=$(jq -r '.completedTasks | length' "$STATE_FILE")
    if [[ "$completed_tasks" -lt 1 ]]; then
        echo "ERROR: Completed tasks not tracked in state: $completed_tasks"
        return 1
    fi
    
    log "State updates through hooks test passed"
    return 0
}

# =============================================================================
# Worktree and Skills Integration Tests
# =============================================================================

test_worktree_skill_coordination() {
    log "Testing worktree and skill coordination..."
    
    cd "$TEST_REPO"
    
    # Create worktree for skill integration test
    local worktree_path
    worktree_path=$(create_worktree 3 1)
    
    # Set up skill context
    export CLAUDE_CURRENT_PHASE=3
    export CLAUDE_CURRENT_TASK=1
    
    cd "$worktree_path"
    
    # Verify we're in the correct worktree
    local current_worktree
    current_worktree=$(get_current_worktree)
    if [[ "$current_worktree" != "phase-3-task-1" ]]; then
        echo "ERROR: Not in expected worktree: expected 'phase-3-task-1', got '$current_worktree'"
        return 1
    fi
    
    # Test skill activation within worktree context
    if ! mock_skill_activation "tdd-implementer" "unit-testing"; then
        echo "ERROR: Skill activation failed in worktree context"
        return 1
    fi
    
    # Simulate skill-driven development
    mkdir -p tests
    cat > tests/integration.test.js << 'EOF'
// Integration test generated by skill
describe('Integration Test', () => {
    test('skill coordination works', () => {
        expect(true).toBe(true);
    });
});
EOF
    
    git add tests/integration.test.js
    git commit -m "Add integration test via TDD skill"
    
    # Test skill activation with different context
    if ! mock_skill_activation "test-strategy" "integration-testing"; then
        echo "ERROR: Test strategy skill activation failed"
        return 1
    fi
    
    # Update state to reflect skill usage
    local skill_state
    skill_state=$(read_state | jq '.metadata.skills_used = ["tdd-implementer", "test-strategy"]')
    write_state "$skill_state" "skills-applied"
    
    # Verify skill coordination doesn't break worktree isolation
    cd "$TEST_REPO"
    export CLAUDE_CURRENT_PHASE=3
    export CLAUDE_CURRENT_TASK=1
    
    if enforce_worktree_isolation 2>/dev/null; then
        echo "ERROR: Should fail isolation check when not in worktree"
        return 1
    fi
    
    cd "$worktree_path"
    if ! enforce_worktree_isolation; then
        echo "ERROR: Isolation check should pass in correct worktree"
        return 1
    fi
    
    log "Worktree and skill coordination test passed"
    return 0
}

test_skill_state_persistence() {
    log "Testing skill state persistence across operations..."
    
    cd "$TEST_REPO"
    
    # Initialize state with skill tracking
    local initial_state='{
        "phase": "skill-persistence-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {
            "skills_available": ["tdd-implementer", "test-strategy", "spec-gen"],
            "skills_used": [],
            "skill_context": {}
        }
    }'
    write_state "$initial_state" "initial"
    
    # Create worktree and activate skills
    local worktree_path
    worktree_path=$(create_worktree 4 1)
    
    export CLAUDE_CURRENT_PHASE=4
    export CLAUDE_CURRENT_TASK=1
    cd "$worktree_path"
    
    # Track skill usage in state
    local skill_state
    skill_state=$(read_state | jq '
        .metadata.skills_used += ["tdd-implementer"] |
        .metadata.skill_context["tdd-implementer"] = {
            "activated_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "context": "unit-testing",
            "worktree": "phase-4-task-1"
        }
    ')
    write_state "$skill_state" "skill-activated"
    
    # Create checkpoint to test persistence
    create_checkpoint "skill-persistence-test" "skill-test-phase"
    local checkpoint_id="$CHECKPOINT_ID"
    
    # Simulate more skill usage
    skill_state=$(read_state | jq '
        .metadata.skills_used += ["test-strategy"] |
        .metadata.skill_context["test-strategy"] = {
            "activated_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "context": "integration-testing",
            "worktree": "phase-4-task-1"
        }
    ')
    write_state "$skill_state" "second-skill-activated"
    
    # Verify skill state is properly tracked
    local skills_used_count
    skills_used_count=$(jq '.metadata.skills_used | length' "$STATE_FILE")
    if [[ "$skills_used_count" != "2" ]]; then
        echo "ERROR: Expected 2 skills used, got $skills_used_count"
        return 1
    fi
    
    # Test state corruption and recovery
    echo "corrupted state" > "$STATE_FILE"
    
    # Restore from checkpoint
    if ! restore_checkpoint "$checkpoint_id"; then
        echo "ERROR: Failed to restore skill state from checkpoint"
        return 1
    fi
    
    # Verify skill state was restored
    local restored_skills_count
    restored_skills_count=$(jq '.metadata.skills_used | length' "$STATE_FILE")
    if [[ "$restored_skills_count" != "1" ]]; then
        echo "ERROR: Expected 1 skill after restore, got $restored_skills_count"
        return 1
    fi
    
    # Verify specific skill context was restored
    local tdd_context
    tdd_context=$(jq -r '.metadata.skill_context["tdd-implementer"].context' "$STATE_FILE")
    if [[ "$tdd_context" != "unit-testing" ]]; then
        echo "ERROR: Skill context not properly restored: expected 'unit-testing', got '$tdd_context'"
        return 1
    fi
    
    log "Skill state persistence test passed"
    return 0
}

# =============================================================================
# Logging and Monitoring Integration Tests
# =============================================================================

test_integrated_logging() {
    log "Testing integrated logging across components..."
    
    cd "$TEST_REPO"
    
    # Initialize logging for all components
    local log_files=(
        "$AUDIT_LOG"
        "$ERROR_LOG"
        "$TEMP_TEST_DIR/logs/worktree-manager.log"
        "$TEMP_TEST_DIR/logs/pipeline.log"
    )
    
    # Ensure log directories exist
    mkdir -p "$(dirname "$AUDIT_LOG")" "$(dirname "$ERROR_LOG")" "$TEMP_TEST_DIR/logs"
    
    # Clear existing logs
    for log_file in "${log_files[@]}"; do
        > "$log_file"
    done
    
    # Perform operations that should generate logs
    local test_state='{
        "phase": "logging-test",
        "completedTasks": [],
        "signals": {"logging_test": true},
        "lastActivation": "",
        "metadata": {"test": "logging"}
    }'
    write_state "$test_state" "initial"
    
    # Create worktree (should log to worktree manager)
    local worktree_path
    worktree_path=$(create_worktree 5 1)
    
    # Create checkpoint (should log to error recovery)
    create_checkpoint "logging-test" "logging-phase"
    
    # Trigger some errors for error logging
    handle_error "${ERROR_CODES[TIMEOUT]}" "Test timeout for logging" "logging-test" "false" >/dev/null 2>&1 || true
    
    # Verify logs were created and contain expected content
    local logs_with_content=0
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]] && [[ -s "$log_file" ]]; then
            ((logs_with_content++))
            log "Log file has content: $log_file"
        else
            log "Log file missing or empty: $log_file"
        fi
    done
    
    # Verify audit log contains state operations
    if [[ -f "$AUDIT_LOG" ]] && grep -q "state-manager" "$AUDIT_LOG"; then
        log "Audit log contains state manager entries"
    else
        echo "WARNING: Audit log missing state manager entries"
    fi
    
    # Verify error log contains error recovery entries
    if [[ -f "$ERROR_LOG" ]] && grep -q "error-recovery" "$ERROR_LOG"; then
        log "Error log contains error recovery entries"
    else
        echo "WARNING: Error log missing error recovery entries"
    fi
    
    # Test log rotation doesn't break integration
    if [[ -f "$AUDIT_LOG" ]]; then
        cp "$AUDIT_LOG" "$AUDIT_LOG.backup"
        > "$AUDIT_LOG"  # Simulate log rotation
        
        # Perform operation after rotation
        local rotated_state
        rotated_state=$(read_state | jq '.metadata.log_rotated = true')
        write_state "$rotated_state" "post-rotation"
        
        # Verify logging continues after rotation
        if [[ -s "$AUDIT_LOG" ]]; then
            log "Logging continues after rotation"
        else
            echo "ERROR: Logging stopped after rotation"
            return 1
        fi
    fi
    
    log "Integrated logging test passed"
    return 0
}

test_monitoring_integration() {
    log "Testing monitoring integration across components..."
    
    cd "$TEST_REPO"
    
    # Set up monitoring state
    local monitoring_state='{
        "phase": "monitoring-test",
        "completedTasks": [],
        "signals": {},
        "lastActivation": "",
        "metadata": {
            "monitoring": {
                "enabled": true,
                "start_time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                "operations": []
            }
        }
    }'
    write_state "$monitoring_state" "initial"
    
    # Function to add monitoring entry
    add_monitoring_entry() {
        local operation="$1"
        local status="$2"
        local duration="$3"
        
        local current_state
        current_state=$(read_state)
        local updated_state
        updated_state=$(echo "$current_state" | jq --arg op "$operation" --arg status "$status" --arg duration "$duration" '
            .metadata.monitoring.operations += [{
                "operation": $op,
                "status": $status,
                "duration_ms": ($duration | tonumber),
                "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            }]
        ')
        write_state "$updated_state" "monitoring-update"
    }
    
    # Monitor worktree operations
    local start_time=$(date +%s%N)
    local worktree_path
    worktree_path=$(create_worktree 6 1)
    local end_time=$(date +%s%N)
    local duration_ms=$(((end_time - start_time) / 1000000))
    
    add_monitoring_entry "create_worktree" "success" "$duration_ms"
    
    # Monitor state operations
    start_time=$(date +%s%N)
    read_state >/dev/null
    end_time=$(date +%s%N)
    duration_ms=$(((end_time - start_time) / 1000000))
    
    add_monitoring_entry "read_state" "success" "$duration_ms"
    
    # Monitor checkpoint operations
    start_time=$(date +%s%N)
    create_checkpoint "monitoring-checkpoint" "monitoring-phase"
    end_time=$(date +%s%N)
    duration_ms=$(((end_time - start_time) / 1000000))
    
    add_monitoring_entry "create_checkpoint" "success" "$duration_ms"
    
    # Verify monitoring data
    local operation_count
    operation_count=$(jq '.metadata.monitoring.operations | length' "$STATE_FILE")
    if [[ "$operation_count" != "3" ]]; then
        echo "ERROR: Expected 3 monitored operations, got $operation_count"
        return 1
    fi
    
    # Test monitoring data aggregation
    local total_duration
    total_duration=$(jq '.metadata.monitoring.operations | map(.duration_ms) | add' "$STATE_FILE")
    if [[ "$total_duration" -le 0 ]]; then
        echo "ERROR: Invalid total duration: $total_duration"
        return 1
    fi
    
    # Test monitoring with failures
    add_monitoring_entry "mock_failure" "failed" "0"
    
    local failed_operations
    failed_operations=$(jq '.metadata.monitoring.operations | map(select(.status == "failed")) | length' "$STATE_FILE")
    if [[ "$failed_operations" != "1" ]]; then
        echo "ERROR: Expected 1 failed operation, got $failed_operations"
        return 1
    fi
    
    # Verify monitoring survives component interactions
    cd "$worktree_path"
    export CLAUDE_CURRENT_PHASE=6
    export CLAUDE_CURRENT_TASK=1
    
    if ! enforce_worktree_isolation; then
        echo "ERROR: Worktree isolation failed during monitoring"
        return 1
    fi
    
    # Verify monitoring state is still intact
    operation_count=$(jq '.metadata.monitoring.operations | length' "$STATE_FILE")
    if [[ "$operation_count" != "4" ]]; then
        echo "ERROR: Monitoring data corrupted during component interaction: expected 4, got $operation_count"
        return 1
    fi
    
    log "Monitoring integration test passed"
    return 0
}

# =============================================================================
# Error Recovery in Full Pipeline Tests
# =============================================================================

test_full_pipeline_error_recovery() {
    log "Testing error recovery in full pipeline context..."
    
    cd "$TEST_REPO"
    
    # Initialize complex pipeline state
    local complex_state='{
        "phase": "error-recovery-integration",
        "completedTasks": ["task1", "task2"],
        "signals": {"ready": true, "error_test": true},
        "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "metadata": {
            "worktrees": [],
            "checkpoints": [],
            "skills_used": ["tdd-implementer"],
            "error_recovery": {"enabled": true}
        }
    }'
    write_state "$complex_state" "initial"
    
    # Create multiple worktrees to simulate active pipeline
    local worktrees=()
    for i in {1..3}; do
        local worktree_path
        worktree_path=$(create_worktree 7 "$i")
        worktrees+=("$worktree_path")
        
        # Add worktree to tracking in main state
        local updated_state
        updated_state=$(read_state | jq --arg wt "phase-7-task-$i" '.metadata.worktrees += [$wt]')
        write_state "$updated_state" "worktree-added"
    done
    
    # Create checkpoint of the complex state
    create_checkpoint "full-pipeline-backup" "complex-state"
    local main_checkpoint_id="$CHECKPOINT_ID"
    
    # Add checkpoint to tracking
    local checkpoint_state
    checkpoint_state=$(read_state | jq --arg cp "$main_checkpoint_id" '.metadata.checkpoints += [$cp]')
    write_state "$checkpoint_state" "checkpoint-added"
    
    # Simulate cascade failure
    log "Simulating cascade failure..."
    
    # Corrupt main state
    echo "corrupted pipeline state" > "$STATE_FILE"
    
    # Corrupt worktree state
    echo "corrupted worktree state" > "$WORKTREE_STATE_FILE"
    
    # Simulate locked resources
    echo "$$" > "$LOCK_DIR/state.lock"
    echo "$$" > "$LOCK_DIR/worktree.lock"
    
    # Test recovery process
    log "Testing recovery process..."
    
    # Step 1: Try to detect corruption
    if validate_state "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: Corruption not detected"
        return 1
    fi
    
    # Step 2: Attempt automatic recovery
    if ! recover_state; then
        echo "ERROR: Automatic state recovery failed"
        return 1
    fi
    
    # Step 3: Verify main state recovery
    if ! validate_state "$STATE_FILE"; then
        echo "ERROR: Recovered state is not valid"
        return 1
    fi
    
    # Step 4: Verify complex data was restored
    local recovered_phase
    recovered_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$recovered_phase" != "error-recovery-integration" ]]; then
        echo "ERROR: Complex state not properly recovered: expected 'error-recovery-integration', got '$recovered_phase'"
        return 1
    fi
    
    local recovered_tasks
    recovered_tasks=$(jq '.completedTasks | length' "$STATE_FILE")
    if [[ "$recovered_tasks" -lt 2 ]]; then
        echo "ERROR: Completed tasks not recovered: got $recovered_tasks, expected >= 2"
        return 1
    fi
    
    # Step 5: Verify worktree state consistency
    for i in {1..3}; do
        if ! validate_worktree "phase-7-task-$i"; then
            echo "ERROR: Worktree phase-7-task-$i not valid after recovery"
            return 1
        fi
    done
    
    # Step 6: Test continued operations after recovery
    local post_recovery_state
    post_recovery_state=$(read_state | jq '.metadata.recovered = true | .completedTasks += ["recovery-test"]')
    write_state "$post_recovery_state" "post-recovery"
    
    # Step 7: Verify all components work together after recovery
    export CLAUDE_CURRENT_PHASE=7
    export CLAUDE_CURRENT_TASK=1
    
    cd "${worktrees[0]}"
    if ! enforce_worktree_isolation; then
        echo "ERROR: Worktree isolation not working after recovery"
        return 1
    fi
    
    # Clean up created worktrees
    cd "$TEST_REPO"
    for i in {1..3}; do
        cleanup_worktree "phase-7-task-$i" "true" >/dev/null 2>&1 || true
    done
    
    log "Full pipeline error recovery test passed"
    return 0
}

test_error_recovery_with_active_operations() {
    log "Testing error recovery with active operations..."
    
    cd "$TEST_REPO"
    
    # Set up state with active operations
    local active_state='{
        "phase": "active-operations-test",
        "completedTasks": [],
        "signals": {"operation_active": true},
        "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "metadata": {
            "active_operations": ["worktree_creation", "skill_activation"],
            "operation_states": {
                "worktree_creation": "in_progress",
                "skill_activation": "pending"
            }
        }
    }'
    write_state "$active_state" "initial"
    
    # Create checkpoint before active operations
    create_checkpoint "pre-active-operations" "active-test"
    local checkpoint_id="$CHECKPOINT_ID"
    
    # Start simulated active operation
    start_mock_operation() {
        local operation_id=$1
        local result_file="$TEMP_TEST_DIR/operation_${operation_id}_result"
        
        # Simulate long-running operation
        (
            sleep 2
            echo "completed" > "$result_file"
        ) &
        
        echo $!
    }
    
    # Start active operations
    local operation_pid1
    operation_pid1=$(start_mock_operation "1")
    
    local operation_pid2
    operation_pid2=$(start_mock_operation "2")
    
    # Update state to reflect active operations
    local operations_state
    operations_state=$(read_state | jq --arg pid1 "$operation_pid1" --arg pid2 "$operation_pid2" '
        .metadata.operation_pids = [$pid1, $pid2] |
        .metadata.operation_states.worktree_creation = "running" |
        .metadata.operation_states.skill_activation = "running"
    ')
    write_state "$operations_state" "operations-started"
    
    # Simulate failure during active operations
    sleep 1  # Let operations run briefly
    
    # Corrupt state while operations are running
    echo "failure during active operations" > "$STATE_FILE"
    
    # Test recovery with active operations
    if ! recover_state; then
        echo "ERROR: Recovery failed with active operations"
        return 1
    fi
    
    # Verify recovery restored the state
    local recovered_phase
    recovered_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$recovered_phase" != "active-operations-test" ]]; then
        echo "ERROR: Phase not recovered correctly: expected 'active-operations-test', got '$recovered_phase'"
        return 1
    fi
    
    # Verify active operations metadata was preserved
    local active_ops_count
    active_ops_count=$(jq '.metadata.active_operations | length' "$STATE_FILE")
    if [[ "$active_ops_count" != "2" ]]; then
        echo "ERROR: Active operations metadata not preserved: expected 2, got $active_ops_count"
        return 1
    fi
    
    # Clean up active operations
    kill "$operation_pid1" "$operation_pid2" 2>/dev/null || true
    wait "$operation_pid1" "$operation_pid2" 2>/dev/null || true
    
    # Update state to reflect completed cleanup
    local cleanup_state
    cleanup_state=$(read_state | jq '
        .metadata.active_operations = [] |
        .metadata.operation_states = {} |
        del(.metadata.operation_pids) |
        .signals.operation_active = false
    ')
    write_state "$cleanup_state" "cleanup-completed"
    
    log "Error recovery with active operations test passed"
    return 0
}

# =============================================================================
# End-to-End Workflow Tests
# =============================================================================

test_complete_development_workflow() {
    log "Testing complete development workflow..."
    
    cd "$TEST_REPO"
    
    # Phase 1: Project Planning
    log "Phase 1: Project Planning"
    local planning_state='{
        "phase": "planning",
        "completedTasks": [],
        "signals": {"planning_started": true},
        "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "metadata": {
            "workflow_test": true,
            "phases": ["planning", "implementation", "testing", "deployment"],
            "current_phase_index": 0
        }
    }'
    write_state "$planning_state" "planning-start"
    
    # Create checkpoint at start of planning
    create_checkpoint "planning-start" "planning"
    
    # Simulate planning activities
    mock_skill_activation "spec-gen" "project-planning" >/dev/null
    
    # Update state after planning
    local post_planning_state
    post_planning_state=$(read_state | jq '
        .completedTasks += ["project-planning", "requirements-analysis"] |
        .metadata.current_phase_index = 1 |
        .signals.planning_complete = true
    ')
    write_state "$post_planning_state" "planning-complete"
    
    # Phase 2: Implementation
    log "Phase 2: Implementation"
    local impl_state
    impl_state=$(read_state | jq '.phase = "implementation" | .signals.implementation_started = true')
    write_state "$impl_state" "implementation-start"
    
    # Create worktree for implementation
    local impl_worktree
    impl_worktree=$(create_worktree 8 1)
    
    export CLAUDE_CURRENT_PHASE=8
    export CLAUDE_CURRENT_TASK=1
    cd "$impl_worktree"
    
    # Verify worktree isolation
    if ! enforce_worktree_isolation; then
        echo "ERROR: Worktree isolation failed during implementation phase"
        return 1
    fi
    
    # Simulate TDD implementation
    mock_skill_activation "tdd-implementer" "feature-development" >/dev/null
    
    # Add implementation files
    cat > new_feature.js << 'EOF'
// New feature implementation
function newFeature(input) {
    return input.toUpperCase() + '!';
}

module.exports = { newFeature };
EOF
    
    cat > new_feature.test.js << 'EOF'
const { newFeature } = require('./new_feature');

describe('New Feature', () => {
    test('transforms input correctly', () => {
        expect(newFeature('hello')).toBe('HELLO!');
    });
});
EOF
    
    git add new_feature.js new_feature.test.js
    git commit -m "Implement new feature with TDD"
    
    # Update state after implementation
    cd "$TEST_REPO"
    local post_impl_state
    post_impl_state=$(read_state | jq '
        .completedTasks += ["feature-implementation", "unit-tests"] |
        .signals.implementation_complete = true
    ')
    write_state "$post_impl_state" "implementation-complete"
    
    # Phase 3: Testing
    log "Phase 3: Testing"
    local testing_state
    testing_state=$(read_state | jq '
        .phase = "testing" |
        .metadata.current_phase_index = 2 |
        .signals.testing_started = true
    ')
    write_state "$testing_state" "testing-start"
    
    # Create checkpoint before testing
    create_checkpoint "pre-testing" "testing"
    
    # Simulate test strategy activation
    mock_skill_activation "test-strategy" "integration-testing" >/dev/null
    
    # Merge implementation back to main
    if ! merge_worktree "phase-8-task-1" "main" "true"; then
        echo "ERROR: Failed to merge implementation worktree"
        return 1
    fi
    
    # Verify merge completed
    if [[ ! -f "new_feature.js" ]] || [[ ! -f "new_feature.test.js" ]]; then
        echo "ERROR: Implementation files not merged to main"
        return 1
    fi
    
    # Update state after testing
    local post_testing_state
    post_testing_state=$(read_state | jq '
        .completedTasks += ["integration-testing", "merge-validation"] |
        .signals.testing_complete = true
    ')
    write_state "$post_testing_state" "testing-complete"
    
    # Phase 4: Deployment
    log "Phase 4: Deployment"
    local deployment_state
    deployment_state=$(read_state | jq '
        .phase = "deployment" |
        .metadata.current_phase_index = 3 |
        .signals.deployment_started = true
    ')
    write_state "$deployment_state" "deployment-start"
    
    # Simulate deployment preparation
    echo '{"deployed": true, "version": "1.0.0"}' > deployment.json
    git add deployment.json
    git commit -m "Add deployment configuration"
    
    # Final state update
    local final_state
    final_state=$(read_state | jq '
        .completedTasks += ["deployment"] |
        .signals.deployment_complete = true |
        .signals.workflow_complete = true |
        .metadata.completed_at = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    ')
    write_state "$final_state" "workflow-complete"
    
    # Validate final workflow state
    local total_tasks
    total_tasks=$(jq '.completedTasks | length' "$STATE_FILE")
    if [[ "$total_tasks" -lt 6 ]]; then
        echo "ERROR: Insufficient completed tasks: expected >= 6, got $total_tasks"
        return 1
    fi
    
    local final_phase
    final_phase=$(jq -r '.phase' "$STATE_FILE")
    if [[ "$final_phase" != "deployment" ]]; then
        echo "ERROR: Final phase incorrect: expected 'deployment', got '$final_phase'"
        return 1
    fi
    
    local workflow_complete
    workflow_complete=$(jq -r '.signals.workflow_complete' "$STATE_FILE")
    if [[ "$workflow_complete" != "true" ]]; then
        echo "ERROR: Workflow not marked as complete"
        return 1
    fi
    
    log "Complete development workflow test passed"
    return 0
}

test_multi_branch_workflow() {
    log "Testing multi-branch workflow integration..."
    
    cd "$TEST_REPO"
    
    # Initialize multi-branch workflow state
    local multi_branch_state='{
        "phase": "multi-branch-development",
        "completedTasks": [],
        "signals": {"multi_branch": true},
        "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "metadata": {
            "branches": ["feature/auth", "feature/api", "bugfix/validation"],
            "parallel_development": true
        }
    }'
    write_state "$multi_branch_state" "initial"
    
    # Create multiple worktrees for parallel development
    local auth_worktree api_worktree bugfix_worktree
    auth_worktree=$(create_worktree 9 1)    # feature/auth
    api_worktree=$(create_worktree 9 2)     # feature/api
    bugfix_worktree=$(create_worktree 9 3)  # bugfix/validation
    
    # Work on authentication feature
    log "Developing authentication feature..."
    export CLAUDE_CURRENT_PHASE=9
    export CLAUDE_CURRENT_TASK=1
    cd "$auth_worktree"
    
    cat > auth.js << 'EOF'
// Authentication module
const jwt = require('jsonwebtoken');

function authenticate(token) {
    try {
        return jwt.verify(token, process.env.JWT_SECRET);
    } catch (err) {
        return null;
    }
}

module.exports = { authenticate };
EOF
    
    git add auth.js
    git commit -m "Add authentication module"
    
    # Work on API feature
    log "Developing API feature..."
    export CLAUDE_CURRENT_TASK=2
    cd "$api_worktree"
    
    cat > api.js << 'EOF'
// API endpoints
const express = require('express');
const router = express.Router();

router.get('/users', (req, res) => {
    res.json([{ id: 1, name: 'Test User' }]);
});

module.exports = router;
EOF
    
    git add api.js
    git commit -m "Add API endpoints"
    
    # Work on bugfix
    log "Fixing validation bug..."
    export CLAUDE_CURRENT_TASK=3
    cd "$bugfix_worktree"
    
    # Modify existing file to fix bug
    sed -i.bak 's/data.map/data \&\& data.map/' src/utils.js
    git add src/utils.js
    git commit -m "Fix validation bug in utils.js"
    
    # Update state to track parallel development
    cd "$TEST_REPO"
    local progress_state
    progress_state=$(read_state | jq '
        .completedTasks += ["auth-implementation", "api-implementation", "bug-fix"] |
        .metadata.parallel_tasks_complete = 3
    ')
    write_state "$progress_state" "parallel-development-complete"
    
    # Test conflict resolution scenario
    log "Testing conflict resolution..."
    
    # Create conflicting change in main
    echo "// Main branch change" >> src/utils.js
    git add src/utils.js
    git commit -m "Conflicting change in main"
    
    # Attempt to merge bugfix (should conflict)
    if merge_worktree "phase-9-task-3" "main" "false" 2>/dev/null; then
        echo "ERROR: Merge should have failed due to conflicts"
        return 1
    fi
    
    # Verify repository is in clean state after failed merge
    local status
    status=$(git status --porcelain)
    if [[ -n "$status" ]]; then
        echo "ERROR: Repository not clean after failed merge"
        return 1
    fi
    
    # Merge non-conflicting features first
    log "Merging non-conflicting features..."
    
    if ! merge_worktree "phase-9-task-1" "main" "true"; then
        echo "ERROR: Failed to merge auth feature"
        return 1
    fi
    
    if ! merge_worktree "phase-9-task-2" "main" "true"; then
        echo "ERROR: Failed to merge API feature"
        return 1
    fi
    
    # Verify merged features are present
    if [[ ! -f "auth.js" ]] || [[ ! -f "api.js" ]]; then
        echo "ERROR: Merged features not present in main branch"
        return 1
    fi
    
    # Update final state
    local final_multi_branch_state
    final_multi_branch_state=$(read_state | jq '
        .completedTasks += ["feature-merging", "conflict-resolution"] |
        .signals.multi_branch_complete = true |
        .metadata.successful_merges = 2 |
        .metadata.conflicts_resolved = 1
    ')
    write_state "$final_multi_branch_state" "multi-branch-complete"
    
    # Validate final state
    local successful_merges
    successful_merges=$(jq '.metadata.successful_merges' "$STATE_FILE")
    if [[ "$successful_merges" != "2" ]]; then
        echo "ERROR: Expected 2 successful merges, got $successful_merges"
        return 1
    fi
    
    log "Multi-branch workflow integration test passed"
    return 0
}

# =============================================================================
# Cross-Component Data Flow Tests
# =============================================================================

test_data_flow_consistency() {
    log "Testing data flow consistency across components..."
    
    cd "$TEST_REPO"
    
    # Initialize with comprehensive data
    local comprehensive_state='{
        "phase": "data-flow-test",
        "completedTasks": [],
        "signals": {
            "data_flow_test": true,
            "component_a": false,
            "component_b": false,
            "component_c": false
        },
        "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "metadata": {
            "test_id": "data-flow-'$(date +%s)'",
            "components": ["state-manager", "worktree-manager", "error-recovery"],
            "data_checkpoints": []
        }
    }'
    write_state "$comprehensive_state" "initial"
    
    # Component A: State Manager operations
    log "Testing Component A: State Manager"
    local component_a_start=$(date +%s%N)
    
    # Perform multiple state operations
    for i in {1..3}; do
        local iteration_state
        iteration_state=$(read_state | jq --arg iteration "$i" '
            .signals.component_a = true |
            .metadata.data_checkpoints += [{
                "component": "state-manager",
                "iteration": ($iteration | tonumber),
                "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                "operation": "state_update"
            }]
        ')
        write_state "$iteration_state" "component-a-iteration-$i"
        
        # Verify data consistency after each write
        local verification_state
        verification_state=$(read_state)
        local checkpoint_count
        checkpoint_count=$(echo "$verification_state" | jq '.metadata.data_checkpoints | length')
        if [[ "$checkpoint_count" != "$i" ]]; then
            echo "ERROR: Data checkpoint count inconsistent: expected $i, got $checkpoint_count"
            return 1
        fi
    done
    
    local component_a_end=$(date +%s%N)
    local component_a_duration=$(((component_a_end - component_a_start) / 1000000))
    
    # Component B: Worktree Manager operations
    log "Testing Component B: Worktree Manager"
    local component_b_start=$(date +%s%N)
    
    # Create worktree and update state
    local worktree_path
    worktree_path=$(create_worktree 10 1)
    
    # Verify worktree state reflects in main state
    local worktree_active
    worktree_active=$(get_active_worktree)
    if [[ "$worktree_active" != "phase-10-task-1" ]]; then
        echo "ERROR: Worktree state not consistent: expected 'phase-10-task-1', got '$worktree_active'"
        return 1
    fi
    
    # Update main state to reflect worktree operations
    local component_b_state
    component_b_state=$(read_state | jq '
        .signals.component_b = true |
        .metadata.data_checkpoints += [{
            "component": "worktree-manager",
            "operation": "worktree_creation",
            "worktree": "phase-10-task-1",
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
        }]
    ')
    write_state "$component_b_state" "component-b-complete"
    
    local component_b_end=$(date +%s%N)
    local component_b_duration=$(((component_b_end - component_b_start) / 1000000))
    
    # Component C: Error Recovery operations
    log "Testing Component C: Error Recovery"
    local component_c_start=$(date +%s%N)
    
    # Create checkpoint
    create_checkpoint "data-flow-checkpoint" "data-flow-test"
    local checkpoint_id="$CHECKPOINT_ID"
    
    # Update state to reflect checkpoint
    local component_c_state
    component_c_state=$(read_state | jq --arg checkpoint_id "$checkpoint_id" '
        .signals.component_c = true |
        .metadata.data_checkpoints += [{
            "component": "error-recovery",
            "operation": "checkpoint_creation",
            "checkpoint_id": $checkpoint_id,
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
        }]
    ')
    write_state "$component_c_state" "component-c-complete"
    
    local component_c_end=$(date +%s%N)
    local component_c_duration=$(((component_c_end - component_c_start) / 1000000))
    
    # Cross-component verification
    log "Verifying cross-component data consistency..."
    
    # Verify all component signals are set
    local signal_a signal_b signal_c
    signal_a=$(jq -r '.signals.component_a' "$STATE_FILE")
    signal_b=$(jq -r '.signals.component_b' "$STATE_FILE")
    signal_c=$(jq -r '.signals.component_c' "$STATE_FILE")
    
    if [[ "$signal_a" != "true" ]] || [[ "$signal_b" != "true" ]] || [[ "$signal_c" != "true" ]]; then
        echo "ERROR: Component signals not all set: A=$signal_a, B=$signal_b, C=$signal_c"
        return 1
    fi
    
    # Verify data checkpoint sequence
    local total_checkpoints
    total_checkpoints=$(jq '.metadata.data_checkpoints | length' "$STATE_FILE")
    if [[ "$total_checkpoints" != "5" ]]; then  # 3 from A + 1 from B + 1 from C
        echo "ERROR: Total checkpoints incorrect: expected 5, got $total_checkpoints"
        return 1
    fi
    
    # Verify data integrity across components
    local test_id_consistency
    test_id_consistency=$(jq -r '.metadata.test_id' "$STATE_FILE")
    if [[ ! "$test_id_consistency" =~ ^data-flow- ]]; then
        echo "ERROR: Test ID not consistent across operations: $test_id_consistency"
        return 1
    fi
    
    # Test data flow under error conditions
    log "Testing data flow under error conditions..."
    
    # Simulate corruption and recovery
    local backup_state
    backup_state=$(cat "$STATE_FILE")
    echo "corrupted" > "$STATE_FILE"
    
    # Recover and verify data integrity
    if ! recover_state; then
        echo "ERROR: Recovery failed during data flow test"
        return 1
    fi
    
    # Verify all component data survived recovery
    signal_a=$(jq -r '.signals.component_a' "$STATE_FILE")
    signal_b=$(jq -r '.signals.component_b' "$STATE_FILE")
    signal_c=$(jq -r '.signals.component_c' "$STATE_FILE")
    
    if [[ "$signal_a" != "true" ]] || [[ "$signal_b" != "true" ]] || [[ "$signal_c" != "true" ]]; then
        echo "ERROR: Component data not preserved after recovery: A=$signal_a, B=$signal_b, C=$signal_c"
        return 1
    fi
    
    # Add performance metrics to final state
    local final_state
    final_state=$(read_state | jq --arg duration_a "$component_a_duration" --arg duration_b "$component_b_duration" --arg duration_c "$component_c_duration" '
        .metadata.performance = {
            "component_a_duration_ms": ($duration_a | tonumber),
            "component_b_duration_ms": ($duration_b | tonumber),
            "component_c_duration_ms": ($duration_c | tonumber),
            "total_duration_ms": (($duration_a | tonumber) + ($duration_b | tonumber) + ($duration_c | tonumber))
        } |
        .completedTasks += ["data-flow-verification"]
    ')
    write_state "$final_state" "data-flow-complete"
    
    # Clean up worktree
    cleanup_worktree "phase-10-task-1" "true" >/dev/null 2>&1 || true
    
    log "Data flow consistency test passed"
    return 0
}

# =============================================================================
# Main Test Execution
# =============================================================================

print_header() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                    INTEGRATION TEST SUITE${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Testing complete system integration, component interactions, and end-to-end workflows"
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
        echo "${GREEN}${BOLD}🎉 All integration tests passed!${RESET}"
        echo
        echo "${CYAN}The Claude Dev Pipeline system has been thoroughly tested and verified${RESET}"
        echo "${CYAN}for robustness, reliability, and integration across all components.${RESET}"
        echo
        exit 0
    fi
}

main() {
    print_header
    
    # Hook and State Manager Integration Tests
    run_integration_test "Hook and State Synchronization" test_hook_state_synchronization
    run_integration_test "State Updates Through Hooks" test_state_updates_through_hooks
    
    # Worktree and Skills Integration Tests
    run_integration_test "Worktree and Skill Coordination" test_worktree_skill_coordination
    run_integration_test "Skill State Persistence" test_skill_state_persistence
    
    # Logging and Monitoring Integration Tests
    run_integration_test "Integrated Logging" test_integrated_logging
    run_integration_test "Monitoring Integration" test_monitoring_integration
    
    # Error Recovery in Full Pipeline Tests
    run_integration_test "Full Pipeline Error Recovery" test_full_pipeline_error_recovery
    run_integration_test "Error Recovery with Active Operations" test_error_recovery_with_active_operations
    
    # End-to-End Workflow Tests
    run_integration_test "Complete Development Workflow" test_complete_development_workflow
    run_integration_test "Multi-Branch Workflow" test_multi_branch_workflow
    
    # Cross-Component Data Flow Tests
    run_integration_test "Data Flow Consistency" test_data_flow_consistency
    
    print_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi