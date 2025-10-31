#!/bin/bash

# =============================================================================
# Claude Dev Pipeline - Health Check Script
# =============================================================================
# 
# Real-time monitoring and health checking for the pipeline system
# 
# Usage:
#   ./health-check.sh [options]
#
# Options:
#   -w, --watch       Continuous monitoring mode (refresh every 5s)
#   -i, --interval N  Set refresh interval for watch mode (seconds)
#   -v, --verbose     Enable verbose output
#   -q, --quiet       Only show critical issues
#   -j, --json        Output in JSON format
#   -l, --logs        Show recent activity log
#   -h, --help        Show this help message
#
# Exit codes:
#   0 - System healthy
#   1 - Minor issues detected
#   2 - Major issues detected
#   3 - Critical system failure
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$SCRIPT_DIR"
PROJECT_ROOT="$PIPELINE_ROOT"  # For logger compatibility
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HEALTH_LOG="$PIPELINE_ROOT/logs/health_${TIMESTAMP}.log"

# Load logging and metrics libraries
source "$PIPELINE_ROOT/lib/logger.sh" 2>/dev/null || {
    echo "Warning: Advanced logging not available, using basic logging" >&2
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_debug() { echo "[DEBUG] $*"; }
    start_timer() { :; }
    stop_timer() { :; }
    get_health_status() { echo '{"score":100,"status":"healthy"}'; }
}

source "$PIPELINE_ROOT/lib/metrics.sh" 2>/dev/null || {
    echo "Warning: Metrics system not available" >&2
    metrics_track_phase_start() { :; }
    metrics_track_phase_end() { :; }
    metrics_collect_system_stats() { echo '{"cpu_usage":0,"memory_usage":0,"disk_usage":0}'; }
    metrics_calculate_health_score() { echo "100"; }
}

# Set logging context
set_log_context --phase "health_check" --task "monitoring"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
WATCH_MODE=false
REFRESH_INTERVAL=5
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
SHOW_LOGS=false
HEALTH_SCORE=100
CRITICAL_ISSUES=0
MAJOR_ISSUES=0
MINOR_ISSUES=0

# Create logs directory if it doesn't exist
mkdir -p "$PIPELINE_ROOT/logs"

# =============================================================================
# Helper Functions
# =============================================================================

log_health() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$HEALTH_LOG"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        return
    fi
    
    if [[ "$QUIET" == "false" || "$level" == "CRITICAL" || "$level" == "MAJOR" ]]; then
        case "$level" in
            "CRITICAL")
                echo -e "${RED}🚨 CRITICAL: $message${NC}"
                ((CRITICAL_ISSUES++))
                HEALTH_SCORE=$((HEALTH_SCORE - 20))
                ;;
            "MAJOR")
                echo -e "${RED}❌ MAJOR: $message${NC}"
                ((MAJOR_ISSUES++))
                HEALTH_SCORE=$((HEALTH_SCORE - 10))
                ;;
            "MINOR")
                echo -e "${YELLOW}⚠️  MINOR: $message${NC}"
                ((MINOR_ISSUES++))
                HEALTH_SCORE=$((HEALTH_SCORE - 5))
                ;;
            "GOOD")
                echo -e "${GREEN}✅ $message${NC}"
                ;;
            "INFO")
                if [[ "$VERBOSE" == "true" ]]; then
                    echo -e "${BLUE}ℹ️  $message${NC}"
                fi
                ;;
        esac
    fi
}

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

format_uptime() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if (( days > 0 )); then
        echo "${days}d ${hours}h ${minutes}m"
    elif (( hours > 0 )); then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

check_file_age() {
    local file="$1"
    local max_age_minutes="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    local file_age_seconds=$(( $(date +%s) - $(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0) ))
    local file_age_minutes=$((file_age_seconds / 60))
    
    if (( file_age_minutes > max_age_minutes )); then
        return 1
    fi
    
    return 0
}

get_file_age_human() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "N/A"
        return
    fi
    
    local file_age_seconds=$(( $(date +%s) - $(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0) ))
    
    if (( file_age_seconds < 60 )); then
        echo "${file_age_seconds}s"
    elif (( file_age_seconds < 3600 )); then
        echo "$((file_age_seconds / 60))m"
    elif (( file_age_seconds < 86400 )); then
        echo "$((file_age_seconds / 3600))h"
    else
        echo "$((file_age_seconds / 86400))d"
    fi
}

# =============================================================================
# Health Check Functions
# =============================================================================

