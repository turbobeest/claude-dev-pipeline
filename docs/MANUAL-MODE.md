# Manual Mode - Explicit Phase Control

## Overview

**Manual Mode** disables automatic phase transitions and requires you to explicitly type a slash command to proceed to each phase. This gives you complete visibility and control over the pipeline.

## Why Manual Mode?

**Advantages:**
- ✅ **Never miss a phase transition** - Pipeline stops and waits for you
- ✅ **Review outputs before proceeding** - Check each phase's results
- ✅ **Full control** - Decide when to move to next phase
- ✅ **Very obvious indicators** - Large terminal banners show completion
- ✅ **Workaround for hook bugs** - Doesn't rely on UserPromptSubmit hooks

**When to use:**
- When you want to review each phase's output before proceeding
- When automatic transitions might go unnoticed
- When you prefer explicit control over automation
- During development/debugging of the pipeline itself

## Enabling Manual Mode

### Option 1: During Installation

```bash
# Install pipeline
./install.sh /path/to/your/project

# Enable manual mode
cd /path/to/your/project
bash ./.claude/../claude-dev-pipeline/scripts/enable-manual-mode.sh
```

### Option 2: In Existing Project

```bash
cd /path/to/your/project

# Enable manual mode
bash /path/to/claude-dev-pipeline/scripts/enable-manual-mode.sh
```

This will:
1. Backup your current `skill-rules.json` (auto-mode)
2. Install `skill-rules.manual-mode.json` as active config
3. Update your project's `.claude/config/skill-rules.json`

## How Manual Mode Works

### Phase Progression

```
PRD Ready
   ↓
[Type: /parse-prd]
   ↓
Phase 1: Task Decomposition
   ↓
🎯 PHASE 1 COMPLETE - AWAITING COMMAND
   ↓
[Type: /generate-specs]
   ↓
Phase 2: Specification Generation
   ↓
🎯 PHASE 2 COMPLETE - AWAITING COMMAND
   ↓
[Type: /implement-tdd]
   ↓
Phase 3: TDD Implementation
   ↓
🎯 PHASE 3 COMPLETE - AWAITING COMMAND
   ↓
[Type: /validate-integration]
   ↓
Phase 4: Integration Testing
   ↓
🎯 PHASE 4 COMPLETE - AWAITING COMMAND
   ↓
[Type: /validate-e2e]
   ↓
Phase 5: E2E Validation
   ↓
🚦 PHASE 5 COMPLETE - GO/NO-GO DECISION REQUIRED
   ↓
[Type: /deploy]
   ↓
Phase 6: Deployment
   ↓
🎉 PIPELINE COMPLETE!
```

### What You'll See

When a phase completes, you'll see a **VERY OBVIOUS** banner like this:

```
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║                    🎯 PHASE 1 COMPLETE 🎯                          ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝

  ✅ Completed: Task Decomposition & Planning

  ⏸️  PIPELINE PAUSED - Awaiting Your Command

╭───────────────────────────────────────────────────────────────────────╮
│                                                                       │
│  To proceed to Phase 2: Specification Generation                     │
│                                                                       │
│  👉 Type: /generate-specs                                            │
│                                                                       │
╰───────────────────────────────────────────────────────────────────────╯

  📋 Alternative: You can review outputs before proceeding
  📊 Monitor: Check .claude/logs/pipeline.log for details
  🔍 Status: Run 'jq . .claude/.workflow-state.json' to see full state

═══════════════════════════════════════════════════════════════════════
```

**You cannot miss this** - it's impossible to overlook!

## Slash Commands Reference

| Phase Complete | Command to Type | Next Phase |
|----------------|-----------------|------------|
| Phase 1 | `/generate-specs` | Phase 2: Spec Generation |
| Phase 2 | `/implement-tdd` | Phase 3: TDD Implementation |
| Phase 3 | `/validate-integration` | Phase 4: Integration Testing |
| Phase 4 | `/validate-e2e` | Phase 5: E2E Validation |
| Phase 5 (with GO) | `/deploy` | Phase 6: Deployment |
| Phase 6 | - | Complete! |

## Manual Mode Configuration

The manual mode config (`skill-rules.manual-mode.json`) sets:

```json
{
  "phase_transitions": {
    "PHASE1_COMPLETE": {
      "auto_trigger": false,
      "requires_user_command": true,
      "slash_command": "/generate-specs"
    },
    "PHASE2_COMPLETE": {
      "auto_trigger": false,
      "requires_user_command": true,
      "slash_command": "/implement-tdd"
    },
    ...
  }
}
```

Key differences from auto-mode:
- **`auto_trigger: false`** - No automatic codeword injection
- **`requires_user_command: true`** - Must type slash command
- **`delay_seconds: 0`** - No delay (waits indefinitely)

## Review Phase Outputs

Before typing the next slash command, you can review the phase outputs:

### After Phase 1 (Task Decomposition)

```bash
# View tasks
task-master list

# Check coupling analysis
cat .taskmaster/tasks.json | jq '.tasks[] | {id, coupling}'

# See dependencies
task-master list --format=tree
```

### After Phase 2 (Spec Generation)

```bash
# List proposals
ls -lh .openspec/proposals/

# Read a proposal
cat .openspec/proposals/batch-1-auth-system.md

# Check test strategies
ls -lh .openspec/test-strategies/
```

### After Phase 3 (TDD Implementation)

```bash
# Run all tests
npm test

# Check coverage
npm test -- --coverage

# Verify no mocks in src/
grep -r "mock\|stub\|fake" src/ --exclude-dir=__tests__
```

### After Phase 4 (Integration Testing)

```bash
# Run integration tests
npm run test:integration

# Check API contracts
openspec validate .openspec/proposals/*.md
```

### After Phase 5 (E2E Validation)

```bash
# Run E2E tests
npm run test:e2e

# Check staging
curl https://staging.example.com/health

# Review test reports
open playwright-report/index.html
```

## Disabling Manual Mode

To restore automatic phase transitions:

```bash
cd /path/to/your/project
bash /path/to/claude-dev-pipeline/scripts/disable-manual-mode.sh
```

This restores the original `skill-rules.json` with `auto_trigger: true`.

## Comparison: Manual vs Auto Mode

| Feature | Manual Mode | Auto Mode |
|---------|-------------|-----------|
| Phase transitions | Explicit slash command | Automatic (PostToolUse hook) |
| Visibility | Very obvious banners | Small messages |
| Control | Full user control | Automated |
| Review time | Unlimited (waits for you) | Brief (2 second delay) |
| Miss transitions? | Impossible | Possible if distracted |
| Best for | Development, learning, debugging | Production, trusted workflows |

## Troubleshooting

### Manual mode not working

```bash
# Verify config is manual mode
grep '"auto_trigger"' .claude/config/skill-rules.json | head -5

# Should show: "auto_trigger": false

# If not, re-run enable script
bash /path/to/claude-dev-pipeline/scripts/enable-manual-mode.sh
```

### Not seeing phase completion banners

The banners are generated by `post-tool-use-tracker.sh` hook. Verify:

```bash
# Check hook is registered
cat .claude/settings.json | jq '.hooks.PostToolUse'

# Check banner library exists
ls -lh .claude/lib/phase-completion-banner.sh

# Check logs for errors
tail -50 .claude/logs/hooks.log
```

### Want to skip a phase

While not recommended, you can jump to any phase:

```bash
# Force skip to Phase 3
/implement-tdd

# Force skip to Phase 5
/validate-e2e
```

The slash commands will check prerequisites and may fail if earlier phases are incomplete.

## Best Practices

1. **Always review phase outputs** before proceeding
2. **Check logs** if something seems wrong: `tail -f .claude/logs/pipeline.log`
3. **Verify tests pass** before moving to next phase
4. **Don't skip phases** unless you know what you're doing
5. **Take notes** on what you observe at each phase

## Related Documentation

- [COMMANDS.md](../COMMANDS.md) - Full slash command reference
- [KNOWN-ISSUES.md](../KNOWN-ISSUES.md) - Hook bugs and workarounds
- [ARCHITECTURE.md](ARCHITECTURE.md) - How hooks and signals work

---

**Last Updated:** 2025-11-05
**Version:** 3.1 (Manual Mode)
