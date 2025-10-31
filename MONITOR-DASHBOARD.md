# Pipeline Monitoring Dashboard

A low-complexity, real-time web dashboard for monitoring the Claude Dev Pipeline execution.

## Features

✨ **Real-time Task Monitoring**
- Live view of TaskMaster hierarchical structure
- Master tasks with expandable subtasks
- Color-coded status indicators
- Progress statistics

📊 **Visual Status Tracking**
- Pending (gray)
- In Progress (green)
- Complete (bright green)
- Auto-updates every 2 seconds

📝 **Live Log Streaming**
- Tail pipeline logs in real-time
- Color-coded log levels (errors, warnings, success, info)
- Auto-scrolling (with manual override)
- Last 100 lines buffered

📈 **Statistics Dashboard**
- Total master tasks
- Total subtasks
- Completed count
- Overall progress percentage

## Quick Start

### 1. Start the Dashboard

From your project root:

```bash
python3 /path/to/claude-dev-pipeline/monitor-dashboard.py
```

Or if the pipeline is installed in your project:

```bash
python3 .claude/monitor-dashboard.py
```

### 2. Open Browser

```
http://localhost:8888
```

### 3. Monitor Pipeline

The dashboard will automatically:
- Load tasks from `.taskmaster/tasks/tasks.json`
- Stream logs from `.taskmaster/pipeline.log`
- Update every 0.5-2 seconds

## Screenshot Preview

```
┌─────────────────────────────────────────────────────────────────┐
│ 🔄 Pipeline Monitor              ● Monitoring  Last: 10:23:45   │
├────────────────────────────────┬────────────────────────────────┤
│ TASK HIERARCHY                 │ LIVE LOGS                      │
│                                │                                │
│ ▼ Task 1: Docker Setup    ✅   │ ℹ️ Starting pipeline...        │
│   1. Create Compose       ✅   │ ✅ Task 1.1 completed          │
│   2. Configure env        🟢   │ ℹ️ Running Task 1.2...         │
│   3. Build containers     ⚪   │ ⚠️ Warning: slow build        │
│                                │ ✅ Build successful            │
│ ▶ Task 2: User Auth       ⚪   │ ℹ️ Starting Task 2...          │
│                                │                                │
│ ▶ Task 3: API Endpoints   ⚪   │ [Logs auto-scroll here]        │
│                                │                                │
├────────────────────────────────┴────────────────────────────────┤
│  10          45          32          71%                        │
│  Master      Subtasks    Complete    Progress                  │
└─────────────────────────────────────────────────────────────────┘
```

## How It Works

### Architecture

```
monitor-dashboard.py (Single Python file)
  ↓
  Serves embedded HTML/CSS/JS
  ↓
  Three API endpoints:
    - /api/tasks  → Returns tasks.json
    - /api/logs   → Returns last 100 log lines
    - /api/status → Returns server status
  ↓
  Browser polls APIs every 0.5-2 seconds
  ↓
  Updates UI in real-time
```

### No Dependencies!

- ✅ Uses only Python standard library
- ✅ No npm install required
- ✅ No build step
- ✅ Single file deployment
- ✅ Works on any Python 3.6+

### Technology Stack

**Backend:**
- Python 3 `http.server` (built-in)
- JSON API endpoints
- File system monitoring

**Frontend:**
- Pure HTML/CSS/JavaScript (embedded)
- No frameworks required
- Polling-based updates (simple, reliable)
- VS Code-inspired dark theme

## Configuration

### Port

Default: `8888`

Change in `monitor-dashboard.py`:
```python
PORT = 8888  # Change to desired port
```

### Polling Intervals

In the HTML JavaScript section:
```javascript
setInterval(fetchTasks, 2000);  // Tasks: 2 seconds
setInterval(fetchLogs, 500);    // Logs: 0.5 seconds
```

### Log Buffer Size

Currently shows last 100 lines. Change in `serve_logs()`:
```python
last_lines = ''.join(lines[-100:])  # Change 100 to desired count
```

## Usage Examples

### Monitoring Active Pipeline

```bash
# Terminal 1: Run pipeline
cd your-project
claude

# Terminal 2: Start dashboard
python3 .claude/monitor-dashboard.py

# Browser: http://localhost:8888
```

### Monitoring Completed Pipeline

```bash
# View tasks and logs from previous run
python3 .claude/monitor-dashboard.py
```

The dashboard works with any existing `.taskmaster/tasks/tasks.json` file.

## Features in Detail

### Task Hierarchy View

**Master Tasks:**
- Click header to expand/collapse
- Shows overall status (pending/in-progress/complete)
- Calculated from subtask statuses

**Subtasks:**
- Individual status indicators
- Numbered (1.1, 1.2, etc.)
- Descriptive titles

