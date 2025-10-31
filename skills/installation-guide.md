# Skills Installation Guide (Updated for Official Format)

## Overview

This guide installs all four TaskMaster + OpenSpec workflow skills following the official Claude Code skill format.

**Official Docs:** https://docs.claude.com/en/docs/claude-code/skills

---

## Skill Directory Structure

### Personal Skills (Available Across All Projects)
```
~/.claude/skills/
├── prd-to-tasks/
│   ├── SKILL.md (with YAML frontmatter)
│   └── examples/
│       └── good-prd-parsing.md
├── coupling-analysis/
│   ├── SKILL.md (with YAML frontmatter)
│   └── examples/
│       └── tightly-coupled-examples.md
├── test-strategy-generator/
│   └── SKILL.md (with YAML frontmatter)
└── integration-validator/
    └── SKILL.md (with YAML frontmatter)
```

### Project Skills (Shared with Team)
```
your-project/
└── .claude/skills/
    ├── prd-to-tasks/
    ├── coupling-analysis/
    ├── test-strategy-generator/
    └── integration-validator/
```

---

## Quick Installation (5 Minutes)

### Option 1: Personal Skills (For You Only)

```bash
# Create personal skills directory
mkdir -p ~/.claude/skills

# Copy all four skills
cp -r /mnt/user-data/outputs/prd-to-tasks-skill ~/.claude/skills/prd-to-tasks
cp -r /mnt/user-data/outputs/coupling-analysis-skill ~/.claude/skills/coupling-analysis
cp -r /mnt/user-data/outputs/test-strategy-generator-skill ~/.claude/skills/test-strategy-generator
cp -r /mnt/user-data/outputs/integration-validator-skill ~/.claude/skills/integration-validator

# Verify installation
ls -la ~/.claude/skills/
```

**Result:** Skills available in ALL your Claude Code projects.

### Option 2: Project Skills (Share with Team)

```bash
# From your project root
cd /path/to/your/project

# Create project skills directory
mkdir -p .claude/skills

# Copy all four skills
cp -r /mnt/user-data/outputs/prd-to-tasks-skill .claude/skills/prd-to-tasks
cp -r /mnt/user-data/outputs/coupling-analysis-skill .claude/skills/coupling-analysis
cp -r /mnt/user-data/outputs/test-strategy-generator-skill .claude/skills/test-strategy-generator
cp -r /mnt/user-data/outputs/integration-validator-skill .claude/skills/integration-validator

# Commit to git
git add .claude/skills
git commit -m "Add TaskMaster + OpenSpec workflow skills"
git push

# Verify installation
ls -la .claude/skills/
```

**Result:** Skills available to ALL team members who pull the repo.

---

## Verification Tests

### Test 1: Verify Skill Files Exist

```bash
# Personal skills
ls ~/.claude/skills/*/SKILL.md

# Project skills
ls .claude/skills/*/SKILL.md

# Expected output (4 files):
# prd-to-tasks/SKILL.md
# coupling-analysis/SKILL.md
# test-strategy-generator/SKILL.md
# integration-validator/SKILL.md
```

### Test 2: Verify YAML Frontmatter

```bash
# Check PRD-to-Tasks skill has proper frontmatter
head -10 ~/.claude/skills/prd-to-tasks/SKILL.md

# Expected output:
# ---
# description: |
#   Generates production-grade TaskMaster tasks.json from Product Requirements Documents (PRD).
#   ...
# ---
```

### Test 3: Test Skill Activation

**Test PRD-to-Tasks Skill:**
```
In Claude Code, say:
"I have a PRD, can you generate tasks.json from it?"

Expected: Skill activates, Claude mentions generating tasks with integration tasks
```

**Test Coupling Analysis Skill:**
```
In Claude Code, run:
task-master show 5

Expected: Skill activates, Claude analyzes coupling (tightly vs loosely)
```

**Test Test Strategy Generator Skill:**
```
In Claude Code, say:
"Create an OpenSpec proposal for user authentication"

Expected: Skill activates, Claude includes test strategy with 60/30/10 distribution
```

