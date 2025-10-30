#!/bin/bash
# =============================================================================
# Pre-Implementation Validator Hook (PreToolUse)
# =============================================================================
# 
# Enforces TDD by blocking implementation writes unless tests exist.
#
# This hook runs BEFORE Write/Create operations to validate TDD compliance.
#
# =============================================================================

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool // ""')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.input // ""')

# Only validate Write/Create operations
if [[ "$TOOL_NAME" != "Write" ]] && [[ "$TOOL_NAME" != "Create" ]]; then
  exit 0
fi

FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.path // ""')

# Check if this is an implementation file (not test file)
if [[ "$FILE_PATH" == *"src/"* ]] || [[ "$FILE_PATH" == *"lib/"* ]]; then
  if [[ "$FILE_PATH" != *"test"* ]] && [[ "$FILE_PATH" != *".spec."* ]] && [[ "$FILE_PATH" != *".test."* ]]; then
    
    # Derive test file path based on common conventions
    TEST_FILE=""
    
    # JavaScript/TypeScript patterns
    if [[ "$FILE_PATH" == *.js ]] || [[ "$FILE_PATH" == *.ts ]] || [[ "$FILE_PATH" == *.jsx ]] || [[ "$FILE_PATH" == *.tsx ]]; then
      # Try common test locations
      # 1. tests/ directory parallel to src/
      TEST_FILE="${FILE_PATH/src\//tests\/}"
      TEST_FILE="${TEST_FILE%.js}.test.js"
      TEST_FILE="${TEST_FILE%.ts}.test.ts"
      TEST_FILE="${TEST_FILE%.jsx}.test.jsx"
      TEST_FILE="${TEST_FILE%.tsx}.test.tsx"
      
      # 2. __tests__ directory
      if [ ! -f "$TEST_FILE" ]; then
        TEST_FILE_ALT="${FILE_PATH/src\//src\/__tests__\/}"
        TEST_FILE_ALT="${TEST_FILE_ALT%.js}.test.js"
        TEST_FILE_ALT="${TEST_FILE_ALT%.ts}.test.ts"
        if [ -f "$TEST_FILE_ALT" ]; then
          TEST_FILE="$TEST_FILE_ALT"
        fi
      fi
      
      # 3. .spec pattern
      if [ ! -f "$TEST_FILE" ]; then
        TEST_FILE_SPEC="${FILE_PATH%.js}.spec.js"
        TEST_FILE_SPEC="${FILE_PATH%.ts}.spec.ts"
        if [ -f "$TEST_FILE_SPEC" ]; then
          TEST_FILE="$TEST_FILE_SPEC"
        fi
      fi
    fi
    
    # Python patterns
    if [[ "$FILE_PATH" == *.py ]]; then
      # 1. tests/ directory
      TEST_FILE="${FILE_PATH/src\//tests\/}"
      TEST_FILE="${TEST_FILE%.py}_test.py"
      
      # 2. test_ prefix pattern
      if [ ! -f "$TEST_FILE" ]; then
        DIR=$(dirname "$FILE_PATH")
        FILENAME=$(basename "$FILE_PATH")
        TEST_FILE_ALT="$DIR/test_$FILENAME"
        if [ -f "$TEST_FILE_ALT" ]; then
          TEST_FILE="$TEST_FILE_ALT"
        fi
      fi
    fi
    
    # Ruby patterns
    if [[ "$FILE_PATH" == *.rb ]]; then
      TEST_FILE="${FILE_PATH/lib\//spec\/}"
      TEST_FILE="${TEST_FILE%.rb}_spec.rb"
    fi
    
    # Go patterns
    if [[ "$FILE_PATH" == *.go ]]; then
      TEST_FILE="${FILE_PATH%.go}_test.go"
    fi
    
    # Check if test file exists
    if [ ! -f "$TEST_FILE" ]; then
      echo "❌ **TDD VIOLATION**"
      echo ""
      echo "**File:** $FILE_PATH"
      echo "**Error:** Tests must be written FIRST"
      echo "**Expected test file:** $TEST_FILE"
      echo ""
      echo "**Action Required:** Create test file before implementation"
      echo ""
      echo "**TDD Process:**"
      echo "1. Write failing tests (RED)"
      echo "2. Write minimum code to pass tests (GREEN)"
      echo "3. Refactor (REFACTOR)"
      exit 1  # Block the write operation
    fi
  fi
fi

exit 0