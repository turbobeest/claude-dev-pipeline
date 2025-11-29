# Use Existing Tasks

Skip PRD parsing and use an existing tasks.json file to proceed directly to complexity analysis.

## When to Use

Use this command when:
- You already have a tasks.json file (manually created or from a previous run)
- The PRD is too large for the LLM to process
- You want to resume from an existing task breakdown

## Prerequisites

- `.taskmaster/tasks/tasks.json` must exist with valid task structure
- Tasks should have: id, title, description, status fields

## Execution Steps

### Step 1: Validate tasks.json exists

```bash
if [ -f ".taskmaster/tasks/tasks.json" ]; then
  echo "✅ tasks.json found"
  task_count=$(jq '.tasks | length' .taskmaster/tasks/tasks.json 2>/dev/null || echo "0")
  echo "📊 Found $task_count tasks"
else
  echo "❌ No tasks.json found at .taskmaster/tasks/tasks.json"
  echo "Please create tasks.json first or use /parse-prd"
  exit 1
fi
```

### Step 2: Validate task structure

```bash
# Check for required fields
jq -e '.tasks[0] | has("id") and has("title") and has("description")' .taskmaster/tasks/tasks.json > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Task structure valid"
else
  echo "⚠️ Task structure may be incomplete - proceeding anyway"
fi
```

### Step 3: Display task summary

```bash
echo ""
echo "📋 Task Summary:"
jq -r '.tasks[] | "  \(.id). \(.title) [\(.status // "todo")]"' .taskmaster/tasks/tasks.json | head -20
echo ""
```

### Step 4: Proceed to complexity analysis

Output the activation codeword to trigger the next phase:

```
✅ Using existing tasks.json - skipping PRD parsing

[ACTIVATE:COUPLING_ANALYSIS_V1]

Next: Complexity analysis will determine which tasks need subtask expansion.
```

## What Happens Next

1. **Coupling Analysis** - Analyzes task dependencies and identifies parallel work opportunities
2. **Task Decomposer** - Expands high-complexity tasks into subtasks
3. **Phase 2+** - Continues autonomously through specs, implementation, testing, and deployment
