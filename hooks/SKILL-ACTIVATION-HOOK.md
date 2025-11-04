# Skill Activation Hook Documentation

## Overview

The `skill-activation-prompt.sh` hook is the **intelligent orchestrator** of the entire automated development pipeline. It bridges user intent with skill execution through a sophisticated codeword injection system.

## Architecture

```
User Message
     ↓
Hook receives stdin JSON: {"message": "..."}
     ↓
┌─────────────────────────────────────┐
│  Pattern Matching Engine            │
│  - Reads skill-rules.json            │
│  - Matches user patterns             │
│  - Checks file prerequisites         │
└─────────────────────────────────────┘
     ↓
┌─────────────────────────────────────┐
│  Signal Detection Engine             │
│  - Monitors .claude/.signals/        │
│  - Detects phase completion          │
│  - Chains next skill automatically   │
└─────────────────────────────────────┘
     ↓
┌─────────────────────────────────────┐
│  Codeword Injection                  │
│  Outputs: {"injectedText":           │
│   "[ACTIVATE:SKILL_CODE_V1]"}        │
└─────────────────────────────────────┘
     ↓
Claude Code sees codeword → Loads skill
```

## How It Works

### 1. User Pattern Matching

User says: **"Generate tasks from my PRD"**

Hook:
1. Extracts message from stdin JSON
2. Converts to lowercase: `"generate tasks from my prd"`
3. Reads `config/skill-rules.json`
4. Finds skill with matching pattern: `"generate tasks"` → `PRD_TO_TASKS_V1`
5. Checks file requirements: `docs/PRD.md` exists?
6. Injects codeword: `{"injectedText": "[ACTIVATE:PRD_TO_TASKS_V1]"}`

### 2. Signal-Based Chaining

Skill completes and emits signal: `.claude/.signals/tasks-generated.json`

Hook (on next user message):
1. Detects recent signal (modified < 60 seconds ago)
2. Reads `skill-rules.json` → phase_transitions
3. Finds: `TASKS_GENERATED` → next = `TASK_REVIEW_GATE_V1`
4. Auto-injects: `{"injectedText": "[ACTIVATE:TASK_REVIEW_GATE_V1]"}`

### 3. Workflow State Management

Hook updates `.claude/.workflow-state.json`:
```json
{
  "phase": "1",
  "lastActivation": "PRD_TO_TASKS_V1",
  "context": {
    "activeSkills": ["PRD_TO_TASKS_V1"]
  },
  "metadata": {
    "lastUpdated": "2025-11-04T20:00:00Z"
  }
}
```

## Configuration: skill-rules.json

### Skill Definition

```json
{
  "skill": "prd-to-tasks",
  "activation_code": "PRD_TO_TASKS_V1",
  "phase": 1,
  "trigger_conditions": {
    "user_patterns": [
      "generate tasks",
      "parse prd",
      "create tasks"
    ],
    "file_patterns": [
      "PRD.md",
      "docs/PRD.md"
    ]
  },
  "outputs": {
    "signals": ["TASKS_GENERATED"],
    "next_activation": "TASK_REVIEW_GATE_V1"
  }
}
```

### Phase Transition

```json
{
  "phase_transitions": {
    "TASKS_GENERATED": {
      "next_activation": "TASK_REVIEW_GATE_V1",
      "auto_trigger": true,
      "delay_seconds": 1
    }
  }
}
```

## Complete Workflow Example

### Phase 1: PRD to Tasks

```
User: "Generate tasks from my PRD"
  ↓
Hook matches: "generate tasks" → PRD_TO_TASKS_V1
  ↓
Hook checks: docs/PRD.md exists ✓
  ↓
Hook detects: Large PRD (31K tokens) → Warns to use large-file-reader
  ↓
Hook injects: [ACTIVATE:PRD_TO_TASKS_V1]
  ↓
Claude loads: skills/PRD-to-Tasks/SKILL.md
  ↓
Skill executes:
  - Runs: ./lib/large-file-reader.sh docs/PRD.md
  - Generates: 27 master tasks (no subtasks)
  - Writes: .taskmaster/tasks/tasks.json
  - Emits: .claude/.signals/tasks-generated.json
```

### Phase 1.2: Task Review (User Interaction)

```
Hook detects: tasks-generated.json signal
  ↓
Hook chains: [ACTIVATE:TASK_REVIEW_GATE_V1]
  ↓
Claude loads: skills/task-review-gate/SKILL.md
  ↓
Skill shows: Generated tasks for review
  ↓
User: "Tasks look good, proceed"
  ↓
Skill emits: .claude/.signals/tasks-approved.json
```

### Phase 1.5: Coupling Analysis