**Test Integration Validator Skill:**
```
In Claude Code, say:
"Show me the architecture.md file"

Expected: Skill activates, Claude identifies integration points to validate
```

---

## YAML Frontmatter Format

Each SKILL.md now follows the official format:

```markdown
---
description: |
  Brief description of what the skill does.
  Include when Claude should use it.
  Mention key trigger words and phrases.
  
  Key triggers: "keyword1", "keyword2", "command"
---

# Skill Name

## What This Skill Does

[Clear explanation of capabilities]

## When This Skill Activates

[Explicit trigger patterns]

[Rest of skill content...]
```

**Key Points:**
- `description` field is CRITICAL for Claude to discover when to use the skill
- Include specific trigger keywords users would mention
- Keep description focused on WHAT and WHEN

---

## How Skills Are Invoked

**Model-Invoked (Automatic):**
- Claude autonomously decides when to use skills
- Based on user's request and skill's description
- No explicit command needed (unlike `/slash` commands)

**Example Flow:**
```
User: "Can you generate tasks from this PRD?"
  ↓
Claude reads all skill descriptions
  ↓
PRD-to-Tasks description matches "PRD" and "generate tasks"
  ↓
Claude activates PRD-to-Tasks skill
  ↓
Skill provides guidance for task generation
```

---

## Skill Descriptions Reference

### PRD-to-Tasks Skill
```yaml
description: |
  Generates production-grade TaskMaster tasks.json from Product Requirements Documents (PRD). 
  Use this skill when the user mentions "PRD", "generate tasks", "parse PRD", or provides 
  a requirements document. Always generates integration tasks (Tasks #N-2, #N-1, #N) for 
  component integration testing, E2E workflows, and production readiness validation.
  
  Key triggers: "generate tasks.json", "parse the PRD", "create tasks from requirements"
```

### Coupling Analysis Skill
```yaml
description: |
  Analyzes TaskMaster tasks to determine if subtasks are tightly coupled (share code/models) 
  or loosely coupled (independent modules), enabling optimal OpenSpec proposal strategy and 
  parallelization decisions. Use when user runs 'task-master show' command, asks about 
  coupling, mentions "parallel", or needs proposal strategy guidance for Phase 2.
  
  Key triggers: "task-master show", "tightly coupled", "loosely coupled", "can I parallelize", 
  "one proposal or multiple", "proposal strategy"
```

### Test Strategy Generator Skill
```yaml
description: |
  Generates comprehensive test strategies and test templates from OpenSpec proposals, enforcing 
  Test-Driven Development (TDD). Use when user creates or views OpenSpec proposals, starts 
  implementation, or asks about testing. Provides 60/30/10 test distribution (unit/integration/e2e), 
  test templates in Arrange-Act-Assert format, coverage projections, and mocking strategies.
  
  Key triggers: "/openspec:proposal", "openspec show", "/openspec:apply", "what tests should I write", 
  "test strategy", "TDD", "test coverage"
```

### Integration Validator Skill
```yaml
description: |
  Validates all integration points are tested and generates production readiness scores before 
  deployment. Use when reading architecture.md, starting Tasks #24-26 (integration testing, 
  E2E workflows, production validation), or user asks "are we ready for production". Parses 
  architecture diagrams to find integration points, validates test coverage, scores production 
  readiness 0-100%, provides Go/No-Go recommendations with remediation plans.
  
  Key triggers: "architecture.md", "Task #24", "Task #25", "Task #26", "integration testing", 
  "production ready", "ready to deploy", "Go/No-Go"
```

---

## Troubleshooting

### Skill Not Activating

**Problem:** Claude doesn't use your skill when expected.

**Debug Steps:**

1. **Verify file exists:**
   ```bash
   ls ~/.claude/skills/skill-name/SKILL.md
   # OR
   ls .claude/skills/skill-name/SKILL.md
   ```

