#!/bin/bash
# =============================================================================
# Skill Activation Hook (UserPromptSubmit) - Simplified Fault-Tolerant Version
# =============================================================================
#
# This is a simplified version that prioritizes reliability over features.
# Use this version if the full hook has dependency issues.
#
# =============================================================================

set +e  # Don't exit on errors - always succeed

# Try to run the real hook logic, but always succeed
{
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"

    # Read input with timeout
    INPUT=$(timeout 5s cat 2>/dev/null || echo '{}')

    # If we have skill rules, try to process
    if [ -f "$CLAUDE_DIR/config/skill-rules.json" ]; then
        # Extract message (works even if jq not available)
        if command -v jq >/dev/null 2>&1; then
            MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null)
        else
            # Fallback: simple grep
            MESSAGE=$(echo "$INPUT" | grep -oP '"message"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        fi

        # Convert to lowercase for case-insensitive matching
        MESSAGE_LOWER=$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]')

        # Simple detection logic
        if echo "$MESSAGE_LOWER" | grep -Eq "prd|begin.*(automated|development)|start.*development|generate.*tasks"; then
            echo '{"injectedText":"[ACTIVATE:PRD_TO_TASKS_V1]"}'
            exit 0
        fi

        if echo "$MESSAGE_LOWER" | grep -Eq "decompose.*tasks|expand.*tasks|task.*complexity"; then
            echo '{"injectedText":"[ACTIVATE:TASK_DECOMPOSER_V1]"}'
            exit 0
        fi

        if echo "$MESSAGE_LOWER" | grep -Eq "generate.*spec|create.*openspec|write.*specification"; then
            echo '{"injectedText":"[ACTIVATE:SPEC_GEN_V1]"}'
            exit 0
        fi
    fi

    # Default: return empty response (no activation)
    echo '{}'
} 2>/dev/null

# Always succeed
exit 0
