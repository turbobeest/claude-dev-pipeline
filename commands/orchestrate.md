---
description: Start full pipeline automation (Phase 0 → Phase 6)
---

# Pipeline Orchestration - Master Control

**🔧 WORKAROUND MODE ACTIVE** - Bypasses broken UserPromptSubmit hooks for pipeline startup.

## Your Task

You are activating the **Pipeline Orchestration** skill (`PIPELINE_ORCHESTRATION_V1`) to manage the complete development lifecycle from Phase 1 through Phase 6.

## Prerequisites Check

Before starting, verify:

```bash
# 1. PRD exists
[ -f docs/PRD.md ] && echo "✅ PRD found" || echo "❌ PRD missing"

# 2. Environment configured
[ -f .env ] && echo "✅ .env found" || echo "⚠️  .env missing (optional)"

# 3. Git repo initialized
git rev-parse --git-dir >/dev/null 2>&1 && echo "✅ Git initialized" || echo "❌ Git not initialized"

# 4. Tools available
which task-master && echo "✅ TaskMaster available" || echo "❌ TaskMaster missing"
which jq && echo "✅ jq available" || echo "❌ jq missing"
```

## Pipeline Overview

You will orchestrate these 6 phases autonomously:

### Phase 1: Task Decomposition & Planning
- Parse PRD with TaskMaster
- Generate task hierarchy with dependencies
- Perform coupling analysis
- **Signal**: `PHASE1_COMPLETE`

### Phase 2: Specification Generation
- Create OpenSpec proposals for coupled tasks
- Generate test strategies
- Define interfaces and contracts
- **Signal**: `PHASE2_COMPLETE`

### Phase 3: TDD Implementation
- Write tests first (RED phase)
- Implement code to pass tests (GREEN phase)
- Refactor with quality improvements (REFACTOR phase)
- **Signal**: `PHASE3_COMPLETE`

### Phase 4: Component Integration Testing
- Validate component interactions
- Test API contracts
- Verify data flows
- **Signal**: `PHASE4_COMPLETE`

### Phase 5: E2E Production Validation
- Run end-to-end user workflows
- Validate production readiness
- **Manual Gate**: Request GO/NO-GO decision
- **Signal**: `PHASE5_COMPLETE` (after approval)

### Phase 6: Deployment & Rollout
- Deploy to staging
- Run canary deployment
- Full production rollout
- **Manual Gate**: Request production deployment approval
- **Signal**: `PHASE6_COMPLETE`

## Execution Steps

### Step 1: Initialize Pipeline State

```bash
# Create state directory
mkdir -p .claude/.signals

# Initialize workflow state
cat > .claude/.workflow-state.json <<'EOF'
{
  "currentPhase": 0,
  "phases": {
    "0": {"status": "in_progress", "name": "Initialization"},
    "1": {"status": "pending", "name": "Task Decomposition"},
    "2": {"status": "pending", "name": "Specification"},
    "3": {"status": "pending", "name": "Implementation"},
    "4": {"status": "pending", "name": "Integration Testing"},
    "5": {"status": "pending", "name": "E2E Validation"},
    "6": {"status": "pending", "name": "Deployment"}
  },
  "signals": {},
  "lastSignal": null,
  "startTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}
EOF

echo "✅ Pipeline state initialized"
```

### Step 2: Start Phase 1 (Task Decomposition)

Activate the PRD-to-Tasks skill:

```
/parse-prd
```

Or manually:
```bash
task-master parse-prd docs/PRD.md
```

**Wait for**: Phase 1 completion signal

### Step 3: Monitor Automatic Phase Transitions

The PostToolUse hook will automatically:
- Detect phase completion signals
- Inject next phase activation codewords
- Transition to subsequent phases

**You should monitor for these signals:**
- `PHASE1_COMPLETE` → Triggers `/generate-specs`
- `PHASE2_COMPLETE` → Triggers `/implement-tdd`
- `PHASE3_COMPLETE` → Triggers `/validate-integration`
- `PHASE4_COMPLETE` → Triggers `/validate-e2e`
- `PHASE5_COMPLETE` → Triggers `/deploy`

### Step 4: Handle Manual Approval Gates

**Gate 1: Phase 5 → Phase 6 (GO/NO-GO Decision)**

After E2E validation completes, you MUST ask the user:

```
**🚦 GO/NO-GO DECISION REQUIRED**

Phase 5 E2E validation is complete. Before proceeding to deployment:

1. Review test results
2. Check production readiness
3. Verify rollback procedures

**Do you approve proceeding to Phase 6 deployment?**
- Type "GO" to approve and continue
- Type "NO-GO" to halt pipeline
```

**Gate 2: Phase 6 Production Deployment**

Before production rollout:

```
**🚀 PRODUCTION DEPLOYMENT APPROVAL REQUIRED**

Staging deployment successful. Ready for production rollout.

**Approve production deployment?**
- Type "DEPLOY PRODUCTION" to proceed
- Type "CANCEL" to abort
```

## Error Handling & Recovery

### If Phase Fails

```bash
# Check last error
tail -50 .claude/logs/pipeline.log

# Check current state
jq . .claude/.workflow-state.json

# Retry current phase
# Use the appropriate slash command for the failed phase
```

### If Signal Detection Fails

Manually inject the activation codeword:

```
[ACTIVATE:SPEC_GEN_V1]           # For Phase 2
[ACTIVATE:TDD_IMPLEMENTER_V1]    # For Phase 3
[ACTIVATE:INTEGRATION_VALIDATOR_V1] # For Phase 4
[ACTIVATE:E2E_VALIDATOR_V1]      # For Phase 5
[ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1] # For Phase 6
```

Or use slash commands:
```
/generate-specs      # Phase 2
/implement-tdd       # Phase 3
/validate-integration # Phase 4
/validate-e2e        # Phase 5
/deploy              # Phase 6
```

## Progress Monitoring

### Real-Time Dashboard

```bash
# Start web dashboard
python3 .claude/monitor-dashboard.py
# Open: http://localhost:8888
```

### CLI Monitoring

```bash
# Watch pipeline status
watch -n 2 'jq ".currentPhase,.phases" .claude/.workflow-state.json'

# Stream logs
tail -f .claude/logs/pipeline.log

# Check signals
ls -lth .claude/.signals/
```

## Automation Level

**95% Automation:**
- ✅ Phase 0 → 1: Automatic (via `/parse-prd` or this command)
- ✅ Phase 1 → 2: Automatic (PostToolUse hook)
- ✅ Phase 2 → 3: Automatic (PostToolUse hook)
- ✅ Phase 3 → 4: Automatic (PostToolUse hook)
- ✅ Phase 4 → 5: Automatic (PostToolUse hook)
- ⚠️  Phase 5 → 6: **Manual approval required** (GO/NO-GO gate)
- ⚠️  Phase 6 production: **Manual approval required** (deployment gate)
- ⚠️  Phase 6 rollback: **Manual approval required** (if issues detected)

**3 Human Decision Points:**
1. Phase 5 completion → GO/NO-GO decision
2. Phase 6 staging → Production deployment approval
3. Phase 6 production → Rollback approval (if needed)

## Expected Timeline

Typical timeline for medium-sized project (50-100 tasks):

- Phase 1: 5-10 minutes (PRD parsing, task generation)
- Phase 2: 15-30 minutes (spec generation, test strategies)
- Phase 3: 2-4 hours (TDD implementation)
- Phase 4: 30-60 minutes (integration testing)
- Phase 5: 30-60 minutes (E2E validation)
- Phase 6: 30-60 minutes (deployment)

**Total: 4-7 hours of autonomous development**

## Success Criteria

Pipeline complete when:
- ✅ All 6 phases show "complete" status
- ✅ All tests passing
- ✅ Production deployment successful
- ✅ No errors in logs
- ✅ Signal: `PHASE6_COMPLETE` emitted

## Troubleshooting

**Pipeline stuck?**
- Check `.claude/.workflow-state.json` for current phase
- Review `.claude/logs/pipeline.log` for errors
- Use slash commands to manually advance phases

**Automatic transitions not working?**
- Verify PostToolUse hook is executing (check logs)
- Manually inject codewords if detection fails
- Fall back to slash commands for reliability

**Phase 5 or 6 blocked?**
- These require manual approval - check for approval prompts
- Type "GO" or "DEPLOY PRODUCTION" to proceed

## Notes

- This command starts the FULL pipeline (all 6 phases)
- For individual phase control, use specific slash commands
- PostToolUse hook handles automatic transitions
- Manual intervention only needed at 3 approval gates
- Progress saved at each phase (can resume from checkpoint)

## Related Commands

- `/parse-prd` - Phase 1 only
- `/generate-specs` - Phase 2 only
- `/implement-tdd` - Phase 3 only
- `/validate-integration` - Phase 4 only
- `/validate-e2e` - Phase 5 only
- `/deploy` - Phase 6 only
