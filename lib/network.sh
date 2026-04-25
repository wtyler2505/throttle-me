#!/bin/bash
# lib/network.sh - Network interface detection for throttle-me
# shellcheck disable=SC2310

set -euo pipefail

# Detect active wireless interface
detect_wireless_interface() {
    local iface=""

    # Check for config override first
    if [[ -n "${CONFIG[INTERFACE_OVERRIDE]:-}" ]]; then
        echo "${CONFIG[INTERFACE_OVERRIDE]}"
        return 0
    fi

    # Method 1: Use ip command (modern approach)
    iface=$(ip -brief link show 2>/dev/null | awk '/UP.*wl/ {print $1}' | head -1)

    # Method 2: Fallback to iwconfig (older systems)
    if [[ -z "${iface}" ]]; then
        iface=$(iwconfig 2>&1 | grep -o '^[^ ]*' | grep -E '^wl' | head -1)
    fi

    # Method 3: Check common wireless interface patterns
    if [[ -z "${iface}" ]]; then
        for pattern in wlo1 wlan0 wlp*s0; do
            if ip link show "${pattern}" &>/dev/null && ip link show "${pattern}" | grep -q "state UP"; then
                iface="${pattern}"
                break
            fi
        done
    fi

    if [[ -z "${iface}" ]]; then
        log_warn "No active wireless interface detected"
        return 1
    fi

    log_debug "Detected wireless interface: ${iface}"
    echo "${iface}"
}

# Get current SSID for an interface
get_current_ssid() {
    local iface=${1:-$(detect_wireless_interface)}
    local ssid=""

    if [[ -z "${iface}" ]]; then
        return 1
    fi

    # Method 1: Use iwgetid (most reliable)
    if command -v iwgetid &>/dev/null; then
        ssid=$(iwgetid "${iface}" -r 2>/dev/null)
    fi

    # Method 2: Use nmcli (NetworkManager)
    if [[ -z "${ssid}" ]] && command -v nmcli &>/dev/null; then
        ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2 | head -1)
    fi

    # Method 3: Parse iwconfig output
    if [[ -z "${ssid}" ]]; then
        ssid=$(iwconfig "${iface}" 2>/dev/null | grep -oP 'ESSID:"\K[^"]+')
    fi

    if [[ -z "${ssid}" ]]; then
        log_debug "No SSID detected for ${iface}"
        return 1
    fi

    log_debug "Current SSID: ${ssid}"
    echo "${ssid}"
}

# Check if interface is up
is_interface_up() {
    local iface=${1:-$(detect_wireless_interface)}

    if [[ -z "${iface}" ]]; then
        return 1
    fi

    ip link show "${iface}" 2>/dev/null | grep -q "state UP"
}

# Get gateway IP for interface
get_gateway_ip() {
    local iface=${1:-$(detect_wireless_interface)}

    if [[ -z "${iface}" ]]; then
        return 1
    fi

    ip route 2>/dev/null | grep "default.*${iface}" | awk '{print $3}' | head -1
}

# Show network info
show_network_info() {
    local iface ssid gateway

    iface=$(detect_wireless_interface) || {
        echo "No wireless interface detected"
        return 1
    }

    ssid=$(get_current_ssid "${iface}") || ssid="Not connected"
    gateway=$(get_gateway_ip "${iface}") || gateway="N/A"

    echo "=== NETWORK INFORMATION ==="
    echo ""
    echo "Interface: ${iface}"
    echo "SSID: ${ssid}"
    echo "Gateway: ${gateway}"

    if is_interface_up "${iface}"; then
        echo "Status: UP"
    else
        echo "Status: DOWN"
    fi
}