2. **Check YAML syntax:**
   ```bash
   head -15 ~/.claude/skills/skill-name/SKILL.md
   ```
   
   Verify:
   - Opening `---` on line 1
   - Closing `---` before Markdown content
   - Valid YAML (no tabs, correct indentation)

3. **Test description specificity:**
   - Does description include words user mentioned?
   - Are trigger keywords present?

4. **Run Claude Code with debug mode:**
   ```bash
   CLAUDE_DEBUG=1 claude-code
   ```

### Skill Has Errors

**Problem:** Skill loads but doesn't work correctly.

**Solutions:**

1. **Check for missing dependencies:**
   - Claude will ask to install dependencies when needed
   - Ensure TaskMaster and OpenSpec are installed

2. **Verify file paths:**
   ```bash
   # Correct (Unix)
   scripts/helper.py
   
   # Wrong (Windows style)
   scripts\helper.py
   ```

---

## Sharing Skills with Your Team

### Recommended: Via Git (Project Skills)

**Step 1: Add to project**
```bash
mkdir -p .claude/skills
cp -r ~/.claude/skills/* .claude/skills/
```

**Step 2: Commit**
```bash
git add .claude/skills
git commit -m "Add TaskMaster + OpenSpec workflow skills"
git push
```

**Step 3: Team members pull**
```bash
git pull
```

Skills are immediately available - no additional setup needed!

---

## Best Practices

### Keep Skills Focused
- ✅ One skill = one capability
- ✅ "PRD-to-Tasks" (specific)
- ❌ "Document processing" (too broad)

### Write Clear Descriptions
Include:
- What the skill does
- When Claude should use it
- Specific trigger keywords

### Test with Your Team
- Does skill activate when expected?
- Are instructions clear?
- Missing examples or edge cases?

---

## Updating Skills

### Update a Skill
```bash
# Edit SKILL.md directly
vim ~/.claude/skills/skill-name/SKILL.md

# Or for project skills
vim .claude/skills/skill-name/SKILL.md

# Commit if project skill
git add .claude/skills/skill-name/SKILL.md
git commit -m "Update skill: add new examples"
git push
```

### Remove a Skill
```bash
# Remove directory
rm -rf ~/.claude/skills/skill-name

# For project skills, commit the deletion
git rm -rf .claude/skills/skill-name
git commit -m "Remove skill: no longer needed"
git push
```

---

## Success Checklist

After installation, verify:

- [ ] All 4 skill directories exist
- [ ] Each SKILL.md has YAML frontmatter
- [ ] YAML frontmatter has `description` field
- [ ] Description includes trigger keywords
- [ ] Test activation works (try trigger phrases)
- [ ] Team members have access (if project skills)

---

## Next Steps

1. **✅ Installation complete** - Skills are ready to use
2. **🎯 Test each skill** - Try trigger phrases in Claude Code
3. **📖 Read workflow docs** - Understand when each skill activates
4. **🚀 Start building** - Skills activate automatically during workflow

**You're ready!** Skills will enhance your development process automatically. 🎉

---

## Quick Reference

### Installation Commands
```bash
# Personal skills (all projects)
cp -r /mnt/user-data/outputs/*-skill ~/.claude/skills/

# Project skills (share with team)
cp -r /mnt/user-data/outputs/*-skill .claude/skills/
```

### Verification
```bash
# Check files exist
ls ~/.claude/skills/*/SKILL.md

# Check YAML syntax
head -15 ~/.claude/skills/*/SKILL.md
```

### Trigger Phrases
- PRD-to-Tasks: "generate tasks.json", "parse PRD"
- Coupling Analysis: "task-master show", "tightly coupled"
- Test Strategy Generator: "/openspec:proposal", "test strategy"
- Integration Validator: "architecture.md", "production ready"

---

**Installation Time:** 5 minutes  
**Format:** Official Claude Code skill format  
**Compatibility:** Claude Code 1.0+  
**Documentation:** https://docs.claude.com/en/docs/claude-code/skills