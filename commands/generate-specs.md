---
description: Generate OpenSpec proposals and test strategies (Phase 2)
---

# Specification Generation - Phase 2

**🔧 WORKAROUND MODE ACTIVE** - Manual activation for Phase 2 spec generation.

## Your Task

Activate the **Spec Generator** skill (`SPEC_GEN_V1`) to create OpenSpec technical specifications and test strategies from TaskMaster tasks.

## Prerequisites

```bash
# 1. Phase 1 must be complete
[ -f .taskmaster/tasks.json ] && echo "✅ tasks.json exists" || echo "❌ Phase 1 incomplete"

# 2. Coupling analysis should be done
grep -q "coupling" .taskmaster/tasks.json && echo "✅ Coupling data present" || echo "⚠️  Run coupling analysis"

# 3. OpenSpec available
which openspec && echo "✅ OpenSpec ready" || echo "❌ OpenSpec not installed"
```

## Activation

### Method 1: Codeword Injection

```
[ACTIVATE:SPEC_GEN_V1]
```

### Method 2: Direct Skill Reference

Read the skill instructions:

```bash
cat .claude/skills/spec-gen/SKILL.md
```

Then follow the workflow defined there.

## What This Phase Does

1. **Analyze Coupling**: Review coupling analysis from Phase 1
2. **Identify Batches**: Group tightly coupled tasks (5-10 tasks per batch)
3. **Create Worktrees**: Isolate each batch in dedicated git worktree
4. **Generate Proposals**: Create OpenSpec proposals for each batch
5. **Define Test Strategies**: Specify testing approach per batch
6. **Review & Validate**: Ensure specs are complete and consistent

## Expected Outputs

After completion, you should have:

```
.openspec/
├── proposals/
│   ├── batch-1-auth-system.md
│   ├── batch-2-data-layer.md
│   ├── batch-3-api-endpoints.md
│   └── ...
└── test-strategies/
    ├── batch-1-test-strategy.md
    ├── batch-2-test-strategy.md
    └── ...

.worktrees/
├── phase-2-batch-1/
├── phase-2-batch-2/
└── ...

.claude/.signals/
└── phase2-complete.json
```

## Worktree Strategy

**CRITICAL**: Each batch MUST be in isolated worktree:

```bash
# Create worktree for batch N
./.claude/lib/worktree-manager.sh create 2 <batch_number>

# Navigate to worktree
cd .worktrees/phase-2-batch-<batch_number>

# Generate specs in isolation
openspec proposal create ...

# Validate isolation
./.claude/hooks/worktree-enforcer.sh enforce
```

## Success Criteria

Phase 2 complete when:
- ✅ All tasks grouped into batches
- ✅ OpenSpec proposal for each batch
- ✅ Test strategy defined for each batch
- ✅ No coupling conflicts between batches
- ✅ Signal emitted: `PHASE2_COMPLETE`

## Next Phase

After Phase 2 completion:
- PostToolUse hook should automatically trigger Phase 3 (TDD Implementation)
- Or manually activate with: `/implement-tdd`

## Troubleshooting

**Coupling analysis missing:**
```bash
# Run coupling analysis
task-master analyze-coupling
```

**OpenSpec errors:**
```bash
# Check OpenSpec config
cat .openspec/config.json

# Verify proposal format
openspec validate .openspec/proposals/batch-1-*.md
```

**Worktree conflicts:**
```bash
# List worktrees
git worktree list

# Clean stale worktrees
git worktree prune
```

## Related Commands

- `/parse-prd` - Phase 1 (prerequisite)
- `/implement-tdd` - Phase 3 (next phase)
- `/orchestrate` - Full pipeline control
