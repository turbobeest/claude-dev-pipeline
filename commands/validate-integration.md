---
description: Run component integration testing (Phase 4)
---

# Component Integration Testing - Phase 4

**🔧 WORKAROUND MODE ACTIVE** - Manual activation for Phase 4 integration validation.

## Your Task

Activate the **Integration Validator** skill (`INTEGRATION_VALIDATOR_V1`) to validate component interactions and system integration.

## Prerequisites

```bash
# 1. Phase 3 must be complete
npm test 2>/dev/null && echo "✅ Unit tests passing" || echo "❌ Phase 3 incomplete"

# 2. All components implemented
[ -d src ] && echo "✅ Source code exists" || echo "❌ No implementation"

# 3. Integration test framework ready
npm list --depth=0 | grep -E "supertest|request|axios" && echo "✅ Integration test tools ready" || echo "⚠️  Install integration test dependencies"
```

## Activation

### Method 1: Codeword Injection

```
[ACTIVATE:INTEGRATION_VALIDATOR_V1]
```

### Method 2: Direct Skill Reference

```bash
cat .claude/skills/integration-validator/SKILL.md
```

## What This Phase Tests

### 1. Component Interactions
- API endpoints calling services
- Services accessing data layer
- Event handlers triggering workflows
- Message queue interactions

### 2. Contract Validation
- Request/response formats match specs
- Data types correct across boundaries
- Error handling propagates properly
- Timeouts and retries work

### 3. Data Flows
- Data transforms correctly through pipeline
- State persists across operations
- Transactions handle errors (rollback)
- Concurrency handled safely

### 4. Integration Points
- Database connections
- External API calls (if not mocked)
- File system operations
- Environment configuration

## Test Strategy

### Start Services

```bash
# Start dependencies (if using Docker)
docker-compose -f docker-compose.test.yml up -d

# Or start services locally
npm run start:test &
TEST_SERVER_PID=$!

# Wait for services
timeout 30 bash -c 'until curl -f http://localhost:3000/health; do sleep 1; done'
```

### Run Integration Tests

```bash
# Run integration test suite
npm run test:integration

# Or specific integration tests
npm test -- --testPathPattern=integration
```

### Check Results

```bash
# All tests should pass
# No timeouts or connection errors
# No contract violations
# Response times acceptable
```

## Validation Checklist

Phase 4 complete when:

- ✅ All component integration tests passing
- ✅ API contracts validated
- ✅ Database operations working
- ✅ Error handling verified
- ✅ Performance acceptable
- ✅ No integration failures
- ✅ Signal emitted: `PHASE4_COMPLETE`

## Example Integration Tests

### API Integration Test

```javascript
describe('User Registration Flow (Integration)', () => {
  it('creates user, sends email, and returns token', async () => {
    const response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'test@example.com',
        password: 'SecurePass123!'
      });

    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('token');

    // Verify user in database
    const user = await db.users.findByEmail('test@example.com');
    expect(user).toBeDefined();

    // Verify email queued
    const emails = await emailQueue.getJobs();
    expect(emails).toHaveLength(1);
    expect(emails[0].data.to).toBe('test@example.com');
  });
});
```

### Service Integration Test

```javascript
describe('Payment Processing (Integration)', () => {
  it('processes payment and updates order status', async () => {
    const order = await createTestOrder();

    const result = await paymentService.processPayment({
      orderId: order.id,
      amount: 99.99,
      method: 'card',
      token: 'test_token_123'
    });

    expect(result.success).toBe(true);

    // Verify order updated
    const updatedOrder = await orderService.getOrder(order.id);
    expect(updatedOrder.status).toBe('paid');
    expect(updatedOrder.payment.transactionId).toBeDefined();
  });
});
```

## Infrastructure Validation

If your system has infrastructure components:

```bash
# Run infrastructure validator
./.claude/hooks/infrastructure-validator.sh check

# Verify:
# - Database migrations applied
# - Environment variables set
# - External services accessible
# - Secrets configured
# - Monitoring enabled
```

## Emit Completion Signal

```bash
# After all integration tests pass
cat > .claude/.signals/phase4-complete.json <<EOF
{
  "phase": 4,
  "status": "complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "integration_tests": "passing",
  "components_validated": true
}
EOF

echo "✅ Phase 4 Complete: Integration tests passing"
```

## Next Phase

After Phase 4 completion:
- PostToolUse hook should automatically trigger Phase 5 (E2E Validation)
- Or manually activate with: `/validate-e2e`

## Troubleshooting

**Integration tests failing:**
```bash
# Check service logs
docker-compose logs

# Verify services running
docker-compose ps

# Check database connection
npm run db:ping
```

**Contract violations:**
```bash
# Validate OpenSpec contracts
openspec validate .openspec/proposals/*.md

# Check actual API responses
curl -v http://localhost:3000/api/endpoint
```

**Timeout issues:**
```bash
# Increase test timeouts
# In test file:
jest.setTimeout(30000); // 30 seconds

# Check service health
curl http://localhost:3000/health
```

## Cleanup

```bash
# Stop test services
docker-compose -f docker-compose.test.yml down

# Or kill test server
kill $TEST_SERVER_PID

# Clean test data
npm run db:clean:test
```

## Related Commands

- `/implement-tdd` - Phase 3 (prerequisite)
- `/validate-e2e` - Phase 5 (next phase)
- `/orchestrate` - Full pipeline control
