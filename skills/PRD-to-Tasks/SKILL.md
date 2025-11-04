---
activation_code: PRD_TO_TASKS_V1
phase: 1
prerequisites: []
outputs: 
  - .taskmaster/tasks/tasks.json
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

## Execution Steps (MANDATORY)

When this skill activates, follow these steps in order:

### Step 1: Read PRD with large-file-reader
```bash
# ALWAYS use large-file-reader - DO NOT use Read tool
echo "📖 Reading PRD with large-file-reader..."
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)
```

### Step 2: Analyze PRD Structure
Extract from $prd_content:
- Feature requirements (Section 3)
- Non-functional requirements
- Integration requirements (Section 4)
- Test strategies
- Architecture components

### Step 3: Generate TaskMaster tasks.json
Create properly structured master tasks with subtasks

### Step 4: Validate Output
- All PRD features mapped
- Integration tasks present
- No circular dependencies
- Schema compliance

## What This Skill Does

Automatically generates high-quality TaskMaster tasks.json from Product Requirements Documents in isolated worktree, ensuring:
- Complete PRD coverage (all features mapped to tasks)
- Proper task dependencies (no circular dependencies)
- **Critical:** Always includes integration tasks (#N-2, #N-1, #N)
- OpenSpec mapping strategy per task
- Production-grade acceptance criteria
- **NEW**: Worktree isolation for each task generation phase
- **NEW**: Cross-worktree contamination prevention
- **NEW**: Support for large PRD files (>25,000 tokens) via large-file-reader utility

## Reading Large PRD Files

**CRITICAL:** This skill ALWAYS uses the large-file-reader utility for PRDs to avoid Claude Code's Read tool 25,000 token limit.

### Automatic Large File Reading

When this skill activates, it MUST use this approach:

```bash
# Step 1: Check file size and get metadata
echo "📊 Analyzing PRD file size..."
./lib/large-file-reader.sh docs/PRD.md --metadata

# Step 2: Read PRD using large-file-reader (bypasses 25K token limit)
echo "📖 Reading comprehensive PRD..."
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)

# Step 3: Analyze and generate tasks
echo "🔨 Generating TaskMaster tasks from PRD..."
# Use $prd_content for analysis
```

**Why Always Use large-file-reader:**
- ✅ No 25,000 token limit (Read tool constraint)
- ✅ Handles files of any size (35,000+ tokens)
- ✅ Atomic document analysis (entire PRD in context)
- ✅ No chunking or pagination needed
- ✅ Prevents "token limit exceeded" errors

**DO NOT use Read tool for PRDs** - it will fail for comprehensive documents.

### File Size Guidelines

| PRD Size | Lines | Tokens | Approach |
|----------|-------|--------|----------|
| Small | <500 | <10K | large-file-reader (consistent) |
| Medium | 500-1000 | 10K-20K | large-file-reader (consistent) |
| Large | 1000-2000 | 20K-40K | large-file-reader (required) |
| Very Large | 2000+ | 40K+ | large-file-reader (required) |

**Consistency Rule:** Always use large-file-reader for PRDs regardless of size to ensure reliable operation.

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

**Task Count Target (Master Tasks Only):**
- Small projects: 5-8 master tasks (with 3-5 subtasks each)
- Medium projects: 8-12 master tasks (with 3-5 subtasks each)
- Large projects: 10-15 master tasks (with 3-5 subtasks each)

**TaskMaster Decomposition Strategy:**
- Generate 8-12 master tasks maximum
- Each master task must have 3-8 subtasks
- Total subtasks: 30-60 (similar to previous flat structure)
- Use numeric IDs only (no strings like "TASK-001")

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

**Final Master Task: Integration & Validation**
```json
{
  "id": 10,
  "name": "Integration & Production Validation",
  "subtasks": [
    {
      "id": 1,
      "title": "Component Integration Testing",
      "testStrategy": "Execute comprehensive integration test suite covering all component interfaces",
      "acceptanceCriteria": ["All integration points tested (100%)", "All integration tests passing"]
    },
    {
      "id": 2,
      "title": "End-to-End Workflow Testing",
      "testStrategy": "Execute E2E test suite for all critical user journeys",
      "acceptanceCriteria": ["All critical user journeys tested", "All E2E tests passing"]
    },
    {
      "id": 3,
      "title": "Production Readiness Validation",
      "testStrategy": "Execute comprehensive validation checklist",
      "acceptanceCriteria": ["All tests passing (100%)", "Coverage thresholds met", "Production readiness complete"]
    }
  ]
}
```

**Note:** Integration tasks are now consolidated into the final master task above with proper TaskMaster subtask structure.

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

## TaskMaster Schema Requirements

**CRITICAL: Use ONLY this structure:**

```json
{
  "master": {
    "tasks": [
      {
        "id": 1,                          // ✅ Numeric ID
        "name": "[Action Verb] + [Object]", // ✅ 'name' for master task
        "subtasks": [                     // ✅ Required subtasks array
          {
            "id": 1,                      // ✅ Numeric subtask ID
            "title": "Specific action",    // ✅ 'title' for subtask
            "testStrategy": "How to test this subtask",
            "acceptanceCriteria": ["Criteria 1", "Criteria 2"],
            "details": "Implementation details"
          }
        ]
      }
    ]
  }
}
```

**Field Mapping (TaskMaster Standard):**
- Master task: `id` (number), `name` (string), `subtasks` (array)
- Subtask: `id` (number), `title` (string), `testStrategy` (string)
- NO custom fields like `status`, `priority`, `dependencies`
- NO string IDs like "TASK-001"

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

**CRITICAL: Generate TaskMaster-compliant format only:**

```json
{
  "master": {
    "tasks": [
      {
        "id": 1,
        "name": "Docker Environment Setup",
        "subtasks": [
          {
            "id": 1,
            "title": "Create Docker Compose file",
            "testStrategy": "Validate with docker-compose config",
            "acceptanceCriteria": ["Docker services start successfully"]
          },
          {
            "id": 2,
            "title": "Configure environment variables",
            "testStrategy": "Test variable loading",
            "acceptanceCriteria": ["All variables loaded correctly"]
          }
        ]
      }
    ]
  }
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