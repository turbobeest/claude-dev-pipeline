#!/bin/bash
# =============================================================================
# Claude Code Development Pipeline Installer
# =============================================================================
# 
# Automated installation of the complete development pipeline including:
# - TaskMaster
# - OpenSpec
# - Pipeline Skills (PRD-to-Tasks, Coupling Analysis, Test Strategy, Integration Validator)
# - Hooks (Skill Activation, Workflow Tracker, TDD Enforcer)
# - Configuration files
# - Documentation
#
# Usage:
#   ./install-pipeline.sh [OPTIONS]
#
# Options:
#   --global           Install skills globally (~/.claude/skills)
#   --project          Install skills in project (.claude/skills) [DEFAULT]
#   --no-hooks         Skip hooks installation
#   --no-tools         Skip TaskMaster/OpenSpec installation
#   --github-org       GitHub org/user for pipeline repo [default: YOUR_ORG]
#   --github-repo      Repository name [default: claude-dev-pipeline]
#   --branch           Branch to use [default: main]
#   -h, --help         Show this help message
#
# Examples:
#   ./install-pipeline.sh                    # Full install (project skills)
#   ./install-pipeline.sh --global           # Full install (global skills)
#   ./install-pipeline.sh --no-hooks         # Install without hooks
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Default values
INSTALL_LOCATION="project"  # "global" or "project"
INSTALL_HOOKS=true
INSTALL_TOOLS=true
GITHUB_ORG="YOUR_ORG"
GITHUB_REPO="claude-dev-pipeline"
GITHUB_BRANCH="main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

log_info "Starting pre-flight checks..."

# Check required commands
REQUIRED_COMMANDS=("git" "curl" "jq" "node" "npm")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        log_error "Missing required command: $cmd"
        exit 1
    fi
done

log_success "All required commands available"

# Check if in git repository (for project install)
if [ "$INSTALL_LOCATION" = "project" ]; then
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository. Run 'git init' first or use --global"
        exit 1
    fi
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
    log_info "Installing in project: $PROJECT_ROOT"
else
    log_info "Installing globally in ~/.claude"
fi

# =============================================================================
# Determine Installation Paths
# =============================================================================

if [ "$INSTALL_LOCATION" = "global" ]; then
    SKILLS_DIR="$HOME/.claude/skills"
    HOOKS_DIR="$HOME/.claude/hooks"
    SETTINGS_FILE="$HOME/.claude/settings.json"
else
    SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
    HOOKS_DIR="$PROJECT_ROOT/.claude/hooks"
    SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"
fi

log_info "Skills directory: $SKILLS_DIR"
log_info "Hooks directory: $HOOKS_DIR"

# =============================================================================
# Create Temporary Working Directory
# =============================================================================

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log_info "Created temporary directory: $TEMP_DIR"

# =============================================================================
# Download Pipeline Files from GitHub
# =============================================================================

log_info "Downloading pipeline files from GitHub..."

GITHUB_BASE_URL="https://raw.githubusercontent.com/$GITHUB_ORG/$GITHUB_REPO/$GITHUB_BRANCH"

# Create directory structure in temp
mkdir -p "$TEMP_DIR"/{skills,hooks,docs}

# Download skills
log_info "Downloading skills..."
SKILLS=("prd-to-tasks" "coupling-analysis" "test-strategy-generator" "integration-validator")

for skill in "${SKILLS[@]}"; do
    log_info "  - $skill"
    mkdir -p "$TEMP_DIR/skills/$skill"
    
    # Download SKILL.md
    if curl -fsSL "$GITHUB_BASE_URL/skills/$skill/SKILL.md" -o "$TEMP_DIR/skills/$skill/SKILL.md"; then
        log_success "    Downloaded SKILL.md"
    else
        log_error "    Failed to download SKILL.md"
        exit 1
    fi
    
    # Download examples if they exist
    if curl -fsSL "$GITHUB_BASE_URL/skills/$skill/examples/example.md" -o "$TEMP_DIR/skills/$skill/examples/example.md" 2>/dev/null; then
        log_success "    Downloaded examples"
    fi
done

