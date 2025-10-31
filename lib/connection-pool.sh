#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Connection Pooling System
# =============================================================================
#
# High-performance connection pooling for external tools and services including
# git operations, TaskMaster, OpenSpec, and other external integrations.
#
# Features:
# - Connection reuse and pooling
# - Health checking and monitoring
# - Automatic retry logic with backoff
# - Load balancing across multiple endpoints
# - Connection lifecycle management
# - Performance metrics and monitoring
# - Circuit breaker pattern
# - Connection warmup and preallocation
#
# Usage:
#   source lib/connection-pool.sh
#   pool_get_connection "git" "repo_path"
#   pool_execute_command "taskmaster" "show tasks"
#   pool_health_check "openspec"
#   pool_close_all_connections
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source dependencies
source "${PROJECT_ROOT}/lib/logger.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/cache.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/profiler.sh" 2>/dev/null || true

# =============================================================================
# Configuration
# =============================================================================

POOL_ENABLED="${POOL_ENABLED:-true}"
POOL_MAX_CONNECTIONS=10
POOL_CONNECTION_TTL=300  # 5 minutes
POOL_HEALTH_CHECK_INTERVAL=60  # 1 minute
POOL_RETRY_MAX_ATTEMPTS=3
POOL_RETRY_BASE_DELAY=1  # seconds
POOL_CIRCUIT_BREAKER_THRESHOLD=5  # failures before circuit opens
POOL_CIRCUIT_BREAKER_TIMEOUT=30  # seconds to wait before retry

# Connection pool storage
POOL_DIR="${PROJECT_ROOT}/.pool"
POOL_STATE_FILE="${POOL_DIR}/pool_state.json"

# Connection tracking
ACTIVE_CONNECTIONS=""
CONNECTION_METADATA_PREFIX="CONN_META_"
CONNECTION_HEALTH_PREFIX="CONN_HEALTH_"
CONNECTION_CIRCUIT_PREFIX="CONN_CIRCUIT_"

# Service definitions
declare -A SERVICE_CONFIGS
SERVICE_CONFIGS=(
    ["git"]="type=git;max_conn=5;health_cmd=git --version"
    ["taskmaster"]="type=api;max_conn=3;health_cmd=taskmaster status"
    ["openspec"]="type=api;max_conn=3;health_cmd=openspec --version"
    ["jq"]="type=tool;max_conn=2;health_cmd=jq --version"
    ["curl"]="type=http;max_conn=5;health_cmd=curl --version"
)

# Create pool directory
mkdir -p "$POOL_DIR"

# =============================================================================
# Core Pool Management
# =============================================================================

# Initialize connection pool
pool_init() {
    if [[ "$POOL_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Initializing connection pool"
    profile_start "pool_init"
    
    # Initialize pool state
    init_pool_state
    
    # Start health monitoring
    start_health_monitoring &
    POOL_HEALTH_MONITOR_PID=$!
    
    # Prewarm critical connections
    prewarm_connections
    
    local duration=$(profile_end "pool_init")
    log_info "Connection pool initialized" "duration_ms=$duration"
}

# Initialize pool state
init_pool_state() {
    local pool_state='{
        "initialized_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "services": {},
        "connections": {},
        "stats": {
            "total_connections": 0,
            "active_connections": 0,
            "total_requests": 0,
            "failed_requests": 0,
            "avg_response_time_ms": 0
        }
    }'
    
    echo "$pool_state" > "$POOL_STATE_FILE"
}

# Get connection from pool
pool_get_connection() {
    local service_type="$1"
    local context="${2:-default}"
    local timeout="${3:-30}"
    
    if [[ "$POOL_ENABLED" != "true" ]]; then
        # Return a dummy connection ID
        echo "direct_connection_$$"
        return 0
    fi
    
    profile_start "pool_get_connection:$service_type"
    
    # Check service configuration
    if [[ -z "${SERVICE_CONFIGS[$service_type]:-}" ]]; then
        log_error "Unknown service type" "service=$service_type"
        return 1
    fi
    
    # Check circuit breaker
    if is_circuit_open "$service_type"; then
        log_warn "Circuit breaker open for service" "service=$service_type"
        return 1
    fi
    
    # Try to get existing connection
    local connection_id=$(find_available_connection "$service_type" "$context")
    
    if [[ -z "$connection_id" ]]; then
        # Create new connection
        connection_id=$(create_new_connection "$service_type" "$context")
        if [[ -z "$connection_id" ]]; then
            log_error "Failed to create connection" "service=$service_type"
            record_connection_failure "$service_type"
            return 1
        fi
    fi
    
    # Mark connection as in use
    mark_connection_active "$connection_id"
    
    local duration=$(profile_end "pool_get_connection:$service_type")
    log_debug "Connection acquired" "service=$service_type" "connection=$connection_id" "duration_ms=$duration"
    
    echo "$connection_id"
}

# Execute command using pooled connection
pool_execute_command() {
    local service_type="$1"
    local command="$2"
    local context="${3:-default}"
    local timeout="${4:-30}"
    
    profile_start "pool_execute:$service_type"
    
    # Get connection
    local connection_id=$(pool_get_connection "$service_type" "$context" "$timeout")
    if [[ -z "$connection_id" ]]; then
        log_error "Failed to get connection for command execution" "service=$service_type"
        return 1
    fi
    
    local start_time=$(date +%s.%3N)
    local result
    local exit_code
    
    # Execute command based on service type
    case "$service_type" in
        git)
            result=$(execute_git_command "$connection_id" "$command" "$context")
            exit_code=$?
            ;;
        taskmaster)
            result=$(execute_taskmaster_command "$connection_id" "$command")
            exit_code=$?
            ;;
        openspec)
            result=$(execute_openspec_command "$connection_id" "$command")
            exit_code=$?
            ;;
        jq)
            result=$(execute_jq_command "$connection_id" "$command")
            exit_code=$?
            ;;
        curl)
            result=$(execute_curl_command "$connection_id" "$command")
            exit_code=$?
            ;;
        *)
            result=$(execute_generic_command "$connection_id" "$service_type" "$command")
            exit_code=$?
            ;;
    esac
    
    local end_time=$(date +%s.%3N)
    local response_time=$(echo "$end_time - $start_time" | bc)
    local response_time_ms=$(echo "$response_time * 1000" | bc | cut -d. -f1)
    
    # Record metrics
    record_command_execution "$service_type" "$response_time_ms" "$exit_code"
    
    # Release connection
    pool_release_connection "$connection_id"
    
    local duration=$(profile_end "pool_execute:$service_type")
    
    if [[ $exit_code -eq 0 ]]; then
        log_debug "Command executed successfully" "service=$service_type" "response_time_ms=$response_time_ms"
        echo "$result"
    else
        log_error "Command execution failed" "service=$service_type" "exit_code=$exit_code"
        record_connection_failure "$service_type"
    fi
    
    return $exit_code
}

# Release connection back to pool
pool_release_connection() {
    local connection_id="$1"
    
    if [[ -z "$connection_id" ]]; then
        return 0
    fi
    
    # Mark connection as available
    mark_connection_available "$connection_id"
    
    log_debug "Connection released" "connection=$connection_id"
}

# =============================================================================
# Connection Management
# =============================================================================

# Find available connection
find_available_connection() {
    local service_type="$1"
    local context="$2"
    
    # Look for available connections of this service type
    # This is a simplified implementation
    local connections=$(get_service_connections "$service_type")
    
    for connection in $connections; do
        if is_connection_available "$connection"; then
            echo "$connection"
            return 0
        fi
    done
    
    return 1
}

# Create new connection
create_new_connection() {
    local service_type="$1"
    local context="$2"
    
    # Check if we've reached max connections for this service
    local current_count=$(count_service_connections "$service_type")
    local max_connections=$(get_service_max_connections "$service_type")
    
    if [[ $current_count -ge $max_connections ]]; then
        log_debug "Max connections reached for service" "service=$service_type" "current=$current_count" "max=$max_connections"
        return 1
    fi
    
    # Generate connection ID
    local connection_id="${service_type}_conn_$(date +%s)_$$"
    
    # Initialize connection based on service type
    if initialize_connection "$connection_id" "$service_type" "$context"; then
        # Add to active connections
        ACTIVE_CONNECTIONS="${ACTIVE_CONNECTIONS}|${connection_id}|"
        
        # Store connection metadata
        eval "${CONNECTION_METADATA_PREFIX}${connection_id}_service=\"$service_type\""
        eval "${CONNECTION_METADATA_PREFIX}${connection_id}_context=\"$context\""
        eval "${CONNECTION_METADATA_PREFIX}${connection_id}_created_at=\"$(date +%s)\""
        eval "${CONNECTION_METADATA_PREFIX}${connection_id}_status=\"available\""
        
        log_debug "New connection created" "service=$service_type" "connection=$connection_id"
        echo "$connection_id"
        return 0
    else
        log_error "Failed to initialize connection" "service=$service_type"
        return 1
    fi
}

