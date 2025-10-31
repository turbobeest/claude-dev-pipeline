# Test Fixtures

This directory contains test data and fixtures for the Claude Dev Pipeline test suite.

## Files

### Sample Project Data
- **`sample-prd.md`** - Complete PRD for user authentication system
- **`sample-tasks.json`** - Generated tasks with coupling analysis
- **`sample-openspec-proposal.md`** - API specification proposal

### Test State Files
- **`test-state-clean.json`** - Clean initial state
- **`test-state-phase1.json`** - State after Phase 1 completion
- **`test-state-complete.json`** - State after full pipeline completion

### Mock Data
- **`mock-hook-inputs.json`** - Sample inputs for hook testing
- **`invalid-tasks.json`** - Malformed tasks.json for error testing

## Usage

These fixtures are used by the test suites to:

1. **Provide realistic test data** - Sample PRD and tasks represent real-world scenarios
2. **Test state transitions** - State files test different pipeline phases  
3. **Validate error handling** - Invalid data tests error scenarios
4. **Mock hook inputs** - Standardized inputs for hook testing

## Test Scenarios Covered

### Happy Path
- Complete pipeline execution from PRD to deployment
- Proper phase transitions and signal emissions
- Successful skill activations

### Error Scenarios  
- Malformed JSON inputs
- Invalid task structures
- Missing required fields
- State corruption recovery

### Edge Cases
- Empty context files
- Duplicate task IDs
- Invalid phase names
- Circular dependencies

## File Formats

All JSON files follow strict schemas:

### State File Schema
```json
{
  "phase": "string",
  "completedTasks": ["array", "of", "strings"],
  "signals": {"signal_name": timestamp},
  "lastActivation": "string",
  "lastSignal": "string",
  "metadata": {"optional": "object"}
}
```

### Tasks File Schema
```json
{
  "project": "string",
  "total_tasks": number,
  "tasks": [
    {
      "id": number,
      "title": "string", 
      "description": "string",
      "phase": number,
      "dependencies": [array],
      "coupling": "tight|loose"
    }
  ]
}
```

## Maintenance

When adding new fixtures:

1. Follow naming convention: `[type]-[scenario].ext`
2. Include realistic data that matches production scenarios
3. Add documentation for the test scenario covered
4. Validate JSON files with `jq` before committing
5. Update this README with new fixture descriptions

## Validation

To validate all JSON fixtures:

```bash
find fixtures/ -name "*.json" -exec jq . {} \; > /dev/null
```

This ensures all JSON files are well-formed before use in tests.