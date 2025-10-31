#!/bin/bash

# =============================================================================
# Claude Dev Pipeline - Validation Script
# =============================================================================
# 
# Comprehensive validation script to verify pipeline installation and configuration
# 
# Usage:
#   ./validate.sh [options]
#
# Options:
#   -v, --verbose     Enable verbose output
#   -q, --quiet       Only show errors
#   -f, --fix         Attempt to fix issues automatically
#   -r, --report      Generate detailed validation report
#   -h, --help        Show this help message
#
# Exit codes:
#   0 - All validations passed
#   1 - Some validations failed
#   2 - Critical errors found
#   3 - Invalid arguments
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$SCRIPT_DIR"
PROJECT_ROOT="$PIPELINE_ROOT"  # For logger compatibility
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
VALIDATION_LOG="$PIPELINE_ROOT/logs/validation_${TIMESTAMP}.log"

# Load logging and metrics libraries
source "$PIPELINE_ROOT/lib/logger.sh" 2>/dev/null || {
    echo "Warning: Advanced logging not available, using basic logging" >&2
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_debug() { echo "[DEBUG] $*"; }
    start_timer() { :; }
    stop_timer() { :; }
}

source "$PIPELINE_ROOT/lib/metrics.sh" 2>/dev/null || {
    echo "Warning: Metrics system not available" >&2
    metrics_track_phase_start() { :; }
    metrics_track_phase_end() { :; }
    metrics_track_task_outcome() { :; }
}

# Set logging context
set_log_context --phase "validation" --task "initialization"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
VERBOSE=false
QUIET=false
FIX_ISSUES=false
GENERATE_REPORT=false
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0
VALIDATION_PASSED=0

# Create logs directory if it doesn't exist
mkdir -p "$PIPELINE_ROOT/logs"

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$VALIDATION_LOG"
    
    if [[ "$QUIET" == "false" || "$level" == "ERROR" ]]; then
        case "$level" in
            "ERROR")
                echo -e "${RED}✗ ERROR: $message${NC}" >&2
                ;;
            "WARN")
                echo -e "${YELLOW}⚠ WARNING: $message${NC}"
                ;;
            "INFO")
                if [[ "$VERBOSE" == "true" ]]; then
                    echo -e "${BLUE}ℹ INFO: $message${NC}"
                fi
                ;;
            "SUCCESS")
                echo -e "${GREEN}✓ $message${NC}"
                ;;
            "DEBUG")
                if [[ "$VERBOSE" == "true" ]]; then
                    echo -e "${PURPLE}🔍 DEBUG: $message${NC}"
                fi
                ;;
        esac
    fi
}

print_header() {
    local title="$1"
    local length=${#title}
    local border=$(printf "%*s" $((length + 4)) '' | tr ' ' '=')
    
    echo -e "\n${CYAN}$border${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}$border${NC}"
}

check_dependency() {
    local name="$1"
    local command="$2"
    local version_flag="${3:-}"
    local min_version="${4:-}"
    
    log "DEBUG" "Checking dependency: $name"
    
    if command -v "$command" >/dev/null 2>&1; then
        local version=""
        if [[ -n "$version_flag" ]]; then
            version=$($command $version_flag 2>&1 | head -n1 || echo "unknown")
        fi
        
        log "SUCCESS" "$name found: $command${version:+ ($version)}"
        ((VALIDATION_PASSED++))
        return 0
    else
        log "ERROR" "$name not found: $command"
        ((VALIDATION_ERRORS++))
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            attempt_install "$name" "$command"
        fi
        return 1
    fi
}

attempt_install() {
    local name="$1"
    local command="$2"
    
    log "INFO" "Attempting to install $name..."
    
    case "$name" in
        "jq")
            if command -v brew >/dev/null 2>&1; then
                brew install jq
            elif command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y jq
            else
                log "WARN" "Cannot auto-install $name - please install manually"
            fi
            ;;
        "task-master")
            log "WARN" "TaskMaster requires manual installation - see documentation"
            ;;
        "openspec")
            log "WARN" "OpenSpec requires manual installation - see documentation"
            ;;
        *)
            log "WARN" "Don't know how to auto-install $name"
            ;;
    esac
}

