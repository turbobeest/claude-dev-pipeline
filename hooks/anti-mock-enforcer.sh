#!/bin/bash
# =============================================================================
# Anti-Mock Enforcer Hook
# Prevents creation of mock/simulated/fake implementations in operational code
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly VIOLATION_REPORT="${PROJECT_ROOT}/.mock-violations.json"
readonly SRC_DIR="${PROJECT_ROOT}/src"
readonly SERVICES_DIR="${PROJECT_ROOT}/services"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Mock patterns that are FORBIDDEN in operational code
readonly FORBIDDEN_PATTERNS=(
    # Mock implementations
    "mock[^t].*implementation"
    "simulated.*deployment"
    "fake.*service"
    "dummy.*data"
    "stub.*connection"
    "pretend.*to"
    "simulate.*execution"
    "emulate.*behavior"
    
    # Hardcoded fake responses
    "return.*['\"]success['\"].*#.*fake"
    "return.*['\"]ok['\"].*#.*mock"
    "return.*{.*status.*:.*['\"]success"
    "hardcoded.*response"
    "fake.*response"
    "mock.*response"
    
    # Simulation functions
    "def.*simulate_"
    "function.*mock"
    "class.*Mock[A-Z]"
    "class.*Fake[A-Z]"
    "class.*Simulated"
    
    # Comments indicating mocks
    "TODO.*implement.*real"
    "FIXME.*placeholder"
    "temporary.*implementation"
    "not.*actually.*connecting"
    "doesn't.*really"
    "pretending.*to"
)

# Allowed mock patterns (for tests only)
readonly ALLOWED_IN_TESTS=(
    "test_*.py"
    "*_test.py"
    "test_*.js"
    "*.test.js"
    "*.spec.js"
    "*_test.go"
    "test/*.py"
    "tests/*.py"
    "__tests__/*"
    "spec/*"
)

# Log function
log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
        *)
            echo "$*"
            ;;
    esac
}

# Check if file is a test file
is_test_file() {
    local file=$1
    
    for pattern in "${ALLOWED_IN_TESTS[@]}"; do
        if [[ "$file" == $pattern ]] || [[ "$file" == *"/$pattern" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Scan for mock implementations
scan_for_mocks() {
    local violations=()
    local checked_files=0
    local violation_count=0
    
    echo -e "${YELLOW}Scanning for mock/simulated implementations...${NC}"
    
    # Search in source directories
    for dir in "$SRC_DIR" "$SERVICES_DIR" "${PROJECT_ROOT}/api" "${PROJECT_ROOT}/lib"; do
        if [ ! -d "$dir" ]; then
            continue
        fi
        
        # Find all code files
        while IFS= read -r file; do
            # Skip test files
            if is_test_file "$file"; then
                continue
            fi
            
            checked_files=$((checked_files + 1))
            
            # Check each forbidden pattern
            for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
                if grep -iE "$pattern" "$file" >/dev/null 2>&1; then
                    local line_num=$(grep -inE "$pattern" "$file" | head -1 | cut -d: -f1)
                    local line_content=$(grep -inE "$pattern" "$file" | head -1 | cut -d: -f2-)
                    
                    violations+=("{\"file\": \"$file\", \"line\": $line_num, \"pattern\": \"$pattern\", \"content\": \"$(echo "$line_content" | sed 's/"/\\"/g')\"}")
                    violation_count=$((violation_count + 1))
                    
                    log ERROR "Mock pattern found in $file:$line_num"
                    echo "  Pattern: $pattern"
                    echo "  Line: $line_content"
                    echo ""
                fi
            done
        done < <(find "$dir" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) 2>/dev/null)
    done
    
    # Generate report
    echo "{" > "$VIOLATION_REPORT"
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"," >> "$VIOLATION_REPORT"
    echo "  \"checked_files\": $checked_files," >> "$VIOLATION_REPORT"
    echo "  \"violation_count\": $violation_count," >> "$VIOLATION_REPORT"
    echo "  \"violations\": [" >> "$VIOLATION_REPORT"
    
    local first=true
    if [ ${#violations[@]} -gt 0 ]; then
        for violation in "${violations[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$VIOLATION_REPORT"
        fi
            echo "    $violation" >> "$VIOLATION_REPORT"
        done
    fi
    
    echo "  ]" >> "$VIOLATION_REPORT"
    echo "}" >> "$VIOLATION_REPORT"
    
    return $violation_count
}

# Check specific dangerous mock patterns
check_dangerous_patterns() {
    echo -e "${YELLOW}Checking for dangerous mock patterns...${NC}"
    
    # Check for "return success" without actual implementation
    if find "${SRC_DIR}" "${SERVICES_DIR}" -type f -name "*.py" 2>/dev/null | \
       xargs grep -l "return.*['\"]success['\"]" 2>/dev/null | \
       xargs grep -L "actual.*implementation\|real.*connection" 2>/dev/null | head -1; then
        
        log ERROR "Found 'return success' without actual implementation!"
        return 1
    fi
    
    # Check for simulated deployments
    if find "${SRC_DIR}" "${SERVICES_DIR}" -type f 2>/dev/null | \
       xargs grep -il "simulat.*deploy\|mock.*deploy\|fake.*deploy" 2>/dev/null | head -1; then
        
        log ERROR "Found simulated deployment code!"
        return 1
    fi
    
    # Check for placeholder implementations
    if find "${SRC_DIR}" "${SERVICES_DIR}" -type f 2>/dev/null | \
       xargs grep -il "TODO.*implement\|FIXME.*real\|placeholder.*implementation" 2>/dev/null | head -1; then
        
        log WARNING "Found TODO/FIXME indicating incomplete implementation"
    fi
    
    return 0
}

# Main execution
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   ANTI-MOCK ENFORCEMENT CHECK            ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    local exit_code=0
    
    # Scan for mocks
    if scan_for_mocks; then
        log SUCCESS "No mock implementations found in operational code"
    else
        exit_code=1
    fi
    
    # Check dangerous patterns
    if ! check_dangerous_patterns; then
        exit_code=1
    fi
    
    # Final verdict
    if [ $exit_code -eq 0 ]; then
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  NO MOCK VIOLATIONS DETECTED${NC}"
        echo -e "${GREEN}════════════════════════════════════════════${NC}"
        echo ""
        log SUCCESS "All operational code uses real implementations"
    else
        echo ""
        echo -e "${RED}════════════════════════════════════════════${NC}"
        echo -e "${RED}  MOCK VIOLATIONS DETECTED!${NC}"
        echo -e "${RED}════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${RED}The pipeline has detected mock/simulated code in operational components.${NC}"
        echo ""
        echo -e "${YELLOW}Required Actions:${NC}"
        echo "  1. Replace ALL mock implementations with real code"
        echo "  2. Remove simulated deployments"
        echo "  3. Implement actual service connections"
        echo "  4. If implementation is not possible, fail explicitly"
        echo ""
        echo -e "${RED}Mock code is only allowed in test files, never in operational code.${NC}"
        echo ""
        echo "Violation report: $VIOLATION_REPORT"
        echo ""
        
        # Signal pipeline to stop
        echo "MOCK_VIOLATION_DETECTED" > "${PROJECT_ROOT}/.claude/.pipeline-signal" 2>/dev/null || true
        
        exit 1
    fi
}

# Run enforcement
main "$@"