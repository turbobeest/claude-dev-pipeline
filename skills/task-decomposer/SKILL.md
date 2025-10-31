---
activation_code: TASK_DECOMPOSER_V1
phase: 1
prerequisites:
  - tasks.json
outputs:
  - .signals/phase1-complete.json
  - expanded tasks in tasks.json
description: |
  Analyzes task complexity and generates subtasks for high-complexity items.
  Activates via codeword [ACTIVATE:TASK_DECOMPOSER_V1] injected by hooks
  after coupling analysis or when explicitly requested.
  
  Activation trigger: [ACTIVATE:TASK_DECOMPOSER_V1]
---

# Task Decomposer Skill

## Activation Method

This skill activates when the hook system injects the codeword:
```
[ACTIVATE:TASK_DECOMPOSER_V1]
```

This occurs when:
- Coupling analysis is complete
- User requests task expansion
- High-complexity tasks detected (score > 7)

## Worktree Isolation Requirements

**CRITICAL**: This skill MUST operate in a dedicated worktree `phase-1-task-3` for task decomposition:

```bash
# Before skill activation:
./lib/worktree-manager.sh create 1 3
cd ./worktrees/phase-1-task-3

# Validate isolation:
./hooks/worktree-enforcer.sh enforce

# Task decomposition with strict isolation
```

### Worktree-Based Decomposition
1. **Isolated expansion**: Each complex task expanded in isolated environment
2. **Safe subtask generation**: No interference with other decomposition work
3. **Atomic commits**: Each task expansion committed separately
4. **Merge validation**: Changes merged only after validation passes

# Task Decomposer Skill

## What This Skill Does

The **Task Decomposer** automates Phase 1 of the development pipeline in isolated worktree:

- **Analyzes complexity** of all tasks using scientific scoring (0-10 scale)
- **Research-backed expansion** for high-complexity tasks (≥7)
- **Generates subtasks** with complete acceptance criteria and test strategies
- **Preserves checkpoints** at key milestones within worktree
- **Creates completion signal** to trigger Phase 2
- **NEW**: Worktree isolation prevents decomposition conflicts
- **NEW**: Each task expansion gets dedicated workspace

## When This Skill Activates

**Primary Trigger:** Pipeline Orchestrator completes Phase 0 and initiates Phase 1

**Manual Activation:**
- "Begin Phase 1"
- "Start task decomposition"
- "Analyze task complexity"
- "Decompose tasks with TaskMaster"

**Prerequisites:**
- ✅ `.taskmaster/tasks.json` exists (15-25 top-level tasks)
- ✅ Phase 0 checkpoint passed
- ✅ No subtasks present yet (subtasks: [] for all tasks)
- ✅ TaskMaster initialized and responding

## Automated Execution Flow

This skill executes Phase 1 **completely autonomously** with 7 automated stages:

```
Stage 1: Verify Prerequisites ✅
         ↓
Stage 2: Analyze Complexity (task-master analyze-complexity --research)
         ↓
Stage 3: Expand High-Complexity Tasks (task-master expand --id=X --research)
         ↓
Stage 4: Validate Expansion Quality
         ↓
Stage 5: Generate Phase Summary
         ↓
Stage 6: Create Completion Signal (.signals/phase1-complete.json)
         ↓
Stage 7: Final Verification
         ↓
✅ PHASE 1 COMPLETE → Trigger Phase 2
```

## Execution Commands

### Full Automated Execution

```bash
# When activated, skill runs all stages automatically:

# Stage 1: Prerequisites
echo "✅ Verifying prerequisites..."
[checks tasks.json, TaskMaster, no existing subtasks]

# Stage 2: Complexity Analysis
echo "🔍 Analyzing task complexity..."
task-master analyze-complexity --research
task-master complexity-report > .taskmaster/phase1-complexity-report.txt

# Stage 3: Expansion
echo "🔨 Expanding high-complexity tasks..."
for task_id in [high_complexity_ids]; do
  task-master expand --id=$task_id --research
  [save checkpoint every 2 tasks]
done

# Stage 4: Validation
echo "🔍 Validating expansion quality..."
[verify all subtasks have acceptance criteria]

# Stage 5: Summary
echo "📊 Generating phase summary..."
[create .taskmaster/phase1-summary.md]

# Stage 6: Signal
echo "📡 Creating completion signal..."
[create .taskmaster/.signals/phase1-complete.json]

# Stage 7: Verification
echo "🎯 Final verification..."
[verify all success criteria met]

echo "✅ PHASE 1 COMPLETE"
```

## Time Estimates

| Tasks | Analysis | Expansion | Total |
|-------|----------|-----------|-------|
| 10-15 | 3-5 min  | 5-7 min   | 8-12 min |
| 16-20 | 5-8 min  | 8-12 min  | 13-20 min |
| 21-25 | 8-12 min | 12-18 min | 20-30 min |
| 26-30 | 12-15 min| 18-25 min | 30-40 min |

## Completion Signal Schema

```json
{
  "phase": 1,
  "phase_name": "Task Decomposition",
  "status": "success",
  "completed_at": "2025-10-29T15:30:00Z",
  "duration_minutes": 12,
  "summary": {
    "tasks_analyzed": 18,
    "tasks_expanded": 6,
    "subtasks_generated": 28,
    "high_complexity_tasks": [3, 5, 9, 12, 15, 18]
  },
  "next_phase": 2,
  "trigger_next": true
}
```

## Error Recovery

**Automatic Recovery:**
- Missing dependencies → Install & retry
- Transient API errors → Exponential backoff
- Invalid JSON → Restore from checkpoint

**Human Escalation:**
- TaskMaster not installed → Report installation needed
- Persistent API failures → Wait for manual intervention
- Corrupted tasks.json → Restore from Phase 0

## Checkpoint System

Checkpoints saved automatically:
- After complexity analysis
- Every 2 task expansions
- After final expansion
- Before creating completion signal

Resume command: "Resume Phase 1 from checkpoint"

## Success Criteria

✅ All tasks analyzed  
✅ High-complexity tasks (≥7) expanded  
✅ Subtasks have acceptance criteria  
✅ Completion signal created  
✅ Ready for Phase 2

## Output Files

```
.taskmaster/
├── tasks.json (with subtasks)
├── phase1-complexity-report.txt
├── phase1-summary.md
├── .checkpoints/phase1-*.json
└── .signals/phase1-complete.json
```

## See Also

- Pipeline Orchestrator skill (triggers this skill)
- Spec Generator skill (Phase 2, triggered by completion signal)
- DEVELOPMENT_WORKFLOW.md (complete workflow)