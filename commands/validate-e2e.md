---
description: Run end-to-end production validation (Phase 5)
---

# End-to-End Production Validation - Phase 5

**🔧 WORKAROUND MODE ACTIVE** - Manual activation for Phase 5 E2E validation.

## Your Task

Activate the **E2E Validator** skill (`E2E_VALIDATOR_V1`) to validate complete user workflows in production-like environment.

## Prerequisites

```bash
# 1. Phase 4 must be complete
[ -f .claude/.signals/phase4-complete.json ] && echo "✅ Integration tests passed" || echo "❌ Phase 4 incomplete"

# 2. Staging environment available
curl -f http://staging.example.com/health 2>/dev/null && echo "✅ Staging ready" || echo "⚠️  Deploy to staging first"

# 3. E2E test framework ready
which playwright || which cypress || which selenium-webdriver && echo "✅ E2E framework ready" || echo "⚠️  Install E2E test tools"
```

## Activation

### Method 1: Codeword Injection

```
[ACTIVATE:E2E_VALIDATOR_V1]
```

### Method 2: Direct Skill Reference

```bash
cat .claude/skills/e2e-validator/SKILL.md
```

## What This Phase Tests

### 1. Complete User Workflows
- User registration → login → core feature usage → logout
- Shopping cart → checkout → payment → confirmation
- Content creation → editing → publishing → viewing
- Admin workflows (user management, configuration)

### 2. Cross-Browser Compatibility
- Chrome/Chromium
- Firefox
- Safari (if applicable)
- Mobile browsers (if applicable)

### 3. Production Readiness
- Performance under load
- Error handling with real scenarios
- Data consistency end-to-end
- Security (authentication, authorization)

### 4. User Experience
- Page load times
- Responsive design
- Accessibility (WCAG compliance)
- Error messages user-friendly

## Test Execution

### Setup E2E Environment

```bash
# Start staging environment
docker-compose -f docker-compose.staging.yml up -d

# Or deploy to staging
npm run deploy:staging

# Wait for services
./scripts/wait-for-staging.sh

# Seed test data
npm run db:seed:e2e
```

### Run E2E Tests

```bash
# Run full E2E suite
npm run test:e2e

# Or with specific framework
npx playwright test
# or
npx cypress run

# Run critical path tests only
npm run test:e2e:critical
```

### Load Testing

```bash
# Run load tests (if configured)
npm run test:load

# Or use artillery/k6
artillery run load-test.yml
```

## Example E2E Tests

### User Registration Flow

```javascript
test('complete user registration and onboarding', async ({ page }) => {
  // Navigate to app
  await page.goto('https://staging.example.com');

  // Click signup
  await page.click('text=Sign Up');

  // Fill registration form
  await page.fill('[name="email"]', 'newuser@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  await page.fill('[name="confirmPassword"]', 'SecurePass123!');
  await page.click('button:has-text("Create Account")');

  // Wait for redirect to dashboard
  await page.waitForURL('**/dashboard');

  // Verify welcome message
  await expect(page.locator('text=Welcome')).toBeVisible();

  // Complete onboarding
  await page.click('text=Get Started');
  await page.fill('[name="displayName"]', 'Test User');
  await page.click('button:has-text("Save")');

  // Verify onboarding complete
  await expect(page.locator('text=Profile Complete')).toBeVisible();
});
```

### E-Commerce Purchase Flow

```javascript
test('complete purchase from browse to confirmation', async ({ page }) => {
  // Login
  await page.goto('https://staging.example.com/login');
  await page.fill('[name="email"]', 'buyer@example.com');
  await page.fill('[name="password"]', 'password123');
  await page.click('button:has-text("Login")');

  // Browse products
  await page.click('text=Shop');
  await page.click('.product-card:first-child');

  // Add to cart
  await page.click('button:has-text("Add to Cart")');
  await expect(page.locator('.cart-badge')).toHaveText('1');

  // Checkout
  await page.click('.cart-icon');
  await page.click('text=Checkout');

  // Enter shipping
  await page.fill('[name="address"]', '123 Test St');
  await page.fill('[name="city"]', 'Test City');
  await page.fill('[name="zip"]', '12345');
  await page.click('button:has-text("Continue")');

  // Enter payment (test mode)
  await page.fill('[name="cardNumber"]', '4242424242424242');
  await page.fill('[name="expiry"]', '12/25');
  await page.fill('[name="cvc"]', '123');
  await page.click('button:has-text("Place Order")');

  // Verify confirmation
  await page.waitForURL('**/order/confirmation/*');
  await expect(page.locator('text=Order Confirmed')).toBeVisible();

  // Extract order number
  const orderNumber = await page.locator('.order-number').textContent();
  expect(orderNumber).toMatch(/^ORD-\d+$/);
});
```

## Production Readiness Checklist

Before proceeding to Phase 6, verify:

### Security
- ✅ Authentication working correctly
- ✅ Authorization enforced
- ✅ HTTPS enabled
- ✅ Security headers set
- ✅ SQL injection prevented
- ✅ XSS protection active

### Performance
- ✅ Page load < 3 seconds
- ✅ API response < 500ms (p95)
- ✅ No memory leaks
- ✅ Database queries optimized

### Reliability
- ✅ Error handling graceful
- ✅ Retry logic works
- ✅ Fallbacks operational
- ✅ Health checks responding

### Monitoring
- ✅ Logs aggregated
- ✅ Metrics collected
- ✅ Alerts configured
- ✅ Dashboards available

### Rollback Plan
- ✅ Rollback procedure documented
- ✅ Rollback tested
- ✅ Recovery time < 5 minutes
- ✅ Data migration reversible

## Emit Completion Signal

```bash
# After all E2E tests pass
cat > .claude/.signals/phase5-complete.json <<EOF
{
  "phase": 5,
  "status": "complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "e2e_tests": "passing",
  "production_ready": true,
  "critical_workflows_validated": true
}
EOF

echo "✅ Phase 5 Complete: E2E validation passed"
```

## 🚦 GO/NO-GO DECISION REQUIRED

**Before proceeding to Phase 6 (Deployment), a human decision is required:**

### Present This Summary to User

```
**📊 PHASE 5 COMPLETE - GO/NO-GO DECISION REQUIRED**

E2E Validation Results:
- ✅ All critical workflows tested and passing
- ✅ Security validation complete
- ✅ Performance benchmarks met
- ✅ Production readiness verified

**Ready for Phase 6 Production Deployment**

Please review:
1. E2E test results (see above)
2. Staging environment behavior
3. Rollback procedures in place

**Decision:**
- Type "GO" to approve proceeding to Phase 6 deployment
- Type "NO-GO" to halt pipeline and review issues

**Awaiting your decision...**
```

### Capture Decision

When user responds:

**If "GO":**
```bash
cat > .claude/.signals/go-decision.json <<EOF
{
  "decision": "GO",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "approved_by": "user",
  "phase5_validated": true
}
EOF

echo "✅ GO DECISION RECORDED - Proceeding to Phase 6"
```

**If "NO-GO":**
```bash
cat > .claude/.signals/no-go-decision.json <<EOF
{
  "decision": "NO-GO",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "User requested halt for review"
}
EOF

echo "🛑 NO-GO DECISION - Pipeline halted. Review issues and restart when ready."
exit 1
```

## Phase Complete - STOP HERE

When Phase 5 is complete AND user approves GO decision, display this message and STOP:

```
═══════════════════════════════════════════════════════════
  🎯 PHASE 5 COMPLETE - E2E Validation Finished
  🚦 GO DECISION RECORDED
═══════════════════════════════════════════════════════════

  ✅ All E2E tests passing
  ✅ Production readiness verified
  ✅ GO decision approved

  ⏸️  PIPELINE STOPPED - Awaiting your command

  👉 To proceed to Phase 6 (Production Deployment), type:

     /deploy

  ⚠️  This will deploy to production!

═══════════════════════════════════════════════════════════
```

**CRITICAL: DO NOT PROCEED AUTOMATICALLY**
- ❌ Do NOT start deployment on your own
- ❌ Do NOT deploy to staging or production
- ❌ Do NOT be "helpful" and continue

**WAIT FOR USER TO TYPE: /deploy**

## Troubleshooting

**E2E tests failing:**
```bash
# Run tests with debug mode
DEBUG=* npm run test:e2e

# Check staging logs
kubectl logs -f deployment/app --namespace=staging
# or
docker-compose -f docker-compose.staging.yml logs -f

# Take screenshots on failure (Playwright)
npx playwright test --screenshot=on
```

**Performance issues:**
```bash
# Run performance profiling
npm run test:performance

# Check resource usage
docker stats

# Profile specific endpoint
curl -w "@curl-format.txt" -o /dev/null -s http://staging.example.com/api/endpoint
```

**Security scan failures:**
```bash
# Run security audit
npm audit
npm run test:security

# Check HTTPS
curl -vI https://staging.example.com
```

## Cleanup

```bash
# Stop staging environment
docker-compose -f docker-compose.staging.yml down

# Clean E2E test data
npm run db:clean:e2e
```

## Related Commands

- `/validate-integration` - Phase 4 (prerequisite)
- `/deploy` - Phase 6 (next phase after GO decision)
- `/orchestrate` - Full pipeline control