# Initialize connection based on service type
initialize_connection() {
    local connection_id="$1"
    local service_type="$2"
    local context="$3"
    
    case "$service_type" in
        git)
            initialize_git_connection "$connection_id" "$context"
            ;;
        taskmaster)
            initialize_taskmaster_connection "$connection_id"
            ;;
        openspec)
            initialize_openspec_connection "$connection_id"
            ;;
        jq|curl)
            # Tool-based services don't need special initialization
            return 0
            ;;
        *)
            log_warn "Unknown service type for initialization" "service=$service_type"
            return 1
            ;;
    esac
}

# Mark connection as active
mark_connection_active() {
    local connection_id="$1"
    eval "${CONNECTION_METADATA_PREFIX}${connection_id}_status=\"active\""
    eval "${CONNECTION_METADATA_PREFIX}${connection_id}_last_used=\"$(date +%s)\""
}

# Mark connection as available
mark_connection_available() {
    local connection_id="$1"
    eval "${CONNECTION_METADATA_PREFIX}${connection_id}_status=\"available\""
    eval "${CONNECTION_METADATA_PREFIX}${connection_id}_last_used=\"$(date +%s)\""
}

# Check if connection is available
is_connection_available() {
    local connection_id="$1"
    local status
    eval "status=\${${CONNECTION_METADATA_PREFIX}${connection_id}_status:-}"
    [[ "$status" == "available" ]]
}

# =============================================================================
# Service-Specific Implementations
# =============================================================================

# Git connection handling
initialize_git_connection() {
    local connection_id="$1"
    local repo_path="$2"
    
    if [[ -n "$repo_path" ]] && [[ -d "$repo_path" ]]; then
        # Store repository context
        eval "${CONNECTION_METADATA_PREFIX}${connection_id}_repo_path=\"$repo_path\""
        return 0
    else
        return 1
    fi
}

execute_git_command() {
    local connection_id="$1"
    local command="$2"
    local context="$3"
    
    local repo_path
    eval "repo_path=\${${CONNECTION_METADATA_PREFIX}${connection_id}_repo_path:-}"
    
    if [[ -n "$repo_path" ]]; then
        (cd "$repo_path" && eval "$command")
    else
        eval "$command"
    fi
}

# TaskMaster connection handling
initialize_taskmaster_connection() {
    local connection_id="$1"
    
    # Check if TaskMaster is available
    if command -v taskmaster >/dev/null; then
        return 0
    else
        log_error "TaskMaster not available"
        return 1
    fi
}

execute_taskmaster_command() {
    local connection_id="$1"
    local command="$2"
    
    taskmaster $command
}

# OpenSpec connection handling
initialize_openspec_connection() {
    local connection_id="$1"
    
    # Check if OpenSpec is available
    if command -v openspec >/dev/null; then
        return 0
    else
        log_error "OpenSpec not available"
        return 1
    fi
}

execute_openspec_command() {
    local connection_id="$1"
    local command="$2"
    
    openspec $command
}

# JQ command execution
execute_jq_command() {
    local connection_id="$1"
    local command="$2"
    
    eval "jq $command"
}

# Curl command execution
execute_curl_command() {
    local connection_id="$1"
    local command="$2"
    
    eval "curl $command"
}

# Generic command execution
execute_generic_command() {
    local connection_id="$1"
    local service_type="$2"
    local command="$3"
    
    eval "$service_type $command"
}

# =============================================================================
# Health Monitoring
# =============================================================================

# Start health monitoring
start_health_monitoring() {
    while [[ -f "$POOL_STATE_FILE" ]]; do
        perform_health_checks
        cleanup_expired_connections
        sleep "$POOL_HEALTH_CHECK_INTERVAL"
    done
}

# Perform health checks on all services
perform_health_checks() {
    for service in "${!SERVICE_CONFIGS[@]}"; do
        pool_health_check "$service" &
    done
    wait
}

# Health check for specific service
pool_health_check() {
    local service_type="$1"
    
    profile_start "pool_health_check:$service_type"
    
    local health_cmd=$(get_service_health_command "$service_type")
    local health_status="healthy"
    
    if [[ -n "$health_cmd" ]]; then
        if ! eval "$health_cmd" >/dev/null 2>&1; then
            health_status="unhealthy"
            record_connection_failure "$service_type"
        fi
    fi
    
    # Store health status
    eval "${CONNECTION_HEALTH_PREFIX}${service_type}=\"$health_status\""
    eval "${CONNECTION_HEALTH_PREFIX}${service_type}_last_check=\"$(date +%s)\""
    
    local duration=$(profile_end "pool_health_check:$service_type")
    log_debug "Health check completed" "service=$service_type" "status=$health_status" "duration_ms=$duration"
    
    [[ "$health_status" == "healthy" ]]
}

