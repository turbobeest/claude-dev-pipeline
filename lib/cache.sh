#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - High-Performance Caching System
# =============================================================================
#
# Memory-efficient caching system with TTL-based invalidation for frequently
# accessed data including skill rules, configuration, and pipeline state.
#
# Features:
# - In-memory key-value caching with TTL
# - Memory-efficient storage using files when needed
# - Cache statistics and monitoring
# - Automatic garbage collection
# - Cache warming for critical data
# - Concurrent access safety
#
# Usage:
#   source lib/cache.sh
#   cache_set "key" "value" 300  # 5 minute TTL
#   value=$(cache_get "key")
#   cache_clear
#   cache_stats
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source logger for cache operations
source "${PROJECT_ROOT}/lib/logger.sh" 2>/dev/null || {
    # Fallback logging functions if logger not available
    log_debug() { echo "[DEBUG] $*" >&2; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_metric() { echo "[METRIC] $*" >&2; }
}

# =============================================================================
# Configuration
# =============================================================================

CACHE_DIR="${PROJECT_ROOT}/.cache"
CACHE_INDEX_FILE="${CACHE_DIR}/index"
CACHE_STATS_FILE="${CACHE_DIR}/stats.json"
CACHE_DEFAULT_TTL=300  # 5 minutes
CACHE_MAX_MEMORY_ITEMS=1000
CACHE_MAX_FILE_SIZE_KB=100
CACHE_GC_INTERVAL=60   # 1 minute
CACHE_ENABLED="${CACHE_ENABLED:-true}"

# In-memory cache using associative arrays simulation
CACHE_KEYS=""
CACHE_PREFIX="CACHE_DATA_"
CACHE_TTL_PREFIX="CACHE_TTL_"
CACHE_SIZE_PREFIX="CACHE_SIZE_"

# Cache statistics
CACHE_HITS=0
CACHE_MISSES=0
CACHE_EVICTIONS=0
CACHE_GC_RUNS=0
CACHE_LAST_GC=0

# =============================================================================
# Initialization
# =============================================================================

# Initialize cache system
init_cache() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
    
    # Initialize index file
    touch "$CACHE_INDEX_FILE"
    
    # Initialize stats
    init_cache_stats
    
    # Set up periodic garbage collection
    setup_cache_gc
    
    # Warm critical cache entries
    warm_cache
    
    log_debug "Cache system initialized" "cache_dir=$CACHE_DIR"
}

# Initialize cache statistics
init_cache_stats() {
    local stats_json='{
        "hits": 0,
        "misses": 0,
        "evictions": 0,
        "gc_runs": 0,
        "last_gc": 0,
        "memory_items": 0,
        "file_items": 0,
        "total_size_kb": 0,
        "initialized_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }'
    echo "$stats_json" > "$CACHE_STATS_FILE"
}

# Set up garbage collection
setup_cache_gc() {
    # Run GC if last run was more than interval ago
    local current_time=$(date +%s)
    if [[ $((current_time - CACHE_LAST_GC)) -gt $CACHE_GC_INTERVAL ]]; then
        cache_gc &
    fi
}

# =============================================================================
# Core Caching Functions
# =============================================================================

# Set cache entry
cache_set() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local key="$1"
    local value="$2"
    local ttl="${3:-$CACHE_DEFAULT_TTL}"
    
    if [[ -z "$key" ]]; then
        log_error "Cache key cannot be empty"
        return 1
    fi
    
    local expire_time=$(($(date +%s) + ttl))
    local value_size=${#value}
    
    # Sanitize key for variable names
    local safe_key=$(echo "$key" | tr -c '[:alnum:]_' '_')
    
    # Decide storage strategy based on size
    if [[ $value_size -lt $((CACHE_MAX_FILE_SIZE_KB * 1024)) ]] && [[ $(cache_memory_count) -lt $CACHE_MAX_MEMORY_ITEMS ]]; then
        # Store in memory
        eval "${CACHE_PREFIX}${safe_key}=\$value"
        eval "${CACHE_TTL_PREFIX}${safe_key}=\$expire_time"
        eval "${CACHE_SIZE_PREFIX}${safe_key}=\$value_size"
        
        # Add to keys list if not already there
        if [[ "$CACHE_KEYS" != *"|$safe_key|"* ]]; then
            CACHE_KEYS="${CACHE_KEYS}|${safe_key}|"
        fi
        
        log_debug "Cache entry stored in memory" "key=$key" "size_bytes=$value_size" "ttl=$ttl"
    else
        # Store in file
        local cache_file="${CACHE_DIR}/${safe_key}.cache"
        echo "$value" > "$cache_file"
        
        # Update index
        echo "${safe_key}|${expire_time}|${value_size}|file" >> "$CACHE_INDEX_FILE"
        
        log_debug "Cache entry stored in file" "key=$key" "size_bytes=$value_size" "ttl=$ttl"
    fi
    
    # Update statistics
    update_cache_stats "set" "$value_size"
}

