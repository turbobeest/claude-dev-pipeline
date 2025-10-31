#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Monitoring Alerts System
# =============================================================================
#
# Comprehensive alert system for detecting and notifying about pipeline issues,
# stuck phases, failures, and resource problems. Provides multiple notification
# methods and configurable thresholds.
#
# Features:
# - Stuck phase detection (timeout monitoring)
# - Repeated failure alerts
# - Phase completion notifications
# - Resource usage warnings
# - Terminal notifications (osascript/notify-send)
# - Email notifications (optional)
# - Webhook notifications (optional)
# - Alert escalation and rate limiting
# - Health status monitoring
#
# Usage:
#   source lib/alerts.sh
#   alerts_start_monitoring
#   alerts_check_stuck_phases
#   alerts_notify "error" "Pipeline failed" "task_id=123"
#
# =============================================================================

# Load dependencies
if [[ -f "${PROJECT_ROOT:-}/lib/logger.sh" ]]; then
    source "${PROJECT_ROOT}/lib/logger.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { echo "[DEBUG] $*" >&2; }
fi

if [[ -f "${PROJECT_ROOT:-}/lib/metrics.sh" ]]; then
    source "${PROJECT_ROOT}/lib/metrics.sh"
else
    # Fallback functions
    get_health_status() { echo '{"score":100,"status":"healthy"}'; }
fi

# =============================================================================
# Configuration
# =============================================================================

ALERTS_DIR="${PROJECT_ROOT}/logs/alerts"
ALERTS_CONFIG_FILE="${ALERTS_DIR}/alerts_config.json"
ALERTS_STATE_FILE="${ALERTS_DIR}/alerts_state.json"
ALERTS_LOG_FILE="${ALERTS_DIR}/alerts.log"

# Default alert thresholds
PHASE_TIMEOUT_WARN=300      # 5 minutes
PHASE_TIMEOUT_CRITICAL=900  # 15 minutes
FAILURE_THRESHOLD=3         # Alert after 3 consecutive failures
CPU_THRESHOLD_WARN=80       # 80% CPU usage
MEMORY_THRESHOLD_WARN=85    # 85% memory usage
DISK_THRESHOLD_WARN=90      # 90% disk usage
HEALTH_SCORE_WARN=70        # Health score below 70
HEALTH_SCORE_CRITICAL=40    # Health score below 40

# Rate limiting (seconds between similar alerts)
ALERT_RATE_LIMIT=300        # 5 minutes

# Notification methods
ENABLE_TERMINAL_NOTIFICATIONS=true
ENABLE_EMAIL_NOTIFICATIONS=false
ENABLE_WEBHOOK_NOTIFICATIONS=false

# =============================================================================
# Initialization
# =============================================================================

init_alerts() {
    # Create alerts directory
    mkdir -p "$ALERTS_DIR"
    
    # Initialize configuration file
    if [[ ! -f "$ALERTS_CONFIG_FILE" ]]; then
        cat > "$ALERTS_CONFIG_FILE" << EOF
{
    "thresholds": {
        "phase_timeout_warn": $PHASE_TIMEOUT_WARN,
        "phase_timeout_critical": $PHASE_TIMEOUT_CRITICAL,
        "failure_threshold": $FAILURE_THRESHOLD,
        "cpu_warn": $CPU_THRESHOLD_WARN,
        "memory_warn": $MEMORY_THRESHOLD_WARN,
        "disk_warn": $DISK_THRESHOLD_WARN,
        "health_score_warn": $HEALTH_SCORE_WARN,
        "health_score_critical": $HEALTH_SCORE_CRITICAL
    },
    "notifications": {
        "terminal": $ENABLE_TERMINAL_NOTIFICATIONS,
        "email": $ENABLE_EMAIL_NOTIFICATIONS,
        "webhook": $ENABLE_WEBHOOK_NOTIFICATIONS
    },
    "rate_limit": $ALERT_RATE_LIMIT,
    "email": {
        "smtp_server": "",
        "smtp_port": 587,
        "username": "",
        "password": "",
        "from": "claude-pipeline@localhost",
        "to": []
    },
    "webhook": {
        "url": "",
        "headers": {},
        "retry_attempts": 3
    }
}
EOF
    fi
    
    # Initialize state file
    if [[ ! -f "$ALERTS_STATE_FILE" ]]; then
        echo '{"last_alerts":{},"failure_counts":{},"monitoring":false}' > "$ALERTS_STATE_FILE"
    fi
    
    # Initialize log file
    touch "$ALERTS_LOG_FILE"
    
    log_info "Alerts system initialized" "alerts_dir=$ALERTS_DIR"
}

