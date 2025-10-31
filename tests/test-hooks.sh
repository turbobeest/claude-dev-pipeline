#!/bin/bash
# =============================================================================
# Hook Testing Suite
# =============================================================================
# 
# Comprehensive tests for all pipeline hooks:
# - skill-activation-prompt.sh (UserPromptSubmit)
# - post-tool-use-tracker.sh (PostToolUse) 
# - pre-implementation-validator.sh (PreToolUse)
#
# Tests cover:
# - Valid and invalid inputs
# - Timeout behavior
# - Error handling  
# - JSON output format validation
# - File locking mechanisms
# - Signal detection and emission
# - Phase transitions
# - TDD enforcement
#
# =============================================================================

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
HOOKS_DIR="$PIPELINE_DIR/hooks"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_DIR="$TEST_DIR/temp"
LOG_FILE="$TEST_DIR/test-hooks.log"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=${VERBOSE:-false}
QUIET=${QUIET:-false}

# Colors for output (if terminal supports it)
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

run_hook_with_timeout() {
    local hook_script="$1"
    local input_data="$2"
    local timeout_seconds="${3:-10}"
    local output_file="$TEMP_DIR/hook_output.tmp"
    
    verbose "Running hook: $hook_script with timeout: ${timeout_seconds}s"
    verbose "Input: $input_data"
    
    # Run hook with timeout
    if timeout "$timeout_seconds" bash "$hook_script" <<< "$input_data" > "$output_file" 2>&1; then
        cat "$output_file"
        return 0
    else
        local exit_code=$?
        cat "$output_file"
        return $exit_code
    fi
}