# Download hooks
if [ "$INSTALL_HOOKS" = true ]; then
    log_info "Downloading hooks..."
    HOOKS=("skill-activation-prompt.sh" "post-tool-use-tracker.sh" "pre-implementation-validator.sh")
    
    for hook in "${HOOKS[@]}"; do
        log_info "  - $hook"
        if curl -fsSL "$GITHUB_BASE_URL/hooks/$hook" -o "$TEMP_DIR/hooks/$hook"; then
            chmod +x "$TEMP_DIR/hooks/$hook"
            log_success "    Downloaded and made executable"
        else
            log_error "    Failed to download $hook"
            exit 1
        fi
    done
fi

# Download configuration files
log_info "Downloading configuration files..."

if curl -fsSL "$GITHUB_BASE_URL/config/skill-rules.json" -o "$TEMP_DIR/skill-rules.json"; then
    log_success "  - skill-rules.json"
else
    log_error "  Failed to download skill-rules.json"
    exit 1
fi

if [ "$INSTALL_HOOKS" = true ]; then
    if curl -fsSL "$GITHUB_BASE_URL/config/settings.json" -o "$TEMP_DIR/settings.json"; then
        log_success "  - settings.json"
    else
        log_warning "  settings.json not found, will generate"
    fi
fi

# Download documentation
log_info "Downloading documentation..."
DOCS=("PIPELINE_SETUP.md" "DEVELOPMENT_WORKFLOW.md" "TROUBLESHOOTING.md")

for doc in "${DOCS[@]}"; do
    if curl -fsSL "$GITHUB_BASE_URL/docs/$doc" -o "$TEMP_DIR/docs/$doc" 2>/dev/null; then
        log_success "  - $doc"
    else
        log_warning "  $doc not found"
    fi
done

# =============================================================================
# Install Skills
# =============================================================================

log_info "Installing skills to $SKILLS_DIR..."

mkdir -p "$SKILLS_DIR"

for skill in "${SKILLS[@]}"; do
    log_info "  Installing $skill..."
    
    # Remove existing if present
    if [ -d "$SKILLS_DIR/$skill" ]; then
        log_warning "    Removing existing $skill"
        rm -rf "$SKILLS_DIR/$skill"
    fi
    
    # Copy skill
    cp -r "$TEMP_DIR/skills/$skill" "$SKILLS_DIR/"
    log_success "    Installed $skill"
done

# Copy skill-rules.json
if [ "$INSTALL_LOCATION" = "project" ]; then
    cp "$TEMP_DIR/skill-rules.json" "$PROJECT_ROOT/.claude/"
    log_success "Installed skill-rules.json"
else
    cp "$TEMP_DIR/skill-rules.json" "$HOME/.claude/"
    log_success "Installed skill-rules.json"
fi

# =============================================================================
# Install Hooks
# =============================================================================

if [ "$INSTALL_HOOKS" = true ]; then
    log_info "Installing hooks to $HOOKS_DIR..."
    
    mkdir -p "$HOOKS_DIR"
    
    for hook in "${HOOKS[@]}"; do
        log_info "  Installing $hook..."
        cp "$TEMP_DIR/hooks/$hook" "$HOOKS_DIR/"
        chmod +x "$HOOKS_DIR/$hook"
        log_success "    Installed $hook"
    done
    
    # Update settings.json
    log_info "Configuring settings.json..."
    
    if [ -f "$SETTINGS_FILE" ]; then
        log_warning "  settings.json exists, backing up to settings.json.backup"
        cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    fi
    
    # Generate or merge settings.json
    if [ -f "$TEMP_DIR/settings.json" ]; then
        cp "$TEMP_DIR/settings.json" "$SETTINGS_FILE"
        log_success "  Installed settings.json"
    else
        log_info "  Generating settings.json..."
        cat > "$SETTINGS_FILE" << 'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
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
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/pre-implementation-validator.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Create",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/pre-implementation-validator.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF
        log_success "  Generated settings.json"
    fi
fi

# =============================================================================
# Install Tools (TaskMaster & OpenSpec)
# =============================================================================