**Status Colors:**
- ⚪ Pending - Gray
- 🟢 In Progress - Green
- ✅ Complete - Bright green

### Live Logs

**Auto-Scrolling:**
- Automatically scrolls to newest logs
- Detects manual scroll - stops auto-scroll
- Scroll to bottom to re-enable auto-scroll

**Color Coding:**
- 🔴 Errors: Red (`ERROR`, `❌`)
- 🟡 Warnings: Yellow (`WARNING`, `⚠️`)
- 🟢 Success: Green (`SUCCESS`, `✅`)
- 🔵 Info: Blue (`INFO`, `ℹ️`)

**Performance:**
- Limits to 1000 log lines in browser
- Prevents memory issues on long runs
- Older logs automatically pruned

### Statistics

**Real-time Metrics:**
1. **Master Tasks** - Total count from tasks.json
2. **Subtasks** - Sum of all subtasks
3. **Completed** - Count of completed subtasks
4. **Progress** - Percentage complete

**Progress Calculation:**
```
Progress = (Completed Subtasks / Total Subtasks) × 100
```

## Advanced Usage

### Custom Project Root

If tasks.json is in a different location:

```python
# Edit monitor-dashboard.py
PROJECT_ROOT = '/path/to/your/project'
```

### Multiple Projects

Run multiple dashboards on different ports:

```bash
# Project 1
PORT=8888 python3 monitor-dashboard.py

# Project 2
PORT=8889 python3 monitor-dashboard.py
```

### Reverse Proxy

For remote access (be careful with security):

```nginx
# Nginx config
location /pipeline-monitor/ {
    proxy_pass http://localhost:8888/;
}
```

## Troubleshooting

### Port Already in Use

```bash
# Error: Address already in use
```

**Solution:** Change port or kill existing process
```bash
lsof -ti:8888 | xargs kill -9
```

### Tasks Not Showing

**Check:**
1. Does `.taskmaster/tasks/tasks.json` exist?
2. Is it valid JSON?
3. Does it have the TaskMaster hierarchical format?

**Debug:**
```bash
# Validate tasks.json
cat .taskmaster/tasks/tasks.json | jq .
```

### Logs Not Updating

**Check:**
1. Does `.taskmaster/pipeline.log` exist?
2. Is the pipeline actually running/writing logs?

**Debug:**
```bash
# Check if log file exists
ls -la .taskmaster/pipeline.log

# Tail logs manually
tail -f .taskmaster/pipeline.log
```

### Browser Console Errors

**Open Developer Tools:**
- Chrome/Edge: F12 or Cmd+Option+I (Mac)
- Check Console tab for JavaScript errors

**Common Issues:**
- CORS errors (shouldn't happen with localhost)
- JSON parse errors (invalid tasks.json)
- Network errors (server not running)

## Future Enhancements

**Possible additions (low complexity maintained):**

1. **DAG Visualization** (vis.js network graph)
   - Show task dependencies as directed graph
   - Visual representation of parallel vs sequential tasks

2. **Task Duration Tracking**
   - Time per task/subtask
   - Estimated completion time

3. **Filter/Search**
   - Filter tasks by status
   - Search logs by keyword

4. **Export**
   - Download tasks as JSON
   - Export logs as text file

5. **Notifications**
   - Browser notifications on completion
   - Desktop alerts on errors

## Comparison with Command Line

### Before (CLI Monitoring)

```bash
# Manual checking required
cat .taskmaster/tasks/tasks.json | jq .
tail -f .taskmaster/pipeline.log
taskmaster show

# Multiple terminals
# Hard to see overall status
# No visual indicators
```

### After (Dashboard)

```bash
# One command
python3 .claude/monitor-dashboard.py

# One browser window
# Visual status at a glance
# Live updates
# No terminal juggling
```

## Performance

**Resource Usage:**
- Memory: ~20-30MB (Python process)
- CPU: <1% (polling only)
- Network: ~1-2KB/s (local polling)

**Scalability:**
- Tested with 50+ tasks
- Handles 1000+ log lines smoothly
- No database required
- No state management

## Security Notes

**Local Development Only:**
- Binds to `localhost` only (not 0.0.0.0)
- No authentication (assumes trusted environment)
- No HTTPS (local traffic only)

**For Production Use:**
- Add authentication
- Enable HTTPS
- Implement proper security headers
- Consider rate limiting

## License

Part of Claude Dev Pipeline - same license as parent project.

## Contributing

Suggestions for enhancements:
1. Keep complexity low (single file preferred)
2. No build steps
3. Minimal dependencies
4. Works cross-platform

## See Also

- **Pipeline Documentation:** `README.md`
- **TaskMaster Format:** `skills/PRD-to-Tasks/SKILL.md`
- **Logging System:** Check `.taskmaster/pipeline.log`
