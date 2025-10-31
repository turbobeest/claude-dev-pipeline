# State Management System

## Overview

The Claude Dev Pipeline state management system provides robust, thread-safe state management with comprehensive error recovery capabilities. It's designed for production use with features like:

- **Atomic Operations**: All state changes are atomic using temp file + rename pattern
- **Concurrency Control**: File locking prevents race conditions between concurrent processes
- **Data Integrity**: Automatic validation, corruption detection, and recovery
- **Backup & Recovery**: Automatic backups with configurable retention
- **Error Handling**: Comprehensive error recovery with graceful degradation
- **Migration Support**: Schema versioning with automatic migration

## Architecture

### Components

1. **State Manager** (`lib/state-manager.sh`)
   - Core state file operations (read/write/validate)
   - Automatic backup and recovery
   - Schema validation and migration
   - Atomic updates with locking

2. **Lock Manager** (`lib/lock-manager.sh`)
   - Centralized lock management
   - Deadlock prevention with lock hierarchy
   - Stale lock detection and cleanup
   - Support for shared and exclusive locks

3. **Error Recovery** (`lib/error-recovery.sh`)
   - Checkpoint system for rollback capability
   - Retry logic with exponential backoff
   - Graceful degradation for non-critical failures
   - Recovery suggestions for common errors

4. **Updated Hooks**
   - `hooks/skill-activation-prompt.sh` - Uses state manager for reads
   - `hooks/post-tool-use-tracker.sh` - Uses state manager for atomic updates

### State File Structure

```json
{
  "schemaVersion": "1.0",
  "phase": "pre-init",
  "completedTasks": [],
  "signals": {
    "PHASE1_START": 1635789123.456,
    "PHASE1_COMPLETE": 1635789456.789
  },
  "lastActivation": "SPEC_GEN_V1",
  "metadata": {
    "created": "2023-11-01T10:30:00Z",
    "lastModified": "2023-11-01T10:35:00Z"
  },
  "degradedMode": {
    "enabled": false,
    "reason": "",
    "timestamp": "",
    "disabledFeatures": []
  }
}
```

## Usage

### State Manager Operations

#### Initialize System
```bash
./lib/state-manager.sh init
```

#### Read Current State
```bash
# Read to stdout
./lib/state-manager.sh read

# Read to file
./lib/state-manager.sh read > state-snapshot.json
```

#### Validate State
```bash
./lib/state-manager.sh validate
```

#### Create Backup
```bash
./lib/state-manager.sh backup "manual-backup"
```

#### Recover from Backup
```bash
# Recover from latest backup
./lib/state-manager.sh recover

# Recover from specific backup
./lib/state-manager.sh recover "backup-pattern"
```

#### Check Status
```bash
./lib/state-manager.sh status
```

### Lock Manager Operations

#### Acquire Lock
```bash
# Exclusive lock (default)
./lib/lock-manager.sh acquire "my-operation" 30

# Shared lock
./lib/lock-manager.sh acquire "read-operation" 30 shared

# With metadata
./lib/lock-manager.sh acquire "complex-op" 60 exclusive '{"purpose":"deployment"}'
```

#### Release Lock
```bash
./lib/lock-manager.sh release "my-operation"
```

#### Check Lock Status
```bash
./lib/lock-manager.sh check "my-operation"
```

#### List All Locks
```bash
# Table format
./lib/lock-manager.sh list

# JSON format
./lib/lock-manager.sh list json
```

#### Clean Stale Locks
```bash
./lib/lock-manager.sh clean
```

### Error Recovery Operations

#### Create Checkpoint
```bash
./lib/error-recovery.sh checkpoint "deployment" "phase6" '{"version":"1.2.3"}'
```

#### Restore from Checkpoint
```bash
./lib/error-recovery.sh restore "checkpoint-20231101-103000-deployment"
```

#### List Checkpoints
```bash
# Table format
./lib/error-recovery.sh list

# JSON format
./lib/error-recovery.sh list json
```

#### Enable Degraded Mode
```bash
./lib/error-recovery.sh degrade "database-unavailable" '["real-time-updates", "notifications"]'
```

#### Recover to Normal Mode
```bash
./lib/error-recovery.sh recover-mode
```

## Programming Interface

### Using in Shell Scripts

```bash
#!/bin/bash

# Load state management
source "$(dirname "$0")/lib/state-manager.sh"

# Safe state update
if lock_state 30; then
    current_state=$(read_state)
    updated_state=$(echo "$current_state" | jq '.phase = "new-phase"')
    
    if write_state "$updated_state" "phase-transition"; then
        echo "State updated successfully"
    else
        echo "Failed to update state"
    fi
    
    unlock_state
fi
```

### Error Handling

```bash
#!/bin/bash

source "$(dirname "$0")/lib/error-recovery.sh"

# Create checkpoint before risky operation
create_checkpoint "risky-operation" "current-phase"

# Perform operation with retry
if retry_with_backoff "risky_command" 3 2 "arg1" "arg2"; then
    echo "Operation succeeded"
else
    echo "Operation failed, restoring checkpoint"
    restore_checkpoint "$CHECKPOINT_ID"
fi
```

## Configuration

### Environment Variables

- `STATE_FILE`: Path to state file (default: `.workflow-state.json`)
- `AUDIT_LOG`: Path to audit log (default: `/tmp/claude-pipeline-audit.log`)
- `LOCK_TIMEOUT`: Default lock timeout in seconds (default: 30)

### Directory Structure

```
.
├── lib/
│   ├── state-manager.sh      # Core state management
│   ├── lock-manager.sh       # Lock management
│   └── error-recovery.sh     # Error recovery
├── .workflow-state.json      # Main state file
├── .state-backups/           # Automatic backups
├── .locks/                   # Lock files
├── .checkpoints/             # Recovery checkpoints
└── .signals/                 # Signal files
```

## Lock Hierarchy

To prevent deadlocks, locks have a priority hierarchy:

1. `state` (priority 1) - Highest priority
2. `config` (priority 2)
3. `signals` (priority 3)
4. `backup` (priority 4)
5. `temp` (priority 5)
6. `user` (priority 10) - Lowest priority

Always acquire locks in priority order (lower numbers first).

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Operation completed successfully |
| 1 | GENERAL_ERROR | Generic error |
| 2 | LOCK_TIMEOUT | Failed to acquire lock within timeout |
| 3 | STATE_CORRUPTION | State file is corrupted |
| 4 | VALIDATION_FAILED | Data validation failed |
| 5 | DEPENDENCY_MISSING | Required dependency not found |
| 6 | PERMISSION_DENIED | Insufficient permissions |
| 7 | DISK_FULL | Disk space exhausted |
| 8 | NETWORK_ERROR | Network connectivity issue |
| 9 | TIMEOUT | Operation timed out |
| 10 | RESOURCE_EXHAUSTED | System resources exhausted |

## Recovery Strategies

The system includes automatic recovery strategies for common error conditions:

- **Lock Timeout**: Clean stale locks
- **State Corruption**: Restore from backup
- **Validation Failed**: Restore from checkpoint
- **Disk Full**: Cleanup temporary files
- **Timeout**: Retry with backoff
- **Resource Exhausted**: Wait and retry

## Performance Considerations

### Optimization Tips

1. **Use Shared Locks** for read-only operations
2. **Minimize Lock Hold Time** - acquire late, release early
3. **Batch State Updates** when possible
4. **Regular Cleanup** of old backups and checkpoints

### Monitoring

Monitor these metrics for performance:

- Lock acquisition time
- State file size growth
- Backup creation frequency
- Error recovery invocations

## Troubleshooting

### Common Issues

#### State File Corruption
```bash
# Check state file
./lib/state-manager.sh validate

# Recover from backup
./lib/state-manager.sh recover
```

#### Lock Contention
```bash
# Check active locks
./lib/lock-manager.sh list

# Clean stale locks
./lib/lock-manager.sh clean
```

#### High Error Rate
```bash
# Check error recovery status
./lib/error-recovery.sh status

# Review error logs
tail -f .error-recovery.log
```

### Debug Mode

Enable debug logging:
```bash
export DEBUG=1
export AUDIT_LOG="./debug.log"
```

## Testing

Run the comprehensive test suite:

```bash
./test-state-management.sh
```

This tests:
- State manager functionality
- Lock manager operations
- Error recovery capabilities
- Hook integration
- Concurrent access patterns
- Corruption recovery
- Performance characteristics

## Security Considerations

1. **File Permissions**: State files use 600 permissions (owner read/write only)
2. **Path Validation**: All file paths are validated to prevent traversal attacks
3. **Input Sanitization**: All inputs are sanitized and size-limited
4. **Process Validation**: Lock ownership is verified by process ID
5. **Audit Logging**: All operations are logged for security monitoring

## Migration

When upgrading schema versions:

1. **Automatic**: Run `./lib/state-manager.sh migrate`
2. **Manual**: Use `./lib/state-manager.sh backup` before changes
3. **Rollback**: Use `./lib/state-manager.sh recover` if needed

## Best Practices

1. **Always use the state manager** - Don't modify state files directly
2. **Handle lock failures gracefully** - Implement fallback strategies
3. **Create checkpoints** before risky operations
4. **Monitor degraded mode** - Restore normal operation quickly
5. **Regular backups** - Ensure backup strategy meets recovery requirements
6. **Test recovery procedures** - Verify backup and recovery work
7. **Monitor performance** - Watch for lock contention and slow operations

## Support

For issues with the state management system:

1. Check the error logs (`.error-recovery.log`)
2. Run the test suite (`./test-state-management.sh`)
3. Verify system status (`./lib/state-manager.sh status`)
4. Review recent audit logs
5. Check for resource constraints (disk space, memory, etc.)