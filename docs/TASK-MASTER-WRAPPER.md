# Task Master Wrapper Guide

## Overview

This project includes a task-master wrapper that prevents `parse-prd` command usage while keeping all other commands functional. This addresses issues with large PRDs exceeding task-master's context limits.

## Why the Wrapper?

**Problem:** Large PRDs (>25,000 tokens) fail with task-master:
- API timeouts and connection errors
- Incomplete task generation
- Poor quality output

**Solution:** Use the PRD-to-Tasks skill instead:
- Handles PRDs of any size via large-file-reader
- Better AI analysis and task decomposition
- Proper TaskMaster schema compliance

## What's Blocked vs. Allowed

### ⛔ BLOCKED
- `task-master parse-prd` - Use PRD-to-Tasks skill instead

### ✅ ALLOWED
- `task-master analyze-complexity --research` - Complexity analysis
- `task-master expand --id=X --research` - Subtask generation
- `task-master list` - List tasks
- `task-master set-status` - Update task status
- All other task management commands

## Installation

### Quick Install

```bash
cd /path/to/claude-dev-pipeline
./bin/install-wrapper.sh
```

The installer will:
1. Verify task-master is installed
2. Make wrapper executable
3. Offer to add to PATH or create alias
4. Provide reload instructions

### Manual Installation

**Option 1: Add to PATH (Recommended)**

Add this to your `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="/path/to/claude-dev-pipeline/bin:$PATH"
```

**Option 2: Create Alias**

Add this to your `~/.zshrc` or `~/.bashrc`:

```bash
alias task-master='/path/to/claude-dev-pipeline/bin/task-master'
```

Then reload your shell:

```bash
source ~/.zshrc  # or ~/.bashrc
```

## Verification

Test the wrapper is working:

```bash
# Should be BLOCKED:
task-master parse-prd docs/PRD.md
# Output: ⛔ task-master parse-prd is DISABLED for this project

# Should WORK:
task-master analyze-complexity --research
task-master list
which task-master
# Output: /path/to/claude-dev-pipeline/bin/task-master
```

## Using PRD-to-Tasks Instead

### In Claude Code

1. **Place your PRD** in `docs/PRD.md`

2. **Say to Claude:**
   ```
   Generate tasks from my PRD
   ```

3. **The skill will:**
   - Read your PRD (any size, including >100KB files)
   - Analyze features and requirements
   - Generate TaskMaster-compliant tasks.json
   - Include integration tasks
   - Validate dependencies

### Benefits Over parse-prd

| Feature | parse-prd | PRD-to-Tasks Skill |
|---------|-----------|-------------------|
| Max file size | ~100KB | Unlimited |
| Context handling | Limited | Full document analysis |
| Integration tasks | Not guaranteed | Always generated |
| Schema compliance | Basic | Fully compliant |
| Error handling | Minimal | Comprehensive |

## Pipeline Integration

The wrapper is **transparent** to the automated pipeline:

### Phase 0: Task Generation (PRD-to-Tasks)
- Uses PRD-to-Tasks skill ✅
- Does NOT use task-master parse-prd ✅
- Generates tasks.json

### Phase 1: Task Decomposition
- Uses `task-master analyze-complexity --research` ✅
- Uses `task-master expand --id=X --research` ✅
- Wrapper allows these commands

### All Other Phases
- Standard task-master commands work normally ✅
- No impact from wrapper

## Bypassing the Wrapper (Not Recommended)

If you absolutely must use parse-prd (not recommended):

```bash
# Call real task-master directly
/opt/homebrew/bin/task-master parse-prd docs/PRD.md
```

**Warning:** This will likely fail for large PRDs with:
- Connection errors
- API timeouts
- Incomplete output

## Troubleshooting

### Wrapper Not Being Used

**Check which task-master is being called:**
```bash
which task-master
```

**Should show:**
```
/path/to/claude-dev-pipeline/bin/task-master
```

**If not, check your PATH:**
```bash
echo $PATH | grep claude-dev-pipeline
```

**Fix:** Reload your shell or re-run installation

### Permission Denied

```bash
chmod +x /path/to/claude-dev-pipeline/bin/task-master
```

### task-master Not Found

The wrapper can't find the real task-master binary.

**Edit the wrapper:**
```bash
vim /path/to/claude-dev-pipeline/bin/task-master
```

**Update this line:**
```bash
REAL_TASKMASTER="/opt/homebrew/bin/task-master"
```

**Find correct path:**
```bash
# Temporarily remove wrapper from PATH
export PATH="${PATH//\/path\/to\/claude-dev-pipeline\/bin:/}"
which task-master
```

## Uninstalling

Remove from your shell configuration:

```bash
# Edit ~/.zshrc or ~/.bashrc
# Remove the line:
# export PATH="/path/to/claude-dev-pipeline/bin:$PATH"
# or
# alias task-master='/path/to/claude-dev-pipeline/bin/task-master'

# Reload shell
source ~/.zshrc
```

## Technical Details

### How It Works

1. Wrapper intercepts all task-master commands
2. If command is `parse-prd`, display error and exit
3. Otherwise, forward to real task-master binary
4. Return real task-master's output

### Wrapper Location

```
claude-dev-pipeline/
├── bin/
│   ├── task-master          # Wrapper script
│   ├── install-wrapper.sh   # Installation script
│   └── README.md            # Usage documentation
```

### Exit Codes

- `0` - Success (allowed command executed)
- `1` - Blocked (parse-prd attempted or error)

## See Also

- [PRD-to-Tasks Skill](../skills/PRD-to-Tasks/SKILL.md)
- [Task Decomposer Skill](../skills/task-decomposer/SKILL.md)
- [Large File Reader](LARGE-FILE-READER.md)
- [Quick Start Guide](QUICK-START.md)
