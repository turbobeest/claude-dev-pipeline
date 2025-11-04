# Task Master Wrapper

This directory contains a wrapper script for `task-master` that restricts certain commands to prevent issues with large PRDs.

## What It Does

The wrapper script **blocks** `task-master parse-prd` while **allowing**:
- `analyze-complexity` - For analyzing task complexity
- `expand` - For expanding high-complexity tasks into subtasks
- `complexity-report` - For viewing complexity analysis
- All other task management commands

## Why?

Large PRDs (>25,000 tokens) exceed task-master's context limits, resulting in:
- Incomplete task generation
- API timeout errors
- Poor quality task decomposition

This project uses the **PRD-to-Tasks skill** instead, which:
- Handles comprehensive PRDs of any size
- Uses the large-file-reader utility for files >100KB
- Generates higher quality TaskMaster-compliant tasks

## Installation

### Option 1: Add to PATH (Recommended)

Add this to your shell configuration (~/.bashrc, ~/.zshrc, etc.):

```bash
# Task Master wrapper for claude-dev-pipeline
export PATH="/path/to/claude-dev-pipeline/bin:$PATH"
```

Then reload your shell:
```bash
source ~/.zshrc  # or ~/.bashrc
```

### Option 2: Create Alias

Add this to your shell configuration:

```bash
alias task-master='/path/to/claude-dev-pipeline/bin/task-master'
```

### Option 3: Manual Installation

Copy the wrapper to your local bin directory:

```bash
mkdir -p ~/.local/bin
cp bin/task-master ~/.local/bin/task-master-wrapped
alias task-master='~/.local/bin/task-master-wrapped'
```

## Verification

Test that the wrapper is working:

```bash
# This should be BLOCKED:
task-master parse-prd docs/PRD.md

# These should WORK:
task-master analyze-complexity --research
task-master expand --id=1 --research
task-master list
```

## Usage in Pipeline

The wrapper is **transparent** to the pipeline automation:

- ✅ **task-decomposer skill** continues to work (uses analyze-complexity and expand)
- ✅ All task management commands work normally
- ⛔ **parse-prd is blocked** with helpful error message

## Generating Tasks from PRD

Instead of `task-master parse-prd`, use the PRD-to-Tasks skill:

1. **Place your PRD** in `docs/PRD.md`
2. **In Claude Code**, say: `"Generate tasks from my PRD"`
3. **The skill** will:
   - Read your PRD (any size)
   - Generate TaskMaster-compliant tasks.json
   - Include integration tasks
   - Validate dependencies

## Bypassing the Wrapper (Not Recommended)

If you absolutely need to use parse-prd (not recommended for large PRDs):

```bash
# Call the real task-master directly
/opt/homebrew/bin/task-master parse-prd docs/PRD.md
```

## Troubleshooting

### "task-master not found"
The wrapper can't find the real task-master binary. Edit `bin/task-master` and update the `REAL_TASKMASTER` path.

### "Permission denied"
Make the wrapper executable:
```bash
chmod +x bin/task-master
```

### Wrapper not being used
Check your PATH:
```bash
which task-master
# Should show: /path/to/claude-dev-pipeline/bin/task-master
```

## Uninstalling

Remove the wrapper from your PATH or delete the alias from your shell configuration.