# =============================================================================
# Alert State Management
# =============================================================================

# Get alert configuration
get_alert_config() {
    if [[ -f "$ALERTS_CONFIG_FILE" ]]; then
        cat "$ALERTS_CONFIG_FILE"
    else
        echo '{}'
    fi
}

# Get alert state
get_alert_state() {
    if [[ -f "$ALERTS_STATE_FILE" ]]; then
        cat "$ALERTS_STATE_FILE"
    else
        echo '{"last_alerts":{},"failure_counts":{},"monitoring":false}'
    fi
}

# Update alert state
update_alert_state() {
    local key="$1"
    local value="$2"
    
    local current_state=$(get_alert_state)
    echo "$current_state" | jq --arg key "$key" --arg value "$value" \
        '.[$key] = $value' > "$ALERTS_STATE_FILE"
}

# Check if alert should be sent (rate limiting)
should_send_alert() {
    local alert_type="$1"
    local current_time=$(date +%s)
    local rate_limit=$(get_alert_config | jq -r '.rate_limit // 300')
    
    local last_alert_time=$(get_alert_state | jq -r ".last_alerts[\"$alert_type\"] // 0")
    
    if [[ $((current_time - last_alert_time)) -gt $rate_limit ]]; then
        # Update last alert time
        local current_state=$(get_alert_state)
        echo "$current_state" | jq --arg type "$alert_type" --argjson time "$current_time" \
            '.last_alerts[$type] = $time' > "$ALERTS_STATE_FILE"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Notification Methods
# =============================================================================

# Send terminal notification
send_terminal_notification() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    # Log the alert
    echo "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ') [$severity] $title: $message" >> "$ALERTS_LOG_FILE"
    log_warn "Alert: $title" "severity=$severity" "message=$message"
    
    # Try macOS notification
    if command -v osascript >/dev/null 2>&1; then
        osascript -e "display notification \"$message\" with title \"Claude Pipeline Alert\" subtitle \"$title\"" 2>/dev/null || true
    fi
    
    # Try Linux notification
    if command -v notify-send >/dev/null 2>&1; then
        local urgency="normal"
        case "$severity" in
            "critical"|"error") urgency="critical" ;;
            "warning") urgency="normal" ;;
            *) urgency="low" ;;
        esac
        notify-send --urgency="$urgency" "Claude Pipeline Alert: $title" "$message" 2>/dev/null || true
    fi
    
    # Console notification (always available)
    local color=""
    case "$severity" in
        "critical"|"error") color='\033[1;31m' ;;  # Bold red
        "warning") color='\033[1;33m' ;;           # Bold yellow
        "info") color='\033[1;36m' ;;              # Bold cyan
        *) color='\033[1;37m' ;;                   # Bold white
    esac
    
    echo -e "${color}🚨 ALERT [$severity]: $title${color}\n   $message\033[0m" >&2
}

# Send email notification
send_email_notification() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    local config=$(get_alert_config)
    local email_enabled=$(echo "$config" | jq -r '.notifications.email // false')
    
    if [[ "$email_enabled" != "true" ]]; then
        return 0
    fi
    
    # Extract email configuration
    local smtp_server=$(echo "$config" | jq -r '.email.smtp_server // ""')
    local smtp_port=$(echo "$config" | jq -r '.email.smtp_port // 587')
    local username=$(echo "$config" | jq -r '.email.username // ""')
    local password=$(echo "$config" | jq -r '.email.password // ""')
    local from=$(echo "$config" | jq -r '.email.from // "claude-pipeline@localhost"')
    local to_addresses=$(echo "$config" | jq -r '.email.to[]? // empty' | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$smtp_server" ]] || [[ -z "$to_addresses" ]]; then
        log_debug "Email notification skipped - incomplete configuration"
        return 0
    fi
    
    # Create email content
    local email_content="Subject: Claude Pipeline Alert: $title
From: $from
To: $to_addresses

Claude Dev Pipeline Alert

Severity: $severity
Title: $title
Time: $(date)
Message: $message

---
Claude Dev Pipeline Monitoring System
"
    
    # Try to send email using available tools
    if command -v sendmail >/dev/null 2>&1; then
        echo "$email_content" | sendmail "$to_addresses" 2>/dev/null || \
            log_warn "Failed to send email notification" "to=$to_addresses"
    elif command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "Claude Pipeline Alert: $title" "$to_addresses" 2>/dev/null || \
            log_warn "Failed to send email notification" "to=$to_addresses"
    else
        log_debug "Email notification skipped - no mail command available"
    fi
}