# Get cache entry
cache_get() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 1
    fi
    
    local key="$1"
    if [[ -z "$key" ]]; then
        log_error "Cache key cannot be empty"
        return 1
    fi
    
    local safe_key=$(echo "$key" | tr -c '[:alnum:]_' '_')
    local current_time=$(date +%s)
    
    # Check memory first
    local ttl_var="${CACHE_TTL_PREFIX}${safe_key}"
    local data_var="${CACHE_PREFIX}${safe_key}"
    local expire_time
    
    eval "expire_time=\${${ttl_var}:-0}"
    
    if [[ $expire_time -gt 0 ]] && [[ $current_time -lt $expire_time ]]; then
        # Found in memory and not expired
        local value
        eval "value=\${${data_var}:-}"
        if [[ -n "$value" ]]; then
            CACHE_HITS=$((CACHE_HITS + 1))
            update_cache_stats "hit"
            echo "$value"
            return 0
        fi
    fi
    
    # Check file cache
    local cache_file="${CACHE_DIR}/${safe_key}.cache"
    if [[ -f "$cache_file" ]]; then
        # Check TTL from index
        local index_entry=$(grep "^${safe_key}|" "$CACHE_INDEX_FILE" 2>/dev/null | tail -1)
        if [[ -n "$index_entry" ]]; then
            local entry_expire_time=$(echo "$index_entry" | cut -d'|' -f2)
            if [[ $current_time -lt $entry_expire_time ]]; then
                # Found in file and not expired
                local value=$(cat "$cache_file")
                CACHE_HITS=$((CACHE_HITS + 1))
                update_cache_stats "hit"
                echo "$value"
                return 0
            else
                # Expired file entry, remove it
                rm -f "$cache_file"
                sed -i.bak "/^${safe_key}|/d" "$CACHE_INDEX_FILE" 2>/dev/null || true
            fi
        fi
    fi
    
    # Not found or expired
    CACHE_MISSES=$((CACHE_MISSES + 1))
    update_cache_stats "miss"
    return 1
}

# Check if cache entry exists and is valid
cache_exists() {
    cache_get "$1" >/dev/null 2>&1
}

# Delete cache entry
cache_delete() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local key="$1"
    if [[ -z "$key" ]]; then
        return 1
    fi
    
    local safe_key=$(echo "$key" | tr -c '[:alnum:]_' '_')
    
    # Remove from memory
    eval "unset ${CACHE_PREFIX}${safe_key}"
    eval "unset ${CACHE_TTL_PREFIX}${safe_key}"
    eval "unset ${CACHE_SIZE_PREFIX}${safe_key}"
    
    # Remove from keys list
    CACHE_KEYS=$(echo "$CACHE_KEYS" | sed "s/|${safe_key}|//g")
    
    # Remove file
    local cache_file="${CACHE_DIR}/${safe_key}.cache"
    rm -f "$cache_file"
    
    # Remove from index
    sed -i.bak "/^${safe_key}|/d" "$CACHE_INDEX_FILE" 2>/dev/null || true
    
    log_debug "Cache entry deleted" "key=$key"
}

# Clear entire cache
cache_clear() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Clear memory cache
    local IFS='|'
    for safe_key in $CACHE_KEYS; do
        if [[ -n "$safe_key" ]]; then
            eval "unset ${CACHE_PREFIX}${safe_key}"
            eval "unset ${CACHE_TTL_PREFIX}${safe_key}"
            eval "unset ${CACHE_SIZE_PREFIX}${safe_key}"
        fi
    done
    CACHE_KEYS=""
    
    # Clear file cache
    rm -rf "${CACHE_DIR:?}"/*.cache 2>/dev/null || true
    > "$CACHE_INDEX_FILE"
    
    # Reset stats
    CACHE_HITS=0
    CACHE_MISSES=0
    CACHE_EVICTIONS=0
    
    log_info "Cache cleared"
}

# =============================================================================
# Cache Management
# =============================================================================

# Garbage collection
cache_gc() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    local cleaned_count=0
    
    # Clean memory cache
    local IFS='|'
    local new_keys=""
    for safe_key in $CACHE_KEYS; do
        if [[ -n "$safe_key" ]]; then
            local ttl_var="${CACHE_TTL_PREFIX}${safe_key}"
            local expire_time
            eval "expire_time=\${${ttl_var}:-0}"
            
            if [[ $expire_time -gt 0 ]] && [[ $current_time -ge $expire_time ]]; then
                # Expired, remove it
                eval "unset ${CACHE_PREFIX}${safe_key}"
                eval "unset ${CACHE_TTL_PREFIX}${safe_key}"
                eval "unset ${CACHE_SIZE_PREFIX}${safe_key}"
                cleaned_count=$((cleaned_count + 1))
            else
                # Keep it
                new_keys="${new_keys}|${safe_key}|"
            fi
        fi
    done
    CACHE_KEYS="$new_keys"
    
    # Clean file cache
    if [[ -f "$CACHE_INDEX_FILE" ]]; then
        local temp_index="${CACHE_INDEX_FILE}.tmp"
        while IFS='|' read -r safe_key expire_time size_bytes storage_type; do
            if [[ -n "$safe_key" ]] && [[ $current_time -lt $expire_time ]]; then
                echo "${safe_key}|${expire_time}|${size_bytes}|${storage_type}" >> "$temp_index"
            else
                # Expired, remove file
                rm -f "${CACHE_DIR}/${safe_key}.cache"
                cleaned_count=$((cleaned_count + 1))
            fi
        done < "$CACHE_INDEX_FILE"
        
        mv "$temp_index" "$CACHE_INDEX_FILE" 2>/dev/null || true
    fi
    
    CACHE_GC_RUNS=$((CACHE_GC_RUNS + 1))
    CACHE_LAST_GC=$current_time
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_debug "Cache garbage collection completed" "cleaned_entries=$cleaned_count"
    fi
    
    update_cache_stats "gc" 0 "$cleaned_count"
}

# Get memory cache item count
cache_memory_count() {
    local count=0
    local IFS='|'
    for safe_key in $CACHE_KEYS; do
        if [[ -n "$safe_key" ]]; then
            count=$((count + 1))
        fi
    done
    echo $count
}

# Get file cache item count
cache_file_count() {
    if [[ -f "$CACHE_INDEX_FILE" ]]; then
        wc -l < "$CACHE_INDEX_FILE" | tr -d ' '
    else
        echo 0
    fi
}

# Update cache statistics
update_cache_stats() {
    local operation="$1"
    local size_bytes="${2:-0}"
    local cleaned_count="${3:-0}"
    
    # Update in-memory counters
    case "$operation" in
        hit)
            CACHE_HITS=$((CACHE_HITS + 1))
            ;;
        miss)
            CACHE_MISSES=$((CACHE_MISSES + 1))
            ;;
        evict)
            CACHE_EVICTIONS=$((CACHE_EVICTIONS + 1))
            ;;
        gc)
            CACHE_GC_RUNS=$((CACHE_GC_RUNS + 1))
            CACHE_EVICTIONS=$((CACHE_EVICTIONS + cleaned_count))
            ;;
    esac
    
    # Update stats file (non-blocking)
    {
        local memory_items=$(cache_memory_count)
        local file_items=$(cache_file_count)
        local total_size_kb=$(du -sk "$CACHE_DIR" 2>/dev/null | cut -f1 || echo 0)
        
        local stats_json="{
            \"hits\": $CACHE_HITS,
            \"misses\": $CACHE_MISSES,
            \"evictions\": $CACHE_EVICTIONS,
            \"gc_runs\": $CACHE_GC_RUNS,
            \"last_gc\": $CACHE_LAST_GC,
            \"memory_items\": $memory_items,
            \"file_items\": $file_items,
            \"total_size_kb\": $total_size_kb,
            \"hit_ratio\": $(echo "scale=4; $CACHE_HITS / ($CACHE_HITS + $CACHE_MISSES + 0.0001)" | bc 2>/dev/null || echo "0.0000"),
            \"updated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }"
        echo "$stats_json" > "$CACHE_STATS_FILE"
    } &
}

# =============================================================================
# High-Level Cache Functions
# =============================================================================

# Cache configuration files
cache_config() {
    local config_file="$1"
    local cache_key="config:$(basename "$config_file")"
    
    if ! cache_exists "$cache_key"; then
        if [[ -f "$config_file" ]]; then
            local content=$(cat "$config_file")
            cache_set "$cache_key" "$content" 600  # 10 minutes
            log_debug "Cached configuration file" "file=$config_file"
        fi
    fi
    
    cache_get "$cache_key"
}

# Cache skill rules
cache_skill_rules() {
    local rules_file="${PROJECT_ROOT}/config/skill-rules.json"
    cache_config "$rules_file"
}

# Cache JSON parsed data
cache_json_parse() {
    local json_file="$1"
    local jq_filter="${2:-.}"
    local cache_key="json:$(basename "$json_file"):$(echo "$jq_filter" | md5sum | cut -d' ' -f1)"
    
    if ! cache_exists "$cache_key"; then
        if [[ -f "$json_file" ]]; then
            local result=$(jq -r "$jq_filter" "$json_file" 2>/dev/null || echo "")
            if [[ -n "$result" ]]; then
                cache_set "$cache_key" "$result" 300  # 5 minutes
                log_debug "Cached JSON parse result" "file=$json_file" "filter=$jq_filter"
            fi
        fi
    fi
    
    cache_get "$cache_key"
}

# Warm cache with critical data
warm_cache() {
    log_debug "Warming cache with critical data"
    
    # Cache skill rules
    cache_skill_rules >/dev/null 2>&1 &
    
    # Cache common configuration files
    if [[ -d "${PROJECT_ROOT}/config" ]]; then
        for config_file in "${PROJECT_ROOT}/config"/*.json; do
            if [[ -f "$config_file" ]]; then
                cache_config "$config_file" >/dev/null 2>&1 &
            fi
        done
    fi
    
    # Cache frequently accessed JSON paths
    local skill_rules="${PROJECT_ROOT}/config/skill-rules.json"
    if [[ -f "$skill_rules" ]]; then
        cache_json_parse "$skill_rules" '.skills | length' >/dev/null 2>&1 &
        cache_json_parse "$skill_rules" '.skills[] | .skill' >/dev/null 2>&1 &
    fi
}

# =============================================================================
# Cache Statistics and Monitoring
# =============================================================================

# Get cache statistics
cache_stats() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        echo "Cache is disabled"
        return 0
    fi
    
    local memory_items=$(cache_memory_count)
    local file_items=$(cache_file_count)
    local total_items=$((memory_items + file_items))
    local hit_ratio="0.0000"
    
    if [[ $((CACHE_HITS + CACHE_MISSES)) -gt 0 ]]; then
        hit_ratio=$(echo "scale=4; $CACHE_HITS / ($CACHE_HITS + $CACHE_MISSES)" | bc 2>/dev/null || echo "0.0000")
    fi
    
    echo "Cache Statistics:"
    echo "  Status: enabled"
    echo "  Total Items: $total_items (memory: $memory_items, file: $file_items)"
    echo "  Hits: $CACHE_HITS"
    echo "  Misses: $CACHE_MISSES"
    echo "  Hit Ratio: ${hit_ratio}"
    echo "  Evictions: $CACHE_EVICTIONS"
    echo "  GC Runs: $CACHE_GC_RUNS"
    echo "  Cache Directory: $CACHE_DIR"
    
    if [[ -f "$CACHE_STATS_FILE" ]]; then
        echo "  Detailed stats available in: $CACHE_STATS_FILE"
    fi
}

# Get cache statistics as JSON
cache_stats_json() {
    if [[ -f "$CACHE_STATS_FILE" ]]; then
        cat "$CACHE_STATS_FILE"
    else
        echo '{"error": "Cache statistics not available"}'
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Enable/disable cache
cache_enable() {
    CACHE_ENABLED="true"
    log_info "Cache enabled"
}

cache_disable() {
    CACHE_ENABLED="false"
    log_info "Cache disabled"
}

# Check cache health
cache_health() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        echo "disabled"
        return 0
    fi
    
    if [[ ! -d "$CACHE_DIR" ]]; then
        echo "unhealthy: cache directory missing"
        return 1
    fi
    
    if [[ ! -w "$CACHE_DIR" ]]; then
        echo "unhealthy: cache directory not writable"
        return 1
    fi
    
    echo "healthy"
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if not already done
if [[ "${CACHE_INITIALIZED:-}" != "true" ]]; then
    init_cache
    export CACHE_INITIALIZED=true
fi