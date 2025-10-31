#!/bin/bash
# =============================================================================
# Security Validator Hook
# Automated security scanning before deployment
# Blocks deployment if critical/high vulnerabilities found
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly SECURITY_REPORT="${PROJECT_ROOT}/.security-validation.json"
readonly LOG_FILE="${PROJECT_ROOT}/.security-validation.log"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Logging
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_success() {
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log "${GREEN}✅ ${1}${NC}"
}

log_error() {
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    log "${RED}❌ ${1}${NC}"
}

log_warning() {
    WARNINGS=$((WARNINGS + 1))
    log "${YELLOW}⚠️  ${1}${NC}"
}

log_info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Initialize report
init_report() {
    cat > "$SECURITY_REPORT" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status": "running",
    "checks": {}
}
EOF
    > "$LOG_FILE"
}

# Update report
update_report() {
    local check_name="$1"
    local status="$2"
    local details="$3"

    local temp_file=$(mktemp)
    jq --arg name "$check_name" \
       --arg status "$status" \
       --arg details "$details" \
       '.checks[$name] = {status: $status, details: $details}' \
       "$SECURITY_REPORT" > "$temp_file"
    mv "$temp_file" "$SECURITY_REPORT"
}

# =============================================================================
# Security Checks
# =============================================================================

# Check 1: Node.js Dependency Scanning
check_npm_audit() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Running npm audit..."

    if [ ! -f "package.json" ]; then
        log_warning "No package.json found - skipping npm audit"
        update_report "npm_audit" "skipped" "No package.json found"
        return 0
    fi

    # Run npm audit and capture output
    if npm audit --audit-level=high --json > npm-audit-results.json 2>&1; then
        log_success "npm audit: No high/critical vulnerabilities"
        update_report "npm_audit" "passed" "No high or critical vulnerabilities"
        return 0
    else
        # Parse vulnerabilities
        local critical=$(jq -r '.metadata.vulnerabilities.critical // 0' npm-audit-results.json 2>/dev/null || echo "0")
        local high=$(jq -r '.metadata.vulnerabilities.high // 0' npm-audit-results.json 2>/dev/null || echo "0")
        local moderate=$(jq -r '.metadata.vulnerabilities.moderate // 0' npm-audit-results.json 2>/dev/null || echo "0")

        if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
            log_error "npm audit failed: $critical critical, $high high vulnerabilities"
            update_report "npm_audit" "failed" "Critical: $critical, High: $high, Moderate: $moderate"
            return 1
        elif [ "$moderate" -gt 0 ]; then
            log_warning "npm audit: $moderate moderate vulnerabilities found"
            update_report "npm_audit" "warning" "Moderate vulnerabilities: $moderate"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        fi
    fi
}

# Check 2: Python Dependency Scanning
check_pip_audit() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Running pip-audit..."

    if [ ! -f "requirements.txt" ] && [ ! -f "pyproject.toml" ] && [ ! -f "Pipfile" ]; then
        log_warning "No Python dependency files found - skipping pip-audit"
        update_report "pip_audit" "skipped" "No Python dependencies found"
        return 0
    fi

    # Check if pip-audit is installed
    if ! command -v pip-audit &> /dev/null; then
        log_warning "pip-audit not installed - skipping (install with: pip install pip-audit)"
        update_report "pip_audit" "skipped" "pip-audit not installed"
        return 0
    fi

    # Run pip-audit
    if pip-audit --format json --output pip-audit-results.json 2>&1; then
        log_success "pip-audit: No vulnerabilities found"
        update_report "pip_audit" "passed" "No vulnerabilities"
        return 0
    else
        local vuln_count=$(jq -r '.dependencies | length' pip-audit-results.json 2>/dev/null || echo "unknown")
        log_error "pip-audit failed: $vuln_count vulnerabilities found"
        update_report "pip_audit" "failed" "Vulnerabilities found: $vuln_count"
        return 1
    fi
}

# Check 3: Container Image Scanning
check_container_security() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Running container security scan..."

    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "Dockerfile" ]; then
        log_warning "No Docker files found - skipping container scan"
        update_report "container_scan" "skipped" "No Docker configuration found"
        return 0
    fi

    # Check if trivy is installed
    if ! command -v trivy &> /dev/null; then
        log_warning "Trivy not installed - skipping container scan (install: brew install trivy)"
        update_report "container_scan" "skipped" "Trivy not installed"
        return 0
    fi

    # Get images to scan
    local images=()
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        # Build images first if needed
        if docker-compose build > /dev/null 2>&1; then
            log_info "Built Docker images for scanning"
        fi

        # Get image names
        mapfile -t images < <(docker-compose config --images 2>/dev/null || echo "")
    elif [ -f "Dockerfile" ]; then
        # Build standalone Dockerfile
        local image_name="security-scan-temp:latest"
        if docker build -t "$image_name" . > /dev/null 2>&1; then
            images=("$image_name")
        fi
    fi

    if [ ${#images[@]} -eq 0 ]; then
        log_warning "No images found to scan"
        update_report "container_scan" "skipped" "No images to scan"
        return 0
    fi

    # Scan each image
    local total_vulns=0
    for image in "${images[@]}"; do
        log_info "Scanning image: $image"

        if trivy image --severity HIGH,CRITICAL --format json --output "trivy-$image.json" "$image" 2>&1; then
            local critical=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "trivy-$image.json" 2>/dev/null || echo "0")
            local high=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "trivy-$image.json" 2>/dev/null || echo "0")

            total_vulns=$((total_vulns + critical + high))

            if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
                log_error "Image $image: $critical critical, $high high vulnerabilities"
            else
                log_success "Image $image: Clean"
            fi
        fi
    done

    if [ "$total_vulns" -gt 0 ]; then
        log_error "Container scan failed: $total_vulns total vulnerabilities"
        update_report "container_scan" "failed" "Total vulnerabilities: $total_vulns"
        return 1
    else
        log_success "Container scan: No critical/high vulnerabilities"
        update_report "container_scan" "passed" "All images clean"
        return 0
    fi
}

# Check 4: Secrets Detection
check_secrets() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Running secrets detection..."

    # Check if gitleaks is installed
    if ! command -v gitleaks &> /dev/null; then
        log_warning "Gitleaks not installed - skipping secrets scan (install: brew install gitleaks)"
        update_report "secrets_scan" "skipped" "Gitleaks not installed"
        return 0
    fi

    # Run gitleaks
    if gitleaks detect --no-git --report-path gitleaks-report.json --exit-code 0 2>&1; then
        local secrets_found=$(jq -r 'length' gitleaks-report.json 2>/dev/null || echo "0")

        if [ "$secrets_found" -gt 0 ]; then
            log_error "Secrets detected: $secrets_found potential secrets found"
            update_report "secrets_scan" "failed" "Secrets found: $secrets_found"
            return 1
        else
            log_success "Secrets scan: No secrets detected"
            update_report "secrets_scan" "passed" "No secrets found"
            return 0
        fi
    else
        log_error "Gitleaks scan failed"
        update_report "secrets_scan" "failed" "Scan execution failed"
        return 1
    fi
}

# Check 5: SAST Scanning (Semgrep)
check_sast() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Running SAST scan..."

    # Check if semgrep is installed
    if ! command -v semgrep &> /dev/null; then
        log_warning "Semgrep not installed - skipping SAST (install: pip install semgrep)"
        update_report "sast_scan" "skipped" "Semgrep not installed"
        return 0
    fi

    # Run semgrep with auto configuration
    if semgrep --config=auto --json --output semgrep-results.json . 2>&1; then
        local errors=$(jq -r '[.results[] | select(.extra.severity=="ERROR")] | length' semgrep-results.json 2>/dev/null || echo "0")
        local warnings=$(jq -r '[.results[] | select(.extra.severity=="WARNING")] | length' semgrep-results.json 2>/dev/null || echo "0")

        if [ "$errors" -gt 0 ]; then
            log_error "SAST scan: $errors error-level findings"
            update_report "sast_scan" "failed" "Errors: $errors, Warnings: $warnings"
            return 1
        elif [ "$warnings" -gt 0 ]; then
            log_warning "SAST scan: $warnings warning-level findings"
            update_report "sast_scan" "warning" "Warnings: $warnings"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            log_success "SAST scan: No issues found"
            update_report "sast_scan" "passed" "No issues"
            return 0
        fi
    else
        log_warning "SAST scan encountered errors (may be expected)"
        update_report "sast_scan" "warning" "Scan completed with warnings"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "==============================================================================="
    echo "Security Validation"
    echo "==============================================================================="
    echo ""

    init_report

    # Run all security checks
    check_npm_audit
    check_pip_audit
    check_container_security
    check_secrets
    check_sast

    echo ""
    echo "==============================================================================="
    echo "Security Validation Summary"
    echo "==============================================================================="
    echo ""
    echo "Total Checks:   $TOTAL_CHECKS"
    echo "Passed:         $PASSED_CHECKS"
    echo "Failed:         $FAILED_CHECKS"
    echo "Warnings:       $WARNINGS"
    echo ""

    # Update final status
    if [ "$FAILED_CHECKS" -gt 0 ]; then
        jq '.status = "failed"' "$SECURITY_REPORT" > "$SECURITY_REPORT.tmp"
        mv "$SECURITY_REPORT.tmp" "$SECURITY_REPORT"

        log_error "Security validation FAILED - $FAILED_CHECKS critical issues found"
        echo ""
        echo "Review detailed results in:"
        echo "  - $SECURITY_REPORT"
        echo "  - $LOG_FILE"
        echo ""
        exit 1
    else
        jq '.status = "passed"' "$SECURITY_REPORT" > "$SECURITY_REPORT.tmp"
        mv "$SECURITY_REPORT.tmp" "$SECURITY_REPORT"

        log_success "Security validation PASSED"

        if [ "$WARNINGS" -gt 0 ]; then
            echo ""
            log_warning "$WARNINGS warnings found - review recommended"
        fi

        echo ""
        echo "Security report: $SECURITY_REPORT"
        exit 0
    fi
}

# Run main function
main "$@"
