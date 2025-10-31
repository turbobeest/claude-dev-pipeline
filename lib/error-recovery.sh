#!/bin/bash
# =============================================================================
# Error Recovery System - Claude Dev Pipeline
# =============================================================================
# 
# Implements comprehensive error recovery with:
# - Checkpoint system for phase transitions
# - Retry logic with exponential backoff
# - Rollback capabilities for each phase
# - Error code system for debugging
# - Graceful degradation for non-critical failures
# - Recovery suggestions for common errors
#
# =============================================================================

set -euo pipefail

# Configuration
readonly ERROR_RECOVERY_VERSION="1.0.0"
readonly MAX_RETRIES=3
readonly BASE_RETRY_DELAY=1
readonly MAX_RETRY_DELAY=60
readonly CHECKPOINT_RETENTION_DAYS=7

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CHECKPOINT_DIR="$PIPELINE_ROOT/.checkpoints"
readonly ERROR_LOG="$PIPELINE_ROOT/.error-recovery.log"
readonly AUDIT_LOG="${AUDIT_LOG:-/tmp/claude-pipeline-audit.log}"

# Load dependencies
source "$SCRIPT_DIR/state-manager.sh"
source "$SCRIPT_DIR/lock-manager.sh"

# Error codes
declare -A ERROR_CODES=(
    ["SUCCESS"]=0
    ["GENERAL_ERROR"]=1
    ["LOCK_TIMEOUT"]=2
    ["STATE_CORRUPTION"]=3
    ["VALIDATION_FAILED"]=4
    ["DEPENDENCY_MISSING"]=5
    ["PERMISSION_DENIED"]=6
    ["DISK_FULL"]=7
    ["NETWORK_ERROR"]=8
    ["TIMEOUT"]=9
    ["RESOURCE_EXHAUSTED"]=10
    ["CONFIGURATION_ERROR"]=11
    ["DATA_INTEGRITY"]=12
    ["SERVICE_UNAVAILABLE"]=13
    ["AUTHENTICATION_ERROR"]=14
    ["AUTHORIZATION_ERROR"]=15
)

# Recovery strategies
declare -A RECOVERY_STRATEGIES=(
    ["LOCK_TIMEOUT"]="clean_stale_locks"
    ["STATE_CORRUPTION"]="recover_state"
    ["VALIDATION_FAILED"]="restore_checkpoint"
    ["DISK_FULL"]="cleanup_temp_files"
    ["TIMEOUT"]="retry_with_backoff"
    ["RESOURCE_EXHAUSTED"]="wait_and_retry"
    ["CONFIGURATION_ERROR"]="reset_config"
    ["DATA_INTEGRITY"]="restore_from_backup"
)

# Ensure required directories exist
mkdir -p "$CHECKPOINT_DIR"
chmod 750 "$CHECKPOINT_DIR"

# Current operation context
declare -g CURRENT_OPERATION=""
declare -g CURRENT_PHASE=""
declare -g CHECKPOINT_ID=""

# Logging function
log_error() {
    local level="$1"
    local component="$2"
    local message="$3"
    local error_code="${4:-1}"
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Log to error recovery log
    echo "$timestamp [$level] error-recovery/$component: $message (code: $error_code)" >> "$ERROR_LOG"
    
    # Log to audit log
    echo "$timestamp [$level] error-recovery/$component: $message" >> "$AUDIT_LOG" 2>/dev/null || true
}

# =============================================================================
# CHECKPOINT MANAGEMENT
# =============================================================================

