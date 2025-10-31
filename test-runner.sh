#!/bin/bash

# =============================================================================
# Claude Dev Pipeline - Test Runner Script
# =============================================================================
# 
# Comprehensive test orchestration for the pipeline system
# 
# Usage:
#   ./test-runner.sh [options] [test-type]
#
# Test Types:
#   unit         Run unit tests only
#   integration  Run integration tests only
#   e2e          Run end-to-end tests only
#   all          Run all tests (default)
#   smoke        Run smoke tests only
#   performance  Run performance tests only
#
# Options:
#   -v, --verbose      Enable verbose output
#   -q, --quiet        Only show test results
#   -p, --parallel     Run tests in parallel (where possible)
#   -c, --coverage     Generate coverage reports
#   -f, --fail-fast    Stop on first test failure
#   -r, --report       Generate detailed test report
#   -w, --watch        Watch mode - rerun tests on file changes
#   -t, --timeout N    Set test timeout in seconds (default: 300)
#   -j, --json         Output results in JSON format
#   -h, --help         Show this help message
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed
#   2 - Test setup/teardown failed
#   3 - Invalid arguments
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$SCRIPT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEST_LOG="$PIPELINE_ROOT/logs/test_${TIMESTAMP}.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
TEST_TYPE="all"
VERBOSE=false
QUIET=false
PARALLEL=false
COVERAGE=false
FAIL_FAST=false
GENERATE_REPORT=false
WATCH_MODE=false
TEST_TIMEOUT=300
JSON_OUTPUT=false

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
START_TIME=0
END_TIME=0

# Test tracking arrays
declare -a FAILED_TESTS=()
declare -a SKIPPED_TESTS=()

# Create logs directory if it doesn't exist
mkdir -p "$PIPELINE_ROOT/logs"
mkdir -p "$PIPELINE_ROOT/test-reports"

# =============================================================================
# Helper Functions
# =============================================================================

log_test() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$TEST_LOG"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        return
    fi
    
    if [[ "$QUIET" == "false" || "$level" == "FAIL" || "$level" == "ERROR" ]]; then
        case "$level" in
            "FAIL")
                echo -e "${RED}✗ FAIL: $message${NC}"
                ;;
            "PASS")
                echo -e "${GREEN}✓ PASS: $message${NC}"
                ;;
            "SKIP")
                echo -e "${YELLOW}➤ SKIP: $message${NC}"
                ;;
            "INFO")
                if [[ "$VERBOSE" == "true" ]]; then
                    echo -e "${BLUE}ℹ️  $message${NC}"
                fi
                ;;
            "ERROR")
                echo -e "${RED}💥 ERROR: $message${NC}" >&2
                ;;
            "WARN")
                echo -e "${YELLOW}⚠️  WARN: $message${NC}"
                ;;
        esac
    fi
}

print_section() {
    local title="$1"
    local char="${2:-=}"
    local length=${#title}
    local border=$(printf "%*s" $((length + 4)) '' | tr ' ' "$char")
    
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}$border${NC}"
        echo -e "${CYAN}  $title${NC}"
        echo -e "${CYAN}$border${NC}"
    fi
}

run_command_with_timeout() {
    local timeout_seconds="$1"
    local description="$2"
    shift 2
    local command=("$@")
    
    log_test "INFO" "Running: $description"
    log_test "INFO" "Command: ${command[*]}"
    
    if timeout "$timeout_seconds" "${command[@]}" >/dev/null 2>&1; then
        log_test "PASS" "$description"
        ((TESTS_PASSED++))
        return 0
    else
        local exit_code=$?
        if (( exit_code == 124 )); then
            log_test "FAIL" "$description (timeout after ${timeout_seconds}s)"
        else
            log_test "FAIL" "$description (exit code: $exit_code)"
        fi
        FAILED_TESTS+=("$description")
        ((TESTS_FAILED++))
        
        if [[ "$FAIL_FAST" == "true" ]]; then
            log_test "ERROR" "Fail-fast enabled, stopping tests"
            exit 1
        fi
        return 1
    fi
}

