#!/bin/bash
# =============================================================================
# Skill Activation Hook - Intelligent Orchestrator
# =============================================================================
#
# This hook orchestrates the entire automated development pipeline by:
# 1. Detecting user patterns → Injecting skill activation codewords
# 2. Monitoring signal files → Auto-triggering next skills
# 3. Managing workflow state → Tracking phase progress
# 4. Reading skill-rules.json → Dynamic skill configuration
#
# Output: JSON with injectedText field containing skill activation codeword
# =============================================================================

set -euo pipefail

# Determine project directory
if [ -n "${CLAUDE_WORKING_DIR:-}" ]; then
    PROJECT_DIR="$CLAUDE_WORKING_DIR"
elif [ -f ".taskmaster/config.json" ]; then
    PROJECT_DIR="$(pwd)"
else
    PROJECT_DIR="$(pwd)"
fi

# Paths
SKILL_RULES="$PROJECT_DIR/config/skill-rules.json"
WORKFLOW_STATE="$PROJECT_DIR/.claude/.workflow-state.json"
SIGNALS_DIR="$PROJECT_DIR/.claude/.signals"
LOG_FILE="$PROJECT_DIR/.claude/logs/skill-activations.log"

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")" "$SIGNALS_DIR" 2>/dev/null || true

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

log_debug() { log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }

# =============================================================================
# Input Processing
# =============================================================================

# Read stdin input
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract message
if command -v jq >/dev/null 2>&1; then
    MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')
else
    MESSAGE=$(echo "$INPUT" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 | tr '[:upper:]' '[:lower:]' || echo "")
fi

log_debug "Received message: $MESSAGE"

# =============================================================================
# Workflow State Management
# =============================================================================

get_current_phase() {
    if [ -f "$WORKFLOW_STATE" ]; then
        jq -r '.phase // "pre-init"' "$WORKFLOW_STATE" 2>/dev/null || echo "pre-init"
    else
        echo "pre-init"
    fi
}

