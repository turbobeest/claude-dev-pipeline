#!/bin/bash
# =============================================================================
# Performance Validator Hook
# Validates performance against PRD requirements
# Blocks deployment if performance targets not met
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly PERF_REPORT="${PROJECT_ROOT}/.performance-validation.json"
readonly LOG_FILE="${PROJECT_ROOT}/.performance-validation.log"

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
# PRD Requirements Extraction
# =============================================================================

extract_performance_requirements() {
    log_info "Extracting performance requirements from PRD..."

    local prd_file=""
    if [ -f "docs/PRD.md" ]; then
        prd_file="docs/PRD.md"
    elif [ -f "PRD.md" ]; then
        prd_file="PRD.md"
    else
        log_warning "No PRD found - cannot extract performance requirements"
        return 1
    fi

    # Initialize requirements object
    cat > "$PERF_REPORT" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "requirements": {},
    "actual": {},
    "validation": {},
    "status": "extracting"
}
EOF

    # Extract latency requirements
    local latency_p95=$(grep -oiE "p95[: ]+[<]?[0-9]+ ?ms" "$prd_file" | grep -oE "[0-9]+" | head -1 || echo "")
    local latency_p99=$(grep -oiE "p99[: ]+[<]?[0-9]+ ?ms" "$prd_file" | grep -oE "[0-9]+" | head -1 || echo "")
    local avg_latency=$(grep -oiE "(average|avg|mean) (latency|response time)[: ]+[<]?[0-9]+ ?ms" "$prd_file" | grep -oE "[0-9]+" | head -1 || echo "")

    # Extract throughput requirements
    local rps=$(grep -oiE "[0-9]+ (requests?|req) ?(/|per) ?(second|sec)" "$prd_file" | grep -oE "^[0-9]+" | head -1 || echo "")
    local tps=$(grep -oiE "[0-9]+ (transactions?|txn) ?(/|per) ?(second|sec)" "$prd_file" | grep -oE "^[0-9]+" | head -1 || echo "")

    # Extract concurrent user requirements
    local concurrent_users=$(grep -oiE "[0-9]+ (concurrent )?users" "$prd_file" | grep -oE "^[0-9]+" | head -1 || echo "")

    # Extract resource requirements
    local cpu_limit=$(grep -oiE "CPU[: ]+[<]?[0-9]+ ?%" "$prd_file" | grep -oE "[0-9]+" | head -1 || echo "")
    local memory_limit=$(grep -oiE "(memory|RAM)[: ]+[<]?[0-9]+ ?(GB|MB)" "$prd_file" | grep -oE "[0-9]+" | head -1 || echo "")

    # Update report with extracted requirements
    local temp=$(mktemp)

    jq --arg p95 "${latency_p95:-not_specified}" \
       --arg p99 "${latency_p99:-not_specified}" \
       --arg avg "${avg_latency:-not_specified}" \
       --arg rps "${rps:-not_specified}" \
       --arg tps "${tps:-not_specified}" \
       --arg users "${concurrent_users:-not_specified}" \
       --arg cpu "${cpu_limit:-not_specified}" \
       --arg mem "${memory_limit:-not_specified}" \
       '.requirements = {
           latency_p95_ms: $p95,
           latency_p99_ms: $p99,
           avg_latency_ms: $avg,
           requests_per_second: $rps,
           transactions_per_second: $tps,
           concurrent_users: $users,
           cpu_limit_percent: $cpu,
           memory_limit: $mem
       }' "$PERF_REPORT" > "$temp"
    mv "$temp" "$PERF_REPORT"

    # Display extracted requirements
    local found_any=false
    if [ -n "$latency_p95" ]; then
        log_info "Latency p95: < ${latency_p95}ms"
        found_any=true
    fi

    if [ -n "$latency_p99" ]; then
        log_info "Latency p99: < ${latency_p99}ms"
        found_any=true
    fi

    if [ -n "$avg_latency" ]; then
        log_info "Average latency: < ${avg_latency}ms"
        found_any=true
    fi

    if [ -n "$rps" ]; then
        log_info "Throughput: ≥ ${rps} req/sec"
        found_any=true
    fi

    if [ -n "$concurrent_users" ]; then
        log_info "Concurrent users: ${concurrent_users}"
        found_any=true
    fi

    if [ -n "$cpu_limit" ]; then
        log_info "CPU limit: < ${cpu_limit}%"
        found_any=true
    fi

    if [ -n "$memory_limit" ]; then
        log_info "Memory limit: < ${memory_limit}"
        found_any=true
    fi

    if [ "$found_any" = false ]; then
        log_warning "No specific performance requirements found in PRD"
        return 1
    fi

    return 0
}

# =============================================================================
# Performance Test Detection & Execution
# =============================================================================

detect_performance_tests() {
    log_info "Detecting performance test configuration..."

    # Check for performance test scripts in package.json
    if [ -f "package.json" ]; then
        if jq -e '.scripts["perf:test"] or .scripts["test:perf"] or .scripts["performance"] or .scripts["benchmark"]' package.json > /dev/null 2>&1; then
            echo "npm"
            return 0
        fi
    fi

    # Check for benchmark files
    if [ -f "benchmark.js" ] || [ -f "perf-test.js" ]; then
        echo "node_benchmark"
        return 0
    fi

    # Check for Python performance tests
    if [ -f "test_performance.py" ] || [ -f "benchmark.py" ]; then
        echo "python_benchmark"
        return 0
    fi

    # Check for k6 with performance-specific config
    if [ -f "k6-performance.js" ]; then
        echo "k6_perf"
        return 0
    fi

    echo "none"
    return 1
}

run_performance_tests() {
    log_info "Running performance tests..."

    local test_type=$(detect_performance_tests)

    if [ "$test_type" = "none" ]; then
        log_warning "No performance tests detected"
        return 1
    fi

    log_info "Running $test_type performance tests..."

    case "$test_type" in
        npm)
            local script=""
            if jq -e '.scripts["perf:test"]' package.json > /dev/null 2>&1; then
                script="perf:test"
            elif jq -e '.scripts["test:perf"]' package.json > /dev/null 2>&1; then
                script="test:perf"
            elif jq -e '.scripts["performance"]' package.json > /dev/null 2>&1; then
                script="performance"
            elif jq -e '.scripts["benchmark"]' package.json > /dev/null 2>&1; then
                script="benchmark"
            fi

            if npm run "$script" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Performance tests completed"
                return 0
            else
                log_error "Performance tests failed"
                return 1
            fi
            ;;

        node_benchmark)
            if node benchmark.js 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Node benchmark completed"
                return 0
            else
                log_error "Node benchmark failed"
                return 1
            fi
            ;;

        python_benchmark)
            if python3 benchmark.py 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Python benchmark completed"
                return 0
            else
                log_error "Python benchmark failed"
                return 1
            fi
            ;;

        k6_perf)
            if command -v k6 &> /dev/null; then
                if k6 run k6-performance.js --out json=k6-perf-results.json 2>&1 | tee -a "$LOG_FILE"; then
                    log_success "k6 performance tests completed"
                    return 0
                else
                    log_error "k6 performance tests failed"
                    return 1
                fi
            else
                log_error "k6 not installed"
                return 1
            fi
            ;;

        *)
            log_error "Unknown test type: $test_type"
            return 1
            ;;
    esac
}

# =============================================================================
# Performance Validation
# =============================================================================

