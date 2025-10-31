# TaskMaster-OpenSpec Integration Bridge Design

## Problem Statement (RESOLVED)
TaskMaster uses hierarchical master→subtask structure. Solution: spec-gen always creates 1 proposal per subtask (simple 1:1 mapping). Coupling analysis is optional and only provides implementation order recommendations.

## Simplified Flow (IMPLEMENTED)

### Current Flow (Working)
```
PRD-to-Tasks → TaskMaster format → spec-gen → OpenSpec
                                      ↓
                         Always 1 proposal per subtask
```

### Optional Enhancement
```
PRD-to-Tasks → TaskMaster format → [Coupling Analysis] → spec-gen → OpenSpec
                                      ↓ (optional hints)        ↓
                                 Implementation order    1 proposal per subtask
```

## Bridge Solution (SIMPLIFIED)

### 1. spec-gen Reads TaskMaster Format ✅
spec-gen understands `.taskmaster/tasks/tasks.json`:
```json
{
  "master": {
    "tasks": [
      {
        "id": 1,
        "name": "User Authentication",
        "subtasks": [
          {"id": 1, "title": "Create user model"},
          {"id": 2, "title": "Registration endpoint"},
          {"id": 3, "title": "Login endpoint"}
        ]
      }
    ]
  }
}
```

### 2. Proposal Creation (ALWAYS 1:1) ✅

**Simple Rule:**
- Extract all subtasks from master tasks
- Create 1 OpenSpec proposal per subtask
- Name: `[master-task-name]-subtask-[id]`

**Example:**
```
Master Task 1: User Authentication (3 subtasks)
→ Proposal 1: user-authentication-subtask-1
→ Proposal 2: user-authentication-subtask-2
→ Proposal 3: user-authentication-subtask-3
```

### 3. Coupling Analysis (OPTIONAL) ⚠️

**Optional Enhancement Only:**
Coupling analysis can provide implementation hints:
```
COUPLING ANALYSIS: Task #1 - User Authentication
COUPLING TYPE: TIGHTLY COUPLED
RECOMMENDATION: Implement proposals sequentially (prevent conflicts)
```

**Does NOT affect:**
- Proposal count (always 1 per subtask)
- Proposal creation logic
- OpenSpec structure

### 4. Batch Processing ✅

**Batching by master tasks:**
- Batch 1: Process master tasks 1-8 (extract all their subtasks)
- Batch 2: Process master tasks 9-12 (extract all their subtasks)
- Create proposals: 1 per subtask across all batches
- Total proposals = Total subtasks (30-60)

## Implementation Changes (COMPLETED ✅)

### spec-gen Skill Updated
1. ✅ **Reads TaskMaster hierarchical format** (.taskmaster/tasks/tasks.json)
2. ✅ **Batches by master tasks** (5-10 per batch)
3. ✅ **Creates 1 proposal per subtask** (always, no conditional logic)
4. ✅ **Updates TASKMASTER_OPENSPEC_MAP.md** with 1:1 mapping

### Coupling-Analysis Skill Updated
1. ✅ **Marked as optional** (not required for proposal creation)
2. ✅ **Provides implementation hints only** (sequential vs parallel)
3. ✅ **Does not affect proposal count** (always 1 per subtask)

### File Structure Bridge
```
.taskmaster/tasks/tasks.json          # TaskMaster format (master→subtasks)
.taskmaster/coupling-analysis.md      # Coupling results per master task
openspec/changes/*/proposal.md        # OpenSpec proposals (variable count)
TASKMASTER_OPENSPEC_MAP.md           # Bridge mapping file
```

### Mapping File Format (Simplified)
```markdown
# TaskMaster-OpenSpec Mapping

## Master Task 1: User Authentication
- Subtask 1.1: Create user model → Proposal: user-authentication-subtask-1
- Subtask 1.2: Registration endpoint → Proposal: user-authentication-subtask-2
- Subtask 1.3: Login endpoint → Proposal: user-authentication-subtask-3
- [Optional] Coupling: TIGHTLY COUPLED → Implement sequentially

## Master Task 2: API Refactoring
- Subtask 2.1: Refactor users → Proposal: api-refactoring-subtask-1
- Subtask 2.2: Refactor products → Proposal: api-refactoring-subtask-2
- Subtask 2.3: Refactor orders → Proposal: api-refactoring-subtask-3
- [Optional] Coupling: LOOSELY COUPLED → Can implement in parallel
```

**Key:** Always 1 proposal per subtask. Coupling hints are optional metadata.

## Benefits of Simplified Solution

1. ✅ **TaskMaster Compliance**: Proper master→subtask decomposition
2. ✅ **OpenSpec Compliance**: Clear 1:1 proposal mapping
3. ✅ **Maximum Simplicity**: No conditional logic, easy to understand
4. ✅ **Clear Tracking**: Each subtask = 1 proposal = 1 implementation
5. ✅ **Optional Optimization**: Can use coupling hints for implementation speed
6. ✅ **Tool Isolation**: Each tool works with its preferred format
7. ✅ **Easy Maintenance**: Simpler code, fewer edge cases

## Validation Strategy

1. **TaskMaster Test**: `taskmaster show` displays tasks correctly
2. **Coupling Test**: Analysis produces strategy per master task  
3. **OpenSpec Test**: Proposals created according to coupling strategy
4. **Integration Test**: End-to-end PRD → Tasks → Coupling → Proposals

## Summary: How Systems Coexist

### TaskMaster (Hierarchical)
```
8-12 master tasks
├─ 3-8 subtasks each
└─ Total: 30-60 subtasks
```

### spec-gen (1:1 Mapping)
```
For each subtask → Create 1 proposal
Total: 30-60 proposals (= subtask count)
```

### Coupling Analysis (Optional)
```
Analyzes subtasks → Recommends implementation order
- Tightly coupled → Sequential (safe)
- Loosely coupled → Parallel (fast)
Does NOT affect proposal count
```

### OpenSpec (Compliant)
```
Receives 30-60 proposals (1 per subtask)
Standard OpenSpec workflow applies
Dependencies always respected
```

## Final Status: ✅ COMPLETE

**Both systems now coexist perfectly:**
- TaskMaster: Hierarchical master→subtask structure ✅
- spec-gen: Always 1 proposal per subtask ✅
- Coupling Analysis: Optional implementation hints ✅
- OpenSpec: Standard proposal workflow ✅
- Integration: Clear 1:1 mapping ✅

**No conflicts, maximum simplicity, full compatibility.**