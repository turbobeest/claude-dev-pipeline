---
activation_code: TDD_IMPLEMENTER_V1
phase: 3
prerequisites:
  - OpenSpec proposals
  - Test strategy
outputs:
  - Implementation files
  - Test files
  - .signals/phase3-complete.json
description: |
  Guides TDD implementation following RED-GREEN-REFACTOR cycle.
  Activates via codeword [ACTIVATE:TDD_IMPLEMENTER_V1] injected by hooks
  when entering Phase 3 implementation.
  
  Activation trigger: [ACTIVATE:TDD_IMPLEMENTER_V1]
---

# TDD Implementer Skill

## Activation Method

This skill activates when the hook system injects the codeword:
```
[ACTIVATE:TDD_IMPLEMENTER_V1]
```

This occurs when:
- Phase 2 is complete (specs and test strategy ready)
- User begins implementation
- Tests need to be written first

## Anti-Mock Directive

**CRITICAL**: NO MOCK IMPLEMENTATIONS IN OPERATIONAL CODE
- Do NOT create simulated services or fake deployments
- Do NOT return hardcoded success responses
- If cannot implement, raise NotImplementedError
- Mock code allowed ONLY in test files

## Worktree Isolation Requirements

**CRITICAL**: This skill MUST operate in dedicated worktrees per subtask `phase-3-task-N`:

```bash
# For each subtask implementation:
./lib/worktree-manager.sh create 3 <subtask_number>
cd ./worktrees/phase-3-task-<subtask_number>

# Validate isolation:
./hooks/worktree-enforcer.sh enforce

# TDD implementation with strict isolation
```

### Implementation Isolation Strategy
1. **One worktree per subtask**: Each subtask gets completely isolated environment
2. **TDD cycle isolation**: RED-GREEN-REFACTOR happens within worktree boundaries
3. **NO MOCKS**: Real implementations only, fail if cannot implement
3. **Test contamination prevention**: Tests don't interfere across subtasks
4. **Sequential merge**: Subtasks merged in dependency order
5. **Integration validation**: Each merge tested in isolation before next subtask

# TDD Implementer Skill

## What This Skill Does

Automates Phase 3: Test-Driven Development implementation in isolated worktrees

- **RED-GREEN-REFACTOR cycle** (tests first, always) per worktree
- **Mandatory coverage gates** (80% line, 70% branch) validated per subtask
- **Worktree-based isolation** (one subtask per worktree)
- **Status updates** (TaskMaster & OpenSpec) from isolated environments
- **Completion signal** → triggers Phase 4
- **NEW**: Complete task isolation prevents implementation conflicts
- **NEW**: Safe parallel development through worktree boundaries

## Execution Flow

```
Stage 1: Load Phase 2 Results
Stage 2: Determine Implementation Strategy
         - Sequential (tightly coupled)
         - Parallel (loosely coupled)
Stage 3: Implement Tasks (TDD Cycle)
         RED: Write failing tests
         GREEN: Implement code
         REFACTOR: Clean up
         VALIDATE: Check coverage
Stage 4: Update Status
Stage 5: Generate Summary
Stage 6: Create Signal → Phase 4
```

## TDD Cycle (Per Task)

### RED Phase: Write Failing Tests FIRST

```bash
# 1. Create test files
tests/unit/[component].test.js
tests/integration/[component]-integration.test.js

# 2. Write comprehensive tests
- Unit tests (60%)
- Integration tests (30%)
- E2E tests (10%)
- Edge cases
- Error cases

# 3. Run tests (MUST FAIL)
npm test
# ❌ All new tests fail (proves they're valid)

# 4. Commit failing tests
git commit -m "Add failing tests for [feature] (RED)"
```

### GREEN Phase: Implement Minimum Code

```bash
# 1. Apply OpenSpec
/openspec:apply [proposal-name]

# 2. Write MINIMUM code to pass tests
# Run tests continuously
npm test -- --watch

# 3. Verify all tests pass
npm test
# ✅ All tests pass

# 4. Commit implementation
git commit -m "Implement [feature] (GREEN)"
```

### REFACTOR Phase: Improve Quality

```bash
# 1. Clean up code
- Remove duplication
- Improve naming
- Extract functions
- Add comments

# 2. Run tests after EVERY change
npm test

# 3. Tests must stay GREEN
# ✅ All tests still pass

# 4. Commit refactoring
git commit -m "Refactor [feature] (REFACTOR)"
```

### VALIDATE Phase: Check Coverage

```bash
# 1. Run coverage report
npm run coverage

# 2. Check thresholds (BLOCKING)
Line coverage:     >= 80%  ✓
Branch coverage:   >= 70%  ✓
Critical paths:    = 100%  ✓

# 3. If insufficient → Back to RED
# Write more tests, repeat cycle

# 4. Run all validation
npm test                 # All tests
npm test:integration     # Integration
npm test:regression      # No breaks
npm run lint            # No errors

# 5. Mark complete ONLY if all pass
task-master set-task-status --id=[id] --status=done
openspec archive [proposal-name] --yes
```

## Implementation Strategies

### Strategy A: Sequential (Tightly Coupled)

**Use when:** Tasks share code, must implement together

```bash
# For each task in order:
# 1. Load task
task-master show [id]
openspec show [proposal-name]

# 2. Run TDD cycle
# [RED → GREEN → REFACTOR → VALIDATE]

# 3. Mark complete
task-master set-task-status --id=[id] --status=done
openspec archive [proposal-name] --yes

# 4. Move to next task
```

**Time:** 45-90 min per task

### Strategy B: Parallel (Loosely Coupled)

**Use when:** Tasks independent, can run simultaneously

```bash
# Setup: Create git worktrees
git worktree add ../project-task-[id] -b feature/task-[id]

# Launch Claude Code per worktree
# Each runs TDD cycle independently

# Merge when all complete
git merge feature/task-[id]
```

**Time:** 3-4x faster (30-45 min total vs sequential)

## Time Estimates

| Tasks | Sequential | Parallel |
|-------|-----------|----------|
| 5     | 4-7 hours | 1-2 hours |
| 10    | 7-15 hours| 2-4 hours |
| 20    | 15-30 hours| 4-8 hours |

## Mandatory Gates

**Before marking task complete:**

- ✅ All tests pass (100%)
- ✅ Line coverage ≥ 80%
- ✅ Branch coverage ≥ 70%
- ✅ Critical paths = 100%
- ✅ Integration tests pass
- ✅ Regression tests pass
- ✅ No lint errors
- ✅ No type errors

**If ANY gate fails:** Back to RED phase

## Completion Signal

```json
{
  "phase": 3,
  "status": "success",
  "summary": {
    "tasks_implemented": N,
    "tests_written": M,
    "coverage_achieved": {
      "line": 85,
      "branch": 78
    }
  },
  "next_phase": 4,
  "trigger_next": true
}
```

## Output Files

```
src/
└── [implementation code]

tests/
├── unit/
├── integration/
└── e2e/

.taskmaster/
├── phase3-summary.md
└── .signals/phase3-complete.json
```

## See Also

- Pipeline Orchestrator (triggers this)
- Spec Generator (Phase 2, provides input)
- Test Strategy Generator (provides test guidance)
- Integration Validator (Phase 4, triggered by signal)