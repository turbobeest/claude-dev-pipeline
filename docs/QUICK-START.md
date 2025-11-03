# Quick Start Guide - Claude Dev Pipeline

## Fast Installation (< 2 minutes)

### Step 1: Clone Pipeline to Temporary Location

```bash
# Clone to /tmp (outside your project)
cd /tmp
git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git
```

### Step 2: Run Quick Install

```bash
# Navigate to YOUR project directory
cd /path/to/your/project

# Run the installer
bash /tmp/claude-dev-pipeline/install.sh
```

**The installer will:**
1. ✅ Check all prerequisites
2. ✅ Auto-install missing tools (jq, TaskMaster, OpenSpec)
3. ✅ Copy pipeline files to `.claude/`
4. ✅ Initialize configuration
5. ✅ Verify installation

## What Gets Checked & Installed

| Prerequisite | Auto-Install | Notes |
|--------------|--------------|-------|
| Claude Code | ❌ Manual | Download from https://claude.ai/download |
| Git | ✅ Yes | Via brew (macOS) or apt/yum (Linux) |
| Bash 3.2+ | ℹ️ Pre-installed | Typically already available |
| jq | ✅ Yes | JSON processor for hooks |
| TaskMaster | ✅ Yes | Task management CLI |
| OpenSpec | ✅ Yes | Specification management |

## Manual Prerequisite Check

```bash
# Check what's installed
./lib/prerequisites-installer.sh --check-only

# Auto-install everything
./lib/prerequisites-installer.sh --fix-all

# Install specific tool
./lib/prerequisites-installer.sh --install jq
```

## Installation Output

```bash
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   Claude Dev Pipeline - Autonomous Full Stack Development       ║
║                                                                  ║
║   Fast Installation with Automatic Prerequisite Setup           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝


==> Step 1: Checking Prerequisites

==> Checking Claude Code...
✓ Claude Code installed: v2.0.31

==> Checking Git...
✓ Git installed: v2.50.1

==> Checking Bash...
✓ Bash installed: v3.2.57 (>= 3.2.0)

==> Checking jq...
✓ jq installed: v1.7

==> Checking TaskMaster...
✓ TaskMaster installed: v0.31.1

==> Checking OpenSpec...
✓ OpenSpec installed: v0.13.0

✓ All prerequisites satisfied


==> Step 2: Installing Pipeline Files
ℹ Installing to: /path/to/your/project
ℹ Copying hooks...
ℹ Copying libraries...
ℹ Copying configuration...
ℹ Copying skills...
ℹ Initializing workflow state...
ℹ Setting permissions...
✓ Pipeline files installed


==> Step 3: Configuring Pipeline
✓ Git repository detected
ℹ Initializing TaskMaster directory...
ℹ Initializing OpenSpec directory...
✓ Project structure initialized


==> Step 4: Verifying Installation
✓ Hooks installed
✓ Libraries installed
✓ Configuration installed
✓ Workflow state initialized
ℹ Testing hooks...
✓ Hooks functional
✓ Installation verified successfully

╔══════════════════════════════════════════════════════════════════╗
║  Installation Complete!                                          ║
╚══════════════════════════════════════════════════════════════════╝
```

## After Installation

### 1. Create Your PRD

```bash
mkdir -p docs
vim docs/PRD.md  # or your preferred editor
```

### 2. Start Development

Open Claude Code in your project directory:

```bash
claude .
```

Then say:
```
I've completed my PRD, begin automated development
```

### 3. For Large PRDs (>25,000 tokens)

If your PRD is comprehensive (>100KB):

```bash
# Check file size first
.claude/lib/large-file-reader.sh docs/PRD.md --metadata

# Read large file in Claude Code
# Tell Claude: "Please use .claude/lib/large-file-reader.sh docs/PRD.md"
```

## Troubleshooting

### Issue: "Claude Code not found"

**Solution:** Install Claude Code manually:
```bash
# macOS
brew install --cask claude

# Or download from:
https://claude.ai/download
```

### Issue: "Permission denied" on hooks

**Solution:** Fix permissions:
```bash
chmod +x .claude/hooks/*.sh
chmod +x .claude/lib/*.sh
```

