# Claude Dev Pipeline - Troubleshooting Guide

## Overview

This comprehensive troubleshooting guide covers common issues, error codes, debugging techniques, and recovery procedures for the Claude Dev Pipeline system.

## Table of Contents

1. [Common Issues and Solutions](#common-issues-and-solutions)
2. [Error Code Reference](#error-code-reference)
3. [Debugging Techniques](#debugging-techniques)
4. [Log Analysis Guide](#log-analysis-guide)
5. [Performance Troubleshooting](#performance-troubleshooting)
6. [Recovery Procedures](#recovery-procedures)
7. [Diagnostic Tools](#diagnostic-tools)
8. [Emergency Recovery](#emergency-recovery)

## Common Issues and Solutions

### Installation Issues

#### Issue: Permission Denied During Installation

**Symptoms:**
```bash
chmod: .claude/hooks/*.sh: Permission denied
./install-pipeline.sh: Permission denied
```

**Diagnosis:**
```bash
# Check current permissions
ls -la .claude/hooks/
whoami
id

# Check file ownership
ls -la $(dirname $(pwd))
```

**Solutions:**

1. **Fix ownership:**
```bash
sudo chown -R $(whoami):$(id -gn) .claude/
chmod -R 755 .claude/
chmod +x .claude/hooks/*.sh
```

2. **Use sudo for installation (last resort):**
```bash
sudo ./install-pipeline.sh --global
sudo chown -R $(whoami):$(id -gn) ~/.claude/
```

3. **Install in user directory:**
```bash
./install-pipeline.sh --project --force
```

#### Issue: Missing Dependencies

**Symptoms:**
```bash
./install-pipeline.sh: line 123: jq: command not found
./install-pipeline.sh: line 156: git: command not found
```

**Solutions:**

```bash
# macOS (Homebrew)
brew install jq git

# Ubuntu/Debian
sudo apt update
sudo apt install jq git curl

# RHEL/CentOS/Fedora
sudo yum install jq git curl
# or
sudo dnf install jq git curl

# Manual jq installation
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
sudo mv jq-linux64 /usr/local/bin/jq
sudo chmod +x /usr/local/bin/jq
```

#### Issue: Claude Code Not Recognizing Skills

**Symptoms:**
```bash
claude --list-skills | grep PRD_TO_TASKS
# No output

echo "generate tasks" | claude
# No [ACTIVATE:...] codeword injection
```

**Diagnosis:**
```bash
# Check skill files
ls -la .claude/skills/*/SKILL.md
head -10 .claude/skills/prd-to-tasks/SKILL.md

# Check configuration
cat .claude/settings.json | jq '.hooks'
cat .claude/skill-rules.json | jq '.skills[0]'

# Test hook execution
echo "test message" | .claude/hooks/skill-activation-prompt.sh
```

**Solutions:**

1. **Verify SKILL.md format:**
```bash
# Each SKILL.md must start with YAML frontmatter
cat > .claude/skills/prd-to-tasks/SKILL.md << 'EOF'
---
activation_code: PRD_TO_TASKS_V1
phase: 1
prerequisites: []
outputs: 
  - tasks.json
description: |
  PRD to Tasks skill
---
# PRD-to-Tasks Skill
...
EOF
```

2. **Fix hook permissions:**
```bash
chmod +x .claude/hooks/*.sh
```

3. **Restart Claude Code:**
```bash
killall claude-code 2>/dev/null || true
claude --reload-skills
```

4. **Validate configuration:**
```bash
jq . .claude/settings.json >/dev/null && echo "settings.json valid"
jq . .claude/skill-rules.json >/dev/null && echo "skill-rules.json valid"
```

### Hook Execution Issues

#### Issue: Hooks Not Running

**Symptoms:**
```bash
echo "generate tasks from PRD" | claude
# No codeword injection visible
# No [ACTIVATE:...] in output
```

**Diagnosis:**
```bash
# Check hook configuration
cat .claude/settings.json | jq '.hooks'

# Check hook permissions
ls -la .claude/hooks/
file .claude/hooks/*.sh

# Test hook directly
echo "generate tasks" | .claude/hooks/skill-activation-prompt.sh

# Check for errors
tail -50 .claude/logs/pipeline.log
```

**Solutions:**

1. **Enable hooks:**
```bash
jq '.hooks.UserPromptSubmit.enabled = true' .claude/settings.json > temp.json
mv temp.json .claude/settings.json
```

2. **Fix script permissions:**
```bash
chmod +x .claude/hooks/*.sh
```

3. **Check shebang lines:**
```bash
head -1 .claude/hooks/*.sh
# Should all be: #!/bin/bash
```

4. **Test with debug mode:**
```bash
DEBUG_MODE=true echo "generate tasks" | .claude/hooks/skill-activation-prompt.sh
```

#### Issue: Hook Execution Timeout

**Symptoms:**
```bash
[ERROR] Hook execution timeout: skill-activation-prompt.sh
[WARN] Falling back to original message
```

**Diagnosis:**
```bash
# Check hook timeout settings
cat .claude/settings.json | jq '.hooks.UserPromptSubmit.timeout'

# Test hook performance
time echo "test" | .claude/hooks/skill-activation-prompt.sh

# Check for infinite loops
strace -c echo "test" | .claude/hooks/skill-activation-prompt.sh
```

**Solutions:**

1. **Increase timeout:**
```bash
jq '.hooks.UserPromptSubmit.timeout = 10000' .claude/settings.json > temp.json
mv temp.json .claude/settings.json
```

2. **Debug slow patterns:**
```bash
# Add timing to hook script
sed -i 's/analyze_patterns/time analyze_patterns/' .claude/hooks/skill-activation-prompt.sh
```

3. **Simplify pattern matching:**
```bash
# Reduce pattern complexity in skill-rules.json
jq '.skills[0].trigger_conditions.user_patterns = ["generate tasks"]' .claude/skill-rules.json > temp.json
mv temp.json .claude/skill-rules.json
```

### State Management Issues

#### Issue: State File Corruption

**Symptoms:**
```bash
./lib/state-manager.sh read
# parse error: Invalid JSON at line 15, column 8

cat .claude/.workflow-state.json
# Malformed JSON or empty file
```

**Diagnosis:**
```bash
# Check file integrity
file .claude/.workflow-state.json
wc -l .claude/.workflow-state.json

# Validate JSON
jq . .claude/.workflow-state.json

# Check for backup files
ls -la .claude/.state-backups/
```

**Solutions:**

1. **Restore from backup:**
```bash
./lib/state-manager.sh restore
# or manually:
cp .claude/.state-backups/$(ls -t .claude/.state-backups/ | head -1) .claude/.workflow-state.json
```

2. **Initialize clean state:**
```bash
./lib/state-manager.sh init --force
```

3. **Manual recovery:**
```bash
# Use template
cp config/workflow-state.template.json .claude/.workflow-state.json

# Or create minimal state
cat > .claude/.workflow-state.json << 'EOF'
{
  "version": "1.0",
  "pipeline_id": "$(uuidgen)",
  "current_phase": 0,
  "phase_status": "init",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

#### Issue: State Lock Timeout

**Symptoms:**
```bash
./lib/state-manager.sh write '{"test": true}'
# [ERROR] Failed to acquire state lock within 30 seconds
# [ERROR] State may be locked by another process
```

**Diagnosis:**
```bash
# Check for lock files
ls -la .claude/.locks/
cat .claude/.locks/state.lock 2>/dev/null

# Check for stale processes
ps aux | grep claude

# Check lock age
stat .claude/.locks/state.lock
```

**Solutions:**

1. **Clean stale locks:**
```bash
./lib/lock-manager.sh cleanup
# or manually:
find .claude/.locks -name "*.lock" -mmin +30 -delete
```

2. **Force release specific lock:**
```bash
./lib/lock-manager.sh force-release state
```

3. **Kill hanging processes:**
```bash
pkill -f "state-manager.sh"
pkill -f "claude.*pipeline"
```

4. **Nuclear option - remove all locks:**
```bash
rm -f .claude/.locks/*.lock
```

### Worktree Issues

#### Issue: Worktree Creation Fails

**Symptoms:**
```bash
./lib/worktree-manager.sh create 1 1
# fatal: 'phase-1-task-1' already exists
# [ERROR] Failed to create worktree
```

**Diagnosis:**
```bash
# Check existing worktrees
git worktree list
ls -la ./worktrees/

# Check for stale references
cat .git/worktrees/*/HEAD 2>/dev/null

# Check worktree state
cat config/worktree-state.json
```

**Solutions:**

1. **Clean stale worktrees:**
```bash
git worktree prune
./lib/worktree-manager.sh cleanup-all --force
```

2. **Remove specific worktree:**
```bash
./lib/worktree-manager.sh cleanup phase-1-task-1 --force
rm -rf ./worktrees/phase-1-task-1
```

3. **Fix worktree state:**
```bash
./lib/worktree-manager.sh repair
```

4. **Nuclear reset:**
```bash
rm -rf ./worktrees/*
rm -f config/worktree-state.json
git worktree prune
./lib/worktree-manager.sh init
```

#### Issue: Merge Conflicts

**Symptoms:**
```bash
./lib/worktree-manager.sh merge phase-1-task-1
# Auto-merging tasks.json
# CONFLICT (content): Merge conflict in tasks.json
# Automatic merge failed
```

**Resolution Steps:**

1. **Identify conflicts:**
```bash
cd ./worktrees/phase-1-task-1
git status
git diff
```

2. **Resolve manually:**
```bash
# Edit conflicted files
nano tasks.json

# Look for conflict markers:
# <<<<<<< HEAD
# original content
# =======
# worktree content
# >>>>>>> phase-1-task-1

# Remove markers, keep desired content
```

3. **Complete merge:**
```bash
git add tasks.json
git commit -m "resolve: merge conflict in tasks.json"
cd ../..
./lib/worktree-manager.sh merge phase-1-task-1
```

4. **Abort if needed:**
```bash
cd ./worktrees/phase-1-task-1
git merge --abort
cd ../..
```

### Skill Activation Issues

#### Issue: Skills Not Activating Despite Codewords

**Symptoms:**
```bash
echo "[ACTIVATE:PRD_TO_TASKS_V1] Generate tasks" | claude
# Claude doesn't recognize the skill
# No skill execution occurs
```

**Diagnosis:**
```bash
# Check if skill exists
find .claude -name "SKILL.md" -exec grep -l "PRD_TO_TASKS_V1" {} \;

# Check Claude's skill list
claude --list-skills | grep -i prd

# Check skill syntax
head -10 .claude/skills/prd-to-tasks/SKILL.md
```

**Solutions:**

1. **Verify skill metadata:**
```bash
# Check YAML frontmatter format
cat .claude/skills/prd-to-tasks/SKILL.md | head -10
# Must start with --- and contain activation_code
```

2. **Reload skills:**
```bash
claude --reload-skills
```

3. **Check skill path:**
```bash
# Skills must be in correct directory structure
ls .claude/skills/prd-to-tasks/SKILL.md
```

4. **Test skill directly:**
```bash
# Manual activation test
cd .claude/skills/prd-to-tasks
claude --activate PRD_TO_TASKS_V1 "test message"
```

## Error Code Reference

### State Manager Error Codes

| Code | Name | Description | Resolution |
|------|------|-------------|------------|
| 0 | STATE_SUCCESS | Operation completed successfully | None needed |
| 1 | STATE_ERROR_LOCK | Failed to acquire lock | Clean stale locks, retry |
| 2 | STATE_ERROR_VALIDATION | State validation failed | Restore from backup |
| 3 | STATE_ERROR_CORRUPTION | State file corrupted | Use recovery procedure |
| 4 | STATE_ERROR_PERMISSION | Permission denied | Fix file permissions |
| 5 | STATE_ERROR_SCHEMA | Invalid state schema | Migrate or reinitialize |

### Worktree Manager Error Codes

| Code | Name | Description | Resolution |
|------|------|-------------|------------|
| 0 | WORKTREE_SUCCESS | Operation completed successfully | None needed |
| 1 | WORKTREE_ERROR_EXISTS | Worktree already exists | Cleanup existing, retry |
| 2 | WORKTREE_ERROR_NOT_FOUND | Worktree not found | Check name, create if needed |
| 3 | WORKTREE_ERROR_MERGE_CONFLICT | Merge conflicts detected | Resolve conflicts manually |
| 4 | WORKTREE_ERROR_VALIDATION | Isolation validation failed | Fix violations, retry |
| 5 | WORKTREE_ERROR_GIT | Git operation failed | Check git status, repair |

### Hook Error Codes

| Code | Name | Description | Resolution |
|------|------|-------------|------------|
| 0 | HOOK_SUCCESS | Hook executed successfully | None needed |
| 1 | HOOK_ERROR_TIMEOUT | Hook execution timeout | Increase timeout, debug |
| 2 | HOOK_ERROR_SCRIPT | Script execution error | Check script syntax |
| 3 | HOOK_ERROR_PERMISSION | Script not executable | Fix permissions |
| 4 | HOOK_ERROR_PATTERN | Pattern matching failed | Check skill rules |
| 5 | HOOK_ERROR_CONFIG | Configuration error | Validate config files |

## Debugging Techniques

### Enable Debug Mode

```bash
# Global debug mode
export DEBUG_MODE=true
export CLAUDE_LOG_LEVEL=debug

# Component-specific debugging
export SKILL_ACTIVATION_DEBUG=true
export WORKTREE_DEBUG=true
export STATE_MANAGER_DEBUG=true

# Hook debugging
export HOOK_DEBUG=true
echo "test message" | .claude/hooks/skill-activation-prompt.sh
```

### Trace Execution

```bash
# Trace hook execution
bash -x .claude/hooks/skill-activation-prompt.sh <<< "generate tasks"

# Trace state operations
bash -x ./lib/state-manager.sh read

# Trace worktree operations
bash -x ./lib/worktree-manager.sh create 1 1
```

### Monitor File Changes

```bash
# Watch for file changes during execution
fswatch -o .claude/ | while read; do
    echo "$(date): Files changed in .claude/"
    find .claude -name "*.json" -mmin -1
done

# Monitor specific files
tail -f .claude/.workflow-state.json &
tail -f .claude/logs/pipeline.log &
```

### Network Debugging

```bash
# Check GitHub connectivity
curl -I https://api.github.com/rate_limit

# Test with proxy
export HTTP_PROXY=http://proxy:8080
export HTTPS_PROXY=http://proxy:8080
./install-pipeline.sh --github-org YOUR_ORG
```

## Log Analysis Guide

### Log Levels and Formats

```bash
# Set appropriate log level
export CLAUDE_LOG_LEVEL=debug  # debug|info|warn|error|fatal

# JSON format for structured analysis
export CLAUDE_LOG_FORMAT=json

# Analyze logs
tail -100 .claude/logs/pipeline.log | jq '.level' | sort | uniq -c
```

### Common Log Patterns

#### Successful Skill Activation

```
2023-11-01T15:30:45.123Z [INFO] hook/skill-activation: Pattern matched 'generate tasks'
2023-11-01T15:30:45.125Z [INFO] hook/skill-activation: Injecting activation code: PRD_TO_TASKS_V1
2023-11-01T15:30:45.130Z [INFO] skill/prd-to-tasks: Skill activated successfully
```

#### State Update Pattern

```
2023-11-01T15:30:50.100Z [INFO] state-manager/lock: Acquired lock for state update
2023-11-01T15:30:50.105Z [INFO] state-manager/write: Updating phase from 1 to 2
2023-11-01T15:30:50.110Z [INFO] state-manager/backup: Created backup: state-20231101-153050.json
2023-11-01T15:30:50.115Z [INFO] state-manager/unlock: Released state lock
```

#### Error Pattern

```
2023-11-01T15:30:55.200Z [ERROR] worktree-manager/create: Failed to create worktree phase-1-task-1
2023-11-01T15:30:55.205Z [ERROR] worktree-manager/create: Git error: fatal: 'phase-1-task-1' already exists
2023-11-01T15:30:55.210Z [WARN] error-recovery/auto: Attempting automatic recovery
2023-11-01T15:30:55.220Z [INFO] error-recovery/auto: Cleaning stale worktree references
```

### Log Analysis Commands

```bash
# Error analysis
grep -E "\[ERROR\]|\[FATAL\]" .claude/logs/pipeline.log | tail -20

# Performance analysis
grep -E "duration_ms" .claude/logs/pipeline.log | \
  jq -r '.metadata.duration_ms' | \
  awk '{sum+=$1; count++} END {print "Average:", sum/count "ms"}'

# Hook execution analysis
grep "hook/" .claude/logs/pipeline.log | \
  jq -r '.timestamp + " " + .event + " " + .message'

# State change tracking
grep "state-manager/write" .claude/logs/pipeline.log | \
  jq -r '.timestamp + " Phase: " + (.metadata.phase // "unknown" | tostring)'
```

## Performance Troubleshooting

### Identify Performance Bottlenecks

```bash
# Profile hook execution
time echo "generate tasks from PRD" | .claude/hooks/skill-activation-prompt.sh

# Profile state operations
time ./lib/state-manager.sh read
time ./lib/state-manager.sh write '{"test": true}' "test update"

# Profile worktree operations
time ./lib/worktree-manager.sh create 1 1
time ./lib/worktree-manager.sh cleanup phase-1-task-1
```

### System Resource Monitoring

```bash
# Monitor CPU usage
top -p $(pgrep -f claude)

# Monitor memory usage
ps -o pid,ppid,cmd,%mem,%cpu --sort=-%mem | grep claude

# Monitor disk I/O
iotop -p $(pgrep -f claude)

# Monitor disk space
df -h .
du -sh .claude/
```

### Optimization Strategies

#### Reduce Pattern Complexity

```bash
# Simplify skill rules
jq '.skills[].trigger_conditions.user_patterns |= .[0:3]' .claude/skill-rules.json > temp.json
mv temp.json .claude/skill-rules.json
```

#### Optimize State Operations

```bash
# Increase backup retention interval
export STATE_BACKUP_INTERVAL=300  # 5 minutes instead of every change

# Use memory caching
export STATE_CACHE_ENABLED=true
export STATE_CACHE_TTL=60
```

#### Clean Up Resources

```bash
# Clean old logs
find .claude/logs -name "*.log" -mtime +7 -delete

# Clean old backups
find .claude/.state-backups -name "*.json" -mtime +7 -delete

# Clean temporary files
find /tmp -name "claude-*" -mtime +1 -delete
```

## Recovery Procedures

### Emergency Recovery Checklist

1. **Stop all pipeline processes:**
```bash
pkill -f "claude.*pipeline"
pkill -f "state-manager"
pkill -f "worktree-manager"
```

2. **Backup current state:**
```bash
mkdir -p emergency-backup-$(date +%Y%m%d-%H%M%S)
cp -r .claude/ emergency-backup-$(date +%Y%m%d-%H%M%S)/
```

3. **Clean locks:**
```bash
rm -f .claude/.locks/*.lock
```

4. **Validate critical files:**
```bash
jq . .claude/settings.json >/dev/null || echo "CORRUPT: settings.json"
jq . .claude/skill-rules.json >/dev/null || echo "CORRUPT: skill-rules.json"
jq . .claude/.workflow-state.json >/dev/null || echo "CORRUPT: workflow-state.json"
```

5. **Restore from backup if needed:**
```bash
./lib/state-manager.sh restore
./lib/worktree-manager.sh repair
```

### Specific Recovery Scenarios

#### Scenario: Complete System Corruption

```bash
# 1. Save current state
tar -czf corruption-backup-$(date +%Y%m%d-%H%M%S).tar.gz .claude/

# 2. Nuclear reset
rm -rf .claude/

# 3. Reinstall
./install-pipeline.sh --force

# 4. Restore data (if possible)
tar -xzf corruption-backup-*.tar.gz
cp -r .claude/.state-backups/ .claude/ 2>/dev/null || true
./lib/state-manager.sh restore
```

#### Scenario: Git Repository Corruption

```bash
# 1. Check git status
git status
git fsck

# 2. Clean worktrees
git worktree prune
rm -rf ./worktrees/*

# 3. Reset to clean state
git reset --hard HEAD
git clean -fd

# 4. Reinitialize pipeline
./lib/worktree-manager.sh init
./lib/state-manager.sh init
```

#### Scenario: Partial File Corruption

```bash
# 1. Identify corrupted files
find .claude -name "*.json" -exec sh -c 'jq . "$1" >/dev/null || echo "CORRUPT: $1"' _ {} \;

# 2. Restore specific files
cp .claude/.state-backups/$(ls -t .claude/.state-backups/ | head -1) .claude/.workflow-state.json
cp config/settings.json .claude/settings.json
cp config/skill-rules.json .claude/skill-rules.json

# 3. Validate restoration
./health-check.sh
```

## Diagnostic Tools

### Built-in Health Check

```bash
# Run comprehensive health check
./health-check.sh

# Component-specific checks
./health-check.sh --component state-manager
./health-check.sh --component worktree-manager
./health-check.sh --component hooks
```

### Custom Diagnostic Scripts

#### System Status Script

```bash
#!/bin/bash
# diagnostic.sh - Comprehensive system status

echo "=== Claude Dev Pipeline Diagnostics ==="
echo "Timestamp: $(date)"
echo

echo "--- Environment ---"
echo "PWD: $(pwd)"
echo "USER: $(whoami)"
echo "Shell: $SHELL"
echo "Platform: $(uname -s)"
echo

echo "--- Dependencies ---"
which git && git --version
which jq && jq --version
which claude && claude --version 2>/dev/null || echo "Claude Code not found"
echo

echo "--- File Structure ---"
ls -la .claude/ 2>/dev/null || echo "No .claude directory found"
echo

echo "--- Configuration ---"
jq . .claude/settings.json 2>/dev/null | head -10 || echo "No valid settings.json"
echo

echo "--- Current State ---"
./lib/state-manager.sh read 2>/dev/null | jq . || echo "No valid state"
echo

echo "--- Active Processes ---"
ps aux | grep -E "(claude|pipeline)" | grep -v grep
echo

echo "--- Locks ---"
ls -la .claude/.locks/ 2>/dev/null || echo "No lock directory"
echo

echo "--- Recent Logs ---"
tail -10 .claude/logs/pipeline.log 2>/dev/null || echo "No pipeline log"
```

#### Performance Monitor

```bash
#!/bin/bash
# performance-monitor.sh - Monitor pipeline performance

echo "=== Performance Monitoring ==="

# Test hook performance
echo "Testing hook performance..."
time echo "test message" | .claude/hooks/skill-activation-prompt.sh >/dev/null 2>&1
echo

# Test state operations
echo "Testing state operations..."
time ./lib/state-manager.sh read >/dev/null 2>&1
echo

# Test worktree operations
echo "Testing worktree list..."
time ./lib/worktree-manager.sh list >/dev/null 2>&1
echo

# Resource usage
echo "Resource usage:"
du -sh .claude/
echo "Active processes:"
ps -o pid,cmd,%cpu,%mem | grep claude | grep -v grep
```

### Validation Scripts

#### Configuration Validator

```bash
#!/bin/bash
# validate-config.sh - Validate all configuration files

errors=0

echo "Validating configuration files..."

# Validate JSON files
for file in .claude/settings.json .claude/skill-rules.json .claude/.workflow-state.json; do
    if [[ -f "$file" ]]; then
        if jq . "$file" >/dev/null 2>&1; then
            echo "✓ $file: Valid JSON"
        else
            echo "✗ $file: Invalid JSON"
            ((errors++))
        fi
    else
        echo "? $file: Not found"
    fi
done

# Validate skill files
for skill_dir in .claude/skills/*/; do
    skill_file="$skill_dir/SKILL.md"
    if [[ -f "$skill_file" ]]; then
        if head -1 "$skill_file" | grep -q "^---"; then
            echo "✓ $skill_file: Valid format"
        else
            echo "✗ $skill_file: Missing YAML frontmatter"
            ((errors++))
        fi
    fi
done

# Validate hook scripts
for hook in .claude/hooks/*.sh; do
    if [[ -x "$hook" ]]; then
        echo "✓ $hook: Executable"
    else
        echo "✗ $hook: Not executable"
        ((errors++))
    fi
done

echo
if [[ $errors -eq 0 ]]; then
    echo "All validations passed ✓"
    exit 0
else
    echo "$errors validation errors found ✗"
    exit 1
fi
```

## Emergency Recovery

### Last Resort Recovery

If all else fails, use this nuclear recovery procedure:

```bash
#!/bin/bash
# nuclear-recovery.sh - Complete system reset

echo "WARNING: This will completely reset the Claude Dev Pipeline"
read -p "Are you sure? (type 'RESET' to confirm): " confirm

if [[ "$confirm" != "RESET" ]]; then
    echo "Aborted"
    exit 1
fi

echo "Creating emergency backup..."
tar -czf emergency-backup-$(date +%Y%m%d-%H%M%S).tar.gz .claude/ .git/worktrees/ 2>/dev/null

echo "Stopping all processes..."
pkill -f claude
pkill -f pipeline

echo "Removing all pipeline files..."
rm -rf .claude/
rm -rf ./worktrees/
git worktree prune

echo "Cleaning git state..."
git reset --hard HEAD
git clean -fd

echo "Reinstalling pipeline..."
./install-pipeline.sh --force

echo "Initializing clean state..."
./lib/state-manager.sh init
./lib/worktree-manager.sh init

echo "Running health check..."
./health-check.sh

echo "Recovery complete. Previous state backed up to emergency-backup-*.tar.gz"
```

---

This troubleshooting guide should help resolve most issues encountered with the Claude Dev Pipeline. For issues not covered here, please check the GitHub issues or create a new issue with detailed error information.

**Next**: Continue to update the main [README.md](../README.md) with the new documentation structure.