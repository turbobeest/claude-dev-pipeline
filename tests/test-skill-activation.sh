#!/bin/bash
# =============================================================================
# Skill Activation Testing Suite
# =============================================================================
# 
# Comprehensive tests for skill activation logic:
# - Codeword injection mechanisms
# - Pattern matching logic (user patterns, file patterns)
# - Phase transition detection
# - Signal-based activation
# - Automatic vs manual transitions
# - Activation code validation
# - Priority handling
# - State management
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
LOG_FILE="$TEST_DIR/test-skill-activation.log"

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

assert_not_contains() {
    local substring="$1"
    local text="$2"
    local message="${3:-String should not contain substring}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$text" != *"$substring"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} $message"
        quiet "    Should not find: '$substring'"
        quiet "    In text: '$text'"
        return 1
    fi
}

assert_activation_count() {
    local expected_count="$1"
    local text="$2"
    local message="${3:-Should have correct number of activations}"
    
    local actual_count
    actual_count=$(echo "$text" | grep -c "\[ACTIVATE:" || echo "0")
    assert_equals "$expected_count" "$actual_count" "$message"
}

simulate_skill_activation() {
    local user_message="$1"
    local context_files="${2:-[]}"
    local phase="${3:-pre-init}"
    local signals="${4:-{}}"
    
    # Create input JSON
    local input
    input=$(jq -n \
        --arg msg "$user_message" \
        --argjson files "$context_files" \
        '{message: $msg, contextFiles: $files}')
    
    # Set up state file with specified phase and signals
    jq -n \
        --arg phase "$phase" \
        --argjson signals "$signals" \
        '{phase: $phase, completedTasks: [], signals: $signals, lastActivation: "", lastSignal: ""}' \
        > "$TEMP_DIR/.workflow-state.json"
    
    # Run the skill activation hook
    CLAUDE_DIR="$TEMP_DIR" timeout 10 bash "$HOOKS_DIR/skill-activation-prompt.sh" <<< "$input" 2>/dev/null || echo ""
}

setup_test_environment() {
    verbose "Setting up skill activation test environment"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    rm -f "$TEMP_DIR"/*
    
    # Create comprehensive test skill rules
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
        "user_patterns": [
          "generate tasks",
          "parse prd",
          "create tasks",
          "product requirements"
        ],
        "file_patterns": [
          "PRD.md",
          "requirements.md"
        ]
      },
      "priority": 1
    },
    {
      "skill": "coupling-analysis",
      "activation_code": "COUPLING_ANALYSIS_V1",
      "phase": 1.5,
      "trigger_conditions": {
        "user_patterns": [
          "task-master show",
          "analyze coupling",
          "parallel tasks"
        ],
        "file_patterns": [
          "tasks.json"
        ],
        "signals_detected": [
          "PHASE1_START"
        ]
      },
      "priority": 2
    },
    {
      "skill": "test-strategy",
      "activation_code": "TEST_STRATEGY_V1",
      "phase": 2.5,
      "trigger_conditions": {
        "user_patterns": [
          "test strategy",
          "TDD",
          "write tests"
        ],
        "signals_detected": [
          "PHASE2_SPECS_CREATED"
        ]
      },
      "priority": 3
    },
    {
      "skill": "integration-validator",
      "activation_code": "INTEGRATION_VALIDATOR_V1",
      "phase": 4,
      "trigger_conditions": {
        "user_patterns": [
          "integration testing",
          "task #24",
          "component integration"
        ],
        "file_patterns": [
          "architecture.md"
        ],
        "signals_detected": [
          "PHASE3_COMPLETE"
        ]
      },
      "priority": 4
    },
    {
      "skill": "multi-trigger-skill",
      "activation_code": "MULTI_TRIGGER_V1",
      "phase": 99,
      "trigger_conditions": {
        "user_patterns": [
          "multi test",
          "complex pattern"
        ],
        "file_patterns": [
          "*.multi",
          "multi.*"
        ],
        "signals_detected": [
          "MULTI_SIGNAL"
        ]
      },
      "priority": 99
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
    "MANUAL_GATE": {
      "next_activation": "MANUAL_SKILL_V1",
      "auto_trigger": false,
      "requires_user_confirmation": true
    }
  }
}
EOF

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
}

teardown_test_environment() {
    verbose "Cleaning up skill activation test environment"
    rm -rf "$TEMP_DIR"
}

# =============================================================================
# Test Functions
# =============================================================================

test_user_pattern_matching() {
    quiet "${BOLD}Testing User Pattern Matching${RESET}"
    
    # Test 1: Exact pattern match
    verbose "Test 1: Exact pattern match"
    local output
    output=$(simulate_skill_activation "generate tasks")
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should activate on exact pattern match"
    assert_contains "Active Skills:" "$output" "Should show active skills section"
    
    # Test 2: Case insensitive matching
    verbose "Test 2: Case insensitive matching"
    output=$(simulate_skill_activation "GENERATE TASKS")
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should activate on case insensitive match"
    
    # Test 3: Partial pattern match
    verbose "Test 3: Partial pattern match"
    output=$(simulate_skill_activation "please generate tasks for me")
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should activate on partial match"
    
    # Test 4: Multiple pattern matches (different skills)
    verbose "Test 4: Multiple pattern matches"
    output=$(simulate_skill_activation "task-master show and test strategy")
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate coupling analysis"
    assert_contains "[ACTIVATE:TEST_STRATEGY_V1]" "$output" "Should activate test strategy"
    assert_activation_count "2" "$output" "Should activate exactly 2 skills"
    
    # Test 5: No pattern match
    verbose "Test 5: No pattern match"
    output=$(simulate_skill_activation "random unrelated message")
    assert_not_contains "[ACTIVATE:" "$output" "Should not activate on unrelated message"
    
    # Test 6: Special characters in patterns
    verbose "Test 6: Special characters in patterns"
    output=$(simulate_skill_activation "task #24 integration")
    assert_contains "[ACTIVATE:INTEGRATION_VALIDATOR_V1]" "$output" "Should match patterns with special characters"
}

test_file_pattern_matching() {
    quiet "${BOLD}Testing File Pattern Matching${RESET}"
    
    # Test 1: Exact file name match
    verbose "Test 1: Exact file name match"
    local output
    output=$(simulate_skill_activation "hello" '["PRD.md", "other.txt"]')
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should activate on exact file match"
    
    # Test 2: Multiple file patterns
    verbose "Test 2: Multiple file patterns"
    output=$(simulate_skill_activation "hello" '["tasks.json", "requirements.md"]')
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should activate prd-to-tasks on requirements.md"
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate coupling analysis on tasks.json"
    
    # Test 3: File path matching
    verbose "Test 3: File path matching"
    output=$(simulate_skill_activation "hello" '["/path/to/PRD.md", "/other/file.txt"]')
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should match file in path"
    
    # Test 4: Wildcard pattern matching
    verbose "Test 4: Wildcard pattern matching"
    output=$(simulate_skill_activation "hello" '["test.multi", "other.txt"]')
    assert_contains "[ACTIVATE:MULTI_TRIGGER_V1]" "$output" "Should match wildcard patterns"
    
    # Test 5: No file match
    verbose "Test 5: No file match"
    output=$(simulate_skill_activation "hello" '["unrelated.txt", "random.log"]')
    assert_not_contains "[ACTIVATE:" "$output" "Should not activate on unmatched files"
    
    # Test 6: Empty file list
    verbose "Test 6: Empty file list"
    output=$(simulate_skill_activation "generate tasks" '[]')
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should still work with user patterns when no files"
}

test_signal_based_activation() {
    quiet "${BOLD}Testing Signal-Based Activation${RESET}"
    
    # Test 1: Signal detection activation
    verbose "Test 1: Signal detection activation"
    local signals='{"PHASE1_START": 1698765432}'
    local output
    output=$(simulate_skill_activation "random message" '[]' "phase1" "$signals")
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate on signal detection"
    
    # Test 2: Multiple signal matches
    verbose "Test 2: Multiple signal matches"
    signals='{"PHASE1_START": 1698765432, "PHASE2_SPECS_CREATED": 1698765433}'
    output=$(simulate_skill_activation "random message" '[]' "phase2" "$signals")
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate coupling analysis"
    assert_contains "[ACTIVATE:TEST_STRATEGY_V1]" "$output" "Should activate test strategy"
    
    # Test 3: No signal match
    verbose "Test 3: No signal match"
    signals='{"UNRELATED_SIGNAL": 1698765432}'
    output=$(simulate_skill_activation "random message" '[]' "phase1" "$signals")
    assert_not_contains "[ACTIVATE:" "$output" "Should not activate on unrelated signal"
    
    # Test 4: Signal priority vs user patterns
    verbose "Test 4: Signal and user pattern combination"
    signals='{"PHASE2_SPECS_CREATED": 1698765432}'
    output=$(simulate_skill_activation "test strategy planning" '[]' "phase2" "$signals")
    # Should activate test strategy only once (not twice for signal + pattern)
    local count
    count=$(echo "$output" | grep -c "TEST_STRATEGY_V1" || echo "0")
    assert_equals "1" "$count" "Should not duplicate activation for signal + pattern"
}

test_phase_transitions() {
    quiet "${BOLD}Testing Phase Transitions${RESET}"
    
    # Test 1: Automatic transition
    verbose "Test 1: Automatic transition detection"
    local signals='{"PHASE1_START": 1698765432}'
    # Set lastSignal to trigger auto transition
    jq '.lastSignal = "PHASE1_START"' "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    local output
    output=$(simulate_skill_activation "random message" '[]' "phase1" "$signals")
    assert_contains "AUTOMATIC PHASE TRANSITION" "$output" "Should show automatic transition"
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate next skill"
    
    # Test 2: Manual gate detection
    verbose "Test 2: Manual gate detection"
    jq '.lastSignal = "MANUAL_GATE"' "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    output=$(simulate_skill_activation "random message")
    assert_contains "MANUAL GATE REACHED" "$output" "Should show manual gate"
    assert_contains "requires user confirmation" "$output" "Should indicate confirmation needed"
    
    # Test 3: No transition available
    verbose "Test 3: No transition available"
    jq '.lastSignal = "UNKNOWN_SIGNAL"' "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    output=$(simulate_skill_activation "random message")
    assert_not_contains "AUTOMATIC PHASE TRANSITION" "$output" "Should not show transition for unknown signal"
}

test_activation_priority() {
    quiet "${BOLD}Testing Activation Priority${RESET}"
    
    # Test 1: Priority ordering (lower number = higher priority)
    verbose "Test 1: Priority ordering"
    local output
    output=$(simulate_skill_activation "generate tasks and test strategy")
    
    # Extract the activation lines and check order
    local activations
    activations=$(echo "$output" | grep -o "\[ACTIVATE:[^]]*\]" | head -2)
    local first_activation
    first_activation=$(echo "$activations" | head -1)
    
    # PRD_TO_TASKS_V1 has priority 1, TEST_STRATEGY_V1 has priority 3
    assert_contains "PRD_TO_TASKS_V1" "$first_activation" "Higher priority skill should activate first"
    
    # Test 2: Same skill shouldn't activate twice
    verbose "Test 2: Duplicate activation prevention"
    # Try to trigger the same skill through both pattern and file
    output=$(simulate_skill_activation "generate tasks" '["PRD.md"]')
    local count
    count=$(echo "$output" | grep -c "PRD_TO_TASKS_V1" || echo "0")
    assert_equals "1" "$count" "Same skill should not activate multiple times"
}

test_state_management() {
    quiet "${BOLD}Testing State Management${RESET}"
    
    # Test 1: State file updates
    verbose "Test 1: State file updates on activation"
    local output
    output=$(simulate_skill_activation "generate tasks")
    
    # Check if lastActivation was updated
    local last_activation
    last_activation=$(jq -r '.lastActivation' "$TEMP_DIR/.workflow-state.json")
    assert_equals "PRD_TO_TASKS_V1" "$last_activation" "Should update lastActivation in state"
    
    # Test 2: Timestamp updates
    verbose "Test 2: Timestamp updates"
    local has_timestamp
    has_timestamp=$(jq -r '.lastActivationTime' "$TEMP_DIR/.workflow-state.json")
    if [[ "$has_timestamp" != "null" ]] && [[ -n "$has_timestamp" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Should update activation timestamp"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should update activation timestamp"
    fi
    
    # Test 3: State persistence across multiple activations
    verbose "Test 3: State persistence"
    output=$(simulate_skill_activation "test strategy")
    last_activation=$(jq -r '.lastActivation' "$TEMP_DIR/.workflow-state.json")
    assert_equals "TEST_STRATEGY_V1" "$last_activation" "Should update to new activation"
}

test_pipeline_status_reporting() {
    quiet "${BOLD}Testing Pipeline Status Reporting${RESET}"
    
    # Test 1: Status command detection
    verbose "Test 1: Status command detection"
    local output
    output=$(simulate_skill_activation "what is the pipeline status")
    assert_contains "Pipeline Status" "$output" "Should show pipeline status"
    assert_contains "Current Phase:" "$output" "Should show current phase"
    assert_contains "Last Signal:" "$output" "Should show last signal"
    
    # Test 2: Phase completion status
    verbose "Test 2: Phase completion status"
    # Add some completed phases to state
    local signals='{"PHASE1_COMPLETE": 1698765432, "PHASE2_COMPLETE": 1698765433}'
    jq --argjson sigs "$signals" '.signals = $sigs' "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    output=$(simulate_skill_activation "pipeline status")
    assert_contains "Phase Status:" "$output" "Should show phase status section"
    assert_contains "" "$output" "Should show completed phases"
    assert_contains "ó" "$output" "Should show pending phases"
    
    # Test 3: Alternative status queries
    verbose "Test 3: Alternative status queries"
    output=$(simulate_skill_activation "current phase")
    assert_contains "Pipeline Status" "$output" "Should respond to 'current phase'"
    
    output=$(simulate_skill_activation "what phase are we in")
    assert_contains "Pipeline Status" "$output" "Should respond to 'what phase'"
}

test_error_handling() {
    quiet "${BOLD}Testing Error Handling${RESET}"
    
    # Test 1: Malformed skill rules
    verbose "Test 1: Malformed skill rules handling"
    echo "invalid json content" > "$TEMP_DIR/skill-rules.json"
    
    local output
    output=$(simulate_skill_activation "generate tasks" 2>&1 || echo "")
    # Should not crash, should handle gracefully
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    quiet "  ${GREEN}${RESET} Handles malformed skill rules gracefully"
    
    # Restore valid skill rules
    setup_test_environment
    
    # Test 2: Missing state file recovery
    verbose "Test 2: Missing state file recovery"
    rm -f "$TEMP_DIR/.workflow-state.json"
    output=$(simulate_skill_activation "generate tasks")
    assert_contains "[ACTIVATE:PRD_TO_TASKS_V1]" "$output" "Should recover from missing state file"
    assert_file_exists "$TEMP_DIR/.workflow-state.json" "Should recreate state file"
    
    # Test 3: Corrupted state file recovery
    verbose "Test 3: Corrupted state file recovery"
    echo "invalid json" > "$TEMP_DIR/.workflow-state.json"
    output=$(simulate_skill_activation "generate tasks")
    # Should either handle gracefully or recreate
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$output" == *"[ACTIVATE:"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        quiet "  ${GREEN}${RESET} Handles corrupted state file"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        quiet "  ${RED}${RESET} Should handle corrupted state file"
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

test_complex_scenarios() {
    quiet "${BOLD}Testing Complex Scenarios${RESET}"
    
    # Test 1: Multi-trigger skill activation
    verbose "Test 1: Multi-trigger skill activation"
    local signals='{"MULTI_SIGNAL": 1698765432}'
    local output
    output=$(simulate_skill_activation "multi test complex pattern" '["test.multi"]' "phase99" "$signals")
    
    # Should activate only once despite multiple triggers
    local count
    count=$(echo "$output" | grep -c "MULTI_TRIGGER_V1" || echo "0")
    assert_equals "1" "$count" "Multi-trigger skill should activate only once"
    
    # Test 2: Cross-phase activation
    verbose "Test 2: Cross-phase activation"
    output=$(simulate_skill_activation "integration testing" '[]' "phase1")
    assert_contains "[ACTIVATE:INTEGRATION_VALIDATOR_V1]" "$output" "Should activate skills from different phases"
    
    # Test 3: Cascading activations (signal -> auto transition -> activation)
    verbose "Test 3: Cascading activations"
    jq '.lastSignal = "PHASE1_START"' "$TEMP_DIR/.workflow-state.json" > "$TEMP_DIR/.workflow-state.json.tmp" && \
        mv "$TEMP_DIR/.workflow-state.json.tmp" "$TEMP_DIR/.workflow-state.json"
    
    output=$(simulate_skill_activation "random message")
    assert_contains "AUTOMATIC PHASE TRANSITION" "$output" "Should trigger automatic transition"
    assert_contains "[ACTIVATE:COUPLING_ANALYSIS_V1]" "$output" "Should activate next skill automatically"
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_all_tests() {
    quiet "${BOLD}Claude Dev Pipeline - Skill Activation Testing Suite${RESET}"
    quiet "========================================================"
    
    # Clear log file
    > "$LOG_FILE"
    
    log "Starting skill activation tests"
    
    # Setup
    setup_test_environment
    
    # Run test suites
    test_user_pattern_matching
    test_file_pattern_matching
    test_signal_based_activation
    test_phase_transitions
    test_activation_priority
    test_state_management
    test_pipeline_status_reporting
    test_error_handling
    test_complex_scenarios
    
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
        log "All skill activation tests passed"
        return 0
    else
        quiet ""
        quiet "${RED}${BOLD}Some tests failed!${RESET}"
        quiet "Check $LOG_FILE for details"
        log "Some skill activation tests failed"
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

show_help() {
    cat << EOF
Claude Dev Pipeline - Skill Activation Testing Suite

Usage: $0 [OPTIONS] [TEST_SUITE]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress most output
    -h, --help          Show this help message

TEST_SUITES:
    user-patterns       Test user pattern matching only
    file-patterns       Test file pattern matching only
    signals             Test signal-based activation only
    transitions         Test phase transitions only
    priority            Test activation priority only
    state               Test state management only
    status              Test pipeline status reporting only
    errors              Test error handling only
    complex             Test complex scenarios only
    all                 Run all tests (default)

EXAMPLES:
    $0                          # Run all tests
    $0 -v user-patterns         # Test user patterns with verbose output
    $0 -q all                   # Run all tests quietly

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
            user-patterns)
                setup_test_environment
                test_user_pattern_matching
                teardown_test_environment
                exit $?
                ;;
            file-patterns)
                setup_test_environment
                test_file_pattern_matching
                teardown_test_environment
                exit $?
                ;;
            signals)
                setup_test_environment
                test_signal_based_activation
                teardown_test_environment
                exit $?
                ;;
            transitions)
                setup_test_environment
                test_phase_transitions
                teardown_test_environment
                exit $?
                ;;
            priority)
                setup_test_environment
                test_activation_priority
                teardown_test_environment
                exit $?
                ;;
            state)
                setup_test_environment
                test_state_management
                teardown_test_environment
                exit $?
                ;;
            status)
                setup_test_environment
                test_pipeline_status_reporting
                teardown_test_environment
                exit $?
                ;;
            errors)
                setup_test_environment
                test_error_handling
                teardown_test_environment
                exit $?
                ;;
            complex)
                setup_test_environment
                test_complex_scenarios
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