#!/bin/bash
# lib/detection.sh - Hotspot auto-detection for throttle-me
# shellcheck disable=SC2154,SC2310

set -euo pipefail

# Check if SSID matches mobile hotspot patterns
is_mobile_hotspot() {
    local ssid=$1

    # Common mobile hotspot patterns
    local patterns=(
        "iPhone"
        "iPad"
        "Android"
        "AndroidAP"
        "Mobile Hotspot"
        "Hotspot"
        ".*'s iPhone"
        ".*'s iPad"
    )

    for pattern in "${patterns[@]}"; do
        if [[ "${ssid}" =~ ${pattern} ]]; then
            log_debug "SSID '${ssid}' matches mobile hotspot pattern: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Detect if currently connected to mobile hotspot
detect_hotspot_connection() {
    local iface ssid

    iface=$(detect_wireless_interface) || {
        log_debug "No wireless interface detected"
        return 1
    }

    ssid=$(get_current_ssid "${iface}") || {
        log_debug "No SSID detected"
        return 1
    }

    if is_mobile_hotspot "${ssid}"; then
        log_info "Mobile hotspot detected: ${ssid}"
        echo "${ssid}"
        return 0
    else
        log_debug "Not a mobile hotspot: ${ssid}"
        return 1
    fi
}

# Auto-enable bypass if connected to hotspot
auto_enable_if_hotspot() {
    local ssid

    # Check if auto-enable is enabled
    if [[ "${CONFIG[AUTO_ENABLE]:-false}" != "true" ]]; then
        log_debug "Auto-enable is disabled"
        return 0
    fi

    # Detect hotspot
    if ssid=$(detect_hotspot_connection); then
        log_info "🔍 Mobile hotspot detected: ${ssid}"

        # Check if already enabled
        if is_bypass_active; then
            log_info "Bypass already active, skipping auto-enable"
            return 0
        fi

        log_info "🚀 Auto-enabling bypass for hotspot: ${ssid}"
        enable_bypass

        return 0
    fi

    return 1
}

# Show detection info
show_detection_info() {
    local iface ssid

    echo "=== HOTSPOT DETECTION ==="
    echo ""
    echo "Auto-Enable: ${CONFIG[AUTO_ENABLE]:-false}"
    echo ""

    iface=$(detect_wireless_interface) || {
        echo "Status: No wireless interface detected"
        return 1
    }

    ssid=$(get_current_ssid "${iface}") || {
        echo "Status: Not connected to any network"
        return 1
    }

    echo "Current SSID: ${ssid}"
    echo ""

    if is_mobile_hotspot "${ssid}"; then
        echo -e "${GREEN}✅ Mobile hotspot detected${NC}"
        if [[ "${CONFIG[AUTO_ENABLE]:-false}" == "true" ]]; then
            echo "   Auto-enable is ON - bypass will activate"
        else
            echo "   Auto-enable is OFF - manual enable required"
        fi
    else
        echo "❌ Not a mobile hotspot"
        echo "   (Detected patterns: iPhone, iPad, Android, Mobile Hotspot)"
    fi
}

# Monitor connection changes (for future daemon mode)
monitor_connection_changes() {
    log_info "Starting connection monitor..."

    local previous_ssid=""
    local current_ssid

    while true; do
        current_ssid=$(get_current_ssid 2>/dev/null) || current_ssid=""

        if [[ "${current_ssid}" != "${previous_ssid}" ]]; then
            if [[ -n "${current_ssid}" ]]; then
                log_info "Connection changed: ${previous_ssid} → ${current_ssid}"
                auto_enable_if_hotspot
            else
                log_info "Disconnected from: ${previous_ssid}"
            fi

            previous_ssid="${current_ssid}"
        fi

        sleep 5
    done
}
