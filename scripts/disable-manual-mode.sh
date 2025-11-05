#!/bin/bash
# =============================================================================
# Disable Manual Mode - Restore Auto-Transitions
# =============================================================================
#
# This script restores automatic phase transitions.
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔄 Disabling Manual Mode (restoring auto-transitions)..."
echo ""

# Restore backup if it exists
if [ -f "$PIPELINE_ROOT/config/skill-rules.auto-mode.json.backup" ]; then
    cp "$PIPELINE_ROOT/config/skill-rules.auto-mode.json.backup" "$PIPELINE_ROOT/config/skill-rules.json"
    echo "✅ Restored auto-mode configuration from backup"
else
    echo "⚠️  No backup found. Manual mode remains active."
    echo "   To restore auto-mode, copy from: config/skill-rules.auto-mode.json.backup"
    exit 1
fi

# Update .claude settings if in project
if [ -d "$PWD/.claude" ] && [ -f "$PWD/.claude/config/skill-rules.json" ]; then
    cp "$PIPELINE_ROOT/config/skill-rules.json" "$PWD/.claude/config/skill-rules.json"
    echo "✅ Updated project .claude/config/skill-rules.json"
fi

echo ""
echo "✅ AUTO-TRANSITION MODE RESTORED"
echo ""
echo "Phase transitions will now happen automatically via PostToolUse hook."
echo ""
