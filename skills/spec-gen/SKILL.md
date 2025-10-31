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

Automates Phase 2: OpenSpec proposal creation with coupling analysis in isolated worktrees

- **Batched processing** (5-10 tasks per batch) in separate worktrees
- **Coupling analysis** (tight vs loose) within batch isolation
- **OpenSpec proposal creation** (with TDD) per batch worktree
- **Integration map updates** merged sequentially
- **Completion signal** → triggers Phase 3
- **NEW**: Worktree isolation prevents cross-batch contamination
- **NEW**: Atomic batch processing with merge validation

## Execution Flow

```
Stage 1: Load Phase 1 Results
Stage 2: Determine Batching  
Stage 3: Process Batches
         - Analyze coupling
         - Create proposals
         - Update map
Stage 4: Validate Proposals
Stage 5: Generate Summary
Stage 6: Create Signal → Phase 3
```

## Time Estimates

| Tasks | Batches | Total |
|-------|---------|-------|
| 10-15 | 1-2     | 15-40 min |
| 16-20 | 2-3     | 30-60 min |
| 21-25 | 4-5     | 60-100 min |

## Completion Signal

```json
{
  "phase": 2,
  "status": "success",
  "summary": {
    "tasks_processed": N,
    "proposals_created": M,
    "tightly_coupled": X,
    "loosely_coupled": Y
  },
  "next_phase": 3,
  "trigger_next": true
}
```

## Output Files

- `openspec/changes/*/proposal.md`
- `TASKMASTER_OPENSPEC_MAP.md` (updated)
- `.taskmaster/phase2-summary.md`
- `.taskmaster/.signals/phase2-complete.json`

## See Also

- Pipeline Orchestrator (triggers this)
- Coupling Analysis skill (used during execution)
- Test Strategy Generator skill (auto-enhances proposals)