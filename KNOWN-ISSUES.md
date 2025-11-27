# Known Issues

## ✅ RESOLVED: UserPromptSubmit Hooks (Fixed in Claude Code v2.0.55+)

### Issue Description

**Claude Code versions 2.0.26 through 2.0.32 had a critical bug where UserPromptSubmit hooks were non-functional.**

- **Affected Versions:** v2.0.26 - v2.0.32
- **Fixed In:** v2.0.55+
- **Status:** ✅ RESOLVED
- **GitHub Issue:** https://github.com/anthropics/claude-code/issues/10287

### Resolution

As of Claude Code v2.0.55, all hook types are working correctly:

- ✅ UserPromptSubmit hooks execute properly
- ✅ PreToolUse hooks work
- ✅ PostToolUse hooks work

The pipeline settings have been updated (v3.2) to re-enable automatic hook-based phase transitions.

### Previous Workarounds (No Longer Required)

The slash commands (`/parse-prd`, `/generate-specs`, etc.) remain available as fallback but are no longer the primary activation method.

---

## ✅ RESOLVED: Bash 3.2 Compatibility

### Issue Description

**macOS ships with Bash 3.2, but `profiler.sh` used Bash 4+ features (`declare -A` associative arrays).**

This caused PostToolUse hooks to fail with exit code 2 on macOS.

### Resolution

`lib/profiler.sh` now checks the Bash version and gracefully disables profiling on Bash < 4:

```bash
BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"
if [[ "$BASH_VERSION_MAJOR" -lt 4 ]]; then
    PROFILER_ENABLED="false"
    PROFILER_BASH3_MODE="true"
fi
```

All hooks now work on both macOS (Bash 3.2) and Linux (Bash 4+).

---

## ✅ RESOLVED: OpenSpec Package Name

### Issue Description

The prerequisites installer referenced `@anthropic/openspec` which doesn't exist on npm.

### Resolution

Corrected to `@fission-ai/openspec@latest` in:
- `lib/prerequisites-installer.sh`
- `install.sh`

---

## Version Compatibility

| Claude Code Version | UserPromptSubmit | PreToolUse | PostToolUse | Status |
|-------------------|------------------|------------|-------------|---------|
| v2.0.25 and earlier | ❓ Unknown | ✅ Working | ✅ Working | Not tested |
| v2.0.26 - v2.0.32 | ❌ Broken | ✅ Working | ✅ Working | Use slash commands |
| v2.0.33 - v2.0.54 | ❓ Unknown | ✅ Working | ✅ Working | Likely fixed |
| **v2.0.55+** | **✅ Working** | **✅ Working** | **✅ Working** | **Full hook support** |

---

## Remaining Notes

### Slash Commands Still Available

Even with hooks working, slash commands remain as reliable fallback:

- `/parse-prd` - Phase 1: Task Decomposition
- `/generate-specs` - Phase 2: Specification Generation
- `/implement-tdd` - Phase 3: TDD Implementation
- `/validate-integration` - Phase 4: Integration Testing
- `/validate-e2e` - Phase 5: E2E Validation
- `/deploy` - Phase 6: Production Deployment

### Profiler Disabled on Bash 3.2

On macOS with default Bash 3.2, the profiler is automatically disabled. This is cosmetic - all other functionality works normally. To enable profiling, use Bash 4+:

```bash
brew install bash
/opt/homebrew/bin/bash your-script.sh
```

---

**Last Updated:** 2025-11-27