setup_test_environment() {
    verbose "Setting up test environment"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Clean previous test artifacts
    rm -f "$TEMP_DIR"/*
    
    # Create test state file
    cat > "$TEMP_DIR/.workflow-state.json" << 'EOF'
{
  "phase": "pre-init",
  "completedTasks": [],
  "signals": {},
  "lastActivation": "",
  "lastSignal": ""
}
EOF

    # Create test skill rules (minimal version for testing)
    cat > "$TEMP_DIR/skill-rules.json" << 'EOF'
{
  "skills": [
    {
      "skill": "test-skill",
      "activation_code": "TEST_SKILL_V1",
      "trigger_conditions": {
        "user_patterns": ["test pattern", "activate test"],
        "file_patterns": ["test.js", "*.test.*"],
        "signals_detected": ["TEST_SIGNAL"]
      }
    }
  ],
  "phase_transitions": {
    "TEST_SIGNAL": {
      "next_activation": "TEST_SKILL_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    }
  }
}
EOF
}

teardown_test_environment() {
    verbose "Cleaning up test environment"
    rm -rf "$TEMP_DIR"
}

# =============================================================================
# Hook-Specific Test Functions
# =============================================================================

test_skill_activation_hook() {
    local hook_script="$HOOKS_DIR/skill-activation-prompt.sh"
    
    quiet "${BOLD}Testing Skill Activation Hook${RESET}"
    
    # Test 1: Valid user message with pattern match
    verbose "Test 1: Pattern matching"
    local input='{"message": "activate test skill", "contextFiles": []}'
    local output
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "ACTIVATE:" "$output" "Should activate skill on pattern match"
    
    # Test 2: File pattern matching
    verbose "Test 2: File pattern matching"
    input='{"message": "hello", "contextFiles": ["test.js", "other.txt"]}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "ACTIVATE:" "$output" "Should activate skill on file pattern match"
    
    # Test 3: No match case
    verbose "Test 3: No activation case"
    input='{"message": "random message", "contextFiles": ["random.txt"]}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    if [[ "$output" == *"ACTIVATE:"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should not activate on non-matching input"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Correctly does not activate on non-matching input"
    fi
    
    # Test 4: Invalid JSON input
    verbose "Test 4: Invalid JSON handling"
    input='{"message": invalid json'
    if output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        # Hook should handle gracefully and not crash
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Handles invalid JSON gracefully"
    else
        # Check if it's a parsing error vs timeout
        if [[ $? -eq 124 ]]; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            quiet "  ${RED}${RESET} Hook timed out on invalid JSON"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            quiet "  ${GREEN}${RESET} Exits gracefully on invalid JSON"
        fi
    fi
    
    # Test 5: Missing skill-rules.json
    verbose "Test 5: Missing skill rules file"
    mv "$TEMP_DIR/skill-rules.json" "$TEMP_DIR/skill-rules.json.bak"
    input='{"message": "test", "contextFiles": []}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5 2>&1)
    mv "$TEMP_DIR/skill-rules.json.bak" "$TEMP_DIR/skill-rules.json"
    
    # Should exit gracefully (exit code 0)
    if [[ $? -eq 0 ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Handles missing skill-rules.json gracefully"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should handle missing skill-rules.json gracefully"
    fi
    
    # Test 6: Signal-based activation
    verbose "Test 6: Signal-based activation"
    # First, set a signal in state
    jq '.signals.TEST_SIGNAL = now | .lastSignal = "TEST_SIGNAL"' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    input='{"message": "random message", "contextFiles": []}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "ACTIVATE:" "$output" "Should activate skill on signal detection"
    
    # Test 7: Pipeline status check
    verbose "Test 7: Pipeline status check"
    input='{"message": "what is the pipeline status", "contextFiles": []}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "Pipeline Status" "$output" "Should show pipeline status"
    assert_contains "Current Phase:" "$output" "Should show current phase"
}

test_post_tool_use_hook() {
    local hook_script="$HOOKS_DIR/post-tool-use-tracker.sh"
    
    quiet "${BOLD}Testing Post-Tool-Use Hook${RESET}"
    
    # Test 1: Write tool tracking (tasks.json creation)
    verbose "Test 1: Write tool tracking - tasks.json"
    local input='{"tool": "Write", "input": {"file_path": "/path/to/tasks.json", "content": "test"}}'
    local output
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "Phase 1 Started" "$output" "Should detect tasks.json creation"
    
    # Verify signal was emitted
    assert_file_exists "$TEMP_DIR/.signals/PHASE1_START.json" "Should create signal file"
    
    # Test 2: Read tool tracking
    verbose "Test 2: Read tool tracking"
    input='{"tool": "Read", "input": {"file_path": "/path/to/tasks.json"}}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "Coupling Analysis Ready" "$output" "Should trigger coupling analysis"
    
    # Test 3: Bash tool tracking - test execution
    verbose "Test 3: Bash tool tracking - test execution"
    input='{"tool": "Bash", "input": {"command": "npm test --coverage"}}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "Tests Executed" "$output" "Should detect test execution"
    
    # Test 4: Signal file creation and JSON format
    verbose "Test 4: Signal file format validation"
    if [[ -f "$TEMP_DIR/.signals/PHASE1_START.json" ]]; then
        local signal_content
        signal_content=$(cat "$TEMP_DIR/.signals/PHASE1_START.json")
        assert_json_valid "$signal_content" "Signal file should contain valid JSON"
        assert_contains "\"signal\":" "$signal_content" "Signal file should contain signal field"
        assert_contains "\"timestamp\":" "$signal_content" "Signal file should contain timestamp"
    fi
    
    # Test 5: State file updates
    verbose "Test 5: State file updates"
    local state_content
    state_content=$(cat "$TEMP_DIR/.workflow-state.json")
    assert_json_valid "$state_content" "State file should contain valid JSON"
    assert_contains "\"signals\":" "$state_content" "State file should contain signals"
    
    # Test 6: Invalid JSON input handling
    verbose "Test 6: Invalid JSON handling"
    input='{"tool": invalid json'
    if output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Handles invalid JSON gracefully"
    else
        if [[ $? -eq 124 ]]; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            quiet "  ${RED}${RESET} Hook timed out on invalid JSON"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            quiet "  ${GREEN}${RESET} Exits gracefully on invalid JSON"
        fi
    fi
    
    # Test 7: GO/NO-GO decision handling
    verbose "Test 7: GO/NO-GO decision"
    # First set PHASE5_COMPLETE signal
    jq '.signals.PHASE5_COMPLETE = now' \
        "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    input='{"tool": "UserMessage", "input": {"message": "GO for production"}}'
    output=$(CLAUDE_DIR="$TEMP_DIR" run_hook_with_timeout "$hook_script" "$input" 5)
    assert_contains "GO DECISION RECORDED" "$output" "Should record GO decision"
}

test_pre_implementation_validator() {
    local hook_script="$HOOKS_DIR/pre-implementation-validator.sh"
    
    quiet "${BOLD}Testing Pre-Implementation Validator${RESET}"
    
    # Test 1: Allow test file creation
    verbose "Test 1: Allow test file creation"
    local input='{"tool": "Write", "input": {"path": "/src/components/Button.test.js"}}'
    if output=$(run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Allows test file creation"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should allow test file creation"
    fi
    
    # Test 2: Block implementation without tests (create test file first)
    verbose "Test 2: Block implementation without tests"
    mkdir -p "$TEMP_DIR/src/components"
    input='{"tool": "Write", "input": {"path": "'$TEMP_DIR'/src/components/Button.js"}}'
    if output=$(run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should block implementation without tests"
        quiet "    Output: $output"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Correctly blocks implementation without tests"
        assert_contains "TDD VIOLATION" "$output" "Should show TDD violation message"
    fi
    
    # Test 3: Allow implementation with tests
    verbose "Test 3: Allow implementation with tests"
    mkdir -p "$TEMP_DIR/tests/components"
    touch "$TEMP_DIR/tests/components/Button.test.js"
    
    input='{"tool": "Write", "input": {"path": "'$TEMP_DIR'/src/components/Button.js"}}'
    if output=$(run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Allows implementation when tests exist"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should allow implementation when tests exist"
        quiet "    Output: $output"
    fi
    
    # Test 4: Python TDD enforcement
    verbose "Test 4: Python TDD enforcement"
    input='{"tool": "Write", "input": {"path": "'$TEMP_DIR'/src/utils.py"}}'
    if output=$(run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should block Python implementation without tests"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Correctly blocks Python implementation without tests"
    fi
    
    # Test 5: Non-implementation files should pass through
    verbose "Test 5: Non-implementation files pass through"
    input='{"tool": "Write", "input": {"path": "/docs/README.md"}}'
    if output=$(run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Allows non-implementation files"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should allow non-implementation files"
    fi
    
    # Test 6: Non-Write tools should pass through
    verbose "Test 6: Non-Write tools pass through"
    input='{"tool": "Read", "input": {"path": "/src/components/Button.js"}}'
    if output=$(run_hook_with_timeout "$hook_script" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Allows non-Write tools"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should allow non-Write tools"
    fi
}

test_hook_timeout_behavior() {
    quiet "${BOLD}Testing Hook Timeout Behavior${RESET}"
    
    # Create a hook script that sleeps
    local test_hook="$TEMP_DIR/slow_hook.sh"
    cat > "$test_hook" << 'EOF'
#!/bin/bash
sleep 15
echo "This should timeout"
EOF
    chmod +x "$test_hook"
    
    verbose "Test: Hook timeout handling"
    local input='{"test": "timeout"}'
    if output=$(run_hook_with_timeout "$test_hook" "$input" 5 2>&1); then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Hook should have timed out"
    else
        if [[ $? -eq 124 ]]; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            quiet "  ${GREEN}${RESET} Hook correctly timed out"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            quiet "  ${RED}${RESET} Hook failed for wrong reason (expected timeout)"
        fi
    fi
}

test_file_locking() {
    quiet "${BOLD}Testing File Locking Mechanisms${RESET}"
    
    verbose "Test 1: Concurrent state file access"
    local lock_test_script="$TEMP_DIR/lock_test.sh"
    cat > "$lock_test_script" << EOF
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$TEMP_DIR"
STATE_FILE="\$SCRIPT_DIR/.workflow-state.json"

# Simulate concurrent access
flock "\$STATE_FILE" -c "
    jq '.test_counter = (.test_counter // 0) + 1' \"\$STATE_FILE\" > \"\$STATE_FILE.tmp\" && 
    mv \"\$STATE_FILE.tmp\" \"\$STATE_FILE\"
    sleep 1
"
EOF
    chmod +x "$lock_test_script"
    
    # Initialize counter
    jq '.test_counter = 0' "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    # Run multiple instances concurrently
    "$lock_test_script" &
    "$lock_test_script" &
    "$lock_test_script" &
    wait
    
    local counter
    counter=$(jq -r '.test_counter' "$TEMP_DIR/.workflow-state.json")
    assert_equals "3" "$counter" "File locking should prevent corruption"
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_all_tests() {
    quiet "${BOLD}Claude Dev Pipeline - Hook Testing Suite${RESET}"
    quiet "=================================================="
    
    # Clear log file
    > "$LOG_FILE"
    
    log "Starting hook tests"
    
    # Setup
    setup_test_environment
    
    # Run test suites
    test_skill_activation_hook
    test_post_tool_use_hook
    test_pre_implementation_validator
    test_hook_timeout_behavior
    test_file_locking
    
    # Cleanup
    teardown_test_environment
    
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
        log "All hook tests passed"
        return 0
    else
        quiet ""
        quiet "${RED}${BOLD}Some tests failed!${RESET}"
        quiet "Check $LOG_FILE for details"
        log "Some hook tests failed"
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

show_help() {
    cat << EOF
Claude Dev Pipeline - Hook Testing Suite

Usage: $0 [OPTIONS] [TEST_SUITE]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress most output
    -h, --help          Show this help message

TEST_SUITES:
    skill-activation    Test skill activation hook only
    post-tool-use       Test post-tool-use hook only  
    pre-implementation  Test pre-implementation validator only
    timeout             Test timeout behavior only
    locking             Test file locking only
    all                 Run all tests (default)

EXAMPLES:
    $0                              # Run all tests
    $0 -v skill-activation          # Run skill activation tests with verbose output
    $0 -q all                       # Run all tests quietly
    
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
            skill-activation)
                setup_test_environment
                test_skill_activation_hook
                teardown_test_environment
                exit $?
                ;;
            post-tool-use)
                setup_test_environment
                test_post_tool_use_hook
                teardown_test_environment
                exit $?
                ;;
            pre-implementation)
                setup_test_environment
                test_pre_implementation_validator
                teardown_test_environment
                exit $?
                ;;
            timeout)
                setup_test_environment
                test_hook_timeout_behavior
                teardown_test_environment
                exit $?
                ;;
            locking)
                setup_test_environment
                test_file_locking
                teardown_test_environment
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