if [ "$INSTALL_TOOLS" = true ]; then
    log_info "Installing development tools..."
    
    # Install TaskMaster
    log_info "  Installing TaskMaster..."
    if [ -d "$HOME/.taskmaster" ]; then
        log_warning "    TaskMaster already installed, skipping"
    else
        git clone https://github.com/eyaltoledano/claude-task-master.git "$TEMP_DIR/taskmaster"
        cd "$TEMP_DIR/taskmaster"
        npm install -g .
        cd -
        log_success "    Installed TaskMaster"
    fi
    
    # Install OpenSpec
    log_info "  Installing OpenSpec..."
    if [ -d "$HOME/.openspec" ]; then
        log_warning "    OpenSpec already installed, skipping"
    else
        git clone https://github.com/Fission-AI/OpenSpec.git "$TEMP_DIR/openspec"
        cd "$TEMP_DIR/openspec"
        npm install -g .
        cd -
        log_success "    Installed OpenSpec"
    fi
fi

# =============================================================================
# Initialize Project Structure
# =============================================================================

if [ "$INSTALL_LOCATION" = "project" ]; then
    log_info "Initializing project structure..."
    
    # Create required directories
    mkdir -p "$PROJECT_ROOT"/{docs,.openspec,.taskmaster,tests}
    
    # Initialize TaskMaster
    if [ "$INSTALL_TOOLS" = true ]; then
        cd "$PROJECT_ROOT"
        if [ ! -f ".taskmaster/tasks.json" ]; then
            log_info "  Initializing TaskMaster..."
            task-master init || log_warning "    TaskMaster init failed (may already be initialized)"
        fi
        
        # Initialize OpenSpec
        if [ ! -d ".openspec" ]; then
            log_info "  Initializing OpenSpec..."
            openspec init --tools claude || log_warning "    OpenSpec init failed (may already be initialized)"
        fi
    fi
    
    # Create TASKMASTER_OPENSPEC_MAP.md if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/TASKMASTER_OPENSPEC_MAP.md" ]; then
        cat > "$PROJECT_ROOT/TASKMASTER_OPENSPEC_MAP.md" << 'EOF'
# TaskMaster ↔ OpenSpec Mapping

This file tracks the relationship between TaskMaster tasks and OpenSpec proposals.

## Format

```
Task #X: [Task Title]
├─ OpenSpec Proposal: [proposal-id]
├─ Status: [not-started|in-progress|complete]
└─ Notes: [any relevant notes]
```

## Mapping

<!-- Auto-populated during workflow -->
EOF
        log_success "  Created TASKMASTER_OPENSPEC_MAP.md"
    fi
    
    # Create workflow state file
    if [ ! -f "$PROJECT_ROOT/.claude/.workflow-state.json" ]; then
        echo '{"phase":"pre-init","completedTasks":[],"signals":{}}' > "$PROJECT_ROOT/.claude/.workflow-state.json"
        log_success "  Created .workflow-state.json"
    fi
fi

# =============================================================================
# Copy Documentation
# =============================================================================

if [ "$INSTALL_LOCATION" = "project" ]; then
    log_info "Installing documentation..."
    
    mkdir -p "$PROJECT_ROOT/docs/pipeline"
    
    for doc in "${DOCS[@]}"; do
        if [ -f "$TEMP_DIR/docs/$doc" ]; then
            cp "$TEMP_DIR/docs/$doc" "$PROJECT_ROOT/docs/pipeline/"
            log_success "  - $doc"
        fi
    done
fi

# =============================================================================
# Verification
# =============================================================================

log_info "Verifying installation..."

# Check skills
SKILLS_INSTALLED=0
for skill in "${SKILLS[@]}"; do
    if [ -f "$SKILLS_DIR/$skill/SKILL.md" ]; then
        ((SKILLS_INSTALLED++))
    fi
done