get_active_skills() {
    if [ -f "$WORKFLOW_STATE" ]; then
        jq -r '.context.activeSkills[]? // empty' "$WORKFLOW_STATE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

update_workflow_state() {
    local phase="$1"
    local skill="$2"

    if [ -f "$WORKFLOW_STATE" ]; then
        local temp_file
        temp_file=$(mktemp)
        jq --arg phase "$phase" --arg skill "$skill" '
            .phase = $phase |
            .lastActivation = $skill |
            .context.activeSkills = [$skill] |
            .metadata.lastUpdated = (now | todate)
        ' "$WORKFLOW_STATE" > "$temp_file"
        mv "$temp_file" "$WORKFLOW_STATE"
        log_info "Updated workflow state: phase=$phase, skill=$skill"
    fi
}

# =============================================================================
# Signal Detection
# =============================================================================

check_signals() {
    if [ ! -d "$SIGNALS_DIR" ]; then
        return 1
    fi

    # Check for recent signals (modified in last 60 seconds)
    local recent_signals
    recent_signals=$(find "$SIGNALS_DIR" -name "*.json" -type f -mmin -1 2>/dev/null || true)

    if [ -n "$recent_signals" ]; then
        log_debug "Recent signals detected: $recent_signals"
        echo "$recent_signals" | while read -r signal_file; do
            local signal_name
            signal_name=$(basename "$signal_file" .json)
            echo "$signal_name"
        done
    fi
}

get_next_skill_for_signal() {
    local signal="$1"

    if [ ! -f "$SKILL_RULES" ]; then
        log_error "skill-rules.json not found"
        return 1
    fi

    # Look up next activation for this signal
    jq -r --arg signal "$signal" '
        .phase_transitions[$signal].next_activation // empty
    ' "$SKILL_RULES" 2>/dev/null || echo ""
}

# =============================================================================
# Pattern Matching
# =============================================================================

match_pattern() {
    local message="$1"
    local pattern="$2"

    # Convert pattern to lowercase and check for match
    pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')

    if echo "$message" | grep -qiE "$pattern_lower"; then
        return 0
    fi
    return 1
}

find_matching_skill() {
    local message="$1"

    if [ ! -f "$SKILL_RULES" ]; then
        log_error "skill-rules.json not found at $SKILL_RULES"
        return 1
    fi

    # Extract all skills and their patterns
    local skills
    skills=$(jq -r '.skills[] |
        .activation_code as $code |
        .trigger_conditions.user_patterns[]? |
        [$code, .] | @tsv
    ' "$SKILL_RULES" 2>/dev/null || echo "")

    if [ -z "$skills" ]; then
        log_debug "No skills found in skill-rules.json"
        return 1
    fi

    # Check each pattern
    while IFS=$'\t' read -r activation_code pattern; do
        if match_pattern "$message" "$pattern"; then
            log_info "Pattern matched: '$pattern' -> $activation_code"
            echo "$activation_code"
            return 0
        fi
    done <<< "$skills"

    log_debug "No matching skill pattern for message"
    return 1
}

# =============================================================================
# File Pattern Detection
# =============================================================================

check_file_patterns() {
    local activation_code="$1"

    # Get file patterns for this skill
    local file_patterns
    file_patterns=$(jq -r --arg code "$activation_code" '
        .skills[] |
        select(.activation_code == $code) |
        .trigger_conditions.file_patterns[]? // empty
    ' "$SKILL_RULES" 2>/dev/null || echo "")

    if [ -z "$file_patterns" ]; then
        return 0  # No file requirements
    fi

    # Check if any required file exists
    local pattern_matched=false
    while IFS= read -r pattern; do
        if [ -n "$pattern" ]; then
            # Handle multiple possible locations
            for test_path in "$PROJECT_DIR/$pattern" "$PROJECT_DIR/docs/$pattern" "$PROJECT_DIR/$pattern.md"; do
                if [ -e "$test_path" ] || ls $test_path 1> /dev/null 2>&1; then
                    log_debug "File pattern matched: $pattern (found at $test_path)"
                    pattern_matched=true
                    break 2
                fi
            done
        fi
    done <<< "$file_patterns"

    if [ "$pattern_matched" = true ]; then
        return 0
    fi

    log_debug "No matching file patterns for $activation_code"
    return 1
}

# =============================================================================
# Large PRD Detection
# =============================================================================

check_large_prd() {
    for prd_path in "$PROJECT_DIR/docs/PRD.md" "$PROJECT_DIR/PRD.md" "$PROJECT_DIR/docs/prd.md"; do
        if [ -f "$prd_path" ]; then
            file_size=$(wc -c < "$prd_path" 2>/dev/null || echo "0")
            estimated_tokens=$((file_size * 3 / 4))

            if [ "$estimated_tokens" -gt 25000 ]; then
                log_info "Large PRD detected: $prd_path (~$estimated_tokens tokens)"

                # Output warning message
                cat <<EOF

⚠️ **LARGE PRD DETECTED** (~$estimated_tokens tokens)

**CRITICAL:** Use large-file-reader for PRDs > 25K tokens:

\`\`\`bash
./.claude/lib/large-file-reader.sh $prd_path
\`\`\`

The PRD-to-Tasks skill will automatically use large-file-reader.
**Do NOT** use Read tool directly on this file.

---

EOF
                return 0
            fi
        fi
    done
    return 1
}

# =============================================================================
# Main Activation Logic
# =============================================================================

activate_skill() {
    local message="$1"

    log_info "Processing activation request"

    # Check for recent signals that should trigger next skill
    local signals
    signals=$(check_signals)

    if [ -n "$signals" ]; then
        log_info "Processing signals: $signals"

        # Get most recent signal
        local latest_signal
        latest_signal=$(echo "$signals" | head -n1)

        # Find next skill for this signal
        local next_activation
        next_activation=$(get_next_skill_for_signal "$latest_signal")

        if [ -n "$next_activation" ]; then
            log_info "Signal '$latest_signal' triggers next skill: $next_activation"

            # Inject codeword for next skill
            local output
            output=$(jq -n --arg code "$next_activation" '{
                "injectedText": "[ACTIVATE:\($code)]",
                "reason": "Signal-triggered activation",
                "signal": "'$latest_signal'"
            }')

            echo "$output"

            # Update workflow state
            local phase
            phase=$(jq -r --arg code "$next_activation" '
                .skills[] | select(.activation_code == $code) | .phase // 1
            ' "$SKILL_RULES" 2>/dev/null || echo "1")

            update_workflow_state "$phase" "$next_activation"
            return 0
        fi
    fi

    # No signals - check user message patterns
    local activation_code
    activation_code=$(find_matching_skill "$message")

    if [ -n "$activation_code" ]; then
        # Check file pattern requirements
        if check_file_patterns "$activation_code"; then
            log_info "Activating skill: $activation_code"

            # Check for large PRD if activating PRD-to-Tasks
            if [ "$activation_code" = "PRD_TO_TASKS_V1" ]; then
                check_large_prd
            fi

            # Inject codeword
            local output
            output=$(jq -n --arg code "$activation_code" '{
                "injectedText": "[ACTIVATE:\($code)]",
                "reason": "User pattern matched"
            }')

            echo "$output"

            # Update workflow state
            local phase
            phase=$(jq -r --arg code "$activation_code" '
                .skills[] | select(.activation_code == $code) | .phase // 1
            ' "$SKILL_RULES" 2>/dev/null || echo "1")

            update_workflow_state "$phase" "$activation_code"
            return 0
        else
            log_info "Skill $activation_code matched but file requirements not met"
        fi
    fi

    # No activation
    log_debug "No skill activation triggered"
    return 1
}

# =============================================================================
# Entry Point
# =============================================================================

main() {
    if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
        log_debug "No message to process"
        exit 0
    fi

    # Try to activate a skill
    if ! activate_skill "$MESSAGE"; then
        # No activation - check if we should still show large PRD warning
        if echo "$MESSAGE" | grep -qiE "prd|requirements|generate.*task"; then
            check_large_prd
        fi
    fi

    exit 0
}

main "$@"
