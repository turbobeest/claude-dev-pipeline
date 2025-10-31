#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Post-Run Analysis Tool
# =============================================================================
#
# This script analyzes pipeline execution after completion to assess performance
# and identify any issues or areas for improvement.
#
# Usage:
#   ./analyze-pipeline.sh              # Full analysis
#   ./analyze-pipeline.sh --summary    # Quick summary only
#   ./analyze-pipeline.sh --errors     # Show errors only
#   ./analyze-pipeline.sh --timeline   # Show execution timeline
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Determine project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(pwd)"
fi

# Log locations
LOG_DIR="${PROJECT_ROOT}/.claude/logs"
PIPELINE_LOG="${LOG_DIR}/pipeline.log"
HOOK_LOG="${LOG_DIR}/hooks.log"
METRICS_LOG="${LOG_DIR}/metrics.csv"
STATE_FILE="${PROJECT_ROOT}/.claude/.workflow-state.json"
SIGNALS_DIR="${PROJECT_ROOT}/.claude/.signals"

# =============================================================================
# Analysis Functions
# =============================================================================

show_header() {
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}       Claude Dev Pipeline - Post-Run Analysis Report${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

analyze_summary() {
    echo -e "${BOLD}${YELLOW}═══ EXECUTION SUMMARY ═══${NC}"
    echo ""
    
    # Get final state
    if [[ -f "$STATE_FILE" ]]; then
        local final_phase=$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)
        local completed_tasks=$(jq -r '.completedTasks | length' "$STATE_FILE" 2>/dev/null || echo "0")
        local start_time=$(jq -r '.metadata.installedAt // ""' "$STATE_FILE" 2>/dev/null)
        
        echo -e "  ${CYAN}Final Phase:${NC} $final_phase"
        echo -e "  ${CYAN}Tasks Completed:${NC} $completed_tasks"
        echo -e "  ${CYAN}Pipeline Started:${NC} $start_time"
    fi
    
    # Count key events
    if [[ -f "$PIPELINE_LOG" ]]; then
        local total_activations=$(grep -c "\[ACTIVATE:" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        local total_signals=$(grep -c "\[SIGNAL:" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        local total_errors=$(grep -c "ERROR" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        local total_warnings=$(grep -c "WARNING" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        
        echo -e "  ${CYAN}Skills Activated:${NC} $total_activations"
        echo -e "  ${CYAN}Signals Emitted:${NC} $total_signals"
        echo -e "  ${CYAN}Errors:${NC} ${RED}$total_errors${NC}"
        echo -e "  ${CYAN}Warnings:${NC} ${YELLOW}$total_warnings${NC}"
    fi
    echo ""
}

analyze_phases() {
    echo -e "${BOLD}${YELLOW}═══ PHASE PROGRESSION ═══${NC}"
    echo ""
    
    if [[ -f "$PIPELINE_LOG" ]]; then
        grep "Phase transition:" "$PIPELINE_LOG" 2>/dev/null | while IFS= read -r line; do
            local timestamp=$(echo "$line" | cut -d' ' -f1-2 | tr -d '[]')
            local transition=$(echo "$line" | sed 's/.*Phase transition: //')
            echo -e "  ${CYAN}[$timestamp]${NC} $transition"
        done
    else
        echo -e "  ${YELLOW}No phase transitions found${NC}"
    fi
    echo ""
}

analyze_skill_activations() {
    echo -e "${BOLD}${YELLOW}═══ SKILL ACTIVATIONS ═══${NC}"
    echo ""
    
    if [[ -f "$PIPELINE_LOG" ]]; then
        grep "\[ACTIVATE:" "$PIPELINE_LOG" 2>/dev/null | while IFS= read -r line; do
            local timestamp=$(echo "$line" | cut -d' ' -f1-2 | tr -d '[]')
            local activation=$(echo "$line" | sed 's/.*\[ACTIVATE:/[ACTIVATE:/')
            echo -e "  ${MAGENTA}[$timestamp]${NC} $activation"
        done | head -20
        
        local total=$(grep -c "\[ACTIVATE:" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        if [[ $total -gt 20 ]]; then
            echo -e "  ${CYAN}... and $((total - 20)) more activations${NC}"
        fi
    else
        echo -e "  ${YELLOW}No skill activations found${NC}"
    fi
    echo ""
}

analyze_errors() {
    echo -e "${BOLD}${YELLOW}═══ ERRORS & WARNINGS ═══${NC}"
    echo ""
    
    if [[ -f "$PIPELINE_LOG" ]]; then
        # Show errors
        local error_count=$(grep -c "ERROR" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        if [[ $error_count -gt 0 ]]; then
            echo -e "${RED}Errors ($error_count):${NC}"
            grep "ERROR" "$PIPELINE_LOG" 2>/dev/null | tail -10 | while IFS= read -r line; do
                echo -e "  ${RED}•${NC} $line"
            done
            echo ""
        else
            echo -e "${GREEN}No errors found!${NC}"
        fi
        
        # Show warnings
        local warning_count=$(grep -c "WARNING" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        if [[ $warning_count -gt 0 ]]; then
            echo -e "${YELLOW}Warnings ($warning_count):${NC}"
            grep "WARNING" "$PIPELINE_LOG" 2>/dev/null | tail -5 | while IFS= read -r line; do
                echo -e "  ${YELLOW}•${NC} $line"
            done
            echo ""
        fi
    else
        echo -e "  ${YELLOW}No logs found${NC}"
    fi
    echo ""
}

analyze_performance() {
    echo -e "${BOLD}${YELLOW}═══ PERFORMANCE METRICS ═══${NC}"
    echo ""
    
    if [[ -f "$METRICS_LOG" ]]; then
        # Calculate hook execution times
        local avg_time=$(awk -F',' '$2=="hook_duration" {sum+=$3; count++} END {if(count>0) print sum/count}' "$METRICS_LOG" 2>/dev/null)
        if [[ -n "$avg_time" ]]; then
            echo -e "  ${CYAN}Average Hook Duration:${NC} ${avg_time}s"
        fi
        
        # Show slowest operations
        echo -e "  ${CYAN}Slowest Operations:${NC}"
        sort -t',' -k3 -rn "$METRICS_LOG" 2>/dev/null | head -5 | while IFS=',' read -r timestamp metric value unit; do
            echo -e "    • $metric: ${value}${unit}"
        done
    else
        echo -e "  ${YELLOW}No metrics recorded${NC}"
    fi
    echo ""
}

analyze_timeline() {
    echo -e "${BOLD}${YELLOW}═══ EXECUTION TIMELINE ═══${NC}"
    echo ""
    
    if [[ -f "$PIPELINE_LOG" ]]; then
        # Extract key events with timestamps
        local events=()
        
        # Get first and last timestamps
        local first_line=$(head -1 "$PIPELINE_LOG" 2>/dev/null)
        local last_line=$(tail -1 "$PIPELINE_LOG" 2>/dev/null)
        
        if [[ -n "$first_line" ]]; then
            echo -e "  ${GREEN}START:${NC} $first_line"
        fi
        
        # Show key milestones
        grep -E "\[ACTIVATE:|\[SIGNAL:|Phase transition:" "$PIPELINE_LOG" 2>/dev/null | head -20 | while IFS= read -r line; do
            echo -e "  ${CYAN}→${NC} $line"
        done
        
        if [[ -n "$last_line" ]]; then
            echo -e "  ${GREEN}END:${NC} $last_line"
        fi
    else
        echo -e "  ${YELLOW}No timeline data available${NC}"
    fi
    echo ""
}

generate_recommendations() {
    echo -e "${BOLD}${YELLOW}═══ RECOMMENDATIONS ═══${NC}"
    echo ""
    
    local has_recommendations=false
    
    # Check for errors
    if [[ -f "$PIPELINE_LOG" ]]; then
        local error_count=$(grep -c "ERROR" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        if [[ $error_count -gt 5 ]]; then
            echo -e "  ${RED}⚠${NC} High error count ($error_count) - Review error patterns"
            has_recommendations=true
        fi
        
        # Check for incomplete phases
        if [[ -f "$STATE_FILE" ]]; then
            local phase=$(jq -r '.phase' "$STATE_FILE" 2>/dev/null)
            if [[ "$phase" != "deployed" ]] && [[ "$phase" != "complete" ]]; then
                echo -e "  ${YELLOW}⚠${NC} Pipeline stopped at phase: $phase"
                echo -e "     Consider resuming or investigating blockers"
                has_recommendations=true
            fi
        fi
        
        # Check for skill activation failures
        if ! grep -q "\[ACTIVATE:" "$PIPELINE_LOG" 2>/dev/null; then
            echo -e "  ${YELLOW}⚠${NC} No skill activations detected"
            echo -e "     Verify hook configuration in .claude/settings.json"
            has_recommendations=true
        fi
    fi
    
    if [[ "$has_recommendations" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} Pipeline execution looks healthy!"
    fi
    echo ""
}

export_report() {
    local report_file="${PROJECT_ROOT}/pipeline-analysis-$(date +%Y%m%d-%H%M%S).md"
    
    {
        echo "# Claude Dev Pipeline - Analysis Report"
        echo "Generated: $(date)"
        echo ""
        echo "## Summary"
        analyze_summary | sed 's/\x1b\[[0-9;]*m//g'  # Strip color codes
        echo ""
        echo "## Phase Progression"
        analyze_phases | sed 's/\x1b\[[0-9;]*m//g'
        echo ""
        echo "## Errors and Warnings"
        analyze_errors | sed 's/\x1b\[[0-9;]*m//g'
        echo ""
        echo "## Performance"
        analyze_performance | sed 's/\x1b\[[0-9;]*m//g'
        echo ""
        echo "## Recommendations"
        generate_recommendations | sed 's/\x1b\[[0-9;]*m//g'
    } > "$report_file"
    
    echo -e "${GREEN}Report saved to: $report_file${NC}"
}

# =============================================================================
# Main
# =============================================================================

MODE="${1:-full}"

case "$MODE" in
    --summary|-s)
        show_header
        analyze_summary
        ;;
    --errors|-e)
        show_header
        analyze_errors
        ;;
    --timeline|-t)
        show_header
        analyze_timeline
        ;;
    --export)
        show_header
        export_report
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --summary, -s    Show execution summary only"
        echo "  --errors, -e     Show errors and warnings only"
        echo "  --timeline, -t   Show execution timeline"
        echo "  --export         Export analysis to markdown file"
        echo "  --help, -h       Show this help"
        echo ""
        echo "Default: Full analysis report"
        ;;
    *)
        show_header
        analyze_summary
        analyze_phases
        analyze_skill_activations
        analyze_errors
        analyze_performance
        generate_recommendations
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "To export this report: $0 --export"
        ;;
esac