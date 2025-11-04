#!/bin/bash
# =============================================================================
# Task Master Wrapper Installation Script
# =============================================================================
#
# This script installs a wrapper for task-master that:
# - Blocks: parse-prd (use PRD-to-Tasks skill for large PRDs)
# - Allows: analyze-complexity, expand, and all other commands
#
# Usage:
#   ./bin/install-wrapper.sh
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# =============================================================================
# Installation
# =============================================================================

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                  ║${NC}"
echo -e "${CYAN}║        Task Master Wrapper Installation                         ║${NC}"
echo -e "${CYAN}║                                                                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "This wrapper prevents task-master parse-prd (for large PRDs)"
log_info "while keeping analyze-complexity and expand functional."
echo ""

# Check if task-master is installed
if ! command -v task-master >/dev/null 2>&1; then
    log_error "task-master is not installed"
    log_info "Install it first: npm install -g @anthropic/task-master"
    exit 1
fi

log_success "task-master is installed"

# Check if wrapper exists
if [ ! -f "${SCRIPT_DIR}/task-master" ]; then
    log_error "Wrapper script not found at ${SCRIPT_DIR}/task-master"
    exit 1
fi

log_success "Wrapper script found"

# Make wrapper executable
chmod +x "${SCRIPT_DIR}/task-master"
log_success "Wrapper is executable"

# Detect shell configuration file
SHELL_CONFIG=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_CONFIG="$HOME/.bash_profile"
    fi
fi

echo ""
echo -e "${CYAN}Installation Options:${NC}"
echo ""
echo "  ${CYAN}1${NC}) Add to PATH (Recommended)"
echo "     Adds ${SCRIPT_DIR} to your PATH in ${SHELL_CONFIG}"
echo ""
echo "  ${CYAN}2${NC}) Create alias"
echo "     Creates an alias in ${SHELL_CONFIG}"
echo ""
echo "  ${CYAN}3${NC}) Manual installation"
echo "     Show instructions for manual setup"
echo ""
echo "  ${CYAN}4${NC}) Skip"
echo "     Exit without installing"
echo ""

read -p "Choose option [1-4] (default: 1): " choice
choice=${choice:-1}

case $choice in
    1)
        # Add to PATH
        if [ -z "$SHELL_CONFIG" ]; then
            log_error "Could not detect shell configuration file"
            log_info "Please add manually: export PATH=\"${SCRIPT_DIR}:\$PATH\""
            exit 1
        fi

        # Check if already in PATH
        if grep -q "${SCRIPT_DIR}" "$SHELL_CONFIG" 2>/dev/null; then
            log_warning "PATH already contains ${SCRIPT_DIR}"
        else
            echo "" >> "$SHELL_CONFIG"
            echo "# Task Master wrapper for claude-dev-pipeline" >> "$SHELL_CONFIG"
            echo "export PATH=\"${SCRIPT_DIR}:\$PATH\"" >> "$SHELL_CONFIG"
            log_success "Added to PATH in ${SHELL_CONFIG}"
        fi

        echo ""
        log_info "Reload your shell to activate:"
        echo "  source ${SHELL_CONFIG}"
        ;;

    2)
        # Create alias
        if [ -z "$SHELL_CONFIG" ]; then
            log_error "Could not detect shell configuration file"
            exit 1
        fi

        # Check if alias already exists
        if grep -q "alias task-master=" "$SHELL_CONFIG" 2>/dev/null; then
            log_warning "Alias already exists in ${SHELL_CONFIG}"
        else
            echo "" >> "$SHELL_CONFIG"
            echo "# Task Master wrapper for claude-dev-pipeline" >> "$SHELL_CONFIG"
            echo "alias task-master='${SCRIPT_DIR}/task-master'" >> "$SHELL_CONFIG"
            log_success "Alias created in ${SHELL_CONFIG}"
        fi

        echo ""
        log_info "Reload your shell to activate:"
        echo "  source ${SHELL_CONFIG}"
        ;;

    3)
        # Manual installation
        echo ""
        log_info "Manual installation instructions:"
        echo ""
        echo "  Add this line to your shell configuration file:"
        echo ""
        echo "    export PATH=\"${SCRIPT_DIR}:\$PATH\""
        echo ""
        echo "  Or create an alias:"
        echo ""
        echo "    alias task-master='${SCRIPT_DIR}/task-master'"
        echo ""
        echo "  Then reload your shell:"
        echo ""
        echo "    source ~/.zshrc  # or ~/.bashrc"
        ;;

    4)
        log_info "Skipping installation"
        exit 0
        ;;

    *)
        log_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Wrapper Installation Complete!                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Testing:${NC}"
echo ""
echo "  After reloading your shell, verify the wrapper:"
echo ""
echo "  ${YELLOW}# This should be BLOCKED:${NC}"
echo "  task-master parse-prd docs/PRD.md"
echo ""
echo "  ${GREEN}# These should WORK:${NC}"
echo "  task-master analyze-complexity --research"
echo "  task-master expand --id=1 --research"
echo "  task-master list"
echo ""

echo -e "${CYAN}Documentation:${NC}"
echo "  See ${SCRIPT_DIR}/README.md for full usage instructions"
echo ""
