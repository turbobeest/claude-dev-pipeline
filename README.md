# Claude Dev System

An autonomous development system that takes you from a Product Requirements Document (PRD) to deployed code with 95% automation. You provide the requirements—Claude handles the rest.

## What This Does

The Claude Dev System automates the entire software development lifecycle:

1. You write a **detailed PRD** describing what you want to build — use the **[PRD Template](templates/PRD-template.md)**
2. You run one command to install the system
3. You approve the task breakdown (Phase 1)
4. Claude autonomously handles everything else — specs, implementation, testing, and deployment

> **The PRD is critical.** The more detailed your requirements, the better the output. Include user stories, acceptance criteria, technical constraints, and edge cases. A thorough PRD means fully autonomous execution from Phase 2 onward.

**No more manually orchestrating Claude through each development step.**

---

## The 6-Phase System

| Phase | What Happens | Your Role |
|-------|--------------|-----------|
| **1. Task Decomposition** | Your PRD is parsed into structured tasks. Complex tasks are broken into subtasks. | Approve task breakdown |
| **2. Specification** | Tasks are analyzed for dependencies. OpenSpec proposals are generated for each work unit. | Automatic |
| **3. TDD Implementation** | Tests are written first, then code to pass them. Enforced automatically—no skipping. | Automatic |
| **4. Integration Testing** | Components are tested together. Architecture is validated. | Automatic |
| **5. E2E Validation** | Full user workflows are tested end-to-end. | Automatic |
| **6. Deployment** | Code is deployed with staged rollout and rollback triggers. | Automatic |

**One approval, then fully autonomous.** After you approve the task breakdown in Phase 1, the system runs to completion without intervention.

---

## Quick Start

### Prerequisites

- macOS, Linux, or WSL2
- Bash 3.2+, Git 2.20+, jq
- Node.js & npm (for TaskMaster and OpenSpec)
- Claude Code CLI installed

### Installation (2 minutes)

The installer automatically:
- **Checks versions** of Node.js, npm, TaskMaster, and OpenSpec
- **Installs or updates** any outdated dependencies
- **Sets up** all 10 skills and 3 hooks

```bash
# Clone the system
git clone https://github.com/turbobeest/claude-dev-system.git

# Navigate to your project
cd your-project

# Install the system (checks and updates all dependencies)
bash /path/to/claude-dev-system/install.sh

# Or auto-update without prompts
bash /path/to/claude-dev-system/install.sh --auto

# Check dependency versions only (no install)
bash /path/to/claude-dev-system/install.sh --check-only

# Skip tool installation if you manage dependencies separately
bash /path/to/claude-dev-system/install.sh --no-tools

# Verify installation
./health-check.sh
```

**Dependency version table** (shown during install):
```
DEPENDENCY           INSTALLED       LATEST          STATUS
----------           ---------       ------          ------
Node.js              20.10.0         22.11.0         Update
npm                  10.2.3          10.9.0          Update
TaskMaster           1.2.0           1.2.0           ✓ OK
OpenSpec             0.5.1           0.6.0           Update
```

This creates a `.claude/` directory with all skills, hooks, and configuration.

### Your First Run

**Step 1:** Create your PRD using the template:

📄 **[PRD Template](templates/PRD-template.md)** — Start here

**Step 2:** Start Claude Code in your project directory:

```bash
claude
```

**Step 3:** Kick off the system:

```
I've completed my PRD at docs/PRD.md. Begin automated development.
```

**Step 4:** Approve the task breakdown when prompted, then watch it run autonomously through deployment.

---

## How It Works

The system uses **hooks** to inject activation codewords that guarantee skill activation (100% reliability vs ~70% with keyword detection).

```
Your Message → Hook analyzes context → Injects activation code → Skill executes → Phase completes → Next phase triggers
```

Three hooks power the system:

| Hook | Trigger | Purpose |
|------|---------|---------|
| `skill-activation-prompt.sh` | Every user message | Detects context and activates the right skill |
| `post-tool-use-tracker.sh` | After each tool use | Tracks progress and triggers phase transitions |
| `pre-implementation-validator.sh` | Before file writes | Enforces TDD—blocks code without tests |

---

## Project Structure After Installation

```
your-project/
└── .claude/
    ├── skills/           # 10 autonomous development skills
    ├── hooks/            # 3 automation hooks
    ├── config/           # skill-rules.json, settings.json
    ├── lib/              # Support libraries
    ├── templates/        # PRD and architecture templates
    └── docs/             # Full documentation
```

---

## Skills Reference

| Skill | Phase | What It Does |
|-------|-------|--------------|
| System Orchestration | 0 | Master controller coordinating all phases |
| PRD-to-Tasks | 1 | Converts PRD into structured tasks.json |
| Task Decomposer | 1 | Breaks complex tasks into subtasks |
| Coupling Analysis | 1 | Determines task dependencies |
| Spec Generator | 2 | Creates OpenSpec proposals |
| Test Strategy | 2 | Designs test coverage (60/30/10 split) |
| TDD Implementer | 3 | Implements code test-first |
| Integration Validator | 4 | Tests component interactions |
| E2E Validator | 5 | Validates full user workflows |
| Deployment Orchestrator | 6 | Manages staged deployment |

---

## Verification

After installation, verify everything works:

```bash
# Check skills are installed
ls .claude/skills/

# Check hooks are executable
ls -la .claude/hooks/*.sh

# Check configuration exists
cat .claude/config/settings.json

# Run health check
./health-check.sh
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Skills not activating | Check `skill-rules.json` has correct trigger patterns |
| Hooks not running | Verify hooks are executable: `chmod +x .claude/hooks/*.sh` |
| State corruption | Reset: `rm .claude/.workflow-state.json` |
| Git worktree conflicts | Clean up: `git worktree prune` |
| Missing jq | Install: `brew install jq` (macOS) or `apt install jq` (Linux) |

For detailed troubleshooting: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## Documentation

- [Setup Guide](docs/SETUP-GUIDE.md) — Detailed installation instructions
- [Architecture](docs/ARCHITECTURE.md) — How the system works internally
- [Development Workflow](docs/DEVELOPMENT-WORKFLOW.md) — Phase-by-phase breakdown
- [API Reference](docs/API.md) — Hook and skill interfaces
- [Worktree Strategy](docs/WORKTREE-STRATEGY.md) — Git isolation approach

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `./tests/run-tests.sh`
5. Submit a pull request

---

## License

MIT License — see [LICENSE](LICENSE) for details.