# Send webhook notification
send_webhook_notification() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    local config=$(get_alert_config)
    local webhook_enabled=$(echo "$config" | jq -r '.notifications.webhook // false')
    
    if [[ "$webhook_enabled" != "true" ]]; then
        return 0
    fi
    
    local webhook_url=$(echo "$config" | jq -r '.webhook.url // ""')
    local retry_attempts=$(echo "$config" | jq -r '.webhook.retry_attempts // 3')
    
    if [[ -z "$webhook_url" ]]; then
        log_debug "Webhook notification skipped - no URL configured"
        return 0
    fi
    
    # Create webhook payload
    local payload=$(jq -n \
        --arg severity "$severity" \
        --arg title "$title" \
        --arg message "$message" \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" \
        --arg source "claude-dev-pipeline" \
        '{
            severity: $severity,
            title: $title,
            message: $message,
            timestamp: $timestamp,
            source: $source
        }')
    
    # Send webhook with retries
    local attempt=1
    while [[ $attempt -le $retry_attempts ]]; do
        if curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$webhook_url" >/dev/null 2>&1; then
            log_debug "Webhook notification sent" "url=$webhook_url" "attempt=$attempt"
            return 0
        else
            log_warn "Webhook notification failed" "url=$webhook_url" "attempt=$attempt"
            ((attempt++))
            sleep 2
        fi
    done
    
    return 1
}

# =============================================================================
# Alert Functions
# =============================================================================

# Send alert using all enabled notification methods
alerts_notify() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    local alert_type="${title// /_}"
    alert_type=$(echo "$alert_type" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
    
    # Check rate limiting
    if ! should_send_alert "$alert_type"; then
        log_debug "Alert rate limited" "type=$alert_type"
        return 0
    fi
    
    local config=$(get_alert_config)
    
    # Send terminal notification
    if [[ "$(echo "$config" | jq -r '.notifications.terminal // true')" == "true" ]]; then
        send_terminal_notification "$severity" "$title" "$message"
    fi
    
    # Send email notification
    send_email_notification "$severity" "$title" "$message"
    
    # Send webhook notification
    send_webhook_notification "$severity" "$title" "$message"
    
    log_info "Alert sent" "severity=$severity" "title=$title" "type=$alert_type"
}

# Check for stuck phases
alerts_check_stuck_phases() {
    local metrics_file="${PROJECT_ROOT}/logs/metrics/metrics_data.json"
    
    if [[ ! -f "$metrics_file" ]]; then
        return 0
    fi
    
    local config=$(get_alert_config)
    local warn_threshold=$(echo "$config" | jq -r '.thresholds.phase_timeout_warn // 300')
    local critical_threshold=$(echo "$config" | jq -r '.thresholds.phase_timeout_critical // 900')
    
    # Get running phases
    local running_phases=$(jq -r '.phases | to_entries[] | select(.value.status == "running") | "\(.key)|\(.value.start_time)"' "$metrics_file" 2>/dev/null || echo "")
    
    if [[ -z "$running_phases" ]]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    
    while IFS='|' read -r phase_name start_time; do
        if [[ -z "$phase_name" ]] || [[ -z "$start_time" ]] || [[ "$start_time" == "null" ]]; then
            continue
        fi
        
        # Calculate phase duration
        local phase_duration=0
        if command -v gdate >/dev/null 2>&1; then
            local start_epoch=$(gdate -d "$start_time" +%s 2>/dev/null || echo 0)
            if [[ "$start_epoch" != "0" ]]; then
                phase_duration=$((current_time - start_epoch))
            fi
        fi
        
        # Check thresholds
        if [[ $phase_duration -gt $critical_threshold ]]; then
            alerts_notify "critical" "Phase Stuck (Critical)" \
                "Phase '$phase_name' has been running for ${phase_duration}s (>${critical_threshold}s threshold)"
        elif [[ $phase_duration -gt $warn_threshold ]]; then
            alerts_notify "warning" "Phase Running Long" \
                "Phase '$phase_name' has been running for ${phase_duration}s (>${warn_threshold}s threshold)"
        fi
        
    done <<< "$running_phases"
}

