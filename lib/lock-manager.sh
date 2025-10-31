#!/bin/bash
# =============================================================================
# Lock Management System - Claude Dev Pipeline
# =============================================================================
# 
# Central lock management for all pipeline operations:
# - Timeout-based lock acquisition
# - Stale lock detection and cleanup
# - Lock hierarchy to prevent deadlocks
# - Support for shared (read) and exclusive (write) locks
# - Process-aware lock validation
#
# =============================================================================

set -euo pipefail

# Configuration
readonly LOCK_MANAGER_VERSION="1.0.0"
readonly DEFAULT_TIMEOUT=30
readonly STALE_LOCK_THRESHOLD=300  # 5 minutes
readonly MAX_LOCK_WAIT=120         # 2 minutes
readonly LOCK_CHECK_INTERVAL=0.1   # 100ms

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOCK_DIR="$PIPELINE_ROOT/.locks"
readonly AUDIT_LOG="${AUDIT_LOG:-/tmp/claude-pipeline-audit.log}"

# Lock hierarchy (lower numbers have higher priority)
# Using functions instead of associative arrays for macOS compatibility
get_lock_priority() {
    local lock_name="$1"
    case "$lock_name" in
        "state") echo "1" ;;
        "config") echo "2" ;;
        "signals") echo "3" ;;
        "backup") echo "4" ;;
        "temp") echo "5" ;;
        "user") echo "10" ;;
        *) echo "999" ;;
    esac
}

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"
chmod 750 "$LOCK_DIR"

# Current process locks (for cleanup)
HELD_LOCKS=()

# Logging function
log_audit() {
    local level="$1"
    local component="$2"
    local message="$3"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [$level] lock-manager/$component: $message" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_no=$1
    log_audit "ERROR" "handler" "Error on line $line_no: exit code $exit_code"
    cleanup_held_locks
    exit $exit_code
}

trap 'handle_error $LINENO' ERR
trap 'cleanup_held_locks' EXIT

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get process start time for lock validation
get_process_start_time() {
    local pid="$1"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    
    # Get process start time (platform-specific)
    if command -v stat >/dev/null 2>&1; then
        # macOS/BSD stat
        stat -f %B "/proc/$pid" 2>/dev/null || echo "0"
    elif [ -f "/proc/$pid/stat" ]; then
        # Linux
        awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo "0"
    else
        # Fallback - current time
        date +%s
    fi
}

# Check if process is still running
is_process_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

# Get lock priority (already defined above)

