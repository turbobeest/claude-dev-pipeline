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

**CRITICAL:** This skill generates MASTER TASKS ONLY (no subtasks). DO NOT call `task-master parse-prd` or generate subtasks. Subtasks will be added later by task-master expand.

**Goal:** Create granular master tasks (as many as needed for the project) to keep LLM context small during development.

When this skill activates, follow these steps in order:

### Step 1: Read PRD with large-file-reader
```bash
# ALWAYS use large-file-reader - DO NOT use Read tool
echo "📖 Reading PRD with large-file-reader..."
./lib/large-file-reader.sh docs/PRD.md
```

**DO NOT** store output in variable - just run the command so PRD content enters your context.

### Step 2: Analyze PRD Structure (AI Analysis)

Using the PRD content now in your context, identify:

1. **Feature Requirements** (typically Section 3):
   - List each major feature/capability
   - Extract acceptance criteria per feature
   - Note architecture components affected

2. **Non-Functional Requirements**:
   - Performance requirements
   - Security requirements
   - Scalability targets

3. **Integration Requirements** (typically Section 4):
   - Component integration points
   - E2E testing requirements
   - Production validation criteria

4. **Dependencies**:
   - What must be built before what
   - Shared infrastructure needs
   - External service integrations

### Step 3: Generate Master Tasks (DIRECT AI GENERATION)

**DO NOT call task-master parse-prd!** Instead, YOU will create the master tasks directly.

#### 3a. Break Down PRD into Granular Master Tasks

**Generate as many tasks as needed** - right-size for the project complexity (simple projects may have 10-15 tasks, complex projects may have 30-50+ tasks)

**Key principle:** More granular tasks = smaller LLM context per task during development

For each PRD section/feature, create multiple focused master tasks:
- **Foundation tasks**: Setup, CI/CD, infrastructure, database
- **Feature tasks**: ONE task per specific feature component (not one task per entire feature)
- **Integration tasks**: Component integration, E2E testing, production validation

**Example breakdown:**
- Instead of: "User Authentication System" (1 big task)
- Create: "User Registration API", "Login/Logout with JWT", "Password Reset Flow", "Session Management" (4 focused tasks)

#### 3b. Create JSON Structure (MASTER TASKS ONLY)

Construct tasks.json with **NO subtasks field** - just master tasks:

```json
{
  "master": {
    "tasks": [
      {
        "id": 1,
        "name": "Specific, focused task name (Action Verb + Object)"
      },
      {
        "id": 2,
        "name": "Another focused task"
      }
    ]
  }
}
```

**CRITICAL:**
- **DO NOT** include "subtasks" field
- **DO NOT** generate subtasks
- Master task IDs: 1, 2, 3, ... (numeric, sequential)
- Each task name should be granular and focused
- Last 3 tasks MUST be: Component Integration Testing, E2E Workflow Testing, Production Readiness Validation

#### 3c. Write tasks.json File

Use the Write tool to create `.taskmaster/tasks/tasks.json`:

```json
{
  "master": {
    "tasks": [
      {"id": 1, "name": "Initialize Project Repository with CI/CD Pipeline"},
      {"id": 2, "name": "Configure PostgreSQL Database and Migrations"},
      {"id": 3, "name": "Set Up Testing Framework and Coverage Tools"},
      ... (as many tasks as needed for the project)
      {"id": N-2, "name": "Component Integration Testing"},
      {"id": N-1, "name": "End-to-End Workflow Testing"},
      {"id": N, "name": "Production Readiness Validation"}
    ]
  }
}
```

### Step 4: Validate Output

After writing tasks.json, verify:
- ✅ File exists: `.taskmaster/tasks/tasks.json`
- ✅ Valid JSON (use `jq . .taskmaster/tasks/tasks.json`)
- ✅ Task count appropriate for project complexity (not too few, not too many)
- ✅ **NO subtasks field** on any task
- ✅ Each task name is specific and focused
- ✅ Last 3 tasks are Integration, E2E, Production Validation
- ✅ All PRD features mapped to tasks
- ✅ Tasks are granular enough for small LLM context windows

### Step 5: Generate Summary

