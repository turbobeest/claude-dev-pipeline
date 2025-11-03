#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Quick Install Script
# =============================================================================
#
# This script:
# 1. Verifies prerequisites (auto-installs if missing)
# 2. Copies pipeline files to your project
# 3. Initializes configuration
#
# Usage:
#   From temporary location:
#     cd /tmp && git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git
#     cd /path/to/your/project
#     bash /tmp/claude-dev-pipeline/install.sh
#
#   Or from pipeline repo:
#     ./install.sh /path/to/your/project
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Destination directory (default: current directory)
DEST_DIR="${1:-$(pwd)}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

log_step() {
    echo -e "\n${CYAN}==>${NC} ${BLUE}$*${NC}"
}

# =============================================================================
# Banner
# =============================================================================

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   Claude Dev Pipeline - Autonomous Full Stack Development       ║
║                                                                  ║
║   Fast Installation with Automatic Prerequisite Setup           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# =============================================================================
# Prerequisites Check & Install
# =============================================================================

check_prerequisites() {
    log_step "Step 1: Checking Prerequisites"

    # Run prerequisite checker
    if bash "${SCRIPT_DIR}/lib/prerequisites-installer.sh" --check-only; then
        log_success "All prerequisites satisfied"
        return 0
    else
        log_warning "Some prerequisites are missing"
        echo ""
        read -p "Would you like to auto-install missing prerequisites? [Y/n] " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            bash "${SCRIPT_DIR}/lib/prerequisites-installer.sh" --fix-all

            # Re-check after installation
            if bash "${SCRIPT_DIR}/lib/prerequisites-installer.sh" --check-only; then
                log_success "Prerequisites installed successfully"
                return 0
            else
                log_warning "Some prerequisites still need manual installation"
                read -p "Continue anyway? [Y/n] " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    return 0
                else
                    log_error "Installation cancelled"
                    exit 1
                fi
            fi
        else
            log_info "Skipping prerequisite installation"
            read -p "Continue without installing prerequisites? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                return 0
            else
                log_error "Installation cancelled"
                exit 1
            fi
        fi
    fi
}

# =============================================================================
# Pipeline Installation
# =============================================================================

install_pipeline() {
    log_step "Step 2: Installing Pipeline Files"

    # Validate destination
    if [[ ! -d "$DEST_DIR" ]]; then
        log_error "Destination directory does not exist: $DEST_DIR"
        exit 1
    fi

    cd "$DEST_DIR"
    log_info "Installing to: $DEST_DIR"

    # Create or update .claude directory
    if [[ -d ".claude" ]]; then
        log_info ".claude directory exists - updating installation"

        # Backup only if settings.json or custom configs exist
        if [[ -f ".claude/settings.json" ]] || [[ -f ".claude/.workflow-state.json" ]]; then
            log_info "Preserving existing configuration files"
            mkdir -p .claude/.backup-$(date +%s)
            cp -p .claude/settings.json .claude/.backup-$(date +%s)/ 2>/dev/null || true
            cp -p .claude/.workflow-state.json .claude/.backup-$(date +%s)/ 2>/dev/null || true
        fi
    else
        log_info "Creating new .claude installation"
        mkdir -p .claude
    fi

    # Copy pipeline files
    log_info "Copying hooks..."
    cp -r "${SCRIPT_DIR}/hooks" .claude/

    # Replace complex hooks with simplified versions for reliability
    log_info "Installing fault-tolerant hook versions..."
    if [[ -f "${SCRIPT_DIR}/hooks/skill-activation-prompt-simple.sh" ]]; then
        cp "${SCRIPT_DIR}/hooks/skill-activation-prompt-simple.sh" .claude/hooks/skill-activation-prompt.sh
    fi
    if [[ -f "${SCRIPT_DIR}/hooks/post-tool-use-tracker-simple.sh" ]]; then
        cp "${SCRIPT_DIR}/hooks/post-tool-use-tracker-simple.sh" .claude/hooks/post-tool-use-tracker.sh
    fi

    log_info "Copying libraries..."
    cp -r "${SCRIPT_DIR}/lib" .claude/

    log_info "Copying configuration..."
    cp -r "${SCRIPT_DIR}/config" .claude/

    log_info "Copying skills..."
    cp -r "${SCRIPT_DIR}/skills" .claude/

    if [[ -d "${SCRIPT_DIR}/commands" ]]; then
        log_info "Copying commands..."
        cp -r "${SCRIPT_DIR}/commands" .claude/
    fi

    # Initialize state files
    log_info "Initializing workflow state..."
    if [[ -f "${SCRIPT_DIR}/config/workflow-state.template.json" ]]; then
        cp "${SCRIPT_DIR}/config/workflow-state.template.json" .claude/.workflow-state.json
    else
        echo '{"phase":"pre-init","completedTasks":[],"signals":{},"lastActivation":""}' > .claude/.workflow-state.json
    fi

    # Create signals directory
    mkdir -p .claude/.signals

    # Set permissions
    log_info "Setting permissions..."
    chmod +x .claude/hooks/*.sh 2>/dev/null || true
    chmod +x .claude/lib/*.sh 2>/dev/null || true

    log_success "Pipeline files installed"
}

# =============================================================================
# Configuration
# =============================================================================

configure_pipeline() {
    log_step "Step 3: Configuring Pipeline"

    # Initialize TaskMaster if installed
    if command -v task-master >/dev/null 2>&1; then
        if [[ ! -d ".taskmaster" ]] || [[ ! -f ".taskmaster/config.json" ]]; then
            log_info "Initializing TaskMaster in project..."

            # Create directory structure
            mkdir -p .taskmaster/tasks
            mkdir -p .taskmaster/proposals
            mkdir -p .taskmaster/.checkpoints
            mkdir -p .taskmaster/.signals

            # Run task-master init with -y flag for non-interactive
            if task-master init -y >/dev/null 2>&1; then
                log_success "TaskMaster initialized"
            else
                # Fallback: manual initialization
                echo '{"version":"1.0","initialized":true}' > .taskmaster/config.json 2>/dev/null || true
                log_success "TaskMaster directories created"
            fi
        else
            log_info "TaskMaster already initialized"
        fi
    else
        log_warning "TaskMaster not installed - skipping initialization"
        log_info "Install with: npm install -g @anthropic/task-master"
    fi

    # Initialize OpenSpec if installed
    if command -v openspec >/dev/null 2>&1; then
        if [[ ! -d "openspec" ]] || [[ -z "$(ls -A openspec 2>/dev/null)" ]]; then
            log_info "Initializing OpenSpec in project..."

            # Run openspec init with --tools for non-interactive mode
            if openspec init --tools all >/dev/null 2>&1; then
                log_success "OpenSpec initialized"
            else
                # Fallback: manual initialization
                mkdir -p openspec
                echo '# OpenSpec Project' > openspec/README.md 2>/dev/null || true
                log_success "OpenSpec directory created"
            fi
        else
            log_info "OpenSpec already initialized"
        fi
    else
        log_warning "OpenSpec not installed - skipping initialization"
        log_info "Install with: npm install -g @anthropic/openspec"
    fi

    # Check if in git repo and get existing remote
    local existing_remote=""
    local git_initialized=false

    if git rev-parse --git-dir > /dev/null 2>&1; then
        log_success "Git repository detected"
        git_initialized=true

        # Try to get existing remote URL
        existing_remote=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$existing_remote" ]]; then
            log_info "Existing remote found: $existing_remote"
        fi
    else
        log_warning "Not a git repository"
        echo ""
        log_info "The pipeline works best with git for version control"
        read -p "Initialize git repository now? [Y/n] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            git init
            git_initialized=true
            log_success "Git repository initialized"
        else
            log_info "Continuing without git (you can run 'git init' later)"
        fi
    fi

    # Ask for GitHub repository URL
    local github_url=""
    if [[ "$git_initialized" == "true" ]]; then
        echo ""
        log_info "GitHub Repository Configuration"
        echo ""

        if [[ -n "$existing_remote" ]]; then
            echo "  Current remote: ${CYAN}$existing_remote${NC}"
            echo ""
            read -p "Keep this remote? [Y/n] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                github_url="$existing_remote"
                log_success "Using existing remote"
            else
                echo ""
                read -p "Enter GitHub repository URL: " github_url
            fi
        else
            echo "  No remote configured yet."
            echo ""
            read -p "Enter GitHub repository URL (or press Enter to skip): " github_url
        fi

        # Set remote if URL provided
        if [[ -n "$github_url" ]]; then
            # Validate URL format (basic check)
            if [[ "$github_url" =~ ^https://github\.com/[^/]+/[^/]+$ ]] || \
               [[ "$github_url" =~ ^git@github\.com:[^/]+/[^/]+\.git$ ]] || \
               [[ "$github_url" =~ ^https://.*github.*\.com/.+/.+$ ]]; then

                # Set or update remote
                if git remote get-url origin >/dev/null 2>&1; then
                    git remote set-url origin "$github_url"
                    log_success "Remote updated: $github_url"
                else
                    git remote add origin "$github_url"
                    log_success "Remote added: $github_url"
                fi
            else
                log_warning "Invalid GitHub URL format. Skipping remote setup."
                log_info "You can add it later with: git remote add origin <url>"
            fi
        fi
    fi

    # Create/update openspec/project.md with repo info
    if [[ ! -f "openspec/project.md" ]] || [[ ! -s "openspec/project.md" ]]; then
        log_info "Creating OpenSpec project.md..."

        local project_name=$(basename "$PWD")
        local repo_url="${github_url:-<add-your-repo-url>}"

        # Bash 3.2 compatible capitalization
        local first_char=$(echo "${project_name:0:1}" | tr '[:lower:]' '[:upper:]')
        local rest="${project_name:1}"
        local project_name_cap="${first_char}${rest}"

        cat > openspec/project.md << EOL
# ${project_name_cap} Project Overview

## Project Description
<!-- Add your project description here -->

## Repository
${repo_url}

## Technology Stack
<!-- List your tech stack here -->

## Architecture
<!-- Describe your architecture here -->

## Development Setup
\`\`\`bash
# Clone repository
git clone ${repo_url}
cd ${project_name}

# Install dependencies
# npm install  # or your package manager

# Run development
# npm run dev  # or your dev command
\`\`\`

## Project Structure
\`\`\`
${project_name}/
├── .claude/              # Claude Dev Pipeline
├── .taskmaster/          # TaskMaster workspace
├── openspec/             # OpenSpec specifications
├── docs/                 # Documentation
│   └── PRD.md           # Product Requirements
└── src/                  # Source code
\`\`\`
EOL
        log_success "OpenSpec project.md created"
    else
        log_info "OpenSpec project.md already exists (keeping existing content)"
    fi

    log_success "Project structure initialized"
}

# =============================================================================
# Verification
# =============================================================================

verify_installation() {
    log_step "Step 4: Verifying Installation"

    local errors=0

    # Check critical files exist
    if [[ ! -f ".claude/hooks/skill-activation-prompt.sh" ]]; then
        log_error "Missing: .claude/hooks/skill-activation-prompt.sh"
        errors=$((errors + 1))
    else
        log_success "Hooks installed"
    fi

    if [[ ! -d ".claude/lib" ]]; then
        log_error "Missing: .claude/lib directory"
        errors=$((errors + 1))
    else
        log_success "Libraries installed"
    fi

    if [[ ! -f ".claude/config/skill-rules.json" ]]; then
        log_error "Missing: .claude/config/skill-rules.json"
        errors=$((errors + 1))
    else
        log_success "Configuration installed"
    fi

    if [[ ! -f ".claude/.workflow-state.json" ]]; then
        log_error "Missing: .claude/.workflow-state.json"
        errors=$((errors + 1))
    else
        log_success "Workflow state initialized"
    fi

    # Test hooks
    log_info "Testing hooks..."
    if echo '{"message":"test"}' | bash .claude/hooks/skill-activation-prompt.sh >/dev/null 2>&1; then
        log_success "Hooks functional"
    else
        log_warning "Hooks may need attention"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Installation verification failed with $errors error(s)"
        return 1
    else
        log_success "Installation verified successfully"
        return 0
    fi
}

# =============================================================================
# Next Steps
# =============================================================================

show_next_steps() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  Installation Complete!                                          ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo ""
    echo "  1. Create your PRD:"
    echo "     Place your Product Requirements Document at: docs/PRD.md"
    echo ""
    echo "  2. Start development in Claude Code:"
    echo "     Open Claude Code in this directory and say:"
    echo "     \"I've completed my PRD, begin automated development\""
    echo ""
    echo "  3. For large PRDs (>25K tokens), use:"
    echo "     \".claude/lib/large-file-reader.sh docs/PRD.md\""
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  • Pipeline Architecture: .claude/docs/ARCHITECTURE.md"
    echo "  • Large File Reader:     .claude/docs/LARGE-FILE-READER.md"
    echo "  • Troubleshooting:       .claude/docs/TROUBLESHOOTING.md"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  • Check prerequisites:   ./.claude/lib/prerequisites-installer.sh"
    echo "  • Read large files:      ./.claude/lib/large-file-reader.sh <file>"
    echo "  • View skills:           ls -la .claude/skills/"
    echo ""
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    show_banner

    # Validate script location
    if [[ ! -f "${SCRIPT_DIR}/lib/prerequisites-installer.sh" ]]; then
        log_error "This script must be run from the claude-dev-pipeline directory"
        exit 1
    fi

    # Run installation steps
    check_prerequisites
    install_pipeline
    configure_pipeline
    verify_installation

    # Show next steps
    show_next_steps

    echo -e "${GREEN}✓ Installation successful!${NC}"
    echo ""
}

# Execute main
main "$@"
