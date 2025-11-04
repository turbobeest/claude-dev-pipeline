# Claude Dev Pipeline - Autonomous Full Stack Development System

[![Version](https://img.shields.io/badge/Version-3.0-blue.svg)](#)
[![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-green.svg)](#)
[![Automation](https://img.shields.io/badge/Automation-95%25-brightgreen.svg)](#)

> **⚠️ IMPORTANT:** Claude Code v2.0.27-2.0.32 has a [known bug](KNOWN-ISSUES.md#-userpromptsubmit-hooks-broken-in-claude-code-v2027) where UserPromptSubmit hooks don't work. **Workaround is active** - the pipeline will notify you loudly when this is fixed. See [KNOWN-ISSUES.md](KNOWN-ISSUES.md) for details.

A complete end-to-end development automation system that takes your Product Requirements Document (PRD) and autonomously handles the entire software development lifecycle - from task decomposition and specification generation through implementation, testing, validation, and deployment. This pipeline achieves 95% automation across all development phases, requiring human intervention only at three strategic decision points.

## ⚡ Fast Installation (< 2 minutes)

The installer **automatically checks and installs** all prerequisites for you!

```bash
# Step 1: Clone to temporary location
cd /tmp
git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git

# Step 2: Navigate to YOUR project directory
cd /path/to/your-project  # <-- Where you want .claude/ installed

# Step 3: Run the installer (auto-checks & installs prerequisites)
bash /tmp/claude-dev-pipeline/install.sh
```

**What the installer does:**
- ✅ Checks all prerequisites (Claude Code, Git, Bash, jq, TaskMaster, OpenSpec)
- ✅ Auto-installs missing tools (jq, TaskMaster, OpenSpec)
- ✅ Copies pipeline files to `.claude/`
- ✅ Initializes configuration
- ✅ Verifies installation
- ✅ Tests hooks

**Installation takes < 2 minutes with zero manual steps for most prerequisites!**

See [Quick Start Guide](docs/QUICK-START.md) for detailed instructions.

## Prerequisites (Auto-Installed)

| Tool | Auto-Install | Notes |
|------|--------------|-------|
| Claude Code | ❌ Manual | [Download](https://claude.ai/download) |
| Git | ✅ Yes | Via brew/apt/yum |
| Bash 3.2+ | ℹ️ Pre-installed | Typically available |
| jq | ✅ Yes | JSON processor |
| TaskMaster | ✅ Yes | [GitHub](https://github.com/eyaltoledano/claude-task-master) |
| OpenSpec | ✅ Yes | [GitHub](https://github.com/Fission-AI/OpenSpec) |

**Manual prerequisite check:**
```bash
# Check what's installed
./.claude/lib/prerequisites-installer.sh

# Auto-install missing tools
./.claude/lib/prerequisites-installer.sh --fix-all
```

## Installation Structure

After installation, your project will have:
```
your-project/              # Your project root (run 'claude' from HERE)
├── .claude/              # Pipeline system (created by installer)
│   ├── skills/          # 10 autonomous skills
│   ├── hooks/           # 3 automation hooks
│   ├── config/          # Configuration files (skill-rules.json)
│   ├── lib/             # Support libraries
│   └── settings.json    # Claude Code hook configuration
├── .env                 # Environment variables (in project root, not .claude/)
├── .taskmaster/         # TaskMaster workspace (created when used)
├── .openspec/           # OpenSpec proposals (created when used)
├── docs/                # Documentation directory
│   └── PRD.md          # Your requirements document
└── src/                # Your source code
```

**⚠️ IMPORTANT File Locations**:
- `.env` goes in your PROJECT ROOT (not in `.claude/`)
- `settings.json` goes in `.claude/` (hooks reference `.claude/hooks/`)
- Always run `claude` from your project root directory
- The hooks use relative paths from your project root

## Configuration

### Environment Variables (.env)

The pipeline can use environment variables for configuration. Since TaskMaster also uses `.env` in the project root, we append pipeline-specific variables to your existing `.env` file:

```bash
# From your project root
cd your-project

# If you have an existing .env (from TaskMaster or other tools), append pipeline config:
cat >> .env << 'EOF'

# === Claude Dev Pipeline Configuration ===
# GitHub Repository (full URL - works with enterprise and personal GitHub)
# Examples: https://github.com/user/repo or https://github.enterprise.com/org/repo
GITHUB_REPO_URL=https://github.com/turbobeest/claude-dev-pipeline
# Or for enterprise: GITHUB_REPO_URL=https://github.enterprise.com/org/repo
GITHUB_BRANCH=deploy

# GitHub Token (optional - only needed for private repos)
# Not required for enterprise GitHub with SSO authentication
# GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# TaskMaster Configuration (REQUIRED for TaskMaster features)
# GitHub token with repo, project, issues, pull_requests permissions
TASKMASTER_GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
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

# Or if you don't have an .env yet, copy the template:
cp /tmp/claude-dev-pipeline/.env.template .env
# Then edit .env with your preferences

# Edit Claude Code settings if needed (optional)
vim .claude/settings.json
```

**Note**: The pipeline works without any .env configuration using sensible defaults. Only add these if you need to customize behavior.

## What This System Does

This pipeline transforms your ideas into deployed, tested, production-ready software:

1. **Planning & Design**: Analyzes your PRD, decomposes into tasks, identifies dependencies
2. **Specification**: Generates detailed technical specifications and test strategies
3. **Development**: Implements code using Test-Driven Development (TDD) methodology
4. **Testing**: Executes component integration and end-to-end validation
5. **Deployment**: Orchestrates staging, canary, and production deployments
6. **Validation**: Ensures production readiness with automated quality gates

### Complete Development Pipeline (6 Phases)
- **Phase 1**: Task Decomposition & Planning (PRD → structured tasks)
- **Phase 2**: Technical Specifications (OpenSpec proposals & test strategies)
- **Phase 3**: TDD Implementation (tests first, then code)
- **Phase 4**: Component Integration Testing (system-wide validation)
- **Phase 5**: E2E Production Validation (user workflow testing)
- **Phase 6**: Deployment & Rollout (staged production deployment)

### 4 Automation Hooks
- `skill-activation-prompt.sh` - Skill activation via codewords (fault-tolerant)
- `post-tool-use-tracker.sh` - Phase transition automation (simplified version available)
- `pre-implementation-validator.sh` - TDD enforcement
- `worktree-enforcer.sh` - Git worktree isolation

**Note:** Hooks include simplified fault-tolerant versions that gracefully degrade if dependencies are missing. See `hooks/README-HOOK-VERSIONS.md` for details.

### Core Infrastructure
- Atomic state management
- Git worktree isolation
- Error recovery with checkpoints
- Connection pooling for tools
- Structured JSON logging

## Prerequisites for Operation

### Required: Product Requirements Document (PRD)
You must have a properly formatted PRD prepared before starting. Use the provided template to structure your requirements properly (see [PRD Template](templates/PRD-template.md)). This comprehensive template ensures all necessary information is captured for the autonomous pipeline to successfully transform your requirements into production-ready code.

## Usage

### Step 1: Place Your PRD
Copy your prepared PRD to the docs directory for better organization:
```bash
# Create docs directory if it doesn't exist
mkdir -p docs

# Place your completed PRD in the docs directory
cp ~/path/to/your/prepared-PRD.md ./docs/PRD.md

# Or if using Claude Projects, export and place:
cp ~/claude-projects/my-app/requirements.md ./docs/PRD.md
```

**Note**: We recommend `docs/PRD.md` instead of root to keep your project organized. TaskMaster doesn't use the PRD - it only works with `tasks.json` which the pipeline creates in `.taskmaster/`.

**Large PRD Handling**: The PRD-to-Tasks skill automatically uses the large-file-reader utility to bypass Claude Code's 25,000 token Read tool limit. Your PRD can be any size.

**For Large PRDs (>25,000 tokens / >100KB):**

If your PRD is comprehensive and exceeds Claude Code's Read tool limit:

```bash
# Check if your PRD is large
./.claude/lib/large-file-reader.sh docs/PRD.md --metadata

# In Claude Code, use:
# "Please use .claude/lib/large-file-reader.sh docs/PRD.md to read my PRD"
```

The large-file-reader utility bypasses the 25,000 token limit and reads files of any size. See [Large File Reader Guide](docs/LARGE-FILE-READER.md) for details.

### Step 2: Start the Autonomous Pipeline
```
"I've completed my PRD, begin automated development"
```

### What Happens Next
1. **Immediate PRD Processing**: The PRD-to-Tasks skill automatically analyzes your document
2. **Task Generation**: Creates structured tasks.json with dependencies and coupling analysis
3. **TaskMaster Activation**: Takes over task orchestration and management
4. **Autonomous Progression**: Pipeline advances through all 6 phases with 95% automation
5. **Human Approval**: You're prompted only at 3 strategic decision points

The entire process from PRD to deployed code is managed autonomously.

## Real-Time Monitoring

### Option 1: Web Dashboard (Recommended) 🆕

Visual web-based monitoring with live updates:

```bash
# Start the web dashboard
python3 .claude/monitor-dashboard.py

# Open browser to: http://localhost:8888
```

**Features:**
- 📊 Visual task hierarchy (master tasks → subtasks)
- 🟢 Real-time status indicators (pending/in-progress/complete)
- 📝 Live log streaming with color coding
- 📈 Progress statistics (completion %, task counts)
- 🎨 VS Code-inspired dark theme
- ⚡ Auto-updates every 0.5-2 seconds

**No dependencies required** - uses only Python standard library!

See [MONITOR-DASHBOARD.md](MONITOR-DASHBOARD.md) for full documentation.

### Option 2: Command Line Monitor

Traditional CLI monitoring:

```bash
# In a separate terminal, run the monitor dashboard
bash /tmp/claude-dev-pipeline/monitor-pipeline.sh

# Or for live log streaming
bash /tmp/claude-dev-pipeline/monitor-pipeline.sh --live

# Check current phase
bash /tmp/claude-dev-pipeline/monitor-pipeline.sh --phase
```

The monitor shows:
- Current pipeline phase and progress
- Active signals and skill activations
- Real-time log streaming with color coding
- Error tracking and performance metrics
- Hook executions and codeword injections

## Documentation

- **[Quick Start Guide](docs/QUICK-START.md)** - Fast installation walkthrough
- **[Large File Reader](docs/LARGE-FILE-READER.md)** - Read PRDs >25K tokens
- [Setup Guide](docs/SETUP-GUIDE.md) - Detailed setup instructions
- [Architecture](docs/ARCHITECTURE.md) - System design overview
- [API Reference](docs/API.md) - Library and function documentation
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Worktree Strategy](docs/WORKTREE-STRATEGY.md) - Isolation approach

## Features

✅ **Fast Installation** - < 2 minutes with automatic prerequisite setup
✅ **100% Skill Activation Rate** - Guaranteed via codewords
✅ **95% Automation** - Only 3 manual approval gates
✅ **Large File Support** - Read PRDs >25K tokens (35K+ tokens tested)
✅ **Complete Isolation** - Git worktrees for parallel development
✅ **Production Ready** - Enterprise-grade error handling
✅ **Tool Integration** - TaskMaster & OpenSpec ready
✅ **Fault-Tolerant Hooks** - Simplified hooks never fail

## License

MIT

## Support

For issues or questions, please check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md) or open an issue on GitHub.
