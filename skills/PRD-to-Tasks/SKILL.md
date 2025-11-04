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

**CRITICAL:** This skill generates tasks.json DIRECTLY using AI analysis. DO NOT call `task-master parse-prd` or any external task generation tools.

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

### Step 3: Generate TaskMaster tasks.json (DIRECT AI GENERATION)

**DO NOT call task-master parse-prd!** Instead, YOU will create the tasks.json directly.

#### 3a. Design Master Task Structure

Based on PRD analysis, create 8-12 master tasks:
- Foundation tasks (setup, infra)
- Feature tasks (one per major PRD feature)
- Integration tasks (MUST be last task)

#### 3b. For Each Master Task, Generate Subtasks

Each master task should have 3-8 subtasks that break down implementation:
- Specific, actionable subtask titles
- testStrategy for each subtask
- acceptanceCriteria array for each subtask

#### 3c. Create JSON Structure

Construct tasks.json following this EXACT schema:

```json
{
  "master": {
    "tasks": [
      {
        "id": 1,
        "name": "Master Task Name (Action Verb + Object)",
        "subtasks": [
          {
            "id": 1,
            "title": "Specific subtask action",
            "testStrategy": "How to verify this subtask works",
            "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
            "details": "Implementation guidance"
          }
        ]
      }
    ]
  }
}
```

#### 3d. Write tasks.json File

Use the Write tool to create `.taskmaster/tasks/tasks.json` with your generated content:

```bash
# After constructing JSON in your analysis, write it:
# Use Write tool: .taskmaster/tasks/tasks.json
# Content: your generated JSON structure
```

**IMPORTANT:**
- Master task IDs: 1, 2, 3, ... (numeric, sequential)
- Subtask IDs: 1, 2, 3, ... (numeric, sequential PER master task)
- Last master task MUST be "Integration & Production Validation" with integration/E2E/validation subtasks

### Step 4: Validate Output

After writing tasks.json, verify:
- ✅ File exists: `.taskmaster/tasks/tasks.json`
- ✅ Valid JSON (use `jq . .taskmaster/tasks/tasks.json`)
- ✅ 8-12 master tasks
- ✅ Each master has 3-8 subtasks
- ✅ All subtasks have testStrategy and acceptanceCriteria
- ✅ Last master task is Integration & Validation
- ✅ All PRD features mapped to tasks

### Step 5: Generate Summary

Provide user with:
```
✅ Tasks generated: X master tasks, Y total subtasks
📊 Breakdown:
   - Foundation: X tasks
   - Features: X tasks
   - Integration: X tasks

📝 Next: Review tasks with 'task-master list --with-subtasks'
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

### ❌ Mistake #4: Vague or incomplete subtasks

**WRONG:**
```json
{
  "id": 1,
  "title": "Set up database",
  "testStrategy": "Test it",
  "acceptanceCriteria": ["Works"]
}
```

**CORRECT:**
```json
{
  "id": 1,
  "title": "Configure PostgreSQL database and connection pooling",
  "testStrategy": "Run connection test, verify pool size=20, test failover",
  "acceptanceCriteria": [
    "PostgreSQL 15+ installed and running",
    "Connection pool configured with min=5, max=20",
    "Connection failover tested",
    "Database migrations folder created"
  ],
  "details": "Install PostgreSQL, configure pg_pool, set up environment variables"
}
```

### ❌ Mistake #5: Missing integration task

**WRONG:** Tasks end with last feature, no integration/E2E/validation tasks.

**CORRECT:** Last master task MUST be "Integration & Production Validation" with 3 subtasks:
1. Component Integration Testing
2. End-to-End Workflow Testing
3. Production Readiness Validation

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

## Complete Example: PRD → tasks.json

### Example PRD (Simplified)

```markdown
# E-Commerce Platform PRD

## 3. Features

### 3.1 User Authentication
- Login/logout functionality
- Password reset
- Session management

### 3.2 Product Catalog
- Browse products
- Search functionality
- Filter by category