```
Hook detects: tasks-approved.json signal
  ↓
Hook chains: [ACTIVATE:COUPLING_ANALYSIS_V1]
  ↓
Skill analyzes: Task relationships
  ↓
Skill emits: .claude/.signals/coupling-analyzed.json
```

### Phase 1: Task Decomposition

```
Hook detects: coupling-analyzed.json signal
  ↓
Hook chains: [ACTIVATE:TASK_DECOMPOSER_V1]
  ↓
Skill executes:
  - task-master analyze-complexity --research
  - Identifies high-complexity tasks (score ≥7)
  - task-master expand --id=X --research (for complex only)
  - Emits: .claude/.signals/phase1-complete.json
```

### Phase 2: Continues automatically...

The hook continues chaining through all 6 phases based on signals.

## Testing the Hook

### Test Pattern Matching

```bash
echo '{"message":"generate tasks from my PRD"}' | ./hooks/skill-activation-prompt.sh
# Expected output:
# {
#   "injectedText": "[ACTIVATE:PRD_TO_TASKS_V1]",
#   "reason": "User pattern matched"
# }
```

### Test Signal Detection

```bash
# Create a test signal
mkdir -p .claude/.signals
echo '{"status":"complete"}' > .claude/.signals/tasks-generated.json

# Trigger hook
echo '{"message":"continue"}' | ./hooks/skill-activation-prompt.sh
# Expected: [ACTIVATE:TASK_REVIEW_GATE_V1]
```

### Test Logging

```bash
tail -f .claude/logs/skill-activations.log
# Shows all pattern matches, signal detections, and activations
```

## Debugging

### Enable Verbose Logging

The hook logs to `.claude/logs/skill-activations.log`:

```
[2025-11-04 20:00:15] [INFO] Processing activation request
[2025-11-04 20:00:15] [INFO] Pattern matched: 'generate tasks' -> PRD_TO_TASKS_V1
[2025-11-04 20:00:15] [DEBUG] File pattern matched: docs/PRD.md
[2025-11-04 20:00:15] [INFO] Activating skill: PRD_TO_TASKS_V1
[2025-11-04 20:00:15] [INFO] Updated workflow state: phase=1, skill=PRD_TO_TASKS_V1
```

### Common Issues

**Issue: "No matching skill pattern"**
- Check: skill-rules.json has the pattern defined
- Check: User message contains the pattern
- Fix: Add pattern to skill's `user_patterns` array

**Issue: "File requirements not met"**
- Check: Required file exists (e.g., docs/PRD.md)
- Check: File path is correct in skill-rules.json
- Fix: Create the required file or adjust file_patterns

**Issue: "Signal not detected"**
- Check: Signal file exists in .claude/.signals/
- Check: Signal file modified < 60 seconds ago
- Check: phase_transitions configured for this signal
- Fix: Skills must emit signals using Write tool

## Key Features

### 1. Dynamic Configuration
- Reads skill-rules.json at runtime
- No hardcoded skill names in hook
- Easy to add new skills without modifying hook

### 2. Intelligent Chaining
- Detects signals automatically
- Chains skills based on phase_transitions
- Maintains workflow state

### 3. Large File Awareness
- Detects PRDs > 25K tokens
- Warns to use large-file-reader
- Prevents Read tool failures

### 4. Workflow Tracking
- Updates .workflow-state.json
- Tracks current phase
- Records skill activations

### 5. Robust Error Handling
- Gracefully handles missing files
- Logs all decisions
- Falls back to manual operation

## Integration with Skills

### Skills MUST:

1. **Emit signals** when complete:
```bash
# In skill execution:
mkdir -p .claude/.signals
cat > .claude/.signals/tasks-generated.json <<EOF
{
  "signal": "TASKS_GENERATED",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": 1,
  "status": "success"
}
EOF
```

2. **Match codewords** in skill frontmatter:
```markdown
---
activation_code: PRD_TO_TASKS_V1
---
```

3. **Follow skill-rules.json** contract:
- Defined in `skills` array
- Proper phase assignment
- User patterns for manual activation
- Signal emissions for chaining

## Performance

- **Hook execution**: < 100ms
- **Pattern matching**: O(n) where n = number of patterns
- **Signal detection**: O(1) filesystem check
- **Workflow state update**: O(1) JSON update

## Future Enhancements

Potential improvements:
1. **Priority-based activation** - Multiple matching skills
2. **Parallel skill execution** - Independent tasks
3. **Retry logic** - Failed skill activations
4. **Metrics collection** - Track activation patterns
5. **A/B testing** - Different skill implementations

## See Also

- [Skill Rules Configuration](../config/skill-rules.json)
- [PRD-to-Tasks Skill](../skills/PRD-to-Tasks/SKILL.md)
- [Task Decomposer Skill](../skills/task-decomposer/SKILL.md)
- [Workflow State Schema](../.claude/.workflow-state.json)
