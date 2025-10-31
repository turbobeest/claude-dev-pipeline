#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Comprehensive Setup Script
# =============================================================================
# 
# Interactive setup wizard that validates dependencies, configures environment,
# and prepares the Claude Dev Pipeline for use.
#
# Features:
# - Dependency validation (TaskMaster, OpenSpec)
# - Interactive configuration wizard
# - Environment setup and validation
# - Comprehensive error handling with rollback
# - Progress indicators and colored output
#
# Usage:
#   ./setup.sh [OPTIONS]
#
# Options:
#   --non-interactive     Skip interactive prompts (use defaults)
#   --force              Force setup even if dependencies are missing
#   --skip-validation    Skip final validation steps
#   --rollback           Rollback previous setup
#   --dry-run            Show what would be done without making changes
#   -h, --help           Show this help message
#
# =============================================================================

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Load logging and metrics libraries
source "$PROJECT_ROOT/lib/logger.sh" 2>/dev/null || {
    echo "Warning: Advanced logging not available, using basic logging" >&2
    # Basic fallback logging functions
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_debug() { echo "[DEBUG] $*"; }
    start_timer() { :; }
    stop_timer() { :; }
}

source "$PROJECT_ROOT/lib/metrics.sh" 2>/dev/null || {
    echo "Warning: Metrics system not available" >&2
    # Basic fallback functions
    metrics_track_phase_start() { :; }
    metrics_track_phase_end() { :; }
    metrics_track_task_outcome() { :; }
}

# Set logging context
set_log_context --phase "setup" --task "initialization"

# =============================================================================
# Configuration and Constants
# =============================================================================

# Script version
VERSION="1.0.0"

# Default values
INTERACTIVE=true
FORCE_SETUP=false
SKIP_VALIDATION=false
DRY_RUN=false
ROLLBACK=false