# Cleanup expired connections
cleanup_expired_connections() {
    local current_time=$(date +%s)
    local expired_connections=()
    
    # Find expired connections
    local IFS='|'
    for connection_id in $ACTIVE_CONNECTIONS; do
        if [[ -n "$connection_id" ]]; then
            local created_at
            eval "created_at=\${${CONNECTION_METADATA_PREFIX}${connection_id}_created_at:-0}"
            
            if [[ $((current_time - created_at)) -gt $POOL_CONNECTION_TTL ]]; then
                expired_connections+=("$connection_id")
            fi
        fi
    done
    
    # Close expired connections
    for connection_id in "${expired_connections[@]}"; do
        close_connection "$connection_id"
    done
    
    if [[ ${#expired_connections[@]} -gt 0 ]]; then
        log_debug "Expired connections cleaned up" "count=${#expired_connections[@]}"
    fi
}

# Close specific connection
close_connection() {
    local connection_id="$1"
    
    # Remove from active connections
    ACTIVE_CONNECTIONS=$(echo "$ACTIVE_CONNECTIONS" | sed "s/|${connection_id}|//g")
    
    # Clean up metadata
    local meta_vars=$(set | grep "^${CONNECTION_METADATA_PREFIX}${connection_id}_" | cut -d= -f1)
    for var in $meta_vars; do
        unset "$var"
    done
    
    log_debug "Connection closed" "connection=$connection_id"
}

# =============================================================================
# Circuit Breaker Pattern
# =============================================================================

# Check if circuit breaker is open
is_circuit_open() {
    local service_type="$1"
    local current_time=$(date +%s)
    
    local circuit_state
    local circuit_opened_at
    local failure_count
    
    eval "circuit_state=\${${CONNECTION_CIRCUIT_PREFIX}${service_type}_state:-closed}"
    eval "circuit_opened_at=\${${CONNECTION_CIRCUIT_PREFIX}${service_type}_opened_at:-0}"
    eval "failure_count=\${${CONNECTION_CIRCUIT_PREFIX}${service_type}_failures:-0}"
    
    case "$circuit_state" in
        open)
            # Check if timeout has passed
            if [[ $((current_time - circuit_opened_at)) -gt $POOL_CIRCUIT_BREAKER_TIMEOUT ]]; then
                # Move to half-open state
                eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_state=\"half-open\""
                log_info "Circuit breaker moved to half-open" "service=$service_type"
                return 1  # Allow one request
            else
                return 0  # Circuit is open
            fi
            ;;
        half-open)
            return 1  # Allow request to test
            ;;
        *)
            return 1  # Circuit is closed
            ;;
    esac
}

# Record connection failure
record_connection_failure() {
    local service_type="$1"
    local current_time=$(date +%s)
    
    local failure_count
    eval "failure_count=\${${CONNECTION_CIRCUIT_PREFIX}${service_type}_failures:-0}"
    failure_count=$((failure_count + 1))
    
    eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_failures=\"$failure_count\""
    eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_last_failure=\"$current_time\""
    
    # Check if we should open the circuit
    if [[ $failure_count -ge $POOL_CIRCUIT_BREAKER_THRESHOLD ]]; then
        eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_state=\"open\""
        eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_opened_at=\"$current_time\""
        log_warn "Circuit breaker opened" "service=$service_type" "failures=$failure_count"
    fi
    
    log_metric "connection_failure" "1" "service=$service_type" "failures=$failure_count"
}

# Record successful operation (reset circuit breaker)
record_connection_success() {
    local service_type="$1"
    
    eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_failures=\"0\""
    eval "${CONNECTION_CIRCUIT_PREFIX}${service_type}_state=\"closed\""
    
    log_debug "Circuit breaker reset" "service=$service_type"
}

# =============================================================================
# Retry Logic
# =============================================================================

# Execute command with retry logic
pool_execute_with_retry() {
    local service_type="$1"
    local command="$2"
    local context="${3:-default}"
    local max_attempts="${4:-$POOL_RETRY_MAX_ATTEMPTS}"
    
    local attempt=1
    local delay=$POOL_RETRY_BASE_DELAY
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempting command execution" "service=$service_type" "attempt=$attempt"
        
        if pool_execute_command "$service_type" "$command" "$context"; then
            record_connection_success "$service_type"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_debug "Command failed, retrying" "service=$service_type" "attempt=$attempt" "delay=${delay}s"
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after all retry attempts" "service=$service_type" "attempts=$max_attempts"
    return 1
}

