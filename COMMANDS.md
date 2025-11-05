# Slash Commands Reference

This document describes the available slash commands in the Claude Dev Pipeline.

## Overview

Slash commands provide explicit, reliable ways to activate pipeline features that bypass the broken UserPromptSubmit hook system in Claude Code v2.0.26-2.0.32.

**When to use slash commands:**
- When you want guaranteed activation (100% reliability)
- When natural language prompts aren't triggering the right behavior
- When you need explicit control over pipeline phases

**When hooks work automatically:**
- PreToolUse and PostToolUse hooks still function normally
- These provide automatic skill activation when Claude naturally uses certain tools

## Available Commands

### `/orchestrate` - Master Pipeline Control

**Phase:** 0 → 6 (Full Pipeline)
**Skill:** `PIPELINE_ORCHESTRATION_V1`

Starts complete autonomous development from Phase 1 through Phase 6.

**Usage:**
```
/orchestrate
```

**What it does:**
- Initializes pipeline state
- Orchestrates all 6 phases autonomously
- Handles manual approval gates (Phase 5 GO/NO-GO, Phase 6 deployment)
- Monitors progress and signals
- Provides 95% automation

**When to use:** Starting a new development cycle from PRD to production deployment.

**See:** [commands/orchestrate.md](commands/orchestrate.md)

---

### `/parse-prd` - Phase 1: Task Decomposition

**Phase:** 1
**Skill:** `PRD_TO_TASKS_V1`

Parse Product Requirements Document and generate structured task hierarchy.

**Usage:**
```
/parse-prd
/parse-prd path/to/requirements.md
```

**What it does:**
1. Locates your PRD (checks `docs/PRD.md`, `PRD.md`, or custom path)
2. Checks file size and uses appropriate reader (<25K tokens: Read tool, ≥25K: large-file-reader)
3. Activates TaskMaster to parse and generate `tasks.json`
4. Performs coupling analysis
5. Emits phase completion signal

**Expected output:**
- Task list in `.taskmaster/tasks.json`
- Task hierarchy with dependencies
- Coupling analysis data

**When to use:** Starting Phase 1, or when you have a new/updated PRD.

**See:** [commands/parse-prd.md](commands/parse-prd.md)

---

### `/generate-specs` - Phase 2: Specification Generation

**Phase:** 2
**Skill:** `SPEC_GEN_V1`

Generate OpenSpec technical specifications and test strategies from tasks.

**Usage:**
```
/generate-specs
```

**What it does:**
1. Reviews coupling analysis from Phase 1
2. Groups tasks into batches (5-10 tasks per batch)
3. Creates git worktrees for isolation
4. Generates OpenSpec proposals for each batch
5. Defines test strategies

**Expected output:**
- `.openspec/proposals/` - OpenSpec proposals per batch
- `.openspec/test-strategies/` - Test strategies per batch
- `.worktrees/phase-2-batch-N/` - Isolated worktrees

**Prerequisites:** Phase 1 complete (tasks.json exists)

**When to use:** After task decomposition, before implementation.

**See:** [commands/generate-specs.md](commands/generate-specs.md)

---

### `/implement-tdd` - Phase 3: TDD Implementation

**Phase:** 3
**Skill:** `TDD_IMPLEMENTER_V1`

Implement code following Test-Driven Development (RED-GREEN-REFACTOR cycle).

**Usage:**
```
/implement-tdd
```

**What it does:**
1. Follows RED-GREEN-REFACTOR cycle for each task
2. Enforces tests-first approach (via pre-implementation-validator hook)
3. Creates worktrees per subtask for isolation
4. Validates anti-mock directive (no mock implementations in operational code)
5. Ensures all tests passing before completion

**Expected output:**
- Implemented features in `src/`
- Test files in `src/__tests__/`
- All tests passing with coverage

**Prerequisites:** Phase 2 complete (OpenSpec proposals and test strategies exist)

**When to use:** After specifications ready, to implement features.

**See:** [commands/implement-tdd.md](commands/implement-tdd.md)

---

### `/validate-integration` - Phase 4: Component Integration Testing

**Phase:** 4
**Skill:** `INTEGRATION_VALIDATOR_V1`

Run component integration tests to validate system interactions.

**Usage:**
```
/validate-integration
```

**What it does:**
1. Tests component interactions (API → Services → Data layer)
2. Validates API contracts match OpenSpec
3. Tests data flows and state persistence
4. Verifies error handling and concurrency
5. Checks integration with external systems

**Expected output:**
- All integration tests passing
- Contract validation complete
- Performance benchmarks met

**Prerequisites:** Phase 3 complete (all unit tests passing)

**When to use:** After implementation complete, before E2E testing.

**See:** [commands/validate-integration.md](commands/validate-integration.md)

---

### `/validate-e2e` - Phase 5: End-to-End Production Validation

**Phase:** 5
**Skill:** `E2E_VALIDATOR_V1`

Run end-to-end tests validating complete user workflows in production-like environment.

**Usage:**
```
/validate-e2e
```

**What it does:**
1. Deploys to staging environment
2. Runs complete user workflow tests (E2E)
3. Tests cross-browser compatibility
4. Validates production readiness (security, performance, reliability)
5. **Requests GO/NO-GO decision** before Phase 6

