#!/bin/bash
# =============================================================================
# PreToolUse Skill Activator - Workaround for Broken UserPromptSubmit
# =============================================================================
#
# WORKAROUND: UserPromptSubmit hooks are broken in Claude Code v2.0.27+
# This PreToolUse hook detects task-master commands and injects skill context.
#
# This is a temporary workaround until the bug is fixed.
# GitHub Issue: https://github.com/anthropics/claude-code/issues/10287
#
# =============================================================================

set -euo pipefail

# Read stdin input
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract tool name and arguments
if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName // ""' 2>/dev/null || echo "")
    TOOL_INPUT=$(echo "$INPUT" | jq -r '.toolInput // ""' 2>/dev/null || echo "")
else
    TOOL_NAME=""
    TOOL_INPUT=""
fi

# Only process Bash tool
if [[ "$TOOL_NAME" != "Bash" ]]; then
    echo "{}"
    exit 0
fi

# Check if this is a task-master parse-prd command
if echo "$TOOL_INPUT" | grep -q "task-master parse-prd"; then
    # Get project directory
    PROJECT_DIR="${CLAUDE_WORKING_DIR:-$(pwd)}"

    # Check if PRD exists
    PRD_FILE=""
    if [[ -f "$PROJECT_DIR/docs/PRD.md" ]]; then
        PRD_FILE="$PROJECT_DIR/docs/PRD.md"
    elif [[ -f "$PROJECT_DIR/PRD.md" ]]; then
        PRD_FILE="$PROJECT_DIR/PRD.md"
    fi

    # Calculate PRD size if found
    PRD_INFO=""
    if [[ -n "$PRD_FILE" ]]; then
        PRD_TOKENS=$(wc -w < "$PRD_FILE" | awk '{print int($1 * 1.3)}')  # Rough token estimate
        if [[ $PRD_TOKENS -gt 25000 ]]; then
            PRD_INFO="

⚠️  **LARGE PRD DETECTED** (~$PRD_TOKENS tokens)

**RECOMMENDATION:** For PRDs > 25K tokens, use the large-file-reader:

\`\`\`bash
./.claude/lib/large-file-reader.sh $PRD_FILE
\`\`\`

The PRD-to-Tasks skill handles this automatically.
**Do NOT** use Read tool directly on large files.

---"
        fi
    fi

    # Inject skill activation context
    cat <<EOF
{
  "hookSpecificOutput": {
    "additionalContext": "${PRD_INFO}

🔧 **SKILL ACTIVATION** (PreToolUse Workaround)

Pattern detected: task-master parse-prd
Skill: PRD_TO_TASKS_V1

⚡ This uses the PreToolUse workaround because UserPromptSubmit hooks
are broken in Claude Code v2.0.27-2.0.32.

Expected workflow:
1. Parse PRD with task-master
2. Generate tasks with native schema (subtasks: [])
3. Emit signal for next phase

---"
  }
}
EOF
else
    # Pass through for other commands
    echo "{}"
fi
