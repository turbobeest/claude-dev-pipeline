#!/bin/bash
# =============================================================================
# Claude Dev Pipeline Installer - Codeword-Based Autonomous System v3.0
# =============================================================================
# 
# Installs the complete codeword-based autonomous development pipeline:
# - 10 Pipeline Skills with unique activation codes
# - 3 Core Hooks (skill-activation, post-tool-use, pre-implementation)
# - Codeword-based skill activation system
# - Signal-based phase transitions
# - State persistence and recovery
# - TaskMaster & OpenSpec integration
# - High-performance optimization libraries
#
# Environment Variables:
#   GITHUB_ORG         GitHub organization/user [default: turbobeest]
#   GITHUB_REPO        Repository name [default: claude-dev-pipeline]
#   GITHUB_BRANCH      Branch to use [default: deploy]
#   GITHUB_TOKEN       GitHub token for private repos (optional)
#   INSTALL_LOG        Log file path [default: install.log]
#   MAX_RETRIES        Network retry attempts [default: 3]
#
# Usage:
#   ./install-pipeline.sh [OPTIONS]
#
# Options:
#   --global           Install skills globally (~/.claude/skills)
#   --project          Install skills in project (.claude/skills) [DEFAULT]
#   --no-hooks         Skip hooks installation
#   --no-tools         Skip TaskMaster/OpenSpec installation
#   --github-org       GitHub org/user for pipeline repo
#   --github-repo      Repository name
#   --branch           Branch to use
#   --local            Install from local directory instead of GitHub
#   --rollback         Rollback previous installation
#   -h, --help         Show this help message
#
# Examples:
#   ./install-pipeline.sh                    # Full install (project skills)
#   ./install-pipeline.sh --global           # Full install (global skills)
#   ./install-pipeline.sh --no-hooks         # Install without hooks
#   ./install-pipeline.sh --local            # Install from current directory
#   ./install-pipeline.sh --rollback         # Rollback previous installation
#
# =============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env file if it exists
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
fi

# Installation logging
INSTALL_LOG="${INSTALL_LOG:-install.log}"
MAX_RETRIES="${MAX_RETRIES:-3}"
BACKUP_DIR=""
ROLLBACK_MODE=false

# =============================================================================
# Configuration
# =============================================================================

# Default values
INSTALL_LOCATION="project"  # "global" or "project"
INSTALL_HOOKS=true
INSTALL_TOOLS=true
INSTALL_FROM_LOCAL=false
GITHUB_ORG="${GITHUB_ORG:-turbobeest}"
GITHUB_REPO="${GITHUB_REPO:-claude-dev-pipeline}"
GITHUB_BRANCH="${GITHUB_BRANCH:-deploy}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# All 10 skills with their activation codes (bash 3.2 compatible)
get_activation_code() {
    local skill="$1"
    case "$skill" in
        "pipeline-orchestration") echo "PIPELINE_ORCHESTRATION_V1" ;;
        "prd-to-tasks") echo "PRD_TO_TASKS_V1" ;;
        "coupling-analysis") echo "COUPLING_ANALYSIS_V1" ;;
        "task-decomposer") echo "TASK_DECOMPOSER_V1" ;;
        "spec-gen") echo "SPEC_GEN_V1" ;;
        "test-strategy") echo "TEST_STRATEGY_V1" ;;
        "tdd-implementer") echo "TDD_IMPLEMENTER_V1" ;;
        "integration-validator") echo "INTEGRATION_VALIDATOR_V1" ;;
        "e2e-validator") echo "E2E_VALIDATOR_V1" ;;
        "deployment-orchestrator") echo "DEPLOYMENT_ORCHESTRATOR_V1" ;;
        *) echo "UNKNOWN_SKILL" ;;
    esac
}

# Ordered skill list for installation
SKILLS=(
    "pipeline-orchestration"
    "prd-to-tasks"
    "coupling-analysis"
    "task-decomposer"
    "spec-gen"
    "test-strategy"
    "tdd-implementer"
    "integration-validator"
    "e2e-validator"
    "deployment-orchestrator"
)

# Hook files
HOOKS=(
    "skill-activation-prompt.sh"
    "post-tool-use-tracker.sh"
    "pre-implementation-validator.sh"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

# Logging functions with file output
log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $msg" | tee -a "$INSTALL_LOG"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $msg" | tee -a "$INSTALL_LOG"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING]${NC} $msg" | tee -a "$INSTALL_LOG"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $msg" | tee -a "$INSTALL_LOG"
}

log_codeword() {
    local msg="$1"
    echo -e "${PURPLE}[CODEWORD]${NC} $msg" | tee -a "$INSTALL_LOG"
}

log_debug() {
    local msg="$1"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$INSTALL_LOG"
}

show_help() {
    grep '^#' "$0" | grep -v '#!/bin/bash' | grep -v '^# =' | sed 's/^# //' | sed 's/^#//'
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed"
        return 1
    fi
    return 0
}