# Required dependencies
REQUIRED_DEPS=("git" "curl" "jq" "bash")
PIPELINE_DEPS=("task-master" "openspec")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Progress tracking
SETUP_STEPS=(
    "Dependency Validation"
    "Environment Configuration"
    "Directory Creation"
    "Tool Installation"
    "Configuration Validation"
    "Final Verification"
)
CURRENT_STEP=0
TOTAL_STEPS=${#SETUP_STEPS[@]}

# Backup directory for rollback
BACKUP_DIR="$PROJECT_ROOT/.setup-backup-$(date +%Y%m%d-%H%M%S)"

# =============================================================================
# Utility Functions
# =============================================================================

# Enhanced logging functions that use our logger but maintain color output
log_success() {
    log_info "$1"
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_step() {
    log_info "Step $1/$2: $3"
    echo -e "${PURPLE}[STEP $1/$2]${NC} $3"
}

# Override log_warning to use our logger
log_warning() {
    log_warn "$@"
}

log_progress() {
    local current=$1
    local total=$2
    local step_name=$3
    local percent=$((current * 100 / total))
    
    printf "\r${CYAN}Progress: [${NC}"
    for ((i=1; i<=20; i++)); do
        if [ $i -le $((percent / 5)) ]; then
            printf "${GREEN}█${NC}"
        else
            printf "░"
        fi
    done
    printf "${CYAN}] %d%% - %s${NC}" "$percent" "$step_name"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Help function
show_help() {
    cat << 'EOF'
Claude Dev Pipeline Setup Script

This script validates dependencies, configures the environment, and prepares
the Claude Dev Pipeline for use.

USAGE:
    ./setup.sh [OPTIONS]

OPTIONS:
    --non-interactive     Skip interactive prompts (use defaults from .env.template)
    --force              Force setup even if dependencies are missing
    --skip-validation    Skip final validation steps
    --rollback           Rollback previous setup
    --dry-run            Show what would be done without making changes
    -h, --help           Show this help message

DEPENDENCIES:
    Required system tools:
    - git               Version control
    - curl              For downloading resources
    - jq                JSON processing
    - bash              Shell execution

    Required pipeline tools:
    - task-master       Task management (https://github.com/eyaltoledano/claude-task-master)
    - openspec          API specification (https://github.com/Fission-AI/OpenSpec)

EXAMPLES:
    ./setup.sh                           # Interactive setup
    ./setup.sh --non-interactive         # Automated setup with defaults
    ./setup.sh --force --skip-validation # Force setup, skip validation
    ./setup.sh --rollback                # Rollback previous setup

ENVIRONMENT:
    Configuration is stored in .env file (created from .env.template)
    Key variables:
    - GITHUB_ORG: Your GitHub organization/username
    - INSTALL_LOCATION: Where to install (project/global)
    - INSTALL_HOOKS: Whether to install hooks
    - INSTALL_TOOLS: Whether to install external tools

For more information, see docs/SETUP-GUIDE.md
EOF
}

# Command existence check
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Progress step management
next_step() {
    ((CURRENT_STEP++))
    log_progress "$CURRENT_STEP" "$TOTAL_STEPS" "${SETUP_STEPS[$((CURRENT_STEP-1))]}"
}

# Backup function for rollback capability
create_backup() {
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would create backup at $BACKUP_DIR"
        return 0
    fi
    
    log_info "Creating backup for rollback capability..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing files that might be modified
    local files_to_backup=(".env" ".claude" "config" "hooks" "install-pipeline.sh")
    
    for file in "${files_to_backup[@]}"; do
        if [ -e "$PROJECT_ROOT/$file" ]; then
            cp -r "$PROJECT_ROOT/$file" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    done
    
    echo "$PROJECT_ROOT" > "$BACKUP_DIR/original_location.txt"
    log_success "Backup created at $BACKUP_DIR"
}

# Rollback function
perform_rollback() {
    local backup_dirs
    mapfile -t backup_dirs < <(find "$PROJECT_ROOT" -maxdepth 1 -name ".setup-backup-*" -type d | sort -r)
    
    if [ ${#backup_dirs[@]} -eq 0 ]; then
        log_error "No backup directories found for rollback"
        exit 1
    fi
    
    local latest_backup="${backup_dirs[0]}"
    log_info "Rolling back from: $latest_backup"
    
    if [ ! -f "$latest_backup/original_location.txt" ]; then
        log_error "Invalid backup directory (missing original_location.txt)"
        exit 1
    fi
    
    local original_location
    original_location=$(cat "$latest_backup/original_location.txt")
    
    if [ "$original_location" != "$PROJECT_ROOT" ]; then
        log_error "Backup was created for different location: $original_location"
        exit 1
    fi
    
    # Restore files
    local files_to_restore=(".env" ".claude" "config" "hooks" "install-pipeline.sh")
    
    for file in "${files_to_restore[@]}"; do
        if [ -e "$latest_backup/$file" ]; then
            log_info "Restoring $file..."
            rm -rf "$PROJECT_ROOT/$file" 2>/dev/null || true
            cp -r "$latest_backup/$file" "$PROJECT_ROOT/" 2>/dev/null || true
        elif [ -e "$PROJECT_ROOT/$file" ]; then
            log_info "Removing $file (wasn't in backup)..."
            rm -rf "$PROJECT_ROOT/$file"
        fi
    done
    
    log_success "Rollback completed successfully"
    
    # Clean up old backups
    if [ ${#backup_dirs[@]} -gt 5 ]; then
        log_info "Cleaning up old backups (keeping 5 most recent)..."
        for ((i=5; i<${#backup_dirs[@]}; i++)); do
            rm -rf "${backup_dirs[$i]}"
        done
    fi
    
    exit 0
}

# Validate GitHub organization exists
validate_github_org() {
    local org="$1"
    
    if [ -z "$org" ] || [ "$org" = "your-github-username" ]; then
        return 1
    fi
    
    # Basic validation - check if it looks like a valid GitHub username
    if [[ ! "$org" =~ ^[a-zA-Z0-9]([a-zA-Z0-9]|-){0,38}$ ]]; then
        return 1
    fi
    
    # Try to check if organization exists (optional - requires network)
    if command_exists curl; then
        if curl -s --head "https://github.com/$org" | head -n 1 | grep -q "200 OK"; then
            return 0
        fi
    fi
    
    # If we can't verify online, assume it's valid if format is correct
    return 0
}

# Interactive prompt with validation
prompt_with_validation() {
    local prompt="$1"
    local default="$2"
    local validator="$3"
    local error_msg="$4"
    local value
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " value
            value="${value:-$default}"
        else
            read -p "$prompt: " value
        fi
        
        if [ -z "$validator" ] || eval "$validator '$value'"; then
            echo "$value"
            return 0
        else
            log_error "$error_msg"
        fi
    done
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive)
            INTERACTIVE=false
            shift
            ;;
        --force)
            FORCE_SETUP=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Setup Functions
# =============================================================================

# Banner and introduction
show_banner() {
    echo ""
    echo -e "${CYAN}=========================================================================="
    echo -e "              Claude Dev Pipeline - Setup Script v$VERSION"
    echo -e "==========================================================================${NC}"
    echo ""
    echo -e "${BLUE}This script will configure the Claude Dev Pipeline for your environment.${NC}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE: No changes will be made${NC}"
        echo ""
    fi
}

# Step 1: Dependency validation
validate_dependencies() {
    log_step "$((CURRENT_STEP + 1))" "$TOTAL_STEPS" "Validating Dependencies"
    echo ""
    
    local missing_deps=()
    local missing_pipeline_deps=()
    
    # Check system dependencies
    log_info "Checking system dependencies..."
    for dep in "${REQUIRED_DEPS[@]}"; do
        if command_exists "$dep"; then
            log_success "✓ $dep is installed"
        else
            log_error "✗ $dep is missing"
            missing_deps+=("$dep")
        fi
    done
    
    # Check pipeline dependencies
    log_info "Checking pipeline dependencies..."
    for dep in "${PIPELINE_DEPS[@]}"; do
        if command_exists "$dep"; then
            log_success "✓ $dep is installed"
        else
            log_error "✗ $dep is missing"
            missing_pipeline_deps+=("$dep")
        fi
    done
    
    # Handle missing system dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required system dependencies: ${missing_deps[*]}"
        echo ""
        echo -e "${YELLOW}Please install the missing dependencies:${NC}"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "git")
                    echo "  • Git: https://git-scm.com/downloads"
                    ;;
                "curl")
                    echo "  • cURL: Usually pre-installed, check your package manager"
                    ;;
                "jq")
                    echo "  • jq: brew install jq (macOS) or apt-get install jq (Ubuntu)"
                    ;;
                "bash")
                    echo "  • Bash: Usually pre-installed, check version with: bash --version"
                    ;;
            esac
        done
        echo ""
        exit 1
    fi
    
    # Handle missing pipeline dependencies
    if [ ${#missing_pipeline_deps[@]} -gt 0 ]; then
        log_error "Missing required pipeline dependencies: ${missing_pipeline_deps[*]}"
        echo ""
        echo -e "${YELLOW}Please install the missing pipeline tools:${NC}"
        
        for dep in "${missing_pipeline_deps[@]}"; do
            case "$dep" in
                "task-master")
                    echo -e "  ${BOLD}TaskMaster:${NC}"
                    echo "    1. Clone: git clone https://github.com/eyaltoledano/claude-task-master"
                    echo "    2. Install: cd claude-task-master && npm install -g ."
                    echo "    3. Verify: task-master --version"
                    ;;
                "openspec")
                    echo -e "  ${BOLD}OpenSpec:${NC}"
                    echo "    1. Clone: git clone https://github.com/Fission-AI/OpenSpec"
                    echo "    2. Install: cd OpenSpec && npm install -g ."
                    echo "    3. Verify: openspec --version"
                    ;;
            esac
            echo ""
        done
        
        if [ "$FORCE_SETUP" = false ]; then
            echo -e "${RED}Setup cannot continue without these dependencies.${NC}"
            echo -e "${YELLOW}Use --force to continue anyway (not recommended).${NC}"
            exit 1
        else
            log_warning "Continuing with --force flag despite missing dependencies"
        fi
    fi
    
    log_success "Dependency validation completed"
    next_step
}

# Step 2: Environment configuration
configure_environment() {
    log_step "$((CURRENT_STEP + 1))" "$TOTAL_STEPS" "Environment Configuration"
    echo ""
    
    local env_file="$PROJECT_ROOT/.env"
    local template_file="$PROJECT_ROOT/.env.template"
    
    # Check if .env already exists
    if [ -f "$env_file" ]; then
        if [ "$INTERACTIVE" = true ]; then
            echo -e "${YELLOW}Environment file .env already exists.${NC}"
            local overwrite
            overwrite=$(prompt_with_validation "Do you want to reconfigure? (y/N)" "N" "" "")
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                log_info "Using existing .env configuration"
                next_step
                return 0
            fi
        else
            log_info "Using existing .env configuration (non-interactive mode)"
            next_step
            return 0
        fi
    fi
    
    # Ensure template exists
    if [ ! -f "$template_file" ]; then
        log_error "Environment template file not found: $template_file"
        exit 1
    fi
    
    # Copy template to .env
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would copy $template_file to $env_file"
    else
        cp "$template_file" "$env_file"
        log_success "Created .env from template"
    fi
    
    if [ "$INTERACTIVE" = true ]; then
        log_info "Configuring environment variables..."
        echo ""
        
        # GitHub Organization
        local github_org
        github_org=$(prompt_with_validation \
            "GitHub organization/username" \
            "your-github-username" \
            "validate_github_org" \
            "Please enter a valid GitHub username or organization name")
        
        # GitHub Repository
        local github_repo
        github_repo=$(prompt_with_validation \
            "GitHub repository name" \
            "claude-dev-pipeline" \
            "" \
            "")
        
        # Installation location
        echo ""
        echo -e "${BLUE}Installation Location:${NC}"
        echo "  project - Install in current project (.claude directory)"
        echo "  global  - Install globally (~/.claude directory)"
        local install_location
        install_location=$(prompt_with_validation \
            "Installation location (project/global)" \
            "project" \
            "[[ \$1 == 'project' || \$1 == 'global' ]]" \
            "Please enter 'project' or 'global'")
        
        # Install hooks
        local install_hooks
        install_hooks=$(prompt_with_validation \
            "Install automation hooks? (Y/n)" \
            "Y" \
            "" \
            "")
        install_hooks=$([[ "$install_hooks" =~ ^[Nn]$ ]] && echo "false" || echo "true")
        
        # Install tools
        local install_tools
        install_tools=$(prompt_with_validation \
            "Install external tools (TaskMaster, OpenSpec)? (Y/n)" \
            "Y" \
            "" \
            "")
        install_tools=$([[ "$install_tools" =~ ^[Nn]$ ]] && echo "false" || echo "true")
        
        # Update .env file
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would update .env with:"
            echo "  GITHUB_ORG=$github_org"
            echo "  GITHUB_REPO=$github_repo"
            echo "  INSTALL_LOCATION=$install_location"
            echo "  INSTALL_HOOKS=$install_hooks"
            echo "  INSTALL_TOOLS=$install_tools"
        else
            # Use sed to update values in .env file
            sed -i.backup \
                -e "s/^GITHUB_ORG=.*/GITHUB_ORG=$github_org/" \
                -e "s/^GITHUB_REPO=.*/GITHUB_REPO=$github_repo/" \
                -e "s/^INSTALL_LOCATION=.*/INSTALL_LOCATION=$install_location/" \
                -e "s/^INSTALL_HOOKS=.*/INSTALL_HOOKS=$install_hooks/" \
                -e "s/^INSTALL_TOOLS=.*/INSTALL_TOOLS=$install_tools/" \
                "$env_file"
            
            # Clean up backup file
            rm -f "$env_file.backup"
            
            log_success "Environment configuration updated"
        fi
    else
        log_info "Using template defaults (non-interactive mode)"
    fi
    
    # Source the environment file
    if [ "$DRY_RUN" = false ] && [ -f "$env_file" ]; then
        set -a  # Automatically export all variables
        source "$env_file"
        set +a
        log_success "Environment variables loaded"
    fi
    
    next_step
}

# Step 3: Directory creation
create_directories() {
    log_step "$((CURRENT_STEP + 1))" "$TOTAL_STEPS" "Creating Required Directories"
    echo ""
    
    # Determine paths based on configuration
    local base_dir
    if [ "${INSTALL_LOCATION:-project}" = "global" ]; then
        base_dir="$HOME/.claude"
    else
        base_dir="$PROJECT_ROOT/.claude"
    fi
    
    local directories=(
        "$base_dir"
        "$base_dir/skills"
        "$base_dir/hooks"
        "$base_dir/logs"
        "$base_dir/.signals"
        "$PROJECT_ROOT/docs"
        "$PROJECT_ROOT/tests"
        "$PROJECT_ROOT/.worktrees"
    )
    
    log_info "Creating directory structure..."
    
    for dir in "${directories[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would create directory: $dir"
        else
            if [ ! -d "$dir" ]; then
                mkdir -p "$dir"
                log_success "Created: $dir"
            else
                log_info "Already exists: $dir"
            fi
        fi
    done
    
    # Set proper permissions
    if [ "$DRY_RUN" = false ]; then
        chmod 755 "$base_dir" 2>/dev/null || true
        chmod 755 "$base_dir"/{skills,hooks,logs,.signals} 2>/dev/null || true
        log_success "Directory permissions set"
    fi
    
    next_step
}

# Step 4: Tool installation validation
validate_tool_installation() {
    log_step "$((CURRENT_STEP + 1))" "$TOTAL_STEPS" "Validating Tool Installation"
    echo ""
    
    # Check if install-pipeline.sh exists and is executable
    local installer="$PROJECT_ROOT/install-pipeline.sh"
    
    if [ ! -f "$installer" ]; then
        log_error "Pipeline installer not found: $installer"
        exit 1
    fi
    
    if [ ! -x "$installer" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would make installer executable"
        else
            chmod +x "$installer"
            log_success "Made installer executable"
        fi
    else
        log_success "Pipeline installer is ready"
    fi
    
    # Verify git repository status
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository. Please run 'git init' first."
        exit 1
    fi
    
    log_success "Git repository validated"
    
    # Check if we can run the installer
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would run pipeline installer"
    else
        log_info "Pipeline installer validation completed"
    fi
    
    next_step
}

# Step 5: Configuration validation
validate_configuration() {
    log_step "$((CURRENT_STEP + 1))" "$TOTAL_STEPS" "Validating Configuration"
    echo ""
    
    local env_file="$PROJECT_ROOT/.env"
    local template_file="$PROJECT_ROOT/.env.template"
    
    # In dry-run mode, use template file if .env doesn't exist
    if [ "$DRY_RUN" = true ] && [ ! -f "$env_file" ] && [ -f "$template_file" ]; then
        log_info "DRY RUN: Using template file for validation"
        env_file="$template_file"
    elif [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        exit 1
    fi
    
    # Source environment and validate key variables
    set -a
    source "$env_file"
    set +a
    
    # Validate required variables
    local required_vars=("GITHUB_ORG" "GITHUB_REPO" "INSTALL_LOCATION")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    # Validate specific values
    if [[ ! "$INSTALL_LOCATION" =~ ^(project|global)$ ]]; then
        log_error "INSTALL_LOCATION must be 'project' or 'global', got: $INSTALL_LOCATION"
        exit 1
    fi
    
    if [ "$GITHUB_ORG" = "your-github-username" ]; then
        log_warning "GITHUB_ORG is still set to placeholder value"
    fi
    
    log_success "Configuration validation passed"
    next_step
}

# Step 6: Final verification
final_verification() {
    log_step "$((CURRENT_STEP + 1))" "$TOTAL_STEPS" "Final Verification"
    echo ""
    
    if [ "$SKIP_VALIDATION" = true ]; then
        log_info "Skipping final verification (--skip-validation)"
        next_step
        return 0
    fi
    
    local checks_passed=0
    local total_checks=4
    
    # Check 1: Environment file
    if [ -f "$PROJECT_ROOT/.env" ]; then
        log_success "✓ Environment file exists"
        ((checks_passed++))
    else
        log_error "✗ Environment file missing"
    fi
    
    # Check 2: Pipeline installer
    if [ -x "$PROJECT_ROOT/install-pipeline.sh" ]; then
        log_success "✓ Pipeline installer is executable"
        ((checks_passed++))
    else
        log_error "✗ Pipeline installer not executable"
    fi
    
    # Check 3: Git repository
    if git rev-parse --git-dir > /dev/null 2>&1; then
        log_success "✓ Git repository initialized"
        ((checks_passed++))
    else
        log_error "✗ Not in a git repository"
    fi
    
    # Check 4: Dependencies
    local deps_ok=true
    for dep in "${PIPELINE_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            deps_ok=false
            break
        fi
    done
    
    if [ "$deps_ok" = true ] || [ "$FORCE_SETUP" = true ]; then
        log_success "✓ Pipeline dependencies available"
        ((checks_passed++))
    else
        log_error "✗ Pipeline dependencies missing"
    fi
    
    echo ""
    if [ "$checks_passed" -eq "$total_checks" ]; then
        log_success "All verification checks passed ($checks_passed/$total_checks)"
    else
        log_warning "Some verification checks failed ($checks_passed/$total_checks)"
        
        if [ "$FORCE_SETUP" = false ]; then
            log_error "Setup verification failed. Use --force to continue anyway."
            exit 1
        fi
    fi
    
    next_step
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Start metrics tracking for setup phase
    start_timer "setup_total"
    metrics_track_phase_start "setup"
    log_system_info
    
    # Handle special operations first
    if [ "$ROLLBACK" = true ]; then
        perform_rollback
        exit 0
    fi
    
    # Show banner
    show_banner
    
    # Create backup for rollback capability
    if [ "$DRY_RUN" = false ]; then
        create_backup
    fi
    
    # Initialize progress
    log_progress 0 "$TOTAL_STEPS" "Starting setup..."
    echo ""
    
    # Execute setup steps with individual tracking
    start_timer "dependencies"; validate_dependencies; stop_timer "dependencies"
    start_timer "environment"; configure_environment; stop_timer "environment"
    start_timer "directories"; create_directories; stop_timer "directories"
    start_timer "tools"; validate_tool_installation; stop_timer "tools"
    start_timer "configuration"; validate_configuration; stop_timer "configuration"
    start_timer "verification"; final_verification; stop_timer "verification"
    
    # Complete metrics tracking
    local total_duration=$(stop_timer "setup_total")
    metrics_track_phase_end "setup" "success"
    metrics_track_task_outcome "setup_complete" "success"
    
    # Completion
    echo ""
    echo -e "${CYAN}=========================================================================="
    echo -e "${GREEN}✅ Claude Dev Pipeline Setup Complete!${NC}"
    log_info "Setup completed successfully" "duration=${total_duration}s"
    echo -e "${CYAN}==========================================================================${NC}"
    echo ""
    echo -e "${BLUE}📋 Setup Summary:${NC}"
    
    if [ -f "$PROJECT_ROOT/.env" ]; then
        source "$PROJECT_ROOT/.env"
        echo "  • Configuration: .env file created and configured"
        echo "  • GitHub Org: ${GITHUB_ORG:-Not set}"
        echo "  • Install Location: ${INSTALL_LOCATION:-project}"
        echo "  • Hooks: ${INSTALL_HOOKS:-true}"
        echo "  • Tools: ${INSTALL_TOOLS:-true}"
    fi
    
    echo ""
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo ""
    echo "1. Run the pipeline installer:"
    echo -e "   ${CYAN}./install-pipeline.sh${NC}"
    echo ""
    echo "2. Or run with specific options:"
    echo -e "   ${CYAN}./install-pipeline.sh --local${NC}    # Install from local directory"
    echo -e "   ${CYAN}./install-pipeline.sh --global${NC}   # Install globally"
    echo ""
    echo "3. Start Claude Code and test:"
    echo -e "   ${CYAN}claude-code${NC}"
    echo ""
    echo -e "${BLUE}📚 Documentation:${NC}"
    echo "  • Setup Guide: docs/SETUP-GUIDE.md"
    echo "  • Troubleshooting: docs/TROUBLESHOOTING.md"
    echo ""
    echo -e "${BLUE}🔧 Configuration:${NC}"
    echo "  • Environment: .env"
    echo "  • Rollback available: Use ./setup.sh --rollback"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}Note: This was a dry run. No changes were made.${NC}"
        echo -e "${YELLOW}Run without --dry-run to perform actual setup.${NC}"
        echo ""
    fi
    
    log_success "Setup completed successfully! Ready to install the pipeline."
}

# Handle script interruption
trap 'echo ""; log_error "Setup interrupted"; exit 1' INT TERM

# Run main function
main "$@"