check_pipeline_status() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}🔍 Pipeline Status${NC}"
        echo -e "${CYAN}==================${NC}"
    fi
    
    # Check if pipeline is running
    local state_file="$PIPELINE_ROOT/config/workflow-state.json"
    if [[ -f "$state_file" ]]; then
        local current_phase=$(jq -r '.current_phase // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
        local phase_status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
        local last_update=$(jq -r '.last_updated // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
        
        log_health "GOOD" "Workflow state file accessible"
        log_health "INFO" "Current phase: $current_phase"
        log_health "INFO" "Phase status: $phase_status"
        log_health "INFO" "Last update: $last_update"
        
        # Check if state file is recent (within last hour)
        if ! check_file_age "$state_file" 60; then
            log_health "MINOR" "Workflow state file is stale ($(get_file_age_human "$state_file") old)"
        fi
    else
        log_health "MAJOR" "Workflow state file not found"
    fi
}

check_worktree_status() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}🌳 Worktree Status${NC}"
        echo -e "${CYAN}====================${NC}"
    fi
    
    # Check git repository status
    if git rev-parse --git-dir >/dev/null 2>&1; then
        log_health "GOOD" "Git repository accessible"
        
        # Check for uncommitted changes
        if [[ -n "$(git status --porcelain)" ]]; then
            local changed_files=$(git status --porcelain | wc -l | tr -d ' ')
            log_health "MINOR" "$changed_files files with uncommitted changes"
        else
            log_health "GOOD" "Working directory clean"
        fi
        
        # Check current branch
        local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        log_health "INFO" "Current branch: $current_branch"
        
        # Check for worktrees
        local worktree_dir="$PIPELINE_ROOT/.worktrees"
        if [[ -d "$worktree_dir" ]]; then
            local worktree_count=$(find "$worktree_dir" -maxdepth 1 -type d | wc -l | tr -d ' ')
            worktree_count=$((worktree_count - 1)) # Subtract the parent directory
            log_health "INFO" "$worktree_count active worktrees"
            
            if (( worktree_count > 10 )); then
                log_health "MINOR" "High number of worktrees - consider cleanup"
            fi
        fi
    else
        log_health "CRITICAL" "Not in a git repository or git not accessible"
    fi
}

check_signal_files() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}📡 Signal Files${NC}"
        echo -e "${CYAN}=================${NC}"
    fi
    
    local signals_dir="$PIPELINE_ROOT/.signals"
    if [[ -d "$signals_dir" ]]; then
        local signal_count=$(find "$signals_dir" -name "*.signal" 2>/dev/null | wc -l | tr -d ' ')
        log_health "INFO" "$signal_count active signals"
        
        # Check for old signal files
        local old_signals=$(find "$signals_dir" -name "*.signal" -mmin +60 2>/dev/null | wc -l | tr -d ' ')
        if (( old_signals > 0 )); then
            log_health "MINOR" "$old_signals stale signal files detected"
        fi
        
        # List recent signals if verbose
        if [[ "$VERBOSE" == "true" ]]; then
            while IFS= read -r -d '' signal_file; do
                local signal_name=$(basename "$signal_file" .signal)
                local signal_age=$(get_file_age_human "$signal_file")
                log_health "INFO" "Signal: $signal_name (${signal_age} old)"
            done < <(find "$signals_dir" -name "*.signal" -print0 2>/dev/null)
        fi
    else
        log_health "INFO" "No signals directory found"
    fi
}

check_lock_files() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}🔒 Lock Files${NC}"
        echo -e "${CYAN}===============${NC}"
    fi
    
    # Check for various lock files
    local -a lock_patterns=(
        "$PIPELINE_ROOT/.locks/*.lock"
        "$PIPELINE_ROOT/config/*.lock"
        "$PIPELINE_ROOT/.taskmaster/*.lock"
    )
    
    local total_locks=0
    local stale_locks=0
    
    for pattern in "${lock_patterns[@]}"; do
        for lock_file in $pattern; do
            if [[ -f "$lock_file" ]]; then
                ((total_locks++))
                
                # Check if lock is stale (older than 30 minutes)
                if ! check_file_age "$lock_file" 30; then
                    ((stale_locks++))
                    log_health "MAJOR" "Stale lock file: $(basename "$lock_file") ($(get_file_age_human "$lock_file") old)"
                else
                    log_health "INFO" "Active lock: $(basename "$lock_file")"
                fi
            fi
        done
    done
    
    if (( total_locks == 0 )); then
        log_health "GOOD" "No lock files detected"
    elif (( stale_locks == 0 )); then
        log_health "GOOD" "$total_locks active locks (all recent)"
    fi
}

check_hook_execution() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}🪝 Hook Capability${NC}"
        echo -e "${CYAN}====================${NC}"
    fi
    
    local hooks_dir="$PIPELINE_ROOT/hooks"
    local -a hook_scripts=(
        "skill-activation-prompt.sh"
        "post-tool-use-tracker.sh"
        "pre-implementation-validator.sh"
    )
    
    for script in "${hook_scripts[@]}"; do
        local hook_path="$hooks_dir/$script"
        if [[ -f "$hook_path" && -x "$hook_path" ]]; then
            log_health "GOOD" "Hook executable: $script"
        elif [[ -f "$hook_path" ]]; then
            log_health "MAJOR" "Hook not executable: $script"
        else
            log_health "CRITICAL" "Hook missing: $script"
        fi
    done
}

check_recent_activity() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}📈 Recent Activity${NC}"
        echo -e "${CYAN}====================${NC}"
    fi
    
    local log_dir="$PIPELINE_ROOT/logs"
    if [[ -d "$log_dir" ]]; then
        # Find recent log files (last 24 hours)
        local recent_logs=$(find "$log_dir" -name "*.log" -mtime -1 2>/dev/null | wc -l | tr -d ' ')
        log_health "INFO" "$recent_logs log files from last 24 hours"
        
        # Check latest log file
        local latest_log=$(find "$log_dir" -name "*.log" -type f -exec ls -t {} \; 2>/dev/null | head -n1)
        if [[ -n "$latest_log" ]]; then
            local log_age=$(get_file_age_human "$latest_log")
            log_health "INFO" "Latest log: $(basename "$latest_log") (${log_age} old)"
        fi
        
        # Check log size growth
        local total_log_size=$(du -sh "$log_dir" 2>/dev/null | cut -f1)
        log_health "INFO" "Total log directory size: $total_log_size"
        
        # Warn if logs are getting large
        local log_size_bytes=$(du -s "$log_dir" 2>/dev/null | cut -f1)
        if (( log_size_bytes > 100000 )); then # 100MB in KB
            log_health "MINOR" "Log directory is large - consider cleanup"
        fi
    else
        log_health "MINOR" "Logs directory not found"
    fi
}

show_current_progress() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}🎯 Current Progress${NC}"
        echo -e "${CYAN}=====================${NC}"
    fi
    
    local state_file="$PIPELINE_ROOT/config/workflow-state.json"
    if [[ -f "$state_file" ]]; then
        # Extract progress information
        local current_phase=$(jq -r '.current_phase // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
        local phase_progress=$(jq -r '.phase_progress // 0' "$state_file" 2>/dev/null || echo "0")
        local total_phases=$(jq -r '.total_phases // 6' "$state_file" 2>/dev/null || echo "6")
        local active_skills=$(jq -r '.active_skills // [] | length' "$state_file" 2>/dev/null || echo "0")
        
        log_health "INFO" "Phase: $current_phase"
        log_health "INFO" "Progress: $phase_progress%"
        log_health "INFO" "Total phases: $total_phases"
        log_health "INFO" "Active skills: $active_skills"
        
        # Calculate overall progress
        local overall_progress=0
        if [[ "$current_phase" =~ phase([0-9]+) ]]; then
            local phase_num="${BASH_REMATCH[1]}"
            overall_progress=$(( (phase_num * 100 + phase_progress) / total_phases ))
        fi
        
        log_health "INFO" "Overall progress: ${overall_progress}%"
    else
        log_health "INFO" "No active workflow detected"
    fi
}

show_activity_log() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${CYAN}📋 Recent Activity Log${NC}"
        echo -e "${CYAN}========================${NC}"
    fi
    
    local log_dir="$PIPELINE_ROOT/logs"
    local activity_log="$log_dir/pipeline_activity.log"
    
    if [[ -f "$activity_log" ]]; then
        echo -e "${WHITE}Last 10 entries:${NC}"
        tail -n 10 "$activity_log" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        log_health "INFO" "No activity log found"
    fi
}

generate_json_output() {
    local health_status="healthy"
    
    if (( CRITICAL_ISSUES > 0 )); then
        health_status="critical"
    elif (( MAJOR_ISSUES > 0 )); then
        health_status="major_issues"
    elif (( MINOR_ISSUES > 0 )); then
        health_status="minor_issues"
    fi
    
    # Ensure health score doesn't go below 0
    if (( HEALTH_SCORE < 0 )); then
        HEALTH_SCORE=0
    fi
    
    cat << EOF
{
  "timestamp": "$(get_timestamp)",
  "health_score": $HEALTH_SCORE,
  "status": "$health_status",
  "issues": {
    "critical": $CRITICAL_ISSUES,
    "major": $MAJOR_ISSUES,
    "minor": $MINOR_ISSUES
  },
  "pipeline_root": "$PIPELINE_ROOT",
  "uptime": "$(format_uptime $SECONDS)"
}
EOF
}

