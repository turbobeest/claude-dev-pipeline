#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - CLI Dashboard
# =============================================================================
#
# Real-time CLI dashboard for monitoring pipeline status, progress, and health.
# Provides comprehensive visibility into pipeline operations with interactive
# monitoring and detailed status displays.
#
# Features:
# - Real-time pipeline status and progress
# - Phase progression with progress bars
# - Recent activity from logs
# - Health metrics and scores
# - Signal file monitoring
# - Worktree status and active tasks
# - Performance metrics display
# - Watch mode for continuous updates
# - Interactive navigation
#
# Usage:
#   ./pipeline-dashboard.sh [OPTIONS]
#
# Options:
#   --watch, -w          Enable watch mode (auto-refresh)
#   --interval, -i N     Refresh interval in seconds (default: 2)
#   --compact, -c        Compact display mode
#   --json               Output in JSON format
#   --no-color          Disable colored output
#   --help, -h          Show this help message
#
# =============================================================================

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Load dependencies
source "$PROJECT_ROOT/lib/logger.sh" 2>/dev/null || {
    echo "Error: Logger library not found at $PROJECT_ROOT/lib/logger.sh" >&2
    exit 1
}

source "$PROJECT_ROOT/lib/metrics.sh" 2>/dev/null || {
    echo "Error: Metrics library not found at $PROJECT_ROOT/lib/metrics.sh" >&2
    exit 1
}

# =============================================================================
# Configuration
# =============================================================================

# Default settings
WATCH_MODE=false
REFRESH_INTERVAL=2
COMPACT_MODE=false
JSON_OUTPUT=false
NO_COLOR=false

# Dashboard layout
TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERMINAL_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# Colors and formatting
if [[ -t 1 ]] && [[ "$NO_COLOR" != "true" ]]; then
    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
    
    # Special formatting
    CLEAR_SCREEN='\033[2J'
    CURSOR_HOME='\033[H'
    CURSOR_HIDE='\033[?25l'
    CURSOR_SHOW='\033[?25h'
else
    # No color mode
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    GRAY=''
    BOLD=''
    DIM=''
    RESET=''
    CLEAR_SCREEN=''
    CURSOR_HOME=''
    CURSOR_HIDE=''
    CURSOR_SHOW=''
fi

# =============================================================================
# Utility Functions
# =============================================================================

# Show help message
show_help() {
    cat << 'EOF'
Claude Dev Pipeline - CLI Dashboard

USAGE:
    ./pipeline-dashboard.sh [OPTIONS]

OPTIONS:
    --watch, -w          Enable watch mode (auto-refresh every 2 seconds)
    --interval, -i N     Set refresh interval in seconds (default: 2)
    --compact, -c        Use compact display mode
    --json               Output dashboard data in JSON format
    --no-color          Disable colored output
    --help, -h          Show this help message

EXAMPLES:
    ./pipeline-dashboard.sh                    # Single snapshot
    ./pipeline-dashboard.sh --watch            # Live monitoring
    ./pipeline-dashboard.sh -w -i 5            # Watch with 5-second intervals
    ./pipeline-dashboard.sh --compact          # Compact display
    ./pipeline-dashboard.sh --json             # JSON output

INTERACTIVE COMMANDS (in watch mode):
    q, Ctrl+C           Quit
    r                   Refresh now
    c                   Toggle compact mode
    j                   Toggle JSON output
    h                   Show this help

The dashboard displays:
- Pipeline health and overall status
- Current phase and progress
- Recent activity and logs
- Performance metrics
- System resource usage
- Active tasks and worktree status
- Error summary

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --watch|-w)
                WATCH_MODE=true
                shift
                ;;
            --interval|-i)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    REFRESH_INTERVAL="$2"
                    shift 2
                else
                    echo "Error: --interval requires a numeric value" >&2
                    exit 1
                fi
                ;;
            --compact|-c)
                COMPACT_MODE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                echo "Use --help for usage information." >&2
                exit 1
                ;;
        esac
    done
}

