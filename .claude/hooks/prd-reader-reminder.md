# PRD Reading Reminder for Claude

## CRITICAL: How to Read PRD Files

When the PRD-to-Tasks skill activates, you MUST use the large-file-reader utility:

### ✅ CORRECT Approach

```bash
# Read PRD using large-file-reader (no token limit)
./lib/large-file-reader.sh docs/PRD.md
```

**Why:**
- Bypasses Claude Code's Read tool 25,000 token limit
- Handles files of any size (35,000+ tokens)
- Provides complete document for atomic analysis
- No chunking or pagination needed

### ❌ INCORRECT Approach

```bash
# DO NOT use Read tool for PRDs - will fail on large files
Read tool: docs/PRD.md
```

**Problems:**
- Hard 25,000 token limit
- Fails with "token limit exceeded" error
- Forces incomplete analysis
- Requires manual chunking

## File Size Detection

Before reading, check file size:

```bash
./lib/large-file-reader.sh docs/PRD.md --metadata
```

Output shows:
- File size in KB
- Estimated tokens
- Line count
- Whether it exceeds Read tool limit

## Complete Workflow

```bash
# 1. Check PRD size
echo "📊 Checking PRD file size..."
./lib/large-file-reader.sh docs/PRD.md --metadata

# 2. Read PRD (regardless of size)
echo "📖 Reading PRD with large-file-reader..."
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)

# 3. Analyze and generate tasks
echo "🔨 Analyzing PRD and generating tasks..."
# Proceed with task generation using $prd_content
```

## Why Not Use task-master parse-prd?

The task-master wrapper blocks `parse-prd` because:
- Large PRDs exceed task-master's API context limits
- Results in connection errors and timeouts
- Produces incomplete or poor quality output
- PRD-to-Tasks skill provides better analysis

## Summary

**For PRD-to-Tasks Skill:**
- ✅ Always use `./lib/large-file-reader.sh docs/PRD.md`
- ❌ Never use Read tool for PRDs
- ❌ Never use task-master parse-prd