# Create checkpoint before critical operations
create_checkpoint() {
    local operation="$1"
    local phase="${2:-unknown}"
    local metadata="${3:-{}}"
    
    # Validate inputs
    if [ -z "$operation" ]; then
        log_error "ERROR" "checkpoint" "Operation name is required for checkpoint" "${ERROR_CODES[GENERAL_ERROR]}"
        return 1
    fi
    
    # Generate checkpoint ID
    CHECKPOINT_ID="checkpoint-$(date +%Y%m%d-%H%M%S)-$operation"
    local checkpoint_dir="$CHECKPOINT_DIR/$CHECKPOINT_ID"
    
    log_error "INFO" "checkpoint" "Creating checkpoint for operation: $operation"
    
    if ! mkdir -p "$checkpoint_dir"; then
        log_error "ERROR" "checkpoint" "Failed to create checkpoint directory" "${ERROR_CODES[PERMISSION_DENIED]}"
        return 1
    fi
    
    # Save current state
    if ! read_state > "$checkpoint_dir/state.json"; then
        log_error "ERROR" "checkpoint" "Failed to save state to checkpoint" "${ERROR_CODES[STATE_CORRUPTION]}"
        return 1
    fi
    
    # Save configuration files
    if [ -d "$PIPELINE_ROOT/config" ]; then
        cp -r "$PIPELINE_ROOT/config" "$checkpoint_dir/" 2>/dev/null || true
    fi
    
    # Save signals
    if [ -d "$PIPELINE_ROOT/.signals" ]; then
        cp -r "$PIPELINE_ROOT/.signals" "$checkpoint_dir/" 2>/dev/null || true
    fi
    
    # Create checkpoint metadata
    local checkpoint_metadata="{
        \"id\": \"$CHECKPOINT_ID\",
        \"operation\": \"$operation\",
        \"phase\": \"$phase\",
        \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
        \"pid\": $$,
        \"hostname\": \"$(hostname)\",
        \"metadata\": $metadata
    }"
    
    echo "$checkpoint_metadata" > "$checkpoint_dir/metadata.json"
    
    # Set context
    CURRENT_OPERATION="$operation"
    CURRENT_PHASE="$phase"
    
    log_error "INFO" "checkpoint" "Checkpoint created: $CHECKPOINT_ID"
    return 0
}

# Restore from checkpoint
restore_checkpoint() {
    local checkpoint_id="${1:-$CHECKPOINT_ID}"
    
    if [ -z "$checkpoint_id" ]; then
        log_error "ERROR" "restore" "No checkpoint ID specified" "${ERROR_CODES[GENERAL_ERROR]}"
        return 1
    fi
    
    local checkpoint_dir="$CHECKPOINT_DIR/$checkpoint_id"
    
    if [ ! -d "$checkpoint_dir" ]; then
        log_error "ERROR" "restore" "Checkpoint not found: $checkpoint_id" "${ERROR_CODES[GENERAL_ERROR]}"
        return 1
    fi
    
    log_error "INFO" "restore" "Restoring from checkpoint: $checkpoint_id"
    
    # Acquire state lock for restoration
    if ! acquire_lock "state" 60 "exclusive" '{"operation": "checkpoint_restore"}'; then
        log_error "ERROR" "restore" "Failed to acquire state lock for restoration" "${ERROR_CODES[LOCK_TIMEOUT]}"
        return 1
    fi
    
    # Restore state
    if [ -f "$checkpoint_dir/state.json" ]; then
        if validate_state "$checkpoint_dir/state.json"; then
            cp "$checkpoint_dir/state.json" "$PIPELINE_ROOT/.workflow-state.json"
            log_error "INFO" "restore" "State restored from checkpoint"
        else
            log_error "ERROR" "restore" "Checkpoint state is invalid" "${ERROR_CODES[DATA_INTEGRITY]}"
            release_lock "state"
            return 1
        fi
    fi
    
    # Restore configuration
    if [ -d "$checkpoint_dir/config" ]; then
        rm -rf "$PIPELINE_ROOT/config" 2>/dev/null || true
        cp -r "$checkpoint_dir/config" "$PIPELINE_ROOT/"
        log_error "INFO" "restore" "Configuration restored from checkpoint"
    fi
    
    # Restore signals
    if [ -d "$checkpoint_dir/.signals" ]; then
        rm -rf "$PIPELINE_ROOT/.signals" 2>/dev/null || true
        cp -r "$checkpoint_dir/.signals" "$PIPELINE_ROOT/"
        log_error "INFO" "restore" "Signals restored from checkpoint"
    fi
    
    release_lock "state"
    
    log_error "INFO" "restore" "Checkpoint restoration completed: $checkpoint_id"
    return 0
}

