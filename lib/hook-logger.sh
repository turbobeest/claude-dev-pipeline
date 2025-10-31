#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Hook Logging Wrapper
# =============================================================================
#
# This script wraps hook execution with comprehensive logging.
# Source this in hooks to get automatic logging of all activities.
#
# Usage (in hooks):
#   source "$(dirname "$0")/../lib/hook-logger.sh"
#   log_hook_start "skill-activation"
#   # ... hook logic ...
#   log_hook_success "Activated skill: $skill_name"
#
# =============================================================================

# Determine paths
HOOK_NAME="${HOOK_NAME:-$(basename "${BASH_SOURCE[1]}" .sh)}"
HOOK_LOG_DIR="${PROJECT_ROOT:-/tmp}/.claude/logs"
HOOK_LOG_FILE="${HOOK_LOG_DIR}/hooks.log"
PIPELINE_LOG="${HOOK_LOG_DIR}/pipeline.log"

# Create log directory
mkdir -p "$HOOK_LOG_DIR"

# =============================================================================
# Logging Functions
# =============================================================================

log_to_file() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] [HOOK:$HOOK_NAME] $message"
    
    # Log to both hook log and main pipeline log
    echo "$log_entry" >> "$HOOK_LOG_FILE"
    echo "$log_entry" >> "$PIPELINE_LOG"
    
    # Also output to stderr for debugging
    if [[ "${HOOK_DEBUG:-false}" == "true" ]]; then
        echo "$log_entry" >&2
    fi
}

log_json() {
    local level="$1"
    local message="$2"
    local extra_fields="${3:-}"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    local json_log=$(jq -n \
        --arg ts "$timestamp" \
        --arg lvl "$level" \
        --arg hook "$HOOK_NAME" \
        --arg msg "$message" \
        --arg phase "${PIPELINE_PHASE:-unknown}" \
        --arg session "${SESSION_ID:-unknown}" \
        --argjson extra "${extra_fields:-{}}" \
        '{
            timestamp: $ts,
            level: $lvl,
            hook: $hook,
            message: $msg,
            phase: $phase,
            session: $session,
            metadata: $extra
        }')
    
    echo "$json_log" >> "${HOOK_LOG_DIR}/hooks.json"
}

# =============================================================================
# Hook Lifecycle Logging
# =============================================================================

log_hook_start() {
    local context="${1:-}"
    log_to_file "INFO" "Hook started: $context"
    log_json "INFO" "Hook started" "{\"context\": \"$context\"}"
    
    # Record start time for performance metrics
    export HOOK_START_TIME=$(date +%s)
}

log_hook_success() {
    local message="${1:-Hook completed successfully}"
    log_to_file "SUCCESS" "$message"
    log_json "SUCCESS" "$message" "{}"
    
    # Calculate and log duration
    if [[ -n "${HOOK_START_TIME:-}" ]]; then
        local duration=$(($(date +%s) - HOOK_START_TIME))
        log_to_file "METRIC" "Hook execution time: ${duration}s"
        log_json "METRIC" "Hook duration" "{\"duration\": $duration, \"unit\": \"seconds\"}"
    fi
}

log_hook_error() {
    local message="${1:-Hook failed}"
    local error_code="${2:-1}"
    log_to_file "ERROR" "$message (code: $error_code)"
    log_json "ERROR" "$message" "{\"error_code\": $error_code}"
}

log_hook_warning() {
    local message="${1:-}"
    log_to_file "WARNING" "$message"
    log_json "WARNING" "$message" "{}"
}

# =============================================================================
# Skill Activation Logging
# =============================================================================

log_skill_activation() {
    local skill_name="$1"
    local activation_code="$2"
    local trigger="${3:-manual}"
    
    log_to_file "ACTIVATE" "Skill: $skill_name | Code: $activation_code | Trigger: $trigger"
    log_json "ACTIVATE" "Skill activated" \
        "{\"skill\": \"$skill_name\", \"code\": \"$activation_code\", \"trigger\": \"$trigger\"}"
    
    # Also log to main pipeline with special marker
    echo "[ACTIVATE:$activation_code] $skill_name triggered by $trigger" >> "$PIPELINE_LOG"
}

log_codeword_injection() {
    local original_input="$1"
    local injected_codeword="$2"
    
    log_to_file "INJECT" "Codeword: $injected_codeword"
    log_json "INJECT" "Codeword injected" \
        "{\"codeword\": \"$injected_codeword\", \"input_length\": ${#original_input}}"
}

# =============================================================================
# Phase Transition Logging
# =============================================================================

log_phase_transition() {
    local from_phase="$1"
    local to_phase="$2"
    local signal="${3:-}"
    
    log_to_file "PHASE" "Transition: $from_phase → $to_phase (signal: $signal)"
    log_json "PHASE" "Phase transition" \
        "{\"from\": \"$from_phase\", \"to\": \"$to_phase\", \"signal\": \"$signal\"}"
    
    # Log to main pipeline with special marker
    echo "[SIGNAL:$signal] Phase transition: $from_phase → $to_phase" >> "$PIPELINE_LOG"
}

log_signal_emission() {
    local signal="$1"
    local context="${2:-}"
    
    log_to_file "SIGNAL" "Emitted: $signal | Context: $context"
    log_json "SIGNAL" "Signal emitted" \
        "{\"signal\": \"$signal\", \"context\": \"$context\"}"
}

# =============================================================================
# State Management Logging
# =============================================================================

log_state_update() {
    local field="$1"
    local old_value="$2"
    local new_value="$3"
    
    log_to_file "STATE" "Updated $field: $old_value → $new_value"
    log_json "STATE" "State updated" \
        "{\"field\": \"$field\", \"old\": \"$old_value\", \"new\": \"$new_value\"}"
}

# =============================================================================
# Performance Metrics
# =============================================================================

log_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-}"
    
    log_to_file "METRIC" "$metric_name: $value $unit"
    log_json "METRIC" "$metric_name" \
        "{\"value\": $value, \"unit\": \"$unit\"}"
    
    # Also append to metrics file for analysis
    echo "$(date '+%s'),$metric_name,$value,$unit" >> "${HOOK_LOG_DIR}/metrics.csv"
}

# =============================================================================
# Initialize Hook Logging
# =============================================================================

# Create initial log entry
log_hook_start "Initialized from ${BASH_SOURCE[1]:-unknown}"

# Set up error trap
trap 'log_hook_error "Hook terminated unexpectedly" $?' ERR

# Export functions for use in hooks
export -f log_to_file log_json log_hook_start log_hook_success log_hook_error
export -f log_hook_warning log_skill_activation log_codeword_injection
export -f log_phase_transition log_signal_emission log_state_update log_metric