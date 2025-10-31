# Claude Dev Pipeline - Worktree Isolation Strategy

## Overview

The Claude Dev Pipeline employs a sophisticated git worktree isolation strategy to ensure complete environment separation during development phases. This approach provides atomic operations, rollback capabilities, and prevents interference between concurrent development activities.

## Table of Contents

1. [Worktree Isolation Principles](#worktree-isolation-principles)
2. [Implementation Architecture](#implementation-architecture)
3. [Worktree Lifecycle Management](#worktree-lifecycle-management)
4. [Naming Conventions](#naming-conventions)
5. [Usage Examples](#usage-examples)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting-worktree-issues)
8. [Advanced Scenarios](#advanced-scenarios)

## Worktree Isolation Principles

### Core Benefits

1. **Complete Environment Isolation**: Each phase operates in its own git worktree
2. **Atomic Development**: All changes contained until explicit merge
3. **Rollback Capability**: Failed phases can be discarded without affecting main
4. **Parallel Execution Ready**: Foundation for future concurrent phase execution
5. **State Preservation**: Main branch remains stable throughout pipeline execution

### Isolation Guarantees

```
Main Repository
    │
    ├─ main branch (always stable)
    │   ├─ Protected from direct modification
    │   ├─ Only receives merged changes
    │   └─ Maintains project integrity
    │
    └─ worktrees/ (isolated environments)
        ├─ phase-1-task-1/ (PRD-to-Tasks)
        │   ├─ Independent file system
        │   ├─ Isolated git state
        │   └─ No cross-contamination
        │
        ├─ phase-2-task-4/ (Spec Generation)
        │   ├─ Clean starting state
        │   ├─ Phase-specific changes
        │   └─ Controlled merge process
        │
        └─ [other phases...]
```

### State Management Integration

```
Worktree Creation → State Update → Execution → State Tracking → Merge → Cleanup
       │               │            │             │             │        │
       ▼               ▼            ▼             ▼             ▼        ▼
   Git Worktree    Record Path   File Ops    Track Changes   Validate  Remove
       │               │            │             │             │        │
       ▼               ▼            ▼             ▼             ▼        ▼
   Branch Create   JSON Update   Isolated    Progress Log   Success   Archive
```

## Implementation Architecture

### Worktree Manager Component

The worktree manager (`lib/worktree-manager.sh`) provides comprehensive lifecycle management:

```bash
./lib/worktree-manager.sh
├── create <phase> <task>        # Create new worktree
├── status [worktree-name]       # Check worktree status
├── validate <worktree-name>     # Validate isolation
├── merge <worktree-name>        # Merge changes to main
├── cleanup <worktree-name>      # Remove worktree
├── list                         # List all worktrees
├── archive <worktree-name>      # Archive before cleanup
└── recover <archive-name>       # Recover from archive
```

### Directory Structure

```
project-root/
├── .git/                       # Main repository
├── .claude/                    # Pipeline configuration
│   ├── settings.json
│   ├── skill-rules.json
│   └── .workflow-state.json
├── worktrees/                  # Isolated environments
│   ├── phase-1-task-1/         # PRD-to-Tasks worktree
│   │   ├── .git → .git/worktrees/phase-1-task-1
│   │   ├── PRD.md
│   │   ├── tasks.json          # Generated in isolation
│   │   └── [other files...]
│   ├── phase-2-task-4/         # Spec Generation worktree
│   │   ├── .git → .git/worktrees/phase-2-task-4
│   │   ├── tasks.json          # Inherited from merge
│   │   ├── .openspec/          # Generated specs
│   │   └── [other files...]
│   └── [other phases...]
├── .state-backups/             # State management
├── .locks/                     # Concurrency control
└── config/                     # Worktree state tracking
    └── worktree-state.json
```

### State Tracking Schema

```json
{
  "version": "1.0",
  "worktrees": {
    "phase-1-task-1": {
      "status": "active",
      "phase": 1,
      "task": 1,
      "branch": "phase-1-task-1",
      "path": "./worktrees/phase-1-task-1",
      "created_at": "2023-11-01T10:30:00Z",
      "last_activity": "2023-11-01T10:35:00Z",
      "skill": "prd-to-tasks",
      "base_commit": "abc123def456",
      "changes": ["tasks.json", ".signals/phase1-start.json"],
      "merge_status": "pending"
    },
    "phase-2-task-4": {
      "status": "completed",
      "phase": 2,
      "task": 4,
      "branch": "phase-2-task-4",
      "path": "./worktrees/phase-2-task-4",
      "created_at": "2023-11-01T11:00:00Z",
      "completed_at": "2023-11-01T11:30:00Z",
      "skill": "spec-gen",
      "base_commit": "def456ghi789",
      "changes": [".openspec/calculator.proposal.md"],
      "merge_status": "merged",
      "merged_at": "2023-11-01T11:35:00Z"
    }
  },
  "active_worktree": "phase-1-task-1",
  "last_updated": "2023-11-01T11:35:00Z"
}
```

## Worktree Lifecycle Management

### 1. Creation Phase

```bash
# Automatic creation during skill activation
./lib/worktree-manager.sh create 1 1

# Creates:
# 1. Git worktree: ./worktrees/phase-1-task-1
# 2. Branch: phase-1-task-1 (based on main)
# 3. State tracking entry
# 4. Validation of isolation
```

**Creation Process**:

```
Phase/Task Request
    │
    ▼
Generate Worktree Name
    │ (phase-{phase}-task-{task})
    ▼
Validate Prerequisites
    │ (git status clean, no conflicts)
    ▼
Create Git Worktree
    │ (git worktree add ./worktrees/{name} -b {name})
    ▼
Update State Tracking
    │ (record in worktree-state.json)
    ▼
Validate Isolation
    │ (check git status, file independence)
    ▼
Return Success/Failure
```

### 2. Execution Phase

During skill execution, all operations are confined to the worktree:

```bash
# Skill execution context
cd ./worktrees/phase-1-task-1

# All file operations isolated
echo '{"tasks": [...]}' > tasks.json
mkdir -p .signals
echo '{"signal": "PHASE1_START"}' > .signals/phase1-start.json

# Git operations local to worktree
git add .
git commit -m "Generate tasks from PRD"

# State remains isolated from main
```

**Execution Monitoring**:

```
File Operations → Isolation Check → Activity Tracking → State Update
       │               │                │                │
       ▼               ▼                ▼                ▼
   Write files    Validate path    Log timestamp    Update JSON
       │               │                │                │
       ▼               ▼                ▼                ▼
   Git operations   Check bounds   Track changes    Record status
```

### 3. Validation Phase

Before merging, comprehensive validation ensures safety:

```bash
# Pre-merge validation
./lib/worktree-manager.sh validate phase-1-task-1

# Checks performed:
# 1. Git status clean
# 2. No conflicts with main
# 3. Required files present
# 4. Phase completion signals exist
# 5. No forbidden modifications
```

**Validation Checklist**:

```
Pre-Merge Validation
├── Git State Validation
│   ├─ No uncommitted changes
│   ├─ All changes committed
│   └─ No merge conflicts
├── File Validation
│   ├─ Required outputs present
│   ├─ No unauthorized modifications
│   └─ File integrity checks
├── Phase Validation
│   ├─ Phase completion signals
│   ├─ Task completion status
│   └─ Quality gates passed
└── Security Validation
    ├─ No sensitive data exposure
    ├─ Path traversal protection
    └─ Permission compliance
```

### 4. Merge Phase

Successful validation triggers the merge process:

```bash
# Merge process
./lib/worktree-manager.sh merge phase-1-task-1

# Steps performed:
# 1. Switch to main branch
# 2. Pull latest changes (if needed)
# 3. Merge worktree branch
# 4. Verify merge success
# 5. Update state tracking
# 6. Trigger next phase (if applicable)
```

**Merge Strategy**:

```
Preparation
├── Switch to main branch
├── Ensure main is up-to-date
└── Check for conflicts

Merge Execution
├── git merge worktree-branch --no-ff
├── Resolve any conflicts (manual intervention)
├── Verify merge commit
└── Push to remote (if configured)

Post-Merge
├── Update worktree state
├── Emit merge completion signal
├── Trigger next phase activation
└── Schedule cleanup (optional)
```

### 5. Cleanup Phase

After successful merge, cleanup removes the worktree:

```bash
# Cleanup options
./lib/worktree-manager.sh cleanup phase-1-task-1

# Or with archival
./lib/worktree-manager.sh archive phase-1-task-1
./lib/worktree-manager.sh cleanup phase-1-task-1

# Removes:
# 1. Worktree directory
# 2. Git worktree tracking
# 3. State tracking entry
# 4. Temporary files
```

**Cleanup Process**:

```
Archive Decision
├── Keep History? → Archive
│   ├─ Compress worktree
│   ├─ Store metadata
│   └─ Preserve for recovery
└── No History → Direct Cleanup

Cleanup Execution
├── Remove worktree directory
├── Delete git worktree reference
├── Update state tracking
└── Clean temporary files

Verification
├── Confirm removal
├── Update worktree list
└── Log cleanup action
```

## Naming Conventions

### Worktree Names

Format: `phase-{phase}-task-{task}`

```
Examples:
phase-1-task-1      # PRD-to-Tasks (Phase 1, Task 1)
phase-1-task-2      # Coupling Analysis (Phase 1, Task 2)
phase-1-task-3      # Task Decomposer (Phase 1, Task 3)
phase-2-task-4      # Spec Generation (Phase 2, Task 4)
phase-2-task-5      # Test Strategy (Phase 2, Task 5)
phase-3-task-6      # TDD Implementation (Phase 3, Task 6)
phase-4-task-24     # Integration Testing (Phase 4, Task 24)
phase-5-task-25     # E2E Testing (Phase 5, Task 25)
phase-6-task-26     # Deployment (Phase 6, Task 26)
```

### Branch Names

Branch names match worktree names for consistency:

```
Git Branches:
main                        # Stable main branch
phase-1-task-1             # PRD-to-Tasks branch
phase-1-task-2             # Coupling Analysis branch
[...other phases...]
```

### Directory Conventions

```
./worktrees/
├── phase-1-task-1/         # Current worktree directories
├── phase-2-task-4/
└── phase-3-task-6/

./archives/                 # Archived worktrees (optional)
├── phase-1-task-1-20231101-103000.tar.gz
└── phase-2-task-4-20231101-113000.tar.gz

./temp/                     # Temporary worktree operations
├── merge-prep-phase-1-task-1/
└── validation-phase-2-task-4/
```

## Usage Examples

### Basic Worktree Operations

#### Creating a Worktree

```bash
# Create worktree for Phase 1, Task 1 (PRD-to-Tasks)
./lib/worktree-manager.sh create 1 1

# Output:
# [INFO] Creating worktree: phase-1-task-1
# [INFO] Base branch: main (commit: abc123)
# [INFO] Worktree path: ./worktrees/phase-1-task-1
# [INFO] Branch created: phase-1-task-1
# [INFO] State updated: worktree active
# [SUCCESS] Worktree phase-1-task-1 created successfully

# Verify creation
ls -la ./worktrees/phase-1-task-1/
git worktree list
```

#### Working in a Worktree

```bash
# Navigate to worktree
cd ./worktrees/phase-1-task-1

# Verify isolation
pwd
git branch
git status

# Perform work (example: PRD-to-Tasks skill)
echo 'Analyzing PRD...' > .analysis.log
echo '{"tasks": [...]}' > tasks.json
mkdir -p .signals
echo '{"signal": "PHASE1_START"}' > .signals/phase1-start.json

# Commit changes
git add .
git commit -m "feat: generate tasks from PRD

- Analyzed product requirements
- Generated 26 tasks with dependencies
- Created phase completion signal"

# Check status
git log --oneline -3
```

#### Merging Changes

```bash
# Validate before merge
./lib/worktree-manager.sh validate phase-1-task-1

# If validation passes, merge
./lib/worktree-manager.sh merge phase-1-task-1

# Output:
# [INFO] Validating worktree: phase-1-task-1
# [SUCCESS] Validation passed
# [INFO] Switching to main branch
# [INFO] Merging branch: phase-1-task-1
# [INFO] Merge completed successfully
# [INFO] State updated: worktree merged
# [SUCCESS] Changes merged to main branch

# Verify merge
git log --oneline -5
git show --stat
```

#### Cleanup

```bash
# Archive before cleanup (optional)
./lib/worktree-manager.sh archive phase-1-task-1

# Clean up worktree
./lib/worktree-manager.sh cleanup phase-1-task-1

# Output:
# [INFO] Archiving worktree: phase-1-task-1
# [INFO] Archive created: ./archives/phase-1-task-1-20231101-103000.tar.gz
# [INFO] Removing worktree: phase-1-task-1
# [INFO] Git worktree removed
# [INFO] State updated: worktree cleaned
# [SUCCESS] Worktree cleanup completed

# Verify cleanup
git worktree list
ls ./worktrees/
```

### Advanced Operations

#### Parallel Worktrees (Future)

```bash
# Create multiple worktrees for parallel work
./lib/worktree-manager.sh create 2 4  # Spec generation
./lib/worktree-manager.sh create 2 5  # Test strategy

# Work in parallel (different terminals/processes)
# Terminal 1:
cd ./worktrees/phase-2-task-4
# ... perform spec generation work

# Terminal 2:
cd ./worktrees/phase-2-task-5
# ... perform test strategy work

# Coordinate merge order
./lib/worktree-manager.sh merge phase-2-task-4  # First
./lib/worktree-manager.sh merge phase-2-task-5  # Second
```

#### Recovery from Archives

```bash
# List available archives
ls -la ./archives/

# Recover specific worktree
./lib/worktree-manager.sh recover phase-1-task-1-20231101-103000.tar.gz

# This creates a new worktree with recovered content
# Useful for debugging or continuation after failure
```

#### Status Monitoring

```bash
# Check all worktrees
./lib/worktree-manager.sh list

# Output:
# Active Worktrees:
# ├── phase-1-task-1 (active, created 2023-11-01 10:30)
# ├── phase-2-task-4 (completed, merged 2023-11-01 11:35)
# └── phase-3-task-6 (pending)
#
# Total: 2 active, 1 completed, 1 pending

# Detailed status for specific worktree
./lib/worktree-manager.sh status phase-1-task-1

# Output:
# Worktree: phase-1-task-1
# ├── Status: active
# ├── Phase: 1, Task: 1
# ├── Skill: prd-to-tasks
# ├── Path: ./worktrees/phase-1-task-1
# ├── Branch: phase-1-task-1
# ├── Created: 2023-11-01T10:30:00Z
# ├── Last Activity: 2023-11-01T10:35:00Z
# ├── Base Commit: abc123def456
# ├── Changes: 3 files modified
# └── Merge Status: pending
```

## Best Practices

### 1. Worktree Hygiene

```bash
# Before creating new worktrees
git worktree prune                    # Clean stale references
./lib/worktree-manager.sh cleanup-all # Remove completed worktrees

# Regular maintenance
find ./worktrees -name ".DS_Store" -delete  # macOS cleanup
find ./worktrees -name "*.tmp" -delete      # Temporary file cleanup
```

### 2. Branch Management

```bash
# Keep main branch clean
git checkout main
git pull origin main                  # Stay up-to-date

# Prune merged branches periodically
git branch --merged | grep -v main | xargs git branch -d
```

### 3. State Synchronization

```bash
# Verify state consistency
./lib/state-manager.sh validate
./lib/worktree-manager.sh validate-all

# Synchronize state if needed
./lib/state-manager.sh repair
```

### 4. Resource Management

```bash
# Monitor disk usage
du -sh ./worktrees/*
du -sh ./archives/*

# Clean old archives
find ./archives -name "*.tar.gz" -mtime +30 -delete
```

### 5. Error Prevention

```bash
# Always validate before operations
./lib/worktree-manager.sh validate <worktree> before merge
./lib/state-manager.sh backup before major changes

# Use checksums for critical files
md5sum tasks.json > tasks.json.md5
```

## Troubleshooting Worktree Issues

### Common Problems

#### Problem: Worktree Creation Fails

```bash
# Symptoms
ERROR: Cannot create worktree 'phase-1-task-1'
fatal: 'phase-1-task-1' already exists

# Diagnosis
git worktree list
ls -la ./worktrees/

# Solutions
# 1. Clean stale references
git worktree prune

# 2. Remove existing directory
rm -rf ./worktrees/phase-1-task-1

# 3. Force recreation
./lib/worktree-manager.sh cleanup phase-1-task-1 --force
./lib/worktree-manager.sh create 1 1
```

#### Problem: Merge Conflicts

```bash
# Symptoms
Auto-merging tasks.json
CONFLICT (content): Merge conflict in tasks.json

# Resolution Process
cd ./worktrees/phase-1-task-1
git status                           # See conflicted files

# Edit conflicted files
nano tasks.json                      # Resolve conflicts manually

# Complete merge
git add tasks.json
git commit -m "resolve: merge conflict in tasks.json"

# Continue with merge
cd ../../
./lib/worktree-manager.sh merge phase-1-task-1
```

#### Problem: Isolation Validation Fails

```bash
# Symptoms
ERROR: Worktree isolation validation failed
Found modifications outside worktree scope

# Diagnosis
./lib/worktree-manager.sh validate phase-1-task-1 --verbose

# Common causes and solutions
# 1. Symlinks outside worktree
find ./worktrees/phase-1-task-1 -type l -ls

# 2. Absolute paths in generated files
grep -r "/.*/" ./worktrees/phase-1-task-1/

# 3. Git operations on main repository
cd ./worktrees/phase-1-task-1
git status --porcelain
```

#### Problem: State Inconsistency

```bash
# Symptoms
WARNING: Worktree state inconsistent
Database shows 'active' but worktree not found

# Diagnosis
./lib/worktree-manager.sh status --all
git worktree list
cat config/worktree-state.json

# Recovery
./lib/worktree-manager.sh repair
./lib/state-manager.sh recover
```

### Recovery Procedures

#### Complete Worktree Reset

```bash
# Nuclear option: reset all worktrees
./lib/worktree-manager.sh cleanup-all --force
git worktree prune
rm -rf ./worktrees/*
rm -f config/worktree-state.json

# Reinitialize
./lib/worktree-manager.sh init
```

#### Selective Recovery

```bash
# Recover specific worktree from archive
./lib/worktree-manager.sh recover phase-1-task-1-20231101-103000.tar.gz

# Resume from recovered state
cd ./worktrees/phase-1-task-1-recovered
git status
git log --oneline -5

# Continue or merge as needed
```

## Advanced Scenarios

### Future Enhancement: Parallel Execution

The worktree strategy is designed to support parallel execution of independent tasks:

```bash
# Parallel execution scenario (future)
./lib/worktree-manager.sh create 1 1    # PRD-to-Tasks
./lib/worktree-manager.sh create 1 2    # Coupling Analysis
./lib/worktree-manager.sh create 1 3    # Task Decomposer

# Execute in parallel
parallel ./run-skill.sh ::: \
  "prd-to-tasks:phase-1-task-1" \
  "coupling-analysis:phase-1-task-2" \
  "task-decomposer:phase-1-task-3"

# Coordinate merges based on dependencies
./lib/worktree-manager.sh merge phase-1-task-1  # First
./lib/worktree-manager.sh merge phase-1-task-2  # After task 1
./lib/worktree-manager.sh merge phase-1-task-3  # After task 2
```

### Integration with CI/CD

```bash
# CI/CD integration example
# .github/workflows/pipeline.yml

name: Claude Dev Pipeline
on: [push, pull_request]

jobs:
  pipeline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Pipeline
        run: ./install-pipeline.sh --ci-mode
      
      - name: Run Pipeline
        run: |
          ./lib/worktree-manager.sh create 1 1
          cd ./worktrees/phase-1-task-1
          # ... execute pipeline steps
          cd ../..
          ./lib/worktree-manager.sh merge phase-1-task-1
      
      - name: Cleanup
        run: ./lib/worktree-manager.sh cleanup-all
```

### Custom Worktree Strategies

```bash
# Custom naming strategy
export WORKTREE_NAMING_STRATEGY="feature"
./lib/worktree-manager.sh create calculator-ui

# Custom base branch
export WORKTREE_BASE_BRANCH="develop"
./lib/worktree-manager.sh create 1 1

# Custom merge strategy
export WORKTREE_MERGE_STRATEGY="squash"
./lib/worktree-manager.sh merge phase-1-task-1
```

---

**Next**: Continue to [API.md](API.md) for detailed API documentation of all pipeline components.