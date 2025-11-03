#!/bin/bash
# =============================================================================
# Skill Activation Hook (UserPromptSubmit) - Codeword Injection Version
# =============================================================================
# 
# Injects activation codewords based on user message analysis and context.
# This guarantees skill activation rather than hoping Claude notices keywords.
#
# This hook runs on EVERY user message to Claude Code.
# Enhanced with performance optimizations and caching.
#
# =============================================================================

# Comprehensive error handling and security
set -uo pipefail  # Removed -e to allow graceful fallbacks
set +H  # Disable history expansion

# Source performance optimization libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cache.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/json-utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/lazy-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/profiler.sh" 2>/dev/null || true

# Security and validation settings
readonly SCRIPT_NAME="$(basename "$0")"
readonly AUDIT_LOG="/tmp/claude-pipeline-audit.log"
readonly MAX_INPUT_SIZE=1048576  # 1MB max input
readonly MAX_MESSAGE_LENGTH=10000
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
    if [ -f "${STATE_FILE}.tmp" ]; then
        rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
    fi
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
    
    # Must be absolute path
    if [[ "$file_path" != /* ]]; then
        audit_log "ERROR" "Relative path not allowed: $file_path"
        return 1
    fi
    
    return 0
}

sanitize_string() {
    local input="$1"
    local max_length="${2:-$MAX_MESSAGE_LENGTH}"
    
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
    if ! echo "$input" | jq -e '.message' >/dev/null 2>&1; then
        audit_log "ERROR" "Missing required field: message"
        return 1
    fi
    
    # Validate message content
    local message
    message=$(echo "$input" | jq -r '.message // ""')
    if [ ${#message} -gt $MAX_MESSAGE_LENGTH ]; then
        audit_log "ERROR" "Message too long: ${#message} chars"
        return 1
    fi
    
    # Validate context files if present
    if echo "$input" | jq -e '.contextFiles' >/dev/null 2>&1; then
        local context_files
        context_files=$(echo "$input" | jq -r '.contextFiles[]? // empty')
        while IFS= read -r file_path; do
            if [ -n "$file_path" ] && ! validate_file_path "$file_path"; then
                return 1
            fi
        done <<< "$context_files"
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
readonly SKILL_RULES="$CLAUDE_DIR/config/skill-rules.json"
readonly STATE_FILE="$CLAUDE_DIR/.workflow-state.json"

# Load state management system
source "$CLAUDE_DIR/lib/state-manager.sh" 2>/dev/null || {
    audit_log "WARN" "State management system not available, using fallback"
}

# Validate critical paths (non-fatal if missing)
if ! validate_file_path "$CLAUDE_DIR" 2>/dev/null; then
    audit_log "WARN" "Invalid CLAUDE_DIR: $CLAUDE_DIR, exiting gracefully"
    echo '{}' # Return empty JSON to not break pipeline
    exit 0
fi

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

# Extract and sanitize user message
USER_MESSAGE_RAW=$(echo "$INPUT" | jq -r '.message // ""')
USER_MESSAGE=$(sanitize_string "$USER_MESSAGE_RAW" | tr '[:upper:]' '[:lower:]')

# Extract and validate context files
CONTEXT_FILES=$(echo "$INPUT" | jq -r '.contextFiles[]? // empty')

audit_log "INFO" "Processing message with ${#USER_MESSAGE} chars and $(echo "$CONTEXT_FILES" | wc -l) context files"

# Read and validate skill rules
if [ ! -f "$SKILL_RULES" ]; then
    audit_log "WARN" "Skill rules file not found: $SKILL_RULES, exiting gracefully"
    echo '{}' # Return empty JSON to not break pipeline
    exit 0
fi

# Validate skill rules file is readable and valid JSON
if [ ! -r "$SKILL_RULES" ]; then
    audit_log "WARN" "Skill rules file not readable: $SKILL_RULES, exiting gracefully"
    echo '{}'
    exit 0
fi

if ! jq empty < "$SKILL_RULES" 2>/dev/null; then
    audit_log "WARN" "Invalid JSON in skill rules file: $SKILL_RULES, exiting gracefully"
    echo '{}'
    exit 0
fi

# Initialize state file using state manager
if command -v init_state_manager >/dev/null 2>&1; then
    init_state_manager || {
        audit_log "WARN" "State manager initialization failed, using fallback"
    }
elif [ ! -f "$STATE_FILE" ]; then
    # Fallback: Create with proper permissions and atomic write
    {
        echo '{"phase":"pre-init","completedTasks":[],"signals":{},"lastActivation":""}'
    } > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    if [ $? -ne 0 ]; then
        audit_log "ERROR" "Failed to initialize state file: $STATE_FILE"
        exit 1
    fi
    
    chmod 600 "$STATE_FILE"  # Secure permissions
    audit_log "INFO" "Initialized state file: $STATE_FILE"
fi

# Validate state file
if [ ! -r "$STATE_FILE" ]; then
    audit_log "ERROR" "State file not readable: $STATE_FILE"
    exit 1
fi

# Use state manager validation if available, otherwise fallback
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
    audit_log "ERROR" "Corrupted state file, recreating: $STATE_FILE"
    echo '{"phase":"pre-init","completedTasks":[],"signals":{},"lastActivation":""}' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# Get current phase and last signal from state (with error handling)
if command -v read_state >/dev/null 2>&1; then
    STATE_DATA=$(read_state 2>/dev/null || echo '{"phase":"pre-init","signals":{}}')
    CURRENT_PHASE=$(echo "$STATE_DATA" | jq -r '.phase // "pre-init"' 2>/dev/null || echo "pre-init")
    LAST_SIGNAL=$(echo "$STATE_DATA" | jq -r '.signals | to_entries | max_by(.value) | .key // ""' 2>/dev/null || echo "")
else
    CURRENT_PHASE=$(jq -r '.phase // "pre-init"' "$STATE_FILE" 2>/dev/null || echo "pre-init")
    LAST_SIGNAL=$(jq -r '.signals | to_entries | max_by(.value) | .key // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi

# Sanitize extracted values
CURRENT_PHASE=$(sanitize_string "$CURRENT_PHASE" 50)
LAST_SIGNAL=$(sanitize_string "$LAST_SIGNAL" 100)

# Detect worktree context and export for skills
CURRENT_WORKTREE=""
WORKTREE_ISOLATION_ENABLED="true"

if [ -d "$PIPELINE_ROOT/lib" ] && [ -f "$PIPELINE_ROOT/lib/worktree-manager.sh" ]; then
    # Source worktree manager for context detection
    source "$PIPELINE_ROOT/lib/worktree-manager.sh" 2>/dev/null || true
    
    # Get current worktree context
    CURRENT_WORKTREE=$(get_current_worktree 2>/dev/null || echo "main")
    
    # Extract phase and task from worktree name if in a pipeline worktree
    if [[ "$CURRENT_WORKTREE" =~ ^phase-([0-9]+)-task-([0-9]+)$ ]]; then
        export CLAUDE_CURRENT_PHASE="${BASH_REMATCH[1]}"
        export CLAUDE_CURRENT_TASK="${BASH_REMATCH[2]}"
        export CLAUDE_CURRENT_WORKTREE="$CURRENT_WORKTREE"
        audit_log "INFO" "Worktree context detected: Phase ${CLAUDE_CURRENT_PHASE}, Task ${CLAUDE_CURRENT_TASK}, Worktree: $CURRENT_WORKTREE"
    else
        export CLAUDE_CURRENT_WORKTREE="$CURRENT_WORKTREE"
        audit_log "INFO" "Non-pipeline worktree detected: $CURRENT_WORKTREE"
    fi
    
    # Enforce worktree isolation for pipeline operations
    if [ "$WORKTREE_ISOLATION_ENABLED" = "true" ] && [ -f "$PIPELINE_ROOT/hooks/worktree-enforcer.sh" ]; then
        # Run worktree enforcement (non-blocking)
        "$PIPELINE_ROOT/hooks/worktree-enforcer.sh" enforce 2>/dev/null || audit_log "WARN" "Worktree enforcement check failed"
    fi
else
    audit_log "WARN" "Worktree manager not found, skipping worktree context detection"
fi

# Initialize arrays for codewords to inject
declare -a CODEWORDS_TO_INJECT=()
declare -a SKILL_NAMES=()

# Function to check if pattern matches (case-insensitive, secure)
matches_pattern() {
    local pattern="$1"
    local text="$2"
    
    # Input validation
    if [ -z "$pattern" ] || [ -z "$text" ]; then
        return 1
    fi
    
    # Sanitize inputs
    pattern=$(sanitize_string "$pattern" 500)
    text=$(sanitize_string "$text" 10000)
    
    # Use grep with timeout and error handling
    echo "$text" | timeout 5s grep -qi "$pattern" 2>/dev/null || return 1
}

# Function to check if file matches pattern (secure)
file_matches() {
    local pattern="$1"
    local files="$2"
    
    # Input validation
    if [ -z "$pattern" ] || [ -z "$files" ]; then
        return 1
    fi
    
    # Sanitize inputs
    pattern=$(sanitize_string "$pattern" 500)
    files=$(sanitize_string "$files" 5000)
    
    # Use grep with timeout and error handling
    echo "$files" | timeout 5s grep -q "$pattern" 2>/dev/null || return 1
}

# Check each skill rule (with bounds checking)
rule_count=0
max_rules=50  # Prevent DoS

while IFS= read -r rule && [ $rule_count -lt $max_rules ]; do
    rule_count=$((rule_count + 1))
    
    # Validate rule JSON
    if ! echo "$rule" | jq empty 2>/dev/null; then
        audit_log "WARN" "Invalid rule JSON, skipping rule $rule_count"
        continue
    fi
    
    # Extract and validate rule fields
    SKILL_NAME=$(echo "$rule" | jq -r '.skill // ""' 2>/dev/null | head -c 100)
    ACTIVATION_CODE=$(echo "$rule" | jq -r '.activation_code // ""' 2>/dev/null | head -c 100)
    USER_PATTERNS=$(echo "$rule" | jq -r '.trigger_conditions.user_patterns[]? // empty' 2>/dev/null)
    FILE_PATTERNS=$(echo "$rule" | jq -r '.trigger_conditions.file_patterns[]? // empty' 2>/dev/null)
    SIGNALS_DETECTED=$(echo "$rule" | jq -r '.trigger_conditions.signals_detected[]? // empty' 2>/dev/null)
    
    # Skip rule if essential fields are missing
    if [ -z "$SKILL_NAME" ] || [ -z "$ACTIVATION_CODE" ]; then
        audit_log "WARN" "Rule missing essential fields, skipping: $SKILL_NAME"
        continue
    fi
    
    # Sanitize extracted values
    SKILL_NAME=$(sanitize_string "$SKILL_NAME" 100)
    ACTIVATION_CODE=$(sanitize_string "$ACTIVATION_CODE" 100)
  
  SHOULD_ACTIVATE=false
  ACTIVATION_REASON=""
  
    # Check user message patterns (with limits)
    pattern_count=0
    max_patterns=20  # Prevent DoS
    
    if [ -n "$USER_PATTERNS" ]; then
        while IFS= read -r pattern && [ $pattern_count -lt $max_patterns ]; do
            pattern_count=$((pattern_count + 1))
            
            if [ -n "$pattern" ] && matches_pattern "$pattern" "$USER_MESSAGE"; then
                SHOULD_ACTIVATE=true
                ACTIVATION_REASON="User mentioned: $(sanitize_string "$pattern" 50)"
                break
            fi
        done <<< "$USER_PATTERNS"
    fi
  
    # Check file patterns in context (with limits)
    if [ "$SHOULD_ACTIVATE" = false ] && [ -n "$FILE_PATTERNS" ] && [ -n "$CONTEXT_FILES" ]; then
        file_pattern_count=0
        max_file_patterns=20  # Prevent DoS
        
        while IFS= read -r pattern && [ $file_pattern_count -lt $max_file_patterns ]; do
            file_pattern_count=$((file_pattern_count + 1))
            
            if [ -n "$pattern" ] && file_matches "$pattern" "$CONTEXT_FILES"; then
                SHOULD_ACTIVATE=true
                ACTIVATION_REASON="File in context: $(sanitize_string "$pattern" 50)"
                break
            fi
        done <<< "$FILE_PATTERNS"
    fi
  
    # Check for signal-based activation (with limits)
    if [ "$SHOULD_ACTIVATE" = false ] && [ -n "$SIGNALS_DETECTED" ]; then
        signal_count=0
        max_signals=20  # Prevent DoS
        
        while IFS= read -r signal && [ $signal_count -lt $max_signals ]; do
            signal_count=$((signal_count + 1))
            
            if [ -n "$signal" ] && [ "$LAST_SIGNAL" = "$signal" ]; then
                SHOULD_ACTIVATE=true
                ACTIVATION_REASON="Signal detected: $(sanitize_string "$signal" 50)"
                break
            fi
        done <<< "$SIGNALS_DETECTED"
    fi
  
    # Add to injection list if matched (with bounds checking)
    if [ "$SHOULD_ACTIVATE" = true ]; then
        # Limit number of activations to prevent DoS
        if [ ${#CODEWORDS_TO_INJECT[@]} -lt 10 ]; then
            CODEWORDS_TO_INJECT+=("$ACTIVATION_CODE")
            SKILL_NAMES+=("$SKILL_NAME ($ACTIVATION_REASON)")
            audit_log "INFO" "Activated skill: $SKILL_NAME ($ACTIVATION_REASON)"
        else
            audit_log "WARN" "Maximum skill activations reached, ignoring: $SKILL_NAME"
        fi
    fi
done < <(timeout 30s jq -c '.skills[]' "$SKILL_RULES" 2>/dev/null || { audit_log "ERROR" "Failed to read skills from $SKILL_RULES"; exit 1; })

# Check phase transitions for automatic activation (with error handling)
if [ -n "$LAST_SIGNAL" ] && [ ${#CODEWORDS_TO_INJECT[@]} -lt 10 ]; then
    TRANSITION=$(timeout 10s jq -r --arg signal "$LAST_SIGNAL" '.phase_transitions[$signal] // empty' "$SKILL_RULES" 2>/dev/null || echo "")
    
    if [ -n "$TRANSITION" ]; then
        # Validate transition JSON
        if echo "$TRANSITION" | jq empty 2>/dev/null; then
            AUTO_TRIGGER=$(echo "$TRANSITION" | jq -r '.auto_trigger // false' 2>/dev/null)
            NEXT_ACTIVATION=$(echo "$TRANSITION" | jq -r '.next_activation // ""' 2>/dev/null | head -c 100)
            
            if [ "$AUTO_TRIGGER" = "true" ] && [ -n "$NEXT_ACTIVATION" ]; then
                NEXT_ACTIVATION=$(sanitize_string "$NEXT_ACTIVATION" 100)
                CODEWORDS_TO_INJECT+=("$NEXT_ACTIVATION")
                SKILL_NAMES+=("AUTO-TRANSITION from $(sanitize_string "$LAST_SIGNAL" 50)")
                audit_log "INFO" "Auto-transition activated: $NEXT_ACTIVATION from $LAST_SIGNAL"
            fi
        else
            audit_log "WARN" "Invalid transition JSON for signal: $LAST_SIGNAL"
        fi
    fi
fi

# Output codeword injections if any matched
if [ ${#CODEWORDS_TO_INJECT[@]} -gt 0 ]; then
  echo "🎯 **SKILL ACTIVATION SYSTEM**"
  echo ""
  
  # Inject the codewords
  for i in "${!CODEWORDS_TO_INJECT[@]}"; do
    CODEWORD="${CODEWORDS_TO_INJECT[$i]}"
    REASON="${SKILL_NAMES[$i]}"
    echo "[ACTIVATE:$CODEWORD]"
    echo "<!-- Reason: $REASON -->"
  done
  
  echo ""
  echo "**Active Skills:**"
  for CODEWORD in "${CODEWORDS_TO_INJECT[@]}"; do
    SKILL_NAME=$(jq -r --arg code "$CODEWORD" '.skills[] | select(.activation_code == $code) | .skill' "$SKILL_RULES")
    echo "- $SKILL_NAME"
  done
  
    # Update state with last activation using state manager
    if [ ${#CODEWORDS_TO_INJECT[@]} -eq 1 ]; then
        if command -v lock_state >/dev/null 2>&1 && command -v write_state >/dev/null 2>&1; then
            # Use state manager for atomic updates
            if lock_state 10; then
                local current_state
                if current_state=$(read_state 2>/dev/null); then
                    local updated_state
                    updated_state=$(echo "$current_state" | jq --arg activation "${CODEWORDS_TO_INJECT[0]}" \
                        '.lastActivation = $activation | .lastActivationTime = now')
                    
                    if write_state "$updated_state" "skill-activation"; then
                        audit_log "INFO" "Updated state with activation: ${CODEWORDS_TO_INJECT[0]}"
                    else
                        audit_log "ERROR" "Failed to write updated state"
                    fi
                else
                    audit_log "ERROR" "Failed to read current state"
                fi
                unlock_state
            else
                audit_log "WARN" "Failed to acquire state lock, using fallback update"
                # Fallback to original method
                if timeout 10s jq --arg activation "${CODEWORDS_TO_INJECT[0]}" \
                    '.lastActivation = $activation | .lastActivationTime = now' \
                    "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null; then
                    
                    if mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null; then
                        audit_log "INFO" "Updated state with activation (fallback): ${CODEWORDS_TO_INJECT[0]}"
                    else
                        audit_log "ERROR" "Failed to move temp state file"
                        rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
                    fi
                else
                    audit_log "ERROR" "Failed to update state file"
                    rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
                fi
            fi
        else
            # Fallback to original method
            if timeout 10s jq --arg activation "${CODEWORDS_TO_INJECT[0]}" \
                '.lastActivation = $activation | .lastActivationTime = now' \
                "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null; then
                
                if mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null; then
                    audit_log "INFO" "Updated state with activation (fallback): ${CODEWORDS_TO_INJECT[0]}"
                else
                    audit_log "ERROR" "Failed to move temp state file"
                    rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
                fi
            else
                audit_log "ERROR" "Failed to update state file"
                rm -f "${STATE_FILE}.tmp" 2>/dev/null || true
            fi
        fi
    fi
  
  echo ""
  echo "---"
  echo ""
fi

# Check for large PRD file that needs large-file-reader (CRITICAL)
if matches_pattern "begin automated development\|completed.*prd\|start pipeline\|prd.*ready" "$USER_MESSAGE"; then
    # Look for PRD file in common locations
    for prd_path in "docs/PRD.md" "PRD.md" "docs/prd.md" ".taskmaster/docs/PRD.md"; do
        if [ -f "$prd_path" ]; then
            # Estimate token count (rough: ~0.75 tokens per character for English text)
            file_size=$(wc -c < "$prd_path" 2>/dev/null || echo "0")
            estimated_tokens=$((file_size * 3 / 4))

            # If file is likely >25000 tokens, warn about using large-file-reader
            if [ "$estimated_tokens" -gt 25000 ]; then
                echo "⚠️ **LARGE PRD DETECTED**"
                echo ""
                echo "The PRD at \`$prd_path\` is approximately $estimated_tokens tokens."
                echo "This exceeds the 25,000 token Read tool limit."
                echo ""
                echo "**CRITICAL:** You MUST use the large-file-reader tool first:"
                echo "\`\`\`bash"
                echo "./.claude/lib/large-file-reader.sh $prd_path"
                echo "\`\`\`"
                echo ""
                echo "**Do NOT:**"
                echo "- Use the Read tool directly on $prd_path"
                echo "- Invoke TaskMaster until AFTER reading the full PRD with large-file-reader"
                echo ""
                echo "**Workflow:**"
                echo "1. Run large-file-reader.sh to read PRD in chunks"
                echo "2. Analyze and understand the full requirements"
                echo "3. THEN invoke TaskMaster to parse and generate tasks"
                echo ""
                echo "---"
                echo ""

                audit_log "INFO" "Large PRD detected ($estimated_tokens tokens), injecting large-file-reader reminder"
                break
            fi
        fi
    done
fi

# Check for PRD requirements reminder (GENERIC)
if matches_pattern "implement\|build\|create\|develop" "$USER_MESSAGE"; then

    # Check if we're in implementation phase
    if [ "$CURRENT_PHASE" = "PHASE3" ] || [ "$CURRENT_PHASE" = "implementation" ]; then
        # Check if PRD requirements file exists
        req_file="${PROJECT_ROOT}/.prd-requirements.json"
        if [ -f "$req_file" ]; then
            must_use_count=$(jq '.must_use | length' "$req_file" 2>/dev/null || echo "0")
            cannot_use_count=$(jq '.cannot_use | length' "$req_file" 2>/dev/null || echo "0")

            if [ "$must_use_count" -gt 0 ] || [ "$cannot_use_count" -gt 0 ]; then
                echo "⚠️ **PRD REQUIREMENTS REMINDER**"
                echo ""

                if [ "$must_use_count" -gt 0 ]; then
                    echo "**MUST USE:**"
                    jq -r '.must_use[]' "$req_file" 2>/dev/null | while IFS= read -r item; do
                        echo "  ✓ $item"
                    done
                    echo ""
                fi

                if [ "$cannot_use_count" -gt 0 ]; then
                    echo "**CANNOT USE:**"
                    jq -r '.cannot_use[]' "$req_file" 2>/dev/null | while IFS= read -r item; do
                        echo "  ✗ $item"
                    done
                    echo ""
                fi

                echo "---"
                echo ""

                audit_log "INFO" "PRD requirements reminder injected for implementation phase"
            fi
        fi
    fi
fi

# Special case: Pipeline status check (secure)
if matches_pattern "pipeline status\|what phase\|current phase" "$USER_MESSAGE"; then
    echo "📊 **Pipeline Status**"
    echo ""
    echo "Current Phase: $CURRENT_PHASE"
    echo "Last Signal: ${LAST_SIGNAL:-none}"
    echo ""
    
    # Show phase completion status (with error handling)
    echo "**Phase Status:**"
    phase_count=0
    for phase in "PHASE1" "PHASE2" "PHASE3" "PHASE4" "PHASE5" "PHASE6"; do
        phase_count=$((phase_count + 1))
        if [ $phase_count -gt 10 ]; then  # Prevent DoS
            break
        fi
        
        SIGNAL_TIME=$(timeout 5s jq -r --arg p "${phase}_COMPLETE" '.signals[$p] // ""' "$STATE_FILE" 2>/dev/null || echo "")
        if [ -n "$SIGNAL_TIME" ]; then
            echo "✅ $phase - Complete"
        else
            echo "⏳ $phase - Pending"
        fi
    done
    echo ""
    
    audit_log "INFO" "Pipeline status requested by user"
fi

audit_log "INFO" "Hook completed successfully with ${#CODEWORDS_TO_INJECT[@]} activations"
exit 0