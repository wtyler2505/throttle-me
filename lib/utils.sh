#!/bin/bash
# lib/utils.sh - Common utilities and sudo caching for throttle-me
# shellcheck disable=SC2310

set -euo pipefail

# Sudo credential caching
SUDO_CACHE_PID=""

# Start sudo credential cache
start_sudo_cache() {
    # Try to refresh sudo timestamp
    # In TUI mode, this may fail if no terminal - that's OK
    if ! sudo -v 2>/dev/null; then
        log_warn "Could not cache sudo credentials (will prompt when needed)"
        return 0  # Non-fatal - just means user will be prompted later
    fi
    
    # Start background process to keep sudo alive
    (
        while true; do
            sleep 60
            sudo -n true 2>/dev/null || exit 1
        done
    ) &
    
    SUDO_CACHE_PID=$!
    log_debug "Started sudo cache (PID: ${SUDO_CACHE_PID})"
}

# Stop sudo credential cache
stop_sudo_cache() {
    if [[ -n "${SUDO_CACHE_PID}" ]]; then
        kill "${SUDO_CACHE_PID}" 2>/dev/null || true
        log_debug "Stopped sudo cache"
    fi
    sudo -k  # Clear sudo timestamp
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if dialog is installed, install if missing
ensure_dialog() {
    if ! command_exists dialog; then
        log_warn "Dialog not installed, attempting to install..."
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y dialog
            log_info "Dialog installed successfully"
        else
            log_error "Cannot install dialog: apt-get not found"
            return 1
        fi
    fi
}

# Launch the rich Textual dashboard. Falls back to classic dialog UI if unavailable.
launch_dashboard() {
    local dashboard_dir=""
    local candidate
    local candidates=(
        "${SCRIPT_DIR}/dashboard"
        "${HOME}/.local/share/throttle-me/dashboard"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}/pyproject.toml" ]]; then
            dashboard_dir="${candidate}"
            break
        fi
    done

    if [[ -z "${dashboard_dir}" ]]; then
        log_warn "Dashboard package not found; launching classic UI"
        start_sudo_cache
        start_tui
        return $?
    fi

    if command_exists uv; then
        THROTTLE_ME_ROOT="${SCRIPT_DIR}" uv run --project "${dashboard_dir}" throttle-me-dashboard "$@"
        return $?
    fi

    if ! command_exists python3; then
        log_warn "python3 not found; launching classic UI"
        start_sudo_cache
        start_tui
        return $?
    fi

    local venv_dir="${dashboard_dir}/.venv"
    if [[ ! -x "${venv_dir}/bin/throttle-me-dashboard" ]]; then
        python3 -m venv "${venv_dir}"
        "${venv_dir}/bin/python" -m pip install --upgrade pip
        "${venv_dir}/bin/python" -m pip install "${dashboard_dir}"
    fi

    THROTTLE_ME_ROOT="${SCRIPT_DIR}" "${venv_dir}/bin/throttle-me-dashboard" "$@"
}

# Get the script directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "${source}" ]]; do
        local dir
        dir="$(cd -P "$(dirname "${source}")" && pwd)"
        source="$(readlink "${source}")"
        [[ ${source} != /* ]] && source="${dir}/${source}"
    done
    cd -P "$(dirname "${source}")/.." && pwd
}

# Version information
THROTTLE_ME_VERSION="2.0.0-alpha"
THROTTLE_ME_DATE="2025-10-17"

# Show version
show_version() {
    echo "throttle-me v${THROTTLE_ME_VERSION} (${THROTTLE_ME_DATE})"
    echo "Carrier hotspot throttling bypass manager"
}
