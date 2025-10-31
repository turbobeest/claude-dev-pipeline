#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Test Runner
# =============================================================================
# 
# Comprehensive test runner for the entire pipeline testing suite.
# Orchestrates execution of all test files and generates consolidated reports.
#
# Features:
# - Run individual test suites or all tests
# - Parallel test execution support
# - Detailed reporting with pass/fail statistics
# - HTML report generation
# - CI/CD integration support
# - Test environment isolation
# - Automatic cleanup
#
# =============================================================================

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
REPORTS_DIR="$TEST_DIR/reports"
LOG_DIR="$TEST_DIR/logs"
TEMP_DIR="$TEST_DIR/temp"

# Test suite files
HOOK_TESTS="$TEST_DIR/test-hooks.sh"
SKILL_TESTS="$TEST_DIR/test-skill-activation.sh"
WORKFLOW_TESTS="$TEST_DIR/test-full-workflow.sh"

# Global test tracking
TOTAL_TESTS_RUN=0
TOTAL_TESTS_PASSED=0
TOTAL_TESTS_FAILED=0
START_TIME=$(date +%s)

# Options
VERBOSE=${VERBOSE:-false}
QUIET=${QUIET:-false}
PARALLEL=${PARALLEL:-false}
GENERATE_HTML=${GENERATE_HTML:-true}
CLEAN_BEFORE=${CLEAN_BEFORE:-true}
FAIL_FAST=${FAIL_FAST:-false}

# Colors for output
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
# Utility Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/test-runner.log"
}

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  ${BLUE}[VERBOSE]${RESET} $*" | tee -a "$LOG_DIR/test-runner.log"
    fi
}

quiet() {
    if [[ "$QUIET" != "true" ]]; then
        echo "$*"
    fi
}

error() {
    echo "${RED}[ERROR]${RESET} $*" >&2
    log "ERROR: $*"
}

warn() {
    echo "${YELLOW}[WARN]${RESET} $*" >&2
    log "WARN: $*"
}

info() {
    echo "${CYAN}[INFO]${RESET} $*"
    log "INFO: $*"
}

success() {
    echo "${GREEN}[SUCCESS]${RESET} $*"
    log "SUCCESS: $*"
}

# =============================================================================
# Setup and Cleanup Functions
# =============================================================================

setup_test_environment() {
    verbose "Setting up test environment"
    
    # Create directories
    mkdir -p "$REPORTS_DIR" "$LOG_DIR" "$TEMP_DIR"
    
    # Clean previous results if requested
    if [[ "$CLEAN_BEFORE" == "true" ]]; then
        verbose "Cleaning previous test results"
        rm -f "$REPORTS_DIR"/* "$LOG_DIR"/* 2>/dev/null || true
    fi
    
    # Initialize log file
    > "$LOG_DIR/test-runner.log"
    
    # Validate test files exist
    local missing_files=()
    [[ ! -f "$HOOK_TESTS" ]] && missing_files+=("$HOOK_TESTS")
    [[ ! -f "$SKILL_TESTS" ]] && missing_files+=("$SKILL_TESTS")
    [[ ! -f "$WORKFLOW_TESTS" ]] && missing_files+=("$WORKFLOW_TESTS")
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        error "Missing test files:"
        for file in "${missing_files[@]}"; do
            error "  - $file"
        done
        exit 1
    fi
    
    # Make test files executable
    chmod +x "$HOOK_TESTS" "$SKILL_TESTS" "$WORKFLOW_TESTS"
    
    verbose "Test environment setup complete"
}

cleanup_test_environment() {
    verbose "Cleaning up test environment"
    
    # Clean up temp directories
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    
    # Clean up any test artifacts in subdirectories
    find "$TEST_DIR" -name "temp" -type d -exec rm -rf {} \; 2>/dev/null || true
    find "$TEST_DIR" -name "*.tmp" -delete 2>/dev/null || true
    
    verbose "Cleanup complete"
}

# =============================================================================
# Test Execution Functions
# =============================================================================

run_test_suite() {
    local test_file="$1"
    local suite_name="$2"
    local args="${3:-}"
    
    local report_file="$REPORTS_DIR/${suite_name}-report.txt"
    local start_time=$(date +%s)
    
    quiet ""
    quiet "${BOLD}${MAGENTA}Running $suite_name Test Suite${RESET}"
    quiet "=================================================="
    
    verbose "Executing: $test_file $args"
    
    # Run the test suite with appropriate flags
    local env_vars=""
    [[ "$VERBOSE" == "true" ]] && env_vars="VERBOSE=true"
    [[ "$QUIET" == "true" ]] && env_vars="$env_vars QUIET=true"
    
    if eval "$env_vars bash '$test_file' $args" 2>&1 | tee "$report_file"; then
        local exit_code=0
    else
        local exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Parse results from the report
    local tests_run=0
    local tests_passed=0
    local tests_failed=0
    
    if [[ -f "$report_file" ]]; then
        tests_run=$(grep "Tests Run:" "$report_file" | tail -1 | awk '{print $3}' || echo "0")
        tests_passed=$(grep "Tests Passed:" "$report_file" | tail -1 | awk '{print $3}' || echo "0")
        tests_failed=$(grep "Tests Failed:" "$report_file" | tail -1 | awk '{print $3}' || echo "0")
    fi
    
    # Update global counters
    TOTAL_TESTS_RUN=$((TOTAL_TESTS_RUN + tests_run))
    TOTAL_TESTS_PASSED=$((TOTAL_TESTS_PASSED + tests_passed))
    TOTAL_TESTS_FAILED=$((TOTAL_TESTS_FAILED + tests_failed))
    
    # Log results
    if [[ $exit_code -eq 0 && $tests_failed -eq 0 ]]; then
        success "$suite_name: ${tests_passed}/${tests_run} tests passed (${duration}s)"
    else
        error "$suite_name: ${tests_failed}/${tests_run} tests failed (${duration}s)"
        
        if [[ "$FAIL_FAST" == "true" ]]; then
            error "Fail-fast mode enabled, stopping test execution"
            return $exit_code
        fi
    fi
    
    return $exit_code
}

run_parallel_tests() {
    quiet "${BOLD}Running tests in parallel${RESET}"
    
    # Start test suites in background
    local pids=()
    
    # Hook tests
    (
        export VERBOSE="$VERBOSE" QUIET="true"
        run_test_suite "$HOOK_TESTS" "hooks" "all" > "$REPORTS_DIR/hooks-parallel.log" 2>&1
        echo $? > "$TEMP_DIR/hooks.exit"
    ) &
    pids+=($!)
    
    # Skill activation tests  
    (
        export VERBOSE="$VERBOSE" QUIET="true"
        run_test_suite "$SKILL_TESTS" "skill-activation" "all" > "$REPORTS_DIR/skill-parallel.log" 2>&1
        echo $? > "$TEMP_DIR/skill.exit"
    ) &
    pids+=($!)
    
    # Workflow tests
    (
        export VERBOSE="$VERBOSE" QUIET="true"
        run_test_suite "$WORKFLOW_TESTS" "workflow" "all" > "$REPORTS_DIR/workflow-parallel.log" 2>&1
        echo $? > "$TEMP_DIR/workflow.exit"
    ) &
    pids+=($!)
    
    # Wait for all background jobs
    local overall_exit=0
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            overall_exit=1
        fi
    done
    
    # Collect results
    quiet ""
    quiet "${BOLD}Parallel Test Results:${RESET}"
    
    local suites=("hooks" "skill-activation" "workflow")
    for suite in "${suites[@]}"; do
        local exit_file="$TEMP_DIR/${suite%%-*}.exit"
        local log_file="$REPORTS_DIR/${suite}-parallel.log"
        
        if [[ -f "$exit_file" ]] && [[ $(cat "$exit_file") -eq 0 ]]; then
            success "$suite: PASSED"
        else
            error "$suite: FAILED"
            if [[ -f "$log_file" ]]; then
                verbose "Error details in: $log_file"
            fi
        fi
    done
    
    return $overall_exit
}

run_sequential_tests() {
    quiet "${BOLD}Running tests sequentially${RESET}"
    
    local overall_exit=0
    
    # Hook tests
    if ! run_test_suite "$HOOK_TESTS" "hooks" "all"; then
        overall_exit=1
        [[ "$FAIL_FAST" == "true" ]] && return $overall_exit
    fi
    
    # Skill activation tests
    if ! run_test_suite "$SKILL_TESTS" "skill-activation" "all"; then
        overall_exit=1
        [[ "$FAIL_FAST" == "true" ]] && return $overall_exit
    fi
    
    # Workflow tests
    if ! run_test_suite "$WORKFLOW_TESTS" "workflow" "all"; then
        overall_exit=1
        [[ "$FAIL_FAST" == "true" ]] && return $overall_exit
    fi
    
    return $overall_exit
}

# =============================================================================
# Reporting Functions
# =============================================================================

generate_summary_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local pass_rate=0
    
    if [[ $TOTAL_TESTS_RUN -gt 0 ]]; then
        pass_rate=$(( (TOTAL_TESTS_PASSED * 100) / TOTAL_TESTS_RUN ))
    fi
    
    local summary_file="$REPORTS_DIR/summary.txt"
    
    cat > "$summary_file" << EOF
Claude Dev Pipeline - Test Execution Summary
============================================

Execution Time: $(date)
Total Duration: ${total_duration} seconds
Test Mode: $([ "$PARALLEL" == "true" ] && echo "Parallel" || echo "Sequential")

Test Results:
=============
Tests Run:    $TOTAL_TESTS_RUN
Tests Passed: $TOTAL_TESTS_PASSED
Tests Failed: $TOTAL_TESTS_FAILED
Pass Rate:    ${pass_rate}%

Test Suites:
============
EOF

    # Add individual suite results
    for report in "$REPORTS_DIR"/*-report.txt; do
        if [[ -f "$report" ]]; then
            local suite_name=$(basename "$report" "-report.txt")
            echo "" >> "$summary_file"
            echo "${suite_name^} Suite:" >> "$summary_file"
            echo "$(grep -E "(Tests Run|Tests Passed|Tests Failed)" "$report" | head -3)" >> "$summary_file"
        fi
    done
    
    cat >> "$summary_file" << EOF

Overall Result: $([ $TOTAL_TESTS_FAILED -eq 0 ] && echo "PASSED" || echo "FAILED")

Detailed Reports:
================
EOF

    for report in "$REPORTS_DIR"/*.txt; do
        if [[ -f "$report" ]] && [[ "$report" != "$summary_file" ]]; then
            echo "- $(basename "$report")" >> "$summary_file"
        fi
    done
    
    # Display summary to console
    quiet ""
    quiet "${BOLD}${CYAN}Test Execution Summary${RESET}"
    quiet "======================"
    quiet "Total Duration: ${total_duration}s"
    quiet "Tests Run:    $TOTAL_TESTS_RUN"
    quiet "Tests Passed: ${GREEN}$TOTAL_TESTS_PASSED${RESET}"
    quiet "Tests Failed: ${RED}$TOTAL_TESTS_FAILED${RESET}"
    quiet "Pass Rate:    ${pass_rate}%"
    
    if [[ $TOTAL_TESTS_FAILED -eq 0 ]]; then
        quiet ""
        success "All tests passed! 🎉"
    else
        quiet ""
        error "Some tests failed. Check reports in $REPORTS_DIR"
    fi
}

generate_html_report() {
    if [[ "$GENERATE_HTML" != "true" ]]; then
        return 0
    fi
    
    verbose "Generating HTML report"
    
    local html_file="$REPORTS_DIR/test-report.html"
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local pass_rate=0
    
    if [[ $TOTAL_TESTS_RUN -gt 0 ]]; then
        pass_rate=$(( (TOTAL_TESTS_PASSED * 100) / TOTAL_TESTS_RUN ))
    fi
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Dev Pipeline - Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { border-bottom: 2px solid #007acc; padding-bottom: 10px; margin-bottom: 20px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric { background: #f8f9fa; padding: 15px; border-radius: 6px; text-align: center; border-left: 4px solid #007acc; }
        .metric.passed { border-left-color: #28a745; }
        .metric.failed { border-left-color: #dc3545; }
        .metric-value { font-size: 2em; font-weight: bold; margin-bottom: 5px; }
        .metric-label { color: #666; text-transform: uppercase; font-size: 0.8em; }
        .suite-results { margin-top: 30px; }
        .suite { margin-bottom: 20px; border: 1px solid #ddd; border-radius: 6px; }
        .suite-header { background: #f8f9fa; padding: 15px; font-weight: bold; border-bottom: 1px solid #ddd; }
        .suite-content { padding: 15px; }
        .status { padding: 4px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
        .status.passed { background: #d4edda; color: #155724; }
        .status.failed { background: #f8d7da; color: #721c24; }
        .progress-bar { width: 100%; height: 20px; background: #e9ecef; border-radius: 10px; overflow: hidden; margin: 10px 0; }
        .progress-fill { height: 100%; transition: width 0.3s ease; }
        .progress-pass { background: #28a745; }
        .progress-fail { background: #dc3545; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 4px; overflow-x: auto; font-size: 0.9em; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Claude Dev Pipeline - Test Report</h1>
            <p class="timestamp">Generated: $(date)</p>
        </div>
        
        <div class="summary">
            <div class="metric">
                <div class="metric-value">$TOTAL_TESTS_RUN</div>
                <div class="metric-label">Total Tests</div>
            </div>
            <div class="metric passed">
                <div class="metric-value">$TOTAL_TESTS_PASSED</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric failed">
                <div class="metric-value">$TOTAL_TESTS_FAILED</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric">
                <div class="metric-value">${pass_rate}%</div>
                <div class="metric-label">Pass Rate</div>
            </div>
            <div class="metric">
                <div class="metric-value">${total_duration}s</div>
                <div class="metric-label">Duration</div>
            </div>
        </div>
        
        <div class="progress-bar">
            <div class="progress-fill progress-pass" style="width: ${pass_rate}%"></div>
        </div>
        
        <div class="suite-results">
            <h2>Test Suite Results</h2>
EOF

    # Add individual suite results to HTML
    for report in "$REPORTS_DIR"/*-report.txt; do
        if [[ -f "$report" ]]; then
            local suite_name=$(basename "$report" "-report.txt")
            local suite_passed=0
            local suite_failed=0
            local suite_total=0
            
            if grep -q "Tests Passed:" "$report"; then
                suite_passed=$(grep "Tests Passed:" "$report" | tail -1 | awk '{print $3}' || echo "0")
                suite_failed=$(grep "Tests Failed:" "$report" | tail -1 | awk '{print $3}' || echo "0")
                suite_total=$(grep "Tests Run:" "$report" | tail -1 | awk '{print $3}' || echo "0")
            fi
            
            local suite_status="passed"
            [[ $suite_failed -gt 0 ]] && suite_status="failed"
            
            cat >> "$html_file" << EOF
            <div class="suite">
                <div class="suite-header">
                    ${suite_name^} Test Suite
                    <span class="status $suite_status">$([ "$suite_status" == "passed" ] && echo "PASSED" || echo "FAILED")</span>
                </div>
                <div class="suite-content">
                    <p><strong>Tests Run:</strong> $suite_total | <strong>Passed:</strong> $suite_passed | <strong>Failed:</strong> $suite_failed</p>
                    <details>
                        <summary>View detailed output</summary>
                        <pre>$(cat "$report" | head -100)</pre>
                    </details>
                </div>
            </div>
EOF
        fi
    done
    
    cat >> "$html_file" << EOF
        </div>
        
        <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; text-align: center;">
            <p>Generated by Claude Dev Pipeline Test Runner</p>
        </div>
    </div>
</body>
</html>
EOF

    success "HTML report generated: $html_file"
}

# =============================================================================
# Main Functions
# =============================================================================

run_specific_suite() {
    local suite="$1"
    local args="${2:-all}"
    
    case "$suite" in
        hooks|hook)
            run_test_suite "$HOOK_TESTS" "hooks" "$args"
            ;;
        skills|skill-activation|skill)
            run_test_suite "$SKILL_TESTS" "skill-activation" "$args"
            ;;
        workflow|full-workflow|integration)
            run_test_suite "$WORKFLOW_TESTS" "workflow" "$args"
            ;;
        *)
            error "Unknown test suite: $suite"
            show_help
            exit 1
            ;;
    esac
}

run_all_tests() {
    setup_test_environment
    
    local exit_code=0
    
    if [[ "$PARALLEL" == "true" ]]; then
        if ! run_parallel_tests; then
            exit_code=1
        fi
    else
        if ! run_sequential_tests; then
            exit_code=1
        fi
    fi
    
    generate_summary_report
    generate_html_report
    cleanup_test_environment
    
    return $exit_code
}

# =============================================================================
# CLI Interface
# =============================================================================

show_help() {
    cat << EOF
Claude Dev Pipeline - Test Runner

Usage: $0 [OPTIONS] [SUITE] [ARGS]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress most output
    -p, --parallel      Run tests in parallel
    -f, --fail-fast     Stop on first failure
    --no-html           Skip HTML report generation
    --no-clean          Don't clean before running
    -h, --help          Show this help message

SUITES:
    hooks               Run hook tests only
    skills              Run skill activation tests only  
    workflow            Run workflow tests only
    all                 Run all test suites (default)

SUITE ARGS:
    Passed directly to the individual test suite.
    Use 'SUITE -h' to see suite-specific options.

EXAMPLES:
    $0                          # Run all tests
    $0 -v hooks                 # Run hook tests with verbose output
    $0 -p all                   # Run all tests in parallel
    $0 skills user-patterns     # Run only user pattern tests
    $0 -f workflow complete     # Run complete workflow with fail-fast

ENVIRONMENT VARIABLES:
    VERBOSE=true        Enable verbose output
    QUIET=true          Enable quiet mode
    PARALLEL=true       Enable parallel execution
    FAIL_FAST=true      Enable fail-fast mode
    GENERATE_HTML=false Disable HTML report generation
    CLEAN_BEFORE=false  Disable cleanup before tests

REPORTS:
    Text reports: $REPORTS_DIR/
    HTML report:  $REPORTS_DIR/test-report.html
    Logs:         $LOG_DIR/
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
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            -f|--fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --no-html)
                GENERATE_HTML=false
                shift
                ;;
            --no-clean)
                CLEAN_BEFORE=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            hooks|hook|skills|skill-activation|skill|workflow|full-workflow|integration)
                local suite="$1"
                shift
                local args="$*"
                setup_test_environment
                run_specific_suite "$suite" "$args"
                cleanup_test_environment
                exit $?
                ;;
            all)
                shift
                run_all_tests
                exit $?
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Default: run all tests
    run_all_tests
}

# Trap for cleanup on exit
trap cleanup_test_environment EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi