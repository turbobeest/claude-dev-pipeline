#!/bin/bash
# =============================================================================
# Task Review Interactive Hook
# Provides interactive review session after task generation
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly TASKS_FILE="${PROJECT_ROOT}/tasks.json"
readonly REVIEWED_FILE="${PROJECT_ROOT}/tasks-reviewed.json"
readonly REVIEW_LOG="${PROJECT_ROOT}/.task-review-log.json"

# Colors
readonly BOLD='\033[1m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Check if this is a task review trigger
if [[ "${CLAUDE_SIGNAL:-}" != "TASKS_GENERATED" ]] && [[ "${1:-}" != "manual" ]]; then
    exit 0
fi

# Display task summary
display_task_summary() {
    if [ ! -f "$TASKS_FILE" ]; then
        echo -e "${RED}No tasks.json found${NC}"
        return 1
    fi
    
    local task_count=$(jq 'length' "$TASKS_FILE" 2>/dev/null || echo "0")
    
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  TASK REVIEW & APPROVAL GATE${NC}"
    echo -e "${BOLD}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Generated $task_count tasks from PRD analysis${NC}"
    echo ""
    
    # Group tasks by phase
    echo -e "${YELLOW}Task Overview:${NC}"
    echo ""
    
    # Display tasks in a readable format
    jq -r '.[] | "  Task \(.id): \(.title)"' "$TASKS_FILE" 2>/dev/null | head -20
    
    if [ "$task_count" -gt 20 ]; then
        echo "  ... and $((task_count - 20)) more tasks"
    fi
    
    echo ""
}

# Interactive review prompt
show_review_prompt() {
    echo -e "${BOLD}How would you like to proceed?${NC}"
    echo ""
    echo "  ${GREEN}approve${NC}  - Accept tasks and start automation"
    echo "  ${YELLOW}review${NC}   - Detailed review with modifications"
    echo "  ${CYAN}show${NC}     - Show all tasks with details"
    echo "  ${CYAN}phase X${NC}  - Show tasks for phase X"
    echo "  ${YELLOW}modify X${NC} - Modify task X"
    echo "  ${YELLOW}add${NC}      - Add a new task"
    echo "  ${RED}reject${NC}   - Regenerate tasks from PRD"
    echo ""
    echo -e "${BOLD}You can also provide natural language feedback:${NC}"
    echo '  "Task 7 should come before task 6"'
    echo '  "Add security audit after task 15"'
    echo '  "Split authentication into JWT and OAuth"'
    echo ""
}

# Create review signal
create_review_signal() {
    local signal_type=$1
    local signal_file="${PROJECT_ROOT}/.claude/.task-review-signal.json"
    
    mkdir -p "$(dirname "$signal_file")"
    
    cat > "$signal_file" << EOF
{
    "signal": "$signal_type",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "task_count": $(jq 'length' "$TASKS_FILE" 2>/dev/null || echo 0),
    "reviewed": true
}
EOF
}

# Main review interface
main() {
    display_task_summary
    
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   TASK REVIEW CHECKPOINT${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╗${NC}"
    echo ""
    echo "The pipeline has generated tasks from your PRD."
    echo "This is your opportunity to review and refine before"
    echo "the fully automated development begins."
    echo ""
    
    show_review_prompt
    
    # Signal that review is starting
    echo "TASK_REVIEW_ACTIVE" > "${PROJECT_ROOT}/.claude/.pipeline-signal" 2>/dev/null || true
    
    echo -e "${YELLOW}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Review Mode Active${NC}"
    echo ""
    echo "I'll help you review and refine the generated tasks."
    echo "You can:"
    echo "  • View detailed breakdowns"
    echo "  • Modify any task"
    echo "  • Reorder dependencies"
    echo "  • Add or remove tasks"
    echo "  • Use natural language to describe changes"
    echo ""
    echo "When you're satisfied, type '${GREEN}approve${NC}' to continue"
    echo "with full automation."
    echo ""
    echo -e "${CYAN}What would you like to do?${NC}"
    echo ""
    
    # Create review state
    create_review_signal "UNDER_REVIEW"
    
    # Copy tasks to reviewed file initially
    cp "$TASKS_FILE" "$REVIEWED_FILE"
    
    # Log review session
    cat > "$REVIEW_LOG" << EOF
{
    "session_started": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "original_task_count": $(jq 'length' "$TASKS_FILE"),
    "status": "under_review",
    "modifications": []
}
EOF
}

# Run main review interface
main "$@"