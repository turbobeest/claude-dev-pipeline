#!/bin/bash
# =============================================================================
# TaskMaster Wrapper - Handles long-running operations with timeout management
# =============================================================================
#
# Claude Code's Bash tool has a 10-minute timeout. This wrapper breaks down
# long-running TaskMaster operations into smaller chunks to avoid timeouts.
#
# Supports parallel execution for faster processing.
#
# Usage:
#   ./lib/task-master-wrapper.sh expand-all [--research] [--parallel N]
#   ./lib/task-master-wrapper.sh analyze [--research]
#   ./lib/task-master-wrapper.sh get-task-ids   # For parallel subagent dispatch
#
# =============================================================================

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =============================================================================
# Expand All Tasks (chunked to avoid timeout)
# =============================================================================

expand_all_chunked() {
    local research_flag=""
    if [[ "$1" == "--research" ]]; then
        research_flag="--research"
    fi

    log_info "Starting chunked task expansion..."

    # Check if tasks.json exists
    local tasks_file=".taskmaster/tasks/tasks.json"
    if [[ ! -f "$tasks_file" ]]; then
        log_error "tasks.json not found at $tasks_file"
        exit 1
    fi

    # Get list of task IDs that need expansion (no subtasks yet)
    local task_ids
    task_ids=$(jq -r '.tasks[] | select(.subtasks == null or .subtasks == [] or (.subtasks | length) == 0) | .id' "$tasks_file" 2>/dev/null)

    if [[ -z "$task_ids" ]]; then
        log_info "No tasks need expansion (all tasks already have subtasks)"
        return 0
    fi

    local total_tasks
    total_tasks=$(echo "$task_ids" | wc -l | tr -d ' ')
    log_info "Found $total_tasks tasks to expand"

    local current=0
    local failed=0
    local succeeded=0

    # Expand each task individually (avoids timeout on --all)
    for task_id in $task_ids; do
        current=$((current + 1))
        echo ""
        log_info "[$current/$total_tasks] Expanding task $task_id..."

        # Run expand with timeout per task (5 minutes each)
        if timeout 300 task-master expand --id="$task_id" $research_flag 2>&1; then
            succeeded=$((succeeded + 1))
            log_success "Task $task_id expanded"
        else
            failed=$((failed + 1))
            log_warning "Task $task_id expansion failed or timed out"
        fi

        # Small delay between tasks to avoid rate limiting
        sleep 2
    done

    echo ""
    log_info "Expansion complete: $succeeded succeeded, $failed failed out of $total_tasks tasks"

    if [[ $failed -gt 0 ]]; then
        log_warning "Some tasks failed to expand. You can retry them individually:"
        echo "  task-master expand --id=<task_id> $research_flag"
    fi
}

# =============================================================================
# Get Task IDs (for parallel subagent dispatch)
# =============================================================================

get_task_ids() {
    local tasks_file=".taskmaster/tasks/tasks.json"
    if [[ ! -f "$tasks_file" ]]; then
        echo "ERROR: tasks.json not found" >&2
        exit 1
    fi

    # Get task IDs that need expansion
    jq -r '.tasks[] | select(.subtasks == null or .subtasks == [] or (.subtasks | length) == 0) | .id' "$tasks_file" 2>/dev/null
}

# =============================================================================
# Get Task IDs in Batches (for parallel subagent dispatch)
# =============================================================================

get_task_batches() {
    local batch_size="${1:-5}"
    local tasks_file=".taskmaster/tasks/tasks.json"

    if [[ ! -f "$tasks_file" ]]; then
        echo "ERROR: tasks.json not found" >&2
        exit 1
    fi

    local task_ids
    task_ids=$(jq -r '.tasks[] | select(.subtasks == null or .subtasks == [] or (.subtasks | length) == 0) | .id' "$tasks_file" 2>/dev/null)

    local batch=""
    local count=0
    local batch_num=1

    for id in $task_ids; do
        if [[ $count -ge $batch_size ]]; then
            echo "BATCH_$batch_num: $batch"
            batch=""
            count=0
            batch_num=$((batch_num + 1))
        fi
        batch="$batch $id"
        count=$((count + 1))
    done

    # Output remaining batch
    if [[ -n "$batch" ]]; then
        echo "BATCH_$batch_num: $batch"
    fi
}

# =============================================================================
# Expand Single Task (for subagent use)
# =============================================================================

expand_single() {
    local task_id="$1"
    local research_flag=""

    if [[ "$2" == "--research" ]]; then
        research_flag="--research"
    fi

    if [[ -z "$task_id" ]]; then
        log_error "Task ID required"
        exit 1
    fi

    log_info "Expanding task $task_id..."

    if timeout 300 task-master expand --id="$task_id" $research_flag 2>&1; then
        log_success "Task $task_id expanded"
        echo "RESULT: SUCCESS task_id=$task_id"
    else
        log_error "Task $task_id failed"
        echo "RESULT: FAILED task_id=$task_id"
        exit 1
    fi
}

# =============================================================================
# Expand Batch of Tasks (for subagent use)
# =============================================================================

expand_batch() {
    local research_flag=""
    local task_ids=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --research)
                research_flag="--research"
                shift
                ;;
            --ids)
                task_ids="$2"
                shift 2
                ;;
            *)
                # Assume remaining args are task IDs
                task_ids="$task_ids $1"
                shift
                ;;
        esac
    done

    if [[ -z "$task_ids" ]]; then
        log_error "No task IDs provided"
        exit 1
    fi

    local succeeded=0
    local failed=0

    for task_id in $task_ids; do
        log_info "Expanding task $task_id..."

        if timeout 300 task-master expand --id="$task_id" $research_flag 2>&1; then
            succeeded=$((succeeded + 1))
            log_success "Task $task_id expanded"
        else
            failed=$((failed + 1))
            log_warning "Task $task_id failed"
        fi

        sleep 1
    done

    echo ""
    echo "BATCH_RESULT: succeeded=$succeeded failed=$failed"
}

# =============================================================================
# Analyze Complexity (with progress)
# =============================================================================

analyze_complexity() {
    local research_flag=""
    if [[ "$1" == "--research" ]]; then
        research_flag="--research"
    fi

    log_info "Running complexity analysis..."

    # Run with extended timeout
    if timeout 600 task-master analyze-complexity $research_flag 2>&1; then
        log_success "Complexity analysis complete"

        # Show summary
        if [[ -f ".taskmaster/reports/task-complexity-report.json" ]]; then
            echo ""
            log_info "Complexity Summary:"
            jq -r '.complexityAnalysis[] | "  Task \(.taskId): \(.complexityScore)/10 - \(.recommendedSubtasks) subtasks recommended"' \
                .taskmaster/reports/task-complexity-report.json 2>/dev/null | head -20
        fi
    else
        log_error "Complexity analysis failed or timed out"
        exit 1
    fi
}

# =============================================================================
# Expand High Complexity Tasks Only
# =============================================================================

expand_high_complexity() {
    local research_flag=""
    local threshold="${2:-7}"  # Default threshold: 7

    if [[ "$1" == "--research" ]]; then
        research_flag="--research"
    fi

    log_info "Expanding high-complexity tasks (score >= $threshold)..."

    # Check for complexity report
    local report_file=".taskmaster/reports/task-complexity-report.json"
    if [[ ! -f "$report_file" ]]; then
        log_warning "No complexity report found. Running analysis first..."
        analyze_complexity "$research_flag"
    fi

    # Get high-complexity task IDs
    local high_complexity_ids
    high_complexity_ids=$(jq -r ".complexityAnalysis[] | select(.complexityScore >= $threshold) | .taskId" "$report_file" 2>/dev/null)

    if [[ -z "$high_complexity_ids" ]]; then
        log_info "No high-complexity tasks found (threshold: $threshold)"
        return 0
    fi

    local total_tasks
    total_tasks=$(echo "$high_complexity_ids" | wc -l | tr -d ' ')
    log_info "Found $total_tasks high-complexity tasks to expand"

    local current=0
    for task_id in $high_complexity_ids; do
        current=$((current + 1))
        echo ""
        log_info "[$current/$total_tasks] Expanding high-complexity task $task_id..."

        if timeout 300 task-master expand --id="$task_id" $research_flag 2>&1; then
            log_success "Task $task_id expanded"
        else
            log_warning "Task $task_id expansion failed or timed out"
        fi

        sleep 2
    done

    echo ""
    log_success "High-complexity expansion complete"
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    echo "TaskMaster Wrapper - Timeout-safe operations with parallel support"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  expand-all [--research]        Expand all tasks (chunked, 5min per task)"
    echo "  expand-high [--research]       Expand only high-complexity tasks (score >= 7)"
    echo "  expand-single <id> [--research] Expand a single task (for subagent use)"
    echo "  expand-batch <ids> [--research] Expand a batch of tasks (for subagent use)"
    echo "  analyze [--research]           Run complexity analysis (10min timeout)"
    echo "  get-task-ids                   List task IDs needing expansion"
    echo "  get-batches [size]             Get task IDs in batches (default: 5 per batch)"
    echo "  help                           Show this help"
    echo ""
    echo "Sequential Examples:"
    echo "  $0 expand-all --research       Expand all tasks with research"
    echo "  $0 expand-high                 Expand only complex tasks"
    echo "  $0 analyze --research          Analyze with research model"
    echo ""
    echo "Parallel Subagent Examples:"
    echo "  $0 get-task-ids                Get list of task IDs for parallel dispatch"
    echo "  $0 get-batches 5               Get task IDs in batches of 5"
    echo "  $0 expand-single 3 --research  Expand task 3 (run in subagent)"
    echo "  $0 expand-batch 1 2 3 --research  Expand tasks 1,2,3 (run in subagent)"
}

case "${1:-help}" in
    expand-all)
        expand_all_chunked "$2"
        ;;
    expand-high)
        expand_high_complexity "$2" "$3"
        ;;
    expand-single)
        expand_single "$2" "$3"
        ;;
    expand-batch)
        shift  # Remove 'expand-batch' from args
        expand_batch "$@"
        ;;
    analyze)
        analyze_complexity "$2"
        ;;
    get-task-ids)
        get_task_ids
        ;;
    get-batches)
        get_task_batches "${2:-5}"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
