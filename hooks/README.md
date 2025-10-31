# Hooks Documentation

This directory contains the Claude Dev Pipeline hook system that enables automated skill activation and worktree management.

## Hooks Overview

### Core Hooks

1. **skill-activation-prompt.sh** (UserPromptSubmit)
   - Analyzes user messages and injects skill activation codewords
   - Detects worktree context and exports environment variables
   - Enforces worktree isolation for pipeline operations

2. **post-tool-use-tracker.sh** (PostToolUse)
   - Tracks tool usage and workflow progress
   - Monitors worktree operations and git commands
   - Updates worktree state and activity timestamps

3. **pre-implementation-validator.sh** (PreToolUse)
   - Validates TDD compliance before file operations
   - Enforces worktree isolation boundaries
   - Auto-creates worktrees when needed

### Worktree Management

4. **worktree-enforcer.sh**
   - Standalone enforcer for worktree isolation rules
   - Validates worktree boundaries and prevents contamination
   - Auto-creates missing worktrees for pipeline operations

## Worktree Isolation System

The pipeline enforces strict worktree isolation with the following naming convention:
- `phase-X-task-Y` format (e.g., `phase-1-task-1`, `phase-3-task-5`)
- Each task gets its own isolated git worktree
- No cross-worktree contamination allowed
- Automatic cleanup after successful merges

### Environment Variables

The hooks set these environment variables for skills:
- `CLAUDE_CURRENT_PHASE` - Current pipeline phase (1-6)
- `CLAUDE_CURRENT_TASK` - Current task number within phase
- `CLAUDE_CURRENT_WORKTREE` - Name of current worktree
- `CLAUDE_ENFORCE_WORKTREES` - Enable/disable worktree enforcement
- `CLAUDE_AUTO_CREATE_WORKTREES` - Auto-create missing worktrees

### Worktree Lifecycle

1. **Creation**: `./lib/worktree-manager.sh create <phase> <task>`
2. **Validation**: Automatic through hook system
3. **Tracking**: Activity monitored via post-tool-use tracker
4. **Merge**: `./lib/worktree-manager.sh merge <worktree-name>`
5. **Cleanup**: `./lib/worktree-manager.sh cleanup <worktree-name>`

### Security Features

- Input validation and sanitization
- Timeout protection for all operations
- Audit logging for all hook activities
- File path validation and traversal protection
- JSON schema validation for state files

## Troubleshooting

- Check audit logs at `/tmp/claude-pipeline-audit.log`
- Verify worktree state at `./config/worktree-state.json`
- Use `./hooks/worktree-enforcer.sh status` for current status
- Run `./lib/worktree-manager.sh list` to see all worktrees