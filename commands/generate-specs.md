---
description: Generate OpenSpec proposals and test strategies (Phase 2)
---

# Specification Generation - Phase 2

**🔧 WORKAROUND MODE ACTIVE** - Manual activation for Phase 2 spec generation.

## Your Task

Activate the **Spec Generator** skill (`SPEC_GEN_V1`) to create OpenSpec technical specifications and test strategies from TaskMaster tasks.

## Prerequisites

```bash
# 1. Phase 1 must be complete
[ -f .taskmaster/tasks.json ] && echo "✅ tasks.json exists" || echo "❌ Phase 1 incomplete"

# 2. Coupling analysis should be done
grep -q "coupling" .taskmaster/tasks.json && echo "✅ Coupling data present" || echo "⚠️  Run coupling analysis"

# 3. OpenSpec available
which openspec && echo "✅ OpenSpec ready" || echo "❌ OpenSpec not installed"
```

## Activation

### Method 1: Codeword Injection

```
[ACTIVATE:SPEC_GEN_V1]
```

### Method 2: Direct Skill Reference

Read the skill instructions:

```bash
cat .claude/skills/spec-gen/SKILL.md
```

Then follow the workflow defined there.

## TaskMaster Preparation (Required First)

**Before generating specs, you must prepare subtasks using TaskMaster:**

### Step 1: Analyze Task Complexity

```bash
# Analyze complexity of all master tasks
task-master analyze-complexity --research

# Or analyze specific range
task-master analyze-complexity --from=1 --to=5 --research
```

This generates `.taskmaster/reports/task-complexity-report.json` with:
- Complexity scores for each task
- Recommended subtask counts
- Technical dependencies
- Risk assessments

### Step 2: Review Complexity Report

```bash
# View the report
task-master complexity-report

# Or read directly
cat .taskmaster/reports/task-complexity-report.json
```

Identify which tasks need subtask expansion (typically high/critical complexity tasks).

### Step 3: Expand Tasks into Subtasks

```bash
# Expand all eligible tasks automatically
task-master expand --all --research

# Or expand specific tasks
task-master expand --id=1 --research
task-master expand --id=2 --research

# Force expansion even if already has subtasks
task-master expand --id=3 --research --force
```

This creates subtasks (1.1, 1.2, 2.1, 2.2, etc.) with:
- Specific implementation steps
- Technical details
- Test strategies
- Dependencies

### Step 4: Verify Task Structure

```bash
# List all tasks including subtasks
task-master list

# View specific task with subtasks
task-master show 1
```

**Now you're ready for OpenSpec specification generation.**

---

## OpenSpec Specification Generation Workflow

**CRITICAL:** You must now execute the Spec Generator skill workflow. This is the core of Phase 2.

### Step 1: Read the Spec Generator Skill

```bash
cat .claude/skills/spec-gen/SKILL.md
```

### Step 2: Execute ALL Stages in Order

You must complete these stages sequentially:

**Stage 1: Load TaskMaster Results**
- Read `.taskmaster/tasks/tasks.json`
- Extract all master tasks and their subtasks
- Count total subtasks (this equals number of proposals to create)

**Stage 2: Determine Batching**
- Group master tasks into batches (5-10 tasks per batch)
- Plan worktree isolation strategy
- Identify dependencies between batches

**Stage 3: Create OpenSpec Proposals**
- Create 1 proposal per subtask (1:1 mapping)
- Path: `openspec/changes/[task-name]-subtask-[id]/proposal.md`
- Include: title, description, test strategy, dependencies
- Update `TASKMASTER_OPENSPEC_MAP.md` as you go

**Stage 4: Validate Proposals**
- Verify all subtasks have proposals
- Check proposal format and completeness
- Validate cross-proposal dependencies

**Stage 5: Generate Summary**
- Count proposals created
- Document batching strategy
- List any issues encountered

**Stage 6: Create Completion Signal**
- Update `.claude/.signals/phase2-complete.json`
- Include: proposals_created, batches_processed, status

### Step 3: Expected Outputs