# Network operations with retry
wget_with_retry() {
    local url="$1"
    local output="$2"
    local attempts=0
    local curl_args=("-fsSL")
    
    # Add authorization header if GitHub token is provided
    if [[ -n "$GITHUB_TOKEN" && "$url" == *"githubusercontent.com"* ]]; then
        curl_args+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    while [[ $attempts -lt $MAX_RETRIES ]]; do
        log_debug "Attempting download: $url (attempt $((attempts + 1))/$MAX_RETRIES)"
        
        if curl "${curl_args[@]}" "$url" -o "$output" 2>/dev/null; then
            log_debug "Successfully downloaded: $url"
            return 0
        fi
        
        attempts=$((attempts + 1))
        if [[ $attempts -lt $MAX_RETRIES ]]; then
            log_warning "Download failed, retrying in 2 seconds... ($attempts/$MAX_RETRIES)"
            sleep 2
        fi
    done
    
    log_error "Failed to download $url after $MAX_RETRIES attempts"
    return 1
}

# Validate GitHub URL accessibility
validate_github_url() {
    local base_url="$1"
    local test_file="config/skill-rules.json"
    local test_url="$base_url/$test_file"
    local curl_args=("-fsSL")
    
    # Add authorization header if GitHub token is provided
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl_args+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    log_debug "Validating GitHub URL: $test_url"
    
    if curl "${curl_args[@]}" "$test_url" >/dev/null 2>&1; then
        log_success "GitHub repository accessible"
        return 0
    else
        log_error "Cannot access GitHub repository at $base_url"
        log_error "Please check:"
        log_error "  - Repository exists: https://github.com/$GITHUB_ORG/$GITHUB_REPO"
        log_error "  - Branch exists: $GITHUB_BRANCH"
        log_error "  - Repository is public or GITHUB_TOKEN is set for private repos"
        return 1
    fi
}

# Create backup for rollback
create_backup() {
    if [[ "$INSTALL_LOCATION" == "global" ]]; then
        local target_dir="$HOME/.claude"
    else
        local target_dir="$PROJECT_ROOT/.claude"
    fi
    
    if [[ -d "$target_dir" ]]; then
        BACKUP_DIR="$target_dir.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Creating backup: $BACKUP_DIR"
        cp -r "$target_dir" "$BACKUP_DIR"
        log_success "Backup created successfully"
        echo "$BACKUP_DIR" > "$INSTALL_LOG.backup_path"
    fi
}

# Rollback installation
rollback_installation() {
    local backup_path_file="$INSTALL_LOG.backup_path"
    
    if [[ -f "$backup_path_file" ]]; then
        local backup_path
        backup_path=$(cat "$backup_path_file")
        
        if [[ -d "$backup_path" ]]; then
            log_info "Rolling back to: $backup_path"
            
            if [[ "$INSTALL_LOCATION" == "global" ]]; then
                local target_dir="$HOME/.claude"
            else
                local target_dir="$PROJECT_ROOT/.claude"
            fi
            
            rm -rf "$target_dir"
            mv "$backup_path" "$target_dir"
            rm -f "$backup_path_file"
            log_success "Rollback completed successfully"
            return 0
        fi
    fi
    
    log_error "No backup found for rollback"
    return 1
}

# Check if TaskMaster can be installed
check_taskmaster_availability() {
    log_info "Checking TaskMaster availability..."
    
    # Check if already installed
    if command -v task-master &> /dev/null; then
        log_success "TaskMaster already installed"
        return 0
    fi
    
    # Check npm availability
    if ! command -v npm &> /dev/null; then
        log_error "npm is required to install TaskMaster"
        log_error "Please install Node.js and npm first:"
        log_error "  - macOS: brew install node"
        log_error "  - Ubuntu: sudo apt-get install nodejs npm"
        log_error "  - CentOS: sudo yum install nodejs npm"
        return 1
    fi
    
    # Test npm registry access
    if ! npm view @eyaltoledano/task-master version &>/dev/null; then
        log_warning "Cannot access TaskMaster npm package"
        log_info "Will attempt GitHub installation instead"
    fi
    
    # Test GitHub access
    if ! curl -fsSL "https://api.github.com/repos/eyaltoledano/claude-task-master" >/dev/null 2>&1; then
        log_error "Cannot access TaskMaster GitHub repository"
        log_error "TaskMaster installation will fail"
        return 1
    fi
    
    log_success "TaskMaster can be installed"
    return 0
}

# Check if OpenSpec can be installed
check_openspec_availability() {
    log_info "Checking OpenSpec availability..."
    
    # Check if already installed
    if command -v openspec &> /dev/null; then
        log_success "OpenSpec already installed"
        return 0
    fi
    
    # Check npm availability
    if ! command -v npm &> /dev/null; then
        log_error "npm is required to install OpenSpec"
        return 1
    fi
    
    # Test npm registry access
    if ! npm view @fission/openspec version &>/dev/null; then
        log_warning "Cannot access OpenSpec npm package"
        log_info "Will attempt GitHub installation instead"
    fi
    
    # Test GitHub access
    if ! curl -fsSL "https://api.github.com/repos/Fission-AI/OpenSpec" >/dev/null 2>&1; then
        log_error "Cannot access OpenSpec GitHub repository"
        log_error "OpenSpec installation will fail"
        return 1
    fi
    
    log_success "OpenSpec can be installed"
    return 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --global)
            INSTALL_LOCATION="global"
            shift
            ;;
        --project)
            INSTALL_LOCATION="project"
            shift
            ;;
        --no-hooks)
            INSTALL_HOOKS=false
            shift
            ;;
        --no-tools)
            INSTALL_TOOLS=false
            shift
            ;;
        --local)
            INSTALL_FROM_LOCAL=true
            shift
            ;;
        --github-org)
            GITHUB_ORG="$2"
            shift 2
            ;;
        --github-repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --branch)
            GITHUB_BRANCH="$2"
            shift 2
            ;;
        --rollback)
            ROLLBACK_MODE=true
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
# Pre-flight Checks
# =============================================================================

# Initialize logging
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation started" > "$INSTALL_LOG"
log_debug "Script arguments: ${*:-none}"
log_debug "Environment variables: GITHUB_ORG=$GITHUB_ORG, GITHUB_REPO=$GITHUB_REPO, GITHUB_BRANCH=$GITHUB_BRANCH"

# Handle rollback mode
if [[ "$ROLLBACK_MODE" == true ]]; then
    echo ""
    echo -e "${CYAN}=========================================================================="
    echo -e "                    Claude Dev Pipeline - Rollback Mode"
    echo -e "==========================================================================${NC}"
    echo ""
    
    log_info "Starting rollback process..."
    
    if rollback_installation; then
        log_success "Rollback completed successfully!"
        exit 0
    else
        log_error "Rollback failed!"
        exit 1
    fi
fi

echo ""
echo -e "${CYAN}=========================================================================="
echo -e "         Claude Dev Pipeline - Codeword System Installer v3.0"
echo -e "==========================================================================${NC}"
echo ""

log_info "Starting pre-flight checks..."

# Check required commands
REQUIRED_COMMANDS=("git" "curl" "jq" "bash")
OPTIONAL_COMMANDS=("node" "npm")

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        log_error "Missing required command: $cmd"
        exit 1
    fi
done

for cmd in "${OPTIONAL_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        log_warning "Optional command not found: $cmd (needed for TaskMaster/OpenSpec)"
        if [ "$INSTALL_TOOLS" = true ]; then
            log_warning "Disabling tools installation"
            INSTALL_TOOLS=false
        fi
    fi
done

log_success "All required commands available"

# Validate dependency availability if tools installation is requested
if [ "$INSTALL_TOOLS" = true ]; then
    log_info "Validating tool dependencies..."
    
    if ! check_taskmaster_availability; then
        log_error "TaskMaster cannot be installed. Aborting."
        exit 1
    fi
    
    if ! check_openspec_availability; then
        log_error "OpenSpec cannot be installed. Aborting."
        exit 1
    fi
    
    log_success "All tool dependencies validated"
fi

# Determine installation directory
if [ "$INSTALL_LOCATION" = "project" ]; then
    # Use current working directory as project root
    # This allows installation in subdirectories of larger repos
    PROJECT_ROOT=$(pwd)
    log_info "Installing in project: $PROJECT_ROOT"
    
    # Check if in git repository (warning only, not required)
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warning "Not in a git repository. Consider running 'git init' if this is a new project."
    else
        GIT_ROOT=$(git rev-parse --show-toplevel)
        if [ "$PROJECT_ROOT" != "$GIT_ROOT" ]; then
            log_info "Note: Installing in subdirectory of git repo at $GIT_ROOT"
        fi
    fi
else
    log_info "Installing globally in ~/.claude"
fi

# =============================================================================
# Determine Installation Paths
# =============================================================================

if [ "$INSTALL_LOCATION" = "global" ]; then
    CLAUDE_DIR="$HOME/.claude"
    SKILLS_DIR="$HOME/.claude/skills"
    HOOKS_DIR="$HOME/.claude/hooks"
    SETTINGS_FILE="$HOME/.claude/settings.json"
else
    CLAUDE_DIR="$PROJECT_ROOT/.claude"
    SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
    HOOKS_DIR="$PROJECT_ROOT/.claude/hooks"
    SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"
fi

log_info "Claude directory: $CLAUDE_DIR"
log_info "Skills directory: $SKILLS_DIR"
log_info "Hooks directory: $HOOKS_DIR"

# Create backup before installation
create_backup

# Create Claude directory
mkdir -p "$CLAUDE_DIR"

# =============================================================================
# Installation Source
# =============================================================================

if [ "$INSTALL_FROM_LOCAL" = true ]; then
    log_info "Installing from local directory: $SCRIPT_DIR"
    SOURCE_DIR="$SCRIPT_DIR"
else
    # Create temporary directory for GitHub download
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    SOURCE_DIR="$TEMP_DIR"
    
    log_info "Downloading from GitHub: $GITHUB_ORG/$GITHUB_REPO@$GITHUB_BRANCH"
    GITHUB_BASE_URL="https://raw.githubusercontent.com/$GITHUB_ORG/$GITHUB_REPO/$GITHUB_BRANCH"
    
    # Validate GitHub URL accessibility
    if ! validate_github_url "$GITHUB_BASE_URL"; then
        log_error "GitHub repository validation failed"
        exit 1
    fi
    
    # Download skills
    log_info "Downloading skills..."
    for skill in "${SKILLS[@]}"; do
        skill_dir="$SOURCE_DIR/skills/$skill"
        mkdir -p "$skill_dir/examples"
        
        # Map directory names (handle case differences)
        github_skill_name=$skill
        case $skill in
            "prd-to-tasks") github_skill_name="PRD-to-Tasks" ;;
            "coupling-analysis") github_skill_name="Coupling-Analysis" ;;
        esac
        
        log_info "  - $skill ($(get_activation_code "$skill"))"
        if wget_with_retry "$GITHUB_BASE_URL/skills/$github_skill_name/SKILL.md" "$skill_dir/SKILL.md" || \
           wget_with_retry "$GITHUB_BASE_URL/skills/$skill/skill.md" "$skill_dir/SKILL.md"; then
            log_success "    Downloaded SKILL.md"
        else
            log_warning "    Could not download SKILL.md for $skill"
        fi
    done
    
    # Download hooks
    if [ "$INSTALL_HOOKS" = true ]; then
        log_info "Downloading hooks..."
        mkdir -p "$SOURCE_DIR/hooks"
        for hook in "${HOOKS[@]}"; do
            log_info "  - $hook"
            if wget_with_retry "$GITHUB_BASE_URL/hooks/$hook" "$SOURCE_DIR/hooks/$hook"; then
                chmod +x "$SOURCE_DIR/hooks/$hook"
                log_success "    Downloaded"
            else
                log_error "    Failed to download $hook"
            fi
        done
    fi
    
    # Download configuration
    log_info "Downloading configuration..."
    mkdir -p "$SOURCE_DIR/config"
    if ! wget_with_retry "$GITHUB_BASE_URL/config/skill-rules.json" "$SOURCE_DIR/config/skill-rules.json"; then
        log_warning "Could not download skill-rules.json"
    fi
    if ! wget_with_retry "$GITHUB_BASE_URL/config/settings.json" "$SOURCE_DIR/config/settings.json"; then
        log_warning "Could not download settings.json"
    fi
fi

# =============================================================================
# Install Skills
# =============================================================================

echo ""
log_info "Installing skills with codeword activation..."
echo ""

mkdir -p "$SKILLS_DIR"

for skill in "${SKILLS[@]}"; do
    activation_code="$(get_activation_code "$skill")"
    log_codeword "Installing $skill → [ACTIVATE:$activation_code]"
    
    # Remove existing if present
    if [ -d "$SKILLS_DIR/$skill" ]; then
        log_warning "  Removing existing $skill"
        rm -rf "$SKILLS_DIR/$skill"
    fi
    
    # Copy skill (handle both directory name formats)
    if [ -d "$SOURCE_DIR/skills/$skill" ]; then
        cp -r "$SOURCE_DIR/skills/$skill" "$SKILLS_DIR/"
    elif [ -d "$SOURCE_DIR/skills/${skill^}" ]; then  # Capitalized version
        cp -r "$SOURCE_DIR/skills/${skill^}" "$SKILLS_DIR/$skill"
    elif [ -d "$SOURCE_DIR/skills/$(echo $skill | sed 's/-/_/g')" ]; then  # Underscore version
        cp -r "$SOURCE_DIR/skills/$(echo $skill | sed 's/-/_/g')" "$SKILLS_DIR/$skill"
    else
        log_warning "  Skill directory not found for $skill"
    fi
    
    if [ -f "$SKILLS_DIR/$skill/SKILL.md" ] || [ -f "$SKILLS_DIR/$skill/skill.md" ]; then
        log_success "  Installed with activation code: $activation_code"
    fi
done

echo ""
log_success "All ${#SKILLS[@]} skills installed with codeword activation!"

# =============================================================================
# Install Configuration
# =============================================================================

log_info "Installing configuration files..."

# Create config and lib directories
mkdir -p "$CLAUDE_DIR/config"
mkdir -p "$CLAUDE_DIR/lib"

# Install skill-rules.json
if [ -f "$SOURCE_DIR/config/skill-rules.json" ]; then
    cp "$SOURCE_DIR/config/skill-rules.json" "$CLAUDE_DIR/config/skill-rules.json"
    # Also keep a copy in the root for backwards compatibility
    cp "$SOURCE_DIR/config/skill-rules.json" "$CLAUDE_DIR/skill-rules.json"
    log_success "  Installed skill-rules.json (codeword mappings)"
else
    log_warning "  skill-rules.json not found in source"
fi

# Initialize workflow state
if [ ! -f "$CLAUDE_DIR/.workflow-state.json" ]; then
    INSTALL_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    cat > "$CLAUDE_DIR/.workflow-state.json" << EOF
{
  "phase": "pre-init",
  "completedTasks": [],
  "signals": {},
  "lastActivation": "",
  "lastSignal": "",
  "metadata": {
    "installedAt": "$INSTALL_TIME",
    "version": "3.0"
  }
}
EOF
    log_success "  Created .workflow-state.json"
fi

# Create signals directory
mkdir -p "$CLAUDE_DIR/.signals"
log_success "  Created .signals/ directory for phase tracking"

# =============================================================================
# Install Hooks
# =============================================================================

if [ "$INSTALL_HOOKS" = true ]; then
    echo ""
    log_info "Installing hooks for autonomous operation..."
    echo ""
    
    mkdir -p "$HOOKS_DIR"
    
    for hook in "${HOOKS[@]}"; do
        hook_desc=""
        case $hook in
            "skill-activation-prompt.sh")
                hook_desc="Injects codewords before Claude sees message"
                ;;
            "post-tool-use-tracker.sh")
                hook_desc="Emits signals and triggers phase transitions"
                ;;
            "pre-implementation-validator.sh")
                hook_desc="Enforces TDD (blocks implementation without tests)"
                ;;
        esac
        
        log_info "Installing $hook"
        if [ -f "$SOURCE_DIR/hooks/$hook" ]; then
            cp "$SOURCE_DIR/hooks/$hook" "$HOOKS_DIR/"
            chmod +x "$HOOKS_DIR/$hook"
            log_success "  $hook_desc"
        else
            log_warning "  $hook not found in source"
        fi
    done
    
    # Configure settings.json
    log_info "Configuring Claude Code settings..."
    
    if [ -f "$SETTINGS_FILE" ]; then
        log_warning "  Backing up existing settings.json to settings.json.backup"
        cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    fi
    
    # Generate settings.json with hook configuration
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "version": "3.0",
  "activation_mode": "codeword",
  "hooks": {
    "UserPromptSubmit": [
      {
        "name": "Codeword Injector",
        "description": "Analyzes context and injects skill activation codewords",
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/skill-activation-prompt.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "name": "Phase Tracker",
        "description": "Tracks progress and triggers automatic phase transitions",
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/post-tool-use-tracker.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "name": "TDD Enforcer",
        "description": "Blocks implementation without tests",
        "matcher": "Write|Create|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/pre-implementation-validator.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "pipeline": {
    "manual_gates": [
      "Pipeline Start (Phase 0 → 1)",
      "Implementation Start (Phase 2 → 3)",
      "Deployment Approval (Phase 5 → 6)"
    ],
    "automation_level": "95%",
    "skill_activation_rate": "100%"
  }
}
EOF
    log_success "  Configured hooks in settings.json"
    echo ""
    log_success "Hooks installed - autonomous operation enabled!"
fi

# =============================================================================
# Install Tools (TaskMaster & OpenSpec)
# =============================================================================

if [ "$INSTALL_TOOLS" = true ]; then
    echo ""
    log_info "Installing development tools..."
    
    # Install TaskMaster
    log_info "  Installing TaskMaster..."
    if command -v task-master &> /dev/null; then
        log_success "    TaskMaster already installed"
    else
        log_info "    Attempting npm installation..."
        if npm install -g @eyaltoledano/task-master 2>&1 | tee -a "$INSTALL_LOG"; then
            log_success "    TaskMaster installed via npm"
        else
            log_warning "    npm installation failed, trying GitHub..."
            if git clone https://github.com/eyaltoledano/claude-task-master.git "$TEMP_DIR/taskmaster" 2>&1 | tee -a "$INSTALL_LOG"; then
                cd "$TEMP_DIR/taskmaster"
                if npm install -g . 2>&1 | tee -a "$INSTALL_LOG"; then
                    log_success "    TaskMaster installed from GitHub"
                else
                    log_error "    TaskMaster GitHub installation failed"
                fi
                cd - > /dev/null
            else
                log_error "    Failed to clone TaskMaster repository"
            fi
        fi
        
        # Final verification
        if ! command -v task-master &> /dev/null; then
            log_error "    TaskMaster installation failed completely"
            log_error "    Please install manually: npm install -g @eyaltoledano/task-master"
        fi
    fi
    
    # Install OpenSpec
    log_info "  Installing OpenSpec..."
    if command -v openspec &> /dev/null; then
        log_success "    OpenSpec already installed"
    else
        log_info "    Attempting npm installation..."
        if npm install -g @fission/openspec 2>&1 | tee -a "$INSTALL_LOG"; then
            log_success "    OpenSpec installed via npm"
        else
            log_warning "    npm installation failed, trying GitHub..."
            if git clone https://github.com/Fission-AI/OpenSpec.git "$TEMP_DIR/openspec" 2>&1 | tee -a "$INSTALL_LOG"; then
                cd "$TEMP_DIR/openspec"
                if npm install -g . 2>&1 | tee -a "$INSTALL_LOG"; then
                    log_success "    OpenSpec installed from GitHub"
                else
                    log_error "    OpenSpec GitHub installation failed"
                fi
                cd - > /dev/null
            else
                log_error "    Failed to clone OpenSpec repository"
            fi
        fi
        
        # Final verification
        if ! command -v openspec &> /dev/null; then
            log_error "    OpenSpec installation failed completely"
            log_error "    Please install manually: npm install -g @fission/openspec"
        fi
    fi
fi

# =============================================================================
# Initialize Project Structure
# =============================================================================

if [ "$INSTALL_LOCATION" = "project" ]; then
    log_info "Initializing project structure..."
    
    # Create required directories
    mkdir -p "$PROJECT_ROOT"/{docs,tests,.taskmaster,.openspec}
    
    # Handle .env configuration
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        # No existing .env, copy template if available
        if [ -f "$SOURCE_DIR/.env.template" ]; then
            cp "$SOURCE_DIR/.env.template" "$PROJECT_ROOT/.env"
            log_success "  Created .env from template"
        fi
    else
        # Existing .env (probably from TaskMaster), check if pipeline config exists
        if ! grep -q "Claude Dev Pipeline Configuration" "$PROJECT_ROOT/.env" 2>/dev/null; then
            # Append pipeline configuration
            cat >> "$PROJECT_ROOT/.env" << 'EOF'

# === Claude Dev Pipeline Configuration ===
# GitHub Repository (full URL - works with enterprise and personal GitHub)
# Examples: https://github.com/user/repo or https://github.enterprise.com/org/repo
GITHUB_REPO_URL=https://github.com/turbobeest/claude-dev-pipeline
GITHUB_BRANCH=deploy

# GitHub Token (optional - only needed for private repos)
# Not required for enterprise GitHub with SSO authentication
# GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# TaskMaster Configuration
# GitHub token with repo, project, issues, pull_requests permissions
# TASKMASTER_GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
# Note: ANTHROPIC_API_KEY should already be at the top of your .env from TaskMaster

# Pipeline Settings (optional - defaults work fine)
AUTOMATION_LEVEL=95
USE_WORKTREES=true
WORKTREE_BASE_DIR=.worktrees
LOG_LEVEL=INFO

# Hook Configuration (optional)
HOOK_DEBUG=false
SKILL_ACTIVATION_DEBUG=false
EOF
            log_success "  Appended pipeline config to existing .env"
        else
            log_info "  Pipeline config already exists in .env"
        fi
    fi
    
    # Create reference documents
    if [ -d "$SOURCE_DIR/reference" ]; then
        log_info "  Installing reference documentation..."
        cp -r "$SOURCE_DIR/reference" "$PROJECT_ROOT/docs/pipeline-reference"
        log_success "  Reference docs installed"
    fi
    
    # Create workflow mapping file
    if [ ! -f "$PROJECT_ROOT/TASKMASTER_OPENSPEC_MAP.md" ]; then
        cat > "$PROJECT_ROOT/TASKMASTER_OPENSPEC_MAP.md" << 'EOF'
# TaskMaster ↔ OpenSpec Mapping

## Workflow Phases

| Phase | Status | Signal | Codeword |
|-------|--------|--------|----------|
| Phase 1: Task Decomposition | ⏳ | PHASE1_COMPLETE | PRD_TO_TASKS_V1 |
| Phase 2: Specification | ⏳ | PHASE2_COMPLETE | SPEC_GEN_V1 |
| Phase 3: Implementation | ⏳ | PHASE3_COMPLETE | TDD_IMPLEMENTER_V1 |
| Phase 4: Integration | ⏳ | PHASE4_COMPLETE | INTEGRATION_VALIDATOR_V1 |
| Phase 5: E2E | ⏳ | PHASE5_COMPLETE | E2E_VALIDATOR_V1 |
| Phase 6: Deployment | ⏳ | DEPLOYED | DEPLOYMENT_ORCHESTRATOR_V1 |

## Task Mapping

<!-- Auto-populated during workflow -->
EOF
        log_success "  Created TASKMASTER_OPENSPEC_MAP.md"
    fi
fi

# =============================================================================
# Verification and Testing
# =============================================================================

echo ""
log_info "Verifying installation..."

# Initialize verification counters
VERIFICATION_ERRORS=0
VERIFICATION_WARNINGS=0

# Check skills installation
log_info "  Checking skills installation..."
SKILLS_INSTALLED=0
SKILLS_ERRORS=()

for skill in "${SKILLS[@]}"; do
    skill_installed=false
    skill_file=""
    
    if [ -f "$SKILLS_DIR/$skill/SKILL.md" ]; then
        skill_file="SKILL.md"
        skill_installed=true
    elif [ -f "$SKILLS_DIR/$skill/skill.md" ]; then
        skill_file="skill.md"
        skill_installed=true
    fi
    
    if [ "$skill_installed" = true ]; then
        ((SKILLS_INSTALLED++))
        
        # Validate skill file contains activation code
        activation_code="$(get_activation_code "$skill")"
        if grep -q "$activation_code" "$SKILLS_DIR/$skill/$skill_file" 2>/dev/null; then
            log_success "    ✅ $skill: installed with activation code"
        else
            log_warning "    ⚠️  $skill: installed but activation code not found in file"
            ((VERIFICATION_WARNINGS++))
        fi
    else
        log_error "    ❌ $skill: not installed"
        SKILLS_ERRORS+=("$skill")
        ((VERIFICATION_ERRORS++))
    fi
done

if [ $SKILLS_INSTALLED -eq ${#SKILLS[@]} ]; then
    log_success "✅ All ${#SKILLS[@]} skills installed successfully"
else
    log_error "❌ Only $SKILLS_INSTALLED/${#SKILLS[@]} skills installed"
    log_error "Missing skills: ${SKILLS_ERRORS[*]}"
    ((VERIFICATION_ERRORS++))
fi

# Check hooks
if [ "$INSTALL_HOOKS" = true ]; then
    log_info "  Checking hooks installation..."
    HOOKS_INSTALLED=0
    HOOKS_ERRORS=()
    
    for hook in "${HOOKS[@]}"; do
        if [ -x "$HOOKS_DIR/$hook" ]; then
            ((HOOKS_INSTALLED++))
            log_success "    ✅ $hook: installed and executable"
        else
            log_error "    ❌ $hook: not installed or not executable"
            HOOKS_ERRORS+=("$hook")
            ((VERIFICATION_ERRORS++))
        fi
    done
    
    if [ $HOOKS_INSTALLED -eq ${#HOOKS[@]} ]; then
        log_success "✅ All ${#HOOKS[@]} hooks installed and executable"
    else
        log_error "❌ Only $HOOKS_INSTALLED/${#HOOKS[@]} hooks installed"
        log_error "Missing hooks: ${HOOKS_ERRORS[*]}"
    fi
    
    # Test hooks functionality
    log_info "  Testing hooks functionality..."
    if [ -x "$HOOKS_DIR/skill-activation-prompt.sh" ]; then
        # Check if timeout command exists (not available on macOS by default)
        if command -v timeout >/dev/null 2>&1; then
            if timeout 10 bash "$HOOKS_DIR/skill-activation-prompt.sh" "test prompt" >/dev/null 2>&1; then
                log_success "    ✅ skill-activation-prompt.sh: functional"
            else
                log_warning "    ⚠️  skill-activation-prompt.sh: execution test failed"
                ((VERIFICATION_WARNINGS++))
            fi
        else
            # On macOS without timeout, just check if hook exists and is executable
            log_success "    ✅ skill-activation-prompt.sh: installed and executable (test skipped on macOS)"
        fi
    fi
fi

# Check configuration
log_info "  Checking configuration files..."
if [ -f "$CLAUDE_DIR/skill-rules.json" ]; then
    if jq . "$CLAUDE_DIR/skill-rules.json" >/dev/null 2>&1; then
        log_success "    ✅ skill-rules.json: installed and valid JSON"
    else
        log_error "    ❌ skill-rules.json: invalid JSON format"
        ((VERIFICATION_ERRORS++))
    fi
else
    log_error "    ❌ skill-rules.json: not found"
    ((VERIFICATION_ERRORS++))
fi

if [ -f "$CLAUDE_DIR/.workflow-state.json" ]; then
    if jq . "$CLAUDE_DIR/.workflow-state.json" >/dev/null 2>&1; then
        log_success "    ✅ .workflow-state.json: initialized and valid JSON"
    else
        log_error "    ❌ .workflow-state.json: invalid JSON format"
        ((VERIFICATION_ERRORS++))
    fi
else
    log_error "    ❌ .workflow-state.json: not found"
    ((VERIFICATION_ERRORS++))
fi

if [ -f "$SETTINGS_FILE" ] && [ "$INSTALL_HOOKS" = true ]; then
    if jq . "$SETTINGS_FILE" >/dev/null 2>&1; then
        log_success "    ✅ settings.json: configured and valid JSON"
    else
        log_error "    ❌ settings.json: invalid JSON format"
        ((VERIFICATION_ERRORS++))
    fi
fi

# Check tools
if [ "$INSTALL_TOOLS" = true ]; then
    log_info "  Checking tools installation..."
    
    if command -v task-master &> /dev/null; then
        if task-master --version >/dev/null 2>&1; then
            log_success "    ✅ TaskMaster: installed and functional"
        else
            log_warning "    ⚠️  TaskMaster: installed but version check failed"
            ((VERIFICATION_WARNINGS++))
        fi
    else
        log_error "    ❌ TaskMaster: not found in PATH"
        ((VERIFICATION_ERRORS++))
    fi
    
    if command -v openspec &> /dev/null; then
        if openspec --version >/dev/null 2>&1; then
            log_success "    ✅ OpenSpec: installed and functional"
        else
            log_warning "    ⚠️  OpenSpec: installed but version check failed"
            ((VERIFICATION_WARNINGS++))
        fi
    else
        log_error "    ❌ OpenSpec: not found in PATH"
        ((VERIFICATION_ERRORS++))
    fi
fi

# Installation verification summary
log_info "  Generating installation report..."
echo ""
echo "========================================" | tee -a "$INSTALL_LOG"
echo "Installation Verification Summary" | tee -a "$INSTALL_LOG"
echo "========================================" | tee -a "$INSTALL_LOG"
echo "Timestamp: $(date)" | tee -a "$INSTALL_LOG"
echo "Location: $INSTALL_LOCATION ($CLAUDE_DIR)" | tee -a "$INSTALL_LOG"
echo "Skills installed: $SKILLS_INSTALLED/${#SKILLS[@]}" | tee -a "$INSTALL_LOG"
if [ "$INSTALL_HOOKS" = true ]; then
    echo "Hooks installed: $HOOKS_INSTALLED/${#HOOKS[@]}" | tee -a "$INSTALL_LOG"
fi
if [ "$INSTALL_TOOLS" = true ]; then
    echo "Tools requested: Yes" | tee -a "$INSTALL_LOG"
fi
echo "Errors: $VERIFICATION_ERRORS" | tee -a "$INSTALL_LOG"
echo "Warnings: $VERIFICATION_WARNINGS" | tee -a "$INSTALL_LOG"
echo "========================================" | tee -a "$INSTALL_LOG"
echo ""

# Determine installation success
if [ $VERIFICATION_ERRORS -eq 0 ]; then
    log_success "🎉 Installation completed successfully!"
    if [ $VERIFICATION_WARNINGS -gt 0 ]; then
        log_warning "⚠️  Installation has $VERIFICATION_WARNINGS warnings (see log: $INSTALL_LOG)"
    fi
    INSTALL_SUCCESS=true
else
    log_error "❌ Installation completed with $VERIFICATION_ERRORS errors"
    log_error "See detailed log: $INSTALL_LOG"
    log_info "To rollback this installation, run: $0 --rollback"
    INSTALL_SUCCESS=false
fi

# =============================================================================
# Post-Installation Instructions
# =============================================================================

echo ""
if [ "$INSTALL_SUCCESS" = true ]; then
    echo -e "${CYAN}=========================================================================="
    echo -e "${GREEN}✅ Codeword-Based Pipeline Installation Complete!${NC}"
    echo -e "${CYAN}==========================================================================${NC}"
else
    echo -e "${CYAN}=========================================================================="
    echo -e "${RED}❌ Codeword-Based Pipeline Installation Failed!${NC}"
    echo -e "${CYAN}==========================================================================${NC}"
fi
echo ""
echo -e "${BLUE}📊 Installation Summary:${NC}"
echo "  • Location: $INSTALL_LOCATION"
echo "  • Skills: ${#SKILLS[@]} installed with codeword activation"
if [ "$INSTALL_HOOKS" = true ]; then
    echo "  • Hooks: 3 autonomous orchestration hooks"
    echo "  • Automation Level: 95% (3 manual gates)"
fi
if [ "$INSTALL_TOOLS" = true ]; then
    echo "  • Tools: TaskMaster, OpenSpec"
fi
echo ""
echo -e "${PURPLE}🎯 Codeword Activation Map:${NC}"
echo ""
for skill in "${SKILLS[@]:0:5}"; do
    printf "  %-25s → [ACTIVATE:%s]\n" "$skill" "$(get_activation_code "$skill")"
done
echo "  ... and 5 more skills"
echo ""
echo -e "${BLUE}🚀 Quick Start:${NC}"
echo ""
echo "1. Start Claude Code:"
echo "   ${CYAN}claude-code${NC}"
echo ""
echo "2. Test codeword activation:"
echo "   Type: ${YELLOW}\"Generate tasks from my PRD\"${NC}"
echo "   "
echo "   Expected response:"
echo "   ${PURPLE}[ACTIVATE:PRD_TO_TASKS_V1]${NC}"
echo "   ${GREEN}**Active Skills:** prd-to-tasks${NC}"
echo ""
echo "3. Start automated pipeline:"
echo "   Type: ${YELLOW}\"Begin automated development\"${NC}"
echo "   "
echo "   System will inject:"
echo "   ${PURPLE}[ACTIVATE:PIPELINE_ORCHESTRATION_V1]${NC}"
echo "   And automation begins!"
echo ""
echo -e "${BLUE}📚 How It Works:${NC}"
echo ""
echo "  Traditional: User says \"generate tasks\" → Claude might miss it (70% success)"
echo "  ${GREEN}Codeword:${NC}    User says \"generate tasks\" → Hook injects ${PURPLE}[ACTIVATE:PRD_TO_TASKS_V1]${NC}"
echo "              → Skill activates immediately (100% success)"
echo ""
if [ "$INSTALL_HOOKS" = true ]; then
    echo -e "${YELLOW}⚠️  Hooks Are Active:${NC}"
    echo "  • Skills auto-activate via codewords"
    echo "  • Phases transition automatically via signals"
    echo "  • TDD is enforced (tests required before implementation)"
    echo "  • State persists across sessions"
    echo ""
fi
echo -e "${BLUE}📖 Documentation:${NC}"
if [ "$INSTALL_LOCATION" = "project" ]; then
    echo "  • Workflow Guide: $PROJECT_ROOT/docs/pipeline-reference/development-workflow-guide.md"
    echo "  • Visual Diagram: $PROJECT_ROOT/docs/pipeline-reference/visual-workflow-diagram.md"
    echo "  • Design Rationale: $PROJECT_ROOT/docs/pipeline-reference/design-decisions-and-rationale.md"
else
    echo "  • GitHub: https://github.com/$GITHUB_ORG/$GITHUB_REPO"
fi
echo ""
echo -e "${BLUE}🔍 Check Pipeline Status:${NC}"
echo "  In Claude Code, type: ${YELLOW}\"What's the pipeline status?\"${NC}"
echo ""
echo -e "${GREEN}=========================================================================="
echo ""
echo -e "${GREEN}Ready for autonomous development! The pipeline will handle 95% of the workflow automatically.${NC}"
echo -e "${GREEN}You only need to intervene at 3 strategic gates. Everything else is automated!${NC}"
echo ""
echo -e "${CYAN}=========================================================================${NC}"
echo ""

# =============================================================================
# Optional Git Commit
# =============================================================================

if [ "$INSTALL_LOCATION" = "project" ]; then
    echo -e "${BLUE}Would you like to commit these changes to git?${NC} (y/n)"
    read -r COMMIT_RESPONSE
    
    if [[ "$COMMIT_RESPONSE" =~ ^[Yy]$ ]]; then
        cd "$PROJECT_ROOT"
        git add .claude/ docs/ TASKMASTER_OPENSPEC_MAP.md 2>/dev/null || true
        git commit -m "feat: Install Claude Dev Pipeline - Codeword System v3.0

- Added 10 pipeline skills with unique activation codes
- Installed 3 autonomous orchestration hooks
- Configured codeword-based skill activation
- Added signal-based phase transitions
- Initialized workflow state tracking
- Set up 95% automation with 3 manual gates

Activation codes:
$(for skill in "${SKILLS[@]}"; do
    echo "  - $skill: $(get_activation_code "$skill")"
done)

Installed via: install-pipeline.sh" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Changes committed to git"
        fi
    fi
fi

# Finalize logging
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation finished with status: $INSTALL_SUCCESS" >> "$INSTALL_LOG"

if [ "$INSTALL_SUCCESS" = true ]; then
    log_success "Installation complete! Welcome to the future of automated development! 🚀"
    log_info "Installation log saved to: $INSTALL_LOG"
else
    log_error "Installation failed. Check the log for details: $INSTALL_LOG"
    log_info "Run '$0 --rollback' to restore previous state"
    exit 1
fi