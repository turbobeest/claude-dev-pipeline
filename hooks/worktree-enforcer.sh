#!/bin/bash

# Worktree Enforcer Hook for Claude Dev Pipeline
# Ensures all development happens in worktrees with proper isolation

set -euo pipefail

# Source the worktree manager
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PIPELINE_ROOT/lib/worktree-manager.sh"

# Configuration
ENFORCE_WORKTREES="${CLAUDE_ENFORCE_WORKTREES:-true}"
AUTO_CREATE_WORKTREES="${CLAUDE_AUTO_CREATE_WORKTREES:-true}"
ALLOWED_MAIN_OPERATIONS="${CLAUDE_ALLOWED_MAIN_OPERATIONS:-fetch,pull,checkout,status,log,diff}"

# Logging
log_enforcer() {
    echo "[WORKTREE-ENFORCER] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$PIPELINE_ROOT/logs/worktree-enforcer.log"
}

log_enforcer_error() {
    echo "[WORKTREE-ENFORCER] $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" | tee -a "$PIPELINE_ROOT/logs/worktree-enforcer.log" >&2
}

log_enforcer_warn() {
    echo "[WORKTREE-ENFORCER] $(date '+%Y-%m-%d %H:%M:%S') WARN: $*" | tee -a "$PIPELINE_ROOT/logs/worktree-enforcer.log"
}

# Check if operation is allowed in main repository
is_operation_allowed_in_main() {
    local operation="$1"
    
    # Convert comma-separated list to array
    IFS=',' read -ra ALLOWED_OPS <<< "$ALLOWED_MAIN_OPERATIONS"
    
    for allowed_op in "${ALLOWED_OPS[@]}"; do
        if [[ "$operation" == "$allowed_op" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Detect git operation from command
detect_git_operation() {
    local command="$1"
    
    # Extract git operation from command
    if [[ "$command" =~ git[[:space:]]+([a-z-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$command" =~ ^([a-z-]+)[[:space:]] ]]; then
        # Handle direct git commands
        echo "${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

# Get current git context
get_git_context() {
    local context="unknown"
    
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local git_dir=$(git rev-parse --git-dir)
        
        if [[ "$git_dir" == *".git/worktrees"* ]]; then
            context="worktree"
        elif [[ "$git_dir" == ".git" ]] || [[ "$git_dir" == *"/.git" ]]; then
            context="main"
        fi
    fi
    
    echo "$context"
}

# Validate current worktree matches expected phase/task
validate_worktree_context() {
    local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
    
    # If we have phase/task context, validate it
    if [[ -n "${CLAUDE_CURRENT_PHASE:-}" ]] && [[ -n "${CLAUDE_CURRENT_TASK:-}" ]]; then
        local expected_worktree=$(generate_worktree_name "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK")
        
        if [[ "$current_worktree" != "$expected_worktree" ]]; then
            log_enforcer_error "Worktree context mismatch: Expected $expected_worktree, but in $current_worktree"
            
            if [[ "$AUTO_CREATE_WORKTREES" == "true" ]]; then
                log_enforcer "Auto-creating worktree: $expected_worktree"
                create_worktree "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK"
                
                # Provide switch command
                echo "# Switch to the correct worktree:"
                echo "cd \"$(jq -r --arg name "$expected_worktree" '.worktrees[$name].path' "$WORKTREE_STATE_FILE")\""
                return 1
            else
                echo "# Create and switch to the correct worktree:"
                echo "$PIPELINE_ROOT/lib/worktree-manager.sh create $CLAUDE_CURRENT_PHASE $CLAUDE_CURRENT_TASK"
                echo "cd \"\$($PIPELINE_ROOT/lib/worktree-manager.sh switch $expected_worktree)\""
                return 1
            fi
        fi
    fi
    
    log_enforcer "Worktree context validated: $current_worktree"
    return 0
}

# Enforce worktree isolation for operations
enforce_worktree_isolation() {
    local operation="$1"
    local git_context=$(get_git_context)
    
    log_enforcer "Enforcing isolation for operation: $operation in context: $git_context"
    
    case "$git_context" in
        "main")
            if is_operation_allowed_in_main "$operation"; then
                log_enforcer "Operation $operation allowed in main repository"
                return 0
            else
                log_enforcer_error "Operation $operation not allowed in main repository"
                
                if [[ -n "${CLAUDE_CURRENT_PHASE:-}" ]] && [[ -n "${CLAUDE_CURRENT_TASK:-}" ]] && [[ "$AUTO_CREATE_WORKTREES" == "true" ]]; then
                    local worktree_name=$(generate_worktree_name "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK")
                    log_enforcer "Auto-creating worktree for operation: $worktree_name"
                    
                    if create_worktree "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK" >/dev/null; then
                        local worktree_path=$(jq -r --arg name "$worktree_name" '.worktrees[$name].path' "$WORKTREE_STATE_FILE")
                        echo "# Operation requires worktree. Auto-created: $worktree_name"
                        echo "cd \"$worktree_path\""
                        echo "# Now run your command in the worktree"
                        return 1
                    fi
                fi
                
                echo "# This operation requires a worktree. Create one with:"
                echo "$PIPELINE_ROOT/lib/worktree-manager.sh create <phase> <task>"
                return 1
            fi
            ;;
        "worktree")
            # Validate worktree context if we have phase/task information
            if ! validate_worktree_context; then
                return 1
            fi
            
            log_enforcer "Operation $operation allowed in worktree"
            return 0
            ;;
        "unknown")
            log_enforcer_warn "Unknown git context - operation may proceed"
            return 0
            ;;
    esac
}

# Check for potential cross-worktree contamination
check_cross_worktree_contamination() {
    local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
    
    # Check if there are multiple active worktrees
    init_worktree_state
    local active_worktrees=$(jq -r '.worktrees | to_entries[] | select(.value.status == "active") | .key' "$WORKTREE_STATE_FILE" 2>/dev/null || echo "")
    local active_count=$(echo "$active_worktrees" | grep -c . || echo "0")
    
    if [[ "$active_count" -gt 1 ]]; then
        log_enforcer_warn "Multiple active worktrees detected. Risk of contamination."
        echo "Active worktrees:"
        echo "$active_worktrees"
        echo
        echo "Consider cleaning up unused worktrees with:"
        echo "$PIPELINE_ROOT/lib/worktree-manager.sh cleanup-completed"
    fi
    
    # Check for uncommitted changes in other worktrees
    if [[ "$current_worktree" != "main" ]]; then
        while read -r worktree_name; do
            if [[ "$worktree_name" != "$current_worktree" ]] && [[ -n "$worktree_name" ]]; then
                local worktree_path=$(jq -r --arg name "$worktree_name" '.worktrees[$name].path // empty' "$WORKTREE_STATE_FILE")
                if [[ -d "$worktree_path" ]]; then
                    cd "$worktree_path"
                    if ! git diff --quiet || ! git diff --cached --quiet; then
                        log_enforcer_warn "Uncommitted changes in worktree: $worktree_name"
                        echo "# Uncommitted changes detected in: $worktree_name"
                        echo "# Path: $worktree_path"
                        echo "# Consider committing or stashing changes"
                    fi
                fi
            fi
        done <<< "$active_worktrees"
    fi
}

# Auto-create worktree if missing and needed
auto_create_missing_worktree() {
    if [[ -n "${CLAUDE_CURRENT_PHASE:-}" ]] && [[ -n "${CLAUDE_CURRENT_TASK:-}" ]]; then
        local expected_worktree=$(generate_worktree_name "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK")
        local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
        
        if [[ "$current_worktree" == "main" ]] && [[ "$AUTO_CREATE_WORKTREES" == "true" ]]; then
            log_enforcer "Auto-creating missing worktree: $expected_worktree"
            
            if create_worktree "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK" >/dev/null; then
                local worktree_path=$(jq -r --arg name "$expected_worktree" '.worktrees[$name].path' "$WORKTREE_STATE_FILE")
                echo "# Auto-created worktree: $expected_worktree"
                echo "cd \"$worktree_path\""
                return 0
            else
                log_enforcer_error "Failed to auto-create worktree: $expected_worktree"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Detect if we're in a pipeline operation
detect_pipeline_operation() {
    # Check for pipeline environment variables
    if [[ -n "${CLAUDE_CURRENT_PHASE:-}" ]] || [[ -n "${CLAUDE_CURRENT_TASK:-}" ]] || [[ -n "${CLAUDE_SKILL_NAME:-}" ]]; then
        return 0
    fi
    
    # Check if we're being called from a pipeline script
    local call_stack=$(caller 0 2>/dev/null || echo "")
    if [[ "$call_stack" =~ (skill|hook|pipeline) ]]; then
        return 0
    fi
    
    return 1
}

# Main enforcement function
enforce_worktree_rules() {
    local command="${1:-}"
    
    # Skip enforcement if disabled
    if [[ "$ENFORCE_WORKTREES" != "true" ]]; then
        log_enforcer "Worktree enforcement disabled"
        return 0
    fi
    
    # Skip enforcement for non-pipeline operations
    if ! detect_pipeline_operation; then
        log_enforcer "Non-pipeline operation detected, skipping enforcement"
        return 0
    fi
    
    log_enforcer "Enforcing worktree rules for command: $command"
    
    # Detect operation if command provided
    local operation="unknown"
    if [[ -n "$command" ]]; then
        operation=$(detect_git_operation "$command")
    fi
    
    # Check for cross-worktree contamination
    check_cross_worktree_contamination
    
    # Enforce isolation if operation specified
    if [[ "$operation" != "unknown" ]]; then
        if ! enforce_worktree_isolation "$operation"; then
            return 1
        fi
    fi
    
    # Auto-create worktree if needed
    auto_create_missing_worktree
    
    log_enforcer "Worktree enforcement completed successfully"
    return 0
}

# Validate worktree boundaries
validate_boundaries() {
    local current_dir=$(pwd)
    local git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    
    if [[ -z "$git_root" ]]; then
        log_enforcer_error "Not in a git repository"
        return 1
    fi
    
    # Check if we're outside the expected boundaries
    local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
    
    if [[ "$current_worktree" != "main" ]]; then
        # Ensure we're within the worktree boundaries
        local worktree_path=$(jq -r --arg name "$current_worktree" '.worktrees[$name].path // empty' "$WORKTREE_STATE_FILE" 2>/dev/null || echo "")
        
        if [[ -n "$worktree_path" ]] && [[ "$current_dir" != "$worktree_path"* ]]; then
            log_enforcer_warn "Working outside worktree boundaries"
            echo "# Current directory: $current_dir"
            echo "# Expected worktree path: $worktree_path"
            echo "cd \"$worktree_path\""
            return 1
        fi
    fi
    
    return 0
}

# Show worktree status
show_worktree_status() {
    local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
    local git_context=$(get_git_context)
    
    echo "=== Worktree Status ==="
    echo "Current worktree: $current_worktree"
    echo "Git context: $git_context"
    echo "Working directory: $(pwd)"
    
    if [[ -n "${CLAUDE_CURRENT_PHASE:-}" ]] && [[ -n "${CLAUDE_CURRENT_TASK:-}" ]]; then
        local expected_worktree=$(generate_worktree_name "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK")
        echo "Expected worktree: $expected_worktree"
        
        if [[ "$current_worktree" == "$expected_worktree" ]]; then
            echo "Status: ✅ Correct worktree"
        else
            echo "Status: ❌ Wrong worktree"
        fi
    fi
    
    echo "Enforcement enabled: $ENFORCE_WORKTREES"
    echo "Auto-create enabled: $AUTO_CREATE_WORKTREES"
}

# Main function for CLI usage
main() {
    local command="${1:-enforce}"
    shift || true
    
    case "$command" in
        "enforce")
            enforce_worktree_rules "$@"
            ;;
        "validate")
            validate_boundaries
            ;;
        "status")
            show_worktree_status
            ;;
        "check-contamination")
            check_cross_worktree_contamination
            ;;
        "auto-create")
            auto_create_missing_worktree
            ;;
        *)
            echo "Usage: $0 {enforce|validate|status|check-contamination|auto-create}"
            echo "Commands:"
            echo "  enforce [command]        - Enforce worktree rules for command"
            echo "  validate                 - Validate worktree boundaries"
            echo "  status                   - Show current worktree status"
            echo "  check-contamination      - Check for cross-worktree contamination"
            echo "  auto-create              - Auto-create missing worktree"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi