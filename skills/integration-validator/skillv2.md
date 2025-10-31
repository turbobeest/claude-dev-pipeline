---
description: |
  Automates Phase 4 of the development pipeline: validates all component integration points
  are tested and working. Analyzes architecture for integration points, identifies coverage
  gaps, creates missing tests, and validates the entire system. Activates when Phase 3
  completes or user says "begin phase 4", "test integration points", "validate Task 24".
  
  Key triggers: "begin phase 4", "test integration", "validate Task 24",
  "phase 3 complete, start phase 4"
---

# Integration Validator Skill

## What This Skill Does

Automates Phase 4: Component integration testing

- **Discovers all integration points** from architecture
- **Analyzes coverage** (tested vs untested)
- **Creates missing tests** automatically
- **Validates performance** and error handling
- **Generates report** and completion signal

## Execution Flow

```
Stage 1: Load Phase 3 Results
Stage 2: Discover Integration Points
         - Parse docs/architecture.md
         - Extract all A ↔ B relationships
Stage 3: Analyze Coverage
         - Scan tests/integration/
         - Calculate coverage %
Stage 4: Create Missing Tests (Batched)
         - Data layer integration
         - Service layer integration
         - External service integration
         - API gateway integration
Stage 5: Validate All Tests Pass
Stage 6: Generate Report & Signal → Phase 5
```

## Integration Point Discovery

**Automatically extracts from architecture:**
- Service ↔ Database
- Service ↔ Service
- Frontend ↔ Backend
- Service ↔ External APIs
- Service ↔ Message Queues

## Test Batching Strategy

### Batch 1: Data Layer
```
- User Service ↔ Database
- Product Service ↔ Database
- Order Service ↔ Database
- Auth Service ↔ Database
```

### Batch 2: Service Layer
```
- API Gateway ↔ Auth Service
- API Gateway ↔ User Service
- Order Service ↔ Payment Service
```

### Batch 3: External Services
```
- Order Service ↔ Stripe
- User Service ↔ SendGrid
- Product Service ↔ S3
```

### Batch 4: Frontend
```
- Frontend ↔ API Gateway
- Frontend ↔ WebSocket Service
```

## Test Template Per Integration

```javascript
// tests/integration/order-payment.test.js
describe('Order → Payment Integration', () => {
  // Happy path
  test('successful payment creates order', async () => {
    const order = await createOrder({...});
    expect(order.status).toBe('paid');
  });
  
  // Error scenarios
  test('payment failure rolls back order', async () => {
    // Stripe returns error
    // Verify order not created
  });
  
  // Performance
  test('payment completes within 2s', async () => {
    const start = Date.now();
    await createOrder({...});
    expect(Date.now() - start).toBeLessThan(2000);
  });
});
```

## Validation Gates

**Before completing Task #24:**

- ✅ All integration points tested (100%)
- ✅ All integration tests passing
- ✅ Error scenarios covered
- ✅ Performance benchmarks met
- ✅ No errors in logs
- ✅ Regression tests passing

## Time Estimates

| Integration Points | Time |
|-------------------|------|
| 5-10 | 1-2 hours |
| 11-20 | 3-4 hours |
| 21-30 | 5-6 hours |

## Completion Signal

```json
{
  "phase": 4,
  "status": "success",
  "summary": {
    "integration_points": N,
    "coverage": 100,
    "tests_created": M,
    "all_passing": true
  },
  "next_phase": 5,
  "trigger_next": true
}
```

## Output Files

```
tests/integration/
├── [component]-[component].test.js
└── ...

.taskmaster/
├── INTEGRATION_TEST_REPORT.md
└── .signals/phase4-complete.json
```

## See Also

- Pipeline Orchestrator (triggers this)
- TDD Implementer (Phase 3, provides input)
- E2E Validator (Phase 5, triggered by signal)