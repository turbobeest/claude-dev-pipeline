#!/bin/bash
# =============================================================================
# Pre-Implementation Validator Hook (PreToolUse)
# =============================================================================
# 
# Enforces TDD by blocking implementation writes unless tests exist.
# Validates worktree isolation and TDD compliance.
#
# This hook runs BEFORE Write/Create operations to validate TDD compliance.
#
# =============================================================================

# Comprehensive error handling and security
set -euo pipefail
set +H  # Disable history expansion

# Timeout for the entire script (30 seconds)
timeout 30s bash -c 'exec "$0" "$@"' "$0" "$@" 2>/dev/null || exit 1

# Security and validation settings
readonly SCRIPT_NAME="$(basename "$0")"
readonly AUDIT_LOG="/tmp/claude-pipeline-audit.log"
readonly MAX_INPUT_SIZE=1048576  # 1MB max input
readonly MAX_TOOL_INPUT_SIZE=524288  # 512KB max tool input
readonly MAX_FILE_PATH_LENGTH=1000

# Cleanup trap
trap 'cleanup_and_exit' EXIT INT TERM

# Audit logging function
audit_log() {
    local level="$1"
    local message="$2"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [$level] $SCRIPT_NAME: $message" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Cleanup function
cleanup_and_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        audit_log "ERROR" "Script exited with code $exit_code"
    fi
    exit $exit_code
}