Provide user with:
```
✅ Master tasks generated: X tasks
📊 Breakdown:
   - Foundation & Setup: X tasks
   - Feature Implementation: X tasks
   - Integration & Validation: 3 tasks

📝 Next Steps:
   1. Review: task-master list
   2. Complexity analysis: task-master analyze-complexity --research
   3. Expand complex tasks: task-master expand --id=<X> --research
```

## Common Mistakes to AVOID

### ❌ Mistake #1: Calling task-master parse-prd

**WRONG:**
```bash
task-master parse-prd docs/PRD.md
```

**WHY WRONG:** task-master parse-prd fails on large PRDs (>25K tokens), times out, and produces no output.

**CORRECT:** Generate tasks.json directly using AI analysis as shown in Step 3 above.

### ❌ Mistake #2: Using Read tool for PRD

**WRONG:**
```
Read tool: docs/PRD.md
```

**WHY WRONG:** Read tool has 25,000 token hard limit. Large PRDs will fail with "token limit exceeded."

**CORRECT:**
```bash
./lib/large-file-reader.sh docs/PRD.md
```

### ❌ Mistake #3: Storing large-file-reader output in variable

**WRONG:**
```bash
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)
echo $prd_content  # Then try to use
```

**WHY WRONG:** Shell variables can't hold 30K+ tokens. Content gets truncated.

**CORRECT:** Just run the command. The output enters your context automatically:
```bash
./lib/large-file-reader.sh docs/PRD.md
# PRD content is now in your context - proceed to analyze
```

### ❌ Mistake #4: Including subtasks field

**WRONG:**
```json
{
  "id": 1,
  "name": "Set Up Database",
  "subtasks": [...]  // ❌ NO SUBTASKS!
}
```

**CORRECT:**
```json
{
  "id": 1,
  "name": "Configure PostgreSQL Database and Migrations"
}
```

**WHY:** Subtasks will be added later by `task-master expand` for complex tasks only.

### ❌ Mistake #5: Too few or too coarse tasks

**WRONG:** 5-8 big tasks like "Implement User Authentication System"

**CORRECT:** Break into granular tasks (as many as needed):
- "Implement User Registration API Endpoint"
- "Implement Login/Logout with JWT Tokens"
- "Implement Password Reset Flow"
- "Implement Session Management"

**WHY:** Smaller, focused tasks = smaller LLM context during development. Don't artificially limit task count - generate what's needed for the project.

### ❌ Mistake #6: Missing integration tasks

**WRONG:** Tasks end with last feature, no integration/E2E/validation tasks.

**CORRECT:** Last 3 master tasks MUST be:
1. "Component Integration Testing"
2. "End-to-End Workflow Testing"
3. "Production Readiness Validation"

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

**Task Count (Master Tasks ONLY - No Subtasks):**
- Generate as many tasks as needed to properly decompose the PRD
- Simple projects: ~10-15 tasks
- Medium projects: ~20-30 tasks
- Complex projects: ~30-50+ tasks

**CRITICAL:** Granularity matters - more focused tasks = smaller LLM context during development. Don't artificially limit or expand task count - right-size for the project.

**Task Granularity Strategy:**
- Break down features into specific,focused tasks
- ONE task per API endpoint/component/feature
- NOT one task per entire feature
- Use numeric IDs only (no strings like "TASK-001")
- **NO subtasks field** - subtasks added later by task-master expand

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

**CRITICAL: PRD-to-Tasks generates MASTER TASKS ONLY (no subtasks):**

```json
{
  "master": {
    "tasks": [
      {
        "id": 1,                          // ✅ Numeric ID
        "name": "[Action Verb] + [Object]" // ✅ 'name' for master task
      },
      {
        "id": 2,
        "name": "Another focused task"
      }
    ]
  }
}
```

**Field Requirements:**
- Master task: `id` (number), `name` (string)
- **NO subtasks field** - subtasks added later by task-master expand
- NO custom fields like `status`, `priority`, `dependencies`
- NO string IDs like "TASK-001"

**Subtasks added LATER by task-master:**
```bash
# After PRD-to-Tasks creates master tasks:
task-master analyze-complexity --research
task-master expand --id=5 --research  # For complex tasks
```

