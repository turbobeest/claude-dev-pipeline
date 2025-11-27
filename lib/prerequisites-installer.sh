#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Prerequisites Checker & Auto-Installer
# =============================================================================
#
# Verifies and installs prerequisites for the pipeline:
# - Claude Code
# - Git
# - Bash 3.2+
# - jq
# - TaskMaster
# - OpenSpec
#
# Usage:
#   ./lib/prerequisites-installer.sh
#   ./lib/prerequisites-installer.sh --check-only
#   ./lib/prerequisites-installer.sh --install <tool>
#   ./lib/prerequisites-installer.sh --fix-all
#
# =============================================================================

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Configuration
CHECK_ONLY=false
INSTALL_TOOL=""
FIX_ALL=false
VERBOSE=false

# Status tracking
ISSUES_FOUND=0
ISSUES_FIXED=0

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
    echo -e "\n${BLUE}==>${NC} $*"
}

# =============================================================================
# Version Comparison
# =============================================================================

version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

version_ge() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" = "$2"
}

# =============================================================================
# Claude Code Verification
# =============================================================================

check_claude_code() {
    log_step "Checking Claude Code..."

    if command -v claude >/dev/null 2>&1; then
        local version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Claude Code installed: v${version}"
        return 0
    else
        log_error "Claude Code not found"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

install_claude_code() {
    log_warning "Claude Code must be installed manually"
    echo ""
    echo "  Install Claude Code from:"
    echo "  https://claude.ai/download"
    echo ""
    echo "  Or via Homebrew (macOS):"
    echo "  brew install --cask claude"
    echo ""
}

# =============================================================================
# Git Verification
# =============================================================================

check_git() {
    log_step "Checking Git..."

    if command -v git >/dev/null 2>&1; then
        local version=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Git installed: v${version}"
        return 0
    else
        log_error "Git not found"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

install_git() {
    log_step "Installing Git..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew >/dev/null 2>&1; then
            log_info "Installing Git via Homebrew..."
            brew install git
            log_success "Git installed successfully"
            ISSUES_FIXED=$((ISSUES_FIXED + 1))
        else
            log_warning "Homebrew not found. Installing via Xcode Command Line Tools..."
            xcode-select --install
            log_info "Please complete the Xcode installation and run this script again"
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get >/dev/null 2>&1; then
            log_info "Installing Git via apt..."
            sudo apt-get update && sudo apt-get install -y git
            log_success "Git installed successfully"
            ISSUES_FIXED=$((ISSUES_FIXED + 1))
        elif command -v yum >/dev/null 2>&1; then
            log_info "Installing Git via yum..."
            sudo yum install -y git
            log_success "Git installed successfully"
            ISSUES_FIXED=$((ISSUES_FIXED + 1))
        else
            log_error "Unsupported package manager. Please install Git manually."
        fi
    else
        log_error "Unsupported OS. Please install Git manually."
    fi
}

# =============================================================================
# Bash Verification
# =============================================================================

check_bash() {
    log_step "Checking Bash..."

    local bash_version=$(bash --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local required_version="3.2.0"

    if version_ge "$bash_version" "$required_version"; then
        log_success "Bash installed: v${bash_version} (>= ${required_version})"
        return 0
    else
        log_error "Bash v${bash_version} is too old (need >= ${required_version})"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

install_bash() {
    log_warning "Bash 3.2+ is typically pre-installed on macOS and Linux"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "macOS ships with Bash 3.2. For a newer version:"
        echo ""
        echo "  brew install bash"
        echo ""
        echo "  Note: The pipeline works fine with Bash 3.2"
    fi
}

# =============================================================================
# jq Verification
# =============================================================================

check_jq() {
    log_step "Checking jq..."

    if command -v jq >/dev/null 2>&1; then
        local version=$(jq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        log_success "jq installed: v${version}"
        return 0
    else
        log_error "jq not found"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

install_jq() {
    log_step "Installing jq..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew >/dev/null 2>&1; then
            log_info "Installing jq via Homebrew..."
            brew install jq
            log_success "jq installed successfully"
            ISSUES_FIXED=$((ISSUES_FIXED + 1))
        else
            log_error "Homebrew not found. Please install Homebrew first:"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get >/dev/null 2>&1; then
            log_info "Installing jq via apt..."
            sudo apt-get update && sudo apt-get install -y jq
            log_success "jq installed successfully"
            ISSUES_FIXED=$((ISSUES_FIXED + 1))
        elif command -v yum >/dev/null 2>&1; then
            log_info "Installing jq via yum..."
            sudo yum install -y jq
            log_success "jq installed successfully"
            ISSUES_FIXED=$((ISSUES_FIXED + 1))
        else
            log_error "Unsupported package manager. Please install jq manually."
        fi
    else
        log_error "Unsupported OS. Please install jq manually."
    fi
}

# =============================================================================
# TaskMaster Verification
# =============================================================================

check_taskmaster() {
    log_step "Checking TaskMaster..."

    if command -v task-master >/dev/null 2>&1; then
        local version=$(task-master --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        log_success "TaskMaster installed: v${version}"
        return 0
    else
        log_error "TaskMaster not found"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

install_taskmaster() {
    log_step "Installing TaskMaster..."

    local install_dir="${HOME}/.local/bin"
    local taskmaster_url="https://github.com/anthropics/taskmaster/releases/latest/download/task-master"

    # Create install directory if it doesn't exist
    mkdir -p "$install_dir"

    # Detect OS and architecture
    local os="unknown"
    local arch="unknown"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        os="darwin"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os="linux"
    fi

    case $(uname -m) in
        x86_64)
            arch="amd64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
    esac

    # Adjust URL based on OS/arch (this is a placeholder - adjust for actual TaskMaster releases)
    taskmaster_url="https://github.com/anthropics/taskmaster/releases/latest/download/task-master-${os}-${arch}"

    log_info "Downloading TaskMaster from GitHub..."

    if curl -fsSL "$taskmaster_url" -o "${install_dir}/task-master" 2>/dev/null; then
        chmod +x "${install_dir}/task-master"

        # Add to PATH if not already there
        if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
            log_info "Adding ${install_dir} to PATH..."

            # Determine shell config file
            local shell_config=""
            if [[ -n "${BASH_VERSION:-}" ]]; then
                shell_config="${HOME}/.bashrc"
            elif [[ -n "${ZSH_VERSION:-}" ]]; then
                shell_config="${HOME}/.zshrc"
            fi

            if [[ -n "$shell_config" ]]; then
                echo "export PATH=\"${install_dir}:\$PATH\"" >> "$shell_config"
                log_info "Added to $shell_config (restart shell or run: source $shell_config)"
            fi
        fi

        log_success "TaskMaster installed successfully to ${install_dir}/task-master"
        ISSUES_FIXED=$((ISSUES_FIXED + 1))

        # Verify installation
        if "${install_dir}/task-master" --version >/dev/null 2>&1; then
            log_success "TaskMaster verified"
        else
            log_warning "TaskMaster installed but may need configuration"
        fi
    else
        log_error "Failed to download TaskMaster"
        echo ""
        echo "  Manual installation:"
        echo "  1. Download from: https://github.com/anthropics/taskmaster"
        echo "  2. Place in ${install_dir}/task-master"
        echo "  3. Run: chmod +x ${install_dir}/task-master"
        echo ""
    fi
}

# =============================================================================
# OpenSpec Verification
# =============================================================================

check_openspec() {
    log_step "Checking OpenSpec..."

    if command -v openspec >/dev/null 2>&1; then
        local version=$(openspec --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        log_success "OpenSpec installed: v${version}"
        return 0
    else
        log_error "OpenSpec not found"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

install_openspec() {
    log_step "Installing OpenSpec..."

    local install_dir="${HOME}/.local/bin"

    # Create install directory if it doesn't exist
    mkdir -p "$install_dir"

    # Check if npm is available (OpenSpec might be an npm package)
    if command -v npm >/dev/null 2>&1; then
        log_info "Installing OpenSpec via npm..."
        npm install -g @fission-ai/openspec@latest 2>/dev/null || {
            log_warning "Global npm install failed, trying local installation..."
            npm install --prefix "$HOME/.local" @fission-ai/openspec@latest

            # Create symlink
            ln -sf "${HOME}/.local/node_modules/.bin/openspec" "${install_dir}/openspec"
        }

        log_success "OpenSpec installed successfully"
        ISSUES_FIXED=$((ISSUES_FIXED + 1))
    else
        log_error "npm not found - required for OpenSpec installation"
        echo ""
        echo "  Install Node.js and npm first:"
        echo "  macOS:  brew install node"
        echo "  Linux:  sudo apt-get install nodejs npm"
        echo ""
        echo "  Then run this script again"
        echo ""
    fi
}

# =============================================================================
# Main Verification Function
# =============================================================================

verify_all() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Claude Dev Pipeline - Prerequisites Check                    ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Run all checks
    check_claude_code || true
    check_git || true
    check_bash || true
    check_jq || true
    check_taskmaster || true
    check_openspec || true

    # Summary
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Summary                                                       ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ $ISSUES_FOUND -eq 0 ]]; then
        log_success "All prerequisites are installed and configured correctly!"
        echo ""
        return 0
    else
        log_warning "Found ${ISSUES_FOUND} missing or outdated prerequisite(s)"
        echo ""

        if [[ "$CHECK_ONLY" == "true" ]]; then
            echo "Run without --check-only to auto-install missing prerequisites:"
            echo "  ./lib/prerequisites-installer.sh --fix-all"
        else
            echo "Run with --fix-all to automatically install all missing prerequisites:"
            echo "  ./lib/prerequisites-installer.sh --fix-all"
        fi
        echo ""
        return 1
    fi
}

# =============================================================================
# Auto-Fix Function
# =============================================================================

fix_all() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Claude Dev Pipeline - Auto-Fix Prerequisites                  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check and install each prerequisite
    check_claude_code || install_claude_code
    check_git || install_git
    check_bash || install_bash
    check_jq || install_jq
    check_taskmaster || install_taskmaster
    check_openspec || install_openspec

    # Summary
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Auto-Fix Summary                                              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ $ISSUES_FIXED -gt 0 ]]; then
        log_success "Automatically fixed ${ISSUES_FIXED} issue(s)"
    fi

    if [[ $ISSUES_FOUND -gt $ISSUES_FIXED ]]; then
        log_warning "$((ISSUES_FOUND - ISSUES_FIXED)) issue(s) require manual installation"
    fi

    echo ""
    log_info "Run verification again to check status:"
    echo "  ./lib/prerequisites-installer.sh"
    echo ""
}

# =============================================================================
# Usage Information
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Verify and install prerequisites for Claude Dev Pipeline.

Options:
    --check-only        Only check prerequisites, don't install
    --fix-all           Automatically install all missing prerequisites
    --install <tool>    Install specific tool (git, jq, taskmaster, openspec)
    --verbose           Show detailed output
    -h, --help          Show this help message

Examples:
    # Check all prerequisites
    ./lib/prerequisites-installer.sh

    # Check without installing
    ./lib/prerequisites-installer.sh --check-only

    # Auto-install all missing prerequisites
    ./lib/prerequisites-installer.sh --fix-all

    # Install specific tool
    ./lib/prerequisites-installer.sh --install jq

Prerequisites:
    - Claude Code        (manual installation)
    - Git               (auto-install available)
    - Bash 3.2+         (typically pre-installed)
    - jq                (auto-install available)
    - TaskMaster        (auto-install available)
    - OpenSpec          (auto-install available)

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-only)
                CHECK_ONLY=true
                shift
                ;;
            --fix-all)
                FIX_ALL=true
                shift
                ;;
            --install)
                INSTALL_TOOL="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    parse_args "$@"

    if [[ "$FIX_ALL" == "true" ]]; then
        fix_all
    elif [[ -n "$INSTALL_TOOL" ]]; then
        case "$INSTALL_TOOL" in
            git)
                install_git
                ;;
            jq)
                install_jq
                ;;
            taskmaster)
                install_taskmaster
                ;;
            openspec)
                install_openspec
                ;;
            *)
                log_error "Unknown tool: $INSTALL_TOOL"
                echo "Available tools: git, jq, taskmaster, openspec"
                exit 1
                ;;
        esac
    else
        verify_all
    fi
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
