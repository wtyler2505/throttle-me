#!/bin/bash
# lib/logging.sh - Centralized logging and error handling for throttle-me

set -euo pipefail

# Log levels
declare -r LOG_ERROR=1
declare -r LOG_WARN=2
declare -r LOG_INFO=3
declare -r LOG_DEBUG=4

# Default log configuration
LOG_LEVEL="${LOG_LEVEL:-${LOG_INFO}}"
LOG_FILE="${LOG_FILE:-/tmp/throttle-me.log}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"

# Colors for terminal output
declare -r RED='\033[0;31m'
declare -r YELLOW='\033[1;33m'
declare -r GREEN='\033[0;32m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m' # No Color

# Internal logging function
_log() {
    local level=$1
    local level_name=$2
    local color=$3
    local message=$4
    
    # Check if we should log this level
    if [[ ${level} -gt ${LOG_LEVEL} ]]; then
        return 0
    fi
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format: [TIMESTAMP] [LEVEL] message
    local log_line="[${timestamp}] [${level_name}] ${message}"
    
    # Write to file if enabled
    if [[ "${LOG_TO_FILE}" == "true" ]]; then
        echo "${log_line}" >> "${LOG_FILE}"
    fi
    
    # Write to terminal with color
    echo -e "${color}[${level_name}]${NC} ${message}" >&2
}

# Public logging functions
log_error() {
    _log "${LOG_ERROR}" "ERROR" "${RED}" "$1"
}

log_warn() {
    _log "${LOG_WARN}" "WARN" "${YELLOW}" "$1"
}

log_info() {
    _log "${LOG_INFO}" "INFO" "${GREEN}" "$1"
}

log_debug() {
    _log "${LOG_DEBUG}" "DEBUG" "${BLUE}" "$1"
}

# Error handler for trap
error_handler() {
    local exit_code=$1
    local line_number=$2
    local command=$3
    
    log_error "Command failed with exit code ${exit_code} at line ${line_number}: ${command}"
    log_error "See ${LOG_FILE} for details"
}

# Cleanup handler for trap
cleanup() {
    local exit_code=$?
    
    if [[ ${exit_code} -eq 0 ]]; then
        log_debug "Script exited successfully"
    else
        log_error "Script exited with code ${exit_code}"
    fi
}

# Initialize logging
initialize_logging() {
    # Create log file if it doesn't exist
    if [[ "${LOG_TO_FILE}" == "true" ]]; then
        touch "${LOG_FILE}" 2>/dev/null || {
            LOG_FILE="/tmp/throttle-me.log"
            log_warn "Cannot write to ${LOG_FILE}, using /tmp/throttle-me.log"
        }
    fi
    
    log_debug "Logging initialized: level=${LOG_LEVEL}, file=${LOG_FILE}"
}
