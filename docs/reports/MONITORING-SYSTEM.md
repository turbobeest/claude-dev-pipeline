# Claude Dev Pipeline - Monitoring and Logging System

## Overview

A comprehensive logging, monitoring, and alerting system for the Claude Dev Pipeline that provides real-time visibility into pipeline operations, performance metrics, and health status.

## Core Components

### 1. Structured Logging System (`lib/logger.sh`)

**Features:**
- **JSON and Text Formats**: Configurable output format
- **Log Levels**: DEBUG, INFO, WARN, ERROR, FATAL with filtering
- **Log Rotation**: Automatic rotation at 10MB with 30-day retention
- **Context Injection**: Automatic timestamp, caller info, phase, and task tracking
- **Performance Timing**: Built-in timer functions for duration tracking
- **Multiple Outputs**: Console and file logging with color support

**Usage:**
```bash
source lib/logger.sh

log_info "Pipeline started" "phase=validation"
log_error "Task failed" "task_id=123" "error_code=500"
start_timer "validation"
# ... work ...
duration=$(stop_timer "validation")
```

### 2. Performance Metrics System (`lib/metrics.sh`)

**Features:**
- **Phase Tracking**: Monitor phase start/end times and status
- **Resource Monitoring**: CPU, memory, disk usage tracking
- **Success/Failure Rates**: Task outcome statistics
- **Health Scoring**: Automated health score calculation
- **Performance History**: Historical performance data
- **JSON Export**: Export metrics for external analysis

**Usage:**
```bash
source lib/metrics.sh

metrics_track_phase_start "validation"
metrics_track_phase_end "validation" "success"
metrics_collect_system_stats
metrics_generate_report
```

### 3. Real-time Dashboard (`pipeline-dashboard.sh`)

**Features:**
- **Live Monitoring**: Watch mode with configurable refresh intervals
- **Health Status**: Overall pipeline health with visual indicators
- **Current Phase**: Active phase tracking with duration
- **Recent Activity**: Live log streaming with color coding
- **System Resources**: CPU, memory, disk usage with progress bars
- **Task Statistics**: Success rates and performance metrics
- **JSON Output**: Machine-readable status export

**Usage:**
```bash
./pipeline-dashboard.sh                    # Single snapshot
./pipeline-dashboard.sh --watch            # Live monitoring
./pipeline-dashboard.sh --json             # JSON output
./pipeline-dashboard.sh --compact          # Compact view
```

### 4. Alerts and Monitoring (`lib/alerts.sh`)

**Features:**
- **Stuck Phase Detection**: Timeout monitoring with configurable thresholds
- **Repeated Failure Alerts**: Alert on consecutive failures
- **Resource Warnings**: CPU, memory, disk usage alerts
- **Health Score Monitoring**: Alert on low health scores
- **Multiple Notification Methods**: Terminal, email, webhook support
- **Rate Limiting**: Prevent alert spam
- **Escalation**: Warning and critical thresholds

**Usage:**
```bash
source lib/alerts.sh

alerts_start_monitoring 60  # 60-second intervals
alerts_notify "error" "Pipeline Failed" "Task validation failed"
alerts_check_stuck_phases
```

### 5. Unified Control Interface (`monitor.sh`)

**Features:**
- **Centralized Control**: Single interface for all monitoring components
- **Status Monitoring**: Real-time status of all components
- **Service Management**: Start/stop monitoring services
- **Testing**: Built-in system testing
- **Log Management**: Access to different log types

**Usage:**
```bash
./monitor.sh start                        # Start all monitoring
./monitor.sh status                       # Check status
./monitor.sh dashboard --watch            # Launch dashboard
./monitor.sh alerts test                  # Test alerts
./monitor.sh logs tail                    # View live logs
./monitor.sh metrics report               # Generate report
```

## Directory Structure

```
/Users/jamesterbeest/dev/claude-dev-pipeline/
├── lib/
│   ├── logger.sh                        # Core logging system
│   ├── metrics.sh                       # Performance metrics
│   └── alerts.sh                        # Monitoring alerts
├── logs/
│   ├── pipeline.log                     # Main application log
│   ├── error.log                        # Error-only log
│   ├── metrics.log                      # Metrics log
│   ├── metrics/                         # Metrics data files
│   │   ├── metrics_data.json
│   │   ├── performance_history.json
│   │   ├── system_stats.json
│   │   └── health_score.json
│   └── alerts/                          # Alerts data files
│       ├── alerts.log
│       ├── alerts_config.json
│       └── alerts_state.json
├── pipeline-dashboard.sh                # CLI dashboard
└── monitor.sh                           # Control interface
```