validate_json_file() {
    local file="$1"
    local description="$2"
    
    log "DEBUG" "Validating JSON file: $file"
    
    if [[ ! -f "$file" ]]; then
        log "ERROR" "$description not found: $file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    if jq empty "$file" >/dev/null 2>&1; then
        log "SUCCESS" "$description is valid JSON: $file"
        ((VALIDATION_PASSED++))
        return 0
    else
        log "ERROR" "$description contains invalid JSON: $file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
}

check_file_executable() {
    local file="$1"
    local description="$2"
    
    log "DEBUG" "Checking if file is executable: $file"
    
    if [[ ! -f "$file" ]]; then
        log "ERROR" "$description not found: $file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    if [[ -x "$file" ]]; then
        log "SUCCESS" "$description is executable: $file"
        ((VALIDATION_PASSED++))
        return 0
    else
        log "ERROR" "$description is not executable: $file"
        ((VALIDATION_ERRORS++))
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            chmod +x "$file"
            log "INFO" "Made $description executable: $file"
        fi
        return 1
    fi
}

validate_directory_structure() {
    local -a required_dirs=(
        "config"
        "hooks"
        "skills"
        "templates"
        "tests"
        "logs"
    )
    
    log "DEBUG" "Validating directory structure"
    
    for dir in "${required_dirs[@]}"; do
        local full_path="$PIPELINE_ROOT/$dir"
        if [[ -d "$full_path" ]]; then
            log "SUCCESS" "Directory exists: $dir"
            ((VALIDATION_PASSED++))
        else
            log "ERROR" "Required directory missing: $dir"
            ((VALIDATION_ERRORS++))
            
            if [[ "$FIX_ISSUES" == "true" ]]; then
                mkdir -p "$full_path"
                log "INFO" "Created directory: $dir"
            fi
        fi
    done
}

