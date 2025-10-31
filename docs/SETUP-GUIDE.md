# Claude Dev Pipeline - Complete Setup Guide

## Overview

The Claude Dev Pipeline is a revolutionary codeword-based autonomous development system that transforms Claude Code from "hope skills activate" to guaranteed execution through deterministic skill activation and automatic phase transitions.

This guide will walk you through the complete setup process from scratch.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation Methods](#installation-methods)
3. [Configuration](#configuration)
4. [First Pipeline Run](#first-pipeline-run)
5. [Verification](#verification)
6. [Troubleshooting Setup Issues](#troubleshooting-setup-issues)
7. [Advanced Configuration](#advanced-configuration)

## Prerequisites

### System Requirements

- **Operating System**: macOS, Linux, or Windows with WSL2
- **Shell**: Bash 3.2+ (macOS default bash is supported)
- **Git**: Version 2.20 or higher
- **jq**: JSON processor for configuration handling
- **Claude Code**: Latest version with hooks support

### Required Tools

```bash
# macOS (using Homebrew)
brew install git jq

# Ubuntu/Debian
sudo apt update && sudo apt install git jq

# RHEL/CentOS/Fedora
sudo yum install git jq
# or
sudo dnf install git jq
```

### Directory Permissions

Ensure your user has write permissions to the target directory:

```bash
# Check permissions
ls -la $(dirname $(pwd))

# If needed, fix permissions
chmod 755 /path/to/your/project
```

## Installation Methods

### Method 1: Quick Install (Recommended)

The fastest way to get started:

```bash
# 1. Navigate to your project directory
cd /path/to/your/project

# 2. Download and run the installer
curl -fsSL https://raw.githubusercontent.com/turbobeest/claude-dev-pipeline/deploy/install-pipeline.sh | bash

# 3. Verify installation
ls -la .claude/
```

### Method 2: Manual Installation

For more control over the installation process:

```bash
# 1. Clone the pipeline repository
git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git
cd claude-dev-pipeline

# 2. Navigate to your project
cd /path/to/your/project

# 3. Run the installer with options
bash /path/to/claude-dev-pipeline/install-pipeline.sh --project

# 4. Verify installation
./install-pipeline.sh --verify
```

### Method 3: Local Development Installation

For pipeline development and customization:

```bash
# 1. Clone and enter the pipeline repository
git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git
cd claude-dev-pipeline

# 2. Set up for local development
./setup.sh --dev-mode

# 3. Install to target project
./install-pipeline.sh --local --target /path/to/your/project
```

## Configuration

### Initial Configuration

After installation, configure the pipeline for your project:

```bash
# 1. Review default settings
cat .claude/settings.json

# 2. Configure GitHub integration (optional)
# Create a GitHub Personal Access Token with these permissions:
#   - repo (Full control of private repositories)
#   - read:org (Read org and team membership)
#   - workflow (Update GitHub Action workflows) - if using CI/CD
# Generate at: https://github.com/settings/tokens
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
echo "GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx" >> .env

# 3. Set up project-specific settings
cp .claude/settings.json .claude/settings.local.json
# Edit .claude/settings.local.json as needed
```

### Environment Configuration

Create a `.env` file in your project root:

```bash
# Core Configuration
CLAUDE_PIPELINE_ROOT=/path/to/your/project
CLAUDE_MAIN_BRANCH=main
CLAUDE_ENVIRONMENT=development

# GitHub Integration
GITHUB_ORG=turbobeest
GITHUB_REPO=your-repo
# Personal Access Token with repo, read:org, workflow permissions
# Generate at: https://github.com/settings/tokens
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# TaskMaster Configuration
# Required for TaskMaster GitHub integration
# Needs: repo, project, issues, pull_requests permissions
TASKMASTER_GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
# Or use same token as above if permissions match:
# TASKMASTER_GITHUB_TOKEN=${GITHUB_TOKEN}

# Claude API Configuration (for TaskMaster)
# Get your API key from: https://console.anthropic.com/settings/keys
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxxxxxxxxxx

# Pipeline Settings
AUTOMATION_LEVEL=95
DEBUG_MODE=false
LOG_LEVEL=info

# Worktree Configuration
WORKTREE_CLEANUP_AFTER_MERGE=true
WORKTREE_BACKUP_BEFORE_CLEANUP=true

# Hook Configuration
SKILL_ACTIVATION_DEBUG=false
PHASE_TRANSITION_AUTO=true
MANUAL_GATE_TIMEOUT=1800

# Notification Settings (optional)
SLACK_WEBHOOK_URL=your_webhook_url
EMAIL_NOTIFICATIONS=false
```

### Claude Code Integration

Configure Claude Code to use the pipeline:

```bash
# 1. Verify Claude Code can see the skills
claude --list-skills | grep -E "(PRD_TO_TASKS|PIPELINE_ORCHESTRATION)"

# 2. Test hook integration
echo "test pipeline activation" | claude --debug-hooks

# 3. Verify settings are loaded
claude --show-config | jq '.hooks'
```

## Operating the Pipeline

Once installation and setup are complete, here's how to use the autonomous development system:

### Understanding the Workflow

The pipeline operates in 6 automated phases:
1. **Requirements Analysis** - Transforms your PRD into actionable tasks
2. **Specification Generation** - Creates technical specs and test plans
3. **Implementation** - Develops code using TDD methodology
4. **Integration Testing** - Validates component interactions
5. **E2E Validation** - Tests complete user workflows
6. **Deployment** - Orchestrates production rollout

### Starting Development

#### Option 1: Natural Language Activation
Simply describe what you want in Claude Code:
```
"I have a PRD ready, please begin the automated development pipeline"
"Start building the application from my requirements document"
"Begin full stack development from PRD.md"
```

#### Option 2: Direct Phase Activation
Target specific phases when needed:
```
"Generate tasks from my PRD" → Activates Phase 1
"Create OpenSpec proposals" → Activates Phase 2
"Begin TDD implementation" → Activates Phase 3
"Run integration tests" → Activates Phase 4
"Validate E2E workflows" → Activates Phase 5
"Deploy to production" → Activates Phase 6
```

### Managing the Pipeline

#### Monitor Progress
```bash
# Check current phase
echo "What's the pipeline status?" | claude

# View workflow state
cat .claude/.workflow-state.json | jq '.phase'

# List active worktrees
git worktree list
```

#### Handle Decision Points
The system requires approval at 3 strategic points:

1. **Before Starting** (Phase 0→1)
   ```
   "Yes, start the pipeline"
   "Proceed with task decomposition"
   ```

2. **Before Implementation** (Phase 2→3)
   ```
   "Approve implementation"
   "Specs look good, begin coding"
   ```

3. **Before Deployment** (Phase 5→6)
   ```
   "GO for production"
   "Approved for deployment"
   ```

#### Interrupt or Modify
```
"Pause the pipeline" - Stops at current phase
"Skip to integration testing" - Jumps to Phase 4
"Restart from specifications" - Returns to Phase 2
```

### Typical Development Session

1. **Prepare Requirements**
   ```bash
   # Create or update your PRD
   vim PRD.md
   # Or copy existing requirements
   cp ~/requirements/project-spec.md PRD.md
   ```

2. **Launch Pipeline**
   ```
   "I've prepared the PRD, start the full development pipeline"
   ```

3. **Monitor Autonomous Progress**
   - Watch as tasks are generated (Phase 1)
   - Review specifications being created (Phase 2)
   - Observe TDD implementation (Phase 3)
   - See integration tests run (Phase 4)
   - View E2E validation (Phase 5)

4. **Approve at Gates**
   - Confirm when prompted at decision points
   - Review outputs before approving next phase

5. **Deployment Decision**
   - Review test results and validation reports
   - Make GO/NO-GO decision for production

### Working with Results

Each phase produces specific outputs:

- **Phase 1**: `tasks.json`, dependency analysis
- **Phase 2**: `.openspec/proposals/*.md`, test strategies
- **Phase 3**: Source code in worktrees, unit tests
- **Phase 4**: Integration test results
- **Phase 5**: E2E test reports, validation scores
- **Phase 6**: Deployment logs, rollback plans

Access outputs:
```bash
# View tasks
cat .taskmaster/tasks.json | jq

# Check specifications
ls .openspec/proposals/

# Review test results
cat .claude/test-results/phase-*.json

# See deployment status
cat .claude/deployment/status.json
```

## First Pipeline Run

Create a Product Requirements Document:

```bash
# Create a PRD file
cat > PRD.md << 'EOF'
# Sample Product Requirements Document

## Project Overview
Build a simple calculator web application.

## Features
1. Basic arithmetic operations (+, -, *, /)
2. Clear button functionality
3. Responsive design
4. Input validation

## Technical Requirements
- Frontend: HTML, CSS, JavaScript
- No external dependencies
- Mobile-friendly interface

## Acceptance Criteria
- Calculator performs accurate arithmetic
- All buttons are functional
- Interface is responsive
- Input validation prevents errors
EOF
```

### Step 2: Initialize the Pipeline

Start the automated development process:

```bash
# Method 1: Direct activation
echo "I've completed my PRD, begin automated development" | claude

# Method 2: Explicit pipeline start
echo "Start the Claude Dev Pipeline for this project" | claude

# Method 3: Manual activation (for testing)
echo "[ACTIVATE:PIPELINE_ORCHESTRATION_V1]" | claude
```

### Step 3: Monitor Progress

Track the pipeline execution:

```bash
# Check pipeline status
cat .claude/.workflow-state.json | jq '.current_phase'

# Monitor logs
tail -f .claude/logs/pipeline.log

# Check active worktree
./lib/worktree-manager.sh status
```

### Step 4: Approve Manual Gates

The pipeline has three manual approval gates:

1. **Pipeline Start** - Confirm readiness to begin
2. **Implementation Start** - Approve moving from specs to code  
3. **Production Deployment** - GO/NO-GO decision

When prompted, approve transitions:

```bash
# When you see approval prompts, respond with:
echo "approve" | claude
# or
echo "proceed with implementation" | claude
```

## Verification

### Test 1: Installation Verification

```bash
# Check all components are installed
ls -la .claude/
echo "Expected directories: skills/ hooks/ lib/"

# Verify skills are present
ls .claude/skills/ | wc -l
echo "Expected: 10 skills"

# Check hooks are executable
ls -la .claude/hooks/*.sh | grep rwx
echo "All hooks should be executable"
```

### Test 2: Configuration Verification

```bash
# Validate JSON configuration
jq . .claude/settings.json >/dev/null && echo "settings.json is valid"
jq . .claude/skill-rules.json >/dev/null && echo "skill-rules.json is valid"

# Check environment variables
env | grep CLAUDE_ | sort
```

### Test 3: Skill Activation Test

```bash
# Test codeword injection
echo "Can you generate tasks from this PRD?" | claude --debug
# Look for: [ACTIVATE:PRD_TO_TASKS_V1] in output

# Test phase transition
echo '{"tasks":[]}' > tasks.json
# Should trigger: [SIGNAL:PHASE1_START]
```

### Test 4: Worktree Functionality

```bash
# Test worktree creation
./lib/worktree-manager.sh create 1 1
./lib/worktree-manager.sh status

# Test worktree cleanup
./lib/worktree-manager.sh cleanup 1 1
```

### Test 5: State Management

```bash
# Test state operations
./lib/state-manager.sh init
./lib/state-manager.sh read
./lib/state-manager.sh validate
./lib/state-manager.sh backup "test-backup"
```

## Troubleshooting Setup Issues

### Common Installation Problems

#### Problem: Permission Denied

```bash
# Symptoms
chmod: .claude/hooks/*.sh: Permission denied

# Solution
sudo chown -R $(whoami) .claude/
chmod -R 755 .claude/
chmod +x .claude/hooks/*.sh
```

#### Problem: jq Command Not Found

```bash
# Symptoms
./install-pipeline.sh: line 123: jq: command not found

# Solution (macOS)
brew install jq

# Solution (Ubuntu/Debian)
sudo apt install jq

# Solution (Manual)
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
sudo mv jq-linux64 /usr/local/bin/jq
sudo chmod +x /usr/local/bin/jq
```

#### Problem: Git Worktree Errors

```bash
# Symptoms
fatal: 'worktrees/phase-1-task-1' already exists

# Solution
./lib/worktree-manager.sh cleanup-all
git worktree prune
```

#### Problem: Claude Code Not Recognizing Skills

```bash
# Symptoms
No skills found with activation code: PRD_TO_TASKS_V1

# Diagnostic
claude --list-skills | grep PRD_TO_TASKS
ls -la .claude/skills/*/SKILL.md

# Solution
# Verify SKILL.md format:
head -5 .claude/skills/prd-to-tasks/SKILL.md
# Should contain: activation_code: PRD_TO_TASKS_V1

# Restart Claude Code
killall claude-code 2>/dev/null || true
claude --reload-skills
```

#### Problem: Hooks Not Executing

```bash
# Symptoms
echo "generate tasks" | claude
# No [ACTIVATE:...] codewords appear

# Diagnostic
cat .claude/settings.json | jq '.hooks'
ls -la .claude/hooks/

# Solution
chmod +x .claude/hooks/*.sh
# Verify hook configuration
jq '.hooks' .claude/settings.json
```

### Configuration Issues

#### Problem: Invalid JSON Configuration

```bash
# Symptoms
Error: Invalid JSON in skill-rules.json

# Diagnostic
jq . .claude/skill-rules.json

# Solution
# Fix JSON syntax, common issues:
# - Missing commas
# - Trailing commas
# - Unquoted keys
# - Mismatched brackets

# Validate fix
jq . .claude/skill-rules.json >/dev/null && echo "Fixed!"
```

#### Problem: Environment Variables Not Loading

```bash
# Symptoms
Pipeline uses default values instead of .env settings

# Solution
# Check .env file location and format
cat .env | grep -v '^#' | grep '='

# Source manually for testing
source .env
env | grep CLAUDE_
```

### Performance Issues

#### Problem: Slow Pipeline Execution

```bash
# Diagnostic
time ./lib/state-manager.sh read
time ./lib/lock-manager.sh acquire test 5

# Common causes and solutions:
# 1. Network latency (use --local for development)
# 2. Large git repository (use .gitignore for node_modules, etc.)
# 3. Insufficient disk space (check df -h)
# 4. Too many backup files (clean old backups)

# Cleanup old backups
find .claude/.state-backups -name "*.json" -mtime +7 -delete
```

## Advanced Configuration

### Custom Skill Configuration

Modify skill activation patterns:

```bash
# Edit skill rules
cp .claude/skill-rules.json .claude/skill-rules.local.json

# Add custom trigger patterns
jq '.skills[0].trigger_conditions.user_patterns += ["custom pattern"]' \
   .claude/skill-rules.local.json > temp.json && mv temp.json .claude/skill-rules.local.json
```

### Hook Customization

Create custom hook behaviors:

```bash
# Create custom hook
cp .claude/hooks/skill-activation-prompt.sh .claude/hooks/skill-activation-prompt.custom.sh

# Modify for your needs
# Edit the custom file

# Update settings to use custom hook
jq '.hooks.UserPromptSubmit.script = "skill-activation-prompt.custom.sh"' \
   .claude/settings.json > temp.json && mv temp.json .claude/settings.json
```

### Development Mode Setup

For pipeline development:

```bash
# Enable debug mode
export DEBUG_MODE=true
export SKILL_ACTIVATION_DEBUG=true
export LOG_LEVEL=debug

# Use local pipeline
./install-pipeline.sh --local --dev-mode

# Monitor debug logs
tail -f .claude/logs/debug.log
```

### Security Configuration

Secure your pipeline installation:

```bash
# Set secure file permissions
chmod 600 .env
chmod 600 .claude/settings.json
chmod 750 .claude/
chmod 700 .claude/.state-backups/

# Audit file permissions
find .claude -type f -exec ls -la {} \; | grep -v '^-rw-------'
```

## Next Steps

After successful setup:

1. **Read the Architecture Guide**: [docs/ARCHITECTURE.md](ARCHITECTURE.md)
2. **Understand Worktree Strategy**: [docs/WORKTREE-STRATEGY.md](WORKTREE-STRATEGY.md)
3. **Review API Documentation**: [docs/API.md](API.md)
4. **Test with Sample Project**: Follow the first pipeline run tutorial
5. **Customize for Your Workflow**: Modify skill rules and hooks as needed

## Support

- **Documentation**: See other files in `docs/`
- **Issues**: Check [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Community**: [GitHub Discussions](https://github.com/turbobeest/claude-dev-pipeline/discussions)
- **Bug Reports**: [GitHub Issues](https://github.com/turbobeest/claude-dev-pipeline/issues)

## Quick Reference

```bash
# Essential commands
./install-pipeline.sh                    # Install pipeline
./lib/state-manager.sh read             # Check pipeline status
./lib/worktree-manager.sh status        # Check worktree status
./health-check.sh                       # Run health diagnostics
./monitor.sh                           # Monitor pipeline execution

# Common troubleshooting
claude --list-skills | grep PIPELINE   # Verify skill installation
jq . .claude/settings.json             # Validate configuration
ls -la .claude/hooks/*.sh              # Check hook permissions
./test-runner.sh                       # Run validation tests
```

---

**Next**: Continue to [ARCHITECTURE.md](ARCHITECTURE.md) to understand the system design and component interactions.