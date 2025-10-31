#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Real-Time Monitor
# =============================================================================
#
# This script provides real-time monitoring of the pipeline execution.
# Run this in a separate terminal to watch the pipeline progress.
#
# Usage:
#   ./monitor-pipeline.sh          # Monitor all logs
#   ./monitor-pipeline.sh --live   # Live tail mode
#   ./monitor-pipeline.sh --phase  # Show current phase
#   ./monitor-pipeline.sh --stats  # Show statistics
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
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Log locations
LOG_DIR="${PROJECT_ROOT}/.claude/logs"
PIPELINE_LOG="${LOG_DIR}/pipeline.log"
HOOK_LOG="${LOG_DIR}/hooks.log"
STATE_FILE="${PROJECT_ROOT}/.claude/.workflow-state.json"
SIGNALS_DIR="${PROJECT_ROOT}/.claude/.signals"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# =============================================================================
# Functions
# =============================================================================

show_header() {
    clear
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}         Claude Dev Pipeline - Real-Time Monitor v3.0${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

show_current_phase() {
    if [[ -f "$STATE_FILE" ]]; then
        local phase=$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
        local last_signal=$(jq -r '.lastSignal // ""' "$STATE_FILE" 2>/dev/null || echo "")
        local completed_tasks=$(jq -r '.completedTasks | length' "$STATE_FILE" 2>/dev/null || echo "0")
        
        echo -e "${BOLD}Current Status:${NC}"
        echo -e "  ${YELLOW}Phase:${NC} $phase"
        echo -e "  ${YELLOW}Last Signal:${NC} $last_signal"
        echo -e "  ${YELLOW}Completed Tasks:${NC} $completed_tasks"
        echo ""
    else
        echo -e "${RED}State file not found. Pipeline may not be initialized.${NC}"
    fi
}

show_active_signals() {
    echo -e "${BOLD}Active Signals:${NC}"
    if [[ -d "$SIGNALS_DIR" ]] && [[ -n "$(ls -A "$SIGNALS_DIR" 2>/dev/null)" ]]; then
        for signal in "$SIGNALS_DIR"/*; do
            if [[ -f "$signal" ]]; then
                local signal_name=$(basename "$signal")
                local signal_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$signal" 2>/dev/null || date)
                echo -e "  ${GREEN}✓${NC} $signal_name (${signal_time})"
            fi
        done
    else
        echo -e "  ${YELLOW}No active signals${NC}"
    fi
    echo ""
}

show_recent_logs() {
    echo -e "${BOLD}Recent Activity:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    
    if [[ -f "$PIPELINE_LOG" ]]; then
        tail -n 20 "$PIPELINE_LOG" | while IFS= read -r line; do
            if [[ "$line" == *"ERROR"* ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ "$line" == *"SUCCESS"* ]] || [[ "$line" == *"COMPLETE"* ]]; then
                echo -e "${GREEN}$line${NC}"
            elif [[ "$line" == *"ACTIVATE"* ]]; then
                echo -e "${MAGENTA}$line${NC}"
            elif [[ "$line" == *"WARNING"* ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        echo -e "${YELLOW}No pipeline logs yet${NC}"
    fi
}

show_statistics() {
    echo -e "${BOLD}Pipeline Statistics:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    
    local total_hooks=0
    local total_skills=0
    local total_errors=0
    
    if [[ -f "$PIPELINE_LOG" ]]; then
        total_hooks=$(grep -c "HOOK:" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        total_skills=$(grep -c "ACTIVATE:" "$PIPELINE_LOG" 2>/dev/null || echo 0)
        total_errors=$(grep -c "ERROR" "$PIPELINE_LOG" 2>/dev/null || echo 0)
    fi
    
    echo -e "  ${YELLOW}Hook Executions:${NC} $total_hooks"
    echo -e "  ${YELLOW}Skills Activated:${NC} $total_skills"
    echo -e "  ${YELLOW}Errors:${NC} $total_errors"
    echo ""
}

live_monitor() {
    show_header
    echo -e "${BOLD}${GREEN}Live Monitoring Mode - Press Ctrl+C to exit${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Create pipes for multiplexing
    touch "$PIPELINE_LOG" "$HOOK_LOG"
    
    # Monitor multiple files simultaneously
    tail -f "$PIPELINE_LOG" "$HOOK_LOG" "$STATE_FILE" 2>/dev/null | while IFS= read -r line; do
        # Color code based on content
        if [[ "$line" == *"==>"* ]]; then
            # File marker from tail
            echo -e "${BOLD}${BLUE}$line${NC}"
        elif [[ "$line" == *"ERROR"* ]]; then
            echo -e "${RED}$(date '+%H:%M:%S') | $line${NC}"
        elif [[ "$line" == *"SUCCESS"* ]] || [[ "$line" == *"COMPLETE"* ]]; then
            echo -e "${GREEN}$(date '+%H:%M:%S') | $line${NC}"
        elif [[ "$line" == *"[ACTIVATE:"* ]]; then
            echo -e "${BOLD}${MAGENTA}$(date '+%H:%M:%S') | 🚀 $line${NC}"
        elif [[ "$line" == *"[SIGNAL:"* ]]; then
            echo -e "${BOLD}${CYAN}$(date '+%H:%M:%S') | 📡 $line${NC}"
        elif [[ "$line" == *"WARNING"* ]]; then
            echo -e "${YELLOW}$(date '+%H:%M:%S') | $line${NC}"
        elif [[ "$line" == *"phase"* ]]; then
            echo -e "${BOLD}$(date '+%H:%M:%S') | $line${NC}"
        else
            echo "$(date '+%H:%M:%S') | $line"
        fi
    done
}

dashboard_mode() {
    while true; do
        show_header
        show_current_phase
        show_active_signals
        show_statistics
        echo ""
        show_recent_logs
        
        # Refresh every 2 seconds
        sleep 2
    done
}

# =============================================================================
# Main
# =============================================================================

# Parse arguments
MODE="${1:-dashboard}"

case "$MODE" in
    --live|-l)
        live_monitor
        ;;
    --phase|-p)
        show_header
        show_current_phase
        ;;
    --stats|-s)
        show_header
        show_statistics
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --live, -l     Live tail mode (real-time log streaming)"
        echo "  --phase, -p    Show current phase only"
        echo "  --stats, -s    Show statistics only"
        echo "  --help, -h     Show this help"
        echo ""
        echo "Default: Dashboard mode (refreshes every 2 seconds)"
        ;;
    *)
        dashboard_mode
        ;;
esac