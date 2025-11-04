#!/bin/bash
# =============================================================================
# Claude Code Version Checker - Update Notification Hook
# =============================================================================
#
# Checks Claude Code version and alerts when UserPromptSubmit bug is fixed.
# Runs on SessionStart to provide immediate feedback.
#
# Known Issue: UserPromptSubmit hooks are broken in Claude Code v2.0.27+
# GitHub Issue: https://github.com/anthropics/claude-code/issues/10287
#
# =============================================================================

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_WORKING_DIR:-$(pwd)}"
ALERT_FILE="$PROJECT_DIR/.claude/.version-alert-shown"

# Get Claude Code version
CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

# Known broken versions (2.0.27 through at least 2.0.32)
BROKEN_MIN="2.0.27"
BROKEN_MAX="2.0.32"  # Update this when the bug is fixed

# Parse version into comparable format
version_to_number() {
    echo "$1" | awk -F. '{ printf("%d%03d%03d\n", $1, $2, $3) }'
}

CURRENT_NUM=$(version_to_number "$CLAUDE_VERSION")
BROKEN_MIN_NUM=$(version_to_number "$BROKEN_MIN")
BROKEN_MAX_NUM=$(version_to_number "$BROKEN_MAX")

# Check if version is in broken range
if [[ $CURRENT_NUM -ge $BROKEN_MIN_NUM ]] && [[ $CURRENT_NUM -le $BROKEN_MAX_NUM ]]; then
    # Show alert only once per session
    if [[ ! -f "$ALERT_FILE" ]]; then
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║  ⚠️  CLAUDE CODE v$CLAUDE_VERSION - KNOWN BUG ACTIVE           ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "🐛 UserPromptSubmit hooks are BROKEN in Claude Code v2.0.27+"
        echo "   GitHub Issue: https://github.com/anthropics/claude-code/issues/10287"
        echo ""
        echo "✅ WORKAROUND ACTIVE: Using PreToolUse hooks instead"
        echo "   Your pipeline will still work, but with limited skill activation"
        echo ""
        echo "🔔 When the bug is fixed:"
        echo "   1. Update Claude Code: Check https://github.com/anthropics/claude-code/releases"
        echo "   2. Update this pipeline: cd claude-dev-pipeline && git pull"
        echo "   3. Reinstall: ./install.sh /path/to/your/project"
        echo ""

        # Create alert file to prevent repeated notifications
        mkdir -p "$(dirname "$ALERT_FILE")"
        echo "Alert shown at $(date)" > "$ALERT_FILE"
    fi
elif [[ $CURRENT_NUM -gt $BROKEN_MAX_NUM ]]; then
    # Version is NEWER than known broken versions - bug might be fixed!
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  🎉 NEW CLAUDE CODE VERSION DETECTED: v$CLAUDE_VERSION       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🔥 YOUR CLAUDE CODE IS NEWER THAN THE LAST KNOWN BROKEN VERSION!"
    echo ""
    echo "⚡ ACTION REQUIRED:"
    echo "   1. Check if UserPromptSubmit bug is fixed:"
    echo "      https://github.com/anthropics/claude-code/issues/10287"
    echo ""
    echo "   2. UPDATE THE PIPELINE IMMEDIATELY:"
    echo "      cd /path/to/claude-dev-pipeline"
    echo "      git pull origin deploy"
    echo "      ./install.sh $PROJECT_DIR"
    echo ""
    echo "   3. Test UserPromptSubmit hooks:"
    echo "      Try: 'generate tasks from my PRD'"
    echo "      Check logs: tail -f .claude/logs/skill-activations.log"
    echo ""
    echo "📧 Report findings to pipeline maintainer"
    echo ""
fi

# Always pass through - don't block
echo "{}"