# Input validation functions
validate_json() {
    local json_string="$1"
    local max_size="${2:-$MAX_INPUT_SIZE}"
    
    # Check size
    if [ ${#json_string} -gt $max_size ]; then
        audit_log "ERROR" "JSON input too large: ${#json_string} bytes"
        return 1
    fi
    
    # Validate JSON syntax
    if ! echo "$json_string" | jq empty 2>/dev/null; then
        audit_log "ERROR" "Invalid JSON input"
        return 1
    fi
    
    return 0
}

validate_file_path() {
    local file_path="$1"
    
    # Check length
    if [ ${#file_path} -gt $MAX_FILE_PATH_LENGTH ]; then
        audit_log "ERROR" "File path too long: ${#file_path} chars"
        return 1
    fi
    
    # Check for path traversal attempts
    if [[ "$file_path" == *".."* ]] || [[ "$file_path" == *"~"* ]]; then
        audit_log "ERROR" "Path traversal attempt detected: $file_path"
        return 1
    fi
    
    # Must be absolute path or relative to working directory
    if [[ "$file_path" == /* ]]; then
        # Absolute path - additional security check
        if [[ "$file_path" != "/Users/"* ]] && [[ "$file_path" != "/tmp/"* ]] && [[ "$file_path" != "/var/tmp/"* ]]; then
            # Allow only user directories and temp directories
            audit_log "WARN" "Suspicious absolute path: $file_path"
        fi
    fi
    
    return 0
}

sanitize_string() {
    local input="$1"
    local max_length="${2:-1000}"
    
    # Truncate if too long
    if [ ${#input} -gt $max_length ]; then
        input="${input:0:$max_length}"
        audit_log "WARN" "Input truncated to $max_length characters"
    fi
    
    # Remove potentially dangerous characters
    echo "$input" | tr -cd '[:alnum:][:space:][:punct:]' | head -c $max_length
}

# Schema validation for hook input
validate_hook_input() {
    local input="$1"
    
    # Required fields validation
    if ! echo "$input" | jq -e '.tool' >/dev/null 2>&1; then
        audit_log "ERROR" "Missing required field: tool"
        return 1
    fi
    
    # Validate tool input if present
    if echo "$input" | jq -e '.input' >/dev/null 2>&1; then
        local tool_input_size
        tool_input_size=$(echo "$input" | jq -r '.input | tostring | length' 2>/dev/null || echo 0)
        if [ "$tool_input_size" -gt $MAX_TOOL_INPUT_SIZE ]; then
            audit_log "ERROR" "Tool input too large: $tool_input_size bytes"
            return 1
        fi
    fi
    
    return 0
}

# TDD compliance checker
check_tdd_compliance() {
    local file_path="$1"
    local file_extension="${file_path##*.}"
    local dir_name="$(dirname "$file_path")"
    local base_name="$(basename "$file_path" ".$file_extension")"
    
    # List of possible test file patterns
    local test_patterns=()
    
    case "$file_extension" in
        "js"|"jsx"|"ts"|"tsx")
            # JavaScript/TypeScript patterns
            test_patterns+=(
                "${dir_name}/../tests/${base_name}.test.${file_extension}"
                "${dir_name}/../__tests__/${base_name}.test.${file_extension}"
                "${dir_name}/__tests__/${base_name}.test.${file_extension}"
                "${dir_name}/${base_name}.test.${file_extension}"
                "${dir_name}/${base_name}.spec.${file_extension}"
                "${file_path%.*}.test.${file_extension}"
                "${file_path%.*}.spec.${file_extension}"
            )
            ;;
        "py")
            # Python patterns
            test_patterns+=(
                "${dir_name}/../tests/test_${base_name}.py"
                "${dir_name}/test_${base_name}.py"
                "${dir_name}/../tests/${base_name}_test.py"
                "${dir_name}/${base_name}_test.py"
            )
            ;;
        "rb")
            # Ruby patterns
            test_patterns+=(
                "${dir_name}/../spec/${base_name}_spec.rb"
                "${dir_name}/spec/${base_name}_spec.rb"
                "${dir_name}/../test/test_${base_name}.rb"
                "${dir_name}/test/test_${base_name}.rb"
            )
            ;;
        "go")
            # Go patterns
            test_patterns+=(
                "${dir_name}/${base_name}_test.go"
                "${file_path%.*}_test.go"
            )
            ;;
        "java")
            # Java patterns (simplified)
            test_patterns+=(
                "${dir_name}/../test/java/**/${base_name}Test.java"
                "${dir_name}/test/${base_name}Test.java"
            )
            ;;
        "rs")
            # Rust patterns
            test_patterns+=(
                "${dir_name}/tests/${base_name}.rs"
                "${dir_name}/../tests/${base_name}.rs"
            )
            ;;
        "c"|"cpp"|"cc"|"cxx")
            # C/C++ patterns
            test_patterns+=(
                "${dir_name}/test_${base_name}.${file_extension}"
                "${dir_name}/../tests/test_${base_name}.${file_extension}"
            )
            ;;
    esac
    
    # Check if any test file exists
    for pattern in "${test_patterns[@]}"; do
        # Resolve relative paths safely
        local resolved_pattern
        resolved_pattern=$(timeout 5s realpath "$pattern" 2>/dev/null || echo "$pattern")
        
        # Validate the resolved path
        if validate_file_path "$resolved_pattern" && [ -f "$resolved_pattern" ] && [ -r "$resolved_pattern" ]; then
            audit_log "INFO" "Found test file for $file_path: $resolved_pattern"
            return 0
        fi
    done
    
    # No test file found
    audit_log "WARN" "No test file found for implementation: $file_path"
    return 1
}

# Enhanced worktree isolation checker with worktree manager integration
check_worktree_isolation() {
    local file_path="$1"
    
    # Check if we're in a git repository
    if ! timeout 5s git rev-parse --git-dir >/dev/null 2>&1; then
        audit_log "INFO" "Not in a git repository, skipping worktree isolation check"
        return 0
    fi
    
    # Check if worktree manager is available and use it for enhanced validation
    if [ -f "$PIPELINE_ROOT/lib/worktree-manager.sh" ]; then
        source "$PIPELINE_ROOT/lib/worktree-manager.sh" 2>/dev/null || {
            audit_log "WARN" "Failed to source worktree manager, falling back to basic validation"
        }
        
        # Get current worktree context
        local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
        audit_log "INFO" "Validating file operation in worktree: $current_worktree"
        
        # If in a pipeline worktree, enforce strict isolation
        if [[ "$current_worktree" =~ ^phase-([0-9]+)-task-([0-9]+)$ ]]; then
            local phase="${BASH_REMATCH[1]}"
            local task="${BASH_REMATCH[2]}"
            
            # Validate worktree isolation using worktree enforcer
            if [ -f "$PIPELINE_ROOT/hooks/worktree-enforcer.sh" ]; then
                if ! "$PIPELINE_ROOT/hooks/worktree-enforcer.sh" validate 2>/dev/null; then
                    audit_log "ERROR" "Worktree isolation validation failed for $current_worktree"
                    return 1
                fi
            fi
            
            # Ensure file is being created within the correct worktree boundaries
            local worktree_path=$(jq -r --arg name "$current_worktree" '.worktrees[$name].path // empty' "$PIPELINE_ROOT/config/worktree-state.json" 2>/dev/null || echo "")
            
            if [ -n "$worktree_path" ] && [[ "$file_path" == /* ]]; then
                if [[ "$file_path" != "$worktree_path"* ]]; then
                    audit_log "ERROR" "File being created outside worktree boundaries: $file_path (expected within: $worktree_path)"
                    return 1
                fi
            fi
            
            audit_log "INFO" "Worktree isolation validated for phase $phase, task $task"
        elif [ "$current_worktree" = "main" ]; then
            # In main repository - check if this should be in a worktree
            if [ -n "${CLAUDE_CURRENT_PHASE:-}" ] && [ -n "${CLAUDE_CURRENT_TASK:-}" ]; then
                local expected_worktree=$(generate_worktree_name "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK")
                audit_log "WARN" "File operation in main repository, but pipeline context suggests worktree: $expected_worktree"
                
                # Auto-create worktree if enabled
                if [ "${CLAUDE_AUTO_CREATE_WORKTREES:-true}" = "true" ]; then
                    audit_log "INFO" "Auto-creating required worktree: $expected_worktree"
                    if create_worktree "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK" >/dev/null 2>&1; then
                        local new_worktree_path=$(jq -r --arg name "$expected_worktree" '.worktrees[$name].path' "$PIPELINE_ROOT/config/worktree-state.json" 2>/dev/null || echo "")
                        audit_log "ERROR" "Worktree created but operation should be performed there: $new_worktree_path"
                        echo "# Switch to the correct worktree for this operation:"
                        echo "cd \"$new_worktree_path\""
                        return 1
                    fi
                fi
            fi
        fi
    fi
    
    # Fallback to basic git repository validation
    local git_root
    git_root=$(timeout 5s git rev-parse --show-toplevel 2>/dev/null || echo "")
    
    if [ -n "$git_root" ] && ! validate_file_path "$git_root"; then
        audit_log "ERROR" "Invalid git root path: $git_root"
        return 1
    fi
    
    # If file path is absolute, check if it's within the git repository
    if [[ "$file_path" == /* ]] && [ -n "$git_root" ]; then
        if [[ "$file_path" != "$git_root"* ]]; then
            audit_log "WARN" "File being created outside git repository: $file_path"
            return 1
        fi
    fi
    
    # Check for uncommitted changes that might conflict
    if timeout 10s git status --porcelain 2>/dev/null | grep -q "^M.*$file_path$"; then
        audit_log "INFO" "File has uncommitted changes: $file_path"
    fi
    
    return 0
}

# Parse and validate hook event data from stdin
INPUT=$(timeout 10s cat 2>/dev/null || { audit_log "ERROR" "Input read timeout"; exit 1; })

# Validate input is not empty
if [ -z "$INPUT" ]; then
    audit_log "ERROR" "Empty input received"
    exit 1
fi

# Validate JSON and input schema
if ! validate_json "$INPUT"; then
    audit_log "ERROR" "JSON validation failed"
    exit 1
fi

if ! validate_hook_input "$INPUT"; then
    audit_log "ERROR" "Hook input validation failed"
    exit 1
fi

# Extract and sanitize tool information
TOOL_NAME_RAW=$(echo "$INPUT" | jq -r '.tool // ""' 2>/dev/null || echo "")
TOOL_INPUT_RAW=$(echo "$INPUT" | jq -r '.input // ""' 2>/dev/null || echo "")

TOOL_NAME=$(sanitize_string "$TOOL_NAME_RAW" 100)
TOOL_INPUT=$(sanitize_string "$TOOL_INPUT_RAW" $MAX_TOOL_INPUT_SIZE)

audit_log "INFO" "Validating tool: $TOOL_NAME"

# Only validate Write/Create/MultiEdit operations
if [[ "$TOOL_NAME" != "Write" ]] && [[ "$TOOL_NAME" != "Create" ]] && [[ "$TOOL_NAME" != "MultiEdit" ]]; then
    audit_log "INFO" "Tool $TOOL_NAME does not require TDD validation"
    exit 0
fi

# Extract file path from tool input (handle both formats)
FILE_PATH_RAW=""
if echo "$TOOL_INPUT_RAW" | jq -e '.file_path' >/dev/null 2>&1; then
    FILE_PATH_RAW=$(echo "$TOOL_INPUT_RAW" | jq -r '.file_path // ""' 2>/dev/null)
elif echo "$TOOL_INPUT_RAW" | jq -e '.path' >/dev/null 2>&1; then
    FILE_PATH_RAW=$(echo "$TOOL_INPUT_RAW" | jq -r '.path // ""' 2>/dev/null)
fi

if [ -z "$FILE_PATH_RAW" ]; then
    audit_log "WARN" "No file path found in tool input for $TOOL_NAME"
    exit 0
fi

FILE_PATH=$(sanitize_string "$FILE_PATH_RAW" $MAX_FILE_PATH_LENGTH)

# Validate file path
if ! validate_file_path "$FILE_PATH"; then
    audit_log "ERROR" "Invalid file path: $FILE_PATH"
    echo "❌ **SECURITY VIOLATION**"
    echo ""
    echo "**File:** $FILE_PATH"
    echo "**Error:** Invalid or potentially dangerous file path"
    echo ""
    exit 1
fi

audit_log "INFO" "Validating file: $FILE_PATH"

# Check worktree isolation
if ! check_worktree_isolation "$FILE_PATH"; then
    audit_log "WARN" "Worktree isolation check failed for: $FILE_PATH"
    echo "⚠️ **WORKTREE ISOLATION WARNING**"
    echo ""
    echo "**File:** $FILE_PATH"
    echo "**Warning:** File is being created outside the expected working area"
    echo ""
    # This is a warning, not a blocking error
fi

# Determine if this is an implementation file that requires TDD
is_implementation_file=false
is_test_file=false

# Check if this is a test file
if [[ "$FILE_PATH" == *"test"* ]] || [[ "$FILE_PATH" == *".spec."* ]] || [[ "$FILE_PATH" == *".test."* ]] || 
   [[ "$FILE_PATH" == *"__tests__"* ]] || [[ "$FILE_PATH" == *"/spec/"* ]] || [[ "$FILE_PATH" == *"_test."* ]] ||
   [[ "$FILE_PATH" == *"Test."* ]] || [[ "$FILE_PATH" == *"_spec."* ]]; then
    is_test_file=true
    audit_log "INFO" "Identified as test file: $FILE_PATH"
fi

# Check if this is an implementation file in source directories
if [[ "$FILE_PATH" == *"src/"* ]] || [[ "$FILE_PATH" == *"lib/"* ]] || [[ "$FILE_PATH" == *"app/"* ]] ||
   [[ "$FILE_PATH" == *"components/"* ]] || [[ "$FILE_PATH" == *"services/"* ]] || [[ "$FILE_PATH" == *"utils/"* ]] ||
   [[ "$FILE_PATH" == *"models/"* ]] || [[ "$FILE_PATH" == *"controllers/"* ]]; then
    
    # Only consider it implementation if it's not a test file
    if [ "$is_test_file" = false ]; then
        is_implementation_file=true
        audit_log "INFO" "Identified as implementation file: $FILE_PATH"
    fi
fi

# Skip validation for non-implementation files
if [ "$is_implementation_file" = false ]; then
    if [ "$is_test_file" = true ]; then
        audit_log "INFO" "Test file creation allowed: $FILE_PATH"
        echo "✅ **TDD COMPLIANCE:** Test file creation"
        echo ""
        echo "**File:** $FILE_PATH"
        echo "**Status:** Test file - proceeding with creation"
        echo ""
    else
        audit_log "INFO" "Non-implementation file, skipping TDD validation: $FILE_PATH"
    fi
    exit 0
fi

# For implementation files, enforce TDD by checking for tests
if ! check_tdd_compliance "$FILE_PATH"; then
    # Generate suggested test file name based on the implementation file
    file_extension="${FILE_PATH##*.}"
    dir_name="$(dirname "$FILE_PATH")"
    base_name="$(basename "$FILE_PATH" ".$file_extension")"
    
    suggested_test_file=""
    case "$file_extension" in
        "js"|"jsx"|"ts"|"tsx")
            suggested_test_file="${dir_name}/${base_name}.test.${file_extension}"
            ;;
        "py")
            suggested_test_file="${dir_name}/test_${base_name}.py"
            ;;
        "rb")
            suggested_test_file="${dir_name}/../spec/${base_name}_spec.rb"
            ;;
        "go")
            suggested_test_file="${dir_name}/${base_name}_test.go"
            ;;
        *)
            suggested_test_file="${dir_name}/${base_name}.test.${file_extension}"
            ;;
    esac
    
    audit_log "ERROR" "TDD violation blocked: $FILE_PATH (no test file found)"
    
    echo "❌ **TDD VIOLATION**"
    echo ""
    echo "**File:** $FILE_PATH"
    echo "**Error:** Tests must be written FIRST"
    echo "**Expected test file:** $suggested_test_file"
    echo ""
    echo "**Action Required:** Create test file before implementation"
    echo ""
    echo "**TDD Process:**"
    echo "1. 🔴 Write failing tests (RED)"
    echo "2. 🟢 Write minimum code to pass tests (GREEN)"  
    echo "3. 🔵 Refactor (REFACTOR)"
    echo ""
    echo "**Security Note:** This enforcement prevents implementation-first development"
    echo "which can lead to untested, potentially buggy code in production."
    echo ""
    
    exit 1  # Block the write operation
fi

# TDD compliance check passed
audit_log "INFO" "TDD compliance check passed for: $FILE_PATH"
echo "✅ **TDD COMPLIANCE VERIFIED**"
echo ""
echo "**File:** $FILE_PATH"
echo "**Status:** Implementation file with corresponding tests found"
echo "**Result:** Proceeding with implementation (GREEN phase)"
echo ""

exit 0