# List available checkpoints
list_checkpoints() {
    local format="${1:-table}"
    
    if [ "$format" = "json" ]; then
        echo "["
        local first=true
        for checkpoint_dir in "$CHECKPOINT_DIR"/checkpoint-*; do
            [ -d "$checkpoint_dir" ] || continue
            
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            
            if [ -f "$checkpoint_dir/metadata.json" ]; then
                cat "$checkpoint_dir/metadata.json"
            else
                echo "{\"id\": \"$(basename "$checkpoint_dir")\", \"status\": \"invalid\"}"
            fi
        done
        echo "]"
    else
        printf "%-30s %-15s %-15s %-20s\n" "CHECKPOINT ID" "OPERATION" "PHASE" "TIMESTAMP"
        printf "%-30s %-15s %-15s %-20s\n" "-------------" "---------" "-----" "---------"
        
        for checkpoint_dir in "$CHECKPOINT_DIR"/checkpoint-*; do
            [ -d "$checkpoint_dir" ] || continue
            
            local checkpoint_id
            checkpoint_id=$(basename "$checkpoint_dir")
            
            if [ -f "$checkpoint_dir/metadata.json" ]; then
                local metadata
                metadata=$(cat "$checkpoint_dir/metadata.json")
                local operation
                operation=$(echo "$metadata" | jq -r '.operation // "unknown"' 2>/dev/null)
                local phase
                phase=$(echo "$metadata" | jq -r '.phase // "unknown"' 2>/dev/null)
                local timestamp
                timestamp=$(echo "$metadata" | jq -r '.timestamp // ""' 2>/dev/null)
                
                printf "%-30s %-15s %-15s %-20s\n" "$checkpoint_id" "$operation" "$phase" "$timestamp"
            else
                printf "%-30s %-15s %-15s %-20s\n" "$checkpoint_id" "unknown" "unknown" "invalid"
            fi
        done
    fi
}

# Cleanup old checkpoints
cleanup_checkpoints() {
    local retention_days="${1:-$CHECKPOINT_RETENTION_DAYS}"
    local cleaned=0
    
    log_error "INFO" "cleanup" "Cleaning up checkpoints older than $retention_days days"
    
    find "$CHECKPOINT_DIR" -name "checkpoint-*" -type d -mtime +$retention_days | while read -r checkpoint_dir; do
        local checkpoint_id
        checkpoint_id=$(basename "$checkpoint_dir")
        
        rm -rf "$checkpoint_dir" 2>/dev/null && {
            log_error "INFO" "cleanup" "Removed old checkpoint: $checkpoint_id"
            ((cleaned++))
        }
    done
    
    log_error "INFO" "cleanup" "Cleaned up $cleaned old checkpoints"
    return 0
}

# =============================================================================
# RETRY LOGIC
# =============================================================================

# Execute operation with retry logic
retry_with_backoff() {
    local operation="$1"
    local max_retries="${2:-$MAX_RETRIES}"
    local base_delay="${3:-$BASE_RETRY_DELAY}"
    shift 3
    
    local attempt=1
    local delay=$base_delay
    
    while [ $attempt -le $max_retries ]; do
        log_error "INFO" "retry" "Attempt $attempt/$max_retries for operation: $operation"
        
        # Execute the operation
        if "$operation" "$@"; then
            log_error "INFO" "retry" "Operation succeeded on attempt $attempt: $operation"
            return 0
        fi
        
        local exit_code=$?
        log_error "WARN" "retry" "Operation failed on attempt $attempt: $operation (exit code: $exit_code)"
        
        # Check if we should retry based on error code
        if ! should_retry "$exit_code"; then
            log_error "ERROR" "retry" "Operation not retryable: $operation (exit code: $exit_code)"
            return $exit_code
        fi
        
        # Don't sleep after the last attempt
        if [ $attempt -lt $max_retries ]; then
            log_error "INFO" "retry" "Waiting ${delay}s before retry"
            sleep "$delay"
            
            # Exponential backoff with jitter
            delay=$(echo "scale=2; $delay * 1.5 + ($RANDOM % 100) / 100" | bc 2>/dev/null || echo "$MAX_RETRY_DELAY")
            if [ "$(echo "$delay > $MAX_RETRY_DELAY" | bc 2>/dev/null || echo 1)" = "1" ]; then
                delay=$MAX_RETRY_DELAY
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "ERROR" "retry" "Operation failed after $max_retries attempts: $operation"
    return $exit_code
}

