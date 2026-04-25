#!/bin/bash
# lib/config.sh - Configuration management for throttle-me

set -euo pipefail

# Default configuration
declare -A CONFIG=(
    [TTL_VALUE]=65
    [HL_VALUE]=65
    [DNS_SERVER]="1.1.1.1"
    [LOG_LEVEL]=3  # INFO
    [LOG_FILE]="/var/log/throttle-me.log"
    [CONFIRM_ENABLE]=true
    [CONFIRM_DISABLE]=true
    [BYPASS_SCRIPT]="$HOME/.local/bin/bypass-tethering"
    [DISABLE_SCRIPT]="$HOME/.local/bin/disable-bypass-tethering"
    [AUTO_ENABLE]=false
    [MAX_SESSIONS]=100
    [MAX_AGE_DAYS]=30
    [INTERFACE_OVERRIDE]=""
    [POLL_INTERVAL]=5
    [HOTSPOT_PATTERNS]="iPhone* AndroidAP* *Galaxy*"
    [SPEED_TEST_TIMEOUT]=30
    [NOTIFICATION_URGENCY]="normal"
)

# Config file locations (in priority order)
CONFIG_FILES=(
    "$HOME/.config/throttle-me/config"
    "$HOME/.throttle-me.conf"
    "/etc/throttle-me.conf"
)

# Load configuration from file
load_config() {
    local config_file=""
    
    # Find first existing config file
    for file in "${CONFIG_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            config_file="$file"
            break
        fi
    done
    
    if [[ -z "$config_file" ]]; then
        log_debug "No config file found, using defaults"
        return 0
    fi
    
    log_debug "Loading config from: $config_file"
    
    # Source config file
    # shellcheck disable=SC1090
    source "$config_file"
    
    # Override defaults with loaded values
    [[ -n "${TTL_VALUE:-}" ]] && CONFIG[TTL_VALUE]=$TTL_VALUE
    [[ -n "${HL_VALUE:-}" ]] && CONFIG[HL_VALUE]=$HL_VALUE
    [[ -n "${DNS_SERVER:-}" ]] && CONFIG[DNS_SERVER]=$DNS_SERVER
    [[ -n "${LOG_LEVEL:-}" ]] && CONFIG[LOG_LEVEL]=$LOG_LEVEL
    [[ -n "${LOG_FILE:-}" ]] && CONFIG[LOG_FILE]=$LOG_FILE
    [[ -n "${CONFIRM_ENABLE:-}" ]] && CONFIG[CONFIRM_ENABLE]=$CONFIRM_ENABLE
    [[ -n "${CONFIRM_DISABLE:-}" ]] && CONFIG[CONFIRM_DISABLE]=$CONFIRM_DISABLE
    [[ -n "${BYPASS_SCRIPT:-}" ]] && CONFIG[BYPASS_SCRIPT]=$BYPASS_SCRIPT
    [[ -n "${DISABLE_SCRIPT:-}" ]] && CONFIG[DISABLE_SCRIPT]=$DISABLE_SCRIPT
    [[ -n "${AUTO_ENABLE:-}" ]] && CONFIG[AUTO_ENABLE]=$AUTO_ENABLE
    [[ -n "${MAX_SESSIONS:-}" ]] && CONFIG[MAX_SESSIONS]=$MAX_SESSIONS
    [[ -n "${MAX_AGE_DAYS:-}" ]] && CONFIG[MAX_AGE_DAYS]=$MAX_AGE_DAYS
    [[ -n "${INTERFACE_OVERRIDE:-}" ]] && CONFIG[INTERFACE_OVERRIDE]=$INTERFACE_OVERRIDE
    [[ -n "${POLL_INTERVAL:-}" ]] && CONFIG[POLL_INTERVAL]=$POLL_INTERVAL
    [[ -n "${HOTSPOT_PATTERNS:-}" ]] && CONFIG[HOTSPOT_PATTERNS]=$HOTSPOT_PATTERNS
    [[ -n "${SPEED_TEST_TIMEOUT:-}" ]] && CONFIG[SPEED_TEST_TIMEOUT]=$SPEED_TEST_TIMEOUT
    [[ -n "${NOTIFICATION_URGENCY:-}" ]] && CONFIG[NOTIFICATION_URGENCY]=$NOTIFICATION_URGENCY
    
    log_info "Configuration loaded from $config_file"
}

# Get config value
get_config() {
    local key=$1
    echo "${CONFIG[$key]}"
}

# Set config value (runtime only, not persisted)
set_config() {
    local key=$1
    local value=$2
    CONFIG[$key]=$value
}

# Show current configuration
show_config() {
    echo "Current Configuration:"
    echo "  TTL Value: ${CONFIG[TTL_VALUE]}"
    echo "  IPv6 Hop Limit: ${CONFIG[HL_VALUE]}"
    echo "  DNS Server: ${CONFIG[DNS_SERVER]}"
    echo "  Log Level: ${CONFIG[LOG_LEVEL]}"
    echo "  Log File: ${CONFIG[LOG_FILE]}"
    echo "  Confirm Enable: ${CONFIG[CONFIRM_ENABLE]}"
    echo "  Confirm Disable: ${CONFIG[CONFIRM_DISABLE]}"
    echo "  Bypass Script: ${CONFIG[BYPASS_SCRIPT]}"
    echo "  Disable Script: ${CONFIG[DISABLE_SCRIPT]}"
    echo "  Auto-Enable Hotspot: ${CONFIG[AUTO_ENABLE]}"
    echo "  Max Session History: ${CONFIG[MAX_SESSIONS]}"
    echo "  Max Age (Days): ${CONFIG[MAX_AGE_DAYS]}"
    echo "  Interface Override: ${CONFIG[INTERFACE_OVERRIDE]:-auto-detect}"
    echo "  Poll Interval: ${CONFIG[POLL_INTERVAL]}"
    echo "  Hotspot Patterns: ${CONFIG[HOTSPOT_PATTERNS]}"
    echo "  Speed Test Timeout: ${CONFIG[SPEED_TEST_TIMEOUT]}"
    echo "  Notification Urgency: ${CONFIG[NOTIFICATION_URGENCY]}"
}
