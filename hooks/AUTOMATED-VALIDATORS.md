# Automated Validation Hooks

This directory contains automated validation hooks that ensure the TARGET codebase meets production-ready standards before deployment.

## Overview

The pipeline now includes **three critical automated validators** that execute actual tests and security scans instead of relying on manual checklists.

### Priority 1 Validators (Production Blockers)

| Validator | Purpose | Blocks Deployment |
|-----------|---------|-------------------|
| `security-validator.sh` | Security scanning (vulnerabilities, secrets, SAST) | ✅ YES |
| `load-test-validator.sh` | Load testing execution and validation | ✅ YES |
| `performance-validator.sh` | Performance target validation against PRD | ⚠️ WARNING |

---

## 1. Security Validator

**File:** `security-validator.sh`

### What It Does

Runs comprehensive security scanning automatically:

1. **Dependency Scanning**
   - npm audit (Node.js projects)
   - pip-audit (Python projects)
   - Blocks on critical/high vulnerabilities

2. **Container Security**
   - Trivy image scanning
   - Checks for vulnerabilities in Docker images
   - Scans all images defined in docker-compose.yml

3. **Secrets Detection**
   - Gitleaks scanning
   - Detects hardcoded secrets, API keys, tokens
   - Prevents credential leaks

4. **SAST Scanning**
   - Semgrep static analysis
   - Detects code security issues
   - Blocks on error-level findings

### Usage

```bash
./hooks/security-validator.sh
```

### Exit Codes

- `0` - Security validation PASSED
- `1` - Security validation FAILED (blocks deployment)

### Output

Creates `.security-validation.json` with detailed results:
```json
{
  "timestamp": "2025-10-31T...",
  "status": "passed",
  "checks": {
    "npm_audit": {"status": "passed", "details": "No high or critical vulnerabilities"},
    "container_scan": {"status": "passed", "details": "All images clean"},
    "secrets_scan": {"status": "passed", "details": "No secrets found"},
    "sast_scan": {"status": "passed", "details": "No issues"}
  }
}
```

### Required Tools

Install security tools (optional but recommended):

```bash
# Container scanning (highly recommended)
brew install trivy

# Secrets detection (highly recommended)
brew install gitleaks

# SAST scanning (optional)
pip install semgrep

# Python security (if Python project)
pip install pip-audit
```

**Note:** The validator gracefully skips tools that aren't installed but will warn you.

---

## 2. Load Test Validator

**File:** `load-test-validator.sh`

### What It Does

Automatically detects, executes, and validates load tests:

1. **Framework Detection**
   - Detects: k6, Artillery, Locust, JMeter, npm scripts
   - Finds test files automatically

2. **Test Execution**
   - Runs load tests automatically
   - Captures results in JSON format

3. **Results Validation**
   - Validates test passed
   - Checks for failures and errors

### Usage

```bash
./hooks/load-test-validator.sh
```

### Exit Codes

- `0` - Load tests PASSED
- `1` - Load tests FAILED or not found

### Supported Frameworks

#### k6 (Recommended)

Create `k6-load-test.js`:
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 100,
  duration: '5m',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get('http://localhost:8000/api/health');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

Install: `brew install k6`

#### Artillery

Create `artillery.yml`:
```yaml
config:
  target: 'http://localhost:8000'
  phases:
    - duration: 300
      arrivalRate: 20
scenarios:
  - flow:
      - get:
          url: '/api/health'
```

Install: `npm install -g artillery`

#### npm Script

Add to `package.json`:
```json
{
  "scripts": {
    "load:test": "k6 run k6-load-test.js"
  }
}
```

### Output

Creates `.load-test-results.json` with test results.

---

## 3. Performance Validator

**File:** `performance-validator.sh`

### What It Does

Validates performance against PRD requirements:

1. **PRD Parsing**
   - Extracts performance targets from PRD
   - Identifies latency, throughput, concurrency requirements

2. **Test Execution**
   - Runs performance tests
   - Collects actual metrics

3. **Validation**
   - Compares actual vs required
   - Blocks if targets not met

### Usage

```bash
./hooks/performance-validator.sh
```

### Exit Codes

- `0` - Performance targets MET or no requirements in PRD
- `1` - Performance targets NOT MET

### PRD Requirements Format

The validator extracts these patterns from `docs/PRD.md`:

```markdown
## Performance Requirements

- Latency p95: < 200ms
- Latency p99: < 500ms
- Average latency: < 100ms
- Throughput: 1000 requests per second
- Concurrent users: 500 users
- CPU: < 80%
- Memory: < 4GB
```

### Output

Creates `.performance-validation.json`:
```json
{
  "requirements": {
    "latency_p95_ms": "200",
    "throughput_rps": "1000"
  },
  "actual": {
    "latency_p95_ms": "185",
    "throughput_rps": "1050"
  },
  "validation": {
    "latency_p95": "PASSED",
    "throughput": "PASSED"
  },
  "status": "passed"
}
```

---

## Integration with Pipeline

### Phase 4: Integration Validator

The `integration-validator` skill now instructs to run automated hooks before Task #26:

```bash
# Before production readiness scoring
./hooks/security-validator.sh || exit 1
./hooks/load-test-validator.sh || exit 1
./hooks/performance-validator.sh || exit 1
```

### Phase 6: Deployment Orchestrator

The `deployment-orchestrator` skill includes automated validation as **Stage 0**:

```bash
# Stage 0: Automated Validation (runs FIRST)
./hooks/security-validator.sh || exit 1
./hooks/load-test-validator.sh || exit 1
./hooks/performance-validator.sh || echo "WARNING: Performance targets not met"

# Stage 1: Infrastructure Setup (only if Stage 0 passes)
docker-compose up -d
...
```

---

## Installation & Setup

### 1. Ensure Hooks are Executable

```bash
chmod +x hooks/security-validator.sh
chmod +x hooks/load-test-validator.sh
chmod +x hooks/performance-validator.sh
```

### 2. Install Recommended Tools

```bash
# k6 for load testing
brew install k6

# Trivy for container security
brew install trivy

# Gitleaks for secrets detection
brew install gitleaks

# Semgrep for SAST (optional)
pip install semgrep
```

### 3. Add Load Tests to TARGET

Create one of:
- `k6-load-test.js` (recommended)
- `artillery.yml`
- `locustfile.py`
- npm script: `"load:test"`

### 4. Add Performance Requirements to PRD

Add to `docs/PRD.md`:
```markdown
## Performance Requirements

- Latency p95: < 200ms
- Throughput: 1000 req/sec
```

---

## Troubleshooting

### Security Validator Fails

**Issue:** `npm audit` fails with high vulnerabilities

**Solution:**
```bash
# View detailed vulnerabilities
npm audit

# Fix automatically (if possible)
npm audit fix

# Force fix (breaking changes possible)
npm audit fix --force

# Re-run validator
./hooks/security-validator.sh
```

---

### Load Test Validator Can't Find Tests

**Issue:** "No load test framework detected"

**Solution:** Create a load test file (see examples above)

---

### Performance Validator Skipped

**Issue:** "No performance requirements found in PRD"

**This is OK** - If PRD doesn't specify performance targets, validation is skipped

**To add requirements:** Add performance section to `docs/PRD.md`

---

## Benefits

### Before (Manual Checklists)

❌ Security: Manual checkbox - trust but not verified
❌ Load Testing: Manual checkbox - might not run
❌ Performance: Manual checkbox - no validation

**Risk:** Deploy without actually validating

### After (Automated Validators)

✅ Security: Actual scans run automatically
✅ Load Testing: Tests execute automatically
✅ Performance: Metrics validated against PRD

**Result:** Cannot deploy without passing validation

---

## Comparison: Functional vs Non-Functional

### Functional Testing (Already Strong)

- ✅ TDD enforcement (RED-GREEN-REFACTOR)
- ✅ Integration point coverage (100% required)
- ✅ E2E workflow validation
- ✅ Unit test coverage gates

### Non-Functional Testing (NOW Strong)

- ✅ Security scanning (automated)
- ✅ Load testing (automated)
- ✅ Performance validation (automated)
- ⚠️ Resilience testing (future)
- ⚠️ Observability validation (future)

**Overall Pipeline Capability:** 🟢 **STRONG (85%)** - Up from 65%

---

## Next Steps (Priority 2)

To further improve, add:

1. **Alert Testing**
   ```bash
   hooks/alert-validator.sh
   # Triggers alerts and validates they fire
   ```

2. **Rollback Testing**
   ```bash
   hooks/rollback-validator.sh
   # Validates rollback procedure works
   ```

3. **Observability Validation**
   ```bash
   hooks/observability-validator.sh
   # Validates logs/metrics are collected
   ```

---

## References

- **Audit Report:** `audit-reports/DEPLOYMENT-VALIDATION-AUDIT.md`
- **Integration Guide:** `skills/integration-validator/SKILL.md`
- **Deployment Guide:** `skills/deployment-orchestrator/SKILL.md`