### 3.3 Shopping Cart
- Add/remove items
- Update quantities
- Persist across sessions

### 3.4 Checkout
- Payment processing
- Order confirmation
- Email notifications

## 4. Integration Requirements
- Component integration testing
- E2E user journey testing
- Production readiness validation
```

### Example tasks.json Output

```json
{
  "master": {
    "tasks": [
      {
        "id": 1,
        "name": "Project Foundation Setup",
        "subtasks": [
          {
            "id": 1,
            "title": "Initialize project repository with CI/CD",
            "testStrategy": "Verify GitHub Actions workflow runs successfully",
            "acceptanceCriteria": [
              "Repository created with main branch",
              "CI/CD pipeline configured",
              "Basic test workflow passes"
            ],
            "details": "Set up project structure, configure build tools, establish CI/CD"
          },
          {
            "id": 2,
            "title": "Configure database and ORM",
            "testStrategy": "Run migration and verify schema creation",
            "acceptanceCriteria": [
              "Database connection established",
              "ORM configured",
              "Initial migration runs successfully"
            ],
            "details": "Set up PostgreSQL, configure Prisma/TypeORM, create base schema"
          }
        ]
      },
      {
        "id": 2,
        "name": "User Authentication System",
        "subtasks": [
          {
            "id": 1,
            "title": "Implement user registration endpoint",
            "testStrategy": "Unit tests for registration validation, integration test for user creation",
            "acceptanceCriteria": [
              "POST /api/auth/register endpoint created",
              "Email validation working",
              "Password hashing implemented",
              "User record created in database"
            ],
            "details": "Create User model, implement registration logic, add validation"
          },
          {
            "id": 2,
            "title": "Implement login/logout with JWT",
            "testStrategy": "Test token generation, verify token expiration, test logout invalidation",
            "acceptanceCriteria": [
              "POST /api/auth/login returns valid JWT",
              "POST /api/auth/logout invalidates token",
              "Token includes user claims",
              "Token expiration configured (24h)"
            ],
            "details": "Set up JWT library, create auth middleware, implement token management"
          },
          {
            "id": 3,
            "title": "Add password reset functionality",
            "testStrategy": "Test email sending, verify reset token generation and validation",
            "acceptanceCriteria": [
              "Password reset email sent successfully",
              "Reset token expires after 1 hour",
              "Token validation prevents reuse",
              "Password update works"
            ],
            "details": "Implement password reset flow, integrate email service, add reset token management"
          }
        ]
      },
      {
        "id": 3,
        "name": "Product Catalog Management",
        "subtasks": [
          {
            "id": 1,
            "title": "Create Product model and CRUD APIs",
            "testStrategy": "Unit tests for model validation, integration tests for CRUD operations",
            "acceptanceCriteria": [
              "Product model with required fields (name, price, description, stock)",
              "GET /api/products returns paginated list",
              "POST /api/products creates product (admin only)",
              "PUT /api/products/:id updates product",
              "DELETE /api/products/:id soft-deletes product"
            ],
            "details": "Design Product schema, implement CRUD endpoints, add admin authorization"
          },
          {
            "id": 2,
            "title": "Implement search and filtering",
            "testStrategy": "Test search accuracy, verify filter combinations, check performance",
            "acceptanceCriteria": [
              "Search by product name working",
              "Filter by category functional",
              "Filter by price range working",
              "Search results paginated",
              "Response time < 200ms for 10k products"
            ],
            "details": "Add search indexing, implement filter logic, optimize queries"
          }
        ]
      },
      {
        "id": 4,
        "name": "Shopping Cart Implementation",
        "subtasks": [
          {
            "id": 1,
            "title": "Create Cart model and add/remove APIs",
            "testStrategy": "Test cart operations, verify item quantity updates, check edge cases",
            "acceptanceCriteria": [
              "POST /api/cart/add adds item to cart",
              "DELETE /api/cart/remove removes item",
              "PUT /api/cart/update changes quantity",
              "Cart items persist in database",
              "Concurrent updates handled correctly"
            ],
            "details": "Design Cart and CartItem models, implement cart operations, handle race conditions"
          },
          {
            "id": 2,
            "title": "Add session persistence and guest cart support",
            "testStrategy": "Test cart survival across sessions, verify guest-to-user cart merge",
            "acceptanceCriteria": [
              "Logged-in user cart persists across sessions",
              "Guest cart stored in session/cookies",
              "Guest cart merges to user cart on login",
              "Cart expires after 30 days of inactivity"
            ],
            "details": "Implement session management, add guest cart logic, create merge functionality"
          }
        ]
      },
      {
        "id": 5,
        "name": "Checkout and Payment Processing",
        "subtasks": [
          {
            "id": 1,
            "title": "Integrate Stripe payment processing",
            "testStrategy": "Test payment flow with Stripe test cards, verify webhook handling",
            "acceptanceCriteria": [
              "Stripe SDK integrated",
              "Payment intent creation working",
              "Test card payments successful",
              "Payment webhooks handled correctly",
              "Failed payments logged"
            ],
            "details": "Set up Stripe account, implement payment API, add webhook endpoints"
          },
          {
            "id": 2,
            "title": "Create order confirmation and email notifications",
            "testStrategy": "Test order creation, verify email sending, check idempotency",
            "acceptanceCriteria": [
              "Order record created after successful payment",
              "Confirmation email sent to customer",
              "Email includes order details and tracking",
              "Duplicate orders prevented",
              "Order status tracking implemented"
            ],
            "details": "Create Order model, implement email templates, add notification service"
          }
        ]
      },
      {
        "id": 6,
        "name": "Integration & Production Validation",
        "subtasks": [
          {
            "id": 1,
            "title": "Component Integration Testing",
            "testStrategy": "Execute integration test suite covering all component interactions",
            "acceptanceCriteria": [
              "All component interfaces tested (Auth ↔ Cart, Cart ↔ Checkout, etc.)",
              "API contract tests passing",
              "Database transaction tests passing",
              "Integration test coverage > 80%"
            ],
            "details": "Create integration test suite, test cross-component workflows, verify data consistency"
          },
          {
            "id": 2,
            "title": "End-to-End Workflow Testing",
            "testStrategy": "Execute E2E tests for critical user journeys using Playwright",
            "acceptanceCriteria": [
              "E2E test: Browse → Add to Cart → Checkout → Order Success",
              "E2E test: User Registration → Login → Browse → Purchase",
              "E2E test: Password Reset Flow",
              "All E2E tests passing",
              "E2E tests run in CI/CD"
            ],
            "details": "Set up Playwright, create E2E test scenarios, integrate with CI"
          },
          {
            "id": 3,
            "title": "Production Readiness Validation",
            "testStrategy": "Execute comprehensive validation checklist",
            "acceptanceCriteria": [
              "All unit tests passing (>90% coverage)",
              "All integration tests passing (>80% coverage)",
              "All E2E tests passing",
              "Security scan passed (no critical vulnerabilities)",
              "Performance benchmarks met (<200ms API response)",
              "Database migrations tested",
              "Error handling and logging verified",
              "Monitoring and alerting configured"
            ],
            "details": "Run full test suite, security scan, performance tests, deployment validation"
          }
        ]
      }
    ]
  }
}
```

### Key Points from Example

✅ **8-12 Master Tasks**: 6 master tasks (foundation + 4 features + integration)
✅ **3-8 Subtasks Each**: Each master has 2-3 subtasks
✅ **Numeric IDs**: Sequential 1, 2, 3...
✅ **Integration Task Last**: Task 6 is Integration & Validation with 3 critical subtasks
✅ **Complete Fields**: Every subtask has testStrategy, acceptanceCriteria, details
✅ **PRD Coverage**: All Section 3 features + Section 4 integration requirements mapped

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