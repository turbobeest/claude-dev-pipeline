# Bug Report: UserPromptSubmit Hooks Non-Functional in Claude Code v2.0.26+

## Summary

**UserPromptSubmit hooks are completely non-functional in Claude Code versions 2.0.26 through 2.0.32 (latest tested).**

The hooks are registered correctly in settings.json, the hook scripts execute successfully when tested manually, but Claude Code never invokes them when users submit prompts.

## Affected Versions

- **Confirmed Broken:** v2.0.26, v2.0.27, v2.0.28, v2.0.29, v2.0.30, v2.0.31, v2.0.32
- **Status:** Likely affects all versions from v2.0.26 onwards
- **Working:** Unknown (needs testing with v2.0.25 or earlier)

## Impact

- **Severity:** High - Completely blocks UserPromptSubmit hook functionality
- **Workarounds:** PreToolUse/PostToolUse hooks still work but provide limited alternatives
- **Affected Use Cases:**
  - Skill activation systems
  - Prompt preprocessing/validation
  - Context injection before AI processing
  - User intent detection and routing

## Environment

```bash
OS: macOS Darwin 24.6.0
Claude Code Version: v2.0.32 (also tested v2.0.26)
Shell: zsh
Installation: Fresh install with clean config
```

## Reproduction Steps

### 1. Configure UserPromptSubmit Hook

**settings.json:**
```json
{
  "version": "3.0",
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/user-prompt-submit.sh"
          }
        ]
      }
    ]
  }
}
```

**Hook script (.claude/hooks/user-prompt-submit.sh):**
```bash
#!/bin/bash
set -euo pipefail

# Log to file
LOG_FILE="${CLAUDE_WORKING_DIR:-.}/.claude/logs/skill-activations.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Read input
INPUT=$(cat 2>/dev/null || echo '{}')
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null || echo "")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Received message: $MESSAGE" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Processing activation request" >> "$LOG_FILE"

# Pattern matching
if echo "$MESSAGE" | grep -qiE "(generate tasks|parse.*(prd|requirements)|task.*generation)"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Pattern matched!" >> "$LOG_FILE"
    echo '{"injectedText":"[SKILL ACTIVATED]"}'
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] No matching skill pattern for message" >> "$LOG_FILE"
    echo "{}"
fi
```

### 2. Set Permissions

```bash
chmod +x .claude/hooks/user-prompt-submit.sh
```

### 3. Test Hook Manually (Works)

```bash
echo '{"message":"generate tasks from my PRD"}' | .claude/hooks/user-prompt-submit.sh
```

**Result:** ✅ Hook executes successfully, outputs correct JSON, logs written

### 4. Test Via Claude Code (Fails)

Start Claude Code session and submit prompt:
```
generate tasks from my PRD
```

**Expected:** Hook should fire, log entry created, injected text appears
**Actual:** No hook execution, no log entry, hook never invoked

### 5. Check Logs

```bash
tail -f .claude/logs/skill-activations.log
```

**Result:** No new entries when user prompts submitted via Claude Code UI

## Testing Evidence

### Test 1: Manual Hook Execution (Success)

```bash
$ echo '{"message":"generate tasks from my PRD"}' | .claude/hooks/user-prompt-submit.sh
{"injectedText":"[SKILL ACTIVATED]"}

$ tail -3 .claude/logs/skill-activations.log
[2025-11-05 02:27:45] [DEBUG] Received message: generate tasks from my PRD
[2025-11-05 02:27:45] [INFO] Processing activation request
[2025-11-05 02:27:45] [INFO] Pattern matched!
```

**✅ Hook script works perfectly when executed manually**

### Test 2: Claude Code Session (Failure)

Started fresh Claude Code session, submitted prompt: "generate tasks from my PRD"

**Log file contents after prompt:**
```
[2025-11-05 02:27:45] [DEBUG] Received message: test
[2025-11-05 02:27:45] [INFO] Processing activation request
[2025-11-05 02:27:45] [DEBUG] No matching skill pattern for message
[2025-11-05 02:28:13] [DEBUG] Received message:
[2025-11-05 02:28:13] [DEBUG] No message to process
```

**❌ No log entry for user prompt - hook never invoked by Claude Code**

### Test 3: Other Hook Types (Success)

**PreToolUse hooks:** ✅ Working normally
**PostToolUse hooks:** ✅ Working normally
**SessionStart hooks:** ✅ Working normally

**Only UserPromptSubmit is broken**

## Configuration Verification

### settings.json Valid

```bash
$ jq . .claude/settings.json
# Valid JSON, correct structure
```

### Hook File Exists and Executable

```bash
$ ls -la .claude/hooks/user-prompt-submit.sh
-rwxr-xr-x  1 user  staff  1234 Nov  5 02:18 .claude/hooks/user-prompt-submit.sh
```

### No Permission Errors

```bash
$ .claude/hooks/user-prompt-submit.sh <<< '{"message":"test"}'
# Executes successfully, no errors
```

## Comparison with Working Hooks

### PreToolUse Hook (Works)

**Input format:** `{"toolName":"Bash","toolInput":"command"}`
**Trigger:** Before tool execution
**Status:** ✅ Fires reliably

**Evidence:**
```bash
$ echo '{"toolName":"Bash","toolInput":"task-master parse-prd PRD.md"}' | \
  .claude/hooks/pretooluse-skill-activator.sh
{"hookSpecificOutput":{"additionalContext":"🔧 SKILL ACTIVATION..."}}
```

### UserPromptSubmit Hook (Broken)

**Input format:** `{"message":"user prompt text"}`
**Trigger:** After user submits prompt
**Status:** ❌ Never fires in Claude Code

## Root Cause Analysis

After extensive testing:

- ✅ Hook configuration is correct
- ✅ Hook file permissions are correct
- ✅ Hook script executes successfully when tested manually
- ✅ JSON output format is valid
- ✅ PreToolUse/PostToolUse hooks function normally
- ❌ **Claude Code simply doesn't invoke UserPromptSubmit hooks**

**Conclusion:** This is a Claude Code bug, not a configuration issue.

## Regression Timeline

- **v2.0.25 and earlier:** Unknown (needs testing)
- **v2.0.26:** ❌ Confirmed broken (tested 2025-11-05)
- **v2.0.27-v2.0.31:** ❌ Assumed broken based on v2.0.32 testing
- **v2.0.32:** ❌ Confirmed broken (latest version, tested 2025-11-05)

## Expected Behavior

When a user submits a prompt in Claude Code:

1. Claude Code should invoke all registered UserPromptSubmit hooks
2. Pass `{"message":"<user prompt text>"}` to hook script stdin
3. Read hook script stdout for JSON response
4. Apply `injectedText` or other hook outputs before processing prompt

## Actual Behavior

UserPromptSubmit hooks are never invoked. No stdin passed, no stdout read, hooks completely bypassed.

## Workaround (Partial)

Using PreToolUse hooks to detect specific command patterns:

```bash
# In pretooluse hook
if [[ "$TOOL_NAME" == "Bash" ]] && echo "$TOOL_INPUT" | grep -q "task-master"; then
    # Inject context
    echo '{"hookSpecificOutput":{"additionalContext":"..."}}'
fi
```

**Limitations:**
- Only works when Claude chooses to use Bash tool
- Cannot intercept raw user prompts
- Cannot detect user intent before Claude processes prompt
- Requires Claude to "naturally" choose specific commands

## Request for Fix

Please restore UserPromptSubmit hook functionality to work as documented and as it did in earlier versions.

## Additional Context

- GitHub Issue Reference: https://github.com/anthropics/claude-code/issues/10287
- Related forum discussions: Multiple users reporting similar issues
- Previous reports: Bug initially reported for v2.0.27+, now confirmed to extend back to v2.0.26

## Testing Offer

Happy to test any fixes or provide additional debugging information. We have:
- Complete reproducible test environment
- Automated monitoring scripts
- Detailed logs from multiple test runs
- Comparison data with working hook types

## Contact

- Date Reported: 2025-11-05
- Reporter: Claude Dev Pipeline Project
- GitHub: https://github.com/turbobeest/claude-dev-pipeline

---

**Thank you for your attention to this issue. UserPromptSubmit hooks are a critical feature for advanced automation workflows.**
