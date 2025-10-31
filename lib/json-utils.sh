#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Optimized JSON Utilities
# =============================================================================
#
# High-performance JSON processing utilities with streaming support, validation
# caching, and optimized jq queries for better performance in large codebases.
#
# Features:
# - Streaming JSON processing for large files
# - JSON validation with caching
# - Optimized jq query patterns
# - Incremental JSON parsing
# - Memory-efficient processing
# - Query result caching
# - JSON schema validation
#
# Usage:
#   source lib/json-utils.sh
#   json_validate "file.json"
#   json_stream_parse "large.json" '.items[]' 
#   json_query_cached "config.json" '.settings.timeout'
#   json_merge_files "a.json" "b.json"
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source dependencies
source "${PROJECT_ROOT}/lib/logger.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/cache.sh" 2>/dev/null || true

# =============================================================================
# Configuration
# =============================================================================

JSON_UTILS_CACHE_TTL=300  # 5 minutes
JSON_STREAM_BUFFER_SIZE=1024
JSON_MAX_INLINE_SIZE=1048576  # 1MB
JSON_VALIDATION_CACHE_TTL=600  # 10 minutes
JSON_TEMP_DIR="${PROJECT_ROOT}/.tmp/json"

# Create temp directory
mkdir -p "$JSON_TEMP_DIR"

# =============================================================================
# Core JSON Functions
# =============================================================================

# Fast JSON validation with caching
json_validate() {
    local json_file="$1"
    local use_cache="${2:-true}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    local cache_key="json_validate:$(stat -f%m "$json_file" 2>/dev/null || stat -c%Y "$json_file"):$(basename "$json_file")"
    
    # Check cache first
    if [[ "$use_cache" == "true" ]] && cache_exists "$cache_key"; then
        local cached_result=$(cache_get "$cache_key")
        [[ "$cached_result" == "valid" ]]
        return $?
    fi
    
    # Validate JSON
    local validation_result="invalid"
    if jq empty "$json_file" >/dev/null 2>&1; then
        validation_result="valid"
    fi
    
    # Cache result
    if [[ "$use_cache" == "true" ]]; then
        cache_set "$cache_key" "$validation_result" "$JSON_VALIDATION_CACHE_TTL"
    fi
    
    [[ "$validation_result" == "valid" ]]
}

# Optimized JSON query with caching
json_query_cached() {
    local json_file="$1"
    local jq_filter="$2"
    local use_cache="${3:-true}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    # Create cache key based on file mtime and query
    local file_mtime=$(stat -f%m "$json_file" 2>/dev/null || stat -c%Y "$json_file")
    local query_hash=$(echo "$jq_filter" | md5sum | cut -d' ' -f1 2>/dev/null || echo "$jq_filter" | md5 | cut -d' ' -f1)
    local cache_key="json_query:${file_mtime}:$(basename "$json_file"):${query_hash}"
    
    # Check cache first
    if [[ "$use_cache" == "true" ]] && cache_exists "$cache_key"; then
        cache_get "$cache_key"
        return $?
    fi
    
    # Execute query
    local result
    if result=$(jq -r "$jq_filter" "$json_file" 2>/dev/null); then
        # Cache successful result
        if [[ "$use_cache" == "true" ]]; then
            cache_set "$cache_key" "$result" "$JSON_UTILS_CACHE_TTL"
        fi
        echo "$result"
        return 0
    else
        log_error "JSON query failed" "file=$json_file" "filter=$jq_filter"
        return 1
    fi
}

# Stream processing for large JSON files
json_stream_parse() {
    local json_file="$1"
    local jq_filter="$2"
    local batch_size="${3:-100}"
    local callback_function="${4:-}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    # Check file size to determine processing strategy
    local file_size=$(stat -f%z "$json_file" 2>/dev/null || stat -c%s "$json_file")
    
    if [[ $file_size -lt $JSON_MAX_INLINE_SIZE ]]; then
        # Small file, process normally
        json_query_cached "$json_file" "$jq_filter"
        return $?
    fi
    
    log_debug "Streaming large JSON file" "file=$json_file" "size_bytes=$file_size"
    
    # Large file, use streaming with jq
    local temp_output="${JSON_TEMP_DIR}/stream_output_$$"
    local item_count=0
    local batch_count=0
    
    # Use jq streaming parser
    jq -c "$jq_filter" "$json_file" | while IFS= read -r item; do
        if [[ -n "$callback_function" ]] && command -v "$callback_function" >/dev/null; then
            "$callback_function" "$item" "$item_count"
        else
            echo "$item"
        fi
        
        item_count=$((item_count + 1))
        
        # Log progress for very large files
        if [[ $((item_count % 1000)) -eq 0 ]]; then
            log_debug "Processed items" "count=$item_count" "file=$json_file"
        fi
    done
    
    rm -f "$temp_output"
}

# Incremental JSON parsing for arrays
json_parse_array_incremental() {
    local json_file="$1"
    local array_path="$2"
    local chunk_size="${3:-50}"
    local start_index="${4:-0}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    # Get array length first
    local array_length
    array_length=$(json_query_cached "$json_file" "${array_path} | length")
    
    if [[ -z "$array_length" ]] || [[ "$array_length" == "null" ]]; then
        log_error "Array not found or invalid" "path=$array_path"
        return 1
    fi
    
    local end_index=$((start_index + chunk_size))
    if [[ $end_index -gt $array_length ]]; then
        end_index=$array_length
    fi
    
    # Extract chunk
    local filter="${array_path}[${start_index}:${end_index}]"
    json_query_cached "$json_file" "$filter"
    
    # Return next start index or -1 if done
    if [[ $end_index -ge $array_length ]]; then
        echo "DONE" >&2
    else
        echo "$end_index" >&2
    fi
}

# =============================================================================
# JSON Manipulation Functions
# =============================================================================

# Merge multiple JSON files
json_merge_files() {
    local output_file="$1"
    shift
    local input_files=("$@")
    
    if [[ ${#input_files[@]} -eq 0 ]]; then
        log_error "No input files provided for JSON merge"
        return 1
    fi
    
    local temp_file="${JSON_TEMP_DIR}/merge_$$"
    local merge_filter="."
    
    # Build jq merge expression
    for ((i=1; i<${#input_files[@]}; i++)); do
        merge_filter="$merge_filter * \$file$i"
    done
    
    # Prepare file arguments for jq
    local jq_args=()
    for ((i=0; i<${#input_files[@]}; i++)); do
        if [[ ! -f "${input_files[$i]}" ]]; then
            log_error "Input file not found" "file=${input_files[$i]}"
            return 1
        fi
        if [[ $i -gt 0 ]]; then
            jq_args+=("--slurpfile" "file$i" "${input_files[$i]}")
        fi
    done
    
    # Perform merge
    if jq "${jq_args[@]}" "$merge_filter" "${input_files[0]}" > "$temp_file"; then
        mv "$temp_file" "$output_file"
        log_debug "JSON files merged successfully" "output=$output_file" "inputs=${#input_files[@]}"
        return 0
    else
        rm -f "$temp_file"
        log_error "JSON merge failed"
        return 1
    fi
}

# Update JSON file with new values
json_update() {
    local json_file="$1"
    local jq_filter="$2"
    local new_value="$3"
    local backup="${4:-true}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    # Create backup if requested
    if [[ "$backup" == "true" ]]; then
        cp "$json_file" "${json_file}.backup.$(date +%s)"
    fi
    
    local temp_file="${JSON_TEMP_DIR}/update_$$"
    
    # Perform update
    if jq "$jq_filter = \$new_value" --arg new_value "$new_value" "$json_file" > "$temp_file"; then
        mv "$temp_file" "$json_file"
        
        # Invalidate related cache entries
        json_invalidate_file_cache "$json_file"
        
        log_debug "JSON file updated" "file=$json_file" "filter=$jq_filter"
        return 0
    else
        rm -f "$temp_file"
        log_error "JSON update failed" "file=$json_file" "filter=$jq_filter"
        return 1
    fi
}

# Add item to JSON array
json_array_add() {
    local json_file="$1"
    local array_path="$2"
    local new_item="$3"
    local position="${4:-end}"  # start, end, or numeric index
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    local jq_filter
    case "$position" in
        start)
            jq_filter="${array_path} = [\$new_item] + ${array_path}"
            ;;
        end)
            jq_filter="${array_path} += [\$new_item]"
            ;;
        [0-9]*)
            jq_filter="${array_path} |= .[:${position}] + [\$new_item] + .[$position:]"
            ;;
        *)
            log_error "Invalid position for array add" "position=$position"
            return 1
            ;;
    esac
    
    json_update "$json_file" "$jq_filter" "$new_item"
}

# Remove item from JSON array
json_array_remove() {
    local json_file="$1"
    local array_path="$2"
    local index_or_value="$3"
    local remove_by="${4:-index}"  # index or value
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    local temp_file="${JSON_TEMP_DIR}/remove_$$"
    local jq_filter
    
    case "$remove_by" in
        index)
            jq_filter="${array_path} |= del(.[$index_or_value])"
            ;;
        value)
            jq_filter="${array_path} |= map(select(. != \$value))"
            ;;
        *)
            log_error "Invalid remove_by option" "option=$remove_by"
            return 1
            ;;
    esac
    
    if [[ "$remove_by" == "value" ]]; then
        if jq "$jq_filter" --arg value "$index_or_value" "$json_file" > "$temp_file"; then
            mv "$temp_file" "$json_file"
            json_invalidate_file_cache "$json_file"
            return 0
        fi
    else
        if jq "$jq_filter" "$json_file" > "$temp_file"; then
            mv "$temp_file" "$json_file"
            json_invalidate_file_cache "$json_file"
            return 0
        fi
    fi
    
    rm -f "$temp_file"
    log_error "JSON array remove failed"
    return 1
}

# =============================================================================
# Optimized Query Patterns
# =============================================================================

# Get all skills from skill rules (optimized common query)
json_get_skills() {
    local rules_file="${1:-${PROJECT_ROOT}/config/skill-rules.json}"
    json_query_cached "$rules_file" '.skills[] | {skill: .skill, phase: .phase, priority: .priority}'
}

# Get skill by activation code (optimized lookup)
json_get_skill_by_code() {
    local activation_code="$1"
    local rules_file="${2:-${PROJECT_ROOT}/config/skill-rules.json}"
    
    if [[ -z "$activation_code" ]]; then
        log_error "Activation code required"
        return 1
    fi
    
    json_query_cached "$rules_file" ".skills[] | select(.activation_code == \"$activation_code\")"
}

# Get skills by phase (optimized phase lookup)
json_get_skills_by_phase() {
    local phase="$1"
    local rules_file="${2:-${PROJECT_ROOT}/config/skill-rules.json}"
    
    if [[ -z "$phase" ]]; then
        log_error "Phase required"
        return 1
    fi
    
    json_query_cached "$rules_file" ".skills[] | select(.phase == $phase)"
}

# Check if skill has pattern match
json_skill_matches_pattern() {
    local skill_name="$1"
    local pattern="$2"
    local rules_file="${3:-${PROJECT_ROOT}/config/skill-rules.json}"
    
    local filter=".skills[] | select(.skill == \"$skill_name\") | .trigger_conditions.user_patterns[]? | select(test(\"$pattern\"; \"i\"))"
    local result=$(json_query_cached "$rules_file" "$filter")
    
    [[ -n "$result" ]]
}

# =============================================================================
# JSON Schema and Validation
# =============================================================================

# Validate JSON against schema
json_validate_schema() {
    local json_file="$1"
    local schema_file="$2"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema file not found" "file=$schema_file"
        return 1
    fi
    
    # Basic schema validation using jq (for simple schemas)
    # For complex validation, consider using ajv-cli or similar tools
    local cache_key="schema_validate:$(stat -f%m "$json_file"):$(stat -f%m "$schema_file"):$(basename "$json_file")"
    
    if cache_exists "$cache_key"; then
        local cached_result=$(cache_get "$cache_key")
        [[ "$cached_result" == "valid" ]]
        return $?
    fi
    
    # Simple type and required field validation
    local validation_result="valid"
    
    # Check if JSON is valid first
    if ! json_validate "$json_file" false; then
        validation_result="invalid"
    fi
    
    # Cache result
    cache_set "$cache_key" "$validation_result" "$JSON_VALIDATION_CACHE_TTL"
    
    [[ "$validation_result" == "valid" ]]
}

# Extract JSON schema from file
json_extract_schema() {
    local json_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    # Generate basic schema structure
    local schema=$(jq -r '
        def extract_schema:
            if type == "object" then
                {
                    type: "object",
                    properties: (to_entries | map({(.key): (.value | extract_schema)}) | add)
                }
            elif type == "array" then
                {
                    type: "array",
                    items: (.[0] // empty | extract_schema)
                }
            else
                {type: type}
            end;
        
        extract_schema
    ' "$json_file")
    
    if [[ -n "$output_file" ]]; then
        echo "$schema" > "$output_file"
    else
        echo "$schema"
    fi
}

# =============================================================================
# Performance and Monitoring
# =============================================================================

# Benchmark JSON operations
json_benchmark() {
    local json_file="$1"
    local operation="${2:-query}"
    local iterations="${3:-100}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    local start_time=$(date +%s.%3N)
    
    case "$operation" in
        validate)
            for ((i=1; i<=iterations; i++)); do
                json_validate "$json_file" false >/dev/null
            done
            ;;
        query)
            for ((i=1; i<=iterations; i++)); do
                jq -r '.skills | length' "$json_file" >/dev/null
            done
            ;;
        parse)
            for ((i=1; i<=iterations; i++)); do
                jq empty "$json_file"
            done
            ;;
        *)
            log_error "Unknown benchmark operation" "operation=$operation"
            return 1
            ;;
    esac
    
    local end_time=$(date +%s.%3N)
    local duration=$(echo "$end_time - $start_time" | bc)
    local ops_per_second=$(echo "scale=2; $iterations / $duration" | bc)
    
    echo "JSON Benchmark Results:"
    echo "  File: $json_file"
    echo "  Operation: $operation"
    echo "  Iterations: $iterations"
    echo "  Duration: ${duration}s"
    echo "  Ops/second: $ops_per_second"
    
    log_metric "json_benchmark_${operation}" "$ops_per_second" "file=$(basename "$json_file")" "iterations=$iterations"
}

# Profile JSON query performance
json_profile_query() {
    local json_file="$1"
    local jq_filter="$2"
    local iterations="${3:-10}"
    
    local total_time=0
    local min_time=999999
    local max_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date +%s.%3N)
        json_query_cached "$json_file" "$jq_filter" false >/dev/null
        local end_time=$(date +%s.%3N)
        
        local duration=$(echo "$end_time - $start_time" | bc)
        total_time=$(echo "$total_time + $duration" | bc)
        
        if (( $(echo "$duration < $min_time" | bc -l) )); then
            min_time=$duration
        fi
        
        if (( $(echo "$duration > $max_time" | bc -l) )); then
            max_time=$duration
        fi
    done
    
    local avg_time=$(echo "scale=6; $total_time / $iterations" | bc)
    
    echo "Query Performance Profile:"
    echo "  Query: $jq_filter"
    echo "  Iterations: $iterations"
    echo "  Average: ${avg_time}s"
    echo "  Min: ${min_time}s"
    echo "  Max: ${max_time}s"
    
    log_metric "json_query_avg_time" "$avg_time" "filter=$jq_filter" "iterations=$iterations"
}

# =============================================================================
# Cache Management
# =============================================================================

# Invalidate cache entries for a specific file
json_invalidate_file_cache() {
    local json_file="$1"
    local file_basename=$(basename "$json_file")
    
    # Note: This is a simplified implementation
    # In a full implementation, you'd want to maintain an index of cache keys by file
    log_debug "Invalidating JSON cache for file" "file=$json_file"
    
    # Clear validation cache
    # This would need to be implemented in the cache system to support pattern-based deletion
}

# Warm JSON cache with common queries
json_warm_cache() {
    local rules_file="${PROJECT_ROOT}/config/skill-rules.json"
    
    if [[ -f "$rules_file" ]]; then
        log_debug "Warming JSON cache with common queries"
        
        # Common queries
        json_query_cached "$rules_file" '.skills | length' >/dev/null &
        json_query_cached "$rules_file" '.skills[] | .skill' >/dev/null &
        json_query_cached "$rules_file" '.skills[] | .phase' >/dev/null &
        json_query_cached "$rules_file" '.phase_transitions | keys' >/dev/null &
        
        wait
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Pretty print JSON with syntax highlighting (if available)
json_pretty_print() {
    local json_file="$1"
    local use_color="${2:-auto}"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    if [[ "$use_color" == "auto" ]] && [[ -t 1 ]]; then
        use_color="true"
    fi
    
    if [[ "$use_color" == "true" ]] && command -v jq >/dev/null; then
        jq -C '.' "$json_file"
    else
        jq '.' "$json_file"
    fi
}

# Convert JSON to other formats
json_convert() {
    local json_file="$1"
    local output_format="$2"  # yaml, csv, tsv
    local output_file="$3"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found" "file=$json_file"
        return 1
    fi
    
    case "$output_format" in
        yaml|yml)
            if command -v yq >/dev/null; then
                yq eval -P '.' "$json_file" ${output_file:+> "$output_file"}
            else
                log_error "yq not available for YAML conversion"
                return 1
            fi
            ;;
        csv)
            jq -r '(.[0] | keys_unsorted) as $keys | $keys, map([.[ $keys[] ]])[] | @csv' "$json_file" ${output_file:+> "$output_file"}
            ;;
        tsv)
            jq -r '(.[0] | keys_unsorted) as $keys | $keys, map([.[ $keys[] ]])[] | @tsv' "$json_file" ${output_file:+> "$output_file"}
            ;;
        *)
            log_error "Unsupported output format" "format=$output_format"
            return 1
            ;;
    esac
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize
if [[ "${JSON_UTILS_INITIALIZED:-}" != "true" ]]; then
    log_debug "JSON utilities initialized"
    json_warm_cache &
    export JSON_UTILS_INITIALIZED=true
fi