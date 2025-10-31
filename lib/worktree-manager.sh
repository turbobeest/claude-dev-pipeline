#!/bin/bash

# Git Worktree Manager for Claude Dev Pipeline
# Provides comprehensive worktree management with isolation and lifecycle tracking

set -euo pipefail

# Configuration
WORKTREE_STATE_FILE="${CLAUDE_PIPELINE_ROOT:-$(pwd)}/config/worktree-state.json"
WORKTREE_BASE_DIR="${CLAUDE_PIPELINE_ROOT:-$(pwd)}/worktrees"
MAIN_BRANCH="${CLAUDE_MAIN_BRANCH:-main}"

# Logging
log_info() {
    echo "[WORKTREE-MGR] $(date '+%Y-%m-%d %H:%M:%S') INFO: $*" | tee -a "${CLAUDE_PIPELINE_ROOT:-$(pwd)}/logs/worktree-manager.log"
}

log_error() {
    echo "[WORKTREE-MGR] $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" | tee -a "${CLAUDE_PIPELINE_ROOT:-$(pwd)}/logs/worktree-manager.log" >&2
}

log_warn() {
    echo "[WORKTREE-MGR] $(date '+%Y-%m-%d %H:%M:%S') WARN: $*" | tee -a "${CLAUDE_PIPELINE_ROOT:-$(pwd)}/logs/worktree-manager.log"
}

# Initialize worktree state file
init_worktree_state() {
    if [[ ! -f "$WORKTREE_STATE_FILE" ]]; then
        mkdir -p "$(dirname "$WORKTREE_STATE_FILE")"
        echo '{"worktrees": {}, "active_worktree": null, "last_updated": ""}' > "$WORKTREE_STATE_FILE"
        log_info "Initialized worktree state file: $WORKTREE_STATE_FILE"
    fi
}

# Update worktree state
update_worktree_state() {
    local worktree_name="$1"
    local status="$2"
    local branch="$3"
    local path="$4"
    
    init_worktree_state
    
    local temp_file=$(mktemp)
    jq --arg name "$worktree_name" \
       --arg status "$status" \
       --arg branch "$branch" \
       --arg path "$path" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.worktrees[$name] = {
           "status": $status,
           "branch": $branch,
           "path": $path,
           "created_at": (.worktrees[$name].created_at // $timestamp),
           "updated_at": $timestamp
       } | .last_updated = $timestamp' "$WORKTREE_STATE_FILE" > "$temp_file"
    
    mv "$temp_file" "$WORKTREE_STATE_FILE"
    log_info "Updated worktree state: $worktree_name -> $status"
}

# Set active worktree
set_active_worktree() {
    local worktree_name="$1"
    
    init_worktree_state
    
    local temp_file=$(mktemp)
    jq --arg name "$worktree_name" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.active_worktree = $name | .last_updated = $timestamp' "$WORKTREE_STATE_FILE" > "$temp_file"
    
    mv "$temp_file" "$WORKTREE_STATE_FILE"
    log_info "Set active worktree: $worktree_name"
}

# Get active worktree
get_active_worktree() {
    init_worktree_state
    jq -r '.active_worktree // empty' "$WORKTREE_STATE_FILE"
}

# Remove worktree from state
remove_worktree_state() {
    local worktree_name="$1"
    
    init_worktree_state
    
    local temp_file=$(mktemp)
    jq --arg name "$worktree_name" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       'del(.worktrees[$name]) | 
        (if .active_worktree == $name then .active_worktree = null else . end) |
        .last_updated = $timestamp' "$WORKTREE_STATE_FILE" > "$temp_file"
    
    mv "$temp_file" "$WORKTREE_STATE_FILE"
    log_info "Removed worktree from state: $worktree_name"
}

# Validate worktree name format
validate_worktree_name() {
    local name="$1"
    
    if [[ ! "$name" =~ ^phase-[0-9]+-task-[0-9]+$ ]]; then
        log_error "Invalid worktree name format: $name. Expected: phase-X-task-Y"
        return 1
    fi
    
    return 0
}

# Generate worktree name
generate_worktree_name() {
    local phase="$1"
    local task="$2"
    
    echo "phase-${phase}-task-${task}"
}

# Create worktree
create_worktree() {
    local phase="$1"
    local task="$2"
    local base_branch="${3:-$MAIN_BRANCH}"
    
    local worktree_name=$(generate_worktree_name "$phase" "$task")
    local branch_name="feature/$worktree_name"
    local worktree_path="$WORKTREE_BASE_DIR/$worktree_name"
    
    # Validate inputs
    if [[ ! "$phase" =~ ^[0-9]+$ ]] || [[ ! "$task" =~ ^[0-9]+$ ]]; then
        log_error "Phase and task must be numeric: phase=$phase, task=$task"
        return 1
    fi
    
    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        log_warn "Worktree already exists: $worktree_path"
        set_active_worktree "$worktree_name"
        echo "$worktree_path"
        return 0
    fi
    
    # Ensure base directory exists
    mkdir -p "$WORKTREE_BASE_DIR"
    
    # Fetch latest changes
    log_info "Fetching latest changes from origin"
    git fetch origin "$base_branch" || {
        log_error "Failed to fetch from origin"
        return 1
    }
    
    # Create worktree
    log_info "Creating worktree: $worktree_name from $base_branch"
    if git worktree add -b "$branch_name" "$worktree_path" "origin/$base_branch"; then
        update_worktree_state "$worktree_name" "active" "$branch_name" "$worktree_path"
        set_active_worktree "$worktree_name"
        
        # Set up worktree-specific configuration
        cd "$worktree_path"
        git config branch."$branch_name".description "Worktree for phase $phase, task $task"
        
        log_info "Successfully created worktree: $worktree_path"
        echo "$worktree_path"
    else
        log_error "Failed to create worktree: $worktree_name"
        return 1
    fi
}

# List worktrees
list_worktrees() {
    local format="${1:-table}"
    
    init_worktree_state
    
    case "$format" in
        "json")
            jq '.worktrees' "$WORKTREE_STATE_FILE"
            ;;
        "names")
            jq -r '.worktrees | keys[]' "$WORKTREE_STATE_FILE"
            ;;
        "table"|*)
            echo "=== Worktree Status ==="
            printf "%-20s %-10s %-30s %-s\n" "NAME" "STATUS" "BRANCH" "PATH"
            printf "%-20s %-10s %-30s %-s\n" "----" "------" "------" "----"
            
            jq -r '.worktrees | to_entries[] | "\(.key)|\(.value.status)|\(.value.branch)|\(.value.path)"' "$WORKTREE_STATE_FILE" | \
            while IFS='|' read -r name status branch path; do
                printf "%-20s %-10s %-30s %-s\n" "$name" "$status" "$branch" "$path"
            done
            
            local active=$(get_active_worktree)
            if [[ -n "$active" ]]; then
                echo
                echo "Active worktree: $active"
            fi
            ;;
    esac
}

# Validate worktree
validate_worktree() {
    local worktree_name="$1"
    
    if ! validate_worktree_name "$worktree_name"; then
        return 1
    fi
    
    # Check if worktree exists in state
    init_worktree_state
    local worktree_path=$(jq -r --arg name "$worktree_name" '.worktrees[$name].path // empty' "$WORKTREE_STATE_FILE")
    
    if [[ -z "$worktree_path" ]]; then
        log_error "Worktree not found in state: $worktree_name"
        return 1
    fi
    
    # Check if path exists
    if [[ ! -d "$worktree_path" ]]; then
        log_error "Worktree path does not exist: $worktree_path"
        return 1
    fi
    
    # Check if it's a valid git worktree
    if ! git worktree list | grep -q "$worktree_path"; then
        log_error "Path is not a valid git worktree: $worktree_path"
        return 1
    fi
    
    log_info "Worktree validation successful: $worktree_name"
    return 0
}

# Get current worktree info
get_current_worktree() {
    local current_path=$(pwd)
    
    # Check if we're in a worktree
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        local git_dir=$(git rev-parse --git-dir)
        local worktree_root=$(git rev-parse --show-toplevel)
        
        # Check if this is a worktree (not main repo)
        if [[ "$git_dir" == *".git/worktrees"* ]]; then
            # Extract worktree name from path
            local worktree_name=$(basename "$worktree_root")
            echo "$worktree_name"
        else
            echo "main"
        fi
    else
        log_error "Not in a git repository"
        return 1
    fi
}

# Switch to worktree
switch_to_worktree() {
    local worktree_name="$1"
    
    if ! validate_worktree "$worktree_name"; then
        return 1
    fi
    
    local worktree_path=$(jq -r --arg name "$worktree_name" '.worktrees[$name].path' "$WORKTREE_STATE_FILE")
    
    if [[ -d "$worktree_path" ]]; then
        set_active_worktree "$worktree_name"
        echo "cd \"$worktree_path\""
        log_info "Switched to worktree: $worktree_name"
    else
        log_error "Worktree path not found: $worktree_path"
        return 1
    fi
}

# Cleanup worktree
cleanup_worktree() {
    local worktree_name="$1"
    local force="${2:-false}"
    
    if ! validate_worktree_name "$worktree_name"; then
        return 1
    fi
    
    init_worktree_state
    local worktree_path=$(jq -r --arg name "$worktree_name" '.worktrees[$name].path // empty' "$WORKTREE_STATE_FILE")
    local branch_name=$(jq -r --arg name "$worktree_name" '.worktrees[$name].branch // empty' "$WORKTREE_STATE_FILE")
    
    if [[ -z "$worktree_path" ]]; then
        log_warn "Worktree not found in state: $worktree_name"
        return 0
    fi
    
    # Check if there are uncommitted changes
    if [[ -d "$worktree_path" ]] && [[ "$force" != "true" ]]; then
        cd "$worktree_path"
        if ! git diff --quiet || ! git diff --cached --quiet; then
            log_error "Uncommitted changes found in worktree: $worktree_name. Use force=true to override."
            return 1
        fi
    fi
    
    # Remove worktree
    if [[ -d "$worktree_path" ]]; then
        log_info "Removing worktree: $worktree_path"
        git worktree remove "$worktree_path" ${force:+--force} || {
            log_error "Failed to remove worktree: $worktree_path"
            return 1
        }
    fi
    
    # Delete branch if it exists
    if [[ -n "$branch_name" ]] && git branch | grep -q "$branch_name"; then
        log_info "Deleting branch: $branch_name"
        git branch -D "$branch_name" || log_warn "Failed to delete branch: $branch_name"
    fi
    
    # Remove from state
    remove_worktree_state "$worktree_name"
    
    log_info "Successfully cleaned up worktree: $worktree_name"
}

# Merge worktree
merge_worktree() {
    local worktree_name="$1"
    local target_branch="${2:-$MAIN_BRANCH}"
    local cleanup_after="${3:-true}"
    
    if ! validate_worktree "$worktree_name"; then
        return 1
    fi
    
    local worktree_path=$(jq -r --arg name "$worktree_name" '.worktrees[$name].path' "$WORKTREE_STATE_FILE")
    local branch_name=$(jq -r --arg name "$worktree_name" '.worktrees[$name].branch' "$WORKTREE_STATE_FILE")
    
    # Ensure we're in the main repository
    local main_repo_root=$(git rev-parse --show-toplevel)
    cd "$main_repo_root"
    
    # Fetch latest changes
    git fetch origin "$target_branch"
    
    # Switch to target branch
    git checkout "$target_branch"
    git pull origin "$target_branch"
    
    # Merge the feature branch
    log_info "Merging $branch_name into $target_branch"
    if git merge --no-ff "$branch_name" -m "Merge $worktree_name: $(git log -1 --pretty=%s $branch_name)"; then
        update_worktree_state "$worktree_name" "merged" "$branch_name" "$worktree_path"
        
        # Push changes
        git push origin "$target_branch"
        
        # Cleanup if requested
        if [[ "$cleanup_after" == "true" ]]; then
            cleanup_worktree "$worktree_name" "true"
        fi
        
        log_info "Successfully merged and cleaned up worktree: $worktree_name"
    else
        log_error "Failed to merge worktree: $worktree_name"
        return 1
    fi
}

# Auto-create worktree if needed
auto_create_worktree() {
    local phase="$1"
    local task="$2"
    
    local worktree_name=$(generate_worktree_name "$phase" "$task")
    
    # Check if already in the correct worktree
    local current_worktree=$(get_current_worktree 2>/dev/null || echo "")
    
    if [[ "$current_worktree" == "$worktree_name" ]]; then
        log_info "Already in correct worktree: $worktree_name"
        return 0
    fi
    
    # Create worktree if it doesn't exist
    local worktree_path
    if worktree_path=$(create_worktree "$phase" "$task"); then
        echo "eval \$(switch_to_worktree \"$worktree_name\")"
        log_info "Auto-created and switched to worktree: $worktree_name"
    else
        log_error "Failed to auto-create worktree: $worktree_name"
        return 1
    fi
}

# Cleanup all completed worktrees
cleanup_completed_worktrees() {
    init_worktree_state
    
    local completed_worktrees=$(jq -r '.worktrees | to_entries[] | select(.value.status == "merged" or .value.status == "completed") | .key' "$WORKTREE_STATE_FILE")
    
    if [[ -z "$completed_worktrees" ]]; then
        log_info "No completed worktrees to clean up"
        return 0
    fi
    
    echo "$completed_worktrees" | while read -r worktree_name; do
        log_info "Cleaning up completed worktree: $worktree_name"
        cleanup_worktree "$worktree_name" "true"
    done
}

# Prevent cross-worktree contamination
enforce_worktree_isolation() {
    local current_worktree=$(get_current_worktree 2>/dev/null || echo "main")
    
    if [[ "$current_worktree" == "main" ]]; then
        log_warn "Working in main repository. Consider using a worktree for isolation."
        return 1
    fi
    
    # Check if we're in the expected worktree for current phase/task
    if [[ -n "${CLAUDE_CURRENT_PHASE:-}" ]] && [[ -n "${CLAUDE_CURRENT_TASK:-}" ]]; then
        local expected_worktree=$(generate_worktree_name "$CLAUDE_CURRENT_PHASE" "$CLAUDE_CURRENT_TASK")
        
        if [[ "$current_worktree" != "$expected_worktree" ]]; then
            log_error "Worktree isolation violation: Expected $expected_worktree, but in $current_worktree"
            return 1
        fi
    fi
    
    log_info "Worktree isolation validated: $current_worktree"
    return 0
}

# Get worktree status
get_worktree_status() {
    local worktree_name="$1"
    
    init_worktree_state
    jq -r --arg name "$worktree_name" '.worktrees[$name].status // "not_found"' "$WORKTREE_STATE_FILE"
}

# Main function for CLI usage
main() {
    local command="$1"
    shift
    
    case "$command" in
        "create")
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 create <phase> <task> [base_branch]"
                exit 1
            fi
            create_worktree "$@"
            ;;
        "list")
            list_worktrees "$@"
            ;;
        "validate")
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 validate <worktree_name>"
                exit 1
            fi
            validate_worktree "$1"
            ;;
        "cleanup")
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 cleanup <worktree_name> [force]"
                exit 1
            fi
            cleanup_worktree "$@"
            ;;
        "merge")
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 merge <worktree_name> [target_branch] [cleanup_after]"
                exit 1
            fi
            merge_worktree "$@"
            ;;
        "switch")
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 switch <worktree_name>"
                exit 1
            fi
            switch_to_worktree "$1"
            ;;
        "current")
            get_current_worktree
            ;;
        "auto-create")
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 auto-create <phase> <task>"
                exit 1
            fi
            auto_create_worktree "$@"
            ;;
        "cleanup-completed")
            cleanup_completed_worktrees
            ;;
        "enforce-isolation")
            enforce_worktree_isolation
            ;;
        "status")
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 status <worktree_name>"
                exit 1
            fi
            get_worktree_status "$1"
            ;;
        *)
            echo "Usage: $0 {create|list|validate|cleanup|merge|switch|current|auto-create|cleanup-completed|enforce-isolation|status}"
            echo "Commands:"
            echo "  create <phase> <task> [base_branch]  - Create a new worktree"
            echo "  list [format]                        - List all worktrees (format: table|json|names)"
            echo "  validate <worktree_name>             - Validate a worktree"
            echo "  cleanup <worktree_name> [force]      - Clean up a worktree"
            echo "  merge <worktree_name> [target] [cleanup] - Merge worktree to target branch"
            echo "  switch <worktree_name>               - Switch to a worktree"
            echo "  current                              - Show current worktree"
            echo "  auto-create <phase> <task>           - Auto-create and switch to worktree"
            echo "  cleanup-completed                    - Clean up all completed worktrees"
            echo "  enforce-isolation                    - Validate worktree isolation"
            echo "  status <worktree_name>               - Get worktree status"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi