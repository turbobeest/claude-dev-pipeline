# Claude Dev Pipeline - API Reference

## Overview

This document provides comprehensive API documentation for all components of the Claude Dev Pipeline system. The API includes hook interfaces, skill definitions, state management, worktree operations, and utility functions.

## Table of Contents

1. [Hook API Reference](#hook-api-reference)
2. [Skill API Reference](#skill-api-reference)
3. [State Manager API](#state-manager-api)
4. [Worktree Manager API](#worktree-manager-api)
5. [Lock Manager API](#lock-manager-api)
6. [Error Recovery API](#error-recovery-api)
7. [Logger API](#logger-api)
8. [Configuration API](#configuration-api)

## Hook API Reference

### UserPromptSubmit Hook

**Script**: `hooks/skill-activation-prompt.sh`

**Purpose**: Analyzes user input and injects skill activation codewords

#### Input Interface

The hook receives input via environment variables and stdin:

```bash
# Environment Variables
CLAUDE_USER_MESSAGE     # The user's input message
CLAUDE_CONTEXT_FILES    # JSON array of context files
CLAUDE_WORKFLOW_STATE   # Current pipeline state JSON
CLAUDE_DEBUG_MODE       # Debug flag (true/false)

# Standard Input
# User message content (if not in environment)
```

#### Output Interface

The hook outputs modified content to stdout:

```bash
# Modified user message with injected codewords
"[ACTIVATE:PRD_TO_TASKS_V1] Generate tasks from this PRD"

# Optional debug information (stderr)
"[DEBUG] Pattern matched: 'generate tasks'"
"[DEBUG] Context file detected: PRD.md" 
"[DEBUG] Injecting activation code: PRD_TO_TASKS_V1"
```

#### API Functions

```bash
# Pattern analysis function
analyze_user_patterns() {
    local message="$1"
    local context_files="$2"
    # Returns: JSON object with matched patterns
}

# Codeword injection function
inject_activation_codeword() {
    local skill_code="$1"
    local original_message="$2"
    # Returns: Modified message with [ACTIVATE:CODE]
}

# Priority selection function
select_highest_priority_skill() {
    local matched_skills="$1"    # JSON array
    # Returns: Single skill activation code
}

# Context validation function
validate_activation_context() {
    local skill="$1"
    local current_state="$2"
    # Returns: true/false
}
```

#### Configuration

```json
{
  "patterns": {
    "prd_to_tasks": [
      "generate tasks",
      "parse prd",
      "create tasks",
      "task decomposition"
    ],
    "spec_gen": [
      "openspec proposal",
      "create spec",
      "generate proposal"
    ]
  },
  "priority_order": [
    "PIPELINE_ORCHESTRATION_V1",
    "PRD_TO_TASKS_V1",
    "COUPLING_ANALYSIS_V1"
  ],
  "debug_mode": false
}
```

### PostToolUse Hook

**Script**: `hooks/post-tool-use-tracker.sh`

**Purpose**: Monitors tool execution and triggers phase transitions

#### Input Interface

```bash
# Environment Variables
CLAUDE_TOOL_NAME        # Name of tool executed
CLAUDE_TOOL_RESULT      # Tool execution result
CLAUDE_FILES_CHANGED    # JSON array of changed files
CLAUDE_EXECUTION_TIME   # Tool execution time (ms)

# Standard Input
# Tool output content
```

#### Output Interface

```bash
# Signal files created
.signals/PHASE1_START.json
.signals/COUPLING_ANALYZED.json

# State updates
.workflow-state.json    # Updated with progress

# Automatic codeword injection (to next prompt)
"[ACTIVATE:NEXT_SKILL_V1]"
```

#### API Functions

```bash
# File change detection
detect_file_changes() {
    local tool_result="$1"
    # Returns: JSON array of changed files with metadata
}

# Signal emission
emit_phase_signal() {
    local signal_name="$1"
    local metadata="$2"
    # Creates: .signals/{signal_name}.json
}

# Phase transition logic
check_phase_completion() {
    local current_phase="$1"
    local changed_files="$2"
    # Returns: completion status and next phase
}

# Next skill activation
trigger_next_skill() {
    local completed_phase="$1"
    # Returns: activation codeword for next skill
}
```

### PreImplementationValidator Hook

**Script**: `hooks/pre-implementation-validator.sh`

**Purpose**: Enforces TDD discipline and validates implementation readiness

#### Input Interface

```bash
# Environment Variables
CLAUDE_TOOL_REQUEST     # Requested tool and parameters
CLAUDE_CURRENT_PHASE    # Current pipeline phase
CLAUDE_FILES_CONTEXT    # Context files JSON

# Tool request details
TOOL_NAME              # write, edit, multiedit, etc.
TOOL_PARAMETERS        # JSON of tool parameters
```

#### Output Interface

```bash
# Return codes
0    # Allow tool execution
1    # Block tool execution
2    # Request user confirmation

# Standard output (blocking message)
"BLOCKED: Implementation requires tests first"
"TDD Violation: Write tests before implementation"

# Standard error (debug info)
"[DEBUG] Phase 3 detected, checking for tests"
"[DEBUG] No test files found for component"
```

#### API Functions

```bash
# TDD validation
validate_tdd_compliance() {
    local tool_request="$1"
    local current_files="$2"
    # Returns: compliance status
}

# Test file detection
find_related_tests() {
    local implementation_file="$1"
    # Returns: array of related test files
}

# Implementation gate check
check_implementation_gate() {
    local current_phase="$1"
    # Returns: gate status (open/closed/requires_approval)
}
```

## Skill API Reference

### Skill Definition Format

Each skill must include a `SKILL.md` file with metadata:

```yaml
---
activation_code: SKILL_NAME_V1
phase: 1
prerequisites: []
outputs: 
  - tasks.json
  - .signals/phase-complete.json
description: |
  Skill description here
---
```

### Skill Activation Interface

#### Environment Variables Available to Skills

```bash
# Pipeline Context
CLAUDE_PIPELINE_PHASE      # Current phase number
CLAUDE_PIPELINE_TASK       # Current task number
CLAUDE_WORKTREE_PATH      # Active worktree path
CLAUDE_PROJECT_ROOT       # Project root directory

# State Information
CLAUDE_WORKFLOW_STATE     # JSON workflow state
CLAUDE_PREVIOUS_OUTPUTS   # JSON of previous skill outputs
CLAUDE_SIGNAL_HISTORY     # JSON of emitted signals

# Configuration
CLAUDE_SKILL_CONFIG       # Skill-specific configuration
CLAUDE_AUTOMATION_LEVEL   # Automation level (0-100)
CLAUDE_DEBUG_MODE         # Debug flag

# Worktree Information
WORKTREE_NAME            # Current worktree name
WORKTREE_BASE_COMMIT     # Base commit for worktree
WORKTREE_ISOLATION       # Isolation validation status
```

#### Expected Outputs

```bash
# Required files (varies by skill)
tasks.json              # Task definitions
.openspec/*.proposal.md # Specification proposals
tests/*.test.js         # Test files
src/*.js               # Implementation files

# Signal files (required)
.signals/{signal_name}.json

# State updates (automatic)
.workflow-state.json   # Updated by post-tool-use hook
```

### Standard Skill Functions

#### PRD-to-Tasks Skill API

```bash
# Activation: [ACTIVATE:PRD_TO_TASKS_V1]
# Input: PRD.md, requirements documents
# Output: tasks.json

# Expected task.json structure:
{
  "version": "1.0",
  "project": "project_name",
  "total_tasks": 26,
  "tasks": [
    {
      "id": 1,
      "title": "Task title",
      "description": "Detailed description",
      "phase": 1,
      "dependencies": [],
      "estimated_hours": 4,
      "complexity": "medium",
      "type": "feature|bug|test|docs"
    }
  ],
  "dependencies": {
    "1": [],
    "2": [1],
    "3": [1, 2]
  },
  "metadata": {
    "generated_at": "ISO8601",
    "source_prd": "PRD.md",
    "total_estimated_hours": 104
  }
}
```

#### Spec Generation Skill API

```bash
# Activation: [ACTIVATE:SPEC_GEN_V1]
# Input: tasks.json
# Output: .openspec/*.proposal.md

# Expected .openspec/component.proposal.md structure:
---
title: Component Specification
version: 1.0
status: draft
created: ISO8601
tasks: [4, 5, 6]
---

# Component Specification

## Overview
[Component description]

## API Definition
[Interface specifications]

## Implementation Plan
[Development approach]

## Testing Strategy
[Test requirements]
```

#### Test Strategy Skill API

```bash
# Activation: [ACTIVATE:TEST_STRATEGY_V1]
# Input: .openspec/*.proposal.md
# Output: .test-strategy/*.md

# Expected test strategy structure:
{
  "version": "1.0",
  "strategy": "60/30/10",
  "levels": {
    "unit": {
      "percentage": 60,
      "frameworks": ["jest", "mocha"],
      "coverage_target": 80
    },
    "integration": {
      "percentage": 30,
      "frameworks": ["supertest"],
      "coverage_target": 70
    },
    "e2e": {
      "percentage": 10,
      "frameworks": ["cypress", "playwright"],
      "coverage_target": 90
    }
  }
}
```

## State Manager API

**Module**: `lib/state-manager.sh`

### Core Functions

#### State Operations

```bash
# Initialize state file
./lib/state-manager.sh init [state_file]
# Returns: 0 on success, 1 on error

# Read current state
./lib/state-manager.sh read [state_file]
# Output: JSON state content
# Returns: 0 on success, 1 on error

# Write state with message
./lib/state-manager.sh write <json_content> [message]
# Input: JSON string or file path
# Returns: 0 on success, 1 on error

# Validate state integrity  
./lib/state-manager.sh validate [state_file]
# Output: Validation report
# Returns: 0 if valid, 1 if invalid
```

#### Backup Operations

```bash
# Create manual backup
./lib/state-manager.sh backup [label]
# Creates: .state-backups/state-{timestamp}-{label}.json
# Returns: 0 on success, 1 on error

# List available backups
./lib/state-manager.sh list-backups
# Output: List of backup files with metadata

# Restore from backup
./lib/state-manager.sh restore <backup_file>
# Returns: 0 on success, 1 on error

# Clean old backups
./lib/state-manager.sh cleanup-backups [days]
# Default: keeps last 5 backups, older than 7 days
```

#### Programming Interface

```bash
#!/bin/bash
source "./lib/state-manager.sh"

# Lock state for atomic operations
if lock_state 30; then
    # Read current state
    current_state=$(read_state)
    
    # Modify state
    updated_state=$(echo "$current_state" | jq '.phase = 2')
    
    # Write atomically
    write_state "$updated_state" "phase transition"
    
    # Release lock
    unlock_state
else
    echo "Failed to acquire state lock"
    exit 1
fi
```

#### State Schema Validation

```bash
# Validate against schema
validate_state_schema() {
    local state_content="$1"
    local schema_version="$2"
    
    # Required fields validation
    jq -e '.version' <<< "$state_content" >/dev/null || return 1
    jq -e '.pipeline_id' <<< "$state_content" >/dev/null || return 1
    jq -e '.current_phase' <<< "$state_content" >/dev/null || return 1
    
    # Type validation
    [[ $(jq -r '.current_phase | type' <<< "$state_content") == "number" ]] || return 1
    
    return 0
}
```

### Error Handling

```bash
# Error codes
STATE_SUCCESS=0
STATE_ERROR_LOCK=1
STATE_ERROR_VALIDATION=2
STATE_ERROR_CORRUPTION=3
STATE_ERROR_PERMISSION=4
STATE_ERROR_SCHEMA=5

# Error recovery
recover_from_corruption() {
    local corrupted_file="$1"
    
    # Try latest backup
    local latest_backup=$(ls -t .state-backups/*.json | head -1)
    if [[ -n "$latest_backup" ]]; then
        cp "$latest_backup" "$corrupted_file"
        return 0
    fi
    
    # Try template
    if [[ -f "config/workflow-state.template.json" ]]; then
        cp "config/workflow-state.template.json" "$corrupted_file"
        return 0
    fi
    
    return 1
}
```

## Worktree Manager API

**Module**: `lib/worktree-manager.sh`

### Core Operations

```bash
# Create new worktree
./lib/worktree-manager.sh create <phase> <task> [base_branch]
# Example: ./lib/worktree-manager.sh create 1 1 main
# Returns: 0 on success, 1 on error

# List all worktrees
./lib/worktree-manager.sh list [--format=json|table]
# Output: Formatted list of worktrees
# Returns: 0 on success

# Get worktree status
./lib/worktree-manager.sh status [worktree_name]
# Output: Detailed status information
# Returns: 0 on success, 1 if not found

# Validate worktree isolation
./lib/worktree-manager.sh validate <worktree_name>
# Output: Validation report
# Returns: 0 if valid, 1 if violations found

# Merge worktree to main
./lib/worktree-manager.sh merge <worktree_name> [--strategy=merge|squash]
# Returns: 0 on success, 1 on conflicts, 2 on validation failure

# Cleanup worktree
./lib/worktree-manager.sh cleanup <worktree_name> [--force] [--archive]
# Returns: 0 on success, 1 on error
```

### Advanced Operations

```bash
# Archive worktree before cleanup
./lib/worktree-manager.sh archive <worktree_name> [archive_path]
# Creates: ./archives/{worktree_name}-{timestamp}.tar.gz
# Returns: 0 on success, 1 on error

# Recover from archive
./lib/worktree-manager.sh recover <archive_file> [new_name]
# Returns: 0 on success, 1 on error

# Repair worktree state
./lib/worktree-manager.sh repair [--all]
# Synchronizes state with actual git worktrees
# Returns: 0 on success, 1 on error

# Cleanup all completed worktrees
./lib/worktree-manager.sh cleanup-all [--older-than=hours]
# Returns: number of cleaned worktrees
```

### Programming Interface

```bash
#!/bin/bash
source "./lib/worktree-manager.sh"

# Create and use worktree
create_worktree() {
    local phase="$1"
    local task="$2"
    
    local worktree_name="phase-${phase}-task-${task}"
    
    # Create worktree
    if create_git_worktree "$worktree_name" "$phase" "$task"; then
        # Update state tracking
        update_worktree_state "$worktree_name" "active" "$phase" "$task"
        echo "Worktree created: $worktree_name"
        return 0
    else
        echo "Failed to create worktree: $worktree_name"
        return 1
    fi
}

# Validate before merge
validate_worktree_merge() {
    local worktree_name="$1"
    
    # Check git status
    if ! is_worktree_clean "$worktree_name"; then
        echo "Worktree has uncommitted changes"
        return 1
    fi
    
    # Check isolation
    if ! validate_worktree_isolation "$worktree_name"; then
        echo "Worktree isolation validation failed"
        return 1
    fi
    
    # Check required outputs
    if ! validate_required_outputs "$worktree_name"; then
        echo "Required output files missing"
        return 1
    fi
    
    return 0
}
```

### State Schema

```json
{
  "version": "1.0",
  "worktrees": {
    "phase-1-task-1": {
      "status": "active|completed|merged|archived",
      "phase": 1,
      "task": 1,
      "skill": "prd-to-tasks",
      "branch": "phase-1-task-1", 
      "path": "./worktrees/phase-1-task-1",
      "base_commit": "abc123def456",
      "created_at": "ISO8601",
      "last_activity": "ISO8601",
      "changes": ["tasks.json", ".signals/phase1-start.json"],
      "merge_status": "pending|merged|failed"
    }
  },
  "active_worktree": "phase-1-task-1",
  "last_updated": "ISO8601"
}
```

## Lock Manager API

**Module**: `lib/lock-manager.sh`

### Lock Operations

```bash
# Acquire exclusive lock
./lib/lock-manager.sh acquire <resource_name> [timeout_seconds]
# Returns: 0 on success, 1 on timeout, 2 on error

# Release lock
./lib/lock-manager.sh release <resource_name>
# Returns: 0 on success, 1 if not held, 2 on error

# Check lock status
./lib/lock-manager.sh check <resource_name>
# Output: Lock status information
# Returns: 0 if locked, 1 if free

# List all locks
./lib/lock-manager.sh list [--format=json|table]
# Output: All current locks with metadata

# Force release lock (dangerous)
./lib/lock-manager.sh force-release <resource_name>
# Returns: 0 on success, 1 on error

# Cleanup stale locks
./lib/lock-manager.sh cleanup [max_age_minutes]
# Default: removes locks older than 30 minutes
```

### Programming Interface

```bash
#!/bin/bash
source "./lib/lock-manager.sh"

# Safe lock pattern
safe_operation() {
    local resource="$1"
    local timeout="${2:-30}"
    
    if acquire_lock "$resource" "$timeout"; then
        trap "release_lock '$resource'" EXIT
        
        # Perform protected operations
        echo "Lock acquired for $resource"
        # ... do work ...
        
        release_lock "$resource"
        trap - EXIT
        return 0
    else
        echo "Failed to acquire lock for $resource"
        return 1
    fi
}

# Lock hierarchy (prevents deadlocks)
acquire_multiple_locks() {
    local locks=("$@")
    local acquired=()
    
    # Sort locks alphabetically to ensure consistent order
    IFS=$'\n' sorted_locks=($(sort <<<"${locks[*]}"))
    
    # Acquire in order
    for lock in "${sorted_locks[@]}"; do
        if acquire_lock "$lock" 30; then
            acquired+=("$lock")
        else
            # Release any acquired locks
            for acquired_lock in "${acquired[@]}"; do
                release_lock "$acquired_lock"
            done
            return 1
        fi
    done
    
    return 0
}
```

### Lock Types and Hierarchy

```bash
# Lock hierarchy (to prevent deadlocks)
LOCK_HIERARCHY=(
    "state"          # Level 1: Global state
    "worktree"       # Level 2: Worktree operations  
    "config"         # Level 3: Configuration
    "files"          # Level 4: File operations
)

# Shared vs Exclusive locks
acquire_shared_lock() {
    local resource="$1"
    local timeout="$2"
    # Multiple readers allowed
}

acquire_exclusive_lock() {
    local resource="$1" 
    local timeout="$2"
    # Single writer only
}
```

## Error Recovery API

**Module**: `lib/error-recovery.sh`

### Recovery Operations

```bash
# Create checkpoint
./lib/error-recovery.sh checkpoint <checkpoint_name> <phase>
# Creates: .checkpoints/{checkpoint_name}-{timestamp}
# Returns: 0 on success, 1 on error

# Restore from checkpoint
./lib/error-recovery.sh restore <checkpoint_name>
# Returns: 0 on success, 1 on error

# List available checkpoints
./lib/error-recovery.sh list-checkpoints
# Output: List of checkpoints with metadata

# Attempt automatic recovery
./lib/error-recovery.sh auto-recover [error_type]
# Returns: 0 on success, 1 if manual intervention needed

# Enable degraded mode
./lib/error-recovery.sh degrade <reason>
# Disables non-essential features
# Returns: 0 on success

# Disable degraded mode
./lib/error-recovery.sh restore-full-operation
# Re-enables all features
# Returns: 0 on success
```

### Error Classification

```bash
# Error types (from error-recovery.sh)
ERROR_LOCK_TIMEOUT=1
ERROR_STATE_CORRUPTION=2
ERROR_WORKTREE_FAILURE=3
ERROR_SKILL_FAILURE=4
ERROR_HOOK_FAILURE=5
ERROR_PERMISSION_DENIED=6
ERROR_DISK_FULL=7
ERROR_NETWORK_FAILURE=8
ERROR_DEPENDENCY_MISSING=9
ERROR_VALIDATION_FAILURE=10
ERROR_MERGE_CONFLICT=11
ERROR_RESOURCE_EXHAUSTION=12
ERROR_CONFIGURATION_ERROR=13
ERROR_UNKNOWN=14
ERROR_CRITICAL_SYSTEM=15

# Recovery strategies
get_recovery_strategy() {
    local error_type="$1"
    
    case "$error_type" in
        $ERROR_LOCK_TIMEOUT)
            echo "cleanup_stale_locks"
            ;;
        $ERROR_STATE_CORRUPTION)
            echo "restore_from_backup"
            ;;
        $ERROR_WORKTREE_FAILURE)
            echo "recreate_worktree"
            ;;
        $ERROR_SKILL_FAILURE)
            echo "retry_with_checkpoint"
            ;;
        *)
            echo "manual_intervention"
            ;;
    esac
}
```

### Programming Interface

```bash
#!/bin/bash
source "./lib/error-recovery.sh"

# Resilient operation pattern
resilient_operation() {
    local operation="$1"
    local max_retries="${2:-3}"
    local backoff_base="${3:-2}"
    
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        # Create checkpoint before risky operation
        local checkpoint="operation-${operation}-${attempt}"
        create_checkpoint "$checkpoint" "$(get_current_phase)"
        
        # Attempt operation
        if eval "$operation"; then
            echo "Operation succeeded on attempt $attempt"
            cleanup_checkpoint "$checkpoint"
            return 0
        else
            local error_code=$?
            echo "Operation failed on attempt $attempt (error: $error_code)"
            
            # Restore from checkpoint
            restore_checkpoint "$checkpoint"
            
            # Calculate backoff delay
            local delay=$((backoff_base ** (attempt - 1)))
            echo "Retrying in ${delay} seconds..."
            sleep "$delay"
            
            ((attempt++))
        fi
    done
    
    echo "Operation failed after $max_retries attempts"
    enter_degraded_mode "repeated_operation_failure"
    return 1
}
```

## Logger API

**Module**: `lib/logger.sh`

### Logging Functions

```bash
# Source the logger
source "./lib/logger.sh"

# Log levels
log_debug "Debug message"
log_info "Information message"  
log_warn "Warning message"
log_error "Error message"
log_fatal "Fatal error message"

# Structured logging
log_structured() {
    local level="$1"
    local component="$2"
    local event="$3"
    local metadata="$4"
    
    # Creates structured JSON log entry
}

# Performance logging
log_performance() {
    local operation="$1"
    local duration_ms="$2"
    local metadata="$3"
}
```

### Log Configuration

```bash
# Configuration options
CLAUDE_LOG_LEVEL="${CLAUDE_LOG_LEVEL:-info}"    # debug|info|warn|error|fatal
CLAUDE_LOG_FORMAT="${CLAUDE_LOG_FORMAT:-text}"  # text|json
CLAUDE_LOG_FILE="${CLAUDE_LOG_FILE:-logs/pipeline.log}"
CLAUDE_LOG_MAX_SIZE="${CLAUDE_LOG_MAX_SIZE:-10M}"
CLAUDE_LOG_MAX_FILES="${CLAUDE_LOG_MAX_FILES:-5}"

# Component-specific logging
CLAUDE_HOOK_LOG_LEVEL="${CLAUDE_HOOK_LOG_LEVEL:-$CLAUDE_LOG_LEVEL}"
CLAUDE_SKILL_LOG_LEVEL="${CLAUDE_SKILL_LOG_LEVEL:-$CLAUDE_LOG_LEVEL}"
CLAUDE_STATE_LOG_LEVEL="${CLAUDE_STATE_LOG_LEVEL:-$CLAUDE_LOG_LEVEL}"
```

### Log Output Format

```bash
# Text format
2023-11-01T15:30:45.123Z [INFO] state-manager/write: State updated successfully (phase: 2)

# JSON format
{
  "timestamp": "2023-11-01T15:30:45.123Z",
  "level": "INFO", 
  "component": "state-manager",
  "event": "write",
  "message": "State updated successfully",
  "metadata": {
    "phase": 2,
    "duration_ms": 45,
    "files_changed": ["tasks.json"]
  }
}
```

## Configuration API

### Configuration Files

#### Main Settings (`config/settings.json`)

```json
{
  "version": "3.0",
  "hooks": {
    "UserPromptSubmit": {
      "enabled": true,
      "script": "skill-activation-prompt.sh",
      "timeout": 5000
    },
    "PostToolUse": {
      "enabled": true, 
      "script": "post-tool-use-tracker.sh",
      "timeout": 10000
    }
  },
  "pipeline": {
    "automationLevel": 95,
    "phaseTransitions": {
      "autoAdvance": true,
      "timeoutMinutes": 30
    },
    "skillActivation": {
      "mode": "codeword-injection",
      "fallbackToKeywords": false,
      "debugMode": false
    }
  },
  "logging": {
    "level": "info",
    "format": "text",
    "hookExecution": true,
    "skillActivation": true
  }
}
```

#### Skill Rules (`config/skill-rules.json`)

```json
{
  "version": "2.0",
  "activation_mode": "codeword",
  "skills": [
    {
      "skill": "prd-to-tasks",
      "activation_code": "PRD_TO_TASKS_V1",
      "phase": 1,
      "trigger_conditions": {
        "user_patterns": ["generate tasks", "parse prd"],
        "file_patterns": ["PRD.md", "requirements.md"],
        "phase_state": "ready_for_phase1"
      },
      "outputs": {
        "files": ["tasks.json"],
        "signals": ["PHASE1_START"],
        "next_activation": "COUPLING_ANALYSIS_V1"
      },
      "priority": 2
    }
  ],
  "phase_transitions": {
    "PHASE1_START": {
      "next_activation": "COUPLING_ANALYSIS_V1",
      "auto_trigger": true,
      "delay_seconds": 2
    }
  }
}
```

### Configuration Access API

```bash
#!/bin/bash

# Read configuration value
get_config_value() {
    local key_path="$1"
    local config_file="${2:-config/settings.json}"
    
    jq -r "$key_path" "$config_file" 2>/dev/null || echo "null"
}

# Update configuration value
set_config_value() {
    local key_path="$1"
    local value="$2"
    local config_file="${3:-config/settings.json}"
    
    local temp_file=$(mktemp)
    jq "$key_path = $value" "$config_file" > "$temp_file" && 
    mv "$temp_file" "$config_file"
}

# Examples
automation_level=$(get_config_value '.pipeline.automationLevel')
debug_mode=$(get_config_value '.pipeline.skillActivation.debugMode')

set_config_value '.logging.level' '"debug"'
set_config_value '.pipeline.automationLevel' '85'
```

### Environment Variable Override

```bash
# Configuration precedence:
# 1. Environment variables (highest)
# 2. Local config files (.claude/settings.local.json)
# 3. Default config files (.claude/settings.json)
# 4. Built-in defaults (lowest)

# Example environment overrides
export CLAUDE_LOG_LEVEL=debug
export CLAUDE_AUTOMATION_LEVEL=75
export CLAUDE_WORKTREE_AUTO_CLEANUP=true
export CLAUDE_HOOK_TIMEOUT=10000
```

---

This API reference provides comprehensive documentation for integrating with and extending the Claude Dev Pipeline system. All APIs follow consistent patterns for error handling, logging, and configuration management.

**Next**: Continue to [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed problem resolution guidance.