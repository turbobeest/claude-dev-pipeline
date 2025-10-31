---
activation_code: PRD_TO_TASKS_V1
phase: 1
prerequisites: []
outputs: 
  - tasks.json
  - .signals/phase1-start.json
description: |
  Generates production-grade TaskMaster tasks.json from Product Requirements Documents (PRD).
  Activates via codeword [ACTIVATE:PRD_TO_TASKS_V1] injected by hooks when PRD is detected.
  Always generates integration tasks (Tasks #N-2, #N-1, #N) for component integration testing,
  E2E workflows, and production readiness validation.
  
  Activation trigger: [ACTIVATE:PRD_TO_TASKS_V1]
---

# PRD-to-Tasks Skill

## Activation Method

This skill activates when the hook system injects the codeword:
```
[ACTIVATE:PRD_TO_TASKS_V1]
```

This occurs when:
- User mentions "PRD", "generate tasks", or "parse requirements"
- PRD.md or requirements.md exists in context
- Phase 0 is complete and user wants to start development

## Worktree Isolation Requirements

**CRITICAL**: This skill MUST operate in a dedicated worktree `phase-1-task-1`:

```bash
# Before skill activation:
./lib/worktree-manager.sh create 1 1
cd ./worktrees/phase-1-task-1

# Validate isolation:
./hooks/worktree-enforcer.sh enforce

# Skill execution with worktree validation
```

### Worktree Validation Steps
1. **Pre-execution**: Verify worktree isolation before any operations
2. **During execution**: All file operations confined to worktree
3. **Post-execution**: Merge changes to main branch and cleanup

## What This Skill Does

Automatically generates high-quality TaskMaster tasks.json from Product Requirements Documents in isolated worktree, ensuring:
- Complete PRD coverage (all features mapped to tasks)
- Proper task dependencies (no circular dependencies)
- **Critical:** Always includes integration tasks (#N-2, #N-1, #N)
- OpenSpec mapping strategy per task
- Production-grade acceptance criteria
- **NEW**: Worktree isolation for each task generation phase
- **NEW**: Cross-worktree contamination prevention

## What This Skill Does

### 1. PRD Structure Analysis
Automatically identifies and extracts:
- Feature requirements (Section 3)
- Non-functional requirements (NFRs)
- Integration requirements (Section 4)
- Test strategy per requirement
- Architecture components affected
- Dependencies between requirements

### 2. Task Generation Rules

**Task Count Target:**
- Small projects: 10-15 tasks
- Medium projects: 15-25 tasks
- Large projects: 25-35 tasks

**Task Categories (Auto-Generated):**
```
Foundation & Setup: 2-3 tasks
├─ Repository/environment setup
├─ CI/CD pipeline
└─ Testing framework

Data Layer: 2-4 tasks
├─ Schema design
├─ Models
└─ Migrations

Business Logic: 5-8 tasks per feature
├─ One task per PRD Feature section
└─ Core services, APIs, workflows

Integration Layer: 1-3 tasks
├─ External APIs
├─ Message queues
└─ Event handling

Frontend: 3-5 tasks (if applicable)
├─ UI components
├─ State management
└─ User workflows

Testing Infrastructure: 1-2 tasks
├─ Test framework setup
└─ Coverage configuration

Documentation: 1-2 tasks
├─ API docs
└─ Architecture docs

Operational Readiness: 2-3 tasks
├─ Monitoring
├─ Logging
└─ Deployment automation

Integration & Validation: 2-3 tasks (CRITICAL)
├─ Task #N-2: Component Integration Testing
├─ Task #N-1: E2E Workflow Testing
└─ Task #N: Production Readiness Validation
```

### 3. Dependency Analysis

**Automatic Dependency Detection:**
```
IF Task B requires output from Task A:
  → dependencies: ["A"]

IF Task mentions "database" AND database task exists:
  → dependencies: [database-task-id]

IF Task is integration/validation:
  → dependencies: [ALL feature task IDs]

IF Task has NO dependencies:
  → dependencies: []
```

**Sequential Dependencies:**
- Database schema → Data models → Services → APIs → Frontend
- Testing framework → Test suites
- Feature work → Integration testing → System validation

**Parallel Opportunities:**
- Independent services
- UI components (with mocked APIs)
- Documentation (ongoing)

### 4. Integration Task Generation (CRITICAL)

**Always Generate These Final Tasks:**

**Task #N-2: Component Integration Testing**
```json
{
  "id": "[N-2]",
  "title": "Component Integration Testing",
  "description": "Maps to PRD Section 4.1. Test all integration points between components...",
  "dependencies": ["1", "2", "3", "...", "[N-3]"],
  "testStrategy": "Execute comprehensive integration test suite...",
  "acceptanceCriteria": [
    "All integration points tested (100%)",
    "All integration tests passing",
    "Error scenarios validated"
  ]
}
```

**Task #N-1: End-to-End Workflow Testing**
```json
{
  "id": "[N-1]",
  "title": "End-to-End Workflow Testing",
  "description": "Maps to PRD Section 4.2. Test complete user journeys...",
  "dependencies": ["[N-2]"],
  "testStrategy": "Execute E2E test suite for all critical user journeys...",
  "acceptanceCriteria": [
    "All critical user journeys tested",
    "All E2E tests passing",
    "Tests passing in all browsers"
  ]
}
```

**Task #N: Production Readiness Validation**
```json
{
  "id": "[N]",
  "title": "Production Readiness Validation",
  "description": "Maps to PRD Section 4.3. Complete production readiness checklist...",
  "dependencies": ["[N-1]"],
  "testStrategy": "Execute comprehensive validation checklist...",
  "acceptanceCriteria": [
    "All tests passing (100%)",
    "Coverage thresholds met (≥80%/70%)",
    "All stakeholder sign-offs obtained",
    "Production readiness checklist 100% complete"
  ]
}
```

### 5. Quality Checks

**Before Outputting tasks.json:**
- [ ] All PRD features mapped to tasks
- [ ] Section 4 (Integration) generates Tasks #N-2, #N-1, #N
- [ ] Integration tasks depend on ALL feature tasks
- [ ] No circular dependencies
- [ ] All tasks have testStrategy
- [ ] All tasks have acceptanceCriteria
- [ ] All tasks have architectureComponent
- [ ] OpenSpec mapping defined per task
- [ ] Task count within target range (15-25 typical)

## Task Structure Template

```json
{
  "id": "string",
  "title": "[Action Verb] + [Object]",
  "description": "Maps to PRD Feature [ID], Requirements FR-[ID].1-[ID].N. [2-3 sentences]. Architecture Component: [name]",
  "status": "pending",
  "priority": "critical|high|medium|low",
  "dependencies": ["array of task IDs"],
  "details": "## Implementation Scope\n[Detailed description]\n\n## Architecture Integration\n[Components, integration points]\n\n## OpenSpec Preparation\n[Proposal strategy]\n\n## Security Considerations\n[Security implications]\n\n## Performance Considerations\n[Performance implications]",
  "testStrategy": "## Test Requirements\n\n### Unit Tests\n[Specifics]\n\n### Integration Tests\n[Specifics]\n\n### E2E Tests\n[Specifics if applicable]\n\n### Validation Commands\n[Commands to run]",
  "acceptanceCriteria": [
    "Functional code implements PRD FR-[ID].X",
    "Unit tests pass with ≥80% line coverage, ≥70% branch coverage",
    "Integration tests pass",
    "Code review completed",
    "Lint/static analysis passing",
    "Performance benchmarks met"
  ],
  "subtasks": [],
  "tags": ["feature:[name]", "component:[name]", "type:[backend|frontend|infrastructure]"],
  "estimatedComplexity": null,
  "architectureComponent": "[Component from architecture.md]",
  "openspecMapping": {
    "proposalStrategy": "tightly-coupled|loosely-coupled|single-task",
    "specFiles": ["[spec-file].md"],
    "relatedTasks": ["array of related task IDs"]
  }
}
```

## OpenSpec Mapping Strategy

**Analyze PRD feature requirements:**

```
IF feature has ≤2 requirements:
  → openspecMapping.proposalStrategy = "single-task"
  → One proposal per task

ELSE IF requirements share code/models:
  → openspecMapping.proposalStrategy = "tightly-coupled"
  → One proposal covers multiple requirements
  → List related task IDs

ELSE IF requirements are independent:
  → openspecMapping.proposalStrategy = "loosely-coupled"
  → Separate proposal per requirement
  → Can implement in parallel
```

## Output Format

**Generate complete tasks.json with:**

```json
{
  "meta": {
    "projectName": "[from PRD]",
    "version": "[from PRD]",
    "prdSource": ".taskmaster/docs/prd.txt",
    "createdAt": "[ISO-8601 timestamp]",
    "generatedBy": "Claude Projects + PRD-to-Tasks Skill",
    "architectureRef": "docs/architecture.md"
  },
  "tasks": [
    { /* task objects */ }
  ]
}
```

**After Generation, Provide:**

### Task Summary
```
Total Tasks: [X]
├─ Foundation: [count] (tasks 1-Y)
├─ Features: [count] (tasks Y+1-Z)
├─ Integration: [count] (tasks Z+1-N)
└─ Total: [X] tasks

Task Distribution:
├─ Data Layer: [count]
├─ Business Logic: [count]
├─ API Layer: [count]
├─ Frontend: [count]
├─ Testing Infrastructure: [count]
├─ Documentation: [count]
└─ Integration & Validation: [count]
```

### Dependency Analysis
```
Critical Path:
[Task 1] → [Task 2] → [Task 5] → [Task N-2] → [Task N-1] → [Task N]

Parallel Opportunities:
Branch A: [Tasks 3, 4, 6] (can run simultaneously)
Branch B: [Tasks 7, 8, 9] (can run simultaneously)

Integration Dependencies:
Task #N-2 depends on: [list ALL feature task IDs]
```

### OpenSpec Proposal Estimate
```
Based on coupling analysis:
├─ Tightly coupled features: [count] → [count] proposals
├─ Loosely coupled features: [count] → [count] proposals
└─ Estimated total proposals: [count]
```

### Validation Report
```
✅ All PRD features mapped
✅ Integration tasks present (Tasks #N-2, #N-1, #N)
✅ Dependencies validated (no circular)
✅ All tasks have test strategies
✅ Task count within target: [X] tasks
⚠️ Issues found: [list any gaps/inconsistencies]
```

## Common Issues to Prevent

### ❌ Missing Integration Tasks
**Problem:** Tasks for component integration/E2E/validation not generated  
**Solution:** Always generate Tasks #N-2, #N-1, #N from PRD Section 4

### ❌ Incomplete Test Strategy
**Problem:** testStrategy field is generic or empty  
**Solution:** Extract specific test scenarios from PRD acceptance criteria

### ❌ Wrong Dependencies
**Problem:** Integration task doesn't depend on all features  
**Solution:** Task #N-2 dependencies = ["1", "2", ..., "N-3"]

### ❌ Poor OpenSpec Mapping
**Problem:** All tasks marked "tightly-coupled" or all "loosely-coupled"  
**Solution:** Analyze each feature's requirements individually

### ❌ Task Count Too High/Low
**Problem:** 50+ tasks (too granular) or <10 tasks (too coarse)  
**Solution:** Target 15-25 tasks, let TaskMaster expand high-complexity

## Examples

See `/examples/` directory for:
- `good-prd-parsing.md` - Ideal PRD → tasks.json transformation
- `integration-tasks-example.md` - How Tasks #N-2, #N-1, #N should look
- `dependency-analysis.md` - Proper dependency chain examples

## Integration with Workflow

**In Claude Projects session:**
1. User pastes PRD content
2. This skill activates automatically
3. Skill enhances task generation with quality checks
4. User receives validated tasks.json ready for Phase 1

**Human validation still required:**
- Review task count and structure
- Verify PRD coverage
- Confirm integration tasks present
- Approve before proceeding to Claude Code