#!/bin/bash
# =============================================================================
# PRD Requirement Extractor
# Dynamically extracts critical requirements from any PRD
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly PRD_FILE="${PROJECT_ROOT}/docs/PRD.md"
readonly REQUIREMENTS_FILE="${PROJECT_ROOT}/.prd-requirements.json"

# Colors
readonly BOLD='\033[1m'
readonly CYAN='\033[0;36m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Extract explicit requirements from PRD
extract_requirements() {
    local requirements=()
    local constraints=()
    local must_use=()
    local cannot_use=()
    
    if [ ! -f "$PRD_FILE" ]; then
        echo "[]"
        return
    fi
    
    # Look for explicit requirement patterns in PRD
    # These are generic patterns that work for any PRD
    
    # Extract "MUST use X" statements
    while IFS= read -r line; do
        if [[ "$line" =~ [Mm][Uu][Ss][Tt][[:space:]]+(use|implement|have)[[:space:]]+([^[:space:]]+) ]]; then
            must_use+=("${BASH_REMATCH[2]}")
        fi
    done < "$PRD_FILE"
    
    # Extract "DO NOT use X" or "CANNOT use X" statements
    while IFS= read -r line; do
        if [[ "$line" =~ ([Dd][Oo][[:space:]]+[Nn][Oo][Tt]|[Cc][Aa][Nn][Nn][Oo][Tt])[[:space:]]+(use|substitute)[[:space:]]+([^[:space:]]+) ]]; then
            cannot_use+=("${BASH_REMATCH[3]}")
        fi
    done < "$PRD_FILE"
    
    # Extract requirements from structured sections
    local in_requirements=false
    while IFS= read -r line; do
        # Check for requirements section
        if [[ "$line" =~ ^#+.*[Rr]equirement ]]; then
            in_requirements=true
        elif [[ "$line" =~ ^#+ ]] && [ "$in_requirements" = true ]; then
            in_requirements=false
        elif [ "$in_requirements" = true ] && [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.*) ]]; then
            requirements+=("${BASH_REMATCH[1]}")
        fi
    done < "$PRD_FILE"
    
    # Generate JSON output
    cat > "$REQUIREMENTS_FILE" << EOF
{
    "extracted_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "source": "$PRD_FILE",
    "must_use": [$(printf '"%s",' "${must_use[@]}" | sed 's/,$//')]],
    "cannot_use": [$(printf '"%s",' "${cannot_use[@]}" | sed 's/,$//')]],
    "requirements": [$(printf '"%s",' "${requirements[@]}" | sed 's/,$//')]],
    "validation_rules": []
}
EOF
}

# Extract architectural patterns from PRD
extract_architecture() {
    local patterns=()
    
    if [ ! -f "$PRD_FILE" ]; then
        return
    fi
    
    # Look for architectural descriptions
    # Generic patterns that apply to any system
    
    # Service separation patterns
    if grep -qi "separation\|boundary\|isolated\|decoupled" "$PRD_FILE"; then
        patterns+=("service_separation")
    fi
    
    # Security patterns
    if grep -qi "sanitiz\|validat\|security\|protect" "$PRD_FILE"; then
        patterns+=("security_validation")
    fi
    
    # Integration patterns
    if grep -qi "integrat\|connect\|interface\|API" "$PRD_FILE"; then
        patterns+=("integration_required")
    fi
    
    # Add patterns to requirements
    if [ ${#patterns[@]} -gt 0 ]; then
        jq --arg patterns "$(printf '%s,' "${patterns[@]}" | sed 's/,$//')" \
           '.architectural_patterns = ($patterns | split(","))' \
           "$REQUIREMENTS_FILE" > tmp.json && mv tmp.json "$REQUIREMENTS_FILE"
    fi
}

# Generate validation rules based on requirements
generate_validation_rules() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        return
    fi
    
    # Read must_use items
    local must_use_items=$(jq -r '.must_use[]' "$REQUIREMENTS_FILE" 2>/dev/null)
    
    # Create validation rules for each required item
    while IFS= read -r item; do
        if [ -n "$item" ]; then
            # Add a validation rule
            jq --arg item "$item" \
               '.validation_rules += [{
                   "type": "must_exist",
                   "item": $item,
                   "check": "grep -r \"" + $item + "\" src/ || find src/ -name \"*" + $item + "*\""
               }]' \
               "$REQUIREMENTS_FILE" > tmp.json && mv tmp.json "$REQUIREMENTS_FILE"
        fi
    done <<< "$must_use_items"
}

# Main execution
main() {
    echo -e "${BOLD}Extracting PRD Requirements...${NC}"
    echo ""
    
    if [ ! -f "$PRD_FILE" ]; then
        echo -e "${YELLOW}PRD not found at: $PRD_FILE${NC}"
        echo "Creating empty requirements file..."
        echo '{"requirements": [], "must_use": [], "cannot_use": []}' > "$REQUIREMENTS_FILE"
        return 0
    fi
    
    # Extract requirements
    extract_requirements
    
    # Extract architectural patterns
    extract_architecture
    
    # Generate validation rules
    generate_validation_rules
    
    # Display summary
    echo -e "${CYAN}Requirements extracted:${NC}"
    echo ""
    
    local must_use_count=$(jq '.must_use | length' "$REQUIREMENTS_FILE")
    local cannot_use_count=$(jq '.cannot_use | length' "$REQUIREMENTS_FILE")
    local req_count=$(jq '.requirements | length' "$REQUIREMENTS_FILE")
    
    echo "  • Must use: $must_use_count items"
    echo "  • Cannot use: $cannot_use_count items"
    echo "  • Requirements: $req_count items"
    echo ""
    
    if [ "$must_use_count" -gt 0 ]; then
        echo "Must use:"
        jq -r '.must_use[]' "$REQUIREMENTS_FILE" | while IFS= read -r item; do
            echo "  ✓ $item"
        done
        echo ""
    fi
    
    if [ "$cannot_use_count" -gt 0 ]; then
        echo "Cannot use:"
        jq -r '.cannot_use[]' "$REQUIREMENTS_FILE" | while IFS= read -r item; do
            echo "  ✗ $item"
        done
        echo ""
    fi
    
    echo "Requirements saved to: $REQUIREMENTS_FILE"
}

# Run extraction
main "$@"