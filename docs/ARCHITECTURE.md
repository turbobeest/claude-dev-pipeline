# Claude Dev Pipeline - System Architecture

## Overview

The Claude Dev Pipeline is a deterministic, codeword-based autonomous development system that guarantees skill activation and orchestrates complex development workflows through signal-driven phase transitions.

## Table of Contents

1. [System Architecture Overview](#system-architecture-overview)
2. [Component Architecture](#component-architecture)
3. [Data Flow Architecture](#data-flow-architecture)
4. [State Management Architecture](#state-management-architecture)
5. [Worktree Isolation Strategy](#worktree-isolation-strategy)
6. [Security Architecture](#security-architecture)
7. [Performance Considerations](#performance-considerations)
8. [Scalability Architecture](#scalability-architecture)

## System Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Claude Code User Interface               │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                     Hook System Layer                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ User Prompt │  │ Post Tool    │  │ Pre Implementation     │ │
│  │ Submit Hook │  │ Use Hook     │  │ Validator Hook          │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
└─────────────────────────┬───────────────────────────────────────┘
                          │ Codeword Injection
┌─────────────────────────▼───────────────────────────────────────┐
│                   Skill Orchestration Layer                    │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ Pipeline    │  │ PRD-to-Tasks │  │ Coupling Analysis       │ │
│  │ Orchestrator│  │ Skill        │  │ Skill                   │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ Task        │  │ Spec Gen     │  │ Test Strategy           │ │
│  │ Decomposer  │  │ Skill        │  │ Skill                   │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ TDD         │  │ Integration  │  │ E2E Validator           │ │
│  │ Implementer │  │ Validator    │  │ Skill                   │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│  ┌─────────────┐                                               │
│  │ Deployment  │                                               │
│  │ Orchestrator│                                               │
│  └─────────────┘                                               │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                  Infrastructure Layer                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ State       │  │ Lock         │  │ Error Recovery          │ │
│  │ Manager     │  │ Manager      │  │ System                  │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ Worktree    │  │ Logger       │  │ Metrics Collector       │ │
│  │ Manager     │  │ System       │  │                         │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                      Storage Layer                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ Workflow    │  │ Worktree     │  │ Configuration           │ │
│  │ State       │  │ State        │  │ Files                   │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ Signal      │  │ Lock Files   │  │ Audit Logs              │ │
│  │ Files       │  │              │  │                         │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Core Design Principles

1. **Deterministic Activation**: Codewords guarantee 100% skill activation
2. **Signal-Driven Transitions**: Phase progression through emitted signals
3. **Worktree Isolation**: Complete isolation of development phases
4. **Atomic Operations**: All state changes are atomic and recoverable
5. **Graceful Degradation**: System continues operating during partial failures

## Component Architecture

### 1. Hook System Components

#### UserPromptSubmit Hook (`skill-activation-prompt.sh`)

**Purpose**: Analyzes user input and injects activation codewords

**Architecture**:
```
User Input → Pattern Analysis → Context Analysis → Codeword Injection → Claude
     │              │                │                    │
     │              ▼                ▼                    ▼
     │        Rule Engine     File Detection     [ACTIVATE:SKILL_V1]
     │              │                │
     ▼              ▼                ▼
Signal Detection  Priority Queue  State Update
```

**Key Functions**:
- Pattern matching against user messages
- File existence detection
- Phase state analysis
- Priority-based skill selection
- Automatic codeword injection

#### PostToolUse Hook (`post-tool-use-tracker.sh`)

**Purpose**: Monitors tool execution and triggers phase transitions

**Architecture**:
```
Tool Execution → Result Analysis → Signal Emission → Phase Transition
       │               │               │               │
       ▼               ▼               ▼               ▼
  File Changes    Success/Failure  .signals/*.json  Next Skill
       │               │               │               │
       ▼               ▼               ▼               ▼
  State Update    Error Recovery   Auto Trigger    Codeword Inject
```

**Key Functions**:
- Tool execution monitoring
- File change detection
- Signal file generation
- Automatic phase transitions
- Error recovery triggering

#### PreImplementationValidator Hook (`pre-implementation-validator.sh`)

**Purpose**: Enforces TDD discipline and validates implementation readiness

**Architecture**:
```
Tool Request → Validation Checks → Decision → Allow/Block
      │              │              │           │
      ▼              ▼              ▼           ▼
Implementation? → Test Exists? → Ready? → Execute/Abort
      │              │              │           │
      ▼              ▼              ▼           ▼
   Phase 3?    → Test Files   → Gate Check → Tool Execution
```

### 2. Skill Architecture

#### Skill Structure

Each skill follows a standardized architecture:

```
skill-name/
├── SKILL.md                 # Skill definition and activation code
├── examples/               # Usage examples and templates
│   ├── input-example.md
│   ├── output-example.json
│   └── workflow-demo.md
└── templates/              # Reusable templates
    ├── task-template.json
    └── validation-checklist.md
```

#### Skill Activation Flow

```
User Message → Hook Analysis → Pattern Match → Codeword Injection → Skill Activation
      │              │             │              │                    │
      ▼              ▼             ▼              ▼                    ▼
   Context      Rule Engine    Priority      [ACTIVATE:CODE]       Execute
      │              │             │              │                    │
      ▼              ▼             ▼              ▼                    ▼
  File State    Conditions    Best Match    Claude Sees Code      Skill Runs
```

#### Phase-Based Skill Organization

```
Phase 0: Pipeline Orchestration
├── pipeline-orchestration (PIPELINE_ORCHESTRATION_V1)
└── Master controller and workflow coordinator

Phase 1: Requirements Analysis
├── prd-to-tasks (PRD_TO_TASKS_V1)
├── coupling-analysis (COUPLING_ANALYSIS_V1)
└── task-decomposer (TASK_DECOMPOSER_V1)

Phase 2: Specification and Planning
├── spec-gen (SPEC_GEN_V1)
└── test-strategy (TEST_STRATEGY_V1)

Phase 3: Implementation
└── tdd-implementer (TDD_IMPLEMENTER_V1)

Phase 4: Integration Testing
└── integration-validator (INTEGRATION_VALIDATOR_V1)

Phase 5: End-to-End Testing
└── e2e-validator (E2E_VALIDATOR_V1)

Phase 6: Deployment
└── deployment-orchestrator (DEPLOYMENT_ORCHESTRATOR_V1)
```

### 3. Infrastructure Components

#### State Manager (`lib/state-manager.sh`)

**Purpose**: Atomic, thread-safe state management

**Architecture**:
```
Operation Request → Lock Acquisition → Validation → Execution → Unlock
        │                │              │            │           │
        ▼                ▼              ▼            ▼           ▼
   API Call        File Lock        Schema       Temp File    Release
        │                │              │            │           │
        ▼                ▼              ▼            ▼           ▼
   Function         Process ID       JSON         Atomic        Cleanup
                                    Validate      Rename
```

**Key Features**:
- File-based locking (macOS compatible)
- Atomic updates via temp file + rename
- Automatic backup system
- Schema validation
- Corruption detection and recovery

#### Lock Manager (`lib/lock-manager.sh`)

**Purpose**: Centralized locking for concurrency control

**Architecture**:
```
Lock Request → Timeout Check → Process Validation → Grant/Deny
      │             │              │                   │
      ▼             ▼              ▼                   ▼
   Resource    Exponential      PID Check         Lock File
      │        Backoff             │                   │
      ▼             │              ▼                   ▼
  Lock Type         │         Ownership          Success/Fail
      │             │              │                   │
      ▼             ▼              ▼                   ▼
Exclusive/Shared   Retry       Valid Process       Return Status
```

#### Worktree Manager (`lib/worktree-manager.sh`)

**Purpose**: Git worktree lifecycle management

**Architecture**:
```
Worktree Request → Validation → Creation → Usage → Cleanup
        │             │          │         │        │
        ▼             ▼          ▼         ▼        ▼
   Phase/Task    Git Status   Branch     Execute    Merge
        │             │          │         │        │
        ▼             ▼          ▼         ▼        ▼
   Naming        Clean State   Checkout   Isolate   Remove
```

## Data Flow Architecture

### 1. User Input Flow

```
User Message
    │
    ▼
skill-activation-prompt.sh
    │
    ├─ Pattern Analysis
    │   ├─ User text patterns
    │   ├─ File existence checks
    │   └─ Phase state analysis
    │
    ├─ Skill Selection
    │   ├─ Priority matching
    │   ├─ Context validation
    │   └─ Codeword selection
    │
    └─ Message Modification
        ├─ Inject [ACTIVATE:CODE]
        ├─ Add context info
        └─ Forward to Claude
            │
            ▼
        Claude Skill Execution
            │
            ▼
        Tool Usage (Write, Edit, etc.)
            │
            ▼
        post-tool-use-tracker.sh
            │
            ├─ Monitor execution
            ├─ Detect file changes
            ├─ Emit signals
            └─ Trigger next phase
```

### 2. State Flow

```
Initial State
    │
    ▼
Phase Execution
    │
    ├─ State Lock Acquisition
    │
    ├─ Read Current State
    │   ├─ .workflow-state.json
    │   ├─ Validate schema
    │   └─ Check integrity
    │
    ├─ State Modification
    │   ├─ Update phase
    │   ├─ Add progress data
    │   ├─ Record timestamps
    │   └─ Backup current state
    │
    ├─ Atomic Write
    │   ├─ Write to temp file
    │   ├─ Validate JSON
    │   └─ Rename to final
    │
    └─ Lock Release
        │
        ▼
    Signal Emission
        │
        ▼
    Next Phase Trigger
```

### 3. Signal Flow

```
Phase Completion
    │
    ▼
Signal Generation
    │
    ├─ Create signal file
    │   ├─ .signals/PHASE_X_COMPLETE.json
    │   ├─ Timestamp
    │   ├─ Metadata
    │   └─ Next phase info
    │
    └─ State Update
        │
        ▼
Hook Detection
    │
    ├─ Monitor signal directory
    ├─ Parse signal content
    └─ Determine next action
        │
        ▼
Automatic Transition
    │
    ├─ Check auto_trigger flag
    ├─ Apply delay if configured
    ├─ Inject next codeword
    └─ Continue pipeline
```

### 4. Worktree Flow

```
Skill Activation
    │
    ▼
Worktree Creation
    │
    ├─ Generate unique name
    │   └─ phase-{phase}-task-{task}
    │
    ├─ Create git worktree
    │   ├─ Base branch: main
    │   ├─ Target: ./worktrees/{name}
    │   └─ Isolated environment
    │
    └─ Update worktree state
        │
        ▼
Skill Execution (in worktree)
    │
    ├─ All file operations isolated
    ├─ Git operations local
    └─ State changes tracked
        │
        ▼
Completion & Merge
    │
    ├─ Validate changes
    ├─ Merge to main branch
    ├─ Update worktree state
    └─ Cleanup (optional)
```

## State Management Architecture

### State Schema

```json
{
  "version": "1.0",
  "pipeline_id": "uuid",
  "project_name": "string",
  "current_phase": "number",
  "current_task": "number",
  "phase_status": "string",
  "started_at": "ISO8601",
  "last_updated": "ISO8601",
  "phases": {
    "0": { "status": "complete", "completed_at": "ISO8601" },
    "1": { "status": "in_progress", "started_at": "ISO8601" },
    "2": { "status": "pending" }
  },
  "active_worktree": "string",
  "signals_emitted": ["PHASE1_START", "COUPLING_ANALYZED"],
  "manual_gates": {
    "implementation_approved": false,
    "deployment_approved": false
  },
  "error_state": {
    "has_errors": false,
    "last_error": null,
    "recovery_attempted": false
  },
  "metrics": {
    "total_tasks": 26,
    "completed_tasks": 8,
    "estimated_completion": "ISO8601"
  }
}
```

### State Transitions

```
Initial → Phase0_Ready → Phase0_Complete → Phase1_Start
  │            │              │               │
  ▼            ▼              ▼               ▼
Empty     PRD_Ready      Orchestration    Task_Gen
  │            │              │               │
  ▼            ▼              ▼               ▼
  {        { phase: 0,    { phase: 0,    { phase: 1,
status:     status:        status:        status:
"init"   "ready" }    "complete" }   "active" }
}
```

### Concurrency Control

```
Process A                Process B
    │                        │
    ▼                        ▼
Lock Request             Lock Request
    │                        │
    ▼                        ▼
Acquire Lock            Wait (timeout)
    │                        │
    ▼                        │
Read State                   │
Modify State                 │
Write State                  │
    │                        │
    ▼                        ▼
Release Lock ────────► Acquire Lock
                            │
                            ▼
                       Read State
                       Modify State
                       Write State
                            │
                            ▼
                       Release Lock
```

## Worktree Isolation Strategy

### Isolation Principles

1. **Complete Environment Isolation**: Each phase operates in its own git worktree
2. **Atomic Operations**: All changes are contained until merge
3. **Rollback Capability**: Failed phases can be discarded without affecting main
4. **Parallel Execution**: Future enhancement for concurrent phase execution

### Worktree Naming Convention

```
./worktrees/
├── phase-1-task-1/     # PRD-to-Tasks execution
├── phase-1-task-2/     # Coupling Analysis execution  
├── phase-1-task-3/     # Task Decomposer execution
├── phase-2-task-4/     # Spec Generation execution
├── phase-2-task-5/     # Test Strategy execution
├── phase-3-task-6/     # TDD Implementation
├── phase-4-task-24/    # Integration Testing
├── phase-5-task-25/    # E2E Testing
└── phase-6-task-26/    # Deployment Orchestration
```

### Worktree Lifecycle

```
Create → Validate → Execute → Merge → Cleanup
   │        │         │        │        │
   ▼        ▼         ▼        ▼        ▼
Branch   Clean     Isolate   Validate  Remove
   │        │         │        │        │
   ▼        ▼         ▼        ▼        ▼
Checkout Pre-state  Changes   Tests    Archive
```

### Merge Strategy

```
Worktree Changes
    │
    ▼
Pre-merge Validation
    │
    ├─ Run tests in worktree
    ├─ Validate file integrity  
    ├─ Check for conflicts
    └─ Verify phase completion
        │
        ▼
    Validation Pass?
        │
        ├─ Yes → Continue
        └─ No → Abort, rollback
            │
            ▼
        Merge to Main
            │
            ├─ git checkout main
            ├─ git merge worktree-branch
            ├─ Verify merge success
            └─ Update state
                │
                ▼
            Post-merge Cleanup
                │
                ├─ Archive worktree (optional)
                ├─ Remove worktree
                └─ Update worktree state
```

## Security Architecture

### Authentication & Authorization

```
User → Claude Code → Hook System → Skill Execution
 │           │            │              │
 ▼           ▼            ▼              ▼
Auth    Pipeline      File Access    Git Operations
 │      Permissions       │              │
 ▼           │            ▼              ▼
User ID   Read/Write   Restricted    Isolated
         Pipeline     Directories   Branches
          Config
```

### File Permission Model

```
.claude/
├── settings.json           (600 - owner read/write only)
├── skill-rules.json        (644 - owner write, group read)
├── .workflow-state.json    (600 - owner read/write only)
├── .state-backups/         (700 - owner access only)
│   └── *.json             (600 - owner read/write only)
├── .locks/                 (750 - owner/group access)
│   └── *.lock             (644 - owner write, group read)
├── skills/                 (755 - public read, owner write)
├── hooks/                  (755 - public read, owner execute)
│   └── *.sh               (755 - executable by owner/group)
└── logs/                   (750 - owner/group access)
    └── *.log              (644 - owner write, group read)
```

### Process Isolation

```
Main Process
    │
    ├─ Hook Subprocess (restricted permissions)
    │   ├─ No network access
    │   ├─ Read-only config
    │   └─ Limited file access
    │
    ├─ Skill Subprocess (sandboxed)
    │   ├─ Worktree-restricted
    │   ├─ No system access
    │   └─ Monitored execution
    │
    └─ State Manager (elevated permissions)
        ├─ Atomic operations
        ├─ Lock management
        └─ Backup/recovery
```

### Audit Trail

```
Operation → Log Entry → Audit File → Review
    │           │          │           │
    ▼           ▼          ▼           ▼
User       Timestamp   Secure      Analysis
Action        │        Storage        │
    │         ▼           │           ▼
    ▼     Component       ▼       Security
Details   Identity   Immutable   Monitoring
    │         │          │           │
    ▼         ▼          ▼           ▼
Context   User ID    Tamper      Alerts
         Process     Evident
```

## Performance Considerations

### Optimization Strategies

#### 1. Lock Management Optimization

```
Lock Acquisition Time Targets:
- State locks: < 100ms
- Worktree locks: < 200ms  
- File locks: < 50ms

Optimization Techniques:
- Minimal lock hold time
- Lock hierarchy to prevent deadlocks
- Exponential backoff for retries
- Stale lock detection and cleanup
```

#### 2. State Operation Performance

```
Operation Performance Targets:
- State read: < 50ms
- State write: < 100ms
- State validation: < 25ms
- Backup creation: < 75ms

Optimization Techniques:
- In-memory state caching
- Incremental backups
- Background cleanup
- Lazy validation
```

#### 3. Worktree Performance

```
Worktree Operation Targets:
- Creation: < 2s
- Merge: < 5s
- Cleanup: < 1s

Optimization Techniques:
- Shallow clones for speed
- Parallel operations where safe
- Background cleanup
- Smart merge strategies
```

#### 4. Memory Management

```
Memory Usage Targets:
- Hook processes: < 50MB
- State manager: < 100MB
- Worktree operations: < 200MB

Optimization Techniques:
- Stream processing for large files
- Temporary file cleanup
- Efficient data structures
- Memory monitoring
```

### Monitoring & Metrics

```
Performance Metrics Collection:
    │
    ├─ Hook Execution Time
    │   ├─ Pattern matching: < 10ms
    │   ├─ Codeword injection: < 5ms
    │   └─ State updates: < 50ms
    │
    ├─ Skill Activation Time
    │   ├─ Discovery: < 100ms
    │   ├─ Loading: < 500ms
    │   └─ Execution: variable
    │
    ├─ Infrastructure Operations
    │   ├─ Lock operations: < 100ms
    │   ├─ State operations: < 50ms
    │   └─ Worktree operations: < 2s
    │
    └─ Resource Utilization
        ├─ CPU usage: < 25%
        ├─ Memory usage: < 500MB
        └─ Disk I/O: < 10MB/s
```

## Scalability Architecture

### Horizontal Scaling Considerations

#### Multi-Project Support

```
Project A                Project B                Project C
    │                        │                        │
    ▼                        ▼                        ▼
.claude/                 .claude/                 .claude/
├── instance-a/          ├── instance-b/          ├── instance-c/
│   ├── state.json       │   ├── state.json       │   ├── state.json
│   ├── locks/           │   ├── locks/           │   ├── locks/
│   └── worktrees/       │   └── worktrees/       │   └── worktrees/
└── shared/              └── shared/              └── shared/
    ├── skills/              ├── skills/              ├── skills/
    └── lib/                 └── lib/                 └── lib/
```

#### Distributed Execution

```
Future Enhancement: Distributed Skills
    │
    ├─ Phase 1 (Local)
    │   ├─ PRD-to-Tasks
    │   ├─ Coupling Analysis
    │   └─ Task Decomposition
    │
    ├─ Phase 2 (Distributed)
    │   ├─ Spec Gen → Worker Node A
    │   └─ Test Strategy → Worker Node B
    │
    ├─ Phase 3 (Parallel)
    │   ├─ TDD Implementation → Multiple Workers
    │   └─ Task parallelization based on coupling
    │
    └─ Phase 4-6 (Coordinated)
        ├─ Integration Testing → Coordinator
        ├─ E2E Testing → Dedicated Environment
        └─ Deployment → Production Pipeline
```

### Vertical Scaling Strategies

#### Resource Allocation

```
Component Resource Allocation:
    │
    ├─ Hook System
    │   ├─ CPU: Low priority, < 1 core
    │   ├─ Memory: < 100MB per hook
    │   └─ I/O: Minimal, config reading
    │
    ├─ Skill Execution
    │   ├─ CPU: High priority, 2-4 cores
    │   ├─ Memory: 1-4GB based on skill
    │   └─ I/O: Heavy, file operations
    │
    ├─ Infrastructure
    │   ├─ CPU: Medium priority, 1-2 cores
    │   ├─ Memory: 200-500MB
    │   └─ I/O: Moderate, state management
    │
    └─ Worktree Operations
        ├─ CPU: Medium priority, 1-2 cores
        ├─ Memory: 200MB-1GB
        └─ I/O: Heavy, git operations
```

### Future Architecture Enhancements

#### 1. Microservices Decomposition

```
Current Monolithic Design → Future Microservices
    │
    ├─ Hook Service
    │   ├─ Pattern matching API
    │   ├─ Codeword injection API
    │   └─ Message processing API
    │
    ├─ Skill Orchestration Service
    │   ├─ Skill discovery API
    │   ├─ Execution management API
    │   └─ Progress tracking API
    │
    ├─ State Management Service
    │   ├─ State CRUD API
    │   ├─ Lock management API
    │   └─ Event streaming API
    │
    └─ Worktree Management Service
        ├─ Lifecycle management API
        ├─ Isolation enforcement API
        └─ Merge coordination API
```

#### 2. Event-Driven Architecture

```
Current Signal Files → Future Event Bus
    │
    ├─ Event Publisher
    │   ├─ Phase completion events
    │   ├─ Error events
    │   └─ Progress events
    │
    ├─ Event Router
    │   ├─ Topic-based routing
    │   ├─ Priority handling
    │   └─ Delivery guarantees
    │
    └─ Event Consumers
        ├─ Skill activation handlers
        ├─ State update handlers
        └─ Notification handlers
```

---

**Next**: Continue to [WORKTREE-STRATEGY.md](WORKTREE-STRATEGY.md) to understand the isolation implementation details.