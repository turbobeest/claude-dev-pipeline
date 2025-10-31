#!/bin/bash
# =============================================================================
# Load Test Validator Hook
# Automated load testing execution and validation
# Blocks deployment if load tests fail or don't exist
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly LOAD_TEST_REPORT="${PROJECT_ROOT}/.load-test-results.json"
readonly LOG_FILE="${PROJECT_ROOT}/.load-test-validation.log"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_success() {
    log "${GREEN}✅ ${1}${NC}"
}

log_error() {
    log "${RED}❌ ${1}${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

log_info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# =============================================================================
# Load Test Framework Detection
# =============================================================================

detect_load_test_framework() {
    log_info "Detecting load test framework..."

    # k6
    if [ -f "k6-load-test.js" ] || [ -f "loadtest.js" ] || [ -f "load-test.js" ]; then
        if command -v k6 &> /dev/null; then
            echo "k6"
            return 0
        else
            log_warning "k6 test file found but k6 not installed"
        fi
    fi

    # Artillery
    if [ -f "artillery.yml" ] || [ -f "artillery.yaml" ] || [ -f "load-test.yml" ]; then
        if command -v artillery &> /dev/null; then
            echo "artillery"
            return 0
        else
            log_warning "Artillery config found but artillery not installed"
        fi
    fi

    # Locust
    if [ -f "locustfile.py" ]; then
        if command -v locust &> /dev/null; then
            echo "locust"
            return 0
        else
            log_warning "Locust file found but locust not installed"
        fi
    fi

    # JMeter
    if [ -f "load-test.jmx" ] || [ -f "test-plan.jmx" ]; then
        if command -v jmeter &> /dev/null; then
            echo "jmeter"
            return 0
        else
            log_warning "JMeter file found but jmeter not installed"
        fi
    fi

    # Gatling
    if [ -d "src/test/scala" ] && [ -f "build.sbt" ]; then
        if command -v gatling &> /dev/null; then
            echo "gatling"
            return 0
        else
            log_warning "Gatling structure found but gatling not installed"
        fi
    fi

    # Custom npm script
    if [ -f "package.json" ]; then
        if jq -e '.scripts["load:test"] or .scripts["test:load"] or .scripts["perf:test"]' package.json > /dev/null 2>&1; then
            echo "npm"
            return 0
        fi
    fi

    echo "none"
    return 1
}

# =============================================================================
# Load Test Execution
# =============================================================================

run_k6_test() {
    log_info "Running k6 load test..."

    local test_file=""
    if [ -f "k6-load-test.js" ]; then
        test_file="k6-load-test.js"
    elif [ -f "load-test.js" ]; then
        test_file="load-test.js"
    elif [ -f "loadtest.js" ]; then
        test_file="loadtest.js"
    else
        log_error "k6 test file not found"
        return 1
    fi

    if k6 run --out json="$LOAD_TEST_REPORT" "$test_file" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "k6 load test completed"
        return 0
    else
        log_error "k6 load test failed"
        return 1
    fi
}

run_artillery_test() {
    log_info "Running Artillery load test..."

    local config_file=""
    if [ -f "artillery.yml" ]; then
        config_file="artillery.yml"
    elif [ -f "artillery.yaml" ]; then
        config_file="artillery.yaml"
    elif [ -f "load-test.yml" ]; then
        config_file="load-test.yml"
    else
        log_error "Artillery config file not found"
        return 1
    fi

    if artillery run --output "$LOAD_TEST_REPORT" "$config_file" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Artillery load test completed"
        return 0
    else
        log_error "Artillery load test failed"
        return 1
    fi
}

run_locust_test() {
    log_info "Running Locust load test..."

    # Locust requires a running server, run headless
    if locust -f locustfile.py --headless --users 100 --spawn-rate 10 --run-time 5m --json 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Locust load test completed"
        return 0
    else
        log_error "Locust load test failed"
        return 1
    fi
}

run_npm_load_test() {
    log_info "Running npm load test script..."

    local script=""
    if jq -e '.scripts["load:test"]' package.json > /dev/null 2>&1; then
        script="load:test"
    elif jq -e '.scripts["test:load"]' package.json > /dev/null 2>&1; then
        script="test:load"
    elif jq -e '.scripts["perf:test"]' package.json > /dev/null 2>&1; then
        script="perf:test"
    else
        log_error "No load test script found in package.json"
        return 1
    fi

    if npm run "$script" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "npm load test completed"
        return 0
    else
        log_error "npm load test failed"
        return 1
    fi
}

# =============================================================================
# Results Validation
# =============================================================================

validate_load_test_results() {
    log_info "Validating load test results..."

    # Check if results file exists
    if [ ! -f "$LOAD_TEST_REPORT" ]; then
        log_warning "No load test results file found - validation skipped"
        return 0
    fi

    # Try to parse results (format varies by tool)
    if ! jq empty "$LOAD_TEST_REPORT" 2>/dev/null; then
        log_warning "Load test results not in JSON format - manual review required"
        return 0
    fi

    # Basic validation - check for obvious failures
    local failed=false

    # k6 results format
    if jq -e '.root_group' "$LOAD_TEST_REPORT" > /dev/null 2>&1; then
        local http_failures=$(jq -r '.metrics.http_req_failed.values.passes // 0' "$LOAD_TEST_REPORT" 2>/dev/null || echo "0")
        local checks_failed=$(jq -r '.metrics.checks.values.fails // 0' "$LOAD_TEST_REPORT" 2>/dev/null || echo "0")

        if [ "$http_failures" -gt 0 ] || [ "$checks_failed" -gt 0 ]; then
            log_error "Load test had failures: $http_failures HTTP failures, $checks_failed check failures"
            failed=true
        else
            log_success "Load test passed all checks"
        fi
    fi

    # Artillery results format
    if jq -e '.aggregate' "$LOAD_TEST_REPORT" > /dev/null 2>&1; then
        local errors=$(jq -r '.aggregate.counters["errors.ECONNREFUSED"] // 0' "$LOAD_TEST_REPORT" 2>/dev/null || echo "0")

        if [ "$errors" -gt 0 ]; then
            log_error "Load test had $errors connection errors"
            failed=true
        else
            log_success "Load test completed without connection errors"
        fi
    fi

    if [ "$failed" = true ]; then
        return 1
    fi

    return 0
}

# =============================================================================
# PRD Requirements Extraction (if available)
# =============================================================================

extract_load_requirements() {
    log_info "Checking for load test requirements in PRD..."

    if [ ! -f "docs/PRD.md" ] && [ ! -f "PRD.md" ]; then
        log_warning "No PRD found - skipping requirements validation"
        return 0
    fi

    local prd_file="docs/PRD.md"
    if [ ! -f "$prd_file" ]; then
        prd_file="PRD.md"
    fi

    # Look for performance/load requirements
    if grep -qi "concurrent users\|requests per second\|throughput\|load test" "$prd_file"; then
        log_info "PRD contains load testing requirements"

        # Extract specific numbers if present
        local concurrent_users=$(grep -oiE "[0-9]+ (concurrent )?users" "$prd_file" | head -1 || echo "")
        local rps=$(grep -oiE "[0-9]+ (requests?|req) per (second|sec)" "$prd_file" | head -1 || echo "")

        if [ -n "$concurrent_users" ]; then
            log_info "Required: $concurrent_users"
        fi

        if [ -n "$rps" ]; then
            log_info "Required: $rps"
        fi
    else
        log_warning "No specific load test requirements found in PRD"
    fi

    return 0
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "==============================================================================="
    echo "Load Test Validation"
    echo "==============================================================================="
    echo ""

    > "$LOG_FILE"

    # Extract requirements from PRD
    extract_load_requirements

    echo ""

    # Detect load test framework
    local framework=$(detect_load_test_framework)

    if [ "$framework" = "none" ]; then
        log_error "No load test framework detected"
        echo ""
        log_info "Please add load tests using one of:"
        echo "  - k6 (recommended): Create k6-load-test.js"
        echo "  - Artillery: Create artillery.yml"
        echo "  - Locust: Create locustfile.py"
        echo "  - npm script: Add 'load:test' to package.json"
        echo ""
        log_info "Example k6 test:"
        cat <<'EOF'

import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 100,
  duration: '5m',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get('http://localhost:8000/api/health');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
EOF
        echo ""
        exit 1
    fi

    log_success "Detected load test framework: $framework"
    echo ""

    # Run load test based on framework
    case "$framework" in
        k6)
            run_k6_test
            ;;
        artillery)
            run_artillery_test
            ;;
        locust)
            run_locust_test
            ;;
        npm)
            run_npm_load_test
            ;;
        *)
            log_error "Unsupported framework: $framework"
            exit 1
            ;;
    esac

    local test_exit_code=$?

    echo ""

    # Validate results
    if [ $test_exit_code -eq 0 ]; then
        validate_load_test_results
        local validation_exit_code=$?

        if [ $validation_exit_code -eq 0 ]; then
            log_success "Load test validation PASSED"
            echo ""
            echo "Results saved to: $LOAD_TEST_REPORT"
            exit 0
        else
            log_error "Load test validation FAILED"
            exit 1
        fi
    else
        log_error "Load test execution FAILED"
        exit 1
    fi
}

# Run main function
main "$@"
