---
activation_code: DEPLOYMENT_ORCHESTRATOR_V1
phase: 6
prerequisites:
  - All tests passing
  - Production readiness validated
  - Human approval
outputs:
  - Deployment artifacts
  - .signals/phase6-complete.json
  - Production deployment status
description: |
  Orchestrates deployment to production after all validations pass.
  Activates via codeword [ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1] injected by hooks
  after human approval gate.
  
  Activation trigger: [ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1]
---

# Deployment Orchestrator Skill

## Activation Method

This skill activates when the hook system injects the codeword:
```
[ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1]
```

This occurs when:
- Phase 5 E2E tests pass with Go decision
- Task #26 (deployment) is active
- Human approval received

## Worktree Isolation Requirements

**CRITICAL**: This skill MUST operate in a dedicated worktree `phase-6-task-1`:

```bash
# Before skill activation:
./lib/worktree-manager.sh create 6 1
cd ./worktrees/phase-6-task-1

# Validate isolation:
./hooks/worktree-enforcer.sh enforce

# Deployment orchestration with isolation
```

### Deployment Isolation Strategy
1. **Secure deployment environment**: Deployment operations in isolated workspace
2. **Artifact isolation**: Build and deployment artifacts contained within worktree
3. **Configuration isolation**: Deployment configs managed without contamination
4. **Rollback preparation**: Rollback scripts and artifacts isolated and ready
5. **Production merge**: Final deployment merged to main with full validation


## What This Skill Does

Automates Phase 6: Production deployment in isolated worktree

- **Staging deployment** (validate) in isolated environment
- **Canary deployment** (monitor) with isolated deployment artifacts
- **Production rollout** (gradual or immediate) from clean workspace
- **Human approval gates** (before canary, before production)
- **Rollback capability** (if issues detected) with isolated rollback scripts
- **NEW**: Isolated deployment environment prevents contamination
- **NEW**: Secure artifact management within worktree boundaries

## Execution Flow

```
Stage 1: Pre-Deployment Validation
         - Verify Phase 5 GO decision
         - Check all tests passing
         - Validate production readiness score
Stage 2: Staging Deployment
         - Deploy to staging environment
         - Run smoke tests
         - Validate monitoring
         ⚠️ HUMAN APPROVAL: Proceed to canary?
Stage 3: Canary Deployment
         - Deploy to 5% of production traffic
         - Monitor for 24 hours
         - Compare metrics vs baseline
         ⚠️ HUMAN APPROVAL: Full production?
Stage 4: Production Rollout
         - Gradual rollout (10% → 50% → 100%)
         - OR immediate (100%)
         - Monitor continuously
Stage 5: Post-Deployment Validation
         - Verify all services healthy
         - Confirm metrics normal
         - Generate completion report
```

## Deployment Strategy

### Staging
```bash
# Deploy to staging
./scripts/deploy.sh staging

# Run smoke tests
npm test:smoke

# Validate
./scripts/health-check.sh staging
```

### Canary (with approval)
```bash
# Deploy 5% traffic
./scripts/deploy.sh canary --traffic=5

# Monitor 24 hours
# Watch: error rate, latency, throughput

# ⚠️ HUMAN DECISION POINT
# Continue OR Rollback
```

### Production (with approval)
```bash
# Gradual rollout
./scripts/deploy.sh prod --traffic=10
# Wait 2 hours, monitor
./scripts/deploy.sh prod --traffic=50
# Wait 4 hours, monitor
./scripts/deploy.sh prod --traffic=100

# OR immediate
./scripts/deploy.sh prod --traffic=100
```

## Human Approval Gates

### Gate 1: Staging → Canary
**Required checks:**
- ✅ Staging deployment successful
- ✅ Smoke tests passing
- ✅ No errors in logs
- ✅ Monitoring dashboards healthy

**Question:** "Proceed to canary deployment?"

### Gate 2: Canary → Production
**Required checks:**
- ✅ Canary stable for 24 hours
- ✅ Error rate ≤ baseline
- ✅ Latency ≤ baseline +10%
- ✅ No customer complaints

**Question:** "Proceed to full production?"

## Rollback Triggers

**Automatic rollback if:**
- Error rate > baseline + 50%
- Latency > baseline + 100%
- Critical service down > 1 min

**Manual rollback:**
```bash
./scripts/rollback.sh
```

## Monitoring Dashboard

**Key metrics:**
- Request rate (req/sec)
- Error rate (%)
- Latency (p50, p95, p99)
- CPU usage (%)
- Memory usage (%)
- Database connections

## Time Estimates

| Phase | Duration |
|-------|----------|
| Staging | 30 min |
| Canary | 24 hours |
| Production | 2-8 hours |
| **Total** | **25-32 hours** |

## Completion Signal

```json
{
  "phase": 6,
  "status": "success",
  "summary": {
    "deployed_to": "production",
    "traffic": 100,
    "health": "green",
    "rollbacks": 0
  },
  "pipeline_complete": true
}
```

## Output Files

```
.taskmaster/
├── DEPLOYMENT_REPORT.md
└── .signals/phase6-complete.json

logs/
├── deployment-staging.log
├── deployment-canary.log
└── deployment-production.log
```

## See Also

- Pipeline Orchestrator (triggers this, manages approvals)
- E2E Validator (Phase 5, provides GO decision)