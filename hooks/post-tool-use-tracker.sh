#!/bin/bash
# =============================================================================
# Post-Tool-Use Tracker Hook (PostToolUse)
# =============================================================================
# 
# Tracks workflow progress and triggers next-phase skills:
# - Detects when tasks.json is created → Trigger coupling analysis
# - Detects when OpenSpec proposal created → Trigger test strategy
# - Detects when tests written → Track TDD compliance
# - Detects when architecture.md read → Trigger integration validator
#
# This hook runs after EVERY tool execution.
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$CLAUDE_DIR/.workflow-state.json"

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
  echo '{"phase":"pre-init","completedTasks":[],"signals":{}}' > "$STATE_FILE"
fi

# Parse tool use event
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool // ""')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.input // ""')

# Function to update workflow state
update_state() {
  local phase="$1"
  local signal="$2"
  jq --arg phase "$phase" --arg signal "$signal" \
    '.phase = $phase | .signals[$signal] = now | .lastUpdate = now' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Function to emit skill suggestion
suggest_skill() {
  local skill="$1"
  local reason="$2"
  echo ""
  echo "🎯 **Workflow Transition Detected**"
  echo "**Next Skill:** $skill"
  echo "**Reason:** $reason"
  echo ""
}

# Detect workflow transitions based on tool usage

case "$TOOL_NAME" in
  
  "Write"|"Create")
    # Check what file was created
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.path // ""')
    
    # Phase 1: Task decomposition complete
    if [[ "$FILE_PATH" == *"tasks.json"* ]]; then
      update_state "phase1-complete" "tasks_created"
      suggest_skill "coupling-analysis" "tasks.json created - analyze task coupling for Phase 2 strategy"
    fi
    
    # Phase 2: OpenSpec proposal created
    if [[ "$FILE_PATH" == *".openspec"* ]] && [[ "$FILE_PATH" == *"proposal"* ]]; then
      update_state "phase2-in-progress" "proposal_created"
      suggest_skill "test-strategy-generator" "OpenSpec proposal created - generate test strategy before implementation"
    fi
    
    # Phase 3: Test files created
    if [[ "$FILE_PATH" == *"test"* ]] || [[ "$FILE_PATH" == *".spec."* ]] || [[ "$FILE_PATH" == *".test."* ]]; then
      update_state "phase3-tdd" "tests_written"
      echo "✅ TDD: Tests written first (CORRECT)"
    fi
    
    # Phase 3: Implementation files created
    if [[ "$FILE_PATH" == *"src/"* ]] || [[ "$FILE_PATH" == *"lib/"* ]]; then
      # Check if tests exist first
      TEST_EXISTS=$(jq -r '.signals.tests_written // empty' "$STATE_FILE")
      if [ -z "$TEST_EXISTS" ]; then
        echo "⚠️  WARNING: Implementation file created without tests"
        echo "**TDD Violation**: Write tests FIRST"
      else
        echo "✅ TDD: Implementation after tests (CORRECT)"
      fi
    fi
    ;;
    
  "Read")
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.path // ""')
    
    # Phase 4: Integration validation triggered
    if [[ "$FILE_PATH" == *"architecture.md"* ]]; then
      update_state "phase4-integration" "architecture_reviewed"
      suggest_skill "integration-validator" "architecture.md read - validate integration points"
    fi
    
    # Task #24, #25, #26 detection
    if [[ "$FILE_PATH" == *"tasks.json"* ]]; then
      TASK_NUM=$(echo "$TOOL_INPUT" | grep -oP 'Task #\K[0-9]+' || echo "")
      if [[ "$TASK_NUM" =~ ^(24|25|26)$ ]]; then
        suggest_skill "integration-validator" "Integration/E2E/Production task detected - use validation checklist"
      fi
    fi
    ;;
    
  "Bash")
    COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')
    
    # TaskMaster show command
    if [[ "$COMMAND" == *"task-master show"* ]]; then
      suggest_skill "coupling-analysis" "task-master show detected - analyze coupling"
    fi
    
    # OpenSpec commands
    if [[ "$COMMAND" == *"openspec"* ]]; then
      if [[ "$COMMAND" == *"proposal"* ]]; then
        suggest_skill "test-strategy-generator" "OpenSpec proposal command - prepare test strategy"
      fi
    fi
    
    # Test execution
    if [[ "$COMMAND" == *"test"* ]] || [[ "$COMMAND" == *"jest"* ]] || [[ "$COMMAND" == *"pytest"* ]] || [[ "$COMMAND" == *"npm test"* ]]; then
      update_state "testing" "tests_executed"
      echo "✅ Tests executed"
    fi
    
    # Coverage check
    if [[ "$COMMAND" == *"coverage"* ]]; then
      echo "✅ Coverage check performed"
    fi
    ;;
    
esac

exit 0