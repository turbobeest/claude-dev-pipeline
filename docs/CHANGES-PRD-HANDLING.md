# Changes to PRD Handling

## Summary

Updated the pipeline to enforce using `large-file-reader.sh` for all PRD reading, preventing issues with large files that exceed Claude Code's 25,000 token Read tool limit.

## Changes Made

### 1. Task Master Wrapper (`bin/task-master`)
**Purpose:** Prevents `task-master parse-prd` usage for large PRDs

**Blocks:**
- `task-master parse-prd` - Shows helpful error directing to PRD-to-Tasks skill

**Allows:**
- `task-master analyze-complexity --research` - Used by task-decomposer
- `task-master expand --id=X --research` - Used for subtask generation
- All other task management commands

**Installation:**
```bash
./bin/install-wrapper.sh
```

### 2. PRD-to-Tasks Skill Updates (`skills/PRD-to-Tasks/SKILL.md`)

**Added Mandatory Execution Steps:**
```bash
# Step 1: ALWAYS use large-file-reader for PRDs
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)

# Step 2-4: Analyze and generate tasks
```

**Updated Documentation:**
- Clear instructions to use large-file-reader
- File size guidelines
- Consistency rule: Always use large-file-reader regardless of PRD size

### 3. Configuration Updates (`config/skill-rules.json`)

**Added execution_instructions field:**
```json
"execution_instructions": "CRITICAL: Use ./lib/large-file-reader.sh to read PRD files (NOT Read tool). Large-file-reader bypasses 25K token limit."
```

### 4. Hook Reminder (`.claude/hooks/prd-reader-reminder.md`)

**Created reference document** showing:
- ✅ Correct: Use large-file-reader.sh
- ❌ Incorrect: Use Read tool or task-master parse-prd
- Complete workflow example

### 5. Documentation

**Created:**
- `bin/README.md` - Wrapper usage guide
- `bin/install-wrapper.sh` - Interactive installer
- `docs/TASK-MASTER-WRAPPER.md` - Comprehensive wrapper documentation
- `docs/CHANGES-PRD-HANDLING.md` - This file

**Updated:**
- `README.md` - Added note about large PRD handling
- `skills/PRD-to-Tasks/SKILL.md` - Added mandatory execution steps

## Why These Changes?

### Problem 1: Read Tool Token Limit
**Issue:** Claude Code's Read tool has a hard 25,000 token limit
**Impact:** Large PRDs (>100KB) fail with "token limit exceeded"
**Solution:** Always use large-file-reader.sh which has no token limit

### Problem 2: task-master parse-prd Failures
**Issue:** task-master parse-prd fails on large PRDs
**Errors:**
- "Cannot connect to API"
- "Client network socket disconnected"
- Timeouts and connection errors
**Solution:** Block parse-prd, direct users to PRD-to-Tasks skill

### Problem 3: Inconsistent PRD Reading
**Issue:** Sometimes Read tool used, sometimes large-file-reader
**Impact:** Unpredictable failures on large PRDs
**Solution:** Enforce large-file-reader for ALL PRDs

## Benefits

### ✅ Reliability
- No more "token limit exceeded" errors
- Handles PRDs of any size (35,000+ tokens)
- Consistent behavior regardless of file size

### ✅ Better Task Generation
- Complete PRD analysis in single context
- No chunking or pagination needed
- Atomic document processing

### ✅ Pipeline Integration
- task-decomposer skill unaffected (uses analyze-complexity/expand)
- PRD-to-Tasks skill now has clear execution steps
- Automation continues to work seamlessly

### ✅ User Experience
- Clear error messages when wrong approach used
- Documentation for proper PRD handling
- Easy installation of wrapper

## Usage

### For Users

**When generating tasks from PRD:**
1. Place PRD in `docs/PRD.md`
2. In Claude Code: "Generate tasks from my PRD"
3. The skill automatically uses large-file-reader

**Installing the wrapper (optional but recommended):**
```bash
./bin/install-wrapper.sh
```

### For Developers

**Reading PRDs in skills:**
```bash
# ALWAYS use this approach
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)
```

**Checking file size first:**
```bash
./lib/large-file-reader.sh docs/PRD.md --metadata
```

## Migration Guide

### If You Were Using task-master parse-prd

**Old way:**
```bash
task-master parse-prd docs/PRD.md --output .taskmaster/tasks/tasks.json
```

**New way:**
```bash
# In Claude Code, say:
"Generate tasks from my PRD in docs/PRD.md"

# The PRD-to-Tasks skill will:
# 1. Use large-file-reader to read PRD
# 2. Analyze with AI (not limited by task-master context)
# 3. Generate TaskMaster-compliant tasks.json
```

### If You Were Using Read Tool

**Old way (fails on large PRDs):**
```
Read tool: docs/PRD.md
# Error: token limit exceeded
```

**New way:**
```bash
./lib/large-file-reader.sh docs/PRD.md
```

## Testing

### Test Wrapper Works

```bash
# Should be blocked:
task-master parse-prd docs/PRD.md
# Expected: ⛔ task-master parse-prd is DISABLED

# Should work:
task-master analyze-complexity --research
task-master list
```

### Test Large PRD Reading

```bash
# Check file size
./lib/large-file-reader.sh docs/PRD.md --metadata

# Read large PRD
./lib/large-file-reader.sh docs/PRD.md
```

## Rollback

If you need to revert these changes:

### Remove Wrapper
```bash
# Edit ~/.zshrc or ~/.bashrc
# Remove: export PATH="/path/to/claude-dev-pipeline/bin:$PATH"
source ~/.zshrc

# Or remove alias:
# Remove: alias task-master='/path/to/claude-dev-pipeline/bin/task-master'
```

### Use task-master parse-prd Directly
```bash
/opt/homebrew/bin/task-master parse-prd docs/PRD.md
```

**Note:** Not recommended - will likely fail on large PRDs

## Future Improvements

Potential enhancements:
1. Auto-detect PRD files and suggest large-file-reader
2. Add file size threshold in skill configuration
3. Stream large files in chunks if needed
4. Add progress indicators for very large files

## Questions?

See documentation:
- [Task Master Wrapper Guide](TASK-MASTER-WRAPPER.md)
- [Large File Reader](LARGE-FILE-READER.md)
- [PRD-to-Tasks Skill](../skills/PRD-to-Tasks/SKILL.md)
