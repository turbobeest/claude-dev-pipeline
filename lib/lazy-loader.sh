#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Lazy Loading System
# =============================================================================
#
# Intelligent lazy loading system for skills, configuration, and pipeline
# components to improve startup performance and reduce memory usage.
#
# Features:
# - On-demand skill loading
# - Deferred hook initialization
# - Progressive configuration loading
# - Dependency resolution
# - Load time optimization
# - Memory usage tracking
# - Preloading strategies
# - Intelligent caching
#
# Usage:
#   source lib/lazy-loader.sh
#   lazy_load_skill "skill-name"
#   lazy_load_config "config-section"
#   lazy_init_hooks
#   preload_critical_components
#
# =============================================================================

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source dependencies
source "${PROJECT_ROOT}/lib/logger.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/cache.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/profiler.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/json-utils.sh" 2>/dev/null || true

# =============================================================================
# Configuration
# =============================================================================

LAZY_LOADING_ENABLED="${LAZY_LOADING_ENABLED:-true}"
LAZY_LOAD_CACHE_TTL=600  # 10 minutes
LAZY_LOAD_PRELOAD_CRITICAL="${LAZY_LOAD_PRELOAD_CRITICAL:-true}"
LAZY_LOAD_MAX_PARALLEL=5
LAZY_LOAD_TIMEOUT=30

# Directories
SKILLS_DIR="${PROJECT_ROOT}/skills"
CONFIG_DIR="${PROJECT_ROOT}/config"
HOOKS_DIR="${PROJECT_ROOT}/hooks"

# Load state tracking
LOADED_SKILLS=""
LOADED_CONFIGS=""
LOADED_HOOKS=""
LOADING_SKILLS=""  # Currently loading
SKILL_DEPENDENCIES=""

# Component metadata
SKILL_METADATA_PREFIX="SKILL_META_"
CONFIG_METADATA_PREFIX="CONFIG_META_"
HOOK_METADATA_PREFIX="HOOK_META_"

# =============================================================================
# Core Lazy Loading Functions
# =============================================================================

# Lazy load a skill
lazy_load_skill() {
    local skill_name="$1"
    local force_reload="${2:-false}"
    
    if [[ "$LAZY_LOADING_ENABLED" != "true" ]]; then
        # Fallback to eager loading
        load_skill_immediately "$skill_name"
        return $?
    fi
    
    profile_start "lazy_load_skill:$skill_name"
    
    # Check if already loaded
    if [[ "$force_reload" != "true" ]] && is_skill_loaded "$skill_name"; then
        log_debug "Skill already loaded" "skill=$skill_name"
        profile_end "lazy_load_skill:$skill_name" >/dev/null
        return 0
    fi
    
    # Check if currently loading (prevent circular dependencies)
    if [[ "$LOADING_SKILLS" == *"|$skill_name|"* ]]; then
        log_warn "Circular dependency detected" "skill=$skill_name"
        return 1
    fi
    
    # Mark as loading
    LOADING_SKILLS="${LOADING_SKILLS}|${skill_name}|"
    
    log_info "Lazy loading skill" "skill=$skill_name"
    
    # Load skill dependencies first
    if ! load_skill_dependencies "$skill_name"; then
        log_error "Failed to load skill dependencies" "skill=$skill_name"
        LOADING_SKILLS=$(echo "$LOADING_SKILLS" | sed "s/|${skill_name}|//g")
        return 1
    fi
    
    # Load the skill
    if load_skill_implementation "$skill_name"; then
        # Mark as loaded
        LOADED_SKILLS="${LOADED_SKILLS}|${skill_name}|"
        
        # Store metadata
        store_skill_metadata "$skill_name"
        
        log_info "Skill loaded successfully" "skill=$skill_name"
    else
        log_error "Failed to load skill" "skill=$skill_name"
        LOADING_SKILLS=$(echo "$LOADING_SKILLS" | sed "s/|${skill_name}|//g")
        return 1
    fi
    
    # Remove from loading list
    LOADING_SKILLS=$(echo "$LOADING_SKILLS" | sed "s/|${skill_name}|//g")
    
    local duration=$(profile_end "lazy_load_skill:$skill_name")
    log_metric "skill_load_time" "$duration" "skill=$skill_name"
    
    return 0
}

