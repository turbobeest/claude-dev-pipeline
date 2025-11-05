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
wc -w docs/PRD.md | awk '{print "Words:", $1, "| Est. tokens:", int($1 * 2.5)}'
```

**Token Estimation:**
- Technical PRDs with markdown/code average **2.5 tokens per word**
- This is more conservative than simple text (1.3x) due to:
  - Markdown formatting (headers, lists, code blocks)
  - Technical terminology
  - Code examples and snippets
  - URLs and special characters

**IMPORTANT File Size Rules:**
- **< 10,000 words (≈25K tokens)**: Use Read tool directly
- **≥ 10,000 words (≈25K tokens)**: Use large-file-reader utility

**When in doubt, use large-file-reader** - it handles files of any size.

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

### Step 4: Generate Master Tasks (Direct AI Generation)

**CRITICAL:** Do NOT call `task-master parse-prd`! For initial task generation from a PRD, YOU must generate the master tasks directly through AI analysis.

**Why:** The PRD-to-Tasks skill generates MASTER TASKS ONLY (no subtasks). TaskMaster's `parse-prd` command is for appending additional tasks to an existing tasks.json, not for initial generation.

**Process:**
1. Analyze the PRD structure you just read
2. Identify major feature areas and epics
3. Create master tasks (numbered 1, 2, 3, etc.) with:
   - Unique ID (numeric)
   - Clear title
   - Detailed description
   - Priority (critical/high/medium/low)
   - Dependencies (if any)
   - Empty subtasks array (subtasks added in Phase 2)
4. Generate tasks.json directly with native TaskMaster schema

**Example tasks.json structure:**
```json
{
  "master": {
    "tasks": [
      {
        "id": "1",
        "title": "Core Infrastructure Setup",
        "description": "Set up development environment, CI/CD, and deployment pipeline",
        "status": "pending",
        "priority": "critical",
        "dependencies": [],
        "subtasks": []
      },
      {
        "id": "2",
        "title": "User Authentication System",
        "description": "Implement JWT-based authentication with OAuth2 providers",
        "status": "pending",
        "priority": "high",
        "dependencies": ["1"],
        "subtasks": []
      }
    ]
  }
}
```

**Save to:**
```bash
# Write generated tasks.json to TaskMaster directory
# Use Write tool: .taskmaster/tasks/tasks.json
```

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

### Step 7: STOP HERE - Display Completion Message

**CRITICAL: DO NOT PROCEED AUTOMATICALLY TO NEXT PHASE**

Display this message and STOP:

```
═══════════════════════════════════════════════════════════
  🎯 PHASE 1 COMPLETE - Task Decomposition Finished
═══════════════════════════════════════════════════════════

  ✅ Tasks generated successfully
  ✅ Dependencies mapped

  ⏸️  PIPELINE STOPPED - Awaiting your command

  👉 To proceed to Phase 2 (Specification Generation), type:

     /generate-specs

  📋 Or review tasks first: task-master list

═══════════════════════════════════════════════════════════
```

**DO NOT:**
- ❌ Run analyze-complexity automatically
- ❌ Run expand tasks automatically
- ❌ Start Phase 2 on your own
- ❌ Be "helpful" and continue the workflow

**WAIT FOR THE USER TO TYPE THE NEXT SLASH COMMAND.**

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
- **Important:** `task-master parse-prd` is for APPENDING tasks to existing tasks.json, not initial generation
- This skill generates master tasks via direct AI analysis, then subtasks are added in Phase 2
- TaskMaster's complexity analysis and expand commands happen in Phase 2 after master tasks exist

## Usage Examples

```
# Basic usage (auto-detects PRD location)
/parse-prd

# Specify custom PRD location
/parse-prd path/to/my-requirements.md

# With debug mode
/parse-prd --debug
```