## Integration with Existing Scripts

The monitoring system has been integrated into key pipeline scripts:

- **setup.sh**: Enhanced with performance tracking and structured logging
- **validate.sh**: Updated to use the logging system
- **health-check.sh**: Integrated with metrics and health scoring

All scripts now provide:
- Structured logging with context
- Performance metrics collection
- Error tracking and alerts
- Health status reporting

## Configuration

### Logger Configuration
```bash
# Environment variables
export LOG_LEVEL="INFO"                  # DEBUG, INFO, WARN, ERROR, FATAL
export LOG_FORMAT="JSON"                 # JSON or TEXT
export LOG_TO_CONSOLE="true"
export LOG_TO_FILE="true"
```

### Metrics Configuration
```bash
# Monitoring intervals
SYSTEM_STATS_INTERVAL=5                  # System stats collection
PERFORMANCE_WINDOW_HOURS=24              # Performance history window
```

### Alerts Configuration
```bash
# Thresholds
PHASE_TIMEOUT_WARN=300                   # 5 minutes
PHASE_TIMEOUT_CRITICAL=900               # 15 minutes
CPU_THRESHOLD_WARN=80                    # 80%
MEMORY_THRESHOLD_WARN=85                 # 85%
HEALTH_SCORE_WARN=70                     # Below 70
```

## Health Scoring Algorithm

The system calculates a health score (0-100) based on:
- **CPU Usage** (40% weight): Performance impact
- **Memory Usage** (60% weight): Resource availability
- **Phase Duration**: Detects stuck phases
- **Error Rates**: Failure frequency
- **System Responsiveness**: Overall system health

## Alert Notifications

### Terminal Notifications
- macOS: `osascript` notifications
- Linux: `notify-send` notifications  
- Console: Always available colored alerts

### Email Notifications (Optional)
- SMTP configuration in `alerts_config.json`
- HTML formatted messages
- Retry logic for reliability

### Webhook Notifications (Optional)
- JSON payload to configurable endpoint
- Retry with exponential backoff
- Custom headers support

## Performance Features

- **Log Rotation**: Automatic rotation at 10MB
- **Data Retention**: 30-day default retention
- **Background Monitoring**: Non-blocking system monitoring
- **Rate Limiting**: Prevents alert spam
- **Efficient Queries**: Optimized JSON processing
- **Minimal Overhead**: Lightweight monitoring impact

## Testing

The system includes comprehensive testing:

```bash
./monitor.sh test                        # Test all components
./monitor.sh alerts test                 # Test alert system
./pipeline-dashboard.sh --json           # Test dashboard
```

## Monitoring Best Practices

1. **Start monitoring early**: Use `./monitor.sh start` before pipeline operations
2. **Watch the dashboard**: Use `./pipeline-dashboard.sh --watch` for live monitoring
3. **Check health regularly**: Monitor health scores and investigate drops
4. **Review logs**: Use `./monitor.sh logs tail` to watch activity
5. **Configure alerts**: Set appropriate thresholds for your environment
6. **Export metrics**: Regular exports for trend analysis
7. **Clean up data**: Use `./monitor.sh metrics cleanup` periodically

## Troubleshooting

### Common Issues

1. **Permission errors**: Ensure log directories are writable
2. **Missing dependencies**: Install `jq`, `bc` for full functionality
3. **Performance impact**: Adjust monitoring intervals if needed
4. **Alert spam**: Configure rate limiting appropriately
5. **Log rotation**: Monitor disk space usage

### Debug Mode

Enable verbose logging for troubleshooting:
```bash
export LOG_LEVEL="DEBUG"
./monitor.sh --verbose [command]
```

## Future Enhancements

- **Database Integration**: Store metrics in time-series database
- **Web Dashboard**: Browser-based monitoring interface
- **Advanced Analytics**: Trend analysis and predictions
- **Integration APIs**: REST endpoints for external monitoring
- **Custom Metrics**: User-defined metrics and thresholds
- **Distributed Monitoring**: Multi-node pipeline monitoring

## Summary

This monitoring system provides enterprise-level observability for the Claude Dev Pipeline with:

- **Real-time visibility** into all pipeline operations
- **Proactive alerting** for issues before they become critical
- **Performance insights** for optimization opportunities
- **Historical tracking** for trend analysis
- **Easy integration** with existing pipeline scripts
- **Minimal overhead** and resource usage

The system is designed to be lightweight, reliable, and extensible while providing comprehensive monitoring capabilities essential for production pipeline operations.