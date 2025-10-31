#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Performance Metrics System
# =============================================================================
#
# Comprehensive metrics collection and reporting system for pipeline performance,
# resource usage, success rates, and operational insights.
#
# Features:
# - Phase completion time tracking
# - Resource usage monitoring (CPU, memory, disk)
# - Success/failure rate calculations
# - Performance trend analysis
# - JSON export capabilities
# - Real-time metrics collection
# - Health scoring system
#
# Usage:
#   source lib/metrics.sh
#   metrics_track_phase_start "validation"
#   metrics_track_phase_end "validation" "success"
#   metrics_collect_system_stats
#   metrics_generate_report
#
# =============================================================================

# Load logger if available
if [[ -f "${PROJECT_ROOT:-}/lib/logger.sh" ]]; then
    source "${PROJECT_ROOT}/lib/logger.sh"
else
    # Fallback logging functions
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { echo "[DEBUG] $*" >&2; }
fi

# =============================================================================
# Configuration
# =============================================================================

METRICS_DIR="${PROJECT_ROOT}/logs/metrics"
METRICS_DATA_FILE="${METRICS_DIR}/metrics_data.json"
PERFORMANCE_HISTORY_FILE="${METRICS_DIR}/performance_history.json"
SYSTEM_STATS_FILE="${METRICS_DIR}/system_stats.json"
HEALTH_SCORE_FILE="${METRICS_DIR}/health_score.json"

# Metric collection intervals (seconds)
SYSTEM_STATS_INTERVAL=5
PERFORMANCE_WINDOW_HOURS=24

# Thresholds for health scoring
CPU_THRESHOLD_WARN=70
CPU_THRESHOLD_CRITICAL=90
MEMORY_THRESHOLD_WARN=80
MEMORY_THRESHOLD_CRITICAL=95
PHASE_TIMEOUT_WARN=300    # 5 minutes
PHASE_TIMEOUT_CRITICAL=900 # 15 minutes

# =============================================================================
# Initialization
# =============================================================================

init_metrics() {
    # Create metrics directory
    mkdir -p "$METRICS_DIR"
    
    # Initialize metrics files
    if [[ ! -f "$METRICS_DATA_FILE" ]]; then
        echo '{"phases":{},"tasks":{},"system":{},"errors":{},"sessions":{}}' > "$METRICS_DATA_FILE"
    fi
    
    if [[ ! -f "$PERFORMANCE_HISTORY_FILE" ]]; then
        echo '{"history":[]}' > "$PERFORMANCE_HISTORY_FILE"
    fi
    
    if [[ ! -f "$SYSTEM_STATS_FILE" ]]; then
        echo '{"stats":[]}' > "$SYSTEM_STATS_FILE"
    fi
    
    if [[ ! -f "$HEALTH_SCORE_FILE" ]]; then
        echo '{"score":100,"status":"healthy","last_updated":"","components":{}}' > "$HEALTH_SCORE_FILE"
    fi
    
    log_info "Metrics system initialized" "metrics_dir=$METRICS_DIR"
}

# =============================================================================
# Phase Tracking
# =============================================================================

# Track phase start
metrics_track_phase_start() {
    local phase_name="$1"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local session_id="${LOGGER_CONTEXT_SESSION_ID:-unknown}"
    
    # Store phase start data
    local phase_data=$(jq -n \
        --arg phase "$phase_name" \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg status "running" \
        '{
            phase: $phase,
            start_time: $timestamp,
            session_id: $session_id,
            status: $status,
            pid: env.PID
        }')
    
    # Update metrics data
    jq --argjson data "$phase_data" \
       '.phases[$data.phase] = $data' \
       "$METRICS_DATA_FILE" > "${METRICS_DATA_FILE}.tmp" && \
    mv "${METRICS_DATA_FILE}.tmp" "$METRICS_DATA_FILE"
    
    log_info "Phase tracking started" "phase=$phase_name" "session_id=$session_id"
}

# Track phase end
metrics_track_phase_end() {
    local phase_name="$1"
    local status="${2:-success}"  # success, failure, timeout
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    # Get existing phase data
    local phase_data=$(jq -r ".phases[\"$phase_name\"] // empty" "$METRICS_DATA_FILE")
    
    if [[ -z "$phase_data" ]] || [[ "$phase_data" == "null" ]]; then
        log_warn "Phase tracking not found" "phase=$phase_name"
        return 1
    fi
    
    # Calculate duration
    local start_time=$(echo "$phase_data" | jq -r '.start_time')
    local duration=0
    
    if [[ -n "$start_time" ]] && [[ "$start_time" != "null" ]]; then
        if command -v gdate >/dev/null 2>&1; then
            # macOS with GNU date
            local start_epoch=$(gdate -d "$start_time" +%s.%3N)
            local end_epoch=$(gdate -d "$timestamp" +%s.%3N)
        else
            # Try standard date
            local start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${start_time%.*}" +%s 2>/dev/null || echo 0)
            local end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%.*}" +%s 2>/dev/null || echo 0)
        fi
        
        if [[ "$start_epoch" != "0" ]] && [[ "$end_epoch" != "0" ]]; then
            duration=$(echo "$end_epoch - $start_epoch" | bc -l 2>/dev/null || echo 0)
        fi
    fi
    
    # Update phase data
    local updated_data=$(echo "$phase_data" | jq \
        --arg timestamp "$timestamp" \
        --arg status "$status" \
        --argjson duration "$duration" \
        '. + {
            end_time: $timestamp,
            status: $status,
            duration: $duration
        }')
    
    # Update metrics data
    jq --argjson data "$updated_data" \
       '.phases[$data.phase] = $data' \
       "$METRICS_DATA_FILE" > "${METRICS_DATA_FILE}.tmp" && \
    mv "${METRICS_DATA_FILE}.tmp" "$METRICS_DATA_FILE"
    
    # Add to performance history
    local history_entry=$(jq -n \
        --arg phase "$phase_name" \
        --arg timestamp "$timestamp" \
        --arg status "$status" \
        --argjson duration "$duration" \
        '{
            phase: $phase,
            timestamp: $timestamp,
            status: $status,
            duration: $duration
        }')
    
    jq --argjson entry "$history_entry" \
       '.history += [$entry]' \
       "$PERFORMANCE_HISTORY_FILE" > "${PERFORMANCE_HISTORY_FILE}.tmp" && \
    mv "${PERFORMANCE_HISTORY_FILE}.tmp" "$PERFORMANCE_HISTORY_FILE"
    
    log_info "Phase tracking completed" "phase=$phase_name" "status=$status" "duration=${duration}s"
}

# =============================================================================
# System Resource Monitoring
# =============================================================================

# Collect current system statistics
metrics_collect_system_stats() {
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local cpu_usage=0
    local memory_usage=0
    local disk_usage=0
    local load_average="0.0"
    
    # CPU usage (average over 1 second)
    if command -v top >/dev/null 2>&1; then
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            cpu_usage=$(top -l 2 -n 0 -s 1 | grep "CPU usage" | tail -1 | awk '{print $3}' | sed 's/%//')
        else
            # Linux
            cpu_usage=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $2}' | sed 's/%us,//')
        fi
    fi
    
    # Memory usage
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        local mem_stats=$(vm_stat | grep -E "(free|inactive|wired|compressed)")
        local page_size=4096
        local free_pages=$(echo "$mem_stats" | grep "free" | awk '{print $3}' | sed 's/\.//')
        local inactive_pages=$(echo "$mem_stats" | grep "inactive" | awk '{print $3}' | sed 's/\.//')
        local wired_pages=$(echo "$mem_stats" | grep "wired" | awk '{print $4}' | sed 's/\.//')
        local compressed_pages=$(echo "$mem_stats" | grep "compressed" | awk '{print $3}' | sed 's/\.//')
        
        local total_used=$((($wired_pages + $compressed_pages) * $page_size))
        local total_free=$((($free_pages + $inactive_pages) * $page_size))
        local total_memory=$(($total_used + $total_free))
        
        if [[ $total_memory -gt 0 ]]; then
            memory_usage=$(echo "scale=2; $total_used * 100 / $total_memory" | bc -l 2>/dev/null || echo 0)
        fi
    else
        # Linux
        if [[ -f /proc/meminfo ]]; then
            local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            if [[ $mem_total -gt 0 ]]; then
                memory_usage=$(echo "scale=2; ($mem_total - $mem_available) * 100 / $mem_total" | bc -l 2>/dev/null || echo 0)
            fi
        fi
    fi
    
    # Disk usage for project directory
    if command -v df >/dev/null 2>&1; then
        disk_usage=$(df "$PROJECT_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
    fi
    
    # Load average
    if command -v uptime >/dev/null 2>&1; then
        load_average=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    fi
    
    # Create stats entry
    local stats_entry=$(jq -n \
        --arg timestamp "$timestamp" \
        --argjson cpu "${cpu_usage:-0}" \
        --argjson memory "${memory_usage:-0}" \
        --argjson disk "${disk_usage:-0}" \
        --arg load "$load_average" \
        --argjson pid "$$" \
        '{
            timestamp: $timestamp,
            cpu_usage: $cpu,
            memory_usage: $memory,
            disk_usage: $disk,
            load_average: $load,
            pid: $pid
        }')
    
    # Add to system stats
    jq --argjson entry "$stats_entry" \
       '.stats += [$entry]' \
       "$SYSTEM_STATS_FILE" > "${SYSTEM_STATS_FILE}.tmp" && \
    mv "${SYSTEM_STATS_FILE}.tmp" "$SYSTEM_STATS_FILE"
    
    # Keep only recent stats (last 24 hours)
    local cutoff_time=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || \
                       date -u -v-24H '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || \
                       echo "1970-01-01T00:00:00.000Z")
    
    jq --arg cutoff "$cutoff_time" \
       '.stats = (.stats | map(select(.timestamp > $cutoff)))' \
       "$SYSTEM_STATS_FILE" > "${SYSTEM_STATS_FILE}.tmp" && \
    mv "${SYSTEM_STATS_FILE}.tmp" "$SYSTEM_STATS_FILE"
    
    echo "$stats_entry"
}

# Start background system monitoring
metrics_start_monitoring() {
    local monitor_interval="${1:-$SYSTEM_STATS_INTERVAL}"
    local monitor_pid_file="${METRICS_DIR}/monitor.pid"
    
    # Check if already running
    if [[ -f "$monitor_pid_file" ]]; then
        local existing_pid=$(cat "$monitor_pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_info "System monitoring already running" "pid=$existing_pid"
            return 0
        fi
    fi
    
    # Start background monitoring
    (
        while true; do
            metrics_collect_system_stats >/dev/null 2>&1
            sleep "$monitor_interval"
        done
    ) &
    
    local monitor_pid=$!
    echo "$monitor_pid" > "$monitor_pid_file"
    
    log_info "System monitoring started" "pid=$monitor_pid" "interval=${monitor_interval}s"
}

# Stop background system monitoring
metrics_stop_monitoring() {
    local monitor_pid_file="${METRICS_DIR}/monitor.pid"
    
    if [[ -f "$monitor_pid_file" ]]; then
        local monitor_pid=$(cat "$monitor_pid_file")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid"
            rm -f "$monitor_pid_file"
            log_info "System monitoring stopped" "pid=$monitor_pid"
        else
            rm -f "$monitor_pid_file"
            log_info "System monitoring was not running"
        fi
    else
        log_info "System monitoring was not running"
    fi
}

# =============================================================================
# Success/Failure Rate Tracking
# =============================================================================

# Track task outcome
metrics_track_task_outcome() {
    local task_name="$1"
    local outcome="$2"  # success, failure, timeout
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local session_id="${LOGGER_CONTEXT_SESSION_ID:-unknown}"
    
    # Update task metrics
    local task_key="task_${task_name}"
    jq --arg task "$task_name" \
       --arg outcome "$outcome" \
       --arg timestamp "$timestamp" \
       --arg session_id "$session_id" \
       '.tasks[$task] = (.tasks[$task] // {}) |
        .tasks[$task].total = ((.tasks[$task].total // 0) + 1) |
        .tasks[$task][$outcome] = ((.tasks[$task][$outcome] // 0) + 1) |
        .tasks[$task].last_updated = $timestamp |
        .tasks[$task].last_session = $session_id' \
       "$METRICS_DATA_FILE" > "${METRICS_DATA_FILE}.tmp" && \
    mv "${METRICS_DATA_FILE}.tmp" "$METRICS_DATA_FILE"
    
    log_info "Task outcome tracked" "task=$task_name" "outcome=$outcome"
}

# Track error occurrence
metrics_track_error() {
    local error_type="$1"
    local error_message="$2"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local session_id="${LOGGER_CONTEXT_SESSION_ID:-unknown}"
    
    # Update error metrics
    jq --arg type "$error_type" \
       --arg message "$error_message" \
       --arg timestamp "$timestamp" \
       --arg session_id "$session_id" \
       '.errors[$type] = (.errors[$type] // {}) |
        .errors[$type].count = ((.errors[$type].count // 0) + 1) |
        .errors[$type].last_message = $message |
        .errors[$type].last_occurrence = $timestamp |
        .errors[$type].last_session = $session_id' \
       "$METRICS_DATA_FILE" > "${METRICS_DATA_FILE}.tmp" && \
    mv "${METRICS_DATA_FILE}.tmp" "$METRICS_DATA_FILE"
    
    log_info "Error tracked" "type=$error_type" "message=$error_message"
}

# =============================================================================
# Health Scoring
# =============================================================================

# Calculate health score
metrics_calculate_health_score() {
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local overall_score=100
    local status="healthy"
    local components={}
    
    # Get recent system stats (last 5 minutes)
    local recent_stats=$(jq -r --arg cutoff "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || 
                                           date -u -v-5M '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || 
                                           echo '1970-01-01T00:00:00.000Z')" \
                           '.stats | map(select(.timestamp > $cutoff))' \
                           "$SYSTEM_STATS_FILE" 2>/dev/null || echo "[]")
    
    if [[ "$recent_stats" != "[]" ]] && [[ -n "$recent_stats" ]]; then
        # CPU health
        local avg_cpu=$(echo "$recent_stats" | jq '[.[].cpu_usage] | add / length' 2>/dev/null || echo 0)
        local cpu_score=100
        local cpu_status="healthy"
        
        if (( $(echo "$avg_cpu > $CPU_THRESHOLD_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
            cpu_score=20
            cpu_status="critical"
        elif (( $(echo "$avg_cpu > $CPU_THRESHOLD_WARN" | bc -l 2>/dev/null || echo 0) )); then
            cpu_score=60
            cpu_status="warning"
        fi
        
        # Memory health
        local avg_memory=$(echo "$recent_stats" | jq '[.[].memory_usage] | add / length' 2>/dev/null || echo 0)
        local memory_score=100
        local memory_status="healthy"
        
        if (( $(echo "$avg_memory > $MEMORY_THRESHOLD_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
            memory_score=20
            memory_status="critical"
        elif (( $(echo "$avg_memory > $MEMORY_THRESHOLD_WARN" | bc -l 2>/dev/null || echo 0) )); then
            memory_score=60
            memory_status="warning"
        fi
        
        # Update components
        components=$(jq -n \
            --argjson cpu_score "$cpu_score" \
            --arg cpu_status "$cpu_status" \
            --argjson avg_cpu "$avg_cpu" \
            --argjson memory_score "$memory_score" \
            --arg memory_status "$memory_status" \
            --argjson avg_memory "$avg_memory" \
            '{
                cpu: {
                    score: $cpu_score,
                    status: $cpu_status,
                    avg_usage: $avg_cpu
                },
                memory: {
                    score: $memory_score,
                    status: $memory_status,
                    avg_usage: $avg_memory
                }
            }')
        
        # Calculate overall score (weighted average)
        overall_score=$(echo "($cpu_score * 0.4) + ($memory_score * 0.6)" | bc -l 2>/dev/null || echo 100)
        overall_score=${overall_score%.*}  # Convert to integer
        
        # Determine overall status
        if [[ $overall_score -lt 40 ]]; then
            status="critical"
        elif [[ $overall_score -lt 70 ]]; then
            status="warning"
        else
            status="healthy"
        fi
    fi
    
    # Check for stuck phases
    local running_phases=$(jq -r '.phases | to_entries[] | select(.value.status == "running") | .key' "$METRICS_DATA_FILE" 2>/dev/null || echo "")
    
    if [[ -n "$running_phases" ]]; then
        while IFS= read -r phase; do
            local start_time=$(jq -r ".phases[\"$phase\"].start_time" "$METRICS_DATA_FILE")
            if [[ -n "$start_time" ]] && [[ "$start_time" != "null" ]]; then
                local phase_duration=0
                if command -v gdate >/dev/null 2>&1; then
                    local start_epoch=$(gdate -d "$start_time" +%s)
                    local now_epoch=$(gdate +%s)
                    phase_duration=$((now_epoch - start_epoch))
                fi
                
                if [[ $phase_duration -gt $PHASE_TIMEOUT_CRITICAL ]]; then
                    overall_score=$((overall_score - 30))
                    status="critical"
                elif [[ $phase_duration -gt $PHASE_TIMEOUT_WARN ]]; then
                    overall_score=$((overall_score - 15))
                    if [[ "$status" == "healthy" ]]; then
                        status="warning"
                    fi
                fi
            fi
        done <<< "$running_phases"
    fi
    
    # Ensure score is not negative
    if [[ $overall_score -lt 0 ]]; then
        overall_score=0
    fi
    
    # Update health score file
    jq -n \
        --argjson score "$overall_score" \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson components "$components" \
        '{
            score: $score,
            status: $status,
            last_updated: $timestamp,
            components: $components
        }' > "$HEALTH_SCORE_FILE"
    
    echo "$overall_score"
}

# =============================================================================
# Reporting
# =============================================================================

# Generate performance report
metrics_generate_report() {
    local output_format="${1:-text}"  # text or json
    local report_file="${METRICS_DIR}/performance_report.${output_format}"
    
    if [[ "$output_format" == "json" ]]; then
        # JSON report
        local report=$(jq -n \
            --argjsonfile metrics "$METRICS_DATA_FILE" \
            --argjsonfile history "$PERFORMANCE_HISTORY_FILE" \
            --argjsonfile health "$HEALTH_SCORE_FILE" \
            '{
                timestamp: (now | strftime("%Y-%m-%dT%H:%M:%S.%3NZ")),
                health: $health,
                metrics: $metrics,
                recent_history: ($history.history | sort_by(.timestamp) | reverse | .[0:10])
            }')
        
        echo "$report" > "$report_file"
    else
        # Text report
        {
            echo "==============================================="
            echo "Claude Dev Pipeline - Performance Report"
            echo "Generated: $(date)"
            echo "==============================================="
            echo
            
            # Health status
            local health_score=$(jq -r '.score' "$HEALTH_SCORE_FILE" 2>/dev/null || echo "unknown")
            local health_status=$(jq -r '.status' "$HEALTH_SCORE_FILE" 2>/dev/null || echo "unknown")
            echo "HEALTH STATUS"
            echo "-------------"
            echo "Overall Score: $health_score/100"
            echo "Status: $health_status"
            echo
            
            # Phase statistics
            echo "PHASE STATISTICS"
            echo "----------------"
            jq -r '.phases | to_entries[] | "\(.key): \(.value.status) (\(.value.duration // 0)s)"' "$METRICS_DATA_FILE" 2>/dev/null || echo "No phase data available"
            echo
            
            # Task success rates
            echo "TASK SUCCESS RATES"
            echo "------------------"
            jq -r '.tasks | to_entries[] | "\(.key): \(.value.success // 0)/\(.value.total // 0) (\(((.value.success // 0) * 100 / (.value.total // 1)) | floor)%)"' "$METRICS_DATA_FILE" 2>/dev/null || echo "No task data available"
            echo
            
            # Error summary
            echo "ERROR SUMMARY"
            echo "-------------"
            jq -r '.errors | to_entries[] | "\(.key): \(.value.count) occurrences"' "$METRICS_DATA_FILE" 2>/dev/null || echo "No error data available"
            echo
            
        } > "$report_file"
    fi
    
    log_info "Performance report generated" "format=$output_format" "file=$report_file"
    echo "$report_file"
}

# Export metrics in JSON format
metrics_export_json() {
    local output_file="${1:-${METRICS_DIR}/metrics_export_$(date +%Y%m%d_%H%M%S).json}"
    
    jq -s '.[0] + {
        system_stats: .[1].stats,
        performance_history: .[2].history,
        health_score: .[3]
    }' \
    "$METRICS_DATA_FILE" \
    "$SYSTEM_STATS_FILE" \
    "$PERFORMANCE_HISTORY_FILE" \
    "$HEALTH_SCORE_FILE" > "$output_file"
    
    log_info "Metrics exported" "file=$output_file"
    echo "$output_file"
}

# =============================================================================
# Cleanup
# =============================================================================

# Clean up old metric data
metrics_cleanup() {
    local retention_days="${1:-30}"
    local cutoff_date=$(date -u -d "${retention_days} days ago" '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || \
                       date -u -v-${retention_days}d '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || \
                       echo "1970-01-01T00:00:00.000Z")
    
    # Clean performance history
    jq --arg cutoff "$cutoff_date" \
       '.history = (.history | map(select(.timestamp > $cutoff)))' \
       "$PERFORMANCE_HISTORY_FILE" > "${PERFORMANCE_HISTORY_FILE}.tmp" && \
    mv "${PERFORMANCE_HISTORY_FILE}.tmp" "$PERFORMANCE_HISTORY_FILE"
    
    # Clean system stats
    jq --arg cutoff "$cutoff_date" \
       '.stats = (.stats | map(select(.timestamp > $cutoff)))' \
       "$SYSTEM_STATS_FILE" > "${SYSTEM_STATS_FILE}.tmp" && \
    mv "${SYSTEM_STATS_FILE}.tmp" "$SYSTEM_STATS_FILE"
    
    log_info "Metrics cleanup completed" "retention_days=$retention_days"
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if not already done
if [[ "${METRICS_INITIALIZED:-}" != "true" ]]; then
    init_metrics
    export METRICS_INITIALIZED=true
fi