---
activation_code: SPEC_GEN_V1
phase: 2
prerequisites:
  - tasks.json with coupling analysis
outputs:
  - .openspec/proposals/*.md
  - .signals/phase2-complete.json
description: |
  Generates OpenSpec proposals from TaskMaster tasks based on coupling analysis.
  Activates via codeword [ACTIVATE:SPEC_GEN_V1] injected by hooks when
  moving to Phase 2 specification generation.
  
  Activation trigger: [ACTIVATE:SPEC_GEN_V1]
---

# Spec Generator Skill

## Activation Method

This skill activates when the hook system injects the codeword:
```
[ACTIVATE:SPEC_GEN_V1]
```

This occurs when:
- Phase 1 is complete (task decomposition done)
- User requests OpenSpec proposal generation
- Moving to Phase 2 of development

## Worktree Isolation Requirements

**CRITICAL**: This skill MUST operate in dedicated worktrees per batch `phase-2-task-N`:

```bash
# For each batch:
./lib/worktree-manager.sh create 2 <batch_number>
cd ./worktrees/phase-2-task-<batch_number>

# Validate isolation:
./hooks/worktree-enforcer.sh enforce

# Spec generation with batch isolation
```

### Batch-Worktree Strategy
1. **One worktree per batch**: Each batch (5-10 tasks) gets isolated workspace
2. **Sequential batch processing**: Complete batch N before starting batch N+1
3. **Atomic batch commits**: Each batch merged separately to prevent conflicts
4. **Cross-batch isolation**: No dependencies between batch worktrees


## What This Skill Does

Automates Phase 2: OpenSpec proposal creation from TaskMaster subtasks in isolated worktrees

- **Batched processing** (5-10 master tasks per batch) in separate worktrees
- **1 proposal per subtask** (simple 1:1 mapping, no conditional logic)
- **OpenSpec proposal creation** (with TDD) per batch worktree
- **Integration map updates** merged sequentially
- **Completion signal** → triggers Phase 3
- **NEW**: Worktree isolation prevents cross-batch contamination
- **NEW**: Atomic batch processing with merge validation
- **SIMPLIFIED**: Always creates 1 proposal per subtask for clarity

## Execution Flow

```
Stage 1: Load TaskMaster Results (hierarchical format)
Stage 2: Determine Batching (by master tasks)
Stage 3: Process Batches
         - Extract all subtasks from master tasks
         - Create 1 proposal per subtask
         - Update map
Stage 4: Validate Proposals
Stage 5: Generate Summary
Stage 6: Create Signal → Phase 3
```

## Stage 1: Load TaskMaster Results

### Read TaskMaster Hierarchical Format

Load `.taskmaster/tasks/tasks.json`:
```json
{
  "master": {
    "tasks": [
      {
        "id": 1,
        "name": "User Authentication",
        "subtasks": [
          {"id": 1, "title": "Create user model", "testStrategy": "..."},
          {"id": 2, "title": "Add authentication", "testStrategy": "..."},
          {"id": 3, "title": "Add profile fields", "testStrategy": "..."}
        ]
      }
    ]
  }
}
```

**Extract:**
- Master task count (expect 8-12)
- Subtasks per master task (expect 3-8 each)
- Total subtasks (expect 30-60)
- Dependencies from TaskMaster structure

## Stage 2: Determine Batching

**Batch by master tasks (5-10 per batch):**
- Batch 1: Process master tasks 1-8
- Batch 2: Process master tasks 9-12 (if needed)

**Within each batch:**
- Process all subtasks from included master tasks
- Create 1 proposal per subtask (simple 1:1 mapping)

## Stage 3: Create OpenSpec Proposals

**For each subtask in each master task:**

1. **Create proposal file:**
   - Path: `openspec/changes/[change-id]/proposal.md`
   - Name pattern: `[master-task-name]-subtask-[id]`
   - Example: `user-authentication-subtask-1`

2. **Proposal content from subtask:**
   - Title: From subtask.title
   - Test Strategy: From subtask.testStrategy
   - Acceptance Criteria: From subtask.acceptanceCriteria
   - Dependencies: From TaskMaster dependencies

3. **Update TASKMASTER_OPENSPEC_MAP.md:**
   ```markdown
   ## Master Task 1: User Authentication
   - Subtask 1.1 → Proposal: user-authentication-subtask-1
   - Subtask 1.2 → Proposal: user-authentication-subtask-2
   - Subtask 1.3 → Proposal: user-authentication-subtask-3
   ```

**Result:** Total proposals = Total subtasks (30-60 proposals)

## Time Estimates

**Based on master tasks (not subtasks):**

| Master Tasks | Batches | Subtasks | Proposals | Total Time |
|--------------|---------|----------|-----------|------------|
| 8-10         | 1-2     | 30-40    | 30-40     | 20-40 min  |
| 10-12        | 2       | 40-50    | 40-50     | 30-50 min  |
| 12-15        | 2-3     | 50-60    | 50-60     | 40-70 min  |

**Note:** 1 proposal created per subtask, so proposal count = subtask count

## Completion Signal

```json
{
  "phase": 2,
  "status": "success",
  "summary": {
    "master_tasks_processed": N,
    "subtasks_processed": M,
    "proposals_created": M,
    "mapping_strategy": "1-proposal-per-subtask"
  },
  "next_phase": 3,
  "trigger_next": true
}
```

**Note:** `subtasks_processed` always equals `proposals_created` (1:1 mapping)

## Output Files

- `openspec/changes/*/proposal.md`
- `TASKMASTER_OPENSPEC_MAP.md` (updated)
- `.taskmaster/phase2-summary.md`
- `.taskmaster/.signals/phase2-complete.json`

## See Also

- Pipeline Orchestrator (triggers this)
- PRD-to-Tasks skill (generates TaskMaster format)
- TaskMaster documentation (for hierarchical structure)
- Test Strategy Generator skill (auto-enhances proposals)