# Check for repeated failures
alerts_check_repeated_failures() {
    local metrics_file="${PROJECT_ROOT}/logs/metrics/metrics_data.json"
    
    if [[ ! -f "$metrics_file" ]]; then
        return 0
    fi
    
    local config=$(get_alert_config)
    local failure_threshold=$(echo "$config" | jq -r '.thresholds.failure_threshold // 3')
    
    # Get error counts
    local errors=$(jq -r '.errors | to_entries[] | "\(.key)|\(.value.count)"' "$metrics_file" 2>/dev/null || echo "")
    
    if [[ -z "$errors" ]]; then
        return 0
    fi
    
    while IFS='|' read -r error_type error_count; do
        if [[ -z "$error_type" ]] || [[ -z "$error_count" ]]; then
            continue
        fi
        
        if [[ $error_count -ge $failure_threshold ]]; then
            alerts_notify "error" "Repeated Failures" \
                "Error type '$error_type' has occurred $error_count times (>=$failure_threshold threshold)"
        fi
        
    done <<< "$errors"
}

# Check resource usage
alerts_check_resource_usage() {
    local config=$(get_alert_config)
    local cpu_threshold=$(echo "$config" | jq -r '.thresholds.cpu_warn // 80')
    local memory_threshold=$(echo "$config" | jq -r '.thresholds.memory_warn // 85')
    local disk_threshold=$(echo "$config" | jq -r '.thresholds.disk_warn // 90')
    
    # Get current system stats
    local stats=$(metrics_collect_system_stats 2>/dev/null || echo '{"cpu_usage":0,"memory_usage":0,"disk_usage":0}')
    
    local cpu_usage=$(echo "$stats" | jq -r '.cpu_usage // 0')
    local memory_usage=$(echo "$stats" | jq -r '.memory_usage // 0')
    local disk_usage=$(echo "$stats" | jq -r '.disk_usage // 0')
    
    # Check CPU usage
    if (( $(echo "$cpu_usage > $cpu_threshold" | bc -l 2>/dev/null || echo 0) )); then
        alerts_notify "warning" "High CPU Usage" \
            "CPU usage is ${cpu_usage}% (>${cpu_threshold}% threshold)"
    fi
    
    # Check memory usage
    if (( $(echo "$memory_usage > $memory_threshold" | bc -l 2>/dev/null || echo 0) )); then
        alerts_notify "warning" "High Memory Usage" \
            "Memory usage is ${memory_usage}% (>${memory_threshold}% threshold)"
    fi
    
    # Check disk usage
    if (( $(echo "$disk_usage > $disk_threshold" | bc -l 2>/dev/null || echo 0) )); then
        alerts_notify "warning" "High Disk Usage" \
            "Disk usage is ${disk_usage}% (>${disk_threshold}% threshold)"
    fi
}

# Check health score
alerts_check_health_score() {
    local config=$(get_alert_config)
    local warn_threshold=$(echo "$config" | jq -r '.thresholds.health_score_warn // 70')
    local critical_threshold=$(echo "$config" | jq -r '.thresholds.health_score_critical // 40')
    
    local health=$(get_health_status 2>/dev/null || echo '{"score":100,"status":"unknown"}')
    local score=$(echo "$health" | jq -r '.score // 100')
    local status=$(echo "$health" | jq -r '.status // "unknown"')
    
    if [[ $score -lt $critical_threshold ]]; then
        alerts_notify "critical" "Critical Health Score" \
            "Pipeline health score is $score (<$critical_threshold threshold). Status: $status"
    elif [[ $score -lt $warn_threshold ]]; then
        alerts_notify "warning" "Low Health Score" \
            "Pipeline health score is $score (<$warn_threshold threshold). Status: $status"
    fi
}

# Notify phase completion
alerts_notify_phase_completion() {
    local phase_name="$1"
    local status="$2"
    local duration="${3:-unknown}"
    
    case "$status" in
        "success")
            alerts_notify "info" "Phase Completed" \
                "Phase '$phase_name' completed successfully in ${duration}s"
            ;;
        "failure")
            alerts_notify "error" "Phase Failed" \
                "Phase '$phase_name' failed after ${duration}s"
            ;;
        "timeout")
            alerts_notify "critical" "Phase Timeout" \
                "Phase '$phase_name' timed out after ${duration}s"
            ;;
    esac
}

# =============================================================================
# Monitoring Loop
# =============================================================================

# Start background monitoring
alerts_start_monitoring() {
    local monitor_interval="${1:-60}"  # Default 60 seconds
    local monitor_pid_file="${ALERTS_DIR}/monitor.pid"
    
    # Check if already running
    if [[ -f "$monitor_pid_file" ]]; then
        local existing_pid=$(cat "$monitor_pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_info "Alerts monitoring already running" "pid=$existing_pid"
            return 0
        fi
    fi
    
    # Mark monitoring as active
    update_alert_state "monitoring" "true"
    
    # Start background monitoring
    (
        while true; do
            # Check if monitoring should continue
            local monitoring_state=$(get_alert_state | jq -r '.monitoring // false')
            if [[ "$monitoring_state" != "true" ]]; then
                break
            fi
            
            # Run all checks
            alerts_check_stuck_phases
            alerts_check_repeated_failures
            alerts_check_resource_usage
            alerts_check_health_score
            
            sleep "$monitor_interval"
        done
        
        # Clean up
        rm -f "$monitor_pid_file"
    ) &
    
    local monitor_pid=$!
    echo "$monitor_pid" > "$monitor_pid_file"
    
    log_info "Alerts monitoring started" "pid=$monitor_pid" "interval=${monitor_interval}s"
    alerts_notify "info" "Monitoring Started" "Alert monitoring is now active (interval: ${monitor_interval}s)"
}

# Stop background monitoring
alerts_stop_monitoring() {
    local monitor_pid_file="${ALERTS_DIR}/monitor.pid"
    
    # Mark monitoring as inactive
    update_alert_state "monitoring" "false"
    
    if [[ -f "$monitor_pid_file" ]]; then
        local monitor_pid=$(cat "$monitor_pid_file")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid"
            rm -f "$monitor_pid_file"
            log_info "Alerts monitoring stopped" "pid=$monitor_pid"
            alerts_notify "info" "Monitoring Stopped" "Alert monitoring has been stopped"
        else
            rm -f "$monitor_pid_file"
            log_info "Alerts monitoring was not running"
        fi
    else
        log_info "Alerts monitoring was not running"
    fi
}

# Check monitoring status
alerts_monitoring_status() {
    local monitor_pid_file="${ALERTS_DIR}/monitor.pid"
    local monitoring_state=$(get_alert_state | jq -r '.monitoring // false')
    
    if [[ -f "$monitor_pid_file" ]] && [[ "$monitoring_state" == "true" ]]; then
        local monitor_pid=$(cat "$monitor_pid_file")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            echo "running"
            return 0
        fi
    fi
    
    echo "stopped"
    return 1
}

# =============================================================================
# Utility Functions
# =============================================================================

# Show alerts configuration
alerts_show_config() {
    echo "Alerts Configuration:"
    echo "===================="
    get_alert_config | jq .
}

# Test alerts system
alerts_test() {
    local test_type="${1:-all}"
    
    case "$test_type" in
        "terminal"|"all")
            alerts_notify "info" "Test Alert" "This is a test alert from the Claude Dev Pipeline monitoring system"
            ;;
        "email")
            send_email_notification "info" "Test Email Alert" "This is a test email alert"
            ;;
        "webhook")
            send_webhook_notification "info" "Test Webhook Alert" "This is a test webhook alert"
            ;;
        *)
            echo "Usage: alerts_test [terminal|email|webhook|all]"
            return 1
            ;;
    esac
    
    log_info "Alert test completed" "type=$test_type"
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if not already done
if [[ "${ALERTS_INITIALIZED:-}" != "true" ]]; then
    init_alerts
    export ALERTS_INITIALIZED=true
fi