# Cleanup locks held by current process
cleanup_held_locks() {
    if [ ${#HELD_LOCKS[@]} -gt 0 ]; then
        for lock_name in "${HELD_LOCKS[@]}"; do
            release_lock "$lock_name" 2>/dev/null || true
        done
    fi
    HELD_LOCKS=()
}

# Add lock to held locks list
add_held_lock() {
    local lock_name="$1"
    HELD_LOCKS+=("$lock_name")
}

# Remove lock from held locks list
remove_held_lock() {
    local lock_name="$1"
    local temp_array=()
    
    if [ ${#HELD_LOCKS[@]} -gt 0 ]; then
        for held_lock in "${HELD_LOCKS[@]}"; do
            if [ "$held_lock" != "$lock_name" ]; then
                temp_array+=("$held_lock")
            fi
        done
    fi
    
    HELD_LOCKS=("${temp_array[@]}")
}

# =============================================================================
# LOCK FILE OPERATIONS
# =============================================================================

# Create lock file with metadata
create_lock_file() {
    local lock_file="$1"
    local lock_type="$2"
    local metadata="$3"
    
    local lock_data="{
        \"pid\": $$,
        \"type\": \"$lock_type\",
        \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
        \"process_start\": \"$(get_process_start_time $$)\",
        \"hostname\": \"$(hostname)\",
        \"metadata\": $metadata
    }"
    
    echo "$lock_data" > "$lock_file"
}

# Read lock file metadata
read_lock_file() {
    local lock_file="$1"
    
    if [ ! -f "$lock_file" ]; then
        return 1
    fi
    
    cat "$lock_file" 2>/dev/null || return 1
}

# Validate lock file
validate_lock_file() {
    local lock_file="$1"
    local lock_data
    
    if ! lock_data=$(read_lock_file "$lock_file"); then
        return 1
    fi
    
    # Validate JSON
    if ! echo "$lock_data" | jq empty 2>/dev/null; then
        log_audit "WARN" "validation" "Invalid JSON in lock file: $(basename "$lock_file")"
        return 1
    fi
    
    # Extract and validate PID
    local pid
    pid=$(echo "$lock_data" | jq -r '.pid // empty' 2>/dev/null)
    
    if [ -z "$pid" ] || ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        log_audit "WARN" "validation" "Invalid PID in lock file: $(basename "$lock_file")"
        return 1
    fi
    
    # Check if process is still alive
    if ! is_process_alive "$pid"; then
        log_audit "WARN" "validation" "Process $pid is dead, lock is stale: $(basename "$lock_file")"
        return 1
    fi
    
    return 0
}

# =============================================================================
# DEADLOCK PREVENTION
# =============================================================================

# Check for potential deadlocks
check_deadlock_risk() {
    local requested_lock="$1"
    local requested_priority
    requested_priority=$(get_lock_priority "$requested_lock")
    
    # Check currently held locks
    if [ ${#HELD_LOCKS[@]} -gt 0 ]; then
        for held_lock in "${HELD_LOCKS[@]}"; do
            local held_priority
            held_priority=$(get_lock_priority "$held_lock")
            
            # If requesting a higher priority lock while holding lower priority
            if [ "$requested_priority" -lt "$held_priority" ]; then
                log_audit "WARN" "deadlock" "Potential deadlock: requesting $requested_lock (priority $requested_priority) while holding $held_lock (priority $held_priority)"
                return 1
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# STALE LOCK MANAGEMENT
# =============================================================================

# Check if lock is stale
is_lock_stale() {
    local lock_file="$1"
    local current_time=$(date +%s)
    local lock_time
    
    # Get file modification time
    if lock_time=$(stat -f %m "$lock_file" 2>/dev/null); then
        local age=$((current_time - lock_time))
        
        if [ $age -gt $STALE_LOCK_THRESHOLD ]; then
            return 0  # Lock is stale
        fi
    fi
    
    return 1  # Lock is not stale
}

# Clean up stale locks
clean_stale_locks() {
    local cleaned=0
    
    log_audit "INFO" "cleanup" "Starting stale lock cleanup"
    
    for lock_file in "$LOCK_DIR"/*.lock; do
        [ -f "$lock_file" ] || continue
        
        local lock_name
        lock_name=$(basename "$lock_file" .lock)
        
        if is_lock_stale "$lock_file"; then
            if ! validate_lock_file "$lock_file"; then
                log_audit "INFO" "cleanup" "Removing stale lock: $lock_name"
                rm -f "$lock_file" 2>/dev/null || true
                ((cleaned++))
            fi
        fi
    done
    
    log_audit "INFO" "cleanup" "Cleaned up $cleaned stale locks"
    return 0
}

# =============================================================================
# CORE LOCK FUNCTIONS
# =============================================================================

# Acquire lock (exclusive by default)
acquire_lock() {
    local lock_name="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    local lock_type="${3:-exclusive}"
    local metadata="${4:-{}}"
    
    # Validate inputs
    if [ -z "$lock_name" ]; then
        log_audit "ERROR" "acquire" "Lock name is required"
        return 1
    fi
    
    # Validate metadata JSON
    if ! echo "$metadata" | jq empty 2>/dev/null; then
        log_audit "WARN" "acquire" "Invalid metadata JSON, using empty object"
        metadata="{}"
    fi
    
    # Check deadlock risk
    if ! check_deadlock_risk "$lock_name"; then
        log_audit "ERROR" "acquire" "Deadlock risk detected for lock: $lock_name"
        return 1
    fi
    
    local lock_file="$LOCK_DIR/${lock_name}.lock"
    local start_time=$(date +%s)
    local attempts=0
    
    log_audit "DEBUG" "acquire" "Attempting to acquire $lock_type lock: $lock_name"
    
    while true; do
        ((attempts++))
        
        # Try to acquire lock atomically
        if (set -C; create_lock_file "$lock_file" "$lock_type" "$metadata") 2>/dev/null; then
            add_held_lock "$lock_name"
            log_audit "INFO" "acquire" "Lock acquired: $lock_name (type: $lock_type, attempts: $attempts)"
            return 0
        fi
        
        # Check if existing lock is valid
        if ! validate_lock_file "$lock_file"; then
            log_audit "INFO" "acquire" "Removing invalid lock: $lock_name"
            rm -f "$lock_file" 2>/dev/null || true
            continue
        fi
        
        # Handle shared locks
        if [ "$lock_type" = "shared" ]; then
            local existing_type
            existing_type=$(read_lock_file "$lock_file" | jq -r '.type // "exclusive"' 2>/dev/null)
            
            if [ "$existing_type" = "shared" ]; then
                # Can acquire shared lock if existing is also shared
                # Create a shared lock file with different name
                local shared_lock_file="$LOCK_DIR/${lock_name}.shared.$$"
                if create_lock_file "$shared_lock_file" "$lock_type" "$metadata" 2>/dev/null; then
                    add_held_lock "${lock_name}.shared.$$"
                    log_audit "INFO" "acquire" "Shared lock acquired: $lock_name (attempts: $attempts)"
                    return 0
                fi
            fi
        fi
        
        # Check timeout
        local elapsed=$(( $(date +%s) - start_time ))
        if [ $elapsed -ge $timeout ]; then
            log_audit "ERROR" "acquire" "Lock acquisition timeout after ${timeout}s: $lock_name (attempts: $attempts)"
            return 1
        fi
        
        # Exponential backoff with jitter
        local wait_time
        wait_time=$(echo "scale=2; $LOCK_CHECK_INTERVAL * (1.5 ^ ($attempts % 10)) + ($RANDOM % 100) / 1000" | bc 2>/dev/null || echo "$LOCK_CHECK_INTERVAL")
        sleep "$wait_time"
    done
}

# Release lock
release_lock() {
    local lock_name="$1"
    
    if [ -z "$lock_name" ]; then
        log_audit "ERROR" "release" "Lock name is required"
        return 1
    fi
    
    # Handle shared locks
    if [[ "$lock_name" == *.shared.* ]]; then
        local shared_lock_file="$LOCK_DIR/${lock_name}.lock"
        if [ -f "$shared_lock_file" ]; then
            rm -f "$shared_lock_file" 2>/dev/null || true
            remove_held_lock "$lock_name"
            log_audit "INFO" "release" "Shared lock released: $lock_name"
            return 0
        fi
    fi
    
    local lock_file="$LOCK_DIR/${lock_name}.lock"
    
    if [ ! -f "$lock_file" ]; then
        log_audit "WARN" "release" "Lock file does not exist: $lock_name"
        return 1
    fi
    
    # Validate ownership
    local lock_data
    if lock_data=$(read_lock_file "$lock_file"); then
        local lock_pid
        lock_pid=$(echo "$lock_data" | jq -r '.pid // empty' 2>/dev/null)
        
        if [ "$lock_pid" != "$$" ]; then
            log_audit "ERROR" "release" "Cannot release lock owned by different process: $lock_name (owner: $lock_pid, current: $$)"
            return 1
        fi
    fi
    
    if rm -f "$lock_file" 2>/dev/null; then
        remove_held_lock "$lock_name"
        log_audit "INFO" "release" "Lock released: $lock_name"
        return 0
    else
        log_audit "ERROR" "release" "Failed to remove lock file: $lock_name"
        return 1
    fi
}

# Check lock status
check_lock() {
    local lock_name="$1"
    local lock_file="$LOCK_DIR/${lock_name}.lock"
    
    if [ ! -f "$lock_file" ]; then
        echo "unlocked"
        return 1
    fi
    
    if validate_lock_file "$lock_file"; then
        local lock_data
        lock_data=$(read_lock_file "$lock_file")
        local lock_type
        lock_type=$(echo "$lock_data" | jq -r '.type // "exclusive"' 2>/dev/null)
        local lock_pid
        lock_pid=$(echo "$lock_data" | jq -r '.pid // empty' 2>/dev/null)
        
        echo "locked:$lock_type:$lock_pid"
        return 0
    else
        echo "stale"
        return 2
    fi
}

# List all locks
list_locks() {
    local format="${1:-table}"
    
    if [ "$format" = "json" ]; then
        echo "["
        local first=true
        for lock_file in "$LOCK_DIR"/*.lock; do
            [ -f "$lock_file" ] || continue
            
            local lock_name
            lock_name=$(basename "$lock_file" .lock)
            
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            
            local lock_data
            if lock_data=$(read_lock_file "$lock_file"); then
                echo "$lock_data" | jq --arg name "$lock_name" '. + {name: $name}'
            else
                echo "{\"name\": \"$lock_name\", \"status\": \"invalid\"}"
            fi
        done
        echo "]"
    else
        printf "%-20s %-10s %-8s %-20s %-10s\n" "LOCK NAME" "TYPE" "PID" "TIMESTAMP" "STATUS"
        printf "%-20s %-10s %-8s %-20s %-10s\n" "----------" "----" "---" "---------" "------"
        
        for lock_file in "$LOCK_DIR"/*.lock; do
            [ -f "$lock_file" ] || continue
            
            local lock_name
            lock_name=$(basename "$lock_file" .lock)
            
            if validate_lock_file "$lock_file"; then
                local lock_data
                lock_data=$(read_lock_file "$lock_file")
                local lock_type
                lock_type=$(echo "$lock_data" | jq -r '.type // "exclusive"' 2>/dev/null)
                local lock_pid
                lock_pid=$(echo "$lock_data" | jq -r '.pid // empty' 2>/dev/null)
                local timestamp
                timestamp=$(echo "$lock_data" | jq -r '.timestamp // ""' 2>/dev/null)
                
                printf "%-20s %-10s %-8s %-20s %-10s\n" "$lock_name" "$lock_type" "$lock_pid" "$timestamp" "VALID"
            else
                printf "%-20s %-10s %-8s %-20s %-10s\n" "$lock_name" "unknown" "unknown" "unknown" "STALE"
            fi
        done
    fi
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

# Main function for direct script usage
main() {
    local command="${1:-status}"
    
    case "$command" in
        "acquire")
            local lock_name="${2:-}"
            local timeout="${3:-$DEFAULT_TIMEOUT}"
            local lock_type="${4:-exclusive}"
            local metadata="${5:-{}}"
            
            if [ -z "$lock_name" ]; then
                echo "Usage: $0 acquire <lock_name> [timeout] [type] [metadata]"
                exit 1
            fi
            
            if acquire_lock "$lock_name" "$timeout" "$lock_type" "$metadata"; then
                echo "Lock acquired: $lock_name"
            else
                echo "Failed to acquire lock: $lock_name"
                exit 1
            fi
            ;;
        "release")
            local lock_name="${2:-}"
            
            if [ -z "$lock_name" ]; then
                echo "Usage: $0 release <lock_name>"
                exit 1
            fi
            
            if release_lock "$lock_name"; then
                echo "Lock released: $lock_name"
            else
                echo "Failed to release lock: $lock_name"
                exit 1
            fi
            ;;
        "check")
            local lock_name="${2:-}"
            
            if [ -z "$lock_name" ]; then
                echo "Usage: $0 check <lock_name>"
                exit 1
            fi
            
            local status
            status=$(check_lock "$lock_name")
            echo "$status"
            ;;
        "list")
            local format="${2:-table}"
            list_locks "$format"
            ;;
        "clean")
            clean_stale_locks
            ;;
        "status")
            echo "Lock Manager Status"
            echo "=================="
            echo "Version: $LOCK_MANAGER_VERSION"
            echo "Lock Directory: $LOCK_DIR"
            echo "Active Locks: $(find "$LOCK_DIR" -name "*.lock" -type f 2>/dev/null | wc -l | tr -d ' ')"
            echo "Held by Process: ${#HELD_LOCKS[@]}"
            echo ""
            list_locks table
            ;;
        *)
            echo "Usage: $0 {acquire|release|check|list|clean|status}"
            echo ""
            echo "Commands:"
            echo "  acquire <name> [timeout] [type] [metadata] - Acquire lock"
            echo "  release <name>                             - Release lock"
            echo "  check <name>                               - Check lock status"
            echo "  list [format]                              - List all locks"
            echo "  clean                                      - Clean stale locks"
            echo "  status                                     - Show manager status"
            echo ""
            echo "Lock Types: exclusive (default), shared"
            echo "List Formats: table (default), json"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi