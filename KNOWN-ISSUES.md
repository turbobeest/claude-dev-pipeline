# Known Issues

## 🐛 UserPromptSubmit Hooks Broken in Claude Code v2.0.26+

### Issue Description

**Claude Code versions 2.0.26 through 2.0.32 (and possibly later) have a critical bug where UserPromptSubmit hooks are completely non-functional.**

- **Affected Versions:** v2.0.26 - v2.0.32+ (tested and confirmed)
- **Status:** Reported to Anthropic
- **GitHub Issue:** https://github.com/anthropics/claude-code/issues/10287
- **Impact:** Skill activation via user prompts does not work
- **Discovery:** v2.0.26 testing confirmed bug extends earlier than initially reported

### Symptoms

1. UserPromptSubmit hooks are registered in settings.json but never execute
2. No hook activity appears in logs when users submit prompts
3. PreToolUse and PostToolUse hooks continue to work normally
4. Hook script works perfectly when tested manually

### Root Cause

This is a **Claude Code bug**, not a configuration issue. After extensive testing:

- ✅ Hook configuration is correct
- ✅ Hook file permissions are correct
- ✅ Hook script executes successfully when tested manually
- ✅ PreToolUse/PostToolUse hooks function normally
- ❌ Claude Code simply doesn't invoke UserPromptSubmit hooks in v2.0.26+

### Workaround (Currently Active)

This pipeline implements a **PreToolUse hook workaround**:

1. **Version Checker** (`claude-version-checker.sh`)
   - Runs on SessionStart
   - Alerts when you're running a broken version
   - **LOUDLY notifies** when a new version is available
   - Provides update instructions

2. **PreToolUse Skill Activator** (`pretooluse-skill-activator.sh`)
   - Detects `task-master parse-prd` commands
   - Injects skill activation context
   - Provides PRD size warnings
   - Less elegant than UserPromptSubmit but functional

3. **UserPromptSubmit Hook Preserved**
   - Kept in configuration for forward compatibility
   - Will automatically work when bug is fixed
   - No code changes needed once Claude Code is patched

### When Bug is Fixed

**You will see a LOUD notification** when:
1. Claude Code version is newer than v2.0.32
2. You start a new session
3. The version checker detects the update

**Then follow these steps:**

```bash
# 1. Verify the bug is fixed
# Check GitHub issue: https://github.com/anthropics/claude-code/issues/10287

# 2. Update this pipeline
cd /path/to/claude-dev-pipeline
git pull origin deploy

# 3. Reinstall in your project
./install.sh /path/to/your/project

# 4. Test UserPromptSubmit hooks
claude --permission-mode bypassPermissions
# Try: "generate tasks from my PRD"
# Check: tail -f .claude/logs/skill-activations.log
```

### Testing Hook Functionality

To verify hooks are working:

```bash
# Test UserPromptSubmit manually
cd /path/to/your/project
echo '{"message":"generate tasks from my PRD"}' | .claude/hooks/user-prompt-submit.sh

# Should output:
# - Pattern detection message
# - PRD location
# - Codeword: [ACTIVATE:PRD_TO_TASKS_V1]
# - JSON with injectedText field

# Check logs
tail -20 .claude/logs/skill-activations.log
# Should show pattern matching and activation
```

### Reporting Issues

If you discover:
- Bug is fixed in a new Claude Code version
- Workaround is causing problems
- Additional issues

**Update the pipeline** and file an issue with:
- Claude Code version (`claude --version`)
- Log output (`.claude/logs/skill-activations.log`)
- Expected vs actual behavior

---

## Other Known Issues

### PreToolUse/PostToolUse Hook Errors

**Status:** Under investigation

Some users see "PreToolUse hook error" or "PostToolUse hook returned blocking error" messages. These are logged by Claude Code but don't appear to break functionality.

**Impact:** Cosmetic - hooks still execute

**Workaround:** None needed currently

---

## Version Compatibility

| Claude Code Version | UserPromptSubmit | PreToolUse | PostToolUse | Status |
|-------------------|------------------|------------|-------------|---------|
| v2.0.25 and earlier | ❓ Unknown | ✅ Working | ✅ Working | Not tested - may work |
| v2.0.26 - v2.0.32 | ❌ Broken | ✅ Working | ✅ Working | Workaround active (tested) |
| v2.0.33+ | ❓ Unknown | ✅ Working | ✅ Working | **Test and report!** |

---

**Last Updated:** 2025-11-05
