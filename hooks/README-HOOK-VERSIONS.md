# Hook Versions - Usage Guide

## Overview

This directory contains two versions of each hook for different use cases.

## Hook Versions

### Full-Featured Hooks (Default)

**Files:**
- `skill-activation-prompt.sh`
- `post-tool-use-tracker.sh`

**Features:**
- Comprehensive validation
- Advanced workflow tracking
- State management integration
- Performance profiling
- Audit logging
- Security checks

**Use When:**
- All lib dependencies are available
- Full pipeline features needed
- Working in the pipeline development repo

**Dependencies:**
- `lib/cache.sh`
- `lib/json-utils.sh`
- `lib/lazy-loader.sh`
- `lib/profiler.sh`
- `lib/state-manager.sh`
- `lib/logger.sh`

### Simplified Hooks (Fault-Tolerant)

**Files:**
- `skill-activation-prompt-simple.sh`
- `post-tool-use-tracker-simple.sh`

**Features:**
- Minimal dependencies
- Graceful degradation
- Never fails/errors
- Simple pattern matching
- Optional jq usage (works without it)

**Use When:**
- Hook errors occurring
- Missing library dependencies
- Quick setup needed
- Testing/debugging

**Dependencies:**
- None (jq optional but not required)

## Switching Between Versions

### Option 1: Copy Simple Versions (Recommended for Hook Errors)

```bash
# In your project with hook errors:
cd /path/to/your/project/.claude/hooks

# Backup existing hooks
cp skill-activation-prompt.sh skill-activation-prompt.sh.backup
cp post-tool-use-tracker.sh post-tool-use-tracker.sh.backup

# Copy simple versions from pipeline repo
cp /path/to/claude-dev-pipeline/hooks/skill-activation-prompt-simple.sh skill-activation-prompt.sh
cp /path/to/claude-dev-pipeline/hooks/post-tool-use-tracker-simple.sh post-tool-use-tracker.sh
```

### Option 2: Fix Dependencies

```bash
# Copy all lib files to fix dependency issues
cp -r /path/to/claude-dev-pipeline/lib/* /path/to/your/project/.claude/lib/
```

## Testing Hooks

### Test UserPromptSubmit Hook

```bash
cd /path/to/your/project
echo '{"message":"I completed my PRD, begin development"}' | .claude/hooks/skill-activation-prompt.sh
```

**Expected output (simple version):**
```json
{"injectedText":"[ACTIVATE:PRD_TO_TASKS_V1]"}
```

### Test PostToolUse Hook

```bash
cd /path/to/your/project
echo '{"toolName":"Read","result":"test"}' | .claude/hooks/post-tool-use-tracker.sh
```

**Expected output (simple version):**
```json
{}
```

## Troubleshooting

### Hooks Still Erroring

1. **Check permissions:**
   ```bash
   chmod +x .claude/hooks/*.sh
   ```

2. **Verify bash is available:**
   ```bash
   which bash
   # Should output: /bin/bash or /usr/bin/bash
   ```

3. **Test hooks manually:**
   ```bash
   bash -x .claude/hooks/skill-activation-prompt.sh <<< '{"message":"test"}'
   ```

### Temporary Disable Hooks

If hooks continue to cause issues, you can temporarily disable them:

```bash
# Rename hooks to disable
cd .claude/hooks
mv skill-activation-prompt.sh skill-activation-prompt.sh.disabled
mv post-tool-use-tracker.sh post-tool-use-tracker.sh.disabled
```

**Note:** Disabling hooks means:
- No automatic skill activation
- No workflow tracking
- You'll need to manually specify activation codes

## Activation Codes (Manual Use)

If hooks are disabled, use these codes in your Claude messages:

| Skill | Activation Code |
|-------|----------------|
| PRD-to-Tasks | `[ACTIVATE:PRD_TO_TASKS_V1]` |
| Task Decomposer | `[ACTIVATE:TASK_DECOMPOSER_V1]` |
| Spec Generator | `[ACTIVATE:SPEC_GEN_V1]` |
| TDD Implementer | `[ACTIVATE:TDD_IMPLEMENTER_V1]` |

**Example:**
```
[ACTIVATE:PRD_TO_TASKS_V1]
Please generate tasks from my PRD at docs/PRD.md
```

## When to Use Each Version

| Scenario | Recommended Version |
|----------|-------------------|
| New installation with all deps | Full-featured |
| Hook errors occurring | Simplified |
| Missing lib/ directory | Simplified |
| Testing/quick setup | Simplified |
| Production use with monitoring | Full-featured |
| Development/debugging | Simplified |
| CI/CD pipelines | Simplified |

## Support

For issues with hooks:
1. Check [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
2. Try simplified versions
3. Test manually with example JSON
4. Check audit log: `/tmp/claude-pipeline-audit.log`
5. Enable debug mode: `export CLAUDE_DEBUG=true`
