---
description: Parse PRD and generate tasks (workaround for UserPromptSubmit bug)
---

# PRD Parsing and Task Generation

**🔧 WORKAROUND MODE ACTIVE** - This command bypasses the broken UserPromptSubmit hooks in Claude Code v2.0.26-2.0.32.

## Your Task

You are activating the **PRD-to-Tasks** skill to parse the Product Requirements Document and generate a structured task list.

### Step 1: Locate the PRD

Check for PRD in these locations (in order):
1. `docs/PRD.md` (recommended location)
2. `PRD.md` (project root)
3. User-specified path (if provided as argument to this command)

### Step 2: Check PRD Size

Before reading, check the file size:

```bash
wc -w docs/PRD.md | awk '{print "Words:", $1, "| Est. tokens:", int($1 * 1.3)}'
```

**IMPORTANT File Size Rules:**
- **< 25,000 tokens**: Use Read tool directly
- **≥ 25,000 tokens**: Use large-file-reader utility

### Step 3: Read the PRD

**For small PRDs (<25K tokens):**
```
Use the Read tool on docs/PRD.md
```

**For large PRDs (≥25K tokens):**
```bash
./.claude/lib/large-file-reader.sh docs/PRD.md
```

The large-file-reader bypasses Claude Code's 25,000 token Read tool limit.

### Step 4: Activate Task-Master

Once you've read and understood the PRD, activate TaskMaster:

```bash
task-master parse-prd docs/PRD.md
```

**Expected Behavior:**
- TaskMaster will parse the PRD
- Generate `tasks.json` in `.taskmaster/` directory
- Create task hierarchy with dependencies
- Output task summary

### Step 5: Verify Task Generation

Check that tasks were created successfully:

```bash
task-master list
```

You should see a structured list of tasks with:
- Task IDs
- Descriptions
- Status (pending/in-progress/done)
- Dependencies
- Subtasks (if applicable)

### Step 6: Emit Phase Signal

Once tasks are generated and verified, emit a signal for phase transition:

```bash
echo '{"phase":"TASK_DECOMPOSITION_COMPLETE","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","status":"success"}' > .claude/.signals/phase-complete.json
```

## Error Handling

### If PRD Not Found
- Ask the user for the PRD location
- Suggest they place it in `docs/PRD.md`
- Provide the [PRD template link](../templates/PRD-template.md)

### If Task-Master Not Installed
```bash
# Check if task-master is available
which task-master || echo "TaskMaster not installed. Run: npm install -g @anthropic/task-master"
```

### If Large File Reader Fails
- Verify the file exists
- Check file permissions
- Try reading in chunks using the Read tool with offset/limit parameters

## Skill Activation Context

**Skill Name:** PRD_TO_TASKS_V1
**Activation Method:** Slash Command (workaround for broken UserPromptSubmit hooks)
**Expected Output:** Structured tasks.json with native TaskMaster schema

This skill is part of the Claude Dev Pipeline's Phase 1: Task Decomposition & Planning.

## Notes

- This command works around the UserPromptSubmit hook bug (GitHub Issue #10287)
- When the bug is fixed, this slash command will remain as a convenient explicit activation method
- The PreToolUse hook may also activate this skill if you naturally run `task-master parse-prd`
- Keep both methods available for maximum reliability

## Usage Examples

```
# Basic usage (auto-detects PRD location)
/parse-prd

# Specify custom PRD location
/parse-prd path/to/my-requirements.md

# With debug mode
/parse-prd --debug
```
