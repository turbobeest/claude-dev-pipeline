---
description: Implement code using Test-Driven Development (Phase 3)
---

# TDD Implementation - Phase 3

**🔧 WORKAROUND MODE ACTIVE** - Manual activation for Phase 3 TDD implementation.

## Your Task

Activate the **TDD Implementer** skill (`TDD_IMPLEMENTER_V1`) to implement features following RED-GREEN-REFACTOR cycle.

## Prerequisites

```bash
# 1. Phase 2 must be complete
[ -d .openspec/proposals ] && echo "✅ OpenSpec proposals exist" || echo "❌ Phase 2 incomplete"

# 2. Test strategies defined
[ -d .openspec/test-strategies ] && echo "✅ Test strategies ready" || echo "⚠️  Define test strategies"

# 3. Test framework available
npm test --version 2>/dev/null && echo "✅ Test runner ready" || echo "⚠️  Install test framework"
```

## Activation

### Method 1: Codeword Injection

```
[ACTIVATE:TDD_IMPLEMENTER_V1]
```

### Method 2: Direct Skill Reference

```bash
cat .claude/skills/tdd-implementer/SKILL.md
```

## TDD Cycle: RED-GREEN-REFACTOR

### RED Phase: Write Failing Test

1. Read OpenSpec proposal for the task
2. Write test that specifies expected behavior
3. Run test - it MUST fail (RED)
4. Commit failing test

```bash
# Write test
vim src/__tests__/feature.test.js

# Verify test fails
npm test -- feature.test.js
# Expected: FAIL (RED)

# Commit RED state
git add src/__tests__/feature.test.js
git commit -m "test: add failing test for feature X (RED)"
```

### GREEN Phase: Implement Minimum Code

1. Write ONLY enough code to pass the test
2. No extra features, no speculation
3. Run test - it MUST pass (GREEN)
4. Commit passing implementation

```bash
# Implement minimum code
vim src/feature.js

# Verify test passes
npm test -- feature.test.js
# Expected: PASS (GREEN)

# Commit GREEN state
git add src/feature.js
git commit -m "feat: implement feature X (GREEN)"
```

### REFACTOR Phase: Improve Quality

1. Improve code quality (no behavior change)
2. Run tests - they MUST still pass
3. Commit refactored code

```bash
# Refactor for quality
vim src/feature.js

# Verify tests still pass
npm test
# Expected: All PASS

# Commit REFACTOR
git commit -am "refactor: improve feature X implementation"
```

## Anti-Mock Directive

**CRITICAL**: NO MOCK IMPLEMENTATIONS IN OPERATIONAL CODE

❌ **Forbidden:**
```javascript
// DON'T DO THIS
function deployToProduction() {
  console.log("Deployment simulated");
  return { success: true }; // FAKE!
}
```

✅ **Required:**
```javascript
// DO THIS
function deployToProduction() {
  throw new NotImplementedError("Real deployment not yet implemented");
}

// Mocks OK in tests
test('deployment works', () => {
  const mockDeploy = jest.fn(() => ({ success: true }));
  // ...
});
```

## Worktree Isolation

**CRITICAL**: Each task/subtask in dedicated worktree:

```bash
# Create worktree for subtask N
./.claude/lib/worktree-manager.sh create 3 <subtask_number>

# Navigate to worktree
cd .worktrees/phase-3-task-<subtask_number>

# Implement in isolation
# ... TDD cycle ...

# Validate anti-mock compliance
./.claude/hooks/anti-mock-enforcer.sh check

# Merge when complete
./.claude/lib/worktree-manager.sh merge 3 <subtask_number>
```

## Pre-Implementation Validator

The `pre-implementation-validator.sh` hook enforces TDD:

- ❌ **Blocks** implementation code before tests exist
- ✅ **Allows** test files anytime
- ⚠️  **Warns** if RED → GREEN → REFACTOR order violated

Hook runs automatically on PreToolUse for Write/Edit tools.

## Success Criteria

Phase 3 complete when:
- ✅ All tasks implemented following TDD
- ✅ All tests passing
- ✅ No mock implementations in operational code
- ✅ Code coverage ≥80% (if configured)
- ✅ Signal emitted: `PHASE3_COMPLETE`

## Verification

```bash
# Run full test suite
npm test

# Check coverage
npm test -- --coverage

# Verify no mocks in src/ (only in __tests__/)
grep -r "mock\|stub\|fake" src/ --exclude-dir=__tests__ || echo "✅ No mocks in src/"

# Emit completion signal
cat > .claude/.signals/phase3-complete.json <<EOF
{
  "phase": 3,
  "status": "complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tests": "passing",
  "coverage": true
}
EOF
```

## Next Phase

After Phase 3 completion:
- PostToolUse hook should automatically trigger Phase 4 (Integration Testing)
- Or manually activate with: `/validate-integration`

## Troubleshooting

**Tests not running:**
```bash
# Check test framework
npm list jest
npm list mocha
# Or your test runner

# Run with debug
npm test -- --verbose
```

**Anti-mock hook blocking:**
```bash
# Check what's being blocked
tail -50 .claude/logs/hooks.log

# Verify test file exists first
ls -la src/__tests__/
```

**Coverage too low:**
```bash
# Generate coverage report
npm test -- --coverage

# Identify untested code
open coverage/index.html  # or your coverage tool
```

## Related Commands

- `/generate-specs` - Phase 2 (prerequisite)
- `/validate-integration` - Phase 4 (next phase)
- `/orchestrate` - Full pipeline control