validate_performance() {
    log_info "Validating performance metrics..."

    # Check if we have load test results
    if [ ! -f ".load-test-results.json" ] && [ ! -f "k6-perf-results.json" ]; then
        log_warning "No load test results found - run load tests first"
        return 1
    fi

    local results_file=".load-test-results.json"
    if [ -f "k6-perf-results.json" ]; then
        results_file="k6-perf-results.json"
    fi

    # Extract actual performance metrics (k6 format)
    if jq -e '.metrics.http_req_duration' "$results_file" > /dev/null 2>&1; then
        local actual_p95=$(jq -r '.metrics.http_req_duration.values["p(95)"] // 0' "$results_file" 2>/dev/null || echo "0")
        local actual_p99=$(jq -r '.metrics.http_req_duration.values["p(99)"] // 0' "$results_file" 2>/dev/null || echo "0")
        local actual_avg=$(jq -r '.metrics.http_req_duration.values.avg // 0' "$results_file" 2>/dev/null || echo "0")
        local actual_rps=$(jq -r '.metrics.http_reqs.values.rate // 0' "$results_file" 2>/dev/null || echo "0")

        # Update report with actual values
        local temp=$(mktemp)
        jq --arg p95 "$actual_p95" \
           --arg p99 "$actual_p99" \
           --arg avg "$actual_avg" \
           --arg rps "$actual_rps" \
           '.actual = {
               latency_p95_ms: $p95,
               latency_p99_ms: $p99,
               avg_latency_ms: $avg,
               requests_per_second: $rps
           }' "$PERF_REPORT" > "$temp"
        mv "$temp" "$PERF_REPORT"

        # Compare against requirements
        local validation_passed=true

        # Validate p95 latency
        local req_p95=$(jq -r '.requirements.latency_p95_ms' "$PERF_REPORT")
        if [ "$req_p95" != "not_specified" ] && [ "$req_p95" != "null" ]; then
            if (( $(echo "$actual_p95 > $req_p95" | bc -l) )); then
                log_error "p95 latency: ${actual_p95}ms > ${req_p95}ms (FAILED)"
                validation_passed=false
            else
                log_success "p95 latency: ${actual_p95}ms ≤ ${req_p95}ms (PASSED)"
            fi
        fi

        # Validate p99 latency
        local req_p99=$(jq -r '.requirements.latency_p99_ms' "$PERF_REPORT")
        if [ "$req_p99" != "not_specified" ] && [ "$req_p99" != "null" ]; then
            if (( $(echo "$actual_p99 > $req_p99" | bc -l) )); then
                log_error "p99 latency: ${actual_p99}ms > ${req_p99}ms (FAILED)"
                validation_passed=false
            else
                log_success "p99 latency: ${actual_p99}ms ≤ ${req_p99}ms (PASSED)"
            fi
        fi

        # Validate throughput
        local req_rps=$(jq -r '.requirements.requests_per_second' "$PERF_REPORT")
        if [ "$req_rps" != "not_specified" ] && [ "$req_rps" != "null" ]; then
            if (( $(echo "$actual_rps < $req_rps" | bc -l) )); then
                log_error "Throughput: ${actual_rps} req/s < ${req_rps} req/s (FAILED)"
                validation_passed=false
            else
                log_success "Throughput: ${actual_rps} req/s ≥ ${req_rps} req/s (PASSED)"
            fi
        fi

        if [ "$validation_passed" = true ]; then
            return 0
        else
            return 1
        fi
    else
        log_warning "Could not parse performance metrics from results"
        return 1
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "==============================================================================="
    echo "Performance Validation"
    echo "==============================================================================="
    echo ""

    > "$LOG_FILE"

    # Extract PRD requirements
    if ! extract_performance_requirements; then
        log_warning "No performance requirements found in PRD"
        log_info "Skipping performance validation"
        exit 0
    fi

    echo ""

    # Run performance tests
    if run_performance_tests; then
        echo ""

        # Validate against requirements
        if validate_performance; then
            local temp=$(mktemp)
            jq '.status = "passed"' "$PERF_REPORT" > "$temp"
            mv "$temp" "$PERF_REPORT"

            log_success "Performance validation PASSED"
            echo ""
            echo "Performance report: $PERF_REPORT"
            exit 0
        else
            local temp=$(mktemp)
            jq '.status = "failed"' "$PERF_REPORT" > "$temp"
            mv "$temp" "$PERF_REPORT"

            log_error "Performance validation FAILED"
            echo ""
            echo "Performance report: $PERF_REPORT"
            exit 1
        fi
    else
        log_warning "Performance tests not available or failed"
        log_info "Consider adding performance tests to validate PRD requirements"
        exit 0
    fi
}

# Run main function
main "$@"
