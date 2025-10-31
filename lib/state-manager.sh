#!/bin/bash
# =============================================================================
# State Management System - Claude Dev Pipeline
# =============================================================================
# 
# Provides atomic, thread-safe state management with:
# - File locking using flock
# - Atomic updates with temp file + rename pattern
# - State corruption detection and recovery
# - Automatic backups (keeps last 5)
# - Schema validation
# - State migration support
# - Performance optimizations and caching
#
# =============================================================================

set -euo pipefail

# Source performance optimization libraries
source "${BASH_SOURCE[0]%/*}/cache.sh" 2>/dev/null || true
source "${BASH_SOURCE[0]%/*}/json-utils.sh" 2>/dev/null || true
source "${BASH_SOURCE[0]%/*}/file-io.sh" 2>/dev/null || true
source "${BASH_SOURCE[0]%/*}/profiler.sh" 2>/dev/null || true

# Configuration
readonly STATE_MANAGER_VERSION="1.0.0"
readonly STATE_SCHEMA_VERSION="1.0"
readonly MAX_BACKUPS=5
readonly LOCK_TIMEOUT=30
readonly VALIDATION_TIMEOUT=10
readonly BACKUP_RETENTION_DAYS=7

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"
readonly STATE_FILE="${STATE_FILE:-$PIPELINE_ROOT/.workflow-state.json}"
readonly BACKUP_DIR="$PIPELINE_ROOT/.state-backups"
readonly LOCK_DIR="$PIPELINE_ROOT/.locks"
readonly AUDIT_LOG="${AUDIT_LOG:-/tmp/claude-pipeline-audit.log}"

# Ensure required directories exist
mkdir -p "$BACKUP_DIR" "$LOCK_DIR"
chmod 750 "$BACKUP_DIR" "$LOCK_DIR"

# Logging function
log_audit() {
    local level="$1"
    local component="$2"
    local message="$3"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [$level] state-manager/$component: $message" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_no=$1
    log_audit "ERROR" "handler" "Error on line $line_no: exit code $exit_code"
    cleanup_temp_files
    exit $exit_code
}

# Only set trap if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'handle_error $LINENO' ERR
fi

# Cleanup function
cleanup_temp_files() {
    find "$PIPELINE_ROOT" -name "*.tmp" -type f -mmin +60 -delete 2>/dev/null || true
    find "$LOCK_DIR" -name "*.lock" -type f -mmin +60 -delete 2>/dev/null || true
}

# =============================================================================
# LOCKING FUNCTIONS
# =============================================================================

# Acquire exclusive lock on state file (macOS compatible)
lock_state() {
    local lock_file="$LOCK_DIR/state.lock"
    local timeout="${1:-$LOCK_TIMEOUT}"
    local start_time=$(date +%s)
    
    log_audit "DEBUG" "lock" "Attempting to acquire state lock"
    
    while true; do
        # Try to acquire lock atomically using noclobber
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            log_audit "INFO" "lock" "State lock acquired by PID $$"
            return 0
        fi
        
        # Check if lock is stale
        if [ -f "$lock_file" ]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
            
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                log_audit "WARN" "lock" "Removing stale lock from dead process $lock_pid"
                rm -f "$lock_file" 2>/dev/null || true
                continue
            fi
            
            # Check lock age (5 minutes max)
            if [ -f "$lock_file" ]; then
                local lock_age
                lock_age=$(( $(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || echo $(date +%s)) ))
                if [ $lock_age -gt 300 ]; then
                    log_audit "WARN" "lock" "Removing aged lock file"
                    rm -f "$lock_file" 2>/dev/null || true
                    continue
                fi
            fi
        fi
        
        # Check timeout
        local elapsed=$(( $(date +%s) - start_time ))
        if [ $elapsed -ge $timeout ]; then
            log_audit "ERROR" "lock" "Failed to acquire lock within ${timeout}s"
            return 1
        fi
        
        sleep 0.1
    done
}

# Release exclusive lock
unlock_state() {
    local lock_file="$LOCK_DIR/state.lock"
    
    if [ -f "$lock_file" ]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
        
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$lock_file"
            log_audit "INFO" "lock" "State lock released by PID $$"
        else
            log_audit "WARN" "lock" "Attempted to release lock not owned by this process"
            return 1
        fi
    fi
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

# Create backup of current state
backup_state() {
    local reason="${1:-manual}"
    local backup_file="$BACKUP_DIR/state-$(date +%Y%m%d-%H%M%S)-$reason.json"
    
    if [ ! -f "$STATE_FILE" ]; then
        log_audit "WARN" "backup" "No state file to backup"
        return 0
    fi
    
    if cp "$STATE_FILE" "$backup_file" 2>/dev/null; then
        chmod 600 "$backup_file"
        log_audit "INFO" "backup" "State backed up to $(basename "$backup_file")"
        
        # Cleanup old backups
        cleanup_old_backups
        return 0
    else
        log_audit "ERROR" "backup" "Failed to create backup"
        return 1
    fi
}

# Cleanup old backups (keep last N and within retention period)
cleanup_old_backups() {
    # Keep only last N backups
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "state-*.json" -type f | wc -l)
    
    if [ "$backup_count" -gt $MAX_BACKUPS ]; then
        find "$BACKUP_DIR" -name "state-*.json" -type f -print0 | \
            xargs -0 ls -t | \
            tail -n +$((MAX_BACKUPS + 1)) | \
            xargs rm -f 2>/dev/null || true
        
        log_audit "INFO" "backup" "Cleaned up old backups, keeping last $MAX_BACKUPS"
    fi
    
    # Remove backups older than retention period
    find "$BACKUP_DIR" -name "state-*.json" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate state file against schema
validate_state() {
    local file="${1:-$STATE_FILE}"
    
    if [ ! -f "$file" ]; then
        log_audit "ERROR" "validation" "State file does not exist: $file"
        return 1
    fi
    
    # Basic JSON validation
    if ! timeout $VALIDATION_TIMEOUT jq empty "$file" 2>/dev/null; then
        log_audit "ERROR" "validation" "Invalid JSON in state file"
        return 1
    fi
    
    # Schema validation
    local required_fields=("phase" "completedTasks" "signals" "lastActivation")
    for field in "${required_fields[@]}"; do
        if ! timeout $VALIDATION_TIMEOUT jq -e "has(\"$field\")" "$file" >/dev/null 2>&1; then
            log_audit "ERROR" "validation" "Missing required field: $field"
            return 1
        fi
    done
    
    # Validate field types
    if ! timeout $VALIDATION_TIMEOUT jq -e '.phase | type == "string"' "$file" >/dev/null 2>&1; then
        log_audit "ERROR" "validation" "Invalid type for field 'phase'"
        return 1
    fi
    
    if ! timeout $VALIDATION_TIMEOUT jq -e '.completedTasks | type == "array"' "$file" >/dev/null 2>&1; then
        log_audit "ERROR" "validation" "Invalid type for field 'completedTasks'"
        return 1
    fi
    
    if ! timeout $VALIDATION_TIMEOUT jq -e '.signals | type == "object"' "$file" >/dev/null 2>&1; then
        log_audit "ERROR" "validation" "Invalid type for field 'signals'"
        return 1
    fi
    
    # Validate schema version if present
    local schema_version
    schema_version=$(timeout $VALIDATION_TIMEOUT jq -r '.schemaVersion // ""' "$file" 2>/dev/null || echo "")
    
    if [ -n "$schema_version" ] && [ "$schema_version" != "$STATE_SCHEMA_VERSION" ]; then
        log_audit "WARN" "validation" "Schema version mismatch: found $schema_version, expected $STATE_SCHEMA_VERSION"
        # Don't fail validation for version mismatch, just warn
    fi
    
    log_audit "DEBUG" "validation" "State file validation passed"
    return 0
}

# =============================================================================
# STATE I/O FUNCTIONS
# =============================================================================

# Read current state (with locking)
read_state() {
    local output_file="${1:-}"
    
    if ! lock_state; then
        log_audit "ERROR" "read" "Failed to acquire lock for reading"
        return 1
    fi
    
    if [ ! -f "$STATE_FILE" ]; then
        log_audit "WARN" "read" "State file does not exist, returning default state"
        unlock_state
        echo '{
            "schemaVersion": "'$STATE_SCHEMA_VERSION'",
            "phase": "pre-init",
            "completedTasks": [],
            "signals": {},
            "lastActivation": "",
            "metadata": {},
            "created": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
        }'
        return 0
    fi
    
    if ! validate_state "$STATE_FILE"; then
        log_audit "ERROR" "read" "State validation failed"
        unlock_state
        return 1
    fi
    
    local content
    if content=$(cat "$STATE_FILE" 2>/dev/null); then
        unlock_state
        
        if [ -n "$output_file" ]; then
            echo "$content" > "$output_file"
        else
            echo "$content"
        fi
        
        log_audit "DEBUG" "read" "State read successfully"
        return 0
    else
        log_audit "ERROR" "read" "Failed to read state file"
        unlock_state
        return 1
    fi
}