# Format timestamp for display
format_timestamp() {
    local timestamp="$1"
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        if command -v gdate >/dev/null 2>&1; then
            gdate -d "$timestamp" '+%H:%M:%S' 2>/dev/null || echo "${timestamp:11:8}"
        else
            echo "${timestamp:11:8}"
        fi
    else
        echo "$timestamp"
    fi
}

# Format duration in human-readable format
format_duration() {
    local seconds="$1"
    local duration=""
    
    if [[ "$seconds" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        local int_seconds=${seconds%.*}
        local hours=$((int_seconds / 3600))
        local minutes=$(((int_seconds % 3600) / 60))
        local secs=$((int_seconds % 60))
        
        if [[ $hours -gt 0 ]]; then
            duration="${hours}h ${minutes}m ${secs}s"
        elif [[ $minutes -gt 0 ]]; then
            duration="${minutes}m ${secs}s"
        else
            duration="${seconds}s"
        fi
    else
        duration="$seconds"
    fi
    
    echo "$duration"
}

# Create progress bar
create_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-20}"
    local char_filled="${4:-█}"
    local char_empty="${5:-░}"
    
    if [[ "$total" -eq 0 ]]; then
        echo "${char_empty}${char_empty}${char_empty}${char_empty}${char_empty}"
        return
    fi
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="$char_filled"
    done
    for ((i=0; i<empty; i++)); do
        bar+="$char_empty"
    done
    
    echo "$bar $percentage%"
}

# Get status color
get_status_color() {
    local status="$1"
    case "$status" in
        "healthy"|"success"|"completed")
            echo "$GREEN"
            ;;
        "warning"|"running"|"in_progress")
            echo "$YELLOW"
            ;;
        "critical"|"error"|"failed"|"failure")
            echo "$RED"
            ;;
        *)
            echo "$GRAY"
            ;;
    esac
}

# =============================================================================
# Data Collection Functions
# =============================================================================

# Get pipeline health status
get_health_status() {
    local health_file="${PROJECT_ROOT}/logs/metrics/health_score.json"
    
    if [[ -f "$health_file" ]]; then
        jq -r '{
            score: .score,
            status: .status,
            last_updated: .last_updated,
            cpu_score: .components.cpu.score // 100,
            cpu_usage: .components.cpu.avg_usage // 0,
            memory_score: .components.memory.score // 100,
            memory_usage: .components.memory.avg_usage // 0
        }' "$health_file" 2>/dev/null || echo '{"score":0,"status":"unknown"}'
    else
        echo '{"score":0,"status":"unknown","last_updated":"","cpu_score":0,"cpu_usage":0,"memory_score":0,"memory_usage":0}'
    fi
}

# Get current phase information
get_current_phase() {
    local metrics_file="${PROJECT_ROOT}/logs/metrics/metrics_data.json"
    
    if [[ -f "$metrics_file" ]]; then
        jq -r '.phases | to_entries[] | select(.value.status == "running") | {
            name: .key,
            start_time: .value.start_time,
            status: .value.status,
            session_id: .value.session_id
        }' "$metrics_file" 2>/dev/null || echo 'null'
    else
        echo 'null'
    fi
}

# Get recent activity from logs
get_recent_activity() {
    local log_file="${PROJECT_ROOT}/logs/pipeline.log"
    local count="${1:-10}"
    
    if [[ -f "$log_file" ]]; then
        tail -"$count" "$log_file" 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^\{ ]]; then
                # JSON format
                echo "$line" | jq -r '"\(.timestamp | .[11:19]) [\(.level)] \(.message)"' 2>/dev/null || echo "$line"
            else
                # Text format
                echo "$line"
            fi
        done
    fi
}

