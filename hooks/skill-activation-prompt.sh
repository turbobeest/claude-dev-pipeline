#!/bin/bash
# =============================================================================
# Skill Activation Hook (UserPromptSubmit)
# =============================================================================
# 
# Automatically suggests relevant skills based on:
# - User's message content
# - Files currently in context
# - Current workflow phase
#
# This hook runs on EVERY user message to Claude Code.
#
# =============================================================================

set -euo pipefail

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_RULES="$CLAUDE_DIR/skill-rules.json"

# Parse hook event data from stdin
INPUT=$(cat)
USER_MESSAGE=$(echo "$INPUT" | jq -r '.message // ""')
CONTEXT_FILES=$(echo "$INPUT" | jq -r '.contextFiles[]? // empty' | tr '\n' '|')

# Read skill rules
if [ ! -f "$SKILL_RULES" ]; then
  # Silently exit if skill-rules.json not found
  exit 0
fi

# Initialize suggestions array
SUGGESTIONS=()

# Function to check if pattern matches (case-insensitive)
matches_pattern() {
  local pattern="$1"
  local text="$2"
  echo "$text" | grep -qi "$pattern"
}

# Check each skill rule
while IFS= read -r rule; do
  SKILL_NAME=$(echo "$rule" | jq -r '.skill')
  TRIGGERS=$(echo "$rule" | jq -r '.triggers[]')
  FILE_PATTERNS=$(echo "$rule" | jq -r '.filePatterns[]? // empty')
  
  SHOULD_ACTIVATE=false
  
  # Check message triggers
  for trigger in $TRIGGERS; do
    if matches_pattern "$trigger" "$USER_MESSAGE"; then
      SHOULD_ACTIVATE=true
      break
    fi
  done
  
  # Check file patterns if defined
  if [ -n "$FILE_PATTERNS" ] && [ -n "$CONTEXT_FILES" ]; then
    for pattern in $FILE_PATTERNS; do
      if echo "$CONTEXT_FILES" | grep -q "$pattern"; then
        SHOULD_ACTIVATE=true
        break
      fi
    done
  fi
  
  # Add to suggestions if matched
  if [ "$SHOULD_ACTIVATE" = true ]; then
    SUGGESTIONS+=("$SKILL_NAME")
  fi
done < <(jq -c '.skills[]' "$SKILL_RULES")

# Output suggestions if any matched
if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
  echo "📋 **Relevant Skills Detected:**"
  echo ""
  for skill in "${SUGGESTIONS[@]}"; do
    echo "- **$skill**"
  done
  echo ""
  echo "I'll use these skills to guide my response."
fi

exit 0