# Lazy load configuration section
lazy_load_config() {
    local config_section="$1"
    local force_reload="${2:-false}"
    
    if [[ "$LAZY_LOADING_ENABLED" != "true" ]]; then
        load_config_immediately "$config_section"
        return $?
    fi
    
    profile_start "lazy_load_config:$config_section"
    
    # Check if already loaded
    if [[ "$force_reload" != "true" ]] && is_config_loaded "$config_section"; then
        log_debug "Config already loaded" "section=$config_section"
        profile_end "lazy_load_config:$config_section" >/dev/null
        return 0
    fi
    
    log_debug "Lazy loading config section" "section=$config_section"
    
    # Load configuration
    if load_config_implementation "$config_section"; then
        LOADED_CONFIGS="${LOADED_CONFIGS}|${config_section}|"
        store_config_metadata "$config_section"
        log_debug "Config section loaded" "section=$config_section"
    else
        log_error "Failed to load config section" "section=$config_section"
        return 1
    fi
    
    local duration=$(profile_end "lazy_load_config:$config_section")
    log_metric "config_load_time" "$duration" "section=$config_section"
    
    return 0
}

# Lazy initialize hooks
lazy_init_hooks() {
    local hook_type="${1:-all}"
    local force_reload="${2:-false}"
    
    if [[ "$LAZY_LOADING_ENABLED" != "true" ]]; then
        init_hooks_immediately "$hook_type"
        return $?
    fi
    
    profile_start "lazy_init_hooks:$hook_type"
    
    log_debug "Lazy initializing hooks" "type=$hook_type"
    
    case "$hook_type" in
        all)
            lazy_init_specific_hooks "pre-implementation-validator" \
                                   "post-tool-use-tracker" \
                                   "skill-activation-prompt" \
                                   "worktree-enforcer"
            ;;
        critical)
            lazy_init_specific_hooks "skill-activation-prompt" \
                                   "worktree-enforcer"
            ;;
        *)
            lazy_init_specific_hooks "$hook_type"
            ;;
    esac
    
    local duration=$(profile_end "lazy_init_hooks:$hook_type")
    log_metric "hooks_init_time" "$duration" "type=$hook_type"
}

# Initialize specific hooks
lazy_init_specific_hooks() {
    local hooks=("$@")
    
    for hook in "${hooks[@]}"; do
        if [[ "$LOADED_HOOKS" != *"|$hook|"* ]]; then
            if init_hook_implementation "$hook"; then
                LOADED_HOOKS="${LOADED_HOOKS}|${hook}|"
                store_hook_metadata "$hook"
                log_debug "Hook initialized" "hook=$hook"
            else
                log_warn "Failed to initialize hook" "hook=$hook"
            fi
        fi
    done
}

# =============================================================================
# Skill Loading Implementation
# =============================================================================

# Load skill dependencies
load_skill_dependencies() {
    local skill_name="$1"
    
    # Get skill information from rules
    local skill_rules="${CONFIG_DIR}/skill-rules.json"
    if [[ ! -f "$skill_rules" ]]; then
        log_debug "Skill rules not found, skipping dependencies" "skill=$skill_name"
        return 0
    fi
    
    # Extract dependencies (this is a simplified implementation)
    local dependencies=$(json_query_cached "$skill_rules" \
        ".skills[] | select(.skill == \"$skill_name\") | .dependencies[]?" 2>/dev/null || echo "")
    
    if [[ -n "$dependencies" ]]; then
        log_debug "Loading skill dependencies" "skill=$skill_name" "dependencies=$dependencies"
        
        # Load each dependency
        while IFS= read -r dep; do
            if [[ -n "$dep" ]] && [[ "$dep" != "null" ]]; then
                if ! lazy_load_skill "$dep"; then
                    log_error "Failed to load skill dependency" "skill=$skill_name" "dependency=$dep"
                    return 1
                fi
            fi
        done <<< "$dependencies"
    fi
    
    return 0
}

# Load skill implementation
load_skill_implementation() {
    local skill_name="$1"
    
    local skill_dir="${SKILLS_DIR}/${skill_name}"
    local skill_file="${skill_dir}/SKILL.md"
    
    if [[ ! -d "$skill_dir" ]]; then
        log_error "Skill directory not found" "skill=$skill_name" "dir=$skill_dir"
        return 1
    fi
    
    if [[ ! -f "$skill_file" ]]; then
        log_error "Skill file not found" "skill=$skill_name" "file=$skill_file"
        return 1
    fi
    
    # Cache skill content
    local cache_key="skill_content:$skill_name"
    if ! cache_exists "$cache_key"; then
        local skill_content=$(cat "$skill_file")
        cache_set "$cache_key" "$skill_content" "$LAZY_LOAD_CACHE_TTL"
    fi
    
    # Load skill-specific configuration if it exists
    local skill_config="${skill_dir}/config.json"
    if [[ -f "$skill_config" ]]; then
        lazy_load_config "skill:$skill_name"
    fi
    
    # Initialize skill environment
    init_skill_environment "$skill_name"
    
    return 0
}

