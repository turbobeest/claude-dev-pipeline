# Claude Dev Pipeline - Test Suite

Comprehensive testing framework for the Claude Dev Pipeline system, including hook validation, skill activation testing, and end-to-end workflow simulation.

## Overview

This test suite provides complete coverage of:

- **Hook functionality** - Pre/post tool use hooks and skill activation
- **Skill activation logic** - Pattern matching, signal detection, phase transitions  
- **Full workflow simulation** - End-to-end pipeline execution
- **Error handling** - Invalid inputs, malformed data, recovery scenarios
- **State management** - Persistence, corruption recovery, concurrent access
- **Integration testing** - Cross-component interaction validation

## Quick Start

```bash
# Run all tests
./run-tests.sh

# Run specific test suite
./run-tests.sh hooks
./run-tests.sh skills  
./run-tests.sh workflow

# Run with options
./run-tests.sh -v all                    # Verbose output
./run-tests.sh -p all                    # Parallel execution
./run-tests.sh -f workflow              # Fail-fast mode
```

## Test Suites

### 1. Hook Tests (`test-hooks.sh`)

Tests all pipeline hooks for:
- Input validation and sanitization
- JSON parsing and error handling  
- Timeout behavior and resource limits
- File locking mechanisms
- TDD enforcement (pre-implementation validator)
- Signal emission and state updates

**Usage:**
```bash
./test-hooks.sh                          # Run all hook tests
./test-hooks.sh skill-activation         # Test skill activation hook only
./test-hooks.sh -v post-tool-use         # Verbose post-tool-use tests
```

### 2. Skill Activation Tests (`test-skill-activation.sh`)

Tests skill activation logic including:
- User message pattern matching (case-insensitive, partial matches)
- File pattern matching (exact, wildcard, path-based)
- Signal-based activation and detection
- Phase transition automation
- Priority handling and duplicate prevention
- State persistence and recovery

**Usage:**
```bash
./test-skill-activation.sh               # Run all activation tests
./test-skill-activation.sh user-patterns # Test user pattern matching only
./test-skill-activation.sh -q signals    # Test signal detection quietly
```

### 3. Full Workflow Tests (`test-full-workflow.sh`)

End-to-end pipeline simulation covering:
- Complete 6-phase pipeline execution
- Manual gate handling and user confirmations
- GO/NO-GO decision points
- Rollback and recovery scenarios
- Concurrent execution safety
- State persistence across phases
- Signal flow validation

**Usage:**
```bash
./test-full-workflow.sh                  # Run complete workflow tests
./test-full-workflow.sh phase1           # Test Phase 1 only
./test-full-workflow.sh -v complete      # Verbose complete pipeline test
```

## Test Runner (`run-tests.sh`)

Orchestrates execution of all test suites with:
- Sequential or parallel execution
- Consolidated reporting (text + HTML)
- CI/CD integration support
- Fail-fast mode for rapid feedback
- Environment isolation and cleanup

**Usage:**
```bash
./run-tests.sh [OPTIONS] [SUITE] [ARGS]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress most output  
    -p, --parallel      Run tests in parallel
    -f, --fail-fast     Stop on first failure
    --no-html           Skip HTML report generation
    --no-clean          Don't clean before running

SUITES:
    hooks               Hook tests only
    skills              Skill activation tests only
    workflow            Workflow tests only
    all                 All test suites (default)
```

## Test Data (`fixtures/`)

Comprehensive test fixtures including:
- **`sample-prd.md`** - Realistic product requirements document
- **`sample-tasks.json`** - Generated tasks with coupling analysis
- **`sample-openspec-proposal.md`** - API specification example
- **`test-state-*.json`** - State files for different pipeline phases
- **`mock-hook-inputs.json`** - Standardized inputs for hook testing
- **`invalid-*.json`** - Malformed data for error testing

## Reports and Logging

Test execution generates:

### Text Reports
- `reports/summary.txt` - Overall execution summary
- `reports/hooks-report.txt` - Hook test results
- `reports/skill-activation-report.txt` - Skill activation results  
- `reports/workflow-report.txt` - Workflow test results

### HTML Report
- `reports/test-report.html` - Interactive HTML dashboard with:
  - Pass/fail statistics and progress bars
  - Suite-by-suite breakdown
  - Detailed output collapsible sections
  - Responsive design for mobile viewing

### Logs
- `logs/test-runner.log` - Detailed execution log
- `logs/*.log` - Individual test suite logs

## Environment Variables

Control test execution with environment variables:

```bash
VERBOSE=true ./run-tests.sh              # Enable verbose output
QUIET=true ./run-tests.sh                # Suppress output
PARALLEL=true ./run-tests.sh             # Enable parallel execution
FAIL_FAST=true ./run-tests.sh            # Stop on first failure
GENERATE_HTML=false ./run-tests.sh       # Skip HTML report
CLEAN_BEFORE=false ./run-tests.sh        # Skip cleanup
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Run Pipeline Tests
  run: |
    cd tests
    ./run-tests.sh -q -f all
    
- name: Upload Test Reports
  uses: actions/upload-artifact@v3
  if: always()
  with:
    name: test-reports
    path: tests/reports/
```

### Jenkins

```groovy
stage('Test') {
    steps {
        sh 'cd tests && ./run-tests.sh -q -f all'
    }
    post {
        always {
            publishHTML([
                allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'tests/reports',
                reportFiles: 'test-report.html',
                reportName: 'Pipeline Test Report'
            ])
        }
    }
}
```

## Test Coverage

Current test coverage includes:

### Hook Tests (75+ test cases)
- ✅ Skill activation pattern matching
- ✅ Signal emission and detection
- ✅ TDD validation enforcement
- ✅ JSON parsing and error handling
- ✅ Timeout and resource management
- ✅ File locking and concurrent access
- ✅ State file integrity

### Skill Activation Tests (60+ test cases)
- ✅ User pattern matching (exact, partial, case-insensitive)
- ✅ File pattern matching (wildcard, path-based)
- ✅ Signal-based activation
- ✅ Phase transition automation
- ✅ Priority ordering and deduplication
- ✅ State management and persistence
- ✅ Error recovery and graceful degradation

### Workflow Tests (50+ test cases)
- ✅ Phase-by-phase progression (Phases 1-6)
- ✅ Manual gate interactions
- ✅ GO/NO-GO decision handling
- ✅ Rollback and recovery scenarios
- ✅ Concurrent execution safety
- ✅ Complete end-to-end pipeline
- ✅ Cross-component integration

## Development and Maintenance

### Adding New Tests

1. **Hook Tests**: Add test functions to `test-hooks.sh`
   ```bash
   test_new_hook_functionality() {
       # Test implementation
   }
   ```

2. **Skill Tests**: Add to `test-skill-activation.sh`
   ```bash
   test_new_activation_logic() {
       # Test implementation  
   }
   ```

3. **Workflow Tests**: Add to `test-full-workflow.sh`
   ```bash
   test_new_workflow_scenario() {
       # Test implementation
   }
   ```

### Test Fixtures

Add new test data to `fixtures/`:
- Follow naming convention: `[type]-[scenario].[ext]`
- Validate JSON files: `jq . fixtures/new-file.json`
- Update `fixtures/README.md` with descriptions

### Best Practices

1. **Isolation**: Each test should be independent
2. **Cleanup**: Always clean up temp files and state
3. **Assertions**: Use descriptive assertion messages
4. **Fixtures**: Use realistic test data
5. **Documentation**: Update README for new test scenarios

## Troubleshooting

### Common Issues

**Tests fail with permission errors:**
```bash
chmod +x tests/*.sh
```

**Parallel tests fail:**
```bash
# Run sequentially for debugging
./run-tests.sh --no-parallel -v all
```

**State corruption errors:**
```bash
# Clean and retry
./run-tests.sh --clean all
```

**Missing dependencies:**
```bash
# Ensure jq and timeout are available
which jq timeout
```

### Debug Mode

Enable debug mode for detailed troubleshooting:
```bash
VERBOSE=true ./run-tests.sh -v workflow 2>&1 | tee debug.log
```

## Performance

Typical execution times:
- Hook tests: ~30 seconds
- Skill activation tests: ~25 seconds  
- Workflow tests: ~45 seconds
- **Total sequential**: ~100 seconds
- **Total parallel**: ~50 seconds

Optimize test execution:
- Use parallel mode: `-p` flag
- Run specific suites: `hooks`, `skills`, `workflow`
- Use fail-fast: `-f` flag for rapid feedback

## Security Considerations

Test scripts follow security best practices:
- No execution of user-provided code
- Temporary files in isolated directories
- Proper cleanup of sensitive test data
- File permission validation
- Input sanitization testing

The test suite itself validates security features:
- TDD enforcement prevents unsafe implementation
- Input validation testing
- Error handling verification
- State corruption recovery

---

For more information, see individual test file documentation and the main pipeline README.