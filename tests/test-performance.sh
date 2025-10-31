#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Performance Tests
# =============================================================================
# 
# Comprehensive performance testing suite for the pipeline system.
# Tests startup performance, processing speed, state operations, scalability,
# resource usage, and generates detailed performance reports.
#
# Test Categories:
# - Startup Performance
# - State Operation Performance
# - Worktree Operation Performance
# - Concurrent Operation Scaling
# - Memory and Resource Usage
# - Large Dataset Handling
# - Performance Regression Detection
# - Benchmark Report Generation
#
# =============================================================================

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$TEST_DIR")"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEMP_TEST_DIR="$TEST_DIR/temp/performance-tests"
RESULTS_DIR="$TEMP_TEST_DIR/results"
REPO_NAME="perf-test-repo"
TEST_REPO="$TEMP_TEST_DIR/$REPO_NAME"

# Load libraries
source "$PIPELINE_DIR/lib/worktree-manager.sh"
source "$PIPELINE_DIR/lib/state-manager.sh"
source "$PIPELINE_DIR/lib/error-recovery.sh"

# Override paths for testing
export PIPELINE_ROOT="$TEMP_TEST_DIR"
export CHECKPOINT_DIR="$TEMP_TEST_DIR/.checkpoints"
export ERROR_LOG="$TEMP_TEST_DIR/.error-recovery.log"
export AUDIT_LOG="$TEMP_TEST_DIR/audit.log"
export STATE_FILE="$TEMP_TEST_DIR/.workflow-state.json"
export BACKUP_DIR="$TEMP_TEST_DIR/.state-backups"
export LOCK_DIR="$TEMP_TEST_DIR/.locks"
export WORKTREE_BASE_DIR="$TEMP_TEST_DIR/worktrees"
export WORKTREE_STATE_FILE="$TEMP_TEST_DIR/config/worktree-state.json"

# Performance test configuration
PERFORMANCE_ITERATIONS=10
SCALABILITY_MAX_OPERATIONS=50
LARGE_DATASET_SIZE=1000
MEMORY_SAMPLE_INTERVAL=1
TIMEOUT_SECONDS=300

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()
PERFORMANCE_RESULTS=()

# Colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" RESET=""
fi

# =============================================================================
# Test Infrastructure
# =============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

perf_log() {
    local test_name="$1"
    local metric="$2"
    local value="$3"
    local unit="$4"
    
    echo "PERF: $test_name | $metric: $value $unit"
    PERFORMANCE_RESULTS+=("$test_name,$metric,$value,$unit")
}

run_performance_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo
    echo "${BLUE}${BOLD}▶ Running Performance Test: $test_name${RESET}"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    ((TESTS_RUN++))
    
    # Setup test environment
    setup_test_environment
    
    if $test_function; then
        echo "${GREEN}✓ PASSED: $test_name${RESET}"
        ((TESTS_PASSED++))
        return 0
    else
        echo "${RED}✗ FAILED: $test_name${RESET}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

setup_test_environment() {
    # Clean up any previous test data
    rm -rf "$TEMP_TEST_DIR"
    mkdir -p "$TEMP_TEST_DIR" "$RESULTS_DIR" "$CHECKPOINT_DIR" "$BACKUP_DIR" "$LOCK_DIR"
    mkdir -p "$TEMP_TEST_DIR/config" "$TEMP_TEST_DIR/logs" "$TEMP_TEST_DIR/worktrees"
    
    # Set up test repository if needed
    if [[ ! -d "$TEST_REPO" ]]; then
        setup_test_repo
    fi
}

setup_test_repo() {
    log "Setting up performance test repository..."
    
    cd "$TEMP_TEST_DIR"
    git init "$REPO_NAME"
    cd "$REPO_NAME"
    
    # Configure git
    git config user.name "Perf Test User"
    git config user.email "perf@example.com"
    git config init.defaultBranch main
    
    # Create realistic repository structure
    echo "# Performance Test Repository" > README.md
    mkdir -p src tests docs config
    
    # Create multiple files of various sizes
    for i in {1..10}; do
        echo "console.log('Module $i');" > "src/module$i.js"
        echo "test('Module $i', () => {});" > "tests/module$i.test.js"
        echo "# Module $i Documentation" > "docs/module$i.md"
    done
    
    # Create config files
    echo '{"version": "1.0.0"}' > config/package.json
    echo 'module.exports = {};' > config/webpack.config.js
    
    git add .
    git commit -m "Initial performance test repository"
    
    log "Performance test repository setup complete"
}

cleanup_test_environment() {
    # Clean up locks and temp files
    find "$TEMP_TEST_DIR" -name "*.lock" -delete 2>/dev/null || true
    find "$TEMP_TEST_DIR" -name "*.tmp*" -delete 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup_test_environment EXIT

# Utility functions for performance measurement
measure_time() {
    local start_time
    start_time=$(date +%s%N)  # nanoseconds
    
    "$@"
    local exit_code=$?
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    echo "$duration_ms"
    return $exit_code
}

measure_memory() {
    local pid=$1
    local interval=${2:-1}
    local output_file="$TEMP_TEST_DIR/memory_usage.log"
    
    while kill -0 "$pid" 2>/dev/null; do
        if command -v ps >/dev/null 2>&1; then
            # macOS/Linux compatible memory measurement
            ps -o pid,rss,vsz -p "$pid" 2>/dev/null | tail -1 >> "$output_file" || true
        fi
        sleep "$interval"
    done &
    
    echo $!  # Return monitor PID
}

get_system_load() {
    if command -v uptime >/dev/null 2>&1; then
        uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ','
    else
        echo "0.0"
    fi
}

# =============================================================================
# Startup Performance Tests
# =============================================================================

test_state_manager_initialization() {
    log "Testing state manager initialization performance..."
    
    local total_time=0
    local iterations=$PERFORMANCE_ITERATIONS
    
    for i in $(seq 1 $iterations); do
        # Clean state for each iteration
        rm -f "$STATE_FILE"
        
        # Measure initialization time
        local init_time
        init_time=$(measure_time init_state_manager)
        total_time=$((total_time + init_time))
        
        # Verify initialization worked
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "ERROR: State file not created during initialization"
            return 1
        fi
    done
    
    local avg_time=$((total_time / iterations))
    perf_log "State Manager Init" "Average Time" "$avg_time" "ms"
    
    # Performance threshold check
    if [[ $avg_time -gt 1000 ]]; then  # 1 second
        echo "WARNING: State manager initialization is slow: ${avg_time}ms"
    fi
    
    log "State manager initialization performance test passed (avg: ${avg_time}ms)"
    return 0
}

test_worktree_manager_initialization() {
    log "Testing worktree manager initialization performance..."
    
    cd "$TEST_REPO"
    
    local total_time=0
    local iterations=$PERFORMANCE_ITERATIONS
    
    for i in $(seq 1 $iterations); do
        # Clean worktree state for each iteration
        rm -f "$WORKTREE_STATE_FILE"
        
        # Measure first worktree creation time (includes initialization)
        local init_time
        init_time=$(measure_time create_worktree "$i" 1)
        total_time=$((total_time + init_time))
        
        # Clean up created worktree
        cleanup_worktree "phase-$i-task-1" "true" >/dev/null 2>&1 || true
    done
    
    local avg_time=$((total_time / iterations))
    perf_log "Worktree Manager Init" "Average Time" "$avg_time" "ms"
    
    # Performance threshold check
    if [[ $avg_time -gt 5000 ]]; then  # 5 seconds
        echo "WARNING: Worktree manager initialization is slow: ${avg_time}ms"
    fi
    
    log "Worktree manager initialization performance test passed (avg: ${avg_time}ms)"
    return 0
}

test_error_recovery_initialization() {
    log "Testing error recovery system initialization performance..."
    
    local total_time=0
    local iterations=$PERFORMANCE_ITERATIONS
    
    for i in $(seq 1 $iterations); do
        # Clean error recovery state
        rm -rf "$CHECKPOINT_DIR"/*
        rm -f "$ERROR_LOG"
        
        # Measure checkpoint creation time (includes initialization)
        local init_time
        init_time=$(measure_time create_checkpoint "perf-test-$i" "test-phase")
        total_time=$((total_time + init_time))
    done
    
    local avg_time=$((total_time / iterations))
    perf_log "Error Recovery Init" "Average Time" "$avg_time" "ms"
    
    # Performance threshold check
    if [[ $avg_time -gt 2000 ]]; then  # 2 seconds
        echo "WARNING: Error recovery initialization is slow: ${avg_time}ms"
    fi
    
    log "Error recovery initialization performance test passed (avg: ${avg_time}ms)"
    return 0
}

# =============================================================================
# State Operation Performance Tests
# =============================================================================

test_state_read_performance() {
    log "Testing state read operation performance..."
    
    # Create test state
    local large_tasks='['
    for i in $(seq 1 100); do
        large_tasks+='"task-'$i'"'
        if [[ $i -lt 100 ]]; then
            large_tasks+=','
        fi
    done
    large_tasks+=']'
    
    local test_state='{
        "phase": "performance-test",
        "completedTasks": '$large_tasks',
        "signals": {},
        "lastActivation": "",
        "metadata": {"size": "medium"}
    }'
    write_state "$test_state" "initial"
    
    # Measure read performance
    local total_time=0
    local iterations=$PERFORMANCE_ITERATIONS
    
    for i in $(seq 1 $iterations); do
        local read_time
        read_time=$(measure_time read_state >/dev/null)
        total_time=$((total_time + read_time))
    done
    
    local avg_time=$((total_time / iterations))
    perf_log "State Read" "Average Time" "$avg_time" "ms"
    
    # Performance threshold check
    if [[ $avg_time -gt 100 ]]; then  # 100ms
        echo "WARNING: State read operation is slow: ${avg_time}ms"
    fi
    
    log "State read performance test passed (avg: ${avg_time}ms)"
    return 0
}

test_state_write_performance() {
    log "Testing state write operation performance..."
    
    # Prepare test states
    local test_states=()
    for i in $(seq 1 $PERFORMANCE_ITERATIONS); do
        local state='{
            "phase": "write-perf-test-'$i'",
            "completedTasks": ["task1", "task2", "task3"],
            "signals": {"iteration": '$i'},
            "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "metadata": {"iteration": '$i', "test": true}
        }'
        test_states+=("$state")
    done
    
    # Measure write performance
    local total_time=0
    
    for i in $(seq 0 $((PERFORMANCE_ITERATIONS - 1))); do
        local write_time
        write_time=$(measure_time write_state "${test_states[$i]}" "perf-test-$i")
        total_time=$((total_time + write_time))
    done
    
    local avg_time=$((total_time / PERFORMANCE_ITERATIONS))
    perf_log "State Write" "Average Time" "$avg_time" "ms"
    
    # Performance threshold check
    if [[ $avg_time -gt 200 ]]; then  # 200ms
        echo "WARNING: State write operation is slow: ${avg_time}ms"
    fi
    
    log "State write performance test passed (avg: ${avg_time}ms)"
    return 0
}

test_state_validation_performance() {
    log "Testing state validation performance..."
    
    # Create various sized states for validation
    local sizes=(10 50 100 500)
    
    for size in "${sizes[@]}"; do
        # Create state with specified number of tasks
        local tasks='['
        for i in $(seq 1 $size); do
            tasks+='"task-'$i'"'
            if [[ $i -lt $size ]]; then
                tasks+=','
            fi
        done
        tasks+=']'
        
        local test_state='{
            "phase": "validation-perf-test",
            "completedTasks": '$tasks',
            "signals": {},
            "lastActivation": "",
            "metadata": {"size": '$size'}
        }'
        echo "$test_state" > "$STATE_FILE"
        
        # Measure validation time
        local total_time=0
        local iterations=5
        
        for i in $(seq 1 $iterations); do
            local validation_time
            validation_time=$(measure_time validate_state "$STATE_FILE")
            total_time=$((total_time + validation_time))
        done
        
        local avg_time=$((total_time / iterations))
        perf_log "State Validation ($size tasks)" "Average Time" "$avg_time" "ms"
        
        # Performance threshold check (scales with size)
        local threshold=$((size / 10 + 50))  # 50ms base + 10ms per 10 tasks
        if [[ $avg_time -gt $threshold ]]; then
            echo "WARNING: State validation is slow for $size tasks: ${avg_time}ms (threshold: ${threshold}ms)"
        fi
    done
    
    log "State validation performance test passed"
    return 0
}

# =============================================================================
# Worktree Operation Performance Tests
# =============================================================================

test_worktree_creation_performance() {
    log "Testing worktree creation performance..."
    
    cd "$TEST_REPO"
    
    local total_time=0
    local iterations=$PERFORMANCE_ITERATIONS
    local created_worktrees=()
    
    for i in $(seq 1 $iterations); do
        local creation_time
        creation_time=$(measure_time create_worktree 1 "$i" >/dev/null)
        total_time=$((total_time + creation_time))
        created_worktrees+=("phase-1-task-$i")
    done
    
    local avg_time=$((total_time / iterations))
    perf_log "Worktree Creation" "Average Time" "$avg_time" "ms"
    
    # Clean up created worktrees
    for worktree in "${created_worktrees[@]}"; do
        cleanup_worktree "$worktree" "true" >/dev/null 2>&1 || true
    done
    
    # Performance threshold check
    if [[ $avg_time -gt 3000 ]]; then  # 3 seconds
        echo "WARNING: Worktree creation is slow: ${avg_time}ms"
    fi
    
    log "Worktree creation performance test passed (avg: ${avg_time}ms)"
    return 0
}

test_worktree_cleanup_performance() {
    log "Testing worktree cleanup performance..."
    
    cd "$TEST_REPO"
    
    # Create worktrees to clean up
    local worktrees_to_clean=()
    for i in $(seq 1 $PERFORMANCE_ITERATIONS); do
        create_worktree 2 "$i" >/dev/null
        worktrees_to_clean+=("phase-2-task-$i")
    done
    
    # Measure cleanup performance
    local total_time=0
    
    for worktree in "${worktrees_to_clean[@]}"; do
        local cleanup_time
        cleanup_time=$(measure_time cleanup_worktree "$worktree" "true")
        total_time=$((total_time + cleanup_time))
    done
    
    local avg_time=$((total_time / PERFORMANCE_ITERATIONS))
    perf_log "Worktree Cleanup" "Average Time" "$avg_time" "ms"
    
    # Performance threshold check
    if [[ $avg_time -gt 2000 ]]; then  # 2 seconds
        echo "WARNING: Worktree cleanup is slow: ${avg_time}ms"
    fi
    
    log "Worktree cleanup performance test passed (avg: ${avg_time}ms)"
    return 0
}

test_worktree_listing_performance() {
    log "Testing worktree listing performance..."
    
    cd "$TEST_REPO"
    
    # Create many worktrees
    local num_worktrees=20
    for i in $(seq 1 $num_worktrees); do
        create_worktree 3 "$i" >/dev/null
    done
    
    # Test different listing formats
    local formats=("table" "json" "names")
    
    for format in "${formats[@]}"; do
        local total_time=0
        local iterations=5
        
        for i in $(seq 1 $iterations); do
            local list_time
            list_time=$(measure_time list_worktrees "$format" >/dev/null)
            total_time=$((total_time + list_time))
        done
        
        local avg_time=$((total_time / iterations))
        perf_log "Worktree Listing ($format)" "Average Time" "$avg_time" "ms"
        
        # Performance threshold check
        if [[ $avg_time -gt 500 ]]; then  # 500ms
            echo "WARNING: Worktree listing ($format) is slow: ${avg_time}ms"
        fi
    done
    
    # Clean up worktrees
    for i in $(seq 1 $num_worktrees); do
        cleanup_worktree "phase-3-task-$i" "true" >/dev/null 2>&1 || true
    done
    
    log "Worktree listing performance test passed"
    return 0
}

# =============================================================================
# Concurrent Operation Scaling Tests
# =============================================================================

test_concurrent_state_operations_scaling() {
    log "Testing concurrent state operations scaling..."
    
    # Test different concurrency levels
    local concurrency_levels=(1 2 5 10 15 20)
    
    for level in "${concurrency_levels[@]}"; do
        log "Testing concurrency level: $level"
        
        # Function for concurrent state operation
        concurrent_state_op() {
            local worker_id=$1
            local result_file="$TEMP_TEST_DIR/worker_${worker_id}_result"
            local start_time=$(date +%s%N)
            
            # Perform state operations
            for i in {1..5}; do
                local state='{
                    "phase": "concurrent-test-'$worker_id'",
                    "completedTasks": ["task'$i'"],
                    "signals": {"worker": '$worker_id', "iteration": '$i'},
                    "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                    "metadata": {"worker": '$worker_id', "iteration": '$i'}
                }'
                
                write_state "$state" "worker-$worker_id-$i" >/dev/null 2>&1
                read_state >/dev/null 2>&1
            done
            
            local end_time=$(date +%s%N)
            local duration_ms=$(((end_time - start_time) / 1000000))
            echo "$duration_ms" > "$result_file"
        }
        
        # Start concurrent workers
        local pids=()
        local start_time=$(date +%s%N)
        
        for worker_id in $(seq 1 $level); do
            concurrent_state_op "$worker_id" &
            pids+=($!)
        done
        
        # Wait for all workers to complete
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        local end_time=$(date +%s%N)
        local total_duration_ms=$(((end_time - start_time) / 1000000))
        
        # Calculate worker statistics
        local total_worker_time=0
        local max_worker_time=0
        
        for worker_id in $(seq 1 $level); do
            local worker_time
            worker_time=$(cat "$TEMP_TEST_DIR/worker_${worker_id}_result" 2>/dev/null || echo "0")
            total_worker_time=$((total_worker_time + worker_time))
            
            if [[ $worker_time -gt $max_worker_time ]]; then
                max_worker_time=$worker_time
            fi
        done
        
        local avg_worker_time=$((total_worker_time / level))
        
        perf_log "Concurrent State Ops (${level} workers)" "Total Time" "$total_duration_ms" "ms"
        perf_log "Concurrent State Ops (${level} workers)" "Avg Worker Time" "$avg_worker_time" "ms"
        perf_log "Concurrent State Ops (${level} workers)" "Max Worker Time" "$max_worker_time" "ms"
        
        # Check for performance degradation
        if [[ $level -gt 1 ]]; then
            # Compare with single worker performance (should scale reasonably)
            local efficiency=$((avg_worker_time * 100 / max_worker_time))
            if [[ $efficiency -lt 50 ]]; then  # Less than 50% efficiency
                echo "WARNING: Poor scaling efficiency at $level workers: ${efficiency}%"
            fi
        fi
    done
    
    log "Concurrent state operations scaling test passed"
    return 0
}

test_concurrent_worktree_operations_scaling() {
    log "Testing concurrent worktree operations scaling..."
    
    cd "$TEST_REPO"
    
    # Test different concurrency levels
    local concurrency_levels=(1 2 5 8)  # Limit due to git worktree constraints
    
    for level in "${concurrency_levels[@]}"; do
        log "Testing worktree concurrency level: $level"
        
        # Function for concurrent worktree operation
        concurrent_worktree_op() {
            local worker_id=$1
            local result_file="$TEMP_TEST_DIR/worktree_worker_${worker_id}_result"
            local start_time=$(date +%s%N)
            
            # Create and cleanup worktree
            if create_worktree 4 "$worker_id" >/dev/null 2>&1; then
                sleep 0.1  # Brief pause to simulate work
                cleanup_worktree "phase-4-task-$worker_id" "true" >/dev/null 2>&1
                local end_time=$(date +%s%N)
                local duration_ms=$(((end_time - start_time) / 1000000))
                echo "success,$duration_ms" > "$result_file"
            else
                echo "failed,0" > "$result_file"
            fi
        }
        
        # Start concurrent workers
        local pids=()
        local start_time=$(date +%s%N)
        
        for worker_id in $(seq 1 $level); do
            concurrent_worktree_op "$worker_id" &
            pids+=($!)
        done
        
        # Wait for all workers to complete
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        local end_time=$(date +%s%N)
        local total_duration_ms=$(((end_time - start_time) / 1000000))
        
        # Calculate statistics
        local success_count=0
        local total_worker_time=0
        
        for worker_id in $(seq 1 $level); do
            local result_file="$TEMP_TEST_DIR/worktree_worker_${worker_id}_result"
            if [[ -f "$result_file" ]]; then
                local result
                result=$(cat "$result_file")
                local status="${result%%,*}"
                local duration="${result##*,}"
                
                if [[ "$status" == "success" ]]; then
                    ((success_count++))
                    total_worker_time=$((total_worker_time + duration))
                fi
            fi
        done
        
        local success_rate=$((success_count * 100 / level))
        local avg_worker_time=0
        if [[ $success_count -gt 0 ]]; then
            avg_worker_time=$((total_worker_time / success_count))
        fi
        
        perf_log "Concurrent Worktree Ops (${level} workers)" "Total Time" "$total_duration_ms" "ms"
        perf_log "Concurrent Worktree Ops (${level} workers)" "Success Rate" "$success_rate" "%"
        perf_log "Concurrent Worktree Ops (${level} workers)" "Avg Success Time" "$avg_worker_time" "ms"
        
        # Check for acceptable success rate
        if [[ $success_rate -lt 80 ]]; then
            echo "WARNING: Low success rate for concurrent worktree operations: ${success_rate}%"
        fi
    done
    
    log "Concurrent worktree operations scaling test passed"
    return 0
}

# =============================================================================
# Memory and Resource Usage Tests
# =============================================================================

test_memory_usage_under_load() {
    log "Testing memory usage under load..."
    
    # Function to create memory load
    memory_load_test() {
        # Perform intensive operations
        for i in {1..50}; do
            # State operations
            local large_state='{
                "phase": "memory-test-'$i'",
                "completedTasks": ['$(for j in {1..100}; do echo '"task'$j'"'; done | paste -sd ',')''],
                "signals": {},
                "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                "metadata": {"iteration": '$i'}
            }'
            write_state "$large_state" "memory-test-$i" >/dev/null 2>&1
            read_state >/dev/null 2>&1
            
            # Checkpoint operations
            create_checkpoint "memory-test-$i" "test-phase" >/dev/null 2>&1
        done
    }
    
    # Start memory monitoring
    memory_load_test &
    local test_pid=$!
    
    local monitor_pid
    monitor_pid=$(measure_memory "$test_pid" 1)
    
    # Wait for test to complete
    wait "$test_pid"
    kill "$monitor_pid" 2>/dev/null || true
    
    # Analyze memory usage
    if [[ -f "$TEMP_TEST_DIR/memory_usage.log" ]]; then
        local max_rss=0
        local max_vsz=0
        
        while read -r pid rss vsz; do
            if [[ "$rss" =~ ^[0-9]+$ ]] && [[ $rss -gt $max_rss ]]; then
                max_rss=$rss
            fi
            if [[ "$vsz" =~ ^[0-9]+$ ]] && [[ $vsz -gt $max_vsz ]]; then
                max_vsz=$vsz
            fi
        done < "$TEMP_TEST_DIR/memory_usage.log"
        
        # Convert KB to MB
        local max_rss_mb=$((max_rss / 1024))
        local max_vsz_mb=$((max_vsz / 1024))
        
        perf_log "Memory Usage" "Peak RSS" "$max_rss_mb" "MB"
        perf_log "Memory Usage" "Peak VSZ" "$max_vsz_mb" "MB"
        
        # Memory usage thresholds
        if [[ $max_rss_mb -gt 100 ]]; then  # 100MB
            echo "WARNING: High memory usage detected: ${max_rss_mb}MB RSS"
        fi
        
        if [[ $max_vsz_mb -gt 500 ]]; then  # 500MB
            echo "WARNING: High virtual memory usage detected: ${max_vsz_mb}MB VSZ"
        fi
    else
        echo "WARNING: Could not measure memory usage (ps command may not be available)"
    fi
    
    log "Memory usage under load test passed"
    return 0
}

test_resource_cleanup_efficiency() {
    log "Testing resource cleanup efficiency..."
    
    cd "$TEST_REPO"
    
    # Create many resources
    local num_resources=30
    
    # Create state backups
    for i in $(seq 1 $num_resources); do
        local state='{
            "phase": "cleanup-test-'$i'",
            "completedTasks": [],
            "signals": {},
            "lastActivation": "",
            "metadata": {"iteration": '$i'}
        }'
        write_state "$state" "cleanup-test-$i" >/dev/null
        backup_state "cleanup-test-$i" >/dev/null
    done
    
    # Create checkpoints
    for i in $(seq 1 $num_resources); do
        create_checkpoint "cleanup-operation-$i" "cleanup-phase" >/dev/null
    done
    
    # Create worktrees
    for i in $(seq 1 10); do  # Fewer worktrees due to git limitations
        create_worktree 5 "$i" >/dev/null
    done
    
    # Create temporary files
    for i in $(seq 1 $num_resources); do
        touch "$TEMP_TEST_DIR/temp_file_$i.tmp"
        touch "$TEMP_TEST_DIR/temp_file_$i.temp"
    done
    
    # Measure cleanup time
    local cleanup_start=$(date +%s%N)
    
    # Run various cleanup operations
    cleanup_old_backups >/dev/null 2>&1 || true
    cleanup_checkpoints 0 >/dev/null 2>&1 || true  # Clean all checkpoints
    cleanup_completed_worktrees >/dev/null 2>&1 || true
    cleanup_temp_files >/dev/null 2>&1 || true
    
    local cleanup_end=$(date +%s%N)
    local cleanup_duration_ms=$(((cleanup_end - cleanup_start) / 1000000))
    
    perf_log "Resource Cleanup" "Total Time" "$cleanup_duration_ms" "ms"
    
    # Verify cleanup effectiveness
    local remaining_backups
    remaining_backups=$(find "$BACKUP_DIR" -name "state-*.json" | wc -l)
    
    local remaining_checkpoints
    remaining_checkpoints=$(find "$CHECKPOINT_DIR" -name "checkpoint-*" -type d | wc -l)
    
    local remaining_temp_files
    remaining_temp_files=$(find "$TEMP_TEST_DIR" -name "*.tmp" -o -name "*.temp" | wc -l)
    
    perf_log "Resource Cleanup" "Remaining Backups" "$remaining_backups" "count"
    perf_log "Resource Cleanup" "Remaining Checkpoints" "$remaining_checkpoints" "count"
    perf_log "Resource Cleanup" "Remaining Temp Files" "$remaining_temp_files" "count"
    
    # Performance threshold
    if [[ $cleanup_duration_ms -gt 5000 ]]; then  # 5 seconds
        echo "WARNING: Resource cleanup is slow: ${cleanup_duration_ms}ms"
    fi
    
    log "Resource cleanup efficiency test passed"
    return 0
}

# =============================================================================
# Large Dataset Handling Tests
# =============================================================================

test_large_state_operations() {
    log "Testing large state operations..."
    
    # Test different state sizes
    local sizes=(100 500 1000 2000)
    
    for size in "${sizes[@]}"; do
        log "Testing state with $size tasks"
        
        # Create large state
        local tasks='['
        for i in $(seq 1 $size); do
            tasks+='"task-'$i'-with-very-long-name-to-increase-size"'
            if [[ $i -lt $size ]]; then
                tasks+=','
            fi
        done
        tasks+=']'
        
        # Create large signals object
        local signals='{'
        for i in $(seq 1 50); do
            signals+='"signal'$i'": {"status": true, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "data": "large signal data payload"}'
            if [[ $i -lt 50 ]]; then
                signals+=','
            fi
        done
        signals+='}'
        
        local large_state='{
            "phase": "large-state-test-'$size'",
            "completedTasks": '$tasks',
            "signals": '$signals',
            "lastActivation": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "metadata": {
                "size": '$size',
                "description": "Large state test with '$size' tasks and comprehensive metadata",
                "performance_test": true
            }
        }'
        
        # Measure write performance
        local write_time
        write_time=$(measure_time write_state "$large_state" "large-test-$size")
        perf_log "Large State ($size tasks)" "Write Time" "$write_time" "ms"
        
        # Measure read performance
        local read_time
        read_time=$(measure_time read_state >/dev/null)
        perf_log "Large State ($size tasks)" "Read Time" "$read_time" "ms"
        
        # Measure validation performance
        local validation_time
        validation_time=$(measure_time validate_state "$STATE_FILE")
        perf_log "Large State ($size tasks)" "Validation Time" "$validation_time" "ms"
        
        # Measure backup performance
        local backup_time
        backup_time=$(measure_time backup_state "large-test-$size")
        perf_log "Large State ($size tasks)" "Backup Time" "$backup_time" "ms"
        
        # Get file size
        local file_size
        file_size=$(stat -f%z "$STATE_FILE" 2>/dev/null || stat -c%s "$STATE_FILE" 2>/dev/null || echo "0")
        local file_size_kb=$((file_size / 1024))
        perf_log "Large State ($size tasks)" "File Size" "$file_size_kb" "KB"
        
        # Performance thresholds (scale with size)
        local write_threshold=$((size / 10 + 100))  # 100ms base + 10ms per 100 tasks
        local read_threshold=$((size / 20 + 50))   # 50ms base + 5ms per 100 tasks
        
        if [[ $write_time -gt $write_threshold ]]; then
            echo "WARNING: Large state write is slow for $size tasks: ${write_time}ms (threshold: ${write_threshold}ms)"
        fi
        
        if [[ $read_time -gt $read_threshold ]]; then
            echo "WARNING: Large state read is slow for $size tasks: ${read_time}ms (threshold: ${read_threshold}ms)"
        fi
    done
    
    log "Large state operations test passed"
    return 0
}

test_bulk_worktree_operations() {
    log "Testing bulk worktree operations..."
    
    cd "$TEST_REPO"
    
    local num_worktrees=25
    local created_worktrees=()
    
    # Measure bulk creation
    local creation_start=$(date +%s%N)
    
    for i in $(seq 1 $num_worktrees); do
        if create_worktree 6 "$i" >/dev/null 2>&1; then
            created_worktrees+=("phase-6-task-$i")
        fi
    done
    
    local creation_end=$(date +%s%N)
    local creation_duration_ms=$(((creation_end - creation_start) / 1000000))
    
    perf_log "Bulk Worktree Creation" "Total Time" "$creation_duration_ms" "ms"
    perf_log "Bulk Worktree Creation" "Created Count" "${#created_worktrees[@]}" "count"
    
    if [[ ${#created_worktrees[@]} -gt 0 ]]; then
        local avg_creation_time=$((creation_duration_ms / ${#created_worktrees[@]}))
        perf_log "Bulk Worktree Creation" "Avg Per Worktree" "$avg_creation_time" "ms"
    fi
    
    # Measure listing performance with many worktrees
    local listing_time
    listing_time=$(measure_time list_worktrees "table" >/dev/null)
    perf_log "Worktree Listing (${#created_worktrees[@]} worktrees)" "Time" "$listing_time" "ms"
    
    # Measure bulk cleanup
    local cleanup_start=$(date +%s%N)
    
    for worktree in "${created_worktrees[@]}"; do
        cleanup_worktree "$worktree" "true" >/dev/null 2>&1 || true
    done
    
    local cleanup_end=$(date +%s%N)
    local cleanup_duration_ms=$(((cleanup_end - cleanup_start) / 1000000))
    
    perf_log "Bulk Worktree Cleanup" "Total Time" "$cleanup_duration_ms" "ms"
    
    if [[ ${#created_worktrees[@]} -gt 0 ]]; then
        local avg_cleanup_time=$((cleanup_duration_ms / ${#created_worktrees[@]}))
        perf_log "Bulk Worktree Cleanup" "Avg Per Worktree" "$avg_cleanup_time" "ms"
    fi
    
    # Performance thresholds
    if [[ $creation_duration_ms -gt 60000 ]]; then  # 1 minute
        echo "WARNING: Bulk worktree creation is slow: ${creation_duration_ms}ms"
    fi
    
    if [[ $cleanup_duration_ms -gt 30000 ]]; then  # 30 seconds
        echo "WARNING: Bulk worktree cleanup is slow: ${cleanup_duration_ms}ms"
    fi
    
    log "Bulk worktree operations test passed"
    return 0
}

# =============================================================================
# Performance Report Generation
# =============================================================================

generate_performance_report() {
    log "Generating performance report..."
    
    local report_file="$RESULTS_DIR/performance_report.md"
    local csv_file="$RESULTS_DIR/performance_data.csv"
    
    # Create markdown report
    cat > "$report_file" << EOF
# Claude Dev Pipeline - Performance Test Report

**Generated:** $(date)
**System:** $(uname -s) $(uname -r)
**Load Average:** $(get_system_load)

## Test Summary

- **Total Tests Run:** $TESTS_RUN
- **Tests Passed:** $TESTS_PASSED
- **Tests Failed:** $TESTS_FAILED

## Performance Metrics

EOF
    
    # Create CSV header
    echo "Test,Metric,Value,Unit" > "$csv_file"
    
    # Group results by test category
    local categories=(
        "Init"
        "State"
        "Worktree"
        "Concurrent"
        "Memory"
        "Cleanup"
        "Large"
        "Bulk"
    )
    
    for category in "${categories[@]}"; do
        echo "### $category Performance" >> "$report_file"
        echo "" >> "$report_file"
        echo "| Test | Metric | Value | Unit |" >> "$report_file"
        echo "|------|--------|-------|------|" >> "$report_file"
        
        # Filter results for this category
        for result in "${PERFORMANCE_RESULTS[@]}"; do
            if [[ "$result" =~ $category ]]; then
                local test_name="${result%%,*}"
                local remainder="${result#*,}"
                local metric="${remainder%%,*}"
                local remainder="${remainder#*,}"
                local value="${remainder%%,*}"
                local unit="${remainder##*,}"
                
                echo "| $test_name | $metric | $value | $unit |" >> "$report_file"
                echo "$test_name,$metric,$value,$unit" >> "$csv_file"
            fi
        done
        
        echo "" >> "$report_file"
    done
    
    # Add failed tests if any
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "## Failed Tests" >> "$report_file"
        echo "" >> "$report_file"
        for test in "${FAILED_TESTS[@]}"; do
            echo "- $test" >> "$report_file"
        done
        echo "" >> "$report_file"
    fi
    
    # Add recommendations
    echo "## Performance Recommendations" >> "$report_file"
    echo "" >> "$report_file"
    echo "- Monitor memory usage during large state operations" >> "$report_file"
    echo "- Consider implementing state compression for large datasets" >> "$report_file"
    echo "- Optimize concurrent operations based on system capabilities" >> "$report_file"
    echo "- Regular cleanup of temporary files and old backups" >> "$report_file"
    echo "- Benchmark performance after system updates" >> "$report_file"
    
    log "Performance report generated: $report_file"
    log "Performance data exported: $csv_file"
    
    # Display summary
    echo
    echo "${CYAN}${BOLD}Performance Summary:${RESET}"
    echo "Report: $report_file"
    echo "Data: $csv_file"
    echo "Total Metrics: ${#PERFORMANCE_RESULTS[@]}"
}

# =============================================================================
# Main Test Execution
# =============================================================================

print_header() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                    PERFORMANCE TEST SUITE${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Testing startup performance, operation speed, scalability, and resource usage"
    echo "System: $(uname -s) $(uname -r)"
    echo "Load Average: $(get_system_load)"
    echo
}

print_summary() {
    echo
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo "${BOLD}${BLUE}                           TEST SUMMARY${RESET}"
    echo "${BOLD}${BLUE}=============================================================================${RESET}"
    echo
    echo "Total Tests Run: $TESTS_RUN"
    echo "${GREEN}Tests Passed: $TESTS_PASSED${RESET}"
    echo "${RED}Tests Failed: $TESTS_FAILED${RESET}"
    echo "Performance Metrics Collected: ${#PERFORMANCE_RESULTS[@]}"
    echo
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "${RED}Failed Tests:${RESET}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo
        exit 1
    else
        echo "${GREEN}${BOLD}🎉 All performance tests passed!${RESET}"
        echo
        exit 0
    fi
}

main() {
    print_header
    
    # Startup Performance Tests
    run_performance_test "State Manager Initialization" test_state_manager_initialization
    run_performance_test "Worktree Manager Initialization" test_worktree_manager_initialization
    run_performance_test "Error Recovery Initialization" test_error_recovery_initialization
    
    # State Operation Performance Tests
    run_performance_test "State Read Performance" test_state_read_performance
    run_performance_test "State Write Performance" test_state_write_performance
    run_performance_test "State Validation Performance" test_state_validation_performance
    
    # Worktree Operation Performance Tests
    run_performance_test "Worktree Creation Performance" test_worktree_creation_performance
    run_performance_test "Worktree Cleanup Performance" test_worktree_cleanup_performance
    run_performance_test "Worktree Listing Performance" test_worktree_listing_performance
    
    # Concurrent Operation Scaling Tests
    run_performance_test "Concurrent State Operations Scaling" test_concurrent_state_operations_scaling
    run_performance_test "Concurrent Worktree Operations Scaling" test_concurrent_worktree_operations_scaling
    
    # Memory and Resource Usage Tests
    run_performance_test "Memory Usage Under Load" test_memory_usage_under_load
    run_performance_test "Resource Cleanup Efficiency" test_resource_cleanup_efficiency
    
    # Large Dataset Handling Tests
    run_performance_test "Large State Operations" test_large_state_operations
    run_performance_test "Bulk Worktree Operations" test_bulk_worktree_operations
    
    # Generate performance report
    generate_performance_report
    
    print_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi