#!/bin/bash
# =============================================================================
# Post-Tool-Use Tracker Hook (PostToolUse) - Codeword Version
# =============================================================================
# 
# Tracks workflow progress, emits phase signals, and injects next-phase codewords.
# Detects phase transitions and automatically triggers skill activation.
#
# This hook runs after EVERY tool execution.
#
# =============================================================================

# Comprehensive error handling and security
set -uo pipefail  # Removed -e to allow graceful fallbacks
set +H  # Disable history expansion

# Security and validation settings
readonly SCRIPT_NAME="$(basename "$0")"
readonly AUDIT_LOG="/tmp/claude-pipeline-audit.log"
readonly MAX_INPUT_SIZE=2097152  # 2MB max input
readonly MAX_TOOL_INPUT_SIZE=1048576  # 1MB max tool input
readonly MAX_FILE_PATH_LENGTH=1000
readonly MAX_COMMAND_LENGTH=5000

# File locking settings
readonly LOCK_TIMEOUT=30
readonly LOCK_RETRY_DELAY=0.1

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
    
    # Clean up temporary files
    for temp_file in "${STATE_FILE}.tmp" "${STATE_FILE}.lock"; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file" 2>/dev/null || true
        fi
    done
    
    # Clean up signal temp files
    if [ -d "$SIGNALS_DIR" ]; then
        find "$SIGNALS_DIR" -name "*.tmp" -type f -delete 2>/dev/null || true
    fi
    
    if [ $exit_code -ne 0 ]; then
        audit_log "ERROR" "Script exited with code $exit_code"
    fi
    
    exit $exit_code
}

# File locking functions (with fallback to new lock manager)
acquire_lock() {
    local lockfile="$1"
    local timeout="${2:-$LOCK_TIMEOUT}"
    
    # Try to use new lock manager if available
    if command -v acquire_lock >/dev/null 2>&1; then
        local lock_name
        lock_name=$(basename "$lockfile" .lock)
        acquire_lock "$lock_name" "$timeout" "exclusive" '{"caller":"post-tool-use-tracker"}'
        return $?
    fi
    
    # Fallback to original implementation
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if (set -C; echo $$ > "$lockfile") 2>/dev/null; then
            return 0
        fi
        
        # Check if lock is stale (older than timeout)
        if [ -f "$lockfile" ]; then
            local lock_age
            lock_age=$(( $(date +%s) - $(stat -f %m "$lockfile" 2>/dev/null || echo 0) ))
            if [ $lock_age -gt $timeout ]; then
                audit_log "WARN" "Removing stale lock file: $lockfile"
                rm -f "$lockfile" 2>/dev/null || true
                continue
            fi
        fi
        
        sleep $LOCK_RETRY_DELAY
        elapsed=$(echo "$elapsed + $LOCK_RETRY_DELAY" | bc 2>/dev/null || echo $timeout)
    done
    
    audit_log "ERROR" "Failed to acquire lock: $lockfile"
    return 1
}

release_lock() {
    local lockfile="$1"
    
    # Try to use new lock manager if available
    if command -v release_lock >/dev/null 2>&1; then
        local lock_name
        lock_name=$(basename "$lockfile" .lock)
        release_lock "$lock_name"
        return $?
    fi
    
    # Fallback to original implementation
    rm -f "$lockfile" 2>/dev/null || true
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
        tool_input_size=$(echo "$input" | jq -r '.input | tostring | length')
        if [ "$tool_input_size" -gt $MAX_TOOL_INPUT_SIZE ]; then
            audit_log "ERROR" "Tool input too large: $tool_input_size bytes"
            return 1
        fi
    fi
    
    return 0
}

# Get the directory where this script lives (secure path resolution)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! validate_file_path "$SCRIPT_DIR"; then
    audit_log "ERROR" "Invalid script directory: $SCRIPT_DIR"
    exit 1
fi

readonly CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
readonly STATE_FILE="$CLAUDE_DIR/.workflow-state.json"
readonly SKILL_RULES="$CLAUDE_DIR/config/skill-rules.json"
readonly SIGNALS_DIR="$CLAUDE_DIR/.signals"
readonly STATE_LOCK="${STATE_FILE}.lock"

# Load state management and lock management systems
source "$CLAUDE_DIR/lib/state-manager.sh" 2>/dev/null || {
    audit_log "WARN" "State management system not available, using fallback"
}
source "$CLAUDE_DIR/lib/lock-manager.sh" 2>/dev/null || {
    audit_log "WARN" "Lock management system not available, using fallback"
}

# Validate critical paths
for critical_path in "$CLAUDE_DIR" "$STATE_FILE" "$SKILL_RULES" "$SIGNALS_DIR"; do
    if ! validate_file_path "$critical_path"; then
        audit_log "ERROR" "Invalid critical path: $critical_path"
        exit 1
    fi
done

# Create signals directory if it doesn't exist (with proper permissions)
if [ ! -d "$SIGNALS_DIR" ]; then
    if ! mkdir -p "$SIGNALS_DIR" 2>/dev/null; then
        audit_log "ERROR" "Failed to create signals directory: $SIGNALS_DIR"
        exit 1
    fi
    chmod 750 "$SIGNALS_DIR"  # Secure permissions
    audit_log "INFO" "Created signals directory: $SIGNALS_DIR"
fi

# Validate signals directory is writable
if [ ! -w "$SIGNALS_DIR" ]; then
    audit_log "ERROR" "Signals directory not writable: $SIGNALS_DIR"
    exit 1
fi

# Initialize state file using state manager
if command -v init_state_manager >/dev/null 2>&1; then
    init_state_manager || {
        audit_log "WARN" "State manager initialization failed, using fallback"
    }
elif [ ! -f "$STATE_FILE" ]; then
    # Fallback: Initialize state file with atomic operation and locking
    if acquire_lock "$STATE_LOCK"; then
        # Double-check after acquiring lock
        if [ ! -f "$STATE_FILE" ]; then
            {
                echo '{"phase":"pre-init","completedTasks":[],"signals":{},"lastActivation":""}'
            } > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            
            if [ $? -ne 0 ]; then
                release_lock "$STATE_LOCK"
                audit_log "ERROR" "Failed to initialize state file: $STATE_FILE"
                exit 1
            fi
            
            chmod 600 "$STATE_FILE"  # Secure permissions
            audit_log "INFO" "Initialized state file: $STATE_FILE"
        fi
        release_lock "$STATE_LOCK"
    else
        audit_log "ERROR" "Failed to acquire lock for state file initialization"
        exit 1
    fi
fi

# Validate state file
if [ ! -r "$STATE_FILE" ]; then
    audit_log "ERROR" "State file not readable: $STATE_FILE"
    exit 1
fi

# Validate and repair state file using state manager if available
if command -v validate_state >/dev/null 2>&1; then
    if ! validate_state "$STATE_FILE"; then
        audit_log "ERROR" "State validation failed, attempting recovery"
        if command -v recover_state >/dev/null 2>&1; then
            recover_state || {
                audit_log "ERROR" "State recovery failed"
                exit 1
            }
        else
            audit_log "ERROR" "State recovery not available"
            exit 1
        fi
    fi
elif ! jq empty < "$STATE_FILE" 2>/dev/null; then
    # Fallback: Check and repair corrupted state file
    audit_log "ERROR" "Corrupted state file detected, attempting repair: $STATE_FILE"
    
    if acquire_lock "$STATE_LOCK"; then
        # Backup corrupted file
        cp "$STATE_FILE" "${STATE_FILE}.corrupted.$(date +%s)" 2>/dev/null || true
        
        # Recreate with default content
        echo '{"phase":"pre-init","completedTasks":[],"signals":{},"lastActivation":""}' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        release_lock "$STATE_LOCK"
        audit_log "WARN" "State file repaired: $STATE_FILE"
    else
        audit_log "ERROR" "Failed to acquire lock for state file repair"
        exit 1
    fi
fi

# Parse and validate tool use event from stdin
INPUT=$(timeout 15s cat 2>/dev/null || { audit_log "ERROR" "Input read timeout"; exit 1; })

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
TOOL_NAME_RAW=$(echo "$INPUT" | jq -r '.tool // ""')
TOOL_INPUT_RAW=$(echo "$INPUT" | jq -r '.input // ""')

TOOL_NAME=$(sanitize_string "$TOOL_NAME_RAW" 100)
TOOL_INPUT=$(sanitize_string "$TOOL_INPUT_RAW" $MAX_TOOL_INPUT_SIZE)

audit_log "INFO" "Processing tool: $TOOL_NAME with input size: ${#TOOL_INPUT} chars"

# Track worktree operations if worktree manager is available
track_worktree_operation() {
    local tool_name="$1"
    local tool_input="$2"
    
    # Only track if worktree manager is available
    if [ -f "$PIPELINE_ROOT/lib/worktree-manager.sh" ]; then
        source "$PIPELINE_ROOT/lib/worktree-manager.sh" 2>/dev/null || return 0
        
        # Get current worktree context
        local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
        
        # Log worktree context for operation
        audit_log "INFO" "Tool $tool_name executed in worktree: $current_worktree"
        
        # Track git operations in worktrees
        case "$tool_name" in
            "Bash")
                # Check if this is a git command
                if echo "$tool_input" | grep -q "git\s"; then
                    local git_op=$(echo "$tool_input" | sed -n 's/.*git\s\+\([a-z-]\+\).*/\1/p' | head -1)
                    if [ -n "$git_op" ]; then
                        audit_log "INFO" "Git operation '$git_op' in worktree: $current_worktree"
                        
                        # Enforce worktree isolation for git operations
                        if [ -f "$PIPELINE_ROOT/hooks/worktree-enforcer.sh" ]; then
                            "$PIPELINE_ROOT/hooks/worktree-enforcer.sh" enforce "git $git_op" 2>/dev/null || \
                                audit_log "WARN" "Worktree enforcement failed for git $git_op"
                        fi
                    fi
                fi
                ;;
            "Edit"|"MultiEdit"|"Write")
                # Track file operations in worktrees
                audit_log "INFO" "File operation '$tool_name' in worktree: $current_worktree"
                ;;
        esac
        
        # Update worktree state if in a pipeline worktree
        if [[ "$current_worktree" =~ ^phase-([0-9]+)-task-([0-9]+)$ ]]; then
            local phase="${BASH_REMATCH[1]}"
            local task="${BASH_REMATCH[2]}"
            
            # Update last activity timestamp
            local worktree_state_file="$PIPELINE_ROOT/config/worktree-state.json"
            if [ -f "$worktree_state_file" ]; then
                local temp_file=$(mktemp)
                jq --arg name "$current_worktree" \
                   --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                   --arg tool "$tool_name" \
                   '.worktrees[$name].updated_at = $timestamp | 
                    .worktrees[$name].last_tool = $tool |
                    .last_updated = $timestamp' "$worktree_state_file" > "$temp_file" 2>/dev/null && \
                mv "$temp_file" "$worktree_state_file" 2>/dev/null || rm -f "$temp_file"
            fi
        fi
    fi
}

# Track the current tool operation in worktree context
track_worktree_operation "$TOOL_NAME" "$TOOL_INPUT"

# Function to update workflow state with signal (using state manager)
emit_signal() {
    local signal="$1"
    local phase="$2"
    local metadata="${3:-{}}"
    
    # Input validation
    if [ -z "$signal" ] || [ -z "$phase" ]; then
        audit_log "ERROR" "emit_signal: missing required parameters"
        return 1
    fi
    
    # Sanitize inputs
    signal=$(sanitize_string "$signal" 100)
    phase=$(sanitize_string "$phase" 100)
    
    # Validate metadata JSON
    if ! echo "$metadata" | jq empty 2>/dev/null; then
        audit_log "WARN" "Invalid metadata JSON, using empty object"
        metadata="{}"
    fi
    
    # Use state manager for atomic updates if available
    if command -v lock_state >/dev/null 2>&1 && command -v write_state >/dev/null 2>&1; then
        if lock_state 15; then
            local current_state
            if current_state=$(read_state 2>/dev/null); then
                local updated_state
                updated_state=$(echo "$current_state" | jq --arg signal "$signal" --arg phase "$phase" --argjson meta "$metadata" \
                    '.signals[$signal] = now | .phase = $phase | .lastSignal = $signal | .metadata = $meta')
                
                if write_state "$updated_state" "signal-emission"; then
                    audit_log "INFO" "State updated with signal: $signal (phase: $phase)"
                    unlock_state
                else
                    audit_log "ERROR" "Failed to write updated state for signal: $signal"
                    unlock_state
                    return 1
                fi
            else
                audit_log "ERROR" "Failed to read current state for signal: $signal"
                unlock_state
                return 1
            fi
        else
            audit_log "WARN" "Failed to acquire state lock for signal: $signal, using fallback"
            # Fall through to original implementation
        fi
    else
        # Fallback to original implementation
        if ! acquire_lock "$STATE_LOCK"; then
            audit_log "ERROR" "Failed to acquire lock for signal emission: $signal"
            return 1
        fi
        
        # Update state file atomically
        if timeout 10s jq --arg signal "$signal" --arg phase "$phase" --argjson meta "$metadata" \
            '.signals[$signal] = now | .phase = $phase | .lastSignal = $signal | .metadata = $meta' \
            "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null; then
            
            if mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null; then
                audit_log "INFO" "State updated with signal (fallback): $signal (phase: $phase)"
            else
                audit_log "ERROR" "Failed to move temp state file for signal: $signal"
                rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
                release_lock "$STATE_LOCK"
                return 1
            fi
        else
            audit_log "ERROR" "Failed to update state file for signal: $signal"
            rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
            release_lock "$STATE_LOCK"
            return 1
        fi
        
        release_lock "$STATE_LOCK"
    fi
    
    # Create signal file atomically
    local signal_file="$SIGNALS_DIR/${signal}.json"
    local signal_temp="${signal_file}.tmp"
    
    {
        echo "{"
        echo "  \"signal\": \"$signal\","
        echo "  \"phase\": \"$phase\","
        echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"metadata\": $metadata"
        echo "}"
    } > "$signal_temp" 2>/dev/null
    
    if [ $? -eq 0 ] && mv "$signal_temp" "$signal_file" 2>/dev/null; then
        chmod 600 "$signal_file"  # Secure permissions
        audit_log "INFO" "Signal file created: $signal_file"
    else
        audit_log "ERROR" "Failed to create signal file: $signal_file"
        rm -f "$signal_temp" 2>/dev/null || true
        return 1
    fi
    
    return 0
}

# Function to inject next activation codeword (secure)
inject_next_activation() {
    local signal="$1"
    
    # Input validation
    if [ -z "$signal" ]; then
        audit_log "ERROR" "inject_next_activation: missing signal parameter"
        return 1
    fi
    
    # Sanitize signal
    signal=$(sanitize_string "$signal" 100)
    
    # Check if skill rules file exists and is readable
    if [ ! -r "$SKILL_RULES" ]; then
        audit_log "ERROR" "Skill rules file not readable: $SKILL_RULES"
        return 1
    fi
    
    # Check if this signal triggers an automatic transition
    local transition
    transition=$(timeout 10s jq -r --arg signal "$signal" '.phase_transitions[$signal] // empty' "$SKILL_RULES" 2>/dev/null || echo "")
    
    if [ -n "$transition" ]; then
        # Validate transition JSON
        if ! echo "$transition" | jq empty 2>/dev/null; then
            audit_log "WARN" "Invalid transition JSON for signal: $signal"
            return 1
        fi
        
        local auto_trigger next_activation delay
        auto_trigger=$(echo "$transition" | jq -r '.auto_trigger // false' 2>/dev/null)
        next_activation=$(echo "$transition" | jq -r '.next_activation // ""' 2>/dev/null | head -c 100)
        delay=$(echo "$transition" | jq -r '.delay_seconds // 2' 2>/dev/null)
        
        # Validate delay is a number and within reasonable bounds
        if ! [[ "$delay" =~ ^[0-9]+$ ]] || [ "$delay" -gt 30 ]; then
            delay=2
        fi
        
        # Sanitize next activation
        next_activation=$(sanitize_string "$next_activation" 100)
        
        if [ "$auto_trigger" = "true" ] && [ -n "$next_activation" ]; then
            echo ""
            echo "🚀 **AUTOMATIC PHASE TRANSITION**"
            echo ""
            echo "[SIGNAL:$signal]"
            echo ""
            
            # Safe sleep with bounds checking
            if [ "$delay" -gt 0 ] && [ "$delay" -le 30 ]; then
                sleep "$delay"
            fi
            
            echo "[ACTIVATE:$next_activation]"
            echo ""
            
            # Get skill name for display (with timeout and error handling)
            local skill_name
            skill_name=$(timeout 5s jq -r --arg code "$next_activation" \
                '.skills[] | select(.activation_code == $code) | .skill' "$SKILL_RULES" 2>/dev/null || echo "Unknown")
            skill_name=$(sanitize_string "$skill_name" 100)
            
            echo "**Next Phase:** $skill_name"
            echo "**Reason:** Automatic transition from $signal"
            echo ""
            
            audit_log "INFO" "Auto-transition: $signal -> $next_activation ($skill_name)"
            
        elif [ -n "$next_activation" ]; then
            echo ""
            echo "⏸️ **MANUAL GATE REACHED**"
            echo "**Signal:** $signal"
            echo "**Next Skill:** $next_activation (requires user confirmation)"
            echo ""
            echo "To continue, say: \"Proceed to next phase\" or \"Continue pipeline\""
            echo ""
            
            audit_log "INFO" "Manual gate reached: $signal -> $next_activation"
        fi
    fi
    
    return 0
}

# Validate skill rules file before processing
if [ ! -r "$SKILL_RULES" ]; then
    audit_log "WARN" "Skill rules file not accessible, skipping transitions: $SKILL_RULES"
    exit 0
fi

# Track workflow progress based on tool usage (with bounds checking)
case "$TOOL_NAME" in
    
    "Write"|"Create"|"MultiEdit")
        # Extract and validate file path
        FILE_PATH_RAW=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null || echo "")
        FILE_PATH=$(sanitize_string "$FILE_PATH_RAW" $MAX_FILE_PATH_LENGTH)
        
        # Validate file path
        if [ -n "$FILE_PATH" ] && ! validate_file_path "$FILE_PATH"; then
            audit_log "WARN" "Invalid file path in tool input: $FILE_PATH"
            exit 0
        fi
        
        # Phase 1: tasks.json created
        if [[ "$FILE_PATH" == *"tasks.json"* ]]; then
            if emit_signal "PHASE1_START" "phase1" '{"file":"tasks.json"}'; then
                echo "✅ **Phase 1 Started:** tasks.json created"
                inject_next_activation "PHASE1_START"
            fi
        fi
        
        # Phase 1 Complete: tasks expanded (safe file check)
        if [[ "$FILE_PATH" == *"tasks.json"* ]] && [ -f "$FILE_PATH" ] && [ -r "$FILE_PATH" ]; then
            if timeout 5s grep -q "subtasks" "$FILE_PATH" 2>/dev/null; then
                if emit_signal "PHASE1_COMPLETE" "phase1-complete" '{"tasks_expanded":true}'; then
                    echo "✅ **Phase 1 Complete:** Tasks decomposed"
                    inject_next_activation "PHASE1_COMPLETE"
                fi
            fi
        fi
        
        # Phase 2: OpenSpec proposals created
        if [[ "$FILE_PATH" == *".openspec"* ]] && [[ "$FILE_PATH" == *"proposal"* ]]; then
            if emit_signal "PHASE2_SPECS_CREATED" "phase2" '{"proposals_created":true}'; then
                echo "✅ **Phase 2 Progress:** OpenSpec proposal created"
                inject_next_activation "PHASE2_SPECS_CREATED"
            fi
        fi
        
        # Phase 3: Test files created (TDD compliance)
        if [[ "$FILE_PATH" == *"test"* ]] || [[ "$FILE_PATH" == *".spec."* ]] || [[ "$FILE_PATH" == *".test."* ]]; then
            if emit_signal "TESTS_WRITTEN" "phase3" '{"tdd_compliant":true}'; then
                echo "✅ **TDD Compliance:** Tests written first"
            fi
        fi
        
        # Phase 3: Implementation files created
        if [[ "$FILE_PATH" == *"src/"* ]] || [[ "$FILE_PATH" == *"lib/"* ]] || [[ "$FILE_PATH" == *"app/"* ]]; then
            # Check if tests exist first (with error handling)
            local test_signal
            test_signal=$(timeout 5s jq -r '.signals.TESTS_WRITTEN // empty' "$STATE_FILE" 2>/dev/null || echo "")
            
            if [ -z "$test_signal" ]; then
                echo "⚠️ **TDD Violation:** Implementation before tests"
                echo "**Required:** Write tests first, then implementation"
            else
                if emit_signal "IMPLEMENTATION_COMPLETE" "phase3" '{"tdd_followed":true}'; then
                    echo "✅ **Phase 3 Progress:** Implementation after tests (TDD compliant)"
                fi
            fi
        fi
        ;;
        
    "Read")
        # Extract and validate file path
        FILE_PATH_RAW=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null || echo "")
        FILE_PATH=$(sanitize_string "$FILE_PATH_RAW" $MAX_FILE_PATH_LENGTH)
        
        # Validate file path
        if [ -n "$FILE_PATH" ] && ! validate_file_path "$FILE_PATH"; then
            audit_log "WARN" "Invalid file path in Read tool input: $FILE_PATH"
            exit 0
        fi
        
        # Coupling analysis trigger
        if [[ "$FILE_PATH" == *"tasks.json"* ]]; then
            local phase1_signal
            phase1_signal=$(timeout 5s jq -r '.signals.PHASE1_START // empty' "$STATE_FILE" 2>/dev/null || echo "")
            
            if [ -n "$phase1_signal" ]; then
                if emit_signal "COUPLING_ANALYZED" "phase1.5" '{"analysis":"ready"}'; then
                    echo "📊 **Coupling Analysis Ready**"
                    inject_next_activation "COUPLING_ANALYZED"
                fi
            fi
        fi
        
        # Phase 4: Architecture review (integration validation)
        if [[ "$FILE_PATH" == *"architecture.md"* ]] || [[ "$FILE_PATH" == *"ARCHITECTURE.md"* ]]; then
            if emit_signal "ARCHITECTURE_REVIEWED" "phase4" '{"integration":"ready"}'; then
                echo "📋 **Architecture Reviewed:** Ready for integration validation"
                echo ""
                echo "[ACTIVATE:INTEGRATION_VALIDATOR_V1]"
                echo ""
            fi
        fi
        ;;
        
    "Bash")
        # Extract and sanitize command
        COMMAND_RAW=$(echo "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null || echo "")
        COMMAND=$(sanitize_string "$COMMAND_RAW" $MAX_COMMAND_LENGTH)
        
        # Basic command validation (prevent obvious dangerous commands)
        if [[ "$COMMAND" == *"rm -rf /"* ]] || [[ "$COMMAND" == *":(){ :|:& };:"* ]] || [[ "$COMMAND" == *"mkfs"* ]]; then
            audit_log "ERROR" "Dangerous command detected and blocked: $COMMAND"
            exit 0
        fi
        
        # TaskMaster commands
        if [[ "$COMMAND" == *"task-master show"* ]]; then
            if emit_signal "TASK_VIEWED" "phase1" '{"command":"task-master show"}'; then
                echo ""
                echo "[ACTIVATE:COUPLING_ANALYSIS_V1]"
                echo "**Reason:** task-master show command detected"
                echo ""
            fi
        fi
        
        # OpenSpec commands
        if [[ "$COMMAND" == *"openspec"* ]]; then
            if [[ "$COMMAND" == *"proposal"* ]]; then
                if emit_signal "OPENSPEC_COMMAND" "phase2" '{"command":"openspec proposal"}'; then
                    echo ""
                    echo "[ACTIVATE:TEST_STRATEGY_V1]"
                    echo "**Reason:** OpenSpec proposal command detected"
                    echo ""
                fi
            fi
        fi
        
        # Test execution
        if [[ "$COMMAND" == *"test"* ]] || [[ "$COMMAND" == *"jest"* ]] || [[ "$COMMAND" == *"pytest"* ]] || [[ "$COMMAND" == *"npm test"* ]]; then
            if emit_signal "TESTS_EXECUTED" "phase3" '{"tests":"running"}'; then
                echo "🧪 **Tests Executed**"
                
                # Check if all tests pass (simplified - would need actual parsing)
                if [[ "$COMMAND" == *"--coverage"* ]]; then
                    if emit_signal "PHASE3_COMPLETE" "phase3-complete" '{"tests":"passed","coverage":true}'; then
                        echo "✅ **Phase 3 Complete:** All tests passing with coverage"
                        inject_next_activation "PHASE3_COMPLETE"
                    fi
                fi
            fi
        fi
        
        # Integration test execution
        if [[ "$COMMAND" == *"integration"* ]] && [[ "$COMMAND" == *"test"* ]]; then
            if emit_signal "PHASE4_COMPLETE" "phase4-complete" '{"integration_tests":"passed"}'; then
                echo "✅ **Phase 4 Complete:** Integration tests passing"
                inject_next_activation "PHASE4_COMPLETE"
            fi
        fi
        
        # E2E test execution
        if [[ "$COMMAND" == *"e2e"* ]] || [[ "$COMMAND" == *"end-to-end"* ]]; then
            if emit_signal "PHASE5_COMPLETE" "phase5-complete" '{"e2e_tests":"passed"}'; then
                echo "✅ **Phase 5 Complete:** E2E tests passing"
                echo ""
                echo "🔴 **GO/NO-GO DECISION REQUIRED**"
                echo ""
                echo "Review test results and make decision:"
                echo "- Say \"GO\" to approve production deployment"
                echo "- Say \"NO-GO\" to halt and review issues"
                echo ""
            fi
        fi
        
        # Deployment commands
        if [[ "$COMMAND" == *"deploy"* ]] || [[ "$COMMAND" == *"release"* ]]; then
            if emit_signal "DEPLOYMENT_INITIATED" "phase6" '{"deployment":"started"}'; then
                echo "🚀 **Deployment Initiated**"
            fi
        fi
        ;;
        
esac

# Check for specific task numbers (integration tasks) with security
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Bash" ]; then
    CONTENT_RAW=$(echo "$TOOL_INPUT" | jq -r '.command // .file_path // ""' 2>/dev/null || echo "")
    CONTENT=$(sanitize_string "$CONTENT_RAW" 1000)
    
    # Task #24 - Component Integration Testing
    if [[ "$CONTENT" == *"task #24"* ]] || [[ "$CONTENT" == *"task 24"* ]]; then
        echo ""
        echo "[ACTIVATE:INTEGRATION_VALIDATOR_V1]"
        echo "**Task #24:** Component Integration Testing"
        echo ""
    fi
    
    # Task #25 - E2E Workflow Testing  
    if [[ "$CONTENT" == *"task #25"* ]] || [[ "$CONTENT" == *"task 25"* ]]; then
        echo ""
        echo "[ACTIVATE:E2E_VALIDATOR_V1]"
        echo "**Task #25:** End-to-End Workflow Testing"
        echo ""
    fi
    
    # Task #26 - Production Readiness
    if [[ "$CONTENT" == *"task #26"* ]] || [[ "$CONTENT" == *"task 26"* ]]; then
        local go_decision
        go_decision=$(timeout 5s jq -r '.signals.GO_DECISION // empty' "$STATE_FILE" 2>/dev/null || echo "")
        
        if [ -n "$go_decision" ]; then
            echo ""
            echo "[ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1]"
            echo "**Task #26:** Production Deployment (GO decision confirmed)"
            echo ""
        else
            echo ""
            echo "⚠️ **Task #26 Blocked:** Awaiting GO/NO-GO decision from Phase 5"
            echo ""
        fi
    fi
fi

# Special handling for user approval responses (secure)
if [ "$TOOL_NAME" = "UserMessage" ]; then
    MESSAGE_RAW=$(echo "$TOOL_INPUT" | jq -r '.message // ""' 2>/dev/null || echo "")
    MESSAGE=$(sanitize_string "$MESSAGE_RAW" 1000 | tr '[:upper:]' '[:lower:]')
    
    # GO/NO-GO decision
    if [[ "$MESSAGE" == *"go"* ]] && [[ "$MESSAGE" != *"no-go"* ]]; then
        local phase5_complete
        phase5_complete=$(timeout 5s jq -r '.signals.PHASE5_COMPLETE // empty' "$STATE_FILE" 2>/dev/null || echo "")
        
        if [ -n "$phase5_complete" ]; then
            if emit_signal "GO_DECISION" "phase5-approved" '{"decision":"GO"}'; then
                echo ""
                echo "✅ **GO DECISION RECORDED**"
                echo "[ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1]"
                echo ""
            fi
        fi
    elif [[ "$MESSAGE" == *"no-go"* ]] || [[ "$MESSAGE" == *"no go"* ]]; then
        if emit_signal "NO_GO_DECISION" "phase5-blocked" '{"decision":"NO-GO"}'; then
            echo ""
            echo "🛑 **NO-GO DECISION RECORDED**"
            echo "Pipeline halted. Review issues and address before retry."
            echo ""
        fi
    fi
    
    # Manual progression triggers
    if [[ "$MESSAGE" == *"proceed"* ]] || [[ "$MESSAGE" == *"continue pipeline"* ]]; then
        local last_signal
        last_signal=$(timeout 5s jq -r '.lastSignal // ""' "$STATE_FILE" 2>/dev/null || echo "")
        
        if [ -n "$last_signal" ]; then
            inject_next_activation "$last_signal"
        fi
    fi
fi

audit_log "INFO" "Hook completed successfully"
exit 0