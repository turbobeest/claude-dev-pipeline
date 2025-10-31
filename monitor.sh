#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Monitoring Control Script
# =============================================================================
#
# Central control script for managing pipeline monitoring, logging, and alerts.
# Provides a unified interface for starting/stopping monitoring components.
#
# Usage:
#   ./monitor.sh [COMMAND] [OPTIONS]
#
# Commands:
#   start                Start all monitoring components
#   stop                 Stop all monitoring components
#   status               Show monitoring status
#   dashboard            Launch interactive dashboard
#   alerts               Manage alerts system
#   logs                 View logs
#   metrics              Show metrics
#   test                 Test monitoring systems
#   help                 Show this help message
#
# Options:
#   --interval N         Set monitoring interval (default: 30 seconds)
#   --dashboard-interval N  Set dashboard refresh interval (default: 2 seconds)
#   --verbose           Enable verbose output
#   --quiet             Minimize output
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Load dependencies
source "$PROJECT_ROOT/lib/logger.sh" || {
    echo "Error: Logger library not found" >&2
    exit 1
}

source "$PROJECT_ROOT/lib/metrics.sh" || {
    echo "Error: Metrics library not found" >&2
    exit 1
}

source "$PROJECT_ROOT/lib/alerts.sh" || {
    echo "Error: Alerts library not found" >&2
    exit 1
}

# Set logging context
set_log_context --phase "monitoring" --task "control"

# =============================================================================
# Configuration
# =============================================================================

MONITORING_INTERVAL=30
DASHBOARD_INTERVAL=2
VERBOSE=false
QUIET=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Utility Functions
# =============================================================================

show_help() {
    cat << 'EOF'
Claude Dev Pipeline - Monitoring Control

USAGE:
    ./monitor.sh [COMMAND] [OPTIONS]

COMMANDS:
    start                Start all monitoring components
    stop                 Stop all monitoring components  
    status               Show status of all monitoring components
    dashboard            Launch interactive dashboard
    alerts               Manage alerts system
    logs                 View and manage logs
    metrics              Show metrics and generate reports
    test                 Test monitoring systems
    help                 Show this help message

ALERT SUBCOMMANDS:
    alerts start         Start alerts monitoring
    alerts stop          Stop alerts monitoring
    alerts status        Show alerts status
    alerts test          Test alert notifications
    alerts config        Show alerts configuration

LOG SUBCOMMANDS:
    logs tail            Tail the main pipeline log
    logs error           Show recent errors
    logs metrics         Show metrics log
    logs alerts          Show alerts log

METRICS SUBCOMMANDS:
    metrics report       Generate performance report
    metrics export       Export metrics to JSON
    metrics health       Show health score
    metrics cleanup      Clean old metrics data

OPTIONS:
    --interval N         Set monitoring interval in seconds (default: 30)
    --dashboard-interval N  Set dashboard refresh interval (default: 2)
    --verbose           Enable verbose output
    --quiet             Minimize output

EXAMPLES:
    ./monitor.sh start                    # Start all monitoring
    ./monitor.sh dashboard --watch        # Launch dashboard in watch mode
    ./monitor.sh alerts test              # Test alert notifications
    ./monitor.sh metrics report           # Generate performance report
    ./monitor.sh logs tail                # Tail pipeline logs

EOF
}

# Parse command line arguments
parse_args() {
    COMMAND=""
    SUBCOMMAND=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            start|stop|status|dashboard|alerts|logs|metrics|test|help)
                if [[ -z "$COMMAND" ]]; then
                    COMMAND="$1"
                else
                    SUBCOMMAND="$1"
                fi
                shift
                ;;
            --interval)
                MONITORING_INTERVAL="$2"
                shift 2
                ;;
            --dashboard-interval)
                DASHBOARD_INTERVAL="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                set_log_level "DEBUG"
                shift
                ;;
            --quiet)
                QUIET=true
                set_log_level "ERROR"
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use 'help' for usage information." >&2
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$COMMAND" ]]; then
        COMMAND="help"
    fi
}