# Get task statistics
get_task_stats() {
    local metrics_file="${PROJECT_ROOT}/logs/metrics/metrics_data.json"
    
    if [[ -f "$metrics_file" ]]; then
        jq -r '.tasks | to_entries[] | {
            name: .key,
            total: .value.total // 0,
            success: .value.success // 0,
            failure: .value.failure // 0,
            success_rate: ((.value.success // 0) * 100 / (.value.total // 1) | floor)
        }' "$metrics_file" 2>/dev/null || echo 'null'
    else
        echo 'null'
    fi
}

# Get error summary
get_error_summary() {
    local metrics_file="${PROJECT_ROOT}/logs/metrics/metrics_data.json"
    
    if [[ -f "$metrics_file" ]]; then
        jq -r '.errors | to_entries[] | {
            type: .key,
            count: .value.count,
            last_message: .value.last_message,
            last_occurrence: .value.last_occurrence
        }' "$metrics_file" 2>/dev/null
    fi
}

# Get worktree status
get_worktree_status() {
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        local branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
        local status=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l)
        local commit=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        
        echo "{\"branch\":\"$branch\",\"modified_files\":$status,\"commit\":\"$commit\"}"
    else
        echo '{"branch":"not_a_repo","modified_files":0,"commit":"unknown"}'
    fi
}

# Get system resource usage
get_system_resources() {
    metrics_collect_system_stats 2>/dev/null | jq -r '{
        cpu_usage: .cpu_usage,
        memory_usage: .memory_usage,
        disk_usage: .disk_usage,
        load_average: .load_average
    }' 2>/dev/null || echo '{"cpu_usage":0,"memory_usage":0,"disk_usage":0,"load_average":"0.0"}'
}

# =============================================================================
# Display Functions
# =============================================================================

