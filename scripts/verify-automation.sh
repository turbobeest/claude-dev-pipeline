#!/bin/bash
# =============================================================================
# Pipeline Automation Verifier
# Ensures the pipeline runs fully autonomously without manual intervention
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"
readonly SKILL_RULES="${PIPELINE_ROOT}/config/skill-rules.json"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   PIPELINE AUTOMATION VERIFICATION       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# Check if skill rules file exists
if [ ! -f "$SKILL_RULES" ]; then
    echo -e "${RED}ERROR: skill-rules.json not found${NC}"
    exit 1
fi

echo -e "${CYAN}Checking phase transitions for automation...${NC}"
echo ""

# Check all phase transitions
MANUAL_TRANSITIONS=0
AUTO_TRANSITIONS=0

# Extract all phase transitions
TRANSITIONS=$(jq -r '.phase_transitions | to_entries[] | "\(.key):\(.value.auto_trigger):\(.value.requires_user_confirmation // false)"' "$SKILL_RULES")

echo "Phase Transition Analysis:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while IFS=':' read -r phase auto_trigger requires_confirmation; do
    if [ "$auto_trigger" = "true" ] && [ "$requires_confirmation" = "false" ]; then
        echo -e "  ${GREEN}✓${NC} $phase → Automatic"
        AUTO_TRANSITIONS=$((AUTO_TRANSITIONS + 1))
    else
        echo -e "  ${RED}✗${NC} $phase → Manual intervention required"
        echo -e "    ${YELLOW}auto_trigger=$auto_trigger, requires_confirmation=$requires_confirmation${NC}"
        MANUAL_TRANSITIONS=$((MANUAL_TRANSITIONS + 1))
    fi
done <<< "$TRANSITIONS"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check skill activation patterns
echo "Skill Activation Chain:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Map out the skill chain
echo -e "${CYAN}Phase 0${NC}: PRD Creation (Manual)"
echo "    ↓"
echo -e "${GREEN}Phase 1${NC}: PRD → Tasks → Coupling → Decomposition"

# Check Phase 1 chain
P1_AUTO=$(jq -r '.phase_transitions.PHASE1_START.auto_trigger' "$SKILL_RULES")
if [ "$P1_AUTO" = "true" ]; then
    echo -e "    ${GREEN}✓ Automatic${NC}"
else
    echo -e "    ${RED}✗ Manual${NC}"
fi

echo "    ↓"
echo -e "${GREEN}Phase 2${NC}: Spec Generation → Test Strategy"

# Check Phase 2 chain
P2_AUTO=$(jq -r '.phase_transitions.PHASE1_COMPLETE.auto_trigger' "$SKILL_RULES")
if [ "$P2_AUTO" = "true" ]; then
    echo -e "    ${GREEN}✓ Automatic${NC}"
else
    echo -e "    ${RED}✗ Manual${NC}"
fi

echo "    ↓"
echo -e "${GREEN}Phase 3${NC}: TDD Implementation"

# Check Phase 3 transition
P3_AUTO=$(jq -r '.phase_transitions.TEST_STRATEGY_COMPLETE.auto_trigger' "$SKILL_RULES")
if [ "$P3_AUTO" = "true" ]; then
    echo -e "    ${GREEN}✓ Automatic${NC}"
else
    echo -e "    ${RED}✗ Manual - FIX NEEDED${NC}"
fi

echo "    ↓"
echo -e "${GREEN}Phase 4${NC}: Integration Testing"

# Check Phase 4 transition
P4_AUTO=$(jq -r '.phase_transitions.PHASE3_COMPLETE.auto_trigger' "$SKILL_RULES")
if [ "$P4_AUTO" = "true" ]; then
    echo -e "    ${GREEN}✓ Automatic${NC}"
else
    echo -e "    ${RED}✗ Manual${NC}"
fi

echo "    ↓"
echo -e "${GREEN}Phase 5${NC}: E2E Testing"

# Check Phase 5 transition
P5_AUTO=$(jq -r '.phase_transitions.PHASE4_COMPLETE.auto_trigger' "$SKILL_RULES")
if [ "$P5_AUTO" = "true" ]; then
    echo -e "    ${GREEN}✓ Automatic${NC}"
else
    echo -e "    ${RED}✗ Manual${NC}"
fi

echo "    ↓"
echo -e "${GREEN}Phase 6${NC}: Deployment & Demo"

# Check Phase 6 transition
P6_AUTO=$(jq -r '.phase_transitions.PHASE5_COMPLETE.auto_trigger' "$SKILL_RULES")
if [ "$P6_AUTO" = "true" ]; then
    echo -e "    ${GREEN}✓ Automatic${NC}"
else
    echo -e "    ${RED}✗ Manual - FIX NEEDED${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Final verdict
if [ $MANUAL_TRANSITIONS -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ PIPELINE IS FULLY AUTONOMOUS${NC}"
    echo ""
    echo "All phase transitions are automatic."
    echo "No manual intervention required after PRD approval."
    echo ""
    echo -e "${CYAN}Expected Flow:${NC}"
    echo "1. User provides PRD and approves tasks"
    echo "2. Pipeline runs automatically through all 6 phases"
    echo "3. Docker containers built and started"
    echo "4. Demo environment ready without any 'please proceed' prompts"
else
    echo -e "${RED}${BOLD}⚠️  MANUAL INTERVENTIONS DETECTED${NC}"
    echo ""
    echo "Found $MANUAL_TRANSITIONS phase transitions requiring manual intervention."
    echo "The pipeline will pause and require 'please proceed' at these points."
    echo ""
    echo -e "${YELLOW}To fix:${NC}"
    echo "1. Edit config/skill-rules.json"
    echo "2. Set auto_trigger: true for all transitions"
    echo "3. Set requires_user_confirmation: false"
fi

echo ""

# Check for approval gates
echo "Special Gates:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APPROVAL_GATES=$(jq -r '.phase_transitions | to_entries[] | select(.value.approval_gate != null) | "\(.key): \(.value.approval_gate)"' "$SKILL_RULES")

if [ -n "$APPROVAL_GATES" ]; then
    echo "$APPROVAL_GATES" | while IFS=':' read -r phase gate; do
        echo -e "  ${YELLOW}⚠${NC} $phase has approval gate: $gate"
        echo "    (This is OK for production deployment)"
    done
else
    echo -e "  ${GREEN}✓${NC} No blocking approval gates"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show automation level
AUTOMATION_LEVEL=$(jq -r '.notes.automation_level // "Not specified"' "$SKILL_RULES")
echo -e "${BOLD}Automation Level:${NC} $AUTOMATION_LEVEL"
echo ""

exit $MANUAL_TRANSITIONS