#!/bin/bash
# =============================================================================
# Post-Tool-Use Tracker Hook - Simplified Fault-Tolerant Version
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
    LOG_FILE="$CLAUDE_DIR/.tool-usage.log"

    # Read input with timeout
    INPUT=$(timeout 5s cat 2>/dev/null || echo '{}')

    # Optional: Log tool usage for debugging
    if [ "${CLAUDE_DEBUG:-}" = "true" ]; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $INPUT" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Extract tool name if available
    if command -v jq >/dev/null 2>&1; then
        TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName // ""' 2>/dev/null)

        # Simple workflow tracking (optional)
        if [ "$TOOL_NAME" = "Write" ] && [ -f "$CLAUDE_DIR/.workflow-state.json" ]; then
            # Could update workflow state here if needed
            : # No-op for now
        fi
    fi

    # Default: return empty response
    echo '{}'
} 2>/dev/null

# Always succeed
exit 0