# =============================================================================
# Utility Functions
# =============================================================================

# Get service connections
get_service_connections() {
    local service_type="$1"
    local connections=""
    
    local IFS='|'
    for connection_id in $ACTIVE_CONNECTIONS; do
        if [[ -n "$connection_id" ]]; then
            local conn_service
            eval "conn_service=\${${CONNECTION_METADATA_PREFIX}${connection_id}_service:-}"
            if [[ "$conn_service" == "$service_type" ]]; then
                connections="$connections $connection_id"
            fi
        fi
    done
    
    echo "$connections"
}

# Count service connections
count_service_connections() {
    local service_type="$1"
    local connections=$(get_service_connections "$service_type")
    echo "$connections" | wc -w
}

# Get service configuration
get_service_max_connections() {
    local service_type="$1"
    local config="${SERVICE_CONFIGS[$service_type]:-}"
    
    if [[ -n "$config" ]]; then
        echo "$config" | grep -o 'max_conn=[0-9]*' | cut -d= -f2
    else
        echo "$POOL_MAX_CONNECTIONS"
    fi
}

get_service_health_command() {
    local service_type="$1"
    local config="${SERVICE_CONFIGS[$service_type]:-}"
    
    if [[ -n "$config" ]]; then
        echo "$config" | grep -o 'health_cmd=[^;]*' | cut -d= -f2-
    fi
}

# Record command execution metrics
record_command_execution() {
    local service_type="$1"
    local response_time_ms="$2"
    local exit_code="$3"
    
    log_metric "pool_command_execution" "$response_time_ms" \
        "service=$service_type" \
        "exit_code=$exit_code"
}

# Prewarm connections
prewarm_connections() {
    log_debug "Prewarming connections"
    
    # Prewarm critical services
    local critical_services=("git" "jq")
    
    for service in "${critical_services[@]}"; do
        if [[ -n "${SERVICE_CONFIGS[$service]:-}" ]]; then
            create_new_connection "$service" "prewarm" >/dev/null &
        fi
    done
    
    wait
    log_debug "Connection prewarming completed"
}

# =============================================================================
# Statistics and Monitoring
# =============================================================================

# Get pool statistics
pool_stats() {
    local total_connections=$(echo "$ACTIVE_CONNECTIONS" | tr -cd '|' | wc -c)
    local active_count=0
    local available_count=0
    
    # Count active vs available connections
    local IFS='|'
    for connection_id in $ACTIVE_CONNECTIONS; do
        if [[ -n "$connection_id" ]]; then
            local status
            eval "status=\${${CONNECTION_METADATA_PREFIX}${connection_id}_status:-}"
            case "$status" in
                active) active_count=$((active_count + 1)) ;;
                available) available_count=$((available_count + 1)) ;;
            esac
        fi
    done
    
    echo "Connection Pool Statistics:"
    echo "  Enabled: $POOL_ENABLED"
    echo "  Total Connections: $total_connections"
    echo "  Active Connections: $active_count"
    echo "  Available Connections: $available_count"
    echo "  Max Connections: $POOL_MAX_CONNECTIONS"
    echo "  Connection TTL: ${POOL_CONNECTION_TTL}s"
    echo "  Health Check Interval: ${POOL_HEALTH_CHECK_INTERVAL}s"
    
    echo ""
    echo "Service Health:"
    for service in "${!SERVICE_CONFIGS[@]}"; do
        local health_status
        eval "health_status=\${${CONNECTION_HEALTH_PREFIX}${service}:-unknown}"
        echo "  $service: $health_status"
    done
}

# Close all connections
pool_close_all_connections() {
    log_info "Closing all connections"
    
    local IFS='|'
    for connection_id in $ACTIVE_CONNECTIONS; do
        if [[ -n "$connection_id" ]]; then
            close_connection "$connection_id"
        fi
    done
    
    ACTIVE_CONNECTIONS=""
    
    # Stop health monitoring
    if [[ -n "${POOL_HEALTH_MONITOR_PID:-}" ]]; then
        kill "$POOL_HEALTH_MONITOR_PID" 2>/dev/null || true
    fi
    
    log_info "All connections closed"
}

# =============================================================================
# Initialization and Cleanup
# =============================================================================

# Auto-initialize
if [[ "${CONNECTION_POOL_INITIALIZED:-}" != "true" ]]; then
    if [[ "$POOL_ENABLED" == "true" ]]; then
        pool_init
        
        # Set up cleanup on exit
        trap 'pool_close_all_connections' EXIT
    fi
    
    export CONNECTION_POOL_INITIALIZED=true
fi