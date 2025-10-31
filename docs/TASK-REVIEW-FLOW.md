# Task Review Flow

## Overview
The pipeline now includes an **interactive review gate** after task generation, allowing you to review, refine, and approve tasks before full automation begins.

## Complete Flow

```
┌─────────────────┐
│   User Creates  │
│      PRD        │
└────────┬────────┘
         ↓
┌─────────────────┐
│  PRD-to-Tasks   │
│  (Automatic)    │
└────────┬────────┘
         ↓
╔═════════════════╗
║  REVIEW GATE    ║ ← YOU ARE HERE (Interactive)
║                 ║
║ • View tasks    ║
║ • Modify/refine ║
║ • Add/remove    ║
║ • Reorder deps  ║
║ • Natural lang   ║
║ • APPROVE       ║
╚════════╤════════╝
         ↓ (After approval)
         
    🤖 FULLY AUTONOMOUS FROM HERE 🤖
    
┌─────────────────┐
│ Coupling Analysis│
│   (Automatic)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│Task Decomposition│
│   (Automatic)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Spec Generation │
│   (Automatic)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│ TDD Implementation│
│   (Automatic)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│Integration Testing│
│   (Automatic)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│  E2E Testing    │
│   (Automatic)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Docker Deploy   │
│   (Automatic)   │
└────────┬────────┘
         ↓
    ✅ DEMO READY
```

## Review Gate Features

### 1. Task Display
```
Generated 30 tasks from PRD analysis:

Task 1: Set up project structure
Task 2: Design system architecture  
Task 3: Define API contracts
Task 4: Create database schema
...
```

### 2. Interactive Commands

| Command | Description |
|---------|-------------|
| `approve` | Accept tasks and start automation |
| `review` | Enter detailed review mode |
| `show` | Display all tasks with details |
| `phase X` | Show tasks for specific phase |
| `modify X` | Edit task X interactively |
| `add` | Add a new task |
| `remove X` | Delete task X |
| `deps X` | View/edit dependencies |
| `reject` | Start over with task generation |

### 3. Natural Language Refinement

You can also provide feedback in plain English:

- "Task 7 should come before task 6"
- "Add a security audit after task 15"  
- "Split the authentication task into JWT and OAuth2"
- "The database task needs migration setup"
- "Combine tasks 8 and 9 into one"

Claude will interpret and apply your changes intelligently.

## Example Review Session

```
You: "Show me task 7"

Claude: Task #7: Build authentication service
        Description: Implement user authentication with JWT
        Dependencies: [6]
        Acceptance Criteria:
        - JWT token generation
        - Token validation
        - Refresh token logic
        
You: "Split this into two tasks - one for JWT and one for OAuth2"

Claude: I'll split Task 7 into:
        
        Task 7a: Implement JWT Authentication
        - JWT token generation and validation
        - Refresh token management
        
        Task 7b: Implement OAuth2 Integration
        - OAuth2 provider configuration
        - Social login flows
        
        Shall I apply these changes? (y/n)

You: "Yes, and make sure both are done before task 10"

Claude: ✓ Updated! Tasks 7a and 7b are now prerequisites for Task 10.
        
You: "approve"

Claude: ✅ Tasks approved! Starting automated development...
        [Pipeline continues automatically through all phases]
```

## Benefits

1. **Quality Control**: Review tasks before committing to full automation
2. **Flexibility**: Easy refinements without stopping the pipeline
3. **Natural Language**: Describe changes conversationally
4. **Confidence**: Know exactly what will be built
5. **One-Time Review**: After approval, everything runs automatically

## Timing

- Task generation: 2-3 minutes
- Review session: 5-15 minutes (depending on refinements)
- After approval: 45-90 minutes fully automated
- **Total**: ~1-2 hours from PRD to running demo

## Skip Review Option

If you trust the task generation completely, you can skip review:

```bash
# Auto-approve tasks without review
echo "auto-approve" > .skip-task-review

# Or set environment variable
export SKIP_TASK_REVIEW=true
```

## Review States

| State | Description |
|-------|-------------|
| `TASKS_GENERATED` | Initial tasks created, awaiting review |
| `UNDER_REVIEW` | Interactive review in progress |
| `TASKS_APPROVED` | Review complete, automation starting |
| `TASKS_REJECTED` | Issues found, regenerating |

## What Happens After Approval

Once you approve the tasks:

1. **No more interruptions** - Pipeline runs completely hands-off
2. **Automatic transitions** - Each phase flows into the next
3. **Docker containers** - Built and started automatically
4. **Health checks** - Services validated
5. **Demo ready** - Full working system

The only pause is this review gate - everything else is autonomous!