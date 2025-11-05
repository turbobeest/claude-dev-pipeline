#!/bin/bash
# =============================================================================
# Enable Manual Mode - Disable Auto-Transitions
# =============================================================================
#
# This script switches the pipeline to manual-control mode where:
# - All phase transitions STOP and wait for user slash command
# - Very obvious banners show phase completion and next command
# - No automatic codeword injection
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔧 Enabling Manual Mode..."
echo ""

# Backup current config
if [ -f "$PIPELINE_ROOT/config/skill-rules.json" ]; then
    cp "$PIPELINE_ROOT/config/skill-rules.json" "$PIPELINE_ROOT/config/skill-rules.auto-mode.json.backup"
    echo "✅ Backed up current config to skill-rules.auto-mode.json.backup"
fi

# Install manual mode config
cp "$PIPELINE_ROOT/config/skill-rules.manual-mode.json" "$PIPELINE_ROOT/config/skill-rules.json"
echo "✅ Installed manual-mode configuration"

# Update .claude settings if in project
if [ -d "$PWD/.claude" ] && [ -f "$PWD/.claude/config/skill-rules.json" ]; then
    cp "$PIPELINE_ROOT/config/skill-rules.json" "$PWD/.claude/config/skill-rules.json"
    echo "✅ Updated project .claude/config/skill-rules.json"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    MANUAL MODE ENABLED                         "
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Phase transitions now require EXPLICIT slash commands:"
echo ""
echo "  Phase 1 Complete → Type: /generate-specs"
echo "  Phase 2 Complete → Type: /implement-tdd"
echo "  Phase 3 Complete → Type: /validate-integration"
echo "  Phase 4 Complete → Type: /validate-integration"
echo "  Phase 5 Complete → Type: /validate-e2e"
echo "  Phase 6 Complete → Type: /deploy"
echo ""
echo "You will see VERY OBVIOUS BANNERS when each phase completes."
echo ""
echo "To revert to auto-transition mode:"
echo "  bash $SCRIPT_DIR/disable-manual-mode.sh"
echo ""
echo "═══════════════════════════════════════════════════════════════"