# Initialize skill environment
init_skill_environment() {
    local skill_name="$1"
    
    # Set skill-specific environment variables
    export CURRENT_SKILL="$skill_name"
    export SKILL_DIR="${SKILLS_DIR}/${skill_name}"
    
    # Load skill-specific functions or scripts if they exist
    local skill_script="${SKILLS_DIR}/${skill_name}/functions.sh"
    if [[ -f "$skill_script" ]]; then
        source "$skill_script"
        log_debug "Skill script loaded" "skill=$skill_name" "script=$skill_script"
    fi
    
    log_debug "Skill environment initialized" "skill=$skill_name"
}

# =============================================================================
# Configuration Loading Implementation
# =============================================================================

# Load configuration implementation
load_config_implementation() {
    local config_section="$1"
    
    case "$config_section" in
        skill-rules)
            load_skill_rules_config
            ;;
        settings)
            load_settings_config
            ;;
        workflow-state)
            load_workflow_state_config
            ;;
        skill:*)
            local skill_name="${config_section#skill:}"
            load_skill_specific_config "$skill_name"
            ;;
        *)
            load_generic_config "$config_section"
            ;;
    esac
}

# Load skill rules configuration
load_skill_rules_config() {
    local rules_file="${CONFIG_DIR}/skill-rules.json"
    
    if [[ -f "$rules_file" ]]; then
        # Cache the rules
        local cache_key="config:skill-rules"
        if ! cache_exists "$cache_key"; then
            local rules_content=$(cat "$rules_file")
            cache_set "$cache_key" "$rules_content" "$LAZY_LOAD_CACHE_TTL"
        fi
        
        # Validate JSON
        if ! json_validate "$rules_file"; then
            log_error "Invalid skill rules JSON" "file=$rules_file"
            return 1
        fi
        
        log_debug "Skill rules configuration loaded"
        return 0
    else
        log_warn "Skill rules file not found" "file=$rules_file"
        return 1
    fi
}

# Load settings configuration
load_settings_config() {
    local settings_file="${CONFIG_DIR}/settings.json"
    
    if [[ -f "$settings_file" ]]; then
        local cache_key="config:settings"
        if ! cache_exists "$cache_key"; then
            local settings_content=$(cat "$settings_file")
            cache_set "$cache_key" "$settings_content" "$LAZY_LOAD_CACHE_TTL"
        fi
        
        log_debug "Settings configuration loaded"
        return 0
    else
        log_debug "Settings file not found, using defaults" "file=$settings_file"
        return 0
    fi
}

# Load workflow state configuration
load_workflow_state_config() {
    local state_file="${CONFIG_DIR}/workflow-state.json"
    local template_file="${CONFIG_DIR}/workflow-state.template.json"
    
    if [[ -f "$state_file" ]]; then
        local cache_key="config:workflow-state"
        if ! cache_exists "$cache_key"; then
            local state_content=$(cat "$state_file")
            cache_set "$cache_key" "$state_content" "$LAZY_LOAD_CACHE_TTL"
        fi
    elif [[ -f "$template_file" ]]; then
        # Create state file from template
        cp "$template_file" "$state_file"
        log_debug "Workflow state initialized from template"
    else
        log_warn "No workflow state file or template found"
        return 1
    fi
    
    log_debug "Workflow state configuration loaded"
    return 0
}

# Load skill-specific configuration
load_skill_specific_config() {
    local skill_name="$1"
    local skill_config="${SKILLS_DIR}/${skill_name}/config.json"
    
    if [[ -f "$skill_config" ]]; then
        local cache_key="config:skill:$skill_name"
        if ! cache_exists "$cache_key"; then
            local config_content=$(cat "$skill_config")
            cache_set "$cache_key" "$config_content" "$LAZY_LOAD_CACHE_TTL"
        fi
        
        log_debug "Skill-specific config loaded" "skill=$skill_name"
        return 0
    else
        log_debug "No skill-specific config found" "skill=$skill_name"
        return 0
    fi
}

# Load generic configuration
load_generic_config() {
    local config_section="$1"
    local config_file="${CONFIG_DIR}/${config_section}.json"
    
    if [[ -f "$config_file" ]]; then
        local cache_key="config:$config_section"
        if ! cache_exists "$cache_key"; then
            local config_content=$(cat "$config_file")
            cache_set "$cache_key" "$config_content" "$LAZY_LOAD_CACHE_TTL"
        fi
        
        log_debug "Generic config loaded" "section=$config_section"
        return 0
    else
        log_debug "Config file not found" "section=$config_section" "file=$config_file"
        return 1
    fi
}

# =============================================================================
# Hook Loading Implementation
# =============================================================================

# Initialize hook implementation
init_hook_implementation() {
    local hook_name="$1"
    local hook_file="${HOOKS_DIR}/${hook_name}.sh"
    
    if [[ ! -f "$hook_file" ]]; then
        log_error "Hook file not found" "hook=$hook_name" "file=$hook_file"
        return 1
    fi
    
    # Make hook executable
    chmod +x "$hook_file"
    
    # Cache hook content for faster subsequent access
    local cache_key="hook_content:$hook_name"
    if ! cache_exists "$cache_key"; then
        local hook_content=$(cat "$hook_file")
        cache_set "$cache_key" "$hook_content" "$LAZY_LOAD_CACHE_TTL"
    fi
    
    # Initialize hook environment
    export HOOK_NAME="$hook_name"
    export HOOK_FILE="$hook_file"
    
    log_debug "Hook initialized" "hook=$hook_name"
    return 0
}

# =============================================================================
# Status Checking Functions
# =============================================================================

# Check if skill is loaded
is_skill_loaded() {
    local skill_name="$1"
    [[ "$LOADED_SKILLS" == *"|$skill_name|"* ]]
}

# Check if config is loaded
is_config_loaded() {
    local config_section="$1"
    [[ "$LOADED_CONFIGS" == *"|$config_section|"* ]]
}

# Check if hook is loaded
is_hook_loaded() {
    local hook_name="$1"
    [[ "$LOADED_HOOKS" == *"|$hook_name|"* ]]
}

# =============================================================================
# Metadata Storage
# =============================================================================

# Store skill metadata
store_skill_metadata() {
    local skill_name="$1"
    local timestamp=$(date +%s)
    local memory_usage=$(get_memory_usage 2>/dev/null || echo "0")
    
    eval "${SKILL_METADATA_PREFIX}${skill_name}_loaded_at=\"$timestamp\""
    eval "${SKILL_METADATA_PREFIX}${skill_name}_memory_mb=\"$memory_usage\""
    
    log_metric "skill_loaded" "1" \
        "skill=$skill_name" \
        "memory_mb=$memory_usage" \
        "timestamp=$timestamp"
}

# Store config metadata
store_config_metadata() {
    local config_section="$1"
    local timestamp=$(date +%s)
    
    eval "${CONFIG_METADATA_PREFIX}${config_section}_loaded_at=\"$timestamp\""
    
    log_metric "config_loaded" "1" \
        "section=$config_section" \
        "timestamp=$timestamp"
}

# Store hook metadata
store_hook_metadata() {
    local hook_name="$1"
    local timestamp=$(date +%s)
    
    eval "${HOOK_METADATA_PREFIX}${hook_name}_loaded_at=\"$timestamp\""
    
    log_metric "hook_loaded" "1" \
        "hook=$hook_name" \
        "timestamp=$timestamp"
}

# =============================================================================
# Preloading Strategies
# =============================================================================

# Preload critical components
preload_critical_components() {
    if [[ "$LAZY_LOAD_PRELOAD_CRITICAL" != "true" ]]; then
        return 0
    fi
    
    log_info "Preloading critical components"
    profile_start "preload_critical"
    
    # Preload critical configuration
    lazy_load_config "skill-rules" &
    lazy_load_config "settings" &
    
    # Preload critical hooks
    lazy_init_hooks "critical" &
    
    # Wait for critical preloads
    wait
    
    # Preload frequently used skills based on usage patterns
    preload_frequent_skills &
    
    local duration=$(profile_end "preload_critical")
    log_info "Critical components preloaded" "duration_ms=$duration"
}

# Preload frequently used skills
preload_frequent_skills() {
    local frequent_skills=(
        "pipeline-orchestration"
        "prd-to-tasks"
        "spec-gen"
    )
    
    for skill in "${frequent_skills[@]}"; do
        lazy_load_skill "$skill" &
        
        # Limit parallel preloads
        local job_count=$(jobs -r | wc -l)
        if [[ $job_count -ge $LAZY_LOAD_MAX_PARALLEL ]]; then
            wait -n  # Wait for any job to complete
        fi
    done
    
    wait  # Wait for all remaining preloads
    log_debug "Frequent skills preloaded" "count=${#frequent_skills[@]}"
}

# Progressive loading based on usage patterns
progressive_load() {
    local priority="${1:-normal}"
    
    case "$priority" in
        high)
            # Load immediately
            preload_critical_components
            ;;
        normal)
            # Load in background
            preload_critical_components &
            ;;
        low)
            # Defer loading
            (sleep 5; preload_critical_components) &
            ;;
    esac
}

# =============================================================================
# Fallback Functions (Eager Loading)
# =============================================================================

# Load skill immediately (fallback)
load_skill_immediately() {
    local skill_name="$1"
    
    log_debug "Loading skill immediately (fallback)" "skill=$skill_name"
    load_skill_implementation "$skill_name"
}

# Load config immediately (fallback)
load_config_immediately() {
    local config_section="$1"
    
    log_debug "Loading config immediately (fallback)" "section=$config_section"
    load_config_implementation "$config_section"
}

# Initialize hooks immediately (fallback)
init_hooks_immediately() {
    local hook_type="$1"
    
    log_debug "Initializing hooks immediately (fallback)" "type=$hook_type"
    
    for hook_file in "${HOOKS_DIR}"/*.sh; do
        if [[ -f "$hook_file" ]]; then
            local hook_name=$(basename "$hook_file" .sh)
            init_hook_implementation "$hook_name"
        fi
    done
}

# =============================================================================
# Performance Monitoring
# =============================================================================

# Get loading statistics
get_loading_stats() {
    local loaded_skills_count=$(echo "$LOADED_SKILLS" | tr -cd '|' | wc -c)
    local loaded_configs_count=$(echo "$LOADED_CONFIGS" | tr -cd '|' | wc -c)
    local loaded_hooks_count=$(echo "$LOADED_HOOKS" | tr -cd '|' | wc -c)
    
    echo "Lazy Loading Statistics:"
    echo "  Enabled: $LAZY_LOADING_ENABLED"
    echo "  Loaded Skills: $loaded_skills_count"
    echo "  Loaded Configs: $loaded_configs_count"
    echo "  Loaded Hooks: $loaded_hooks_count"
    echo "  Preload Critical: $LAZY_LOAD_PRELOAD_CRITICAL"
    echo "  Max Parallel: $LAZY_LOAD_MAX_PARALLEL"
}

# List loaded components
list_loaded_components() {
    echo "=== Loaded Components ==="
    echo ""
    
    echo "Skills:"
    if [[ -n "$LOADED_SKILLS" ]]; then
        echo "$LOADED_SKILLS" | tr '|' '\n' | grep -v '^$' | sed 's/^/  - /'
    else
        echo "  (none)"
    fi
    echo ""
    
    echo "Configurations:"
    if [[ -n "$LOADED_CONFIGS" ]]; then
        echo "$LOADED_CONFIGS" | tr '|' '\n' | grep -v '^$' | sed 's/^/  - /'
    else
        echo "  (none)"
    fi
    echo ""
    
    echo "Hooks:"
    if [[ -n "$LOADED_HOOKS" ]]; then
        echo "$LOADED_HOOKS" | tr '|' '\n' | grep -v '^$' | sed 's/^/  - /'
    else
        echo "  (none)"
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Enable/disable lazy loading
enable_lazy_loading() {
    LAZY_LOADING_ENABLED="true"
    log_info "Lazy loading enabled"
}

disable_lazy_loading() {
    LAZY_LOADING_ENABLED="false"
    log_info "Lazy loading disabled"
}

# Clear loaded components
clear_loaded_components() {
    LOADED_SKILLS=""
    LOADED_CONFIGS=""
    LOADED_HOOKS=""
    log_info "Loaded components cleared"
}

# Reload component
reload_component() {
    local component_type="$1"
    local component_name="$2"
    
    case "$component_type" in
        skill)
            lazy_load_skill "$component_name" true
            ;;
        config)
            lazy_load_config "$component_name" true
            ;;
        hook)
            # Remove from loaded list and reload
            LOADED_HOOKS=$(echo "$LOADED_HOOKS" | sed "s/|${component_name}|//g")
            init_hook_implementation "$component_name"
            LOADED_HOOKS="${LOADED_HOOKS}|${component_name}|"
            ;;
        *)
            log_error "Unknown component type" "type=$component_type"
            return 1
            ;;
    esac
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize lazy loading system
if [[ "${LAZY_LOADER_INITIALIZED:-}" != "true" ]]; then
    log_debug "Lazy loading system initialized"
    
    # Start progressive loading if enabled
    if [[ "$LAZY_LOADING_ENABLED" == "true" ]]; then
        progressive_load "normal"
    fi
    
    export LAZY_LOADER_INITIALIZED=true
fi