# Write state atomically (with locking and backup)
write_state() {
    local new_state="$1"
    local backup_reason="${2:-update}"
    
    # Validate input
    if [ -z "$new_state" ]; then
        log_audit "ERROR" "write" "Empty state provided"
        return 1
    fi
    
    # Validate JSON
    if ! echo "$new_state" | timeout $VALIDATION_TIMEOUT jq empty 2>/dev/null; then
        log_audit "ERROR" "write" "Invalid JSON provided"
        return 1
    fi
    
    if ! lock_state; then
        log_audit "ERROR" "write" "Failed to acquire lock for writing"
        return 1
    fi
    
    # Backup current state if it exists
    if [ -f "$STATE_FILE" ]; then
        if ! backup_state "$backup_reason"; then
            log_audit "WARN" "write" "Backup failed, continuing with write"
        fi
    fi
    
    # Add metadata to state
    local enhanced_state
    enhanced_state=$(echo "$new_state" | jq --arg version "$STATE_SCHEMA_VERSION" --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
        .schemaVersion = $version |
        .lastModified = $timestamp |
        if has("created") | not then .created = $timestamp else . end
    ')
    
    # Validate enhanced state
    local temp_file="${STATE_FILE}.tmp.$$"
    echo "$enhanced_state" > "$temp_file"
    
    if ! validate_state "$temp_file"; then
        log_audit "ERROR" "write" "Enhanced state validation failed"
        rm -f "$temp_file"
        unlock_state
        return 1
    fi
    
    # Atomic write
    if mv "$temp_file" "$STATE_FILE" 2>/dev/null; then
        chmod 600 "$STATE_FILE"
        log_audit "INFO" "write" "State written successfully"
        unlock_state
        return 0
    else
        log_audit "ERROR" "write" "Failed to move temp file to state file"
        rm -f "$temp_file"
        unlock_state
        return 1
    fi
}

# =============================================================================
# RECOVERY FUNCTIONS
# =============================================================================

# Recover state from backup
recover_state() {
    local backup_pattern="${1:-}"
    local force="${2:-false}"
    
    log_audit "INFO" "recovery" "Starting state recovery"
    
    if [ "$force" != "true" ] && [ -f "$STATE_FILE" ] && validate_state "$STATE_FILE"; then
        log_audit "INFO" "recovery" "Current state is valid, no recovery needed"
        return 0
    fi
    
    if ! lock_state; then
        log_audit "ERROR" "recovery" "Failed to acquire lock for recovery"
        return 1
    fi
    
    # Find latest valid backup
    local backup_file=""
    
    if [ -n "$backup_pattern" ]; then
        backup_file=$(find "$BACKUP_DIR" -name "*$backup_pattern*.json" -type f | sort -r | head -1)
    else
        backup_file=$(find "$BACKUP_DIR" -name "state-*.json" -type f | sort -r | head -1)
    fi
    
    if [ -z "$backup_file" ]; then
        log_audit "ERROR" "recovery" "No backup files found"
        
        # Create default state as last resort
        local default_state='{
            "schemaVersion": "'$STATE_SCHEMA_VERSION'",
            "phase": "pre-init",
            "completedTasks": [],
            "signals": {},
            "lastActivation": "",
            "metadata": {"recovered": true},
            "created": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
        }'
        
        echo "$default_state" > "${STATE_FILE}.tmp.$$"
        if mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null; then
            chmod 600 "$STATE_FILE"
            log_audit "WARN" "recovery" "Created default state file"
            unlock_state
            return 0
        else
            rm -f "${STATE_FILE}.tmp.$$"
            unlock_state
            log_audit "ERROR" "recovery" "Failed to create default state file"
            return 1
        fi
    fi
    
    # Validate backup before using it
    if ! validate_state "$backup_file"; then
        log_audit "ERROR" "recovery" "Backup file is invalid: $(basename "$backup_file")"
        unlock_state
        return 1
    fi
    
    # Restore from backup
    if cp "$backup_file" "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"; then
        chmod 600 "$STATE_FILE"
        log_audit "INFO" "recovery" "State recovered from backup: $(basename "$backup_file")"
        unlock_state
        return 0
    else
        rm -f "${STATE_FILE}.tmp.$$"
        log_audit "ERROR" "recovery" "Failed to restore from backup"
        unlock_state
        return 1
    fi
}

# =============================================================================
# MIGRATION FUNCTIONS
# =============================================================================

# Migrate state to current schema version
migrate_state() {
    local current_version
    current_version=$(read_state | jq -r '.schemaVersion // "0.0"' 2>/dev/null || echo "0.0")
    
    if [ "$current_version" = "$STATE_SCHEMA_VERSION" ]; then
        log_audit "DEBUG" "migration" "State is already at current version $STATE_SCHEMA_VERSION"
        return 0
    fi
    
    log_audit "INFO" "migration" "Migrating state from version $current_version to $STATE_SCHEMA_VERSION"
    
    # Backup before migration
    if ! backup_state "pre-migration"; then
        log_audit "ERROR" "migration" "Failed to backup state before migration"
        return 1
    fi
    
    local current_state
    if ! current_state=$(read_state); then
        log_audit "ERROR" "migration" "Failed to read current state for migration"
        return 1
    fi
    
    # Perform version-specific migrations
    case "$current_version" in
        "0.0"|"")
            # Migration from legacy format
            current_state=$(echo "$current_state" | jq '
                .schemaVersion = "'$STATE_SCHEMA_VERSION'" |
                if has("metadata") | not then .metadata = {} else . end |
                .metadata.migrated = true |
                .metadata.migratedFrom = "legacy"
            ')
            ;;
        *)
            log_audit "WARN" "migration" "Unknown version $current_version, attempting generic migration"
            current_state=$(echo "$current_state" | jq '
                .schemaVersion = "'$STATE_SCHEMA_VERSION'" |
                if has("metadata") | not then .metadata = {} else . end |
                .metadata.migrated = true |
                .metadata.migratedFrom = "'$current_version'"
            ')
            ;;
    esac
    
    if write_state "$current_state" "migration"; then
        log_audit "INFO" "migration" "State migration completed successfully"
        return 0
    else
        log_audit "ERROR" "migration" "State migration failed"
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Initialize state management system
init_state_manager() {
    log_audit "INFO" "init" "Initializing state management system v$STATE_MANAGER_VERSION"
    
    # Ensure state file exists
    if [ ! -f "$STATE_FILE" ]; then
        local initial_state='{
            "schemaVersion": "'$STATE_SCHEMA_VERSION'",
            "phase": "pre-init",
            "completedTasks": [],
            "signals": {},
            "lastActivation": "",
            "metadata": {},
            "created": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
        }'
        
        if write_state "$initial_state" "initialization"; then
            log_audit "INFO" "init" "Initial state file created"
        else
            log_audit "ERROR" "init" "Failed to create initial state file"
            return 1
        fi
    fi
    
    # Validate and migrate if necessary
    if ! validate_state; then
        log_audit "WARN" "init" "State validation failed, attempting recovery"
        if ! recover_state; then
            log_audit "ERROR" "init" "State recovery failed"
            return 1
        fi
    fi
    
    # Check for migration needs
    migrate_state
    
    # Cleanup old files
    cleanup_temp_files
    cleanup_old_backups
    
    log_audit "INFO" "init" "State management system initialized successfully"
    return 0
}

# Get state management status
status_state_manager() {
    echo "State Management System Status"
    echo "=============================="
    echo "Version: $STATE_MANAGER_VERSION"
    echo "Schema Version: $STATE_SCHEMA_VERSION"
    echo "State File: $STATE_FILE"
    echo "Backup Directory: $BACKUP_DIR"
    echo "Lock Directory: $LOCK_DIR"
    echo ""
    
    if [ -f "$STATE_FILE" ]; then
        echo "State File Status: EXISTS"
        echo "Size: $(stat -f%z "$STATE_FILE" 2>/dev/null || echo "unknown") bytes"
        echo "Modified: $(stat -f%Sm "$STATE_FILE" 2>/dev/null || echo "unknown")"
        
        if validate_state; then
            echo "Validation: PASSED"
            local current_phase
            current_phase=$(read_state | jq -r '.phase // "unknown"' 2>/dev/null || echo "unknown")
            echo "Current Phase: $current_phase"
        else
            echo "Validation: FAILED"
        fi
    else
        echo "State File Status: MISSING"
    fi
    
    echo ""
    echo "Backups: $(find "$BACKUP_DIR" -name "state-*.json" -type f 2>/dev/null | wc -l | tr -d ' ') files"
    echo "Locks: $(find "$LOCK_DIR" -name "*.lock" -type f 2>/dev/null | wc -l | tr -d ' ') active"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

# Main function for direct script usage
main() {
    local command="${1:-status}"
    
    case "$command" in
        "init")
            init_state_manager
            ;;
        "status")
            status_state_manager
            ;;
        "validate")
            if validate_state; then
                echo "State validation: PASSED"
                exit 0
            else
                echo "State validation: FAILED"
                exit 1
            fi
            ;;
        "backup")
            backup_state "${2:-manual}"
            ;;
        "recover")
            recover_state "${2:-}" "${3:-false}"
            ;;
        "migrate")
            migrate_state
            ;;
        "read")
            read_state
            ;;
        *)
            echo "Usage: $0 {init|status|validate|backup|recover|migrate|read}"
            echo ""
            echo "Commands:"
            echo "  init     - Initialize state management system"
            echo "  status   - Show state management status"
            echo "  validate - Validate current state file"
            echo "  backup   - Create manual backup"
            echo "  recover  - Recover from backup"
            echo "  migrate  - Migrate state schema"
            echo "  read     - Read current state"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi