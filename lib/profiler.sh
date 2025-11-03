#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Performance Profiler
# =============================================================================
#
# Lightweight profiling utilities for performance monitoring
#
# Usage:
#   source lib/profiler.sh
#   profile_start "operation_name"
#   # ... do work ...
#   duration=$(profile_end "operation_name")
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Configuration
PROFILER_SESSION_ID="${PROFILER_SESSION_ID:-$(uuidgen 2>/dev/null || echo "$$-$(date +%s)")}"
PROFILER_ENABLED="${PROFILER_ENABLED:-true}"

# Storage for profile timings
declare -A PROFILE_START_TIMES

# =============================================================================
# Core Profiling Functions
# =============================================================================

# Start profiling an operation
profile_start() {
    local operation_name="$1"

    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        return 0
    fi

    # Store start time in milliseconds
    if command -v gdate >/dev/null 2>&1; then
        # GNU date (via brew install coreutils on macOS)
        PROFILE_START_TIMES["$operation_name"]=$(gdate +%s%3N)
    elif date --version 2>&1 | grep -q GNU; then
        # GNU date (Linux)
        PROFILE_START_TIMES["$operation_name"]=$(date +%s%3N)
    else
        # BSD date (macOS default) - second precision only
        PROFILE_START_TIMES["$operation_name"]=$(date +%s)000
    fi
}

# End profiling an operation and return duration
profile_end() {
    local operation_name="$1"

    if [[ "$PROFILER_ENABLED" != "true" ]]; then
        echo "0"
        return 0
    fi

    # Get end time
    local end_time
    if command -v gdate >/dev/null 2>&1; then
        end_time=$(gdate +%s%3N)
    elif date --version 2>&1 | grep -q GNU; then
        end_time=$(date +%s%3N)
    else
        end_time=$(date +%s)000
    fi

    # Get start time
    local start_time="${PROFILE_START_TIMES[$operation_name]:-$end_time}"

    # Calculate duration in milliseconds
    local duration=$((end_time - start_time))

    # Clean up
    unset PROFILE_START_TIMES["$operation_name"]

    # Return duration
    echo "$duration"
}

# Profile a command execution
profile_command() {
    local operation_name="$1"
    shift
    local command_to_run=("$@")

    profile_start "$operation_name"
    "${command_to_run[@]}"
    local exit_code=$?
    local duration=$(profile_end "$operation_name")

    if [[ "$PROFILER_ENABLED" == "true" ]]; then
        echo "⏱️  $operation_name: ${duration}ms" >&2
    fi

    return $exit_code
}

# =============================================================================
# Utility Functions
# =============================================================================

# Enable profiler
profiler_enable() {
    PROFILER_ENABLED=true
}

# Disable profiler
profiler_disable() {
    PROFILER_ENABLED=false
}

# Get profiler status
profiler_status() {
    echo "Profiler: $PROFILER_ENABLED"
    echo "Session ID: $PROFILER_SESSION_ID"
}

# Reset all profile data
profiler_reset() {
    PROFILE_START_TIMES=()
}

# =============================================================================
# Initialization
# =============================================================================

# Export session ID for child processes
export PROFILER_SESSION_ID

# Mark as initialized
export PROFILER_INITIALIZED=true
