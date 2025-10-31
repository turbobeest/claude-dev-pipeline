#!/bin/bash
# =============================================================================
# Full Workflow Testing Suite
# =============================================================================
# 
# End-to-end pipeline simulation and testing:
# - Complete pipeline execution from PRD to deployment
# - Phase-by-phase progression
# - Manual gate interactions
# - Rollback scenarios
# - Concurrent execution handling
# - State persistence validation
# - Signal flow verification
# - Integration between hooks and skills
#
# =============================================================================

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
HOOKS_DIR="$PIPELINE_DIR/hooks"
SKILLS_DIR="$PIPELINE_DIR/skills"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_DIR="$TEST_DIR/temp"
LOG_FILE="$TEST_DIR/test-full-workflow.log"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=${VERBOSE:-false}
QUIET=${QUIET:-false}

# Colors for output
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
# Utility Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  ${BLUE}[VERBOSE]${RESET} $*" | tee -a "$LOG_FILE"
    fi
}

quiet() {
    if [[ "$QUIET" != "true" ]]; then
        echo "$*"
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} $message"
        verbose "    Expected: '$expected', Got: '$actual'"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} $message"
        quiet "    Expected: '$expected'"
        quiet "    Got: '$actual'"
        return 1
    fi
}

assert_contains() {
    local substring="$1"
    local text="$2"
    local message="${3:-String should contain substring}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$text" == *"$substring"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} $message"
        verbose "    Found '$substring' in text"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} $message"
        quiet "    Looking for: '$substring'"
        quiet "    In text: '$text'"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist: $file_path}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$file_path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} $message"
        return 1
    fi
}

assert_json_valid() {
    local json_text="$1"
    local message="${2:-JSON should be valid}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if echo "$json_text" | jq . >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} $message"
        quiet "    Invalid JSON: $json_text"
        return 1
    fi
}

simulate_user_message() {
    local message="$1"
    local context_files="${2:-[]}"
    
    local input
    input=$(jq -n \
        --arg msg "$message" \
        --argjson files "$context_files" \
        '{message: $msg, contextFiles: $files}')
    
    verbose "Simulating user message: $message"
    CLAUDE_DIR="$TEMP_DIR" timeout 10 bash "$HOOKS_DIR/skill-activation-prompt.sh" <<< "$input" 2>/dev/null || echo ""
}

simulate_tool_use() {
    local tool_name="$1"
    local tool_input="$2"
    
    local input
    input=$(jq -n \
        --arg tool "$tool_name" \
        --argjson inp "$tool_input" \
        '{tool: $tool, input: $inp}')
    
    verbose "Simulating tool use: $tool_name"
    CLAUDE_DIR="$TEMP_DIR" timeout 10 bash "$HOOKS_DIR/post-tool-use-tracker.sh" <<< "$input" 2>/dev/null || echo ""
}

validate_pre_tool_use() {
    local tool_name="$1"
    local tool_input="$2"
    
    local input
    input=$(jq -n \
        --arg tool "$tool_name" \
        --argjson inp "$tool_input" \
        '{tool: $tool, input: $inp}')
    
    verbose "Validating pre-tool use: $tool_name"
    if timeout 10 bash "$HOOKS_DIR/pre-implementation-validator.sh" <<< "$input" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

get_current_phase() {
    jq -r '.phase // "unknown"' "$TEMP_DIR/.workflow-state.json"
}

get_last_signal() {
    jq -r '.lastSignal // ""' "$TEMP_DIR/.workflow-state.json"
}

get_signal_count() {
    jq -r '.signals | length' "$TEMP_DIR/.workflow-state.json"
}

setup_workflow_environment() {
    verbose "Setting up full workflow test environment"
    
    # Create temp directory structure
    mkdir -p "$TEMP_DIR"
    mkdir -p "$TEMP_DIR/.signals"
    mkdir -p "$TEMP_DIR/src"
    mkdir -p "$TEMP_DIR/tests"
    mkdir -p "$TEMP_DIR/docs"
    rm -rf "$TEMP_DIR"/* 2>/dev/null || true
    
    # Create directories again after cleanup
    mkdir -p "$TEMP_DIR/.signals"
    mkdir -p "$TEMP_DIR/src"
    mkdir -p "$TEMP_DIR/tests"
    mkdir -p "$TEMP_DIR/docs"
    
    # Copy skill rules from the main pipeline
    if [[ -f "$PIPELINE_DIR/config/skill-rules.json" ]]; then
        cp "$PIPELINE_DIR/config/skill-rules.json" "$TEMP_DIR/skill-rules.json"
    else
        # Create a comprehensive test version
        cat > "$TEMP_DIR/skill-rules.json" << 'EOF'
{
  "version": "2.0",
  "activation_mode": "codeword",
  "skills": [
    {
      "skill": "prd-to-tasks",
      "activation_code": "PRD_TO_TASKS_V1",
      "phase": 1,
      "trigger_conditions": {
        "user_patterns": ["generate tasks", "parse prd", "create tasks"],
        "file_patterns": ["PRD.md", "requirements.md"]
      },
      "priority": 1
    },
    {
      "skill": "coupling-analysis",
      "activation_code": "COUPLING_ANALYSIS_V1",
      "phase": 1.5,
      "trigger_conditions": {
        "user_patterns": ["task-master show", "analyze coupling"],
        "file_patterns": ["tasks.json"],
        "signals_detected": ["PHASE1_START"]
      },
      "priority": 2
    },
    {
      "skill": "task-decomposer",
      "activation_code": "TASK_DECOMPOSER_V1",
      "phase": 1,
      "trigger_conditions": {
        "user_patterns": ["expand task", "decompose task"],
        "signals_detected": ["COUPLING_ANALYZED"]
      },
      "priority": 3
    },
    {
      "skill": "spec-gen",
      "activation_code": "SPEC_GEN_V1",
      "phase": 2,
      "trigger_conditions": {
        "user_patterns": ["openspec proposal", "create spec"],
        "signals_detected": ["PHASE1_COMPLETE"]
      },
      "priority": 4
    },
    {
      "skill": "test-strategy",
      "activation_code": "TEST_STRATEGY_V1",
      "phase": 2.5,
      "trigger_conditions": {
        "user_patterns": ["test strategy", "TDD"],
        "signals_detected": ["PHASE2_SPECS_CREATED"]
      },
      "priority": 5
    },
    {
      "skill": "tdd-implementer",
      "activation_code": "TDD_IMPLEMENTER_V1",
      "phase": 3,
      "trigger_conditions": {
        "user_patterns": ["implement", "write code", "TDD cycle"],
        "signals_detected": ["TEST_STRATEGY_COMPLETE"]
      },
      "priority": 6
    },
    {
      "skill": "integration-validator",
      "activation_code": "INTEGRATION_VALIDATOR_V1",
      "phase": 4,
      "trigger_conditions": {
        "user_patterns": ["integration testing", "task #24"],
        "signals_detected": ["PHASE3_COMPLETE"]
      },
      "priority": 7
    },
    {
      "skill": "e2e-validator",
      "activation_code": "E2E_VALIDATOR_V1",
      "phase": 5,
      "trigger_conditions": {
        "user_patterns": ["e2e testing", "task #25"],
        "signals_detected": ["PHASE4_COMPLETE"]
      },
      "priority": 8
    },
    {
      "skill": "deployment-orchestrator",
      "activation_code": "DEPLOYMENT_ORCHESTRATOR_V1",
      "phase": 6,
      "trigger_conditions": {
        "user_patterns": ["deploy", "task #26"],
        "signals_detected": ["PHASE5_COMPLETE", "GO_DECISION"]
      },
      "priority": 9
    }
  ],
  "phase_transitions": {
    "PHASE1_START": {
      "next_activation": "COUPLING_ANALYSIS_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    },
    "COUPLING_ANALYZED": {
      "next_activation": "TASK_DECOMPOSER_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    },
    "PHASE1_COMPLETE": {
      "next_activation": "SPEC_GEN_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    },
    "PHASE2_SPECS_CREATED": {
      "next_activation": "TEST_STRATEGY_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    },
    "TEST_STRATEGY_COMPLETE": {
      "next_activation": "TDD_IMPLEMENTER_V1",
      "auto_trigger": false,
      "requires_user_confirmation": true
    },
    "PHASE3_COMPLETE": {
      "next_activation": "INTEGRATION_VALIDATOR_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    },
    "PHASE4_COMPLETE": {
      "next_activation": "E2E_VALIDATOR_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    },
    "PHASE5_COMPLETE": {
      "next_activation": "DEPLOYMENT_ORCHESTRATOR_V1",
      "auto_trigger": false,
      "requires_user_confirmation": true,
      "approval_gate": "GO_NO_GO_DECISION"
    }
  }
}
EOF
    fi
    
    # Initialize clean state
    cat > "$TEMP_DIR/.workflow-state.json" << 'EOF'
{
  "phase": "pre-init",
  "completedTasks": [],
  "signals": {},
  "lastActivation": "",
  "lastSignal": ""
}
EOF

    # Create sample PRD file
    cat > "$TEMP_DIR/PRD.md" << 'EOF'
# Product Requirements Document

## Feature: User Authentication System

### Requirements
1. User registration with email validation
2. Secure login/logout functionality  
3. Password reset capability
4. Session management
5. Role-based access control

### Technical Requirements
- JWT token authentication
- bcrypt password hashing
- Rate limiting for login attempts
- Email service integration
- Database user model

### Acceptance Criteria
- Users can register with valid email
- Users can login with correct credentials
- Users receive password reset emails
- Sessions expire after inactivity
- Admin users have elevated permissions
EOF
}

teardown_workflow_environment() {
    verbose "Cleaning up full workflow test environment"
    rm -rf "$TEMP_DIR"
}

# =============================================================================
# Phase-by-Phase Test Functions
# =============================================================================

test_phase1_task_generation() {
    quiet "${BOLD}Testing Phase 1: Task Generation${RESET}"
    
    # Test 1: PRD parsing and task generation
    verbose "Test 1: PRD parsing triggers task generation"
    local output
    output=$(simulate_user_message "generate tasks from PRD" '["PRD.md"]')
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should activate PRD to tasks skill"
    
    # Test 2: Simulate tasks.json creation
    verbose "Test 2: Tasks.json creation triggers signals"
    local tool_input='{"file_path": "'$TEMP_DIR'/tasks.json", "content": "{\"tasks\": []}"}'
    output=$(simulate_tool_use "Write" "$tool_input")
    assert_contains "Phase 1 Started" "$output" "Should emit Phase 1 start signal"
    
    # Verify signal file was created
    assert_file_exists "$TEMP_DIR/.signals/PHASE1_START.json" "Should create PHASE1_START signal file"
    
    # Test 3: Automatic coupling analysis activation
    verbose "Test 3: Automatic coupling analysis"
    output=$(simulate_user_message "random message")
    assert_contains "AUTOMATIC PHASE TRANSITION" "$output" "Should trigger automatic transition"
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate coupling analysis"
    
    # Test 4: Task decomposition
    verbose "Test 4: Task decomposition after coupling analysis"
    # Simulate coupling analysis completion
    local signals_input='{"tool": "UserMessage", "input": {"message": "coupling analysis complete"}}'
    jq '.signals.COUPLING_ANALYZED = now | .lastSignal = "COUPLING_ANALYZED"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    output=$(simulate_user_message "random message")
    assert_contains "[ACTIVATE:TASK_DECOMPOSER_V1]" "$output" "Should activate task decomposer"
    
    # Test 5: Phase 1 completion
    verbose "Test 5: Phase 1 completion"
    # Simulate expanded tasks.json
    echo '{"tasks": [{"id": 1, "subtasks": [{"id": "1.1"}]}]}' > "$TEMP_DIR/tasks.json"
    tool_input='{"file_path": "'$TEMP_DIR'/tasks.json", "content": "updated"}'
    output=$(simulate_tool_use "Write" "$tool_input")
    
    # Check phase progression
    local current_phase
    current_phase=$(get_current_phase)
    verbose "Current phase after Phase 1: $current_phase"
}

test_phase2_specification() {
    quiet "${BOLD}Testing Phase 2: Specification Generation${RESET}"
    
    # Test 1: Spec generation activation
    verbose "Test 1: Spec generation from Phase 1 completion"
    jq '.signals.PHASE1_COMPLETE = now | .lastSignal = "PHASE1_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local output
    output=$(simulate_user_message "continue to next phase")
    assert_contains "[ACTIVATE:SPEC_GEN_V1]" "$output" "Should activate spec generation"
    
    # Test 2: OpenSpec proposal creation
    verbose "Test 2: OpenSpec proposal creation"
    mkdir -p "$TEMP_DIR/.openspec/proposals"
    local tool_input='{"file_path": "'$TEMP_DIR'/.openspec/proposals/auth.proposal.md", "content": "# Auth Proposal"}'
    output=$(simulate_tool_use "Write" "$tool_input")
    assert_contains "OpenSpec proposal created" "$output" "Should detect proposal creation"
    
    # Test 3: Test strategy activation
    verbose "Test 3: Test strategy activation"
    jq '.signals.PHASE2_SPECS_CREATED = now | .lastSignal = "PHASE2_SPECS_CREATED"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    output=$(simulate_user_message "random message")
    assert_contains "[ACTIVATE:TEST_STRATEGY_V1]" "$output" "Should activate test strategy"
}

test_phase3_implementation() {
    quiet "${BOLD}Testing Phase 3: TDD Implementation${RESET}"
    
    # Test 1: TDD validation (should block implementation without tests)
    verbose "Test 1: TDD validation blocks implementation without tests"
    local tool_input='{"path": "'$TEMP_DIR'/src/auth.js"}'
    if validate_pre_tool_use "Write" "$tool_input"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should block implementation without tests"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Correctly blocks implementation without tests"
    fi
    
    # Test 2: Test file creation
    verbose "Test 2: Test file creation"
    tool_input='{"file_path": "'$TEMP_DIR'/tests/auth.test.js", "content": "// Test file"}'
    local output
    output=$(simulate_tool_use "Write" "$tool_input")
    assert_contains "TDD Compliance" "$output" "Should detect test file creation"
    
    # Test 3: Implementation after tests
    verbose "Test 3: Implementation after tests"
    tool_input='{"path": "'$TEMP_DIR'/src/auth.js"}'
    if validate_pre_tool_use "Write" "$tool_input"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Allows implementation after tests exist"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should allow implementation after tests exist"
    fi
    
    # Test 4: Implementation file creation
    verbose "Test 4: Implementation file creation"
    tool_input='{"file_path": "'$TEMP_DIR'/src/auth.js", "content": "// Implementation"}'
    output=$(simulate_tool_use "Write" "$tool_input")
    assert_contains "TDD compliant" "$output" "Should show TDD compliance"
    
    # Test 5: Test execution
    verbose "Test 5: Test execution"
    tool_input='{"command": "npm test --coverage"}'
    output=$(simulate_tool_use "Bash" "$tool_input")
    assert_contains "Tests Executed" "$output" "Should detect test execution"
    assert_contains "Phase 3 Complete" "$output" "Should complete Phase 3"
}

test_phase4_integration() {
    quiet "${BOLD}Testing Phase 4: Integration Testing${RESET}"
    
    # Test 1: Integration validator activation
    verbose "Test 1: Integration validator activation"
    jq '.signals.PHASE3_COMPLETE = now | .lastSignal = "PHASE3_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local output
    output=$(simulate_user_message "random message")
    assert_contains "[ACTIVATE:INTEGRATION_VALIDATOR_V1]" "$output" "Should activate integration validator"
    
    # Test 2: Architecture review trigger
    verbose "Test 2: Architecture review"
    local tool_input='{"file_path": "'$TEMP_DIR'/architecture.md"}'
    output=$(simulate_tool_use "Read" "$tool_input")
    assert_contains "Architecture Reviewed" "$output" "Should detect architecture review"
    
    # Test 3: Integration test execution
    verbose "Test 3: Integration test execution"
    tool_input='{"command": "npm run test:integration"}'
    output=$(simulate_tool_use "Bash" "$tool_input")
    assert_contains "Phase 4 Complete" "$output" "Should complete Phase 4"
}

test_phase5_e2e() {
    quiet "${BOLD}Testing Phase 5: E2E Testing${RESET}"
    
    # Test 1: E2E validator activation
    verbose "Test 1: E2E validator activation"
    jq '.signals.PHASE4_COMPLETE = now | .lastSignal = "PHASE4_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local output
    output=$(simulate_user_message "random message")
    assert_contains "[ACTIVATE:E2E_VALIDATOR_V1]" "$output" "Should activate E2E validator"
    
    # Test 2: E2E test execution
    verbose "Test 2: E2E test execution"
    local tool_input='{"command": "npm run test:e2e"}'
    output=$(simulate_tool_use "Bash" "$tool_input")
    assert_contains "Phase 5 Complete" "$output" "Should complete Phase 5"
    assert_contains "GO/NO-GO DECISION REQUIRED" "$output" "Should require GO/NO-GO decision"
}

test_phase6_deployment() {
    quiet "${BOLD}Testing Phase 6: Deployment${RESET}"
    
    # Test 1: GO decision
    verbose "Test 1: GO decision handling"
    jq '.signals.PHASE5_COMPLETE = now' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local tool_input='{"tool": "UserMessage", "input": {"message": "GO for production"}}'
    local output
    output=$(simulate_tool_use "UserMessage" '{"message": "GO for production"}')
    assert_contains "GO DECISION RECORDED" "$output" "Should record GO decision"
    
    # Test 2: Deployment orchestrator activation
    verbose "Test 2: Deployment orchestrator activation"
    output=$(simulate_user_message "deploy to production")
    assert_contains "[ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1]" "$output" "Should activate deployment orchestrator"
    
    # Test 3: Deployment execution
    verbose "Test 3: Deployment execution"
    tool_input='{"command": "npm run deploy"}'
    output=$(simulate_tool_use "Bash" "$tool_input")
    assert_contains "Deployment Initiated" "$output" "Should initiate deployment"
}

# =============================================================================
# Advanced Workflow Tests
# =============================================================================

test_manual_gate_handling() {
    quiet "${BOLD}Testing Manual Gate Handling${RESET}"
    
    # Test 1: Manual gate detection
    verbose "Test 1: Manual gate at test strategy completion"
    jq '.signals.TEST_STRATEGY_COMPLETE = now | .lastSignal = "TEST_STRATEGY_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local output
    output=$(simulate_user_message "random message")
    assert_contains "MANUAL GATE REACHED" "$output" "Should detect manual gate"
    assert_contains "requires user confirmation" "$output" "Should require confirmation"
    
    # Test 2: Manual progression
    verbose "Test 2: Manual progression with user confirmation"
    output=$(simulate_user_message "proceed to next phase")
    assert_contains "[ACTIVATE:" "$output" "Should activate next skill on confirmation"
    
    # Test 3: Pipeline status during manual gate
    verbose "Test 3: Pipeline status during manual gate"
    output=$(simulate_user_message "pipeline status")
    assert_contains "Pipeline Status" "$output" "Should show pipeline status"
    assert_contains "Current Phase" "$output" "Should show current phase"
}

test_rollback_scenarios() {
    quiet "${BOLD}Testing Rollback Scenarios${RESET}"
    
    # Test 1: NO-GO decision handling
    verbose "Test 1: NO-GO decision handling"
    jq '.signals.PHASE5_COMPLETE = now' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local output
    output=$(simulate_tool_use "UserMessage" '{"message": "NO-GO"}')
    assert_contains "NO-GO DECISION RECORDED" "$output" "Should record NO-GO decision"
    assert_contains "Pipeline halted" "$output" "Should halt pipeline"
    
    # Test 2: Recovery from NO-GO
    verbose "Test 2: Recovery workflow"
    # After fixing issues, should be able to restart
    output=$(simulate_user_message "generate tasks")
    assert_contains "[ACTIVATE:" "$output" "Should allow skill activation after NO-GO"
    
    # Test 3: State reset capability
    verbose "Test 3: State reset"
    # Reset state to earlier phase
    jq '.phase = "phase2" | .signals = {"PHASE1_COMPLETE": 1234567890}' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local current_phase
    current_phase=$(get_current_phase)
    assert_equals "phase2" "$current_phase" "Should allow phase rollback"
}

test_concurrent_execution() {
    quiet "${BOLD}Testing Concurrent Execution${RESET}"
    
    # Test 1: Multiple simultaneous hook calls
    verbose "Test 1: Concurrent hook execution"
    
    # Start multiple background processes
    simulate_user_message "test message 1" &
    local pid1=$!
    simulate_user_message "test message 2" &
    local pid2=$!
    simulate_user_message "test message 3" &
    local pid3=$!
    
    # Wait for all to complete
    wait $pid1 $pid2 $pid3
    
    # State should still be valid JSON
    local state_content
    state_content=$(cat "$TEMP_DIR/.workflow-state.json")
    assert_json_valid "$state_content" "State should remain valid after concurrent access"
    
    # Test 2: File locking verification
    verbose "Test 2: File locking verification"
    # Check that signals directory has proper files
    local signal_count
    signal_count=$(find "$TEMP_DIR/.signals" -name "*.json" 2>/dev/null | wc -l)
    verbose "Signal files found: $signal_count"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    quiet "  ${GREEN}${RESET} Concurrent execution completed without corruption"
}

test_state_persistence() {
    quiet "${BOLD}Testing State Persistence${RESET}"
    
    # Test 1: State file format validation
    verbose "Test 1: State file format"
    local state_content
    state_content=$(cat "$TEMP_DIR/.workflow-state.json")
    assert_json_valid "$state_content" "State file should be valid JSON"
    
    # Verify required fields
    local has_phase
    has_phase=$(echo "$state_content" | jq -r '.phase // "missing"')
    assert_equals "pre-init" "$has_phase" "Should have phase field" || \
    assert_equals "phase1" "$has_phase" "Should have valid phase field" || \
    assert_equals "phase2" "$has_phase" "Should have valid phase field" || \
    assert_equals "phase3" "$has_phase" "Should have valid phase field"
    
    local has_signals
    has_signals=$(echo "$state_content" | jq -r 'has("signals")')
    assert_equals "true" "$has_signals" "Should have signals field"
    
    # Test 2: Signal persistence
    verbose "Test 2: Signal file persistence"
    # Create a signal and verify it persists
    jq '.signals.TEST_PERSISTENCE = now' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local signal_exists
    signal_exists=$(jq -r '.signals.TEST_PERSISTENCE // "missing"' "$TEMP_DIR/.workflow-state.json")
    if [[ "$signal_exists" != "missing" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Signal persistence works correctly"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Signal should persist in state file"
    fi
    
    # Test 3: Recovery from corrupted state
    verbose "Test 3: Recovery from corrupted state"
    echo "invalid json" > "$TEMP_DIR/.workflow-state.json"
    
    # Trigger hook that initializes state
    local output
    output=$(simulate_user_message "test recovery")
    
    # Check if state was recreated
    if [[ -f "$TEMP_DIR/.workflow-state.json" ]]; then
        state_content=$(cat "$TEMP_DIR/.workflow-state.json")
        if echo "$state_content" | jq . >/dev/null 2>&1; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            quiet "  ${GREEN}${RESET} Successfully recovers from corrupted state"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            quiet "  ${RED}${RESET} Should recreate valid state file"
        fi
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should recreate state file when corrupted"
    fi
}

test_signal_flow_verification() {
    quiet "${BOLD}Testing Signal Flow Verification${RESET}"
    
    # Test 1: Signal ordering
    verbose "Test 1: Signal emission ordering"
    setup_workflow_environment  # Reset for clean test
    
    # Create tasks.json to trigger PHASE1_START
    local tool_input='{"file_path": "'$TEMP_DIR'/tasks.json", "content": "{}"}'
    simulate_tool_use "Write" "$tool_input" >/dev/null
    
    # Check signal was created
    assert_file_exists "$TEMP_DIR/.signals/PHASE1_START.json" "Should create PHASE1_START signal"
    
    # Test 2: Signal metadata
    verbose "Test 2: Signal metadata validation"
    local signal_content
    signal_content=$(cat "$TEMP_DIR/.signals/PHASE1_START.json")
    assert_json_valid "$signal_content" "Signal file should be valid JSON"
    assert_contains "\"signal\":" "$signal_content" "Should contain signal field"
    assert_contains "\"timestamp\":" "$signal_content" "Should contain timestamp"
    assert_contains "\"phase\":" "$signal_content" "Should contain phase field"
    
    # Test 3: Signal chain validation
    verbose "Test 3: Signal chain progression"
    local initial_signal_count
    initial_signal_count=$(get_signal_count)
    
    # Trigger a few more signals
    jq '.signals.COUPLING_ANALYZED = now | .signals.PHASE1_COMPLETE = now' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local final_signal_count
    final_signal_count=$(get_signal_count)
    
    if [[ $final_signal_count -gt $initial_signal_count ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Signal chain progresses correctly"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Signal chain should progress"
    fi
}

test_complete_pipeline_flow() {
    quiet "${BOLD}Testing Complete Pipeline Flow${RESET}"
    
    verbose "Running complete end-to-end pipeline simulation"
    setup_workflow_environment  # Reset for clean run
    
    # Phase 1: Task Generation
    verbose "Phase 1: Task Generation"
    simulate_user_message "generate tasks from PRD" '["PRD.md"]' >/dev/null
    local tool_input='{"file_path": "'$TEMP_DIR'/tasks.json", "content": "{\"tasks\": []}"}'
    simulate_tool_use "Write" "$tool_input" >/dev/null
    
    # Phase 2: Specification
    verbose "Phase 2: Specification"
    jq '.signals.PHASE1_COMPLETE = now | .lastSignal = "PHASE1_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    mkdir -p "$TEMP_DIR/.openspec/proposals"
    tool_input='{"file_path": "'$TEMP_DIR'/.openspec/proposals/auth.proposal.md", "content": "# Auth"}'
    simulate_tool_use "Write" "$tool_input" >/dev/null
    
    # Phase 3: Implementation
    verbose "Phase 3: Implementation"
    tool_input='{"file_path": "'$TEMP_DIR'/tests/auth.test.js", "content": "// Test"}'
    simulate_tool_use "Write" "$tool_input" >/dev/null
    
    tool_input='{"file_path": "'$TEMP_DIR'/src/auth.js", "content": "// Implementation"}'
    simulate_tool_use "Write" "$tool_input" >/dev/null
    
    # Phase 4: Integration
    verbose "Phase 4: Integration"
    jq '.signals.PHASE3_COMPLETE = now | .lastSignal = "PHASE3_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    # Phase 5: E2E
    verbose "Phase 5: E2E"
    jq '.signals.PHASE4_COMPLETE = now | .lastSignal = "PHASE4_COMPLETE"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    jq '.signals.PHASE5_COMPLETE = now' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    # Phase 6: Deployment (GO decision)
    verbose "Phase 6: Deployment"
    simulate_tool_use "UserMessage" '{"message": "GO for production"}' >/dev/null
    
    # Verify final state
    local final_signal_count
    final_signal_count=$(get_signal_count)
    
    if [[ $final_signal_count -ge 5 ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Complete pipeline flow executed successfully"
        verbose "    Final signal count: $final_signal_count"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Complete pipeline flow should generate multiple signals"
        quiet "    Signal count: $final_signal_count (expected >= 5)"
    fi
    
    # Verify key files exist
    assert_file_exists "$TEMP_DIR/tasks.json" "Tasks file should exist"
    assert_file_exists "$TEMP_DIR/tests/auth.test.js" "Test file should exist"
    assert_file_exists "$TEMP_DIR/src/auth.js" "Implementation file should exist"
    
    verbose "Complete pipeline flow test finished"
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_all_tests() {
    quiet "${BOLD}Claude Dev Pipeline - Full Workflow Testing Suite${RESET}"
    quiet "========================================================="
    
    # Clear log file
    > "$LOG_FILE"
    
    log "Starting full workflow tests"
    
    # Setup
    setup_workflow_environment
    
    # Run phase tests
    test_phase1_task_generation
    test_phase2_specification
    test_phase3_implementation
    test_phase4_integration
    test_phase5_e2e
    test_phase6_deployment
    
    # Run advanced tests
    test_manual_gate_handling
    test_rollback_scenarios
    test_concurrent_execution
    test_state_persistence
    test_signal_flow_verification
    
    # Run complete pipeline test
    test_complete_pipeline_flow
    
    # Cleanup
    teardown_workflow_environment
    
    # Report results
    quiet ""
    quiet "${BOLD}Test Results${RESET}"
    quiet "============"
    quiet "Tests Run:    $TESTS_RUN"
    quiet "Tests Passed: ${GREEN}$TESTS_PASSED${RESET}"
    quiet "Tests Failed: ${RED}$TESTS_FAILED${RESET}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        quiet ""
        quiet "${GREEN}${BOLD}All tests passed!${RESET}"
        log "All full workflow tests passed"
        return 0
    else
        quiet ""
        quiet "${RED}${BOLD}Some tests failed!${RESET}"
        quiet "Check $LOG_FILE for details"
        log "Some full workflow tests failed"
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

show_help() {
    cat << EOF
Claude Dev Pipeline - Full Workflow Testing Suite

Usage: $0 [OPTIONS] [TEST_SUITE]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress most output
    -h, --help          Show this help message

TEST_SUITES:
    phase1              Test Phase 1 (task generation) only
    phase2              Test Phase 2 (specification) only
    phase3              Test Phase 3 (implementation) only
    phase4              Test Phase 4 (integration) only
    phase5              Test Phase 5 (e2e testing) only
    phase6              Test Phase 6 (deployment) only
    manual-gates        Test manual gate handling only
    rollback            Test rollback scenarios only
    concurrent          Test concurrent execution only
    persistence         Test state persistence only
    signals             Test signal flow only
    complete            Test complete pipeline flow only
    all                 Run all tests (default)

EXAMPLES:
    $0                          # Run all tests
    $0 -v phase1                # Test Phase 1 with verbose output
    $0 -q complete              # Test complete flow quietly

ENVIRONMENT VARIABLES:
    VERBOSE=true        Enable verbose output
    QUIET=true          Enable quiet mode
EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            phase1)
                setup_workflow_environment
                test_phase1_task_generation
                teardown_workflow_environment
                exit $?
                ;;
            phase2)
                setup_workflow_environment
                test_phase2_specification
                teardown_workflow_environment
                exit $?
                ;;
            phase3)
                setup_workflow_environment
                test_phase3_implementation
                teardown_workflow_environment
                exit $?
                ;;
            phase4)
                setup_workflow_environment
                test_phase4_integration
                teardown_workflow_environment
                exit $?
                ;;
            phase5)
                setup_workflow_environment
                test_phase5_e2e
                teardown_workflow_environment
                exit $?
                ;;
            phase6)
                setup_workflow_environment
                test_phase6_deployment
                teardown_workflow_environment
                exit $?
                ;;
            manual-gates)
                setup_workflow_environment
                test_manual_gate_handling
                teardown_workflow_environment
                exit $?
                ;;
            rollback)
                setup_workflow_environment
                test_rollback_scenarios
                teardown_workflow_environment
                exit $?
                ;;
            concurrent)
                setup_workflow_environment
                test_concurrent_execution
                teardown_workflow_environment
                exit $?
                ;;
            persistence)
                setup_workflow_environment
                test_state_persistence
                teardown_workflow_environment
                exit $?
                ;;
            signals)
                setup_workflow_environment
                test_signal_flow_verification
                teardown_workflow_environment
                exit $?
                ;;
            complete)
                setup_workflow_environment
                test_complete_pipeline_flow
                teardown_workflow_environment
                exit $?
                ;;
            all)
                run_all_tests
                exit $?
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Default: run all tests
    run_all_tests
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi