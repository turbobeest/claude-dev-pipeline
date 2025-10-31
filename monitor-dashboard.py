#!/usr/bin/env python3
"""
Pipeline Monitoring Dashboard
Simple web server that displays tasks.json structure and live logs
"""

import json
import os
import time
import threading
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

# Configuration
PORT = 8888
PROJECT_ROOT = os.getcwd()
TASKS_FILE = os.path.join(PROJECT_ROOT, '.taskmaster', 'tasks', 'tasks.json')
LOG_FILE = os.path.join(PROJECT_ROOT, '.taskmaster', 'pipeline.log')
MONITOR_DIR = os.path.join(os.path.dirname(__file__), 'monitor')

class DashboardHandler(SimpleHTTPRequestHandler):
    """Custom handler for dashboard requests"""

    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)

        if parsed_path.path == '/':
            self.serve_dashboard()
        elif parsed_path.path == '/api/tasks':
            self.serve_tasks_json()
        elif parsed_path.path == '/api/logs':
            self.serve_logs()
        elif parsed_path.path == '/api/status':
            self.serve_status()
        else:
            super().do_GET()

    def serve_dashboard(self):
        """Serve the main dashboard HTML"""
        html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pipeline Monitor</title>
    <script src="https://unpkg.com/vis-network@9.1.2/standalone/umd/vis-network.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Courier New', monospace;
            background: #1e1e1e;
            color: #d4d4d4;
            height: 100vh;
            overflow: hidden;
        }

        #header {
            background: #252526;
            padding: 15px 20px;
            border-bottom: 1px solid #3e3e42;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        #header h1 {
            font-size: 18px;
            font-weight: 600;
            color: #4ec9b0;
        }

        #status {
            display: flex;
            gap: 20px;
            font-size: 12px;
        }

        .status-item {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
        }

        .status-dot.active {
            background: #4ec9b0;
            box-shadow: 0 0 8px #4ec9b0;
        }

        .status-dot.inactive {
            background: #666;
        }

        #container {
            display: flex;
            height: calc(100vh - 51px);
        }

        #left-panel {
            flex: 1;
            display: flex;
            flex-direction: column;
            border-right: 1px solid #3e3e42;
        }

        #right-panel {
            width: 500px;
            display: flex;
            flex-direction: column;
        }

        .panel-header {
            background: #2d2d30;
            padding: 10px 15px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: #999;
            border-bottom: 1px solid #3e3e42;
        }

        #graph {
            flex: 1;
            background: #1e1e1e;
        }

        #task-list {
            flex: 1;
            overflow-y: auto;
            padding: 15px;
        }

        .master-task {
            margin-bottom: 20px;
            background: #252526;
            border-radius: 4px;
            border: 1px solid #3e3e42;
        }

        .master-task-header {
            padding: 12px 15px;
            font-weight: 600;
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: pointer;
            user-select: none;
        }

        .master-task-header:hover {
            background: #2d2d30;
        }

        .task-name {
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .task-status {
            font-size: 10px;
            padding: 3px 8px;
            border-radius: 3px;
            text-transform: uppercase;
            font-weight: 600;
        }

        .task-status.pending {
            background: #3e3e42;
            color: #999;
        }

        .task-status.in-progress {
            background: #1a472a;
            color: #4ec9b0;
        }

        .task-status.complete {
            background: #1a472a;
            color: #6fc89f;
        }

        .subtask-list {
            padding: 0 15px 12px 15px;
            display: none;
        }

        .master-task.expanded .subtask-list {
            display: block;
        }

        .subtask {
            padding: 8px 12px;
            margin: 4px 0;
            background: #1e1e1e;
            border-radius: 3px;
            font-size: 13px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .subtask:hover {
            background: #2d2d30;
        }

        #logs {
            flex: 1;
            background: #1e1e1e;
            overflow-y: auto;
            padding: 15px;
            font-size: 12px;
            line-height: 1.6;
        }

        .log-line {
            padding: 2px 0;
            font-family: 'SF Mono', monospace;
        }

        .log-line.error {
            color: #f48771;
        }

        .log-line.warning {
            color: #dcdcaa;
        }

        .log-line.success {
            color: #4ec9b0;
        }

        .log-line.info {
            color: #9cdcfe;
        }

        #stats {
            padding: 15px;
            background: #252526;
            border-top: 1px solid #3e3e42;
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 15px;
            font-size: 11px;
        }

        .stat {
            text-align: center;
        }

        .stat-value {
            font-size: 24px;
            font-weight: 600;
            margin-bottom: 5px;
        }

        .stat-label {
            color: #999;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .expand-icon {
            transition: transform 0.2s;
        }

        .master-task.expanded .expand-icon {
            transform: rotate(90deg);
        }

        /* Scrollbar styling */
        ::-webkit-scrollbar {
            width: 10px;
        }

        ::-webkit-scrollbar-track {
            background: #1e1e1e;
        }

        ::-webkit-scrollbar-thumb {
            background: #3e3e42;
            border-radius: 5px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: #4e4e52;
        }
    </style>
</head>
<body>
    <div id="header">
        <h1>🔄 Pipeline Monitor</h1>
        <div id="status">
            <div class="status-item">
                <div class="status-dot active" id="status-indicator"></div>
                <span id="status-text">Monitoring</span>
            </div>
            <div class="status-item">
                <span id="update-time">Last update: --:--:--</span>
            </div>
        </div>
    </div>

    <div id="container">
        <div id="left-panel">
            <div class="panel-header">Task Hierarchy</div>
            <div id="task-list"></div>
            <div id="stats">
                <div class="stat">
                    <div class="stat-value" id="total-tasks">0</div>
                    <div class="stat-label">Master Tasks</div>
                </div>
                <div class="stat">
                    <div class="stat-value" id="total-subtasks">0</div>
                    <div class="stat-label">Subtasks</div>
                </div>
                <div class="stat">
                    <div class="stat-value" id="completed-tasks">0</div>
                    <div class="stat-label">Completed</div>
                </div>
                <div class="stat">
                    <div class="stat-value" id="progress">0%</div>
                    <div class="stat-label">Progress</div>
                </div>
            </div>
        </div>

        <div id="right-panel">
            <div class="panel-header">Live Logs</div>
            <div id="logs"></div>
        </div>
    </div>

    <script>
        let logsContainer = document.getElementById('logs');
        let taskListContainer = document.getElementById('task-list');
        let logLines = [];
        let autoScroll = true;

        // Check if logs should auto-scroll
        logsContainer.addEventListener('scroll', () => {
            const isAtBottom = logsContainer.scrollHeight - logsContainer.scrollTop <= logsContainer.clientHeight + 50;
            autoScroll = isAtBottom;
        });

        // Fetch and display tasks
        async function fetchTasks() {
            try {
                const response = await fetch('/api/tasks');
                const data = await response.json();

                if (data.master && data.master.tasks) {
                    renderTasks(data.master.tasks);
                    updateStats(data.master.tasks);
                }

                updateTimestamp();
            } catch (error) {
                console.error('Error fetching tasks:', error);
            }
        }

        function renderTasks(tasks) {
            taskListContainer.innerHTML = '';

            tasks.forEach(task => {
                const taskDiv = document.createElement('div');
                taskDiv.className = 'master-task';

                const status = getTaskStatus(task);

                taskDiv.innerHTML = `
                    <div class="master-task-header">
                        <div class="task-name">
                            <span class="expand-icon">▶</span>
                            <span>Task ${task.id}: ${task.name}</span>
                        </div>
                        <span class="task-status ${status}">${status}</span>
                    </div>
                    <div class="subtask-list">
                        ${renderSubtasks(task.subtasks || [])}
                    </div>
                `;

                taskDiv.querySelector('.master-task-header').addEventListener('click', () => {
                    taskDiv.classList.toggle('expanded');
                });

                taskListContainer.appendChild(taskDiv);
            });
        }

        function renderSubtasks(subtasks) {
            return subtasks.map(subtask => {
                const status = subtask.status || 'pending';
                return `
                    <div class="subtask">
                        <span>${subtask.id}. ${subtask.title}</span>
                        <span class="task-status ${status}">${status}</span>
                    </div>
                `;
            }).join('');
        }

        function getTaskStatus(task) {
            if (!task.subtasks || task.subtasks.length === 0) {
                return task.status || 'pending';
            }

            const allComplete = task.subtasks.every(st => st.status === 'complete');
            const anyInProgress = task.subtasks.some(st => st.status === 'in-progress');

            if (allComplete) return 'complete';
            if (anyInProgress) return 'in-progress';
            return 'pending';
        }

        function updateStats(tasks) {
            const totalTasks = tasks.length;
            const totalSubtasks = tasks.reduce((sum, task) => sum + (task.subtasks?.length || 0), 0);

            let completedSubtasks = 0;
            tasks.forEach(task => {
                if (task.subtasks) {
                    completedSubtasks += task.subtasks.filter(st => st.status === 'complete').length;
                }
            });

            const progress = totalSubtasks > 0 ? Math.round((completedSubtasks / totalSubtasks) * 100) : 0;

            document.getElementById('total-tasks').textContent = totalTasks;
            document.getElementById('total-subtasks').textContent = totalSubtasks;
            document.getElementById('completed-tasks').textContent = completedSubtasks;
            document.getElementById('progress').textContent = progress + '%';
        }

        // Fetch and display logs
        async function fetchLogs() {
            try {
                const response = await fetch('/api/logs');
                const text = await response.text();

                if (text) {
                    const lines = text.split('\\n').filter(line => line.trim());

                    // Only add new lines
                    const newLines = lines.slice(logLines.length);
                    logLines = lines;

                    newLines.forEach(line => {
                        const logDiv = document.createElement('div');
                        logDiv.className = 'log-line';

                        // Color code based on content
                        if (line.includes('ERROR') || line.includes('❌')) {
                            logDiv.className += ' error';
                        } else if (line.includes('WARNING') || line.includes('⚠️')) {
                            logDiv.className += ' warning';
                        } else if (line.includes('SUCCESS') || line.includes('✅')) {
                            logDiv.className += ' success';
                        } else if (line.includes('INFO') || line.includes('ℹ️')) {
                            logDiv.className += ' info';
                        }

                        logDiv.textContent = line;
                        logsContainer.appendChild(logDiv);
                    });

                    // Auto-scroll if user is at bottom
                    if (autoScroll) {
                        logsContainer.scrollTop = logsContainer.scrollHeight;
                    }

                    // Limit log lines to prevent memory issues
                    while (logsContainer.children.length > 1000) {
                        logsContainer.removeChild(logsContainer.firstChild);
                    }
                }
            } catch (error) {
                console.error('Error fetching logs:', error);
            }
        }

        function updateTimestamp() {
            const now = new Date();
            const timeStr = now.toLocaleTimeString();
            document.getElementById('update-time').textContent = `Last update: ${timeStr}`;
        }

        // Initial load
        fetchTasks();
        fetchLogs();

        // Poll for updates
        setInterval(fetchTasks, 2000);  // Update tasks every 2 seconds
        setInterval(fetchLogs, 500);    // Update logs every 0.5 seconds
    </script>
</body>
</html>"""

        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

    def serve_tasks_json(self):
        """Serve tasks.json content"""
        try:
            if os.path.exists(TASKS_FILE):
                with open(TASKS_FILE, 'r') as f:
                    tasks_data = json.load(f)
            else:
                # Return empty structure if file doesn't exist
                tasks_data = {"master": {"tasks": []}}

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(tasks_data).encode())
        except Exception as e:
            self.send_error(500, f'Error reading tasks: {str(e)}')

    def serve_logs(self):
        """Serve last N lines of log file"""
        try:
            if os.path.exists(LOG_FILE):
                # Read last 100 lines
                with open(LOG_FILE, 'r') as f:
                    lines = f.readlines()
                    last_lines = ''.join(lines[-100:])
            else:
                last_lines = "No logs available yet.\n"

            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(last_lines.encode())
        except Exception as e:
            self.send_error(500, f'Error reading logs: {str(e)}')

    def serve_status(self):
        """Serve pipeline status"""
        status = {
            'tasks_file_exists': os.path.exists(TASKS_FILE),
            'log_file_exists': os.path.exists(LOG_FILE),
            'timestamp': time.time()
        }

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(status).encode())

    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

def main():
    """Start the monitoring server"""
    print("=" * 70)
    print("Pipeline Monitoring Dashboard")
    print("=" * 70)
    print(f"\n🚀 Starting server on http://localhost:{PORT}")
    print(f"📂 Monitoring directory: {PROJECT_ROOT}")
    print(f"📋 Tasks file: {TASKS_FILE}")
    print(f"📝 Log file: {LOG_FILE}")
    print("\n" + "=" * 70)
    print(f"\n✨ Open your browser to: http://localhost:{PORT}")
    print("\n💡 Press Ctrl+C to stop the server\n")

    server = HTTPServer(('localhost', PORT), DashboardHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n🛑 Shutting down server...")
        server.shutdown()
        print("✅ Server stopped\n")

if __name__ == '__main__':
    main()