# Status checking functions
check_metrics_monitoring() {
    local monitor_pid_file="${PROJECT_ROOT}/logs/metrics/monitor.pid"
    if [[ -f "$monitor_pid_file" ]]; then
        local pid=$(cat "$monitor_pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "running (PID: $pid)"
            return 0
        fi
    fi
    echo "stopped"
    return 1
}

check_alerts_monitoring() {
    if alerts_monitoring_status >/dev/null 2>&1; then
        local monitor_pid_file="${PROJECT_ROOT}/logs/alerts/monitor.pid"
        if [[ -f "$monitor_pid_file" ]]; then
            local pid=$(cat "$monitor_pid_file")
            echo "running (PID: $pid)"
        else
            echo "running"
        fi
        return 0
    else
        echo "stopped"
        return 1
    fi
}

# =============================================================================
# Command Implementations
# =============================================================================

cmd_start() {
    echo -e "${CYAN}Starting Claude Dev Pipeline Monitoring...${NC}"
    
    # Start metrics monitoring
    echo -n "Starting metrics monitoring... "
    metrics_start_monitoring "$MONITORING_INTERVAL"
    echo -e "${GREEN}✓${NC}"
    
    # Start alerts monitoring
    echo -n "Starting alerts monitoring... "
    alerts_start_monitoring "$MONITORING_INTERVAL"
    echo -e "${GREEN}✓${NC}"
    
    echo -e "${GREEN}✅ All monitoring components started${NC}"
    echo -e "   Metrics interval: ${MONITORING_INTERVAL}s"
    echo -e "   Use './monitor.sh status' to check status"
    echo -e "   Use './monitor.sh dashboard' to view dashboard"
    
    log_info "Monitoring started" "metrics_interval=$MONITORING_INTERVAL" "alerts_interval=$MONITORING_INTERVAL"
}

cmd_stop() {
    echo -e "${CYAN}Stopping Claude Dev Pipeline Monitoring...${NC}"
    
    # Stop metrics monitoring
    echo -n "Stopping metrics monitoring... "
    metrics_stop_monitoring
    echo -e "${GREEN}✓${NC}"
    
    # Stop alerts monitoring
    echo -n "Stopping alerts monitoring... "
    alerts_stop_monitoring
    echo -e "${GREEN}✓${NC}"
    
    echo -e "${GREEN}✅ All monitoring components stopped${NC}"
    
    log_info "Monitoring stopped"
}

cmd_status() {
    echo -e "${BOLD}Claude Dev Pipeline Monitoring Status${NC}"
    echo -e "${CYAN}================================${NC}"
    
    # Metrics monitoring status
    echo -n "Metrics Monitoring: "
    if check_metrics_monitoring >/dev/null 2>&1; then
        echo -e "${GREEN}$(check_metrics_monitoring)${NC}"
    else
        echo -e "${RED}$(check_metrics_monitoring)${NC}"
    fi
    
    # Alerts monitoring status
    echo -n "Alerts Monitoring:  "
    if check_alerts_monitoring >/dev/null 2>&1; then
        echo -e "${GREEN}$(check_alerts_monitoring)${NC}"
    else
        echo -e "${RED}$(check_alerts_monitoring)${NC}"
    fi
    
    # Health status
    echo -n "Pipeline Health:    "
    local health=$(get_health_status 2>/dev/null || echo '{"score":0,"status":"unknown"}')
    local score=$(echo "$health" | jq -r '.score // 0')
    local status=$(echo "$health" | jq -r '.status // "unknown"')
    
    case "$status" in
        "healthy") echo -e "${GREEN}$status ($score/100)${NC}" ;;
        "warning") echo -e "${YELLOW}$status ($score/100)${NC}" ;;
        "critical") echo -e "${RED}$status ($score/100)${NC}" ;;
        *) echo -e "${CYAN}$status ($score/100)${NC}" ;;
    esac
    
    # Recent activity
    echo
    echo -e "${BOLD}Recent Activity:${NC}"
    if [[ -f "$PROJECT_ROOT/logs/pipeline.log" ]]; then
        tail -5 "$PROJECT_ROOT/logs/pipeline.log" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo "  No recent activity"
    fi
}

cmd_dashboard() {
    if [[ "$SUBCOMMAND" == "watch" ]] || [[ "$1" == "--watch" ]] 2>/dev/null; then
        "$PROJECT_ROOT/pipeline-dashboard.sh" --watch --interval "$DASHBOARD_INTERVAL"
    else
        "$PROJECT_ROOT/pipeline-dashboard.sh" "$@"
    fi
}

