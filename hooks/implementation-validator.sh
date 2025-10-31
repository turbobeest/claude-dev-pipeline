#!/bin/bash
# =============================================================================
# Implementation Validator
# Validates implementation against PRD-extracted requirements (not hardcoded)
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly REQUIREMENTS_FILE="${PROJECT_ROOT}/.prd-requirements.json"
readonly VALIDATION_REPORT="${PROJECT_ROOT}/.validation-report.json"
readonly IMPLEMENTATION_DIR="${PROJECT_ROOT}/src"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Log function
log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $*"
            ;;
        *)
            echo "$*"
            ;;
    esac
}

# Validate against PRD requirements
validate_requirements() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        log WARNING "No requirements file found. Running extractor..."
        "$SCRIPT_DIR/prd-requirement-extractor.sh"
    fi
    
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        log ERROR "Failed to extract requirements from PRD"
        return 1
    fi
    
    # Initialize report
    cat > "$VALIDATION_REPORT" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "passed": true,
    "violations": [],
    "verified": []
}
EOF
    
    local has_violations=false
    
    # Check must_use requirements
    local must_use_items=$(jq -r '.must_use[]' "$REQUIREMENTS_FILE" 2>/dev/null)
    
    if [ -n "$must_use_items" ]; then
        echo "Checking required components..."
        while IFS= read -r item; do
            if [ -z "$item" ]; then
                continue
            fi
            
            log INFO "Checking for: $item"
            
            # Generic search for the requirement in implementation
            local found=false
            
            # Search in code files
            if [ -d "$IMPLEMENTATION_DIR" ]; then
                if find "$IMPLEMENTATION_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" \) \
                   -exec grep -l "$item" {} \; 2>/dev/null | head -1 | grep -q .; then
                    found=true
                fi
                
                # Also check for file names containing the item
                if find "$IMPLEMENTATION_DIR" -type f -name "*${item}*" 2>/dev/null | head -1 | grep -q .; then
                    found=true
                fi
                
                # Check docker-compose if it exists
                if [ -f "${PROJECT_ROOT}/docker-compose.yml" ]; then
                    if grep -q "$item" "${PROJECT_ROOT}/docker-compose.yml" 2>/dev/null; then
                        found=true
                    fi
                fi
            fi
            
            if [ "$found" = false ]; then
                log ERROR "Missing required component: $item"
                
                # Add violation
                jq --arg item "$item" \
                   '.violations += ["Missing required component: " + $item] | .passed = false' \
                   "$VALIDATION_REPORT" > tmp.json && mv tmp.json "$VALIDATION_REPORT"
                
                has_violations=true
            else
                log SUCCESS "Found required component: $item"
                
                # Add to verified
                jq --arg item "$item" \
                   '.verified += [$item]' \
                   "$VALIDATION_REPORT" > tmp.json && mv tmp.json "$VALIDATION_REPORT"
            fi
        done <<< "$must_use_items"
    fi
    
    # Check cannot_use restrictions
    local cannot_use_items=$(jq -r '.cannot_use[]' "$REQUIREMENTS_FILE" 2>/dev/null)
    
    if [ -n "$cannot_use_items" ]; then
        echo "Checking for forbidden components..."
        while IFS= read -r item; do
            if [ -z "$item" ]; then
                continue
            fi
            
            log INFO "Ensuring not using: $item"
            
            # Search for forbidden item
            local found=false
            
            if [ -d "$IMPLEMENTATION_DIR" ]; then
                if find "$IMPLEMENTATION_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" \) \
                   -exec grep -l "$item" {} \; 2>/dev/null | head -1 | grep -q .; then
                    found=true
                fi
            fi
            
            if [ "$found" = true ]; then
                log ERROR "Found forbidden component: $item"
                
                # Add violation
                jq --arg item "$item" \
                   '.violations += ["Using forbidden component: " + $item] | .passed = false' \
                   "$VALIDATION_REPORT" > tmp.json && mv tmp.json "$VALIDATION_REPORT"
                
                has_violations=true
            else
                log SUCCESS "Not using forbidden: $item"
            fi
        done <<< "$cannot_use_items"
    fi
    
    # Check architectural patterns
    local patterns=$(jq -r '.architectural_patterns[]?' "$REQUIREMENTS_FILE" 2>/dev/null)
    
    if [ -n "$patterns" ]; then
        echo "Checking architectural patterns..."
        while IFS= read -r pattern; do
            case "$pattern" in
                service_separation)
                    # Check for service directory structure
                    if [ -d "$IMPLEMENTATION_DIR/services" ] || [ -d "$IMPLEMENTATION_DIR/modules" ]; then
                        log SUCCESS "Service separation detected"
                    else
                        log WARNING "Service separation pattern not clearly visible"
                    fi
                    ;;
                security_validation)
                    # Check for validation/sanitization code
                    if [ -d "$IMPLEMENTATION_DIR" ]; then
                        if find "$IMPLEMENTATION_DIR" -type f -exec grep -l "validat\|sanitiz" {} \; 2>/dev/null | head -1 | grep -q .; then
                            log SUCCESS "Security validation found"
                        else
                            log WARNING "Security validation not clearly visible"
                        fi
                    fi
                    ;;
                *)
                    log INFO "Pattern: $pattern"
                    ;;
            esac
        done <<< "$patterns"
    fi
    
    # Final verdict
    if [ "$has_violations" = true ]; then
        echo ""
        echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  VALIDATION FAILED${NC}"
        echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "The following violations were found:"
        jq -r '.violations[]' "$VALIDATION_REPORT" 2>/dev/null | while IFS= read -r violation; do
            echo "  ❌ $violation"
        done
        echo ""
        echo "Report saved to: $VALIDATION_REPORT"
        return 1
    else
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  VALIDATION PASSED${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "All PRD requirements verified!"
        echo "Report saved to: $VALIDATION_REPORT"
        return 0
    fi
}

# Main execution
main() {
    log INFO "Starting implementation validation against PRD requirements..."
    echo ""
    
    # Extract requirements if not present
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        "$SCRIPT_DIR/prd-requirement-extractor.sh"
    fi
    
    # Run validation
    validate_requirements
}

# Run validation
main "$@"