**Final structure (AFTER expand):**
```json
{
  "id": 5,
  "name": "Implement User Authentication API",
  "subtasks": [  // ← Added by task-master expand
    {
      "id": 1,
      "title": "Create user registration endpoint",
      "testStrategy": "...",
      "acceptanceCriteria": ["..."]
    }
  ]
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

### ❌ Task Count Too Coarse
**Problem:** Too few tasks (e.g. 5-8 big monolithic tasks)
**Solution:** Break down into granular, focused tasks. Generate as many as needed - don't artificially limit.

**Example:** A complex multi-service application might need 40-50 tasks. A simple CRUD app might need 12-15. Right-size for the project.

## Complete Example: PRD → tasks.json (MASTER TASKS ONLY)

### Example PRD (Simplified)

```markdown
# E-Commerce Platform PRD

## 3. Features

### 3.1 User Authentication
- User registration with email validation
- Login/logout with JWT tokens
- Password reset via email
- Session management and refresh tokens

### 3.2 Product Catalog
- Product CRUD operations
- Product search functionality
- Category filtering
- Price range filtering

### 3.3 Shopping Cart
- Add/remove cart items
- Update item quantities
- Guest cart support
- Persist cart across sessions

### 3.4 Checkout
- Stripe payment integration
- Order creation
- Order confirmation emails
- Order history tracking

## 4. Integration Requirements
- Component integration testing
- E2E user journey testing
- Production readiness validation
```

### Example tasks.json Output (MASTER TASKS ONLY - NO SUBTASKS)

```json
{
  "master": {
    "tasks": [
      {"id": 1, "name": "Initialize Project Repository with CI/CD Pipeline"},
      {"id": 2, "name": "Configure PostgreSQL Database and Migrations Framework"},
      {"id": 3, "name": "Set Up Testing Framework (Jest/Pytest) and Coverage Tools"},
      {"id": 4, "name": "Configure Environment Variables and Secrets Management"},
      {"id": 5, "name": "Implement User Registration API Endpoint"},
      {"id": 6, "name": "Implement Login/Logout with JWT Token Generation"},
      {"id": 7, "name": "Implement Password Reset Flow with Email Notifications"},
      {"id": 8, "name": "Implement Session Management and Token Refresh"},
      {"id": 9, "name": "Create Product Model and Database Schema"},
      {"id": 10, "name": "Implement Product CRUD API Endpoints"},
      {"id": 11, "name": "Implement Product Search Functionality"},
      {"id": 12, "name": "Implement Category and Price Range Filtering"},
      {"id": 13, "name": "Create Cart and CartItem Models"},
      {"id": 14, "name": "Implement Add/Remove Cart Items API"},
      {"id": 15, "name": "Implement Cart Quantity Update Logic"},
      {"id": 16, "name": "Implement Guest Cart Session Storage"},
      {"id": 17, "name": "Implement Cart Persistence Across User Sessions"},
      {"id": 18, "name": "Integrate Stripe Payment SDK"},
      {"id": 19, "name": "Implement Payment Intent Creation and Processing"},
      {"id": 20, "name": "Implement Payment Webhook Handling"},
      {"id": 21, "name": "Create Order Model and Database Schema"},
      {"id": 22, "name": "Implement Order Creation After Successful Payment"},
      {"id": 23, "name": "Implement Order Confirmation Email Service"},
      {"id": 24, "name": "Implement Order History Retrieval API"},
      {"id": 25, "name": "Component Integration Testing"},
      {"id": 26, "name": "End-to-End Workflow Testing"},
      {"id": 27, "name": "Production Readiness Validation"}
    ]
  }
}
```

### Key Points from Example

✅ **27 Master Tasks**: Granular, focused tasks (not 6 big tasks)
✅ **NO Subtasks Field**: Subtasks added later by task-master expand
✅ **Numeric IDs**: Sequential 1, 2, 3...
✅ **One Task Per Component**: Registration, Login, Password Reset are separate tasks
✅ **Last 3 Tasks**: Integration Testing, E2E Testing, Production Validation
✅ **Smaller Context**: Each task is focused, keeping LLM context small during development
✅ **PRD Coverage**: All Section 3 features + Section 4 requirements mapped

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