cmd_alerts() {
    case "$SUBCOMMAND" in
        "start")
            alerts_start_monitoring "$MONITORING_INTERVAL"
            echo -e "${GREEN}✅ Alerts monitoring started${NC}"
            ;;
        "stop")
            alerts_stop_monitoring
            echo -e "${GREEN}✅ Alerts monitoring stopped${NC}"
            ;;
        "status")
            echo -n "Alerts monitoring: "
            if check_alerts_monitoring >/dev/null 2>&1; then
                echo -e "${GREEN}$(check_alerts_monitoring)${NC}"
            else
                echo -e "${RED}$(check_alerts_monitoring)${NC}"
            fi
            ;;
        "test")
            echo "Testing alert notifications..."
            alerts_test
            echo -e "${GREEN}✅ Alert test completed${NC}"
            ;;
        "config")
            alerts_show_config
            ;;
        *)
            echo "Usage: $0 alerts [start|stop|status|test|config]"
            exit 1
            ;;
    esac
}

cmd_logs() {
    case "$SUBCOMMAND" in
        "tail")
            if [[ -f "$PROJECT_ROOT/logs/pipeline.log" ]]; then
                tail -f "$PROJECT_ROOT/logs/pipeline.log"
            else
                echo "No pipeline log found"
                exit 1
            fi
            ;;
        "error")
            if [[ -f "$PROJECT_ROOT/logs/error.log" ]]; then
                tail -20 "$PROJECT_ROOT/logs/error.log"
            else
                echo "No error log found"
            fi
            ;;
        "metrics")
            if [[ -f "$PROJECT_ROOT/logs/metrics.log" ]]; then
                tail -20 "$PROJECT_ROOT/logs/metrics.log"
            else
                echo "No metrics log found"
            fi
            ;;
        "alerts")
            if [[ -f "$PROJECT_ROOT/logs/alerts/alerts.log" ]]; then
                tail -20 "$PROJECT_ROOT/logs/alerts/alerts.log"
            else
                echo "No alerts log found"
            fi
            ;;
        *)
            echo "Usage: $0 logs [tail|error|metrics|alerts]"
            exit 1
            ;;
    esac
}

cmd_metrics() {
    case "$SUBCOMMAND" in
        "report")
            echo "Generating performance report..."
            local report_file=$(metrics_generate_report text)
            echo -e "${GREEN}✅ Report generated: $report_file${NC}"
            if [[ "$VERBOSE" == "true" ]]; then
                cat "$report_file"
            fi
            ;;
        "export")
            echo "Exporting metrics..."
            local export_file=$(metrics_export_json)
            echo -e "${GREEN}✅ Metrics exported: $export_file${NC}"
            ;;
        "health")
            local health=$(get_health_status)
            echo "Pipeline Health Status:"
            echo "$health" | jq .
            ;;
        "cleanup")
            echo "Cleaning up old metrics data..."
            metrics_cleanup
            echo -e "${GREEN}✅ Metrics cleanup completed${NC}"
            ;;
        *)
            echo "Usage: $0 metrics [report|export|health|cleanup]"
            exit 1
            ;;
    esac
}

cmd_test() {
    echo -e "${CYAN}Testing monitoring systems...${NC}"
    
    # Test logger
    echo -n "Testing logger... "
    log_info "Test log message"
    echo -e "${GREEN}✓${NC}"
    
    # Test metrics
    echo -n "Testing metrics... "
    start_timer "test_timer"
    sleep 1
    stop_timer "test_timer"
    echo -e "${GREEN}✓${NC}"
    
    # Test alerts
    echo -n "Testing alerts... "
    alerts_test terminal
    echo -e "${GREEN}✓${NC}"
    
    # Test dashboard
    echo -n "Testing dashboard... "
    "$PROJECT_ROOT/pipeline-dashboard.sh" --json >/dev/null
    echo -e "${GREEN}✓${NC}"
    
    echo -e "${GREEN}✅ All tests completed${NC}"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    parse_args "$@"
    
    # Ensure required directories exist
    mkdir -p "$PROJECT_ROOT/logs/metrics" "$PROJECT_ROOT/logs/alerts"
    
    case "$COMMAND" in
        "start")
            cmd_start
            ;;
        "stop")
            cmd_stop
            ;;
        "status")
            cmd_status
            ;;
        "dashboard")
            shift  # Remove 'dashboard' from args
            cmd_dashboard "$@"
            ;;
        "alerts")
            cmd_alerts
            ;;
        "logs")
            cmd_logs
            ;;
        "metrics")
            cmd_metrics
            ;;
        "test")
            cmd_test
            ;;
        "help")
            show_help
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Use 'help' for usage information." >&2
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi