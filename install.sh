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

    log_info "Copying libraries..."
    cp -r "${SCRIPT_DIR}/lib" .claude/

    log_info "Copying configuration..."
    cp -r "${SCRIPT_DIR}/config" .claude/

    # Copy settings.json to .claude/ root (where Claude Code expects it)
    if [[ -f "${SCRIPT_DIR}/config/settings.json" ]]; then
        cp "${SCRIPT_DIR}/config/settings.json" .claude/settings.json
        log_info "Configured hooks in .claude/settings.json"
    fi

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

    # Create symlink for user-prompt-submit hook
    log_info "Creating hook symlinks..."
    ln -sf skill-activation-prompt.sh .claude/hooks/user-prompt-submit.sh

    log_success "Pipeline files installed"
}

# =============================================================================
# Configuration
# =============================================================================

configure_pipeline() {
    log_step "Step 3: Configuring Pipeline"

    # Initialize TaskMaster if installed
    if command -v task-master >/dev/null 2>&1; then
        # Check if TaskMaster already has data
        local has_existing_data=false
        if [[ -f ".taskmaster/tasks/tasks.json" ]]; then
            local task_count=$(jq 'try (.master.tasks | length) // (if .tasks then (.tasks | length) else 0 end)' .taskmaster/tasks/tasks.json 2>/dev/null || echo "0")
            if [[ "$task_count" -gt 0 ]]; then
                has_existing_data=true
            fi
        fi

        if [[ "$has_existing_data" == "true" ]]; then
            # Preserve existing data
            log_success "TaskMaster data found ($task_count tasks) - preserving existing data"
            log_info "To start fresh, manually delete .taskmaster/ before reinstalling"
        elif [[ ! -d ".taskmaster" ]] || [[ ! -f ".taskmaster/config.json" ]]; then
            # Fresh installation
            log_info "Initializing TaskMaster in project..."

            # Create directory structure
            mkdir -p .taskmaster/tasks
            mkdir -p .taskmaster/proposals
            mkdir -p .taskmaster/.checkpoints
            mkdir -p .taskmaster/.signals
            mkdir -p .taskmaster/docs

            # Run task-master init with -y flag for non-interactive (claude rule only)
            if task-master init -y -r claude >/dev/null 2>&1; then
                log_success "TaskMaster initialized"
            else
                # Fallback: manual initialization
                echo '{"version":"1.0","initialized":true}' > .taskmaster/config.json 2>/dev/null || true
                log_success "TaskMaster directories created"
            fi
        else
            # Empty .taskmaster exists - safe to skip
            log_info "TaskMaster already initialized (no data to preserve)"
        fi
    else
        log_warning "TaskMaster not installed - skipping initialization"
        log_info "Install with: npm install -g @anthropic/task-master"
    fi

    # Configure API Keys for TaskMaster
    if command -v task-master >/dev/null 2>&1; then
        echo ""
        log_info "TaskMaster API Configuration"
        echo ""

        # Copy .env.example if it doesn't exist
        if [[ ! -f ".env" ]] && [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
            cp "${SCRIPT_DIR}/.env.example" .env
        fi

        # Check for existing API key
        local existing_api_key=""
        if [[ -f ".env" ]]; then
            existing_api_key=$(grep "^ANTHROPIC_API_KEY=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
        fi

        local api_key=""
        if [[ -n "$existing_api_key" ]]; then
            # Mask the key for display (show first 7 and last 4 characters)
            local masked_key="${existing_api_key:0:7}...${existing_api_key: -4}"
            echo "  Existing API key found: ${CYAN}${masked_key}${NC}"
            echo ""
            read -p "Keep this API key? [Y/n] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                api_key="$existing_api_key"
                log_success "Using existing API key"
            else
                read -p "Enter your Claude API key: " api_key
            fi
        else
            echo "  TaskMaster requires an Anthropic API key."
            echo "  Get yours at: ${CYAN}https://console.anthropic.com/settings/keys${NC}"
            echo ""
            read -p "Enter your Claude API key (or press Enter to skip): " api_key
        fi

        # Save API key to .env
        if [[ -n "$api_key" ]]; then
            # Create or update .env file
            if [[ -f ".env" ]]; then
                # Update existing key or append
                if grep -q "^ANTHROPIC_API_KEY=" .env 2>/dev/null; then
                    # Use different sed syntax for macOS vs Linux
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i '' "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$api_key|" .env
                    else
                        sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$api_key|" .env
                    fi
                else
                    echo "ANTHROPIC_API_KEY=$api_key" >> .env
                fi
            else
                echo "ANTHROPIC_API_KEY=$api_key" > .env
            fi
            log_success "API key saved to .env"

            # Ensure .env is in .gitignore
            if [[ -f ".gitignore" ]]; then
                if ! grep -q "^\.env$" .gitignore 2>/dev/null; then
                    echo ".env" >> .gitignore
                    log_info "Added .env to .gitignore"
                fi
            else
                echo ".env" > .gitignore
                log_info "Created .gitignore with .env"
            fi
        else
            log_warning "No API key provided - TaskMaster features will be limited"
            log_info "You can add it later to .env file: ANTHROPIC_API_KEY=your_key"
        fi

        # Configure TaskMaster models
        if [[ -f ".taskmaster/config.json" ]]; then
            echo ""
            log_info "TaskMaster Model Configuration"
            echo ""

            # Check existing model configuration
            local current_main_model=$(jq -r '.models.main.modelId // "not configured"' .taskmaster/config.json 2>/dev/null)
            local current_research_model=$(jq -r '.models.research.modelId // "not configured"' .taskmaster/config.json 2>/dev/null)

            # Check if models are already configured
            local current_fallback_model=$(jq -r '.models.fallback.modelId // "not configured"' .taskmaster/config.json 2>/dev/null)

            if [[ "$current_main_model" != "not configured" ]]; then
                echo "  Current configuration:"
                echo "    Main model: ${CYAN}${current_main_model}${NC}"
                echo "    Research model: ${CYAN}${current_research_model}${NC}"
                echo "    Fallback model: ${CYAN}${current_fallback_model}${NC}"
                echo ""
                read -p "Keep these model settings? [Y/n] " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    log_success "Using existing model configuration"
                else
                    # Prompt for new model selection (all three roles)
                    echo ""
                    echo "  ${YELLOW}TaskMaster uses three model roles:${NC}"
                    echo "    • ${CYAN}Main${NC}: Primary task processing (parse PRD, add/update tasks)"
                    echo "    • ${CYAN}Research${NC}: Web research and analysis (--research flag)"
                    echo "    • ${CYAN}Fallback${NC}: Backup if main model fails"
                    echo ""
                    echo "  ${GREEN}Recommended: Use Sonnet 4.5 for all three roles${NC}"
                    echo ""

                    # Model selection options
                    echo "  Available models:"
                    echo "    ${CYAN}1${NC}) claude-sonnet-4-5-20250929 (73% SWE, \$3/\$15 per 1M tokens) ${GREEN}[Default]${NC}"
                    echo "    ${CYAN}2${NC}) claude-opus-4-20250514 (72.5% SWE, \$15/\$75 per 1M tokens)"
                    echo "    ${CYAN}3${NC}) claude-3-7-sonnet-20250219 (62% SWE, \$3/\$15 per 1M tokens)"
                    echo "    ${CYAN}4${NC}) claude-haiku-4-5-20251001 (45% SWE, \$1/\$5 per 1M tokens)"
                    echo "    ${CYAN}5${NC}) perplexity-llama-3.1-sonar-large-128k-online (research only)"
                    echo ""

                    # Main model
                    read -p "Main model [1-5] (default: 1): " main_choice
                    main_choice=${main_choice:-1}
                    case $main_choice in
                        1) main_model="claude-sonnet-4-5-20250929"; main_provider="anthropic" ;;
                        2) main_model="claude-opus-4-20250514"; main_provider="anthropic" ;;
                        3) main_model="claude-3-7-sonnet-20250219"; main_provider="anthropic" ;;
                        4) main_model="claude-haiku-4-5-20251001"; main_provider="anthropic" ;;
                        5) main_model="perplexity-llama-3.1-sonar-large-128k-online"; main_provider="perplexity" ;;
                        *) main_model="claude-sonnet-4-5-20250929"; main_provider="anthropic" ;;
                    esac

                    # Research model
                    read -p "Research model [1-5] (default: 1): " research_choice
                    research_choice=${research_choice:-1}
                    case $research_choice in
                        1) research_model="claude-sonnet-4-5-20250929"; research_provider="anthropic" ;;
                        2) research_model="claude-opus-4-20250514"; research_provider="anthropic" ;;
                        3) research_model="claude-3-7-sonnet-20250219"; research_provider="anthropic" ;;
                        4) research_model="claude-haiku-4-5-20251001"; research_provider="anthropic" ;;
                        5) research_model="perplexity-llama-3.1-sonar-large-128k-online"; research_provider="perplexity" ;;
                        *) research_model="claude-sonnet-4-5-20250929"; research_provider="anthropic" ;;
                    esac

                    # Fallback model
                    read -p "Fallback model [1-5] (default: 1): " fallback_choice
                    fallback_choice=${fallback_choice:-1}
                    case $fallback_choice in
                        1) fallback_model="claude-sonnet-4-5-20250929"; fallback_provider="anthropic" ;;
                        2) fallback_model="claude-opus-4-20250514"; fallback_provider="anthropic" ;;
                        3) fallback_model="claude-3-7-sonnet-20250219"; fallback_provider="anthropic" ;;
                        4) fallback_model="claude-haiku-4-5-20251001"; fallback_provider="anthropic" ;;
                        5) fallback_model="perplexity-llama-3.1-sonar-large-128k-online"; fallback_provider="perplexity" ;;
                        *) fallback_model="claude-sonnet-4-5-20250929"; fallback_provider="anthropic" ;;
                    esac

                    # Update config.json with all three models
                    jq --arg main "$main_model" \
                       --arg main_provider "$main_provider" \
                       --arg research "$research_model" \
                       --arg research_provider "$research_provider" \
                       --arg fallback "$fallback_model" \
                       --arg fallback_provider "$fallback_provider" \
                        '.models.main.modelId = $main |
                         .models.main.provider = $main_provider |
                         .models.research.modelId = $research |
                         .models.research.provider = $research_provider |
                         .models.fallback.modelId = $fallback |
                         .models.fallback.provider = $fallback_provider' \
                        .taskmaster/config.json > .taskmaster/config.json.tmp && \
                        mv .taskmaster/config.json.tmp .taskmaster/config.json

                    echo ""
                    log_success "Model configuration updated:"
                    echo "  Main: ${CYAN}${main_model}${NC}"
                    echo "  Research: ${CYAN}${research_model}${NC}"
                    echo "  Fallback: ${CYAN}${fallback_model}${NC}"
                fi
            else
                # First-time setup - offer quick defaults
                echo "  ${YELLOW}TaskMaster Model Configuration${NC}"
                echo ""
                echo "  TaskMaster uses three model roles:"
                echo "    • ${CYAN}Main${NC}: Primary task processing"
                echo "    • ${CYAN}Research${NC}: Web research (with --research flag)"
                echo "    • ${CYAN}Fallback${NC}: Backup if main fails"
                echo ""
                echo "  ${GREEN}Quick Setup: Use Sonnet 4.5 for all three? [Y/n]${NC}"
                read -p "  " -n 1 -r
                echo ""

                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    # Set all three to sonnet 4.5
                    jq '.models.main.modelId = "claude-sonnet-4-5-20250929" |
                        .models.main.provider = "anthropic" |
                        .models.research.modelId = "claude-sonnet-4-5-20250929" |
                        .models.research.provider = "anthropic" |
                        .models.fallback.modelId = "claude-sonnet-4-5-20250929" |
                        .models.fallback.provider = "anthropic"' \
                        .taskmaster/config.json > .taskmaster/config.json.tmp && \
                        mv .taskmaster/config.json.tmp .taskmaster/config.json

                    log_success "All models set to claude-sonnet-4-5-20250929"
                else
                    log_info "Models will use TaskMaster defaults"
                    log_info "Run 'task-master models --setup' later to configure"
                fi
            fi
        fi
    fi

    # Initialize OpenSpec if installed
    if command -v openspec >/dev/null 2>&1; then
        if [[ ! -d "openspec" ]] || [[ -z "$(ls -A openspec 2>/dev/null)" ]]; then
            log_info "Initializing OpenSpec in project..."

            # Run openspec init with piped input for non-interactive mode (claude only)
            # The 'echo' provides the Enter keystroke needed by openspec init
            if echo | openspec init --tools claude >/dev/null 2>&1; then
                log_success "OpenSpec initialized"
            else
                # Fallback: manual initialization
                mkdir -p openspec/specs openspec/changes/archive
                cat > openspec/project.md << 'EOF'
# Project Overview
<!-- Add your project description here -->
EOF
                log_success "OpenSpec directory created (manual fallback)"
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
    echo "     ${YELLOW}Note:${NC} For large PRDs (>25K tokens), the hook will automatically"
    echo "     guide Claude to use the large-file-reader tool first."
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