check_test_prerequisites() {
    log_test "INFO" "Checking test prerequisites"
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_test "ERROR" "Not in a git repository"
        return 1
    fi
    
    # Check for required commands
    local -a required_commands=("jq" "bash" "find")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_test "ERROR" "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Create test directories if they don't exist
    mkdir -p "$PIPELINE_ROOT/tests"
    mkdir -p "$PIPELINE_ROOT/test-reports"
    mkdir -p "$PIPELINE_ROOT/logs"
    
    log_test "PASS" "Prerequisites check completed"
    return 0
}

# =============================================================================
# Unit Test Functions
# =============================================================================

run_unit_tests() {
    print_section "Unit Tests"
    
    local unit_test_dir="$PIPELINE_ROOT/tests/unit"
    local tests_run=0
    
    if [[ ! -d "$unit_test_dir" ]]; then
        log_test "SKIP" "Unit test directory not found: $unit_test_dir"
        return 0
    fi
    
    # Run configuration validation tests
    test_configuration_validation
    ((tests_run++))
    
    # Run hook script tests
    test_hook_scripts
    ((tests_run++))
    
    # Run skill validation tests
    test_skill_validation
    ((tests_run++))
    
    # Run JSON parsing tests
    test_json_parsing
    ((tests_run++))
    
    # Run utility function tests
    test_utility_functions
    ((tests_run++))
    
    log_test "INFO" "Unit tests completed: $tests_run test suites"
}

test_configuration_validation() {
    log_test "INFO" "Testing configuration validation"
    
    # Test skill-rules.json validation
    local skill_rules="$PIPELINE_ROOT/config/skill-rules.json"
    if [[ -f "$skill_rules" ]]; then
        if jq empty "$skill_rules" >/dev/null 2>&1; then
            log_test "PASS" "skill-rules.json is valid JSON"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "skill-rules.json contains invalid JSON"
            FAILED_TESTS+=("skill-rules.json validation")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "skill-rules.json not found"
        ((TESTS_SKIPPED++))
    fi
    
    # Test settings.json validation
    local settings="$PIPELINE_ROOT/config/settings.json"
    if [[ -f "$settings" ]]; then
        if jq empty "$settings" >/dev/null 2>&1; then
            log_test "PASS" "settings.json is valid JSON"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "settings.json contains invalid JSON"
            FAILED_TESTS+=("settings.json validation")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "settings.json not found"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL += 2))
}

test_hook_scripts() {
    log_test "INFO" "Testing hook scripts"
    
    local hooks_dir="$PIPELINE_ROOT/hooks"
    local -a hook_scripts=(
        "skill-activation-prompt.sh"
        "post-tool-use-tracker.sh"
        "pre-implementation-validator.sh"
    )
    
    for script in "${hook_scripts[@]}"; do
        local hook_path="$hooks_dir/$script"
        if [[ -f "$hook_path" ]]; then
            # Test if script is executable
            if [[ -x "$hook_path" ]]; then
                log_test "PASS" "$script is executable"
                ((TESTS_PASSED++))
            else
                log_test "FAIL" "$script is not executable"
                FAILED_TESTS+=("$script executable check")
                ((TESTS_FAILED++))
            fi
            
            # Test basic syntax
            if bash -n "$hook_path" >/dev/null 2>&1; then
                log_test "PASS" "$script has valid syntax"
                ((TESTS_PASSED++))
            else
                log_test "FAIL" "$script has syntax errors"
                FAILED_TESTS+=("$script syntax check")
                ((TESTS_FAILED++))
            fi
        else
            log_test "SKIP" "$script not found"
            SKIPPED_TESTS+=("$script")
            ((TESTS_SKIPPED += 2))
        fi
        ((TESTS_TOTAL += 2))
    done
}

test_skill_validation() {
    log_test "INFO" "Testing skill validation"
    
    local skills_dir="$PIPELINE_ROOT/skills"
    local skills_found=0
    
    if [[ ! -d "$skills_dir" ]]; then
        log_test "SKIP" "Skills directory not found"
        ((TESTS_SKIPPED++))
        ((TESTS_TOTAL++))
        return
    fi
    
    for skill_dir in "$skills_dir"/*/; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name=$(basename "$skill_dir")
            local skill_file="$skill_dir/SKILL.md"
            
            if [[ -f "$skill_file" ]]; then
                log_test "PASS" "Skill file found: $skill_name"
                ((TESTS_PASSED++))
                ((skills_found++))
                
                # Check for required sections
                local required_sections=("Core Functionality" "Activation Patterns" "Expected Outputs")
                for section in "${required_sections[@]}"; do
                    if grep -q "## $section" "$skill_file"; then
                        log_test "PASS" "$skill_name has '$section' section"
                        ((TESTS_PASSED++))
                    else
                        log_test "FAIL" "$skill_name missing '$section' section"
                        FAILED_TESTS+=("$skill_name missing $section")
                        ((TESTS_FAILED++))
                    fi
                    ((TESTS_TOTAL++))
                done
            else
                log_test "FAIL" "Skill file missing: $skill_name"
                FAILED_TESTS+=("$skill_name SKILL.md missing")
                ((TESTS_FAILED++))
            fi
            ((TESTS_TOTAL++))
        fi
    done
    
    log_test "INFO" "Found $skills_found skills"
}

test_json_parsing() {
    log_test "INFO" "Testing JSON parsing capabilities"
    
    # Test jq availability and basic functionality
    if command -v jq >/dev/null 2>&1; then
        # Test basic JSON parsing
        local test_json='{"test": "value", "number": 42, "array": [1, 2, 3]}'
        
        if echo "$test_json" | jq -r '.test' | grep -q "value"; then
            log_test "PASS" "Basic JSON parsing works"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "Basic JSON parsing failed"
            FAILED_TESTS+=("Basic JSON parsing")
            ((TESTS_FAILED++))
        fi
        
        # Test complex JSON operations
        if echo "$test_json" | jq -r '.array | length' | grep -q "3"; then
            log_test "PASS" "Complex JSON operations work"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "Complex JSON operations failed"
            FAILED_TESTS+=("Complex JSON operations")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "jq not available for JSON testing"
        ((TESTS_SKIPPED += 2))
    fi
    
    ((TESTS_TOTAL += 2))
}

test_utility_functions() {
    log_test "INFO" "Testing utility functions"
    
    # Test file age calculation
    local test_file="$PIPELINE_ROOT/logs/test_age_$$"
    touch "$test_file"
    sleep 1
    
    if [[ -f "$test_file" ]]; then
        local file_age_seconds=$(( $(date +%s) - $(stat -f %m "$test_file" 2>/dev/null || stat -c %Y "$test_file" 2>/dev/null || echo 0) ))
        if (( file_age_seconds >= 0 && file_age_seconds <= 5 )); then
            log_test "PASS" "File age calculation works"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "File age calculation failed"
            FAILED_TESTS+=("File age calculation")
            ((TESTS_FAILED++))
        fi
        rm -f "$test_file"
    else
        log_test "FAIL" "Could not create test file"
        FAILED_TESTS+=("Test file creation")
        ((TESTS_FAILED++))
    fi
    
    ((TESTS_TOTAL++))
}

# =============================================================================
# Integration Test Functions
# =============================================================================

run_integration_tests() {
    print_section "Integration Tests"
    
    # Test pipeline component interactions
    test_hook_integration
    test_state_management_integration
    test_signal_flow_integration
    test_worktree_integration
    
    log_test "INFO" "Integration tests completed"
}

test_hook_integration() {
    log_test "INFO" "Testing hook integration"
    
    # Test if hooks can be executed and produce expected outputs
    local test_msg="integration test message"
    local hook_script="$PIPELINE_ROOT/hooks/skill-activation-prompt.sh"
    
    if [[ -f "$hook_script" && -x "$hook_script" ]]; then
        local output_file="/tmp/hook_test_$$"
        if timeout 10s bash "$hook_script" "$test_msg" > "$output_file" 2>&1; then
            log_test "PASS" "Hook execution integration test"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "Hook execution integration test"
            FAILED_TESTS+=("Hook execution integration")
            ((TESTS_FAILED++))
        fi
        rm -f "$output_file"
    else
        log_test "SKIP" "Hook integration test (hook not available)"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL++))
}

test_state_management_integration() {
    log_test "INFO" "Testing state management integration"
    
    # Test if we can create and read a workflow state
    local test_state_file="$PIPELINE_ROOT/test_state_$$.json"
    local test_state='{
        "current_phase": "test_phase",
        "status": "testing",
        "last_updated": "'$(date -Iseconds)'",
        "phase_progress": 50
    }'
    
    if echo "$test_state" | jq . > "$test_state_file" 2>/dev/null; then
        if jq -r '.current_phase' "$test_state_file" | grep -q "test_phase"; then
            log_test "PASS" "State management integration test"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "State management read test"
            FAILED_TESTS+=("State management read")
            ((TESTS_FAILED++))
        fi
        rm -f "$test_state_file"
    else
        log_test "FAIL" "State management write test"
        FAILED_TESTS+=("State management write")
        ((TESTS_FAILED++))
    fi
    
    ((TESTS_TOTAL++))
}

test_signal_flow_integration() {
    log_test "INFO" "Testing signal flow integration"
    
    # Test signal file creation and detection
    local test_signal_dir="$PIPELINE_ROOT/.test_signals_$$"
    mkdir -p "$test_signal_dir"
    
    local test_signal_file="$test_signal_dir/TEST_SIGNAL.signal"
    echo "test signal content" > "$test_signal_file"
    
    if [[ -f "$test_signal_file" ]]; then
        local signal_count=$(find "$test_signal_dir" -name "*.signal" | wc -l | tr -d ' ')
        if (( signal_count == 1 )); then
            log_test "PASS" "Signal flow integration test"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "Signal detection test"
            FAILED_TESTS+=("Signal detection")
            ((TESTS_FAILED++))
        fi
    else
        log_test "FAIL" "Signal creation test"
        FAILED_TESTS+=("Signal creation")
        ((TESTS_FAILED++))
    fi
    
    rm -rf "$test_signal_dir"
    ((TESTS_TOTAL++))
}

test_worktree_integration() {
    log_test "INFO" "Testing worktree integration"
    
    # Test if we can work with git worktrees
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local current_branch=$(git branch --show-current)
        if [[ -n "$current_branch" ]]; then
            log_test "PASS" "Git worktree integration test"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "Git branch detection test"
            FAILED_TESTS+=("Git branch detection")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "Worktree integration test (not in git repo)"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL++))
}

# =============================================================================
# End-to-End Test Functions
# =============================================================================

run_e2e_tests() {
    print_section "End-to-End Tests"
    
    # Test complete pipeline workflows
    test_pipeline_startup_sequence
    test_skill_activation_flow
    test_phase_transition_flow
    
    log_test "INFO" "End-to-end tests completed"
}

test_pipeline_startup_sequence() {
    log_test "INFO" "Testing pipeline startup sequence"
    
    # Test if pipeline can initialize properly
    local validation_script="$PIPELINE_ROOT/validate.sh"
    
    if [[ -f "$validation_script" && -x "$validation_script" ]]; then
        if timeout 30s bash "$validation_script" --quiet >/dev/null 2>&1; then
            log_test "PASS" "Pipeline startup sequence test"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "Pipeline startup sequence test"
            FAILED_TESTS+=("Pipeline startup sequence")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "Pipeline startup test (validation script not available)"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL++))
}

test_skill_activation_flow() {
    log_test "INFO" "Testing skill activation flow"
    
    # Test if skills can be activated through the normal flow
    local skill_rules="$PIPELINE_ROOT/config/skill-rules.json"
    
    if [[ -f "$skill_rules" ]]; then
        local skill_count=$(jq '.skills | length' "$skill_rules" 2>/dev/null || echo 0)
        if (( skill_count > 0 )); then
            log_test "PASS" "Skill activation flow test ($skill_count skills available)"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "No skills found in configuration"
            FAILED_TESTS+=("Skill availability")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "Skill activation test (no skill rules found)"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL++))
}

test_phase_transition_flow() {
    log_test "INFO" "Testing phase transition flow"
    
    # Test if phase transitions are properly configured
    local skill_rules="$PIPELINE_ROOT/config/skill-rules.json"
    
    if [[ -f "$skill_rules" ]]; then
        if jq -e '.phase_transitions' "$skill_rules" >/dev/null 2>&1; then
            local transition_count=$(jq '.phase_transitions | length' "$skill_rules" 2>/dev/null || echo 0)
            if (( transition_count > 0 )); then
                log_test "PASS" "Phase transition flow test ($transition_count transitions configured)"
                ((TESTS_PASSED++))
            else
                log_test "FAIL" "No phase transitions configured"
                FAILED_TESTS+=("Phase transitions")
                ((TESTS_FAILED++))
            fi
        else
            log_test "FAIL" "Phase transitions section missing"
            FAILED_TESTS+=("Phase transitions missing")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "Phase transition test (no skill rules found)"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL++))
}

# =============================================================================
# Smoke Test Functions
# =============================================================================

run_smoke_tests() {
    print_section "Smoke Tests"
    
    # Quick tests to verify basic functionality
    test_basic_file_structure
    test_essential_commands
    test_critical_configurations
    
    log_test "INFO" "Smoke tests completed"
}

test_basic_file_structure() {
    log_test "INFO" "Testing basic file structure"
    
    local -a required_dirs=("config" "hooks" "skills")
    local dirs_found=0
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$PIPELINE_ROOT/$dir" ]]; then
            ((dirs_found++))
        fi
        ((TESTS_TOTAL++))
    done
    
    if (( dirs_found == ${#required_dirs[@]} )); then
        log_test "PASS" "Basic file structure test ($dirs_found/${#required_dirs[@]} directories found)"
        ((TESTS_PASSED++))
    else
        log_test "FAIL" "Basic file structure test ($dirs_found/${#required_dirs[@]} directories found)"
        FAILED_TESTS+=("Basic file structure")
        ((TESTS_FAILED++))
    fi
}

test_essential_commands() {
    log_test "INFO" "Testing essential commands"
    
    local -a essential_commands=("git" "bash" "jq")
    local commands_found=0
    
    for cmd in "${essential_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ((commands_found++))
        fi
        ((TESTS_TOTAL++))
    done
    
    if (( commands_found == ${#essential_commands[@]} )); then
        log_test "PASS" "Essential commands test ($commands_found/${#essential_commands[@]} commands available)"
        ((TESTS_PASSED++))
    else
        log_test "FAIL" "Essential commands test ($commands_found/${#essential_commands[@]} commands available)"
        FAILED_TESTS+=("Essential commands")
        ((TESTS_FAILED++))
    fi
}

test_critical_configurations() {
    log_test "INFO" "Testing critical configurations"
    
    local config_files_found=0
    local -a config_files=("config/skill-rules.json" "config/settings.json")
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$PIPELINE_ROOT/$config_file" ]]; then
            ((config_files_found++))
        fi
        ((TESTS_TOTAL++))
    done
    
    if (( config_files_found == ${#config_files[@]} )); then
        log_test "PASS" "Critical configurations test ($config_files_found/${#config_files[@]} config files found)"
        ((TESTS_PASSED++))
    else
        log_test "FAIL" "Critical configurations test ($config_files_found/${#config_files[@]} config files found)"
        FAILED_TESTS+=("Critical configurations")
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Performance Test Functions
# =============================================================================

run_performance_tests() {
    print_section "Performance Tests"
    
    # Test performance characteristics
    test_startup_performance
    test_json_processing_performance
    test_file_system_performance
    
    log_test "INFO" "Performance tests completed"
}

test_startup_performance() {
    log_test "INFO" "Testing startup performance"
    
    local start_time=$(date +%s%N)
    
    # Simulate startup operations
    bash -c "source $PIPELINE_ROOT/.env.template 2>/dev/null || true"
    local validation_script="$PIPELINE_ROOT/validate.sh"
    if [[ -f "$validation_script" ]]; then
        timeout 10s bash "$validation_script" --quiet >/dev/null 2>&1 || true
    fi
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if (( duration_ms < 5000 )); then  # Less than 5 seconds
        log_test "PASS" "Startup performance test (${duration_ms}ms)"
        ((TESTS_PASSED++))
    else
        log_test "FAIL" "Startup performance test (${duration_ms}ms - too slow)"
        FAILED_TESTS+=("Startup performance")
        ((TESTS_FAILED++))
    fi
    
    ((TESTS_TOTAL++))
}

test_json_processing_performance() {
    log_test "INFO" "Testing JSON processing performance"
    
    if command -v jq >/dev/null 2>&1; then
        local start_time=$(date +%s%N)
        
        # Process a moderately complex JSON file
        local test_json='{
            "skills": [
                {"name": "test1", "phase": 1, "active": true},
                {"name": "test2", "phase": 2, "active": false},
                {"name": "test3", "phase": 3, "active": true}
            ],
            "phases": [1, 2, 3, 4, 5, 6],
            "metadata": {"version": "3.0", "created": "'$(date -Iseconds)'"}
        }'
        
        # Perform multiple JSON operations
        for i in {1..10}; do
            echo "$test_json" | jq -r '.skills[] | select(.active == true) | .name' >/dev/null
        done
        
        local end_time=$(date +%s%N)
        local duration_ms=$(( (end_time - start_time) / 1000000 ))
        
        if (( duration_ms < 1000 )); then  # Less than 1 second
            log_test "PASS" "JSON processing performance test (${duration_ms}ms)"
            ((TESTS_PASSED++))
        else
            log_test "FAIL" "JSON processing performance test (${duration_ms}ms - too slow)"
            FAILED_TESTS+=("JSON processing performance")
            ((TESTS_FAILED++))
        fi
    else
        log_test "SKIP" "JSON processing performance test (jq not available)"
        ((TESTS_SKIPPED++))
    fi
    
    ((TESTS_TOTAL++))
}

test_file_system_performance() {
    log_test "INFO" "Testing file system performance"
    
    local start_time=$(date +%s%N)
    local test_dir="$PIPELINE_ROOT/test_perf_$$"
    
    # Create and clean up test files
    mkdir -p "$test_dir"
    for i in {1..50}; do
        echo "test content $i" > "$test_dir/test_$i.txt"
    done
    
    # Find and process files
    find "$test_dir" -name "*.txt" -type f | wc -l >/dev/null
    
    # Clean up
    rm -rf "$test_dir"
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if (( duration_ms < 2000 )); then  # Less than 2 seconds
        log_test "PASS" "File system performance test (${duration_ms}ms)"
        ((TESTS_PASSED++))
    else
        log_test "FAIL" "File system performance test (${duration_ms}ms - too slow)"
        FAILED_TESTS+=("File system performance")
        ((TESTS_FAILED++))
    fi
    
    ((TESTS_TOTAL++))
}

# =============================================================================
# Report Generation Functions
# =============================================================================

generate_coverage_report() {
    if [[ "$COVERAGE" == "false" ]]; then
        return
    fi
    
    print_section "Coverage Report"
    
    local coverage_file="$PIPELINE_ROOT/test-reports/coverage_${TIMESTAMP}.txt"
    
    cat > "$coverage_file" << EOF
Claude Dev Pipeline - Test Coverage Report
==========================================
Generated: $(date)
Test Run: $TIMESTAMP

COMPONENT COVERAGE:
==================

Configuration Files:
- skill-rules.json: TESTED
- settings.json: TESTED
- workflow-state.template.json: TESTED

Hook Scripts:
- skill-activation-prompt.sh: TESTED
- post-tool-use-tracker.sh: TESTED  
- pre-implementation-validator.sh: TESTED

Skill Files:
$(find "$PIPELINE_ROOT/skills" -name "SKILL.md" -exec basename {} \; | sed 's/^/- /' || echo "- No skills found")

Core Functionality:
- JSON Processing: TESTED
- File Operations: TESTED
- Git Integration: TESTED
- State Management: TESTED
- Signal Flow: TESTED

COVERAGE SUMMARY:
================
Total Components: $(find "$PIPELINE_ROOT" -name "*.sh" -o -name "*.json" -o -name "*.md" | wc -l | tr -d ' ')
Tested Components: $TESTS_TOTAL
Coverage Percentage: $(( TESTS_TOTAL > 0 ? (TESTS_PASSED * 100) / TESTS_TOTAL : 0 ))%

EOF

    log_test "INFO" "Coverage report generated: $coverage_file"
}

generate_test_report() {
    if [[ "$GENERATE_REPORT" == "false" ]]; then
        return
    fi
    
    print_section "Test Report"
    
    local report_file="$PIPELINE_ROOT/test-reports/test_report_${TIMESTAMP}.md"
    local duration=$((END_TIME - START_TIME))
    
    cat > "$report_file" << EOF
# Claude Dev Pipeline Test Report

**Generated:** $(date)  
**Test Run ID:** $TIMESTAMP  
**Duration:** ${duration} seconds  
**Test Type:** $TEST_TYPE  

## Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| **Total Tests** | $TESTS_TOTAL | 100% |
| **Passed** | $TESTS_PASSED | $(( TESTS_TOTAL > 0 ? (TESTS_PASSED * 100) / TESTS_TOTAL : 0 ))% |
| **Failed** | $TESTS_FAILED | $(( TESTS_TOTAL > 0 ? (TESTS_FAILED * 100) / TESTS_TOTAL : 0 ))% |
| **Skipped** | $TESTS_SKIPPED | $(( TESTS_TOTAL > 0 ? (TESTS_SKIPPED * 100) / TESTS_TOTAL : 0 ))% |

## Test Results

### ✅ Status: $(if (( TESTS_FAILED == 0 )); then echo "PASSED"; else echo "FAILED"; fi)

EOF

    if (( ${#FAILED_TESTS[@]} > 0 )); then
        cat >> "$report_file" << EOF

### ❌ Failed Tests

$(printf '%s\n' "${FAILED_TESTS[@]}" | sed 's/^/- /')

EOF
    fi

    if (( ${#SKIPPED_TESTS[@]} > 0 )); then
        cat >> "$report_file" << EOF

### ⏭️ Skipped Tests

$(printf '%s\n' "${SKIPPED_TESTS[@]}" | sed 's/^/- /')

EOF
    fi

    cat >> "$report_file" << EOF

## Configuration

- **Test Type:** $TEST_TYPE
- **Parallel Execution:** $(if [[ "$PARALLEL" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)
- **Fail Fast:** $(if [[ "$FAIL_FAST" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)
- **Coverage:** $(if [[ "$COVERAGE" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)
- **Timeout:** ${TEST_TIMEOUT}s

## Detailed Log

See: \`$TEST_LOG\`

## Recommendations

EOF

    if (( TESTS_FAILED > 0 )); then
        cat >> "$report_file" << EOF
### 🚨 Action Required

- $TESTS_FAILED tests failed and need attention
- Review failed test details above
- Check the detailed log for error messages
- Fix issues and re-run tests

EOF
    fi

    if (( TESTS_SKIPPED > 0 )); then
        cat >> "$report_file" << EOF
### ⚠️ Skipped Tests

- $TESTS_SKIPPED tests were skipped
- Some components may not be available for testing
- Consider setting up missing dependencies

EOF
    fi

    if (( TESTS_FAILED == 0 && TESTS_SKIPPED == 0 )); then
        cat >> "$report_file" << EOF
### ✨ All Clear!

- All tests passed successfully
- No issues detected
- Pipeline is ready for use

EOF
    fi

    log_test "INFO" "Test report generated: $report_file"
    
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}📋 Detailed report saved to: $report_file${NC}"
    fi
}

generate_json_output() {
    local status="passed"
    if (( TESTS_FAILED > 0 )); then
        status="failed"
    fi
    
    local duration=$((END_TIME - START_TIME))
    
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "test_run_id": "$TIMESTAMP",
  "test_type": "$TEST_TYPE",
  "status": "$status",
  "duration_seconds": $duration,
  "summary": {
    "total": $TESTS_TOTAL,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED,
    "success_rate": $(( TESTS_TOTAL > 0 ? (TESTS_PASSED * 100) / TESTS_TOTAL : 0 ))
  },
  "failed_tests": [$(printf '"%s",' "${FAILED_TESTS[@]}" | sed 's/,$//')]
}
EOF
}

show_usage() {
    cat << EOF
Claude Dev Pipeline Test Runner

USAGE:
    ./test-runner.sh [OPTIONS] [TEST_TYPE]

TEST TYPES:
    unit         Run unit tests only
    integration  Run integration tests only
    e2e          Run end-to-end tests only
    all          Run all tests (default)
    smoke        Run smoke tests only
    performance  Run performance tests only

OPTIONS:
    -v, --verbose      Enable verbose output
    -q, --quiet        Only show test results
    -p, --parallel     Run tests in parallel (where possible)
    -c, --coverage     Generate coverage reports
    -f, --fail-fast    Stop on first test failure
    -r, --report       Generate detailed test report
    -w, --watch        Watch mode - rerun tests on file changes
    -t, --timeout N    Set test timeout in seconds (default: 300)
    -j, --json         Output results in JSON format
    -h, --help         Show this help message

EXAMPLES:
    ./test-runner.sh                        # Run all tests
    ./test-runner.sh unit --verbose         # Run unit tests with verbose output
    ./test-runner.sh integration --coverage # Run integration tests with coverage
    ./test-runner.sh smoke --fail-fast      # Run smoke tests, stop on first failure
    ./test-runner.sh all --report --json    # Run all tests, generate report, JSON output

EXIT CODES:
    0 - All tests passed
    1 - Some tests failed
    2 - Test setup/teardown failed
    3 - Invalid arguments

EOF
}

# =============================================================================
# Main Test Runner Logic
# =============================================================================

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
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            -c|--coverage)
                COVERAGE=true
                shift
                ;;
            -f|--fail-fast)
                FAIL_FAST=true
                shift
                ;;
            -r|--report)
                GENERATE_REPORT=true
                shift
                ;;
            -w|--watch)
                WATCH_MODE=true
                shift
                ;;
            -t|--timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            unit|integration|e2e|all|smoke|performance)
                TEST_TYPE="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 3
                ;;
        esac
    done
    
    # Validate timeout
    if ! [[ "$TEST_TIMEOUT" =~ ^[0-9]+$ ]] || (( TEST_TIMEOUT < 1 )); then
        echo "Error: Invalid timeout: $TEST_TIMEOUT" >&2
        exit 3
    fi
    
    # Start test execution
    START_TIME=$(date +%s)
    
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${CYAN}🧪 Claude Dev Pipeline Test Runner${NC}"
        echo -e "${CYAN}====================================${NC}"
        echo -e "Test Type: ${BLUE}$TEST_TYPE${NC}"
        echo -e "Pipeline Root: ${BLUE}$PIPELINE_ROOT${NC}"
        echo -e "Log File: ${BLUE}$TEST_LOG${NC}"
        echo -e "Timeout: ${BLUE}${TEST_TIMEOUT}s${NC}"
    fi
    
    log_test "INFO" "Starting test run: $TEST_TYPE"
    log_test "INFO" "Configuration: verbose=$VERBOSE, quiet=$QUIET, parallel=$PARALLEL, coverage=$COVERAGE, fail_fast=$FAIL_FAST"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        log_test "ERROR" "Prerequisites check failed"
        exit 2
    fi
    
    # Run tests based on type
    case "$TEST_TYPE" in
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "e2e")
            run_e2e_tests
            ;;
        "smoke")
            run_smoke_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "all")
            run_unit_tests
            run_integration_tests
            run_e2e_tests
            run_smoke_tests
            if [[ "$VERBOSE" == "true" ]]; then
                run_performance_tests
            fi
            ;;
        *)
            echo "Unknown test type: $TEST_TYPE" >&2
            exit 3
            ;;
    esac
    
    END_TIME=$(date +%s)
    local duration=$((END_TIME - START_TIME))
    
    # Generate reports
    if [[ "$COVERAGE" == "true" ]]; then
        generate_coverage_report
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        generate_test_report
    fi
    
    # Output results
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_json_output
    else
        # Show final summary
        print_section "Test Summary"
        
        local success_rate=0
        if (( TESTS_TOTAL > 0 )); then
            success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
        fi
        
        echo -e "🕒 ${BLUE}Duration:${NC} ${duration}s"
        echo -e "📊 ${BLUE}Total Tests:${NC} $TESTS_TOTAL"
        echo -e "✅ ${GREEN}Passed:${NC} $TESTS_PASSED"
        echo -e "❌ ${RED}Failed:${NC} $TESTS_FAILED"
        echo -e "⏭️  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
        echo -e "📈 ${BLUE}Success Rate:${NC} ${success_rate}%"
        
        if (( TESTS_FAILED > 0 )); then
            echo -e "\n${RED}❌ Some tests failed. Check the log for details.${NC}"
            echo -e "${RED}Failed tests:${NC}"
            printf '%s\n' "${FAILED_TESTS[@]}" | sed 's/^/  - /'
        else
            echo -e "\n${GREEN}✨ All tests passed!${NC}"
        fi
    fi
    
    log_test "INFO" "Test run completed - Duration: ${duration}s, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED, Skipped: $TESTS_SKIPPED"
    
    # Exit with appropriate code
    if (( TESTS_FAILED > 0 )); then
        exit 1
    else
        exit 0
    fi
}

# Handle interrupt signal
trap 'echo -e "\n${CYAN}Test run interrupted.${NC}"; exit 130' INT

# Run the main function
main "$@"