show_usage() {
    cat << EOF
Claude Dev Pipeline Health Check

USAGE:
    ./health-check.sh [OPTIONS]

OPTIONS:
    -w, --watch       Continuous monitoring mode (refresh every 5s)
    -i, --interval N  Set refresh interval for watch mode (seconds)
    -v, --verbose     Enable verbose output
    -q, --quiet       Only show critical issues
    -j, --json        Output in JSON format
    -l, --logs        Show recent activity log
    -h, --help        Show this help message

EXAMPLES:
    ./health-check.sh                    # Single health check
    ./health-check.sh --watch            # Continuous monitoring
    ./health-check.sh --watch -i 10      # Monitor every 10 seconds
    ./health-check.sh --json             # JSON output
    ./health-check.sh --logs --verbose   # Show logs with verbose output

EXIT CODES:
    0 - System healthy
    1 - Minor issues detected
    2 - Major issues detected  
    3 - Critical system failure

EOF
}

# =============================================================================
# Main Health Check Logic
# =============================================================================

run_health_checks() {
    # Reset counters
    CRITICAL_ISSUES=0
    MAJOR_ISSUES=0
    MINOR_ISSUES=0
    HEALTH_SCORE=100
    
    # Run all health checks
    check_pipeline_status
    check_worktree_status
    check_signal_files
    check_lock_files
    check_hook_execution
    check_recent_activity
    show_current_progress
    
    if [[ "$SHOW_LOGS" == "true" ]]; then
        show_activity_log
    fi
}

watch_mode() {
    echo -e "${CYAN}👁️  Entering watch mode (refresh every ${REFRESH_INTERVAL}s)${NC}"
    echo -e "${CYAN}Press Ctrl+C to exit${NC}\n"
    
    while true; do
        # Clear screen
        clear
        
        # Show header
        echo -e "${WHITE}Claude Dev Pipeline - Health Monitor${NC}"
        echo -e "${WHITE}====================================${NC}"
        echo -e "Last check: $(get_timestamp)"
        echo -e "Refresh interval: ${REFRESH_INTERVAL}s"
        echo -e "Health score: ${HEALTH_SCORE}/100\n"
        
        # Run health checks
        run_health_checks
        
        # Show summary
        if (( CRITICAL_ISSUES > 0 )); then
            echo -e "\n${RED}🚨 CRITICAL ISSUES DETECTED${NC}"
        elif (( MAJOR_ISSUES > 0 )); then
            echo -e "\n${RED}❌ MAJOR ISSUES DETECTED${NC}"
        elif (( MINOR_ISSUES > 0 )); then
            echo -e "\n${YELLOW}⚠️  MINOR ISSUES DETECTED${NC}"
        else
            echo -e "\n${GREEN}✅ SYSTEM HEALTHY${NC}"
        fi
        
        # Wait for next refresh
        sleep "$REFRESH_INTERVAL"
    done
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--watch)
                WATCH_MODE=true
                shift
                ;;
            -i|--interval)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -l|--logs)
                SHOW_LOGS=true
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
    
    # Validate interval
    if ! [[ "$REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || (( REFRESH_INTERVAL < 1 )); then
        echo "Error: Invalid refresh interval: $REFRESH_INTERVAL" >&2
        exit 3
    fi
    
    if [[ "$WATCH_MODE" == "true" ]]; then
        watch_mode
    else
        if [[ "$JSON_OUTPUT" == "false" ]]; then
            echo -e "${CYAN}🏥 Claude Dev Pipeline Health Check${NC}"
            echo -e "${CYAN}=====================================${NC}"
            echo -e "Pipeline Root: ${BLUE}$PIPELINE_ROOT${NC}"
            echo -e "Check Time: ${BLUE}$(get_timestamp)${NC}"
        fi
        
        run_health_checks
        
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            generate_json_output
        else
            # Show final summary
            echo -e "\n${CYAN}📊 Health Summary${NC}"
            echo -e "${CYAN}==================${NC}"
            echo -e "Health Score: ${HEALTH_SCORE}/100"
            echo -e "Critical Issues: $CRITICAL_ISSUES"
            echo -e "Major Issues: $MAJOR_ISSUES"
            echo -e "Minor Issues: $MINOR_ISSUES"
        fi
        
        # Determine exit code
        if (( CRITICAL_ISSUES > 0 )); then
            exit 3
        elif (( MAJOR_ISSUES > 0 )); then
            exit 2
        elif (( MINOR_ISSUES > 0 )); then
            exit 1
        else
            exit 0
        fi
    fi
}

# Handle interrupt signal for watch mode
trap 'echo -e "\n${CYAN}Health monitoring stopped.${NC}"; exit 0' INT

# Run the main function
main "$@"