validate_skill_files() {
    local skills_dir="$PIPELINE_ROOT/skills"
    local skill_errors=0
    
    log "DEBUG" "Validating skill files"
    
    if [[ ! -d "$skills_dir" ]]; then
        log "ERROR" "Skills directory not found: $skills_dir"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    for skill_dir in "$skills_dir"/*/; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name=$(basename "$skill_dir")
            local skill_md="$skill_dir/SKILL.md"
            
            if [[ -f "$skill_md" ]]; then
                log "SUCCESS" "Skill file found: $skill_name/SKILL.md"
                ((VALIDATION_PASSED++))
                
                # Check if the skill file contains required sections
                if grep -q "## Core Functionality" "$skill_md" && 
                   grep -q "## Activation Patterns" "$skill_md" && 
                   grep -q "## Expected Outputs" "$skill_md"; then
                    log "SUCCESS" "Skill file structure valid: $skill_name"
                    ((VALIDATION_PASSED++))
                else
                    log "WARN" "Skill file missing required sections: $skill_name"
                    ((VALIDATION_WARNINGS++))
                fi
            else
                log "ERROR" "Skill file missing: $skill_name/SKILL.md"
                ((VALIDATION_ERRORS++))
                skill_errors=$((skill_errors + 1))
            fi
        fi
    done
    
    return $skill_errors
}

validate_environment_variables() {
    local -a optional_vars=(
        "GITHUB_ORG"
        "INSTALL_LOCATION"
        "PIPELINE_VERSION"
        "ACTIVATION_MODE"
        "LOG_LEVEL"
    )
    
    log "DEBUG" "Validating environment variables"
    
    # Check if .env file exists
    if [[ -f "$PIPELINE_ROOT/.env" ]]; then
        log "SUCCESS" "Environment file found: .env"
        ((VALIDATION_PASSED++))
        
        # Source the file for validation
        set +u
        source "$PIPELINE_ROOT/.env"
        set -u
        
        # Check optional variables
        for var in "${optional_vars[@]}"; do
            if [[ -n "${!var:-}" ]]; then
                log "SUCCESS" "Environment variable set: $var"
                ((VALIDATION_PASSED++))
            else
                log "WARN" "Optional environment variable not set: $var"
                ((VALIDATION_WARNINGS++))
            fi
        done
    else
        log "WARN" "Environment file not found: .env (using defaults)"
        ((VALIDATION_WARNINGS++))
    fi
}

test_pipeline_communication() {
    log "DEBUG" "Testing basic pipeline communication"
    
    # Test hook execution capability
    local test_hook="$PIPELINE_ROOT/hooks/skill-activation-prompt.sh"
    if [[ -f "$test_hook" && -x "$test_hook" ]]; then
        # Create a test message
        local test_msg="test pipeline validation"
        if timeout 10s bash "$test_hook" "$test_msg" >/dev/null 2>&1; then
            log "SUCCESS" "Hook execution test passed"
            ((VALIDATION_PASSED++))
        else
            log "WARN" "Hook execution test failed (timeout or error)"
            ((VALIDATION_WARNINGS++))
        fi
    else
        log "WARN" "Cannot test hook execution - hook not found or not executable"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Test JSON processing
    if echo '{"test": "validation"}' | jq . >/dev/null 2>&1; then
        log "SUCCESS" "JSON processing test passed"
        ((VALIDATION_PASSED++))
    else
        log "ERROR" "JSON processing test failed"
        ((VALIDATION_ERRORS++))
    fi
}

generate_validation_report() {
    local report_file="$PIPELINE_ROOT/logs/validation_report_${TIMESTAMP}.md"
    
    cat > "$report_file" << EOF
# Claude Dev Pipeline Validation Report

**Generated:** $(date)
**Pipeline Root:** $PIPELINE_ROOT

## Summary

- ✅ **Passed:** $VALIDATION_PASSED
- ⚠️  **Warnings:** $VALIDATION_WARNINGS  
- ❌ **Errors:** $VALIDATION_ERRORS

## Validation Results

EOF

    # Add detailed results from log
    echo "### Detailed Log" >> "$report_file"
    echo '```' >> "$report_file"
    cat "$VALIDATION_LOG" >> "$report_file"
    echo '```' >> "$report_file"
    
    # Add recommendations
    cat >> "$report_file" << EOF

## Recommendations

EOF

    if (( VALIDATION_ERRORS > 0 )); then
        cat >> "$report_file" << EOF
### Critical Issues Found
- $VALIDATION_ERRORS validation errors detected
- Pipeline may not function correctly until these are resolved
- Run with \`--fix\` flag to attempt automatic repairs
- Check the detailed log above for specific issues

EOF
    fi

    if (( VALIDATION_WARNINGS > 0 )); then
        cat >> "$report_file" << EOF
### Warnings
- $VALIDATION_WARNINGS warnings detected
- Pipeline should function but may have reduced capabilities
- Consider addressing warnings for optimal performance

EOF
    fi

    if (( VALIDATION_ERRORS == 0 && VALIDATION_WARNINGS == 0 )); then
        cat >> "$report_file" << EOF
### All Clear! ✨
- All validations passed successfully
- Pipeline is ready for use
- No issues detected

EOF
    fi

    log "INFO" "Validation report generated: $report_file"
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo -e "\n${CYAN}📋 Detailed report saved to: $report_file${NC}"
    fi
}

show_usage() {
    cat << EOF
Claude Dev Pipeline Validation Script

USAGE:
    ./validate.sh [OPTIONS]

OPTIONS:
    -v, --verbose     Enable verbose output
    -q, --quiet       Only show errors
    -f, --fix         Attempt to fix issues automatically
    -r, --report      Generate detailed validation report
    -h, --help        Show this help message

EXAMPLES:
    ./validate.sh                    # Basic validation
    ./validate.sh --verbose          # Verbose validation
    ./validate.sh --fix --report     # Fix issues and generate report
    ./validate.sh --quiet            # Only show errors

EXIT CODES:
    0 - All validations passed
    1 - Some validations failed  
    2 - Critical errors found
    3 - Invalid arguments

EOF
}

# =============================================================================
# Main Validation Functions
# =============================================================================

validate_dependencies() {
    print_header "Dependency Validation"
    
    # Core system dependencies
    check_dependency "Git" "git" "--version"
    check_dependency "Bash" "bash" "--version"
    check_dependency "jq" "jq" "--version"
    
    # Pipeline-specific tools
    check_dependency "TaskMaster" "task-master" "--version"
    check_dependency "OpenSpec" "openspec" "--version"
    
    # Optional but useful tools
    if command -v curl >/dev/null 2>&1; then
        log "SUCCESS" "curl found (useful for downloads)"
        ((VALIDATION_PASSED++))
    else
        log "WARN" "curl not found (may limit some functionality)"
        ((VALIDATION_WARNINGS++))
    fi
}

validate_configuration() {
    print_header "Configuration Validation"
    
    # Validate JSON configuration files
    validate_json_file "$PIPELINE_ROOT/config/skill-rules.json" "Skill rules configuration"
    validate_json_file "$PIPELINE_ROOT/config/settings.json" "Pipeline settings"
    
    # Check for workflow state template
    if [[ -f "$PIPELINE_ROOT/config/workflow-state.template.json" ]]; then
        validate_json_file "$PIPELINE_ROOT/config/workflow-state.template.json" "Workflow state template"
    else
        log "WARN" "Workflow state template not found (will be created on first run)"
        ((VALIDATION_WARNINGS++))
    fi
}

validate_hooks() {
    print_header "Hook Script Validation"
    
    local hooks_dir="$PIPELINE_ROOT/hooks"
    local -a hook_scripts=(
        "skill-activation-prompt.sh"
        "post-tool-use-tracker.sh"
        "pre-implementation-validator.sh"
    )
    
    for script in "${hook_scripts[@]}"; do
        check_file_executable "$hooks_dir/$script" "Hook script ($script)"
    done
}

validate_skills() {
    print_header "Skill Validation"
    validate_skill_files
}

validate_structure() {
    print_header "Directory Structure Validation"
    validate_directory_structure
}

validate_environment() {
    print_header "Environment Validation"
    validate_environment_variables
}

validate_communication() {
    print_header "Pipeline Communication Test"
    test_pipeline_communication
}

# =============================================================================
# Main Script Logic
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
            -f|--fix)
                FIX_ISSUES=true
                shift
                ;;
            -r|--report)
                GENERATE_REPORT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 3
                ;;
        esac
    done
    
    # Start validation
    echo -e "${CYAN}🔍 Claude Dev Pipeline Validation${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo -e "Pipeline Root: ${BLUE}$PIPELINE_ROOT${NC}"
    echo -e "Log File: ${BLUE}$VALIDATION_LOG${NC}"
    
    log "INFO" "Starting validation process"
    log "INFO" "Pipeline root: $PIPELINE_ROOT"
    log "INFO" "Options: verbose=$VERBOSE, quiet=$QUIET, fix=$FIX_ISSUES, report=$GENERATE_REPORT"
    
    # Run all validations
    validate_dependencies
    validate_structure
    validate_configuration
    validate_hooks
    validate_skills
    validate_environment
    validate_communication
    
    # Generate summary
    print_header "Validation Summary"
    
    local total_checks=$((VALIDATION_PASSED + VALIDATION_WARNINGS + VALIDATION_ERRORS))
    
    echo -e "📊 ${BLUE}Total Checks:${NC} $total_checks"
    echo -e "✅ ${GREEN}Passed:${NC} $VALIDATION_PASSED"
    echo -e "⚠️  ${YELLOW}Warnings:${NC} $VALIDATION_WARNINGS"
    echo -e "❌ ${RED}Errors:${NC} $VALIDATION_ERRORS"
    
    log "INFO" "Validation completed - Passed: $VALIDATION_PASSED, Warnings: $VALIDATION_WARNINGS, Errors: $VALIDATION_ERRORS"
    
    # Generate report if requested
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        generate_validation_report
    fi
    
    # Determine exit code
    if (( VALIDATION_ERRORS > 5 )); then
        echo -e "\n${RED}💥 Critical issues found! Pipeline may not function correctly.${NC}"
        exit 2
    elif (( VALIDATION_ERRORS > 0 )); then
        echo -e "\n${YELLOW}⚠️  Some issues found. Pipeline may have reduced functionality.${NC}"
        exit 1
    elif (( VALIDATION_WARNINGS > 0 )); then
        echo -e "\n${YELLOW}⚠️  Minor issues found, but pipeline should work correctly.${NC}"
        exit 0
    else
        echo -e "\n${GREEN}✨ All validations passed! Pipeline is ready to use.${NC}"
        exit 0
    fi
}

# Run the main function
main "$@"