# Determine if error code is retryable
should_retry() {
    local error_code="$1"
    
    case "$error_code" in
        "${ERROR_CODES[LOCK_TIMEOUT]}")     return 0 ;;
        "${ERROR_CODES[TIMEOUT]}")          return 0 ;;
        "${ERROR_CODES[NETWORK_ERROR]}")    return 0 ;;
        "${ERROR_CODES[RESOURCE_EXHAUSTED]}")  return 0 ;;
        "${ERROR_CODES[SERVICE_UNAVAILABLE]}")  return 0 ;;
        "${ERROR_CODES[DISK_FULL]}")        return 1 ;;
        "${ERROR_CODES[PERMISSION_DENIED]}") return 1 ;;
        "${ERROR_CODES[VALIDATION_FAILED]}") return 1 ;;
        *)                                   return 0 ;;
    esac
}

# =============================================================================
# ERROR HANDLING AND RECOVERY
# =============================================================================

# Handle error with automatic recovery
handle_error() {
    local error_code="$1"
    local error_message="$2"
    local operation="${3:-$CURRENT_OPERATION}"
    local auto_recover="${4:-true}"
    
    log_error "ERROR" "handler" "$error_message" "$error_code"
    
    # Try automatic recovery if enabled
    if [ "$auto_recover" = "true" ]; then
        local recovery_strategy=""
        
        # Find recovery strategy for error code
        for code_name in "${!ERROR_CODES[@]}"; do
            if [ "${ERROR_CODES[$code_name]}" = "$error_code" ]; then
                recovery_strategy="${RECOVERY_STRATEGIES[$code_name]:-}"
                break
            fi
        done
        
        if [ -n "$recovery_strategy" ]; then
            log_error "INFO" "recovery" "Attempting automatic recovery with strategy: $recovery_strategy"
            
            if "$recovery_strategy"; then
                log_error "INFO" "recovery" "Automatic recovery successful"
                return 0
            else
                log_error "ERROR" "recovery" "Automatic recovery failed"
            fi
        else
            log_error "WARN" "recovery" "No recovery strategy available for error code: $error_code"
        fi
    fi
    
    # Generate recovery suggestions
    generate_recovery_suggestions "$error_code" "$error_message" "$operation"
    
    return "$error_code"
}

# Generate recovery suggestions for common errors
generate_recovery_suggestions() {
    local error_code="$1"
    local error_message="$2"
    local operation="$3"
    
    echo ""
    echo "🔧 **RECOVERY SUGGESTIONS**"
    echo ""
    echo "Error Code: $error_code"
    echo "Operation: $operation"
    echo "Message: $error_message"
    echo ""
    
    case "$error_code" in
        "${ERROR_CODES[LOCK_TIMEOUT]}")
            echo "**Lock Timeout Recovery:**"
            echo "1. Check for deadlocked processes: ps aux | grep claude"
            echo "2. Clean stale locks: ./lib/lock-manager.sh clean"
            echo "3. Check system load: uptime"
            echo "4. Restart pipeline if necessary"
            ;;
        "${ERROR_CODES[STATE_CORRUPTION]}")
            echo "**State Corruption Recovery:**"
            echo "1. Restore from backup: ./lib/state-manager.sh recover"
            echo "2. Check available backups: ls -la .state-backups/"
            echo "3. Validate state file: ./lib/state-manager.sh validate"
            echo "4. Restore from checkpoint if available"
            ;;
        "${ERROR_CODES[DISK_FULL]}")
            echo "**Disk Full Recovery:**"
            echo "1. Check disk usage: df -h"
            echo "2. Clean temporary files: find /tmp -name 'claude-*' -delete"
            echo "3. Clean old logs: find . -name '*.log' -mtime +7 -delete"
            echo "4. Clean old backups: ./lib/state-manager.sh cleanup"
            ;;
        "${ERROR_CODES[PERMISSION_DENIED]}")
            echo "**Permission Denied Recovery:**"
            echo "1. Check file permissions: ls -la .workflow-state.json"
            echo "2. Fix permissions: chmod 600 .workflow-state.json"
            echo "3. Check directory permissions: ls -la ."
            echo "4. Ensure proper ownership: chown \$USER:staff ."
            ;;
        "${ERROR_CODES[DEPENDENCY_MISSING]}")
            echo "**Dependency Missing Recovery:**"
            echo "1. Check required tools: which jq flock bc"
            echo "2. Install missing dependencies"
            echo "3. Verify PATH: echo \$PATH"
            echo "4. Re-run setup: ./setup.sh"
            ;;
        *)
            echo "**General Recovery:**"
            echo "1. Check system resources: free -m && df -h"
            echo "2. Review error logs: tail -50 .error-recovery.log"
            echo "3. Restart pipeline from last checkpoint"
            echo "4. Contact support if issue persists"
            ;;
    esac
    
    echo ""
    echo "**Available Recovery Commands:**"
    echo "- Restore checkpoint: ./lib/error-recovery.sh restore <checkpoint-id>"
    echo "- List checkpoints: ./lib/error-recovery.sh list"
    echo "- Validate state: ./lib/state-manager.sh validate"
    echo "- Check locks: ./lib/lock-manager.sh status"
    echo ""
}

# =============================================================================
# GRACEFUL DEGRADATION
# =============================================================================

# Enable degraded mode for non-critical failures
enable_degraded_mode() {
    local reason="$1"
    local degraded_features="${2:-[]}"
    
    log_error "WARN" "degradation" "Enabling degraded mode: $reason"
    
    # Update state to indicate degraded mode
    local current_state
    if current_state=$(read_state); then
        local updated_state
        updated_state=$(echo "$current_state" | jq --arg reason "$reason" --argjson features "$degraded_features" '
            .degradedMode = {
                "enabled": true,
                "reason": $reason,
                "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
                "disabledFeatures": $features
            }
        ')
        
        if write_state "$updated_state" "degraded-mode"; then
            log_error "INFO" "degradation" "Degraded mode enabled successfully"
        else
            log_error "ERROR" "degradation" "Failed to enable degraded mode"
            return 1
        fi
    fi
    
    echo ""
    echo "⚠️ **DEGRADED MODE ENABLED**"
    echo ""
    echo "Reason: $reason"
    echo "Some features may be unavailable or operate with reduced functionality."
    echo "Normal operation will resume when the issue is resolved."
    echo ""
    
    return 0
}

# Disable degraded mode
disable_degraded_mode() {
    log_error "INFO" "degradation" "Disabling degraded mode"
    
    local current_state
    if current_state=$(read_state); then
        local updated_state
        updated_state=$(echo "$current_state" | jq 'del(.degradedMode)')
        
        if write_state "$updated_state" "normal-mode"; then
            log_error "INFO" "degradation" "Degraded mode disabled successfully"
            
            echo ""
            echo "✅ **NORMAL MODE RESTORED**"
            echo ""
            echo "All features are now available."
            echo ""
        else
            log_error "ERROR" "degradation" "Failed to disable degraded mode"
            return 1
        fi
    fi
    
    return 0
}

# Check if in degraded mode
is_degraded_mode() {
    local current_state
    if current_state=$(read_state); then
        echo "$current_state" | jq -r '.degradedMode.enabled // false'
    else
        echo "false"
    fi
}

# =============================================================================
# RECOVERY STRATEGIES
# =============================================================================

# Clean stale locks
clean_stale_locks() {
    log_error "INFO" "strategy" "Executing clean_stale_locks recovery strategy"
    
    # Use lock manager to clean stale locks
    if command -v "$SCRIPT_DIR/lock-manager.sh" >/dev/null; then
        "$SCRIPT_DIR/lock-manager.sh" clean
    else
        # Fallback: manual cleanup
        find "$PIPELINE_ROOT/.locks" -name "*.lock" -type f -mmin +30 -delete 2>/dev/null || true
    fi
    
    return 0
}

# Wait and retry for resource exhaustion
wait_and_retry() {
    log_error "INFO" "strategy" "Executing wait_and_retry recovery strategy"
    
    # Wait for resources to become available
    sleep 5
    
    # Check system resources
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    # If load is still high, wait more
    if [ "$(echo "$load_avg > 2.0" | bc 2>/dev/null || echo 0)" = "1" ]; then
        log_error "WARN" "strategy" "System load still high ($load_avg), waiting longer"
        sleep 10
    fi
    
    return 0
}

# Reset configuration to defaults
reset_config() {
    log_error "INFO" "strategy" "Executing reset_config recovery strategy"
    
    # Backup current config
    if [ -d "$PIPELINE_ROOT/config" ]; then
        mv "$PIPELINE_ROOT/config" "$PIPELINE_ROOT/config.backup.$(date +%s)" 2>/dev/null || true
    fi
    
    # Restore default config if available
    if [ -d "$PIPELINE_ROOT/config.default" ]; then
        cp -r "$PIPELINE_ROOT/config.default" "$PIPELINE_ROOT/config"
        log_error "INFO" "strategy" "Configuration reset to defaults"
    fi
    
    return 0
}

# Cleanup temporary files
cleanup_temp_files() {
    log_error "INFO" "strategy" "Executing cleanup_temp_files recovery strategy"
    
    # Clean pipeline temp files
    find "$PIPELINE_ROOT" -name "*.tmp" -type f -delete 2>/dev/null || true
    find "$PIPELINE_ROOT" -name "*.temp" -type f -delete 2>/dev/null || true
    
    # Clean system temp files
    find /tmp -name "claude-*" -user "$(whoami)" -delete 2>/dev/null || true
    
    # Clean old log files
    find "$PIPELINE_ROOT" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    return 0
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

# Main function for direct script usage
main() {
    local command="${1:-status}"
    
    case "$command" in
        "checkpoint")
            local operation="${2:-}"
            local phase="${3:-unknown}"
            local metadata="${4:-{}}"
            
            if [ -z "$operation" ]; then
                echo "Usage: $0 checkpoint <operation> [phase] [metadata]"
                exit 1
            fi
            
            if create_checkpoint "$operation" "$phase" "$metadata"; then
                echo "Checkpoint created: $CHECKPOINT_ID"
            else
                echo "Failed to create checkpoint"
                exit 1
            fi
            ;;
        "restore")
            local checkpoint_id="${2:-}"
            
            if [ -z "$checkpoint_id" ]; then
                echo "Usage: $0 restore <checkpoint_id>"
                exit 1
            fi
            
            if restore_checkpoint "$checkpoint_id"; then
                echo "Checkpoint restored: $checkpoint_id"
            else
                echo "Failed to restore checkpoint: $checkpoint_id"
                exit 1
            fi
            ;;
        "list")
            local format="${2:-table}"
            list_checkpoints "$format"
            ;;
        "cleanup")
            local retention_days="${2:-$CHECKPOINT_RETENTION_DAYS}"
            cleanup_checkpoints "$retention_days"
            ;;
        "degrade")
            local reason="${2:-manual}"
            local features="${3:-[]}"
            enable_degraded_mode "$reason" "$features"
            ;;
        "recover-mode")
            disable_degraded_mode
            ;;
        "status")
            echo "Error Recovery System Status"
            echo "============================"
            echo "Version: $ERROR_RECOVERY_VERSION"
            echo "Checkpoint Directory: $CHECKPOINT_DIR"
            echo "Error Log: $ERROR_LOG"
            echo "Available Checkpoints: $(find "$CHECKPOINT_DIR" -name "checkpoint-*" -type d 2>/dev/null | wc -l | tr -d ' ')"
            echo "Degraded Mode: $(is_degraded_mode)"
            echo ""
            
            if [ -f "$ERROR_LOG" ]; then
                echo "Recent Errors (last 10):"
                tail -10 "$ERROR_LOG" 2>/dev/null || echo "No recent errors"
            fi
            ;;
        *)
            echo "Usage: $0 {checkpoint|restore|list|cleanup|degrade|recover-mode|status}"
            echo ""
            echo "Commands:"
            echo "  checkpoint <operation> [phase] [metadata] - Create checkpoint"
            echo "  restore <checkpoint_id>                   - Restore from checkpoint"
            echo "  list [format]                             - List checkpoints"
            echo "  cleanup [retention_days]                  - Cleanup old checkpoints"
            echo "  degrade <reason> [features]               - Enable degraded mode"
            echo "  recover-mode                              - Disable degraded mode"
            echo "  status                                    - Show system status"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi