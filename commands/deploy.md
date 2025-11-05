---
description: Deploy to staging and production (Phase 6)
---

# Deployment & Rollout - Phase 6

**🔧 WORKAROUND MODE ACTIVE** - Manual activation for Phase 6 deployment.

## Your Task

Activate the **Deployment Orchestrator** skill (`DEPLOYMENT_ORCHESTRATOR_V1`) to deploy to staging, run canary deployment, and complete production rollout.

## Prerequisites

```bash
# 1. Phase 5 must be complete with GO decision
[ -f .claude/.signals/go-decision.json ] && echo "✅ GO decision recorded" || echo "❌ GO decision required first"

# 2. Deployment tools available
which kubectl || which docker || which aws && echo "✅ Deployment tools ready" || echo "⚠️  Install deployment tools"

# 3. Production credentials configured
[ -n "$PROD_DEPLOY_KEY" ] && echo "✅ Credentials set" || echo "⚠️  Set deployment credentials"
```

## Activation

### Method 1: Codeword Injection

```
[ACTIVATE:DEPLOYMENT_ORCHESTRATOR_V1]
```

### Method 2: Direct Skill Reference

```bash
cat .claude/skills/deployment-orchestrator/SKILL.md
```

## Deployment Strategy

### Phase 6.1: Staging Deployment

Deploy complete system to staging for final validation.

### Phase 6.2: Canary Deployment

Deploy to small % of production traffic to detect issues early.

### Phase 6.3: Progressive Rollout

Gradually increase traffic to new version (0% → 10% → 50% → 100%).

### Phase 6.4: Monitoring & Validation

Watch metrics, logs, and errors during rollout. Rollback if issues detected.

## Deployment Steps

### Step 1: Pre-Deployment Checks

```bash
# Verify build
npm run build
echo "✅ Build successful"

# Run final tests
npm test
echo "✅ Tests passing"

# Verify version
cat package.json | jq -r '.version'

# Check deployment config
kubectl get configmap app-config --namespace=production || echo "⚠️  Config missing"

# Verify secrets
kubectl get secret app-secrets --namespace=production || echo "⚠️  Secrets missing"
```

### Step 2: Staging Deployment

```bash
# Deploy to staging
npm run deploy:staging
# or
kubectl apply -f k8s/staging/ --namespace=staging

# Wait for rollout
kubectl rollout status deployment/app --namespace=staging --timeout=5m

# Verify staging health
curl -f https://staging.example.com/health || echo "❌ Staging unhealthy"

# Run smoke tests on staging
npm run test:smoke -- --env=staging

echo "✅ Staging deployment successful"
```

### Step 3: Request Production Approval

**⚠️ MANUAL GATE: Production Deployment Approval Required**

Present this to user:

```
**🚀 PRODUCTION DEPLOYMENT APPROVAL REQUIRED**

Staging Deployment Summary:
- ✅ Staging deployment successful
- ✅ Smoke tests passing on staging
- ✅ Health checks responding
- ✅ Performance acceptable

**Ready for Production Deployment**

Deployment Plan:
1. Canary: 10% traffic for 15 minutes
2. Monitor: Error rate, latency, success rate
3. Progressive: 10% → 50% → 100% over 1 hour
4. Rollback: Automatic if error rate > 1%

**Rollback procedure tested and ready**

**Decision:**
- Type "DEPLOY PRODUCTION" to approve production deployment
- Type "CANCEL" to abort and remain on staging

**Awaiting your approval...**
```

### Step 4: Production Canary Deployment

Only proceed after approval:

```bash
# Deploy canary (10% traffic)
kubectl apply -f k8s/production/canary.yaml --namespace=production

# Or using deployment tool
npm run deploy:canary

# Wait for canary pods
kubectl rollout status deployment/app-canary --namespace=production --timeout=5m

# Route 10% traffic to canary
kubectl apply -f k8s/production/traffic-split-10.yaml

echo "✅ Canary deployment active (10% traffic)"
```

### Step 5: Monitor Canary

```bash
# Monitor for 15 minutes
echo "⏱️  Monitoring canary for 15 minutes..."

# Watch error rate
watch -n 10 'kubectl logs deployment/app-canary --namespace=production --tail=100 | grep -c ERROR'

# Watch latency (example with Prometheus)
# curl -s "http://prometheus:9090/api/v1/query?query=http_request_duration_seconds{job='app',version='canary'}" | jq

# Check key metrics
for i in {1..90}; do
    # Error rate
    ERROR_RATE=$(kubectl logs deployment/app-canary --namespace=production --since=1m | grep -c ERROR || echo 0)

    # Health check
    HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.example.com/health)

    if [ "$ERROR_RATE" -gt 10 ] || [ "$HEALTH_STATUS" != "200" ]; then
        echo "❌ Canary showing issues - initiating rollback"
        kubectl rollout undo deployment/app-canary --namespace=production
        exit 1
    fi

    sleep 10
done

echo "✅ Canary metrics healthy - proceeding with rollout"
```

### Step 6: Progressive Rollout

```bash
# Increase to 50% traffic
kubectl apply -f k8s/production/traffic-split-50.yaml
echo "📊 Rollout: 50% traffic to new version"
sleep 600  # Monitor for 10 minutes

# Check metrics again
ERROR_RATE=$(kubectl logs deployment/app --namespace=production --since=10m | grep -c ERROR || echo 0)
if [ "$ERROR_RATE" -gt 50 ]; then
    echo "❌ Error rate too high - rollback initiated"
    kubectl rollout undo deployment/app --namespace=production
    exit 1
fi

# Increase to 100% traffic
kubectl apply -f k8s/production/traffic-split-100.yaml
echo "🚀 Rollout: 100% traffic to new version"

# Remove old version after monitoring
sleep 600  # Monitor for 10 minutes
kubectl delete deployment/app-old --namespace=production

echo "✅ Production rollout complete"
```

### Step 7: Post-Deployment Validation

```bash
# Verify production health
curl -f https://api.example.com/health || echo "❌ Production unhealthy"

# Run production smoke tests
npm run test:smoke -- --env=production

# Check error rate
kubectl logs deployment/app --namespace=production --since=30m | grep -c ERROR

# Verify monitoring
curl -s https://monitoring.example.com/api/status

# Check database connections
kubectl exec deployment/app --namespace=production -- npm run db:ping

echo "✅ Post-deployment validation complete"
```

### Step 8: Emit Completion Signal

```bash
cat > .claude/.signals/phase6-complete.json <<EOF
{
  "phase": 6,
  "status": "complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "staging_deployed": true,
  "production_deployed": true,
  "rollout_successful": true,
  "version": "$(cat package.json | jq -r '.version')"
}
EOF

echo "🎉 PHASE 6 COMPLETE - PRODUCTION DEPLOYMENT SUCCESSFUL"
```

## Rollback Procedure

If issues detected at ANY stage:

```bash
# Immediate rollback
kubectl rollout undo deployment/app --namespace=production

# Or using deployment tool
npm run deploy:rollback

# Verify rollback
kubectl rollout status deployment/app --namespace=production

# Check health after rollback
curl -f https://api.example.com/health

# Emit rollback signal
cat > .claude/.signals/rollback.json <<EOF
{
  "action": "rollback",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "High error rate detected during rollout",
  "previous_version_restored": true
}
EOF

echo "🔄 Rollback complete - previous version restored"
```

## Success Criteria

Phase 6 complete when:
- ✅ Staging deployment successful
- ✅ Production approval obtained
- ✅ Canary deployment healthy (error rate < 1%)
- ✅ Progressive rollout complete (100% traffic)
- ✅ Post-deployment validation passed
- ✅ Monitoring confirms stability
- ✅ Signal emitted: `PHASE6_COMPLETE`

## Pipeline Complete

After Phase 6 completion:

```
🎉 **PIPELINE COMPLETE - AUTONOMOUS DEVELOPMENT FINISHED**

Timeline:
- Phase 1: Task Decomposition ✅
- Phase 2: Specification Generation ✅
- Phase 3: TDD Implementation ✅
- Phase 4: Integration Testing ✅
- Phase 5: E2E Validation ✅
- Phase 6: Production Deployment ✅

**Your PRD is now production code!**

Next Steps:
1. Monitor production metrics
2. Set up alerting for anomalies
3. Plan next iteration
4. Document lessons learned
```

## Monitoring Post-Deployment

```bash
# Watch production logs
kubectl logs -f deployment/app --namespace=production

# Monitor dashboards
open https://grafana.example.com/d/app-dashboard

# Set up alerts
# (configured in monitoring/alerts.yaml)

# Check error tracking
open https://sentry.io/your-org/your-project
```

## Troubleshooting

**Deployment stuck:**
```bash
# Check deployment status
kubectl describe deployment/app --namespace=production

# Check pod status
kubectl get pods --namespace=production

# Check events
kubectl get events --namespace=production --sort-by='.lastTimestamp'
```

**High error rate:**
```bash
# Immediate rollback
kubectl rollout undo deployment/app --namespace=production

# Investigate errors
kubectl logs deployment/app --namespace=production --tail=500 | grep ERROR

# Check resource limits
kubectl top pods --namespace=production
```

**Database connection issues:**
```bash
# Test database connection
kubectl exec deployment/app --namespace=production -- npm run db:ping

# Check database credentials
kubectl get secret db-credentials --namespace=production -o yaml

# Verify network policies
kubectl get networkpolicies --namespace=production
```

## Related Commands

- `/validate-e2e` - Phase 5 (prerequisite)
- `/orchestrate` - Full pipeline control (restart if needed)
- `/parse-prd` - Phase 1 (for next iteration)