When complete, you should have:
- **Proposals:** One per subtask in `openspec/changes/[task-name]-subtask-[id]/proposal.md`
- **Mapping:** `TASKMASTER_OPENSPEC_MAP.md` showing task → proposal relationships
- **Worktrees:** `.worktrees/phase-2-batch-[1-4]/` (if using worktree isolation)
- **Signal:** Updated `.claude/.signals/phase2-complete.json` with proposal count

### Step 4: Verification

Before proceeding, verify:
```bash
# Count proposals (should equal subtask count)
find openspec/changes -name "proposal.md" | wc -l

# Verify mapping file exists
ls -lh TASKMASTER_OPENSPEC_MAP.md

# Check signal file
cat .claude/.signals/phase2-complete.json
```

**DO NOT skip the workflow execution.** Phase 2 is not complete until all proposals are created.

---

## What This Phase Does (Summary)

1. **Analyze Coupling**: Review coupling analysis from Phase 1
2. **Identify Batches**: Group tightly coupled tasks (5-10 tasks per batch)
3. **Create Worktrees**: Isolate each batch in dedicated git worktree
4. **Generate Proposals**: Create OpenSpec proposals for each batch
5. **Define Test Strategies**: Specify testing approach per batch
6. **Review & Validate**: Ensure specs are complete and consistent

## Expected Outputs

After completion, you should have:

```
.openspec/
├── proposals/
│   ├── batch-1-auth-system.md
│   ├── batch-2-data-layer.md
│   ├── batch-3-api-endpoints.md
│   └── ...
└── test-strategies/
    ├── batch-1-test-strategy.md
    ├── batch-2-test-strategy.md
    └── ...

.worktrees/
├── phase-2-batch-1/
├── phase-2-batch-2/
└── ...

.claude/.signals/
└── phase2-complete.json
```

## Worktree Strategy

**CRITICAL**: Each batch MUST be in isolated worktree:

```bash
# Create worktree for batch N
./.claude/lib/worktree-manager.sh create 2 <batch_number>

# Navigate to worktree
cd .worktrees/phase-2-batch-<batch_number>

# Generate specs in isolation
openspec proposal create ...

# Validate isolation
./.claude/hooks/worktree-enforcer.sh enforce
```

## Success Criteria

Phase 2 complete when:
- ✅ All tasks grouped into batches
- ✅ OpenSpec proposal for each batch
- ✅ Test strategy defined for each batch
- ✅ No coupling conflicts between batches
- ✅ Signal emitted: `PHASE2_COMPLETE`

## Phase Complete - STOP HERE

When Phase 2 is complete, display this message and STOP:

```
═══════════════════════════════════════════════════════════
  🎯 PHASE 2 COMPLETE - Specification Generation Finished
═══════════════════════════════════════════════════════════

  ✅ OpenSpec proposals created
  ✅ Test strategies defined

  ⏸️  PIPELINE STOPPED - Awaiting your command

  👉 To proceed to Phase 3 (TDD Implementation), type:

     /implement-tdd

  📋 Review specs: ls -lh .openspec/proposals/

═══════════════════════════════════════════════════════════
```

**CRITICAL: DO NOT PROCEED AUTOMATICALLY**
- ❌ Do NOT start TDD implementation on your own
- ❌ Do NOT begin writing tests
- ❌ Do NOT be "helpful" and continue

**WAIT FOR USER TO TYPE: /implement-tdd**

## Troubleshooting

**Coupling analysis missing:**
```bash
# Run coupling analysis
task-master analyze-coupling
```

**OpenSpec errors:**
```bash
# Check OpenSpec config
cat .openspec/config.json

# Verify proposal format
openspec validate .openspec/proposals/batch-1-*.md
```

**Worktree conflicts:**
```bash
# List worktrees
git worktree list

# Clean stale worktrees
git worktree prune
```

## Related Commands

- `/parse-prd` - Phase 1 (prerequisite)
- `/implement-tdd` - Phase 3 (next phase)
- `/orchestrate` - Full pipeline control
