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

# Read input from stdin (no timeout - hooks are already time-limited by Claude)
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract message
MESSAGE=""
if command -v jq >/dev/null 2>&1; then
    MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null || echo "")
else
    # Fallback: extract message field manually
    MESSAGE=$(echo "$INPUT" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || echo "")
fi

# Convert to lowercase for case-insensitive matching
MESSAGE_LOWER=$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]' 2>/dev/null || echo "")

# Simple detection logic - check for PRD-related keywords
if echo "$MESSAGE_LOWER" | grep -Eq "prd|begin.*(automated|development)|start.*development|generate.*tasks" 2>/dev/null; then
    echo '{"injectedText":"[ACTIVATE:PRD_TO_TASKS_V1]"}'
    exit 0
fi

if echo "$MESSAGE_LOWER" | grep -Eq "decompose.*tasks|expand.*tasks|task.*complexity" 2>/dev/null; then
    echo '{"injectedText":"[ACTIVATE:TASK_DECOMPOSER_V1]"}'
    exit 0
fi

if echo "$MESSAGE_LOWER" | grep -Eq "generate.*spec|create.*openspec|write.*specification" 2>/dev/null; then
    echo '{"injectedText":"[ACTIVATE:SPEC_GEN_V1]"}'
    exit 0
fi

# Default: return empty response (no activation)
echo '{}'

# Always succeed
exit 0