if [ $SKILLS_INSTALLED -eq ${#SKILLS[@]} ]; then
    log_success "All $SKILLS_INSTALLED skills installed"
else
    log_error "Only $SKILLS_INSTALLED/${#SKILLS[@]} skills installed"
    exit 1
fi

# Check hooks
if [ "$INSTALL_HOOKS" = true ]; then
    HOOKS_INSTALLED=0
    for hook in "${HOOKS[@]}"; do
        if [ -x "$HOOKS_DIR/$hook" ]; then
            ((HOOKS_INSTALLED++))
        fi
    done
    
    if [ $HOOKS_INSTALLED -eq ${#HOOKS[@]} ]; then
        log_success "All $HOOKS_INSTALLED hooks installed"
    else
        log_error "Only $HOOKS_INSTALLED/${#HOOKS[@]} hooks installed"
        exit 1
    fi
fi

# Check tools
if [ "$INSTALL_TOOLS" = true ]; then
    if command -v task-master &> /dev/null && command -v openspec &> /dev/null; then
        log_success "TaskMaster and OpenSpec installed"
    else
        log_warning "Tools installation may have issues"
    fi
fi

# =============================================================================
# Post-Installation Instructions
# =============================================================================

echo ""
echo "=========================================================================="
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo "=========================================================================="
echo ""
echo -e "${BLUE}Installation Summary:${NC}"
echo "  - Location: $INSTALL_LOCATION"
echo "  - Skills: $SKILLS_DIR"
if [ "$INSTALL_HOOKS" = true ]; then
    echo "  - Hooks: $HOOKS_DIR"
fi
if [ "$INSTALL_TOOLS" = true ]; then
    echo "  - Tools: TaskMaster, OpenSpec"
fi
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Review the pipeline documentation:"
if [ "$INSTALL_LOCATION" = "project" ]; then
    echo "   cat $PROJECT_ROOT/docs/pipeline/PIPELINE_SETUP.md"
else
    echo "   Visit: $GITHUB_BASE_URL/docs/PIPELINE_SETUP.md"
fi
echo ""
echo "2. Verify installation:"
echo "   claude-code"
echo "   # In Claude Code, type: 'what skills do I have?'"
echo ""
echo "3. Test skill activation:"
echo "   # In Claude Code, type: 'Can you help me generate tasks from a PRD?'"
echo "   # Should see: 📋 Relevant Skills Detected: prd-to-tasks"
echo ""
echo "4. Start your first workflow:"
if [ "$INSTALL_LOCATION" = "project" ]; then
    echo "   a. Create docs/PRD.md with your product requirements"
    echo "   b. Run: claude-code"
    echo "   c. Ask: 'Generate tasks.json from the PRD'"
    echo "   d. Follow the automated workflow"
else
    echo "   a. cd to your project"
    echo "   b. Create docs/PRD.md"
    echo "   c. Run: claude-code"
    echo "   d. Ask: 'Generate tasks.json from the PRD'"
fi
echo ""
if [ "$INSTALL_HOOKS" = true ]; then
    echo -e "${YELLOW}⚠️  Hooks are enabled${NC}"
    echo "   - Skills will auto-activate based on context"
    echo "   - Workflow state is tracked automatically"
    echo "   - TDD enforcement is active"
    echo ""
fi
echo -e "${BLUE}Resources:${NC}"
echo "  - TaskMaster: https://github.com/eyaltoledano/claude-task-master"
echo "  - OpenSpec: https://github.com/Fission-AI/OpenSpec"
echo "  - Claude Code Docs: https://docs.claude.com/en/docs/claude-code"
echo ""
echo "=========================================================================="
echo ""

# =============================================================================
# Git Commit (if project installation)
# =============================================================================

if [ "$INSTALL_LOCATION" = "project" ]; then
    log_info "Would you like to commit these changes to git? (y/n)"
    read -r COMMIT_RESPONSE
    
    if [ "$COMMIT_RESPONSE" = "y" ] || [ "$COMMIT_RESPONSE" = "Y" ]; then
        cd "$PROJECT_ROOT"
        git add .claude/ docs/pipeline/ TASKMASTER_OPENSPEC_MAP.md 2>/dev/null || true
        git commit -m "feat: Install Claude Code development pipeline

- Added 4 workflow skills (PRD-to-Tasks, Coupling Analysis, Test Strategy, Integration Validator)
- Added 3 hooks (Skill Activation, Workflow Tracker, TDD Enforcer)
- Initialized TaskMaster and OpenSpec
- Added pipeline documentation

Installed via: install-pipeline.sh"
        log_success "Changes committed to git"
    fi
fi

log_success "Installation complete! 🚀"