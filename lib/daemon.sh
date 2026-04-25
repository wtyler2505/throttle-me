#!/bin/bash
# lib/daemon.sh - Daemon management functions for throttle-me
# shellcheck disable=SC2310

set -euo pipefail

# Daemon configuration
DAEMON_SERVICE="throttle-me-daemon.service"
DAEMON_SCRIPT="${HOME}/.local/bin/throttle-me-daemon"
DAEMON_STATE_FILE="${HOME}/.config/throttle-me/daemon.state"
DAEMON_LOCK_FILE="${HOME}/.cache/throttle-me/daemon.lock"

# Check if daemon is currently running
is_daemon_running() {
    systemctl --user is-active "${DAEMON_SERVICE}" &>/dev/null
}

# Get daemon PID if running
get_daemon_pid() {
    if [[ -f "${DAEMON_LOCK_FILE}" ]]; then
        cat "${DAEMON_LOCK_FILE}" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Start the daemon
daemon_start() {
    if is_daemon_running; then
        echo "Daemon is already running"
        return 0
    fi
    
    log_info "Starting throttle-me daemon..."
    
    if systemctl --user start "${DAEMON_SERVICE}" 2>/dev/null; then
        sleep 1
        if is_daemon_running; then
            echo "✅ Daemon started successfully"
            log_info "Daemon started"
            return 0
        else
            echo "❌ Daemon failed to start"
            echo "Check logs: journalctl --user -u ${DAEMON_SERVICE} -n 20"
            return 1
        fi
    else
        echo "❌ Failed to start daemon"
        echo "Service may not be installed. Run: throttle-me --install-daemon"
        return 1
    fi
}

# Stop the daemon
daemon_stop() {
    if ! is_daemon_running; then
        echo "Daemon is not running"
        return 0
    fi
    
    log_info "Stopping throttle-me daemon..."
    
    if systemctl --user stop "${DAEMON_SERVICE}" 2>/dev/null; then
        sleep 1
        if ! is_daemon_running; then
            echo "✅ Daemon stopped successfully"
            log_info "Daemon stopped"
            return 0
        else
            echo "❌ Daemon failed to stop"
            return 1
        fi
    else
        echo "❌ Failed to stop daemon"
        return 1
    fi
}

# Enable daemon auto-start on login
daemon_enable() {
    log_info "Enabling daemon auto-start..."
    
    if systemctl --user enable "${DAEMON_SERVICE}" 2>/dev/null; then
        echo "✅ Daemon will start automatically on login"
        log_info "Daemon auto-start enabled"
        return 0
    else
        echo "❌ Failed to enable daemon auto-start"
        return 1
    fi
}

# Disable daemon auto-start
daemon_disable() {
    log_info "Disabling daemon auto-start..."
    
    if systemctl --user disable "${DAEMON_SERVICE}" 2>/dev/null; then
        echo "✅ Daemon auto-start disabled"
        log_info "Daemon auto-start disabled"
        return 0
    else
        echo "❌ Failed to disable daemon auto-start"
        return 1
    fi
}

# Get daemon status
daemon_status() {
    echo "=== DAEMON STATUS ==="
    echo ""
    
    # Check if service is installed
    if ! systemctl --user list-unit-files "${DAEMON_SERVICE}" &>/dev/null; then
        echo "Status: NOT INSTALLED"
        echo ""
        echo "Run 'throttle-me --install-daemon' to install ${DAEMON_SCRIPT}"
        return 1
    fi
    
    # Running status
    if is_daemon_running; then
        echo "Status: RUNNING ✅"
        
        local pid
        pid=$(get_daemon_pid)
        if [[ -n "${pid}" ]]; then
            echo "PID: ${pid}"
        fi
        
        # Uptime
        local start_time
        start_time=$(systemctl --user show -p ActiveEnterTimestamp "${DAEMON_SERVICE}" | cut -d= -f2)
        if [[ -n "${start_time}" ]]; then
            echo "Started: ${start_time}"
        fi
    else
        echo "Status: STOPPED ❌"
    fi
    
    # Auto-start status
    if systemctl --user is-enabled "${DAEMON_SERVICE}" &>/dev/null; then
        echo "Auto-start: ENABLED ✅"
    else
        echo "Auto-start: DISABLED ❌"
    fi
    
    echo ""
    
    # Current state from state file
    if [[ -f "${DAEMON_STATE_FILE}" ]]; then
        echo "=== CURRENT STATE ==="
        echo ""
        source "${DAEMON_STATE_FILE}"
        echo "Last SSID: ${LAST_SSID:-none}"
        echo "Bypass Active: ${BYPASS_ACTIVE:-unknown}"
        if [[ -n "${LAST_CHECK:-}" ]]; then
            local check_time
            check_time=$(date -d "@${LAST_CHECK}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            echo "Last Check: ${check_time}"
        fi
        echo ""
    fi
    
    # Show recent logs
    echo "=== RECENT LOGS (last 5 entries) ==="
    echo ""
    journalctl --user -u "${DAEMON_SERVICE}" -n 5 --no-pager 2>/dev/null || echo "No logs available"
}

# Show daemon info for TUI
show_daemon_info() {
    if is_daemon_running; then
        echo "Daemon: RUNNING ✅"
        
        local pid
        pid=$(get_daemon_pid)
        if [[ -n "${pid}" ]]; then
            echo "PID: ${pid}"
        fi
    else
        echo "Daemon: STOPPED ❌"
    fi
    
    if systemctl --user is-enabled "${DAEMON_SERVICE}" &>/dev/null; then
        echo "Auto-start: Enabled"
    else
        echo "Auto-start: Disabled"
    fi
}

# Restart daemon
daemon_restart() {
    log_info "Restarting throttle-me daemon..."
    
    if systemctl --user restart "${DAEMON_SERVICE}" 2>/dev/null; then
        sleep 1
        if is_daemon_running; then
            echo "✅ Daemon restarted successfully"
            log_info "Daemon restarted"
            return 0
        else
            echo "❌ Daemon failed to restart"
            return 1
        fi
    else
        echo "❌ Failed to restart daemon"
        return 1
    fi
}

# Show daemon logs
daemon_logs() {
    local lines=${1:-20}
    echo "=== DAEMON LOGS (last ${lines} entries) ==="
    echo ""
    journalctl --user -u "${DAEMON_SERVICE}" -n "${lines}" --no-pager 2>/dev/null || {
        echo "No logs available"
        return 1
    }
}

# Follow daemon logs in real-time
daemon_logs_follow() {
    echo "Following daemon logs (Ctrl+C to stop)..."
    echo ""
    journalctl --user -u "${DAEMON_SERVICE}" -f 2>/dev/null || {
        echo "Failed to access logs"
        return 1
    }
}