# Display header
display_header() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║${WHITE}                    Claude Dev Pipeline - Dashboard                          ${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${GRAY}                           $timestamp                           ${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# Display health status
display_health() {
    local health_data=$(get_health_status)
    local score=$(echo "$health_data" | jq -r '.score')
    local status=$(echo "$health_data" | jq -r '.status')
    local cpu_usage=$(echo "$health_data" | jq -r '.cpu_usage')
    local memory_usage=$(echo "$health_data" | jq -r '.memory_usage')
    
    local status_color=$(get_status_color "$status")
    local health_bar=$(create_progress_bar "$score" 100 20 "█" "░")
    
    echo -e "${BOLD}${WHITE}HEALTH STATUS${RESET}"
    echo -e "${GRAY}─────────────${RESET}"
    echo -e "Overall Health: ${status_color}$status${RESET} (${BOLD}$score/100${RESET})"
    echo -e "Health Bar:     ${status_color}$health_bar${RESET}"
    echo -e "CPU Usage:      $(create_progress_bar "${cpu_usage%.*}" 100 15) ${cpu_usage}%"
    echo -e "Memory Usage:   $(create_progress_bar "${memory_usage%.*}" 100 15) ${memory_usage}%"
    echo
}

# Display current phase
display_current_phase() {
    local phase_data=$(get_current_phase)
    
    echo -e "${BOLD}${WHITE}CURRENT PHASE${RESET}"
    echo -e "${GRAY}─────────────${RESET}"
    
    if [[ "$phase_data" == "null" ]] || [[ -z "$phase_data" ]]; then
        echo -e "${GRAY}No active phase${RESET}"
    else
        local phase_name=$(echo "$phase_data" | jq -r '.name')
        local start_time=$(echo "$phase_data" | jq -r '.start_time')
        local status=$(echo "$phase_data" | jq -r '.status')
        
        local formatted_start_time=$(format_timestamp "$start_time")
        local status_color=$(get_status_color "$status")
        
        # Calculate elapsed time
        local elapsed="unknown"
        if [[ -n "$start_time" ]] && [[ "$start_time" != "null" ]]; then
            if command -v gdate >/dev/null 2>&1; then
                local start_epoch=$(gdate -d "$start_time" +%s 2>/dev/null || echo 0)
                local now_epoch=$(gdate +%s)
                if [[ "$start_epoch" != "0" ]]; then
                    elapsed=$(format_duration $((now_epoch - start_epoch)))
                fi
            fi
        fi
        
        echo -e "Phase:    ${BOLD}$phase_name${RESET}"
        echo -e "Status:   ${status_color}$status${RESET}"
        echo -e "Started:  $formatted_start_time"
        echo -e "Elapsed:  $elapsed"
    fi
    echo
}

# Display recent activity
display_recent_activity() {
    local activity_count=8
    if [[ "$COMPACT_MODE" == "true" ]]; then
        activity_count=5
    fi
    
    echo -e "${BOLD}${WHITE}RECENT ACTIVITY${RESET}"
    echo -e "${GRAY}───────────────${RESET}"
    
    local activity=$(get_recent_activity "$activity_count")
    if [[ -n "$activity" ]]; then
        echo "$activity" | tail -"$activity_count" | while IFS= read -r line; do
            # Colorize log levels
            if [[ "$line" =~ \[ERROR\] ]]; then
                echo -e "${RED}$line${RESET}"
            elif [[ "$line" =~ \[WARN\] ]]; then
                echo -e "${YELLOW}$line${RESET}"
            elif [[ "$line" =~ \[INFO\] ]]; then
                echo -e "${GREEN}$line${RESET}"
            elif [[ "$line" =~ \[DEBUG\] ]]; then
                echo -e "${GRAY}$line${RESET}"
            else
                echo -e "${DIM}$line${RESET}"
            fi
        done
    else
        echo -e "${GRAY}No recent activity${RESET}"
    fi
    echo
}

# Display task statistics
display_task_stats() {
    echo -e "${BOLD}${WHITE}TASK STATISTICS${RESET}"
    echo -e "${GRAY}───────────────${RESET}"
    
    local task_stats=$(get_task_stats)
    if [[ "$task_stats" == "null" ]] || [[ -z "$task_stats" ]]; then
        echo -e "${GRAY}No task data available${RESET}"
    else
        echo "$task_stats" | jq -r '. | "\(.name): \(.success)/\(.total) (\(.success_rate)%)"' | head -5 | while IFS= read -r line; do
            if [[ "$line" =~ \(([0-9]+)%\) ]]; then
                local percentage="${BASH_REMATCH[1]}"
                if [[ "$percentage" -ge 80 ]]; then
                    echo -e "${GREEN}$line${RESET}"
                elif [[ "$percentage" -ge 60 ]]; then
                    echo -e "${YELLOW}$line${RESET}"
                else
                    echo -e "${RED}$line${RESET}"
                fi
            else
                echo -e "${GRAY}$line${RESET}"
            fi
        done
    fi
    echo
}

# Display system resources
display_system_resources() {
    local resources=$(get_system_resources)
    local cpu_usage=$(echo "$resources" | jq -r '.cpu_usage')
    local memory_usage=$(echo "$resources" | jq -r '.memory_usage')
    local disk_usage=$(echo "$resources" | jq -r '.disk_usage')
    local load_avg=$(echo "$resources" | jq -r '.load_average')
    
    echo -e "${BOLD}${WHITE}SYSTEM RESOURCES${RESET}"
    echo -e "${GRAY}────────────────${RESET}"
    echo -e "CPU:     $(create_progress_bar "${cpu_usage%.*}" 100 15) ${cpu_usage}%"
    echo -e "Memory:  $(create_progress_bar "${memory_usage%.*}" 100 15) ${memory_usage}%"
    echo -e "Disk:    $(create_progress_bar "${disk_usage%.*}" 100 15) ${disk_usage}%"
    echo -e "Load:    $load_avg"
    echo
}

# Display worktree status
display_worktree() {
    local worktree=$(get_worktree_status)
    local branch=$(echo "$worktree" | jq -r '.branch')
    local modified=$(echo "$worktree" | jq -r '.modified_files')
    local commit=$(echo "$worktree" | jq -r '.commit')
    
    echo -e "${BOLD}${WHITE}WORKTREE STATUS${RESET}"
    echo -e "${GRAY}───────────────${RESET}"
    echo -e "Branch:   ${CYAN}$branch${RESET}"
    echo -e "Commit:   ${GRAY}$commit${RESET}"
    
    if [[ "$modified" -gt 0 ]]; then
        echo -e "Modified: ${YELLOW}$modified files${RESET}"
    else
        echo -e "Modified: ${GREEN}clean${RESET}"
    fi
    echo
}

# Display error summary
display_errors() {
    echo -e "${BOLD}${WHITE}ERROR SUMMARY${RESET}"
    echo -e "${GRAY}─────────────${RESET}"
    
    local errors=$(get_error_summary)
    if [[ -n "$errors" ]]; then
        echo "$errors" | jq -r '"\(.type): \(.count) (\(.last_occurrence | .[11:19]))"' | head -3 | while IFS= read -r line; do
            echo -e "${RED}$line${RESET}"
        done
    else
        echo -e "${GREEN}No errors recorded${RESET}"
    fi
    echo
}

# Display footer with instructions
display_footer() {
    if [[ "$WATCH_MODE" == "true" ]]; then
        echo -e "${GRAY}Press 'q' to quit, 'r' to refresh, 'c' for compact mode, 'j' for JSON${RESET}"
    fi
}

# =============================================================================
# Main Display Function
# =============================================================================

# Render the complete dashboard
render_dashboard() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # JSON output mode
        local health=$(get_health_status)
        local phase=$(get_current_phase)
        local worktree=$(get_worktree_status)
        local resources=$(get_system_resources)
        local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
        
        jq -n \
            --argjson health "$health" \
            --argjson phase "$phase" \
            --argjson worktree "$worktree" \
            --argjson resources "$resources" \
            --arg timestamp "$timestamp" \
            '{
                timestamp: $timestamp,
                health: $health,
                current_phase: $phase,
                worktree: $worktree,
                resources: $resources
            }'
        return
    fi
    
    # Clear screen in watch mode
    if [[ "$WATCH_MODE" == "true" ]]; then
        echo -e "${CLEAR_SCREEN}${CURSOR_HOME}"
    fi
    
    # Display components
    display_header
    
    if [[ "$COMPACT_MODE" == "true" ]]; then
        # Compact layout (2 columns)
        {
            display_health
            display_current_phase
        } | head -20
        
        {
            display_system_resources
            display_worktree
        } | head -15
    else
        # Full layout
        display_health
        display_current_phase
        display_recent_activity
        display_task_stats
        display_system_resources
        display_worktree
        display_errors
    fi
    
    display_footer
}

# =============================================================================
# Interactive Mode
# =============================================================================

# Handle keyboard input in watch mode
handle_input() {
    local key
    read -t 0.1 -n 1 key 2>/dev/null || return
    
    case "$key" in
        'q'|'Q')
            echo -e "${CURSOR_SHOW}"
            exit 0
            ;;
        'r'|'R')
            render_dashboard
            ;;
        'c'|'C')
            COMPACT_MODE=$([[ "$COMPACT_MODE" == "true" ]] && echo "false" || echo "true")
            render_dashboard
            ;;
        'j'|'J')
            JSON_OUTPUT=$([[ "$JSON_OUTPUT" == "true" ]] && echo "false" || echo "true")
            render_dashboard
            ;;
        'h'|'H')
            show_help
            ;;
    esac
}

# Watch mode loop
run_watch_mode() {
    # Hide cursor
    echo -e "${CURSOR_HIDE}"
    
    # Set up signal handlers
    trap 'echo -e "${CURSOR_SHOW}"; exit 0' INT TERM
    
    while true; do
        render_dashboard
        
        # Wait for refresh interval, checking for input
        local elapsed=0
        while [[ $elapsed -lt $REFRESH_INTERVAL ]]; do
            handle_input
            sleep 0.1
            elapsed=$((elapsed + 1))
        done
    done
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Ensure required directories exist
    mkdir -p "$PROJECT_ROOT/logs/metrics"
    
    # Initialize metrics collection
    metrics_collect_system_stats >/dev/null 2>&1 || true
    metrics_calculate_health_score >/dev/null 2>&1 || true
    
    if [[ "$WATCH_MODE" == "true" ]]; then
        run_watch_mode
    else
        render_dashboard
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi