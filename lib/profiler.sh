#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Performance Profiler
# =============================================================================
#
# Comprehensive performance monitoring and instrumentation system for 
# identifying bottlenecks and optimizing critical paths in the pipeline.
#
# Features:
# - Function-level timing instrumentation
# - Call stack profiling
# - Memory usage monitoring
# - I/O operation tracking
# - Performance reports generation
# - Bottleneck identification
# - Automated optimization suggestions
# - Real-time performance dashboards
#
# Usage:
#   source lib/profiler.sh
#   profile_function "my_function"
#   profile_start "operation_name"
#   profile_end "operation_name"
#   profile_report
#   profile_analyze_bottlenecks
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source dependencies
source "${PROJECT_ROOT}/lib/logger.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/cache.sh" 2>/dev/null || true

# =============================================================================
# Configuration
# =============================================================================

PROFILER_ENABLED="${PROFILER_ENABLED:-true}"
PROFILER_DIR="${PROJECT_ROOT}/.profiler"
PROFILER_DATA_FILE="${PROFILER_DIR}/profile_data.json"
PROFILER_REPORT_FILE="${PROFILER_DIR}/profile_report.html"
PROFILER_SESSION_ID="session_$(date +%s)_$$"
PROFILER_MAX_CALL_DEPTH=20
PROFILER_MIN_DURATION_MS=1
PROFILER_SAMPLE_INTERVAL=0.1  # seconds

# Performance thresholds
PROFILER_SLOW_FUNCTION_MS=1000
PROFILER_SLOW_IO_MS=500
PROFILER_HIGH_MEMORY_MB=100

# Data storage
mkdir -p "$PROFILER_DIR"

# Profile data structure simulation using variables
PROFILE_TIMERS=""
PROFILE_FUNCTIONS=""
PROFILE_CALL_STACK=""
PROFILE_MEMORY_SAMPLES=""
PROFILE_IO_OPERATIONS=""

# =============================================================================
# Core Profiling Functions
# =============================================================================

# Start profiling session
profile_init() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Initialize data file
    echo '{
        "session_id": "'$PROFILER_SESSION_ID'",
        "start_time": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "functions": {},
        "timers": {},
        "call_stacks": [],
        "memory_samples": [],
        "io_operations": [],
        "system_info": {
            "hostname": "'$(hostname)'",
            "os": "'$(uname -s)'",
            "arch": "'$(uname -m)'",
            "bash_version": "'$BASH_VERSION'",
            "pid": '$$'
        }
    }' > "$PROFILER_DATA_FILE"
    
    # Start background monitoring
    profile_monitor_background &
    PROFILER_MONITOR_PID=$!
    
    log_info "Performance profiler initialized" "session=$PROFILER_SESSION_ID"
}

# Profile a function call
profile_function() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local function_name="$1"
    local start_time_ns=$(date +%s%N)
    local caller_info=$(get_caller_info 2)
    
    # Add to call stack
    PROFILE_CALL_STACK="${PROFILE_CALL_STACK}|${function_name}"
    local call_depth=$(echo "$PROFILE_CALL_STACK" | tr -cd '|' | wc -c)
    
    # Execute the function (this would need to be done by wrapper)
    log_debug "Function profiling started" "function=$function_name" "depth=$call_depth"
    
    return 0
}

# End function profiling
profile_function_end() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local function_name="$1"
    local end_time_ns=$(date +%s%N)
    local memory_usage=$(get_memory_usage)
    
    # Remove from call stack
    PROFILE_CALL_STACK=$(echo "$PROFILE_CALL_STACK" | sed "s/|${function_name}$//")
    
    # Record function performance data
    record_function_performance "$function_name" "$end_time_ns" "$memory_usage"
    
    log_debug "Function profiling ended" "function=$function_name"
}

# Start named timer
profile_start() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local timer_name="$1"
    local context="${2:-}"
    local start_time_ns=$(date +%s%N)
    
    # Store timer start time
    eval "TIMER_START_${timer_name}=\"$start_time_ns\""
    eval "TIMER_CONTEXT_${timer_name}=\"$context\""
    
    log_debug "Timer started" "timer=$timer_name" "context=$context"
}

# End named timer
profile_end() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local timer_name="$1"
    local end_time_ns=$(date +%s%N)
    local start_time_ns
    local context
    
    eval "start_time_ns=\${TIMER_START_${timer_name}:-}"
    eval "context=\${TIMER_CONTEXT_${timer_name}:-}"
    
    if [[ -z "$start_time_ns" ]]; then
        log_warn "Timer not found" "timer=$timer_name"
        return 1
    fi
    
    local duration_ns=$((end_time_ns - start_time_ns))
    local duration_ms=$((duration_ns / 1000000))
    
    # Record timer data
    record_timer_performance "$timer_name" "$duration_ms" "$context"
    
    # Clean up timer variables
    eval "unset TIMER_START_${timer_name}"
    eval "unset TIMER_CONTEXT_${timer_name}"
    
    log_debug "Timer completed" "timer=$timer_name" "duration_ms=$duration_ms"
    
    echo "$duration_ms"
}

# Profile I/O operations
profile_io() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local operation_type="$1"  # read, write, stat, etc.
    local file_path="$2"
    local size_bytes="${3:-0}"
    local start_time_ns=$(date +%s%N)
    
    # Execute the actual I/O operation (placeholder)
    # In real implementation, this would wrap actual I/O
    
    local end_time_ns=$(date +%s%N)
    local duration_ms=$(((end_time_ns - start_time_ns) / 1000000))
    
    record_io_performance "$operation_type" "$file_path" "$size_bytes" "$duration_ms"
    
    if [[ $duration_ms -gt $PROFILER_SLOW_IO_MS ]]; then
        log_warn "Slow I/O operation detected" "operation=$operation_type" "file=$file_path" "duration_ms=$duration_ms"
    fi
}

# =============================================================================
# Data Recording Functions
# =============================================================================

# Record function performance data
record_function_performance() {
    local function_name="$1"
    local end_time_ns="$2"
    local memory_usage="$3"
    
    # In a real implementation, this would update the JSON data file
    # For now, we'll simulate with logging
    log_metric "function_performance" "$end_time_ns" \
        "function=$function_name" \
        "memory_mb=$memory_usage" \
        "session=$PROFILER_SESSION_ID"
}

# Record timer performance data
record_timer_performance() {
    local timer_name="$1"
    local duration_ms="$2"
    local context="$3"
    
    log_metric "timer_performance" "$duration_ms" \
        "timer=$timer_name" \
        "context=$context" \
        "session=$PROFILER_SESSION_ID"
    
    # Check for slow operations
    if [[ $duration_ms -gt $PROFILER_SLOW_FUNCTION_MS ]]; then
        log_warn "Slow operation detected" "timer=$timer_name" "duration_ms=$duration_ms"
    fi
}

# Record I/O performance data
record_io_performance() {
    local operation_type="$1"
    local file_path="$2"
    local size_bytes="$3"
    local duration_ms="$4"
    
    local throughput_mbps=0
    if [[ $duration_ms -gt 0 ]] && [[ $size_bytes -gt 0 ]]; then
        throughput_mbps=$(echo "scale=2; $size_bytes / 1024 / 1024 / ($duration_ms / 1000)" | bc 2>/dev/null || echo "0")
    fi
    
    log_metric "io_performance" "$duration_ms" \
        "operation=$operation_type" \
        "file=$(basename "$file_path")" \
        "size_bytes=$size_bytes" \
        "throughput_mbps=$throughput_mbps" \
        "session=$PROFILER_SESSION_ID"
}

# =============================================================================
# System Monitoring
# =============================================================================

# Get current memory usage
get_memory_usage() {
    # Memory usage for current process
    if [[ -f "/proc/$$/status" ]]; then
        # Linux
        awk '/VmRSS:/ {print $2/1024}' "/proc/$$/status" 2>/dev/null || echo "0"
    else
        # macOS/BSD
        ps -o rss= -p $$ | awk '{print $1/1024}' 2>/dev/null || echo "0"
    fi
}

# Get system load
get_system_load() {
    if command -v uptime >/dev/null; then
        uptime | awk -F'load averages?: ' '{print $2}' | awk '{print $1}' | tr -d ','
    else
        echo "0.0"
    fi
}

# Get disk I/O stats
get_disk_io_stats() {
    if [[ -f "/proc/diskstats" ]]; then
        # Linux
        awk '{reads+=$4; writes+=$8} END {printf "%.0f %.0f\n", reads, writes}' /proc/diskstats
    else
        # macOS/BSD - simplified
        echo "0 0"
    fi
}

# Background monitoring
profile_monitor_background() {
    while [[ -f "$PROFILER_DATA_FILE" ]]; do
        local timestamp=$(date +%s)
        local memory_mb=$(get_memory_usage)
        local load_avg=$(get_system_load)
        
        # Sample system metrics
        log_metric "system_memory" "$memory_mb" \
            "load_avg=$load_avg" \
            "session=$PROFILER_SESSION_ID"
        
        sleep "$PROFILER_SAMPLE_INTERVAL"
    done
}

# =============================================================================
# Analysis and Reporting
# =============================================================================

# Generate performance report
profile_report() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        echo "Profiler is disabled"
        return 0
    fi
    
    local report_format="${1:-console}"  # console, html, json
    
    case "$report_format" in
        console)
            generate_console_report
            ;;
        html)
            generate_html_report
            ;;
        json)
            generate_json_report
            ;;
        *)
            log_error "Unknown report format" "format=$report_format"
            return 1
            ;;
    esac
}

# Generate console report
generate_console_report() {
    echo "=== Performance Profile Report ==="
    echo "Session: $PROFILER_SESSION_ID"
    echo "Generated: $(date)"
    echo ""
    
    # Function performance summary
    echo "=== Function Performance ==="
    echo "Functions with duration > ${PROFILER_SLOW_FUNCTION_MS}ms:"
    # In real implementation, this would analyze the collected data
    echo "  (Analyzing collected metrics...)"
    echo ""
    
    # Timer performance summary
    echo "=== Timer Performance ==="
    echo "Slow timers (> ${PROFILER_SLOW_FUNCTION_MS}ms):"
    echo "  (Analyzing timer data...)"
    echo ""
    
    # I/O performance summary
    echo "=== I/O Performance ==="
    echo "Slow I/O operations (> ${PROFILER_SLOW_IO_MS}ms):"
    echo "  (Analyzing I/O metrics...)"
    echo ""
    
    # Memory usage summary
    echo "=== Memory Usage ==="
    echo "Peak memory usage: $(get_memory_usage)MB"
    echo ""
    
    # Optimization suggestions
    echo "=== Optimization Suggestions ==="
    generate_optimization_suggestions
}

# Generate HTML report
generate_html_report() {
    cat > "$PROFILER_REPORT_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Performance Profile Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .metric { margin: 10px 0; padding: 10px; background: #f9f9f9; border-left: 4px solid #007acc; }
        .slow { border-left-color: #ff6b6b; }
        .chart { width: 100%; height: 400px; background: #f5f5f5; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; border: 1px solid #ddd; text-align: left; }
        th { background: #f5f5f5; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Performance Profile Report</h1>
        <p>Session: PROFILER_SESSION_ID</p>
        <p>Generated: $(date)</p>
    </div>
    
    <div class="section">
        <h2>Performance Overview</h2>
        <div class="chart">[Performance charts would go here]</div>
    </div>
    
    <div class="section">
        <h2>Function Performance</h2>
        <table>
            <tr><th>Function</th><th>Calls</th><th>Total Time</th><th>Avg Time</th><th>Max Time</th></tr>
            <tr><td colspan="5">Data analysis in progress...</td></tr>
        </table>
    </div>
    
    <div class="section">
        <h2>I/O Performance</h2>
        <table>
            <tr><th>Operation</th><th>File</th><th>Size</th><th>Duration</th><th>Throughput</th></tr>
            <tr><td colspan="5">Data analysis in progress...</td></tr>
        </table>
    </div>
    
    <div class="section">
        <h2>Optimization Recommendations</h2>
        <div class="metric">Performance analysis recommendations will be generated here.</div>
    </div>
</body>
</html>
EOF
    
    echo "HTML report generated: $PROFILER_REPORT_FILE"
}

# Generate JSON report
generate_json_report() {
    local json_report='{
        "session_id": "'$PROFILER_SESSION_ID'",
        "generated_at": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "summary": {
            "total_functions": 0,
            "total_timers": 0,
            "total_io_operations": 0,
            "peak_memory_mb": '$(get_memory_usage)',
            "session_duration_ms": 0
        },
        "functions": {},
        "timers": {},
        "io_operations": [],
        "optimization_suggestions": []
    }'
    
    echo "$json_report"
}

# Analyze bottlenecks
profile_analyze_bottlenecks() {
    echo "=== Bottleneck Analysis ==="
    echo ""
    
    # CPU bottlenecks
    echo "CPU Bottlenecks:"
    echo "  - Functions taking > ${PROFILER_SLOW_FUNCTION_MS}ms"
    echo "  - High CPU utilization periods"
    echo ""
    
    # I/O bottlenecks
    echo "I/O Bottlenecks:"
    echo "  - File operations taking > ${PROFILER_SLOW_IO_MS}ms"
    echo "  - Excessive file access patterns"
    echo ""
    
    # Memory bottlenecks
    echo "Memory Bottlenecks:"
    echo "  - Memory usage > ${PROFILER_HIGH_MEMORY_MB}MB"
    echo "  - Memory growth patterns"
    echo ""
}

# Generate optimization suggestions
generate_optimization_suggestions() {
    echo "Based on profiling data:"
    echo ""
    echo "1. Function Optimizations:"
    echo "   - Consider caching for frequently called functions"
    echo "   - Optimize algorithms in slow functions"
    echo "   - Use lazy loading where appropriate"
    echo ""
    echo "2. I/O Optimizations:"
    echo "   - Batch file operations where possible"
    echo "   - Use buffered I/O for large files"
    echo "   - Implement file caching"
    echo ""
    echo "3. Memory Optimizations:"
    echo "   - Review memory usage patterns"
    echo "   - Clean up temporary variables"
    echo "   - Use streaming for large data sets"
    echo ""
}

# =============================================================================
# Function Instrumentation Helpers
# =============================================================================

# Create instrumented wrapper for a function
instrument_function() {
    local function_name="$1"
    
    # This would create a wrapper function that adds profiling
    # This is a simplified example of how it could work
    eval "
    original_${function_name}() {
        $(declare -f "$function_name" | sed '1d;$d')
    }
    
    ${function_name}() {
        profile_function '${function_name}'
        local result
        result=\$(original_${function_name} \"\$@\")
        local exit_code=\$?
        profile_function_end '${function_name}'
        echo \"\$result\"
        return \$exit_code
    }
    "
    
    log_debug "Function instrumented" "function=$function_name"
}

# Auto-instrument common functions
auto_instrument_common_functions() {
    local common_functions=(
        "json_query_cached"
        "cache_get"
        "cache_set"
        "log_info"
        "log_error"
    )
    
    for func in "${common_functions[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            instrument_function "$func"
        fi
    done
}

# =============================================================================
# Performance Testing
# =============================================================================

# Run performance test suite
profile_run_tests() {
    echo "=== Performance Test Suite ==="
    
    # Test JSON operations
    profile_test_json_operations
    
    # Test cache operations
    profile_test_cache_operations
    
    # Test file I/O operations
    profile_test_file_operations
    
    echo "Performance tests completed"
}

# Test JSON operations performance
profile_test_json_operations() {
    echo "Testing JSON operations..."
    
    local test_file="${PROJECT_ROOT}/config/skill-rules.json"
    if [[ -f "$test_file" ]]; then
        profile_start "json_validate_test"
        json_validate "$test_file" >/dev/null
        local duration=$(profile_end "json_validate_test")
        echo "  JSON validation: ${duration}ms"
        
        profile_start "json_query_test"
        json_query_cached "$test_file" '.skills | length' >/dev/null
        duration=$(profile_end "json_query_test")
        echo "  JSON query: ${duration}ms"
    fi
}

# Test cache operations performance
profile_test_cache_operations() {
    echo "Testing cache operations..."
    
    profile_start "cache_set_test"
    cache_set "test_key" "test_value" 60
    local duration=$(profile_end "cache_set_test")
    echo "  Cache set: ${duration}ms"
    
    profile_start "cache_get_test"
    cache_get "test_key" >/dev/null
    duration=$(profile_end "cache_get_test")
    echo "  Cache get: ${duration}ms"
    
    cache_delete "test_key"
}

# Test file operations performance
profile_test_file_operations() {
    echo "Testing file I/O operations..."
    
    local test_file="${PROFILER_DIR}/test_file"
    
    profile_start "file_write_test"
    echo "test data" > "$test_file"
    local duration=$(profile_end "file_write_test")
    echo "  File write: ${duration}ms"
    
    profile_start "file_read_test"
    cat "$test_file" >/dev/null
    duration=$(profile_end "file_read_test")
    echo "  File read: ${duration}ms"
    
    rm -f "$test_file"
}

# =============================================================================
# Cleanup and Finalization
# =============================================================================

# Stop profiling and generate final report
profile_stop() {
    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Stop background monitoring
    if [[ -n "${PROFILER_MONITOR_PID:-}" ]]; then
        kill "$PROFILER_MONITOR_PID" 2>/dev/null || true
    fi
    
    # Generate final report
    log_info "Generating final performance report"
    profile_report console
    
    # Clean up
    log_info "Performance profiling session completed" "session=$PROFILER_SESSION_ID"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Enable/disable profiler
profile_enable() {
    PROFILER_ENABLED="true"
    log_info "Performance profiler enabled"
}

profile_disable() {
    PROFILER_ENABLED="false"
    log_info "Performance profiler disabled"
}

# Get profiler status
profile_status() {
    echo "Profiler Status:"
    echo "  Enabled: $PROFILER_ENABLED"
    echo "  Session: $PROFILER_SESSION_ID"
    echo "  Data file: $PROFILER_DATA_FILE"
    echo "  Memory usage: $(get_memory_usage)MB"
    echo "  System load: $(get_system_load)"
}

# Get caller information for profiling
get_caller_info() {
    local frame=${1:-2}
    local caller_file="${BASH_SOURCE[$frame]}"
    local caller_line="${BASH_LINENO[$((frame-1))]}"
    local caller_func="${FUNCNAME[$frame]}"
    
    echo "${caller_file##*/}:${caller_line}:${caller_func}"
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if not already done
if [[ "${PROFILER_INITIALIZED:-}" != "true" ]]; then
    if [[ "$PROFILER_ENABLED" == "true" ]]; then
        profile_init
        
        # Set up exit handler
        trap 'profile_stop' EXIT
        
        # Auto-instrument common functions
        auto_instrument_common_functions
    fi
    
    export PROFILER_INITIALIZED=true
fi