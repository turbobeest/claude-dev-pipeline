#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Comprehensive Logging System
# =============================================================================
#
# Structured logging system with JSON format, log rotation, and performance metrics.
# Supports multiple log levels, context injection, and both file and console output.
#
# Features:
# - Structured JSON logging
# - Log levels: DEBUG, INFO, WARN, ERROR, FATAL
# - Log rotation (max 10MB, keep 30 days)
# - Performance metrics logging
# - Context injection (timestamp, caller, phase, task)
# - File and console output
# - Color-coded console output
#
# Usage:
#   source lib/logger.sh
#   log_info "Pipeline started"
#   log_error "Failed to process task" "task_id=123"
#   log_metric "phase_duration" 45.2 "phase=validation"
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# =============================================================================
# Configuration
# =============================================================================

# Log levels (numeric for comparison)
get_log_level_num() {
    case "$1" in
        DEBUG) echo 10 ;;
        INFO) echo 20 ;;
        WARN) echo 30 ;;
        ERROR) echo 40 ;;
        FATAL) echo 50 ;;
        *) echo 20 ;;
    esac
}

# Default configuration
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/pipeline.log"
ERROR_LOG_FILE="${LOG_DIR}/error.log"
METRICS_LOG_FILE="${LOG_DIR}/metrics.log"
CURRENT_LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FORMAT="${LOG_FORMAT:-JSON}"  # JSON or TEXT
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"
MAX_LOG_SIZE_MB=10
LOG_RETENTION_DAYS=30

# Color codes for console output
get_log_color() {
    case "$1" in
        DEBUG) echo '\033[0;36m' ;;    # Cyan
        INFO) echo '\033[0;32m' ;;     # Green
        WARN) echo '\033[0;33m' ;;     # Yellow
        ERROR) echo '\033[0;31m' ;;    # Red
        FATAL) echo '\033[1;31m' ;;    # Bold Red
        RESET) echo '\033[0m' ;;       # Reset
        BOLD) echo '\033[1m' ;;        # Bold
        DIM) echo '\033[2m' ;;         # Dim
        *) echo '\033[0m' ;;
    esac
}

# Context variables
LOGGER_CONTEXT_PHASE="${PIPELINE_PHASE:-unknown}"
LOGGER_CONTEXT_TASK="${CURRENT_TASK:-unknown}"
LOGGER_CONTEXT_SESSION_ID="${SESSION_ID:-$(uuidgen 2>/dev/null || echo "session-$(date +%s)")}"

# =============================================================================
# Initialization
# =============================================================================

# Initialize logging system
init_logger() {
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Initialize log files
    touch "$LOG_FILE" "$ERROR_LOG_FILE" "$METRICS_LOG_FILE"
    
    # Set up log rotation
    setup_log_rotation
    
    # Clean old logs
    cleanup_old_logs
    
    # Log initialization
    log_info "Logger initialized" "log_dir=$LOG_DIR" "session_id=$LOGGER_CONTEXT_SESSION_ID"
}

# Set up log rotation
setup_log_rotation() {
    for log_file in "$LOG_FILE" "$ERROR_LOG_FILE" "$METRICS_LOG_FILE"; do
        if [[ -f "$log_file" ]] && [[ $(get_file_size_mb "$log_file") -gt $MAX_LOG_SIZE_MB ]]; then
            rotate_log "$log_file"
        fi
    done
}

# Rotate a log file
rotate_log() {
    local log_file="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local rotated_file="${log_file}.${timestamp}"
    
    mv "$log_file" "$rotated_file"
    touch "$log_file"
    
    # Compress old log
    if command -v gzip >/dev/null 2>&1; then
        gzip "$rotated_file" &
    fi
}

# Get file size in MB
get_file_size_mb() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local size_bytes=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        echo $((size_bytes / 1024 / 1024))
    else
        echo 0
    fi
}

# Clean up old logs
cleanup_old_logs() {
    find "$LOG_DIR" -name "*.log.*" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    find "$LOG_DIR" -name "*.gz" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
}

# =============================================================================
# Core Logging Functions
# =============================================================================

# Check if log level should be logged
should_log() {
    local level="$1"
    local current_level_num=$(get_log_level_num "$CURRENT_LOG_LEVEL")
    local level_num=$(get_log_level_num "$level")
    [[ $level_num -ge $current_level_num ]]
}

# Get caller information
get_caller_info() {
    local frame=${1:-2}
    local caller_file="${BASH_SOURCE[$frame]}"
    local caller_line="${BASH_LINENO[$((frame-1))]}"
    local caller_func="${FUNCNAME[$frame]}"
    
    # Get relative path from project root
    if [[ "$caller_file" == "$PROJECT_ROOT"* ]]; then
        caller_file="${caller_file#$PROJECT_ROOT/}"
    fi
    
    echo "${caller_file}:${caller_line}:${caller_func}"
}

# Generate timestamp
get_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%S.%3NZ'
}

# Format log message
format_log_message() {
    local level="$1"
    local message="$2"
    shift 2
    
    local timestamp=$(get_timestamp)
    local caller=$(get_caller_info 3)
    
    if [[ "$LOG_FORMAT" == "JSON" ]]; then
        # JSON format
        local json_fields=()
        json_fields+=("\"timestamp\":\"$timestamp\"")
        json_fields+=("\"level\":\"$level\"")
        json_fields+=("\"message\":\"$message\"")
        json_fields+=("\"caller\":\"$caller\"")
        json_fields+=("\"phase\":\"$LOGGER_CONTEXT_PHASE\"")
        json_fields+=("\"task\":\"$LOGGER_CONTEXT_TASK\"")
        json_fields+=("\"session_id\":\"$LOGGER_CONTEXT_SESSION_ID\"")
        json_fields+=("\"pid\":$$")
        
        # Add extra fields
        while [[ $# -gt 0 ]]; do
            local field="$1"
            if [[ "$field" == *"="* ]]; then
                local key="${field%%=*}"
                local value="${field#*=}"
                json_fields+=("\"$key\":\"$value\"")
            fi
            shift
        done
        
        echo "{$(IFS=,; echo "${json_fields[*]}")}"
    else
        # Text format
        local extra_str=""
        if [[ $# -gt 0 ]]; then
            extra_str=" [$*]"
        fi
        echo "[$timestamp] [$level] [$LOGGER_CONTEXT_PHASE:$LOGGER_CONTEXT_TASK] $message$extra_str ($caller)"
    fi
}

# Core logging function
_log() {
    local level="$1"
    local message="$2"
    shift 2
    
    # Check if we should log this level
    if ! should_log "$level"; then
        return 0
    fi
    
    # Check log rotation
    setup_log_rotation
    
    # Format message
    local formatted_message=$(format_log_message "$level" "$message" "$@")
    
    # Console output
    if [[ "$LOG_TO_CONSOLE" == "true" ]]; then
        local color=$(get_log_color "$level")
        local reset=$(get_log_color "RESET")
        
        if [[ -t 1 ]] && [[ -n "$color" ]]; then
            echo -e "${color}${formatted_message}${reset}" >&2
        else
            echo "$formatted_message" >&2
        fi
    fi
    
    # File output
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        echo "$formatted_message" >> "$LOG_FILE"
        
        # Also log errors and fatals to error log
        if [[ "$level" == "ERROR" ]] || [[ "$level" == "FATAL" ]]; then
            echo "$formatted_message" >> "$ERROR_LOG_FILE"
        fi
    fi
}

# =============================================================================
# Public Logging Functions
# =============================================================================

# Debug logging
log_debug() {
    _log "DEBUG" "$@"
}

# Info logging
log_info() {
    _log "INFO" "$@"
}

# Warning logging
log_warn() {
    _log "WARN" "$@"
}

# Error logging
log_error() {
    _log "ERROR" "$@"
}

# Fatal logging
log_fatal() {
    _log "FATAL" "$@"
}

# Performance metric logging
log_metric() {
    local metric_name="$1"
    local metric_value="$2"
    shift 2
    local extra_fields=("$@")
    
    local timestamp=$(get_timestamp)
    local caller=$(get_caller_info 2)
    
    # Format metric message
    local metric_message="metric=$metric_name value=$metric_value"
    
    # JSON format for metrics
    local json_fields=()
    json_fields+=("\"timestamp\":\"$timestamp\"")
    json_fields+=("\"type\":\"metric\"")
    json_fields+=("\"metric\":\"$metric_name\"")
    json_fields+=("\"value\":$metric_value")
    json_fields+=("\"caller\":\"$caller\"")
    json_fields+=("\"phase\":\"$LOGGER_CONTEXT_PHASE\"")
    json_fields+=("\"task\":\"$LOGGER_CONTEXT_TASK\"")
    json_fields+=("\"session_id\":\"$LOGGER_CONTEXT_SESSION_ID\"")
    json_fields+=("\"pid\":$$")
    
    # Add extra fields
    for field in "${extra_fields[@]}"; do
        if [[ "$field" == *"="* ]]; then
            local key="${field%%=*}"
            local value="${field#*=}"
            json_fields+=("\"$key\":\"$value\"")
        fi
    done
    
    local metric_json="{$(IFS=,; echo "${json_fields[*]}")}"
    
    # Log as info level
    _log "INFO" "$metric_message" "${extra_fields[@]}"
    
    # Also write to metrics log
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        echo "$metric_json" >> "$METRICS_LOG_FILE"
    fi
}

# =============================================================================
# Context Management
# =============================================================================

# Set logging context
set_log_context() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                LOGGER_CONTEXT_PHASE="$2"
                shift 2
                ;;
            --task)
                LOGGER_CONTEXT_TASK="$2"
                shift 2
                ;;
            --session-id)
                LOGGER_CONTEXT_SESSION_ID="$2"
                shift 2
                ;;
            *)
                log_warn "Unknown context parameter: $1"
                shift
                ;;
        esac
    done
}

# Get current context
get_log_context() {
    echo "phase=$LOGGER_CONTEXT_PHASE task=$LOGGER_CONTEXT_TASK session_id=$LOGGER_CONTEXT_SESSION_ID"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Set log level
set_log_level() {
    local new_level="$1"
    if [[ $(get_log_level_num "$new_level") -ne 20 ]] || [[ "$new_level" == "INFO" ]]; then
        CURRENT_LOG_LEVEL="$new_level"
        log_info "Log level changed" "new_level=$new_level"
    else
        log_error "Invalid log level" "level=$new_level"
        return 1
    fi
}

# Get current log level
get_log_level() {
    echo "$CURRENT_LOG_LEVEL"
}

# Enable/disable console logging
set_console_logging() {
    LOG_TO_CONSOLE="$1"
    log_info "Console logging changed" "enabled=$1"
}

# Enable/disable file logging
set_file_logging() {
    LOG_TO_FILE="$1"
    log_info "File logging changed" "enabled=$1"
}

# Set log format
set_log_format() {
    local format="$1"
    if [[ "$format" == "JSON" ]] || [[ "$format" == "TEXT" ]]; then
        LOG_FORMAT="$format"
        log_info "Log format changed" "format=$format"
    else
        log_error "Invalid log format" "format=$format"
        return 1
    fi
}

# Performance timing helpers (using simple variables since no associative arrays)
TIMER_PREFIX="TIMER_START_"

# Start a timer
start_timer() {
    local timer_name="$1"
    local var_name="${TIMER_PREFIX}${timer_name}"
    eval "${var_name}=\"$(date +%s)\""
    log_debug "Timer started" "timer=$timer_name"
}

# Stop a timer and log the duration
stop_timer() {
    local timer_name="$1"
    local var_name="${TIMER_PREFIX}${timer_name}"
    local start_time
    
    eval "start_time=\${${var_name}:-}"
    
    if [[ -z "$start_time" ]]; then
        log_warn "Timer not found" "timer=$timer_name"
        return 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_metric "${timer_name}_duration" "$duration" "unit=seconds"
    eval "unset ${var_name}"
    
    echo "$duration"
}

# Log system information
log_system_info() {
    log_info "System information" \
        "hostname=$(hostname)" \
        "user=$(whoami)" \
        "pwd=$(pwd)" \
        "shell=$SHELL" \
        "bash_version=$BASH_VERSION" \
        "os=$(uname -s)" \
        "arch=$(uname -m)"
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if not already done
if [[ "${LOGGER_INITIALIZED:-}" != "true" ]]; then
    init_logger
    export LOGGER_INITIALIZED=true
fi