### Issue: Hook errors

**Solution:** Use simplified hooks:
```bash
cp .claude/hooks/skill-activation-prompt-simple.sh .claude/hooks/skill-activation-prompt.sh
cp .claude/hooks/post-tool-use-tracker-simple.sh .claude/hooks/post-tool-use-tracker.sh
```

### Issue: "jq not found"

**Solution:** Install jq:
```bash
# macOS
brew install jq

# Linux (Ubuntu/Debian)
sudo apt-get install jq

# Or use the installer
./.claude/lib/prerequisites-installer.sh --install jq
```

## Verify Installation

```bash
# Re-check all prerequisites
./.claude/lib/prerequisites-installer.sh

# Test hooks manually
echo '{"message":"test PRD"}' | ./.claude/hooks/skill-activation-prompt.sh
# Should output: {"injectedText":"[ACTIVATE:PRD_TO_TASKS_V1]"}

# Check large file reader
./.claude/lib/large-file-reader.sh --help
```

## Directory Structure After Installation

```
your-project/
├── .claude/                          # Pipeline installation
│   ├── hooks/                        # Claude Code hooks
│   │   ├── skill-activation-prompt.sh
│   │   ├── post-tool-use-tracker.sh
│   │   └── ...
│   ├── lib/                          # Utility libraries
│   │   ├── large-file-reader.sh     # Read files >25K tokens
│   │   ├── prerequisites-installer.sh
│   │   └── ...
│   ├── config/                       # Configuration files
│   │   ├── skill-rules.json
│   │   └── ...
│   ├── skills/                       # Skill definitions
│   │   ├── PRD-to-Tasks/
│   │   ├── task-decomposer/
│   │   └── ...
│   └── .workflow-state.json         # Workflow tracking
├── .taskmaster/                      # TaskMaster files
│   ├── tasks/
│   └── proposals/
├── openspec/                         # OpenSpec specifications
│   └── project.md
└── docs/                             # Your documentation
    └── PRD.md                        # Your PRD goes here
```

## Updating the Pipeline

```bash
# Pull latest changes
cd /tmp/claude-dev-pipeline
git pull origin deploy

# Re-run installer
cd /path/to/your/project
bash /tmp/claude-dev-pipeline/install.sh
```

## Uninstalling

```bash
# Remove pipeline files
rm -rf .claude

# Optionally remove TaskMaster/OpenSpec directories
rm -rf .taskmaster openspec
```

## Next Steps

1. **Read the Documentation:**
   - [Architecture Overview](.claude/docs/ARCHITECTURE.md)
   - [Large File Reader](.claude/docs/LARGE-FILE-READER.md)
   - [Troubleshooting](.claude/docs/TROUBLESHOOTING.md)

2. **Explore Skills:**
   ```bash
   ls -la .claude/skills/
   ```

3. **Customize Configuration:**
   - Edit `.claude/config/skill-rules.json`
   - Adjust `.claude/config/settings.json`

4. **Start Building:**
   Create your PRD and let Claude Code handle the rest!

## Getting Help

- **Troubleshooting:** `.claude/docs/TROUBLESHOOTING.md`
- **GitHub Issues:** https://github.com/turbobeest/claude-dev-pipeline/issues
- **Prerequisites:** `.claude/lib/prerequisites-installer.sh --help`

## Example Workflow

```bash
# 1. Install pipeline
cd /tmp && git clone -b deploy https://github.com/turbobeest/claude-dev-pipeline.git
cd ~/my-new-project
bash /tmp/claude-dev-pipeline/install.sh

# 2. Verify prerequisites
./.claude/lib/prerequisites-installer.sh

# 3. Create PRD
mkdir docs
cat > docs/PRD.md << 'EOF'
# My Awesome Project

## Overview
Building an amazing application...
EOF

# 4. Check PRD size (if large)
./.claude/lib/large-file-reader.sh docs/PRD.md --metadata

# 5. Start development
claude .
# In Claude: "I've completed my PRD, begin automated development"
```

---

**Installation takes < 2 minutes with automatic prerequisite installation!** 🚀
