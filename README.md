# Claude Dev Pipeline - Full Stack Autonomous Development System

[![Version](https://img.shields.io/badge/Version-3.0-blue.svg)](#)
[![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-green.svg)](#)
[![Automation](https://img.shields.io/badge/Automation-95%25-brightgreen.svg)](#)

A complete end-to-end development automation system that takes your Product Requirements Document (PRD) and autonomously handles the entire software development lifecycle - from task decomposition and specification generation through implementation, testing, validation, and deployment. This pipeline achieves 95% automation across all development phases, requiring human intervention only at three strategic decision points.

## Quick Installation

```bash
# Clone the repository (use deploy branch for production-ready code)
git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git

# Navigate to your project
cd your-project

# Run installer
bash /path/to/claude-dev-pipeline/install-pipeline.sh
```

## Prerequisites

- Claude Code
- Git
- Bash 3.2+
- jq
- TaskMaster ([installation](https://github.com/eyaltoledano/claude-task-master))
- OpenSpec ([installation](https://github.com/Fission-AI/OpenSpec))

## Configuration

1. Copy and configure environment:
```bash
cp .env.template .env
# Edit .env with your GitHub organization and preferences
```

2. Run setup:
```bash
./setup.sh
```

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
- `skill-activation-prompt.sh` - Skill activation via codewords
- `post-tool-use-tracker.sh` - Phase transition automation
- `pre-implementation-validator.sh` - TDD enforcement
- `worktree-enforcer.sh` - Git worktree isolation

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
Copy your prepared PRD to the project root:
```bash
# Place your completed PRD in the project directory
cp ~/path/to/your/prepared-PRD.md ./PRD.md

# Or if using Claude Projects, export and place:
cp ~/claude-projects/my-app/requirements.md ./PRD.md
```

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

## Documentation

- [Setup Guide](docs/SETUP-GUIDE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [API Reference](docs/API.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Worktree Strategy](docs/WORKTREE-STRATEGY.md)

## Features

✅ **100% Skill Activation Rate** - Guaranteed via codewords  
✅ **95% Automation** - Only 3 manual approval gates  
✅ **Complete Isolation** - Git worktrees for parallel development  
✅ **Production Ready** - Enterprise-grade error handling  
✅ **Tool Integration** - TaskMaster & OpenSpec ready  

## License

MIT

## Support

For issues or questions, please check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md) or open an issue on GitHub.