**Expected output:**
- All E2E tests passing
- Production readiness confirmed
- **Manual approval gate:** User must approve "GO" to proceed to deployment

**Prerequisites:** Phase 4 complete (integration tests passing)

**When to use:** After integration testing, before production deployment.

**⚠️ Manual Gate:** This phase requires user approval to proceed to Phase 6.

**See:** [commands/validate-e2e.md](commands/validate-e2e.md)

---

### `/deploy` - Phase 6: Deployment & Rollout

**Phase:** 6
**Skill:** `DEPLOYMENT_ORCHESTRATOR_V1`

Deploy to staging, run canary deployment, and complete progressive production rollout.

**Usage:**
```
/deploy
```

**What it does:**
1. Deploys to staging
2. Runs smoke tests on staging
3. **Requests production deployment approval**
4. Executes canary deployment (10% traffic)
5. Monitors canary metrics (15 minutes)
6. Progressive rollout (10% → 50% → 100%)
7. Post-deployment validation

**Expected output:**
- Staging deployment successful
- Production deployment successful
- Monitoring confirms stability
- **Pipeline complete!**

**Prerequisites:** Phase 5 complete with GO decision recorded

**When to use:** After E2E validation and GO approval received.

**⚠️ Manual Gate:** This phase requires production deployment approval.

**See:** [commands/deploy.md](commands/deploy.md)

---

## Command Summary Table

| Command | Phase | Skill | Manual Gate | Description |
|---------|-------|-------|-------------|-------------|
| `/orchestrate` | 0-6 | `PIPELINE_ORCHESTRATION_V1` | Yes (2 gates) | Full pipeline automation |
| `/parse-prd` | 1 | `PRD_TO_TASKS_V1` | No | Parse PRD → generate tasks |
| `/generate-specs` | 2 | `SPEC_GEN_V1` | No | Create OpenSpec proposals |
| `/implement-tdd` | 3 | `TDD_IMPLEMENTER_V1` | No | TDD implementation |
| `/validate-integration` | 4 | `INTEGRATION_VALIDATOR_V1` | No | Integration testing |
| `/validate-e2e` | 5 | `E2E_VALIDATOR_V1` | Yes (GO/NO-GO) | E2E validation |
| `/deploy` | 6 | `DEPLOYMENT_ORCHESTRATOR_V1` | Yes (Prod approval) | Production deployment |

---

## Usage Patterns

### Full Autonomous Pipeline

Start from PRD and let it run through all phases:

```
/orchestrate
```

This will:
1. Run `/parse-prd` automatically
2. Auto-transition through Phases 2-4
3. Pause at Phase 5 for GO/NO-GO decision
4. Pause at Phase 6 for production deployment approval
5. Complete full deployment

### Manual Phase-by-Phase Control

Run each phase explicitly:

```
/parse-prd
# Wait for completion...

/generate-specs
# Wait for completion...

/implement-tdd
# Wait for completion...

/validate-integration
# Wait for completion...

/validate-e2e
# Approve GO decision...

/deploy
# Approve production deployment...
```

### Restart from Specific Phase

If a phase fails or you want to retry:

```
# Restart from Phase 3 (implementation)
/implement-tdd

# Or restart from Phase 5 (E2E)
/validate-e2e
```

### Skip Phases (Not Recommended)

You can technically skip phases, but it's not recommended:

```
# DON'T DO THIS - skipping directly to deployment
/deploy
# Will likely fail prerequisite checks
```

---

## Workaround Context

**Why slash commands?**

Claude Code v2.0.26-2.0.32 has a bug where UserPromptSubmit hooks don't execute. This means natural language prompts like "generate tasks from my PRD" may not reliably trigger skill activation.

**The hybrid approach:**
1. **Slash commands (this file)** - 100% reliable, explicit control
2. **PreToolUse hooks** - Automatic fallback when Claude uses certain tools
3. **Natural language** - May work if Claude chooses the right tool

**When the bug is fixed:**
- UserPromptSubmit hooks will work again
- Natural language prompts will reliably activate skills
- Slash commands will remain as explicit alternatives
- You'll have maximum flexibility with all three methods working

**Related documentation:**
- [KNOWN-ISSUES.md](KNOWN-ISSUES.md) - Details on the bug and workarounds
- [BUG-REPORT-USERPROMPTSUBMIT.md](BUG-REPORT-USERPROMPTSUBMIT.md) - Comprehensive bug report
- [GitHub Issue #10287](https://github.com/anthropics/claude-code/issues/10287) - Official bug tracking

---

## Creating Custom Commands

You can add your own slash commands to the pipeline:

1. Create a markdown file in `commands/` directory
2. Add frontmatter with description:
   ```markdown
   ---
   description: Your command description
   ---
   ```
3. Write instructions for Claude to follow
4. Test with `/your-command-name`

**Command naming conventions:**
- Use lowercase with hyphens: `parse-prd`, `run-tests`
- Keep names short and memorable
- Prefix with verb: `run`, `generate`, `validate`, `deploy`

**Example command structure:**
```markdown
---
description: Brief one-line description
---

# Command Name

## Your Task

Clear instructions for what Claude should do when this command is invoked.

### Step 1: First Action
Details...

### Step 2: Second Action
Details...

## Expected Output
What should happen...

## Error Handling
How to handle problems...
```

---

**Last Updated:** 2025-11-05
**Version:** 3.0
