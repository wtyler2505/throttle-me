#!/bin/bash
# lib/core.sh - Core bypass enable/disable logic for throttle-me

set -euo pipefail

# Enable bypass
enable_bypass() {
    log_info "Enabling carrier bypass..."
    
    # Check if bypass script exists
    local bypass_script="${CONFIG[BYPASS_SCRIPT]}"
    if [[ ! -f "$bypass_script" ]]; then
        log_error "Bypass script not found: $bypass_script"
        log_error "Please ensure $bypass_script exists and is executable"
        return 1
    fi
    
    # Check if already active
    if is_bypass_active; then
        log_warn "Bypass is already active"
        return 0
    fi
    
    # Execute bypass script
    if TTL_VALUE="${CONFIG[TTL_VALUE]}" \
        HL_VALUE="${CONFIG[HL_VALUE]:-${CONFIG[TTL_VALUE]}}" \
        DNS_SERVER="${CONFIG[DNS_SERVER]}" \
        "$bypass_script"; then
        log_info "✅ Bypass enabled successfully"
        log_info "TTL set to ${CONFIG[TTL_VALUE]}, DNS redirected to ${CONFIG[DNS_SERVER]}"

        # Start session tracking
        start_session

        return 0
    else
        log_error "Failed to enable bypass"
        return 1
    fi
}

# Disable bypass
disable_bypass() {
    log_info "Disabling carrier bypass..."
    
    # Check if disable script exists
    local disable_script="${CONFIG[DISABLE_SCRIPT]}"
    if [[ ! -f "$disable_script" ]]; then
        log_error "Disable script not found: $disable_script"
        log_error "Please ensure $disable_script exists and is executable"
        return 1
    fi
    
    # Check if already inactive
    if ! is_bypass_active; then
        log_warn "Bypass is already inactive"
        return 0
    fi
    
    # End session tracking before disabling
    end_session 2>/dev/null || true

    # Execute disable script
    if DNS_SERVER="${CONFIG[DNS_SERVER]}" "$disable_script"; then
        log_info "✅ Bypass disabled successfully"
        log_info "Network settings restored to normal"
        return 0
    else
        log_error "Failed to disable bypass"
        return 1
    fi
}

# Show status (for CLI mode)
show_status() {
    local status_output
    status_output=$(get_bypass_status)

    # Parse status
    local status="" ttl_ipv4="" hl_ipv6="" dns_ipv4="" dns_ipv6="" dns_config="" dns_lock="" dns_transport="" packets_ipv4="" packets_ipv6=""
    while IFS='=' read -r key value; do
        case $key in
            STATUS) status="$value" ;;
            TTL_IPV4) ttl_ipv4="$value" ;;
            HL_IPV6) hl_ipv6="$value" ;;
            DNS_IPV4) dns_ipv4="$value" ;;
            DNS_IPV6) dns_ipv6="$value" ;;
            DNS_CONFIG) dns_config="$value" ;;
            DNS_LOCK) dns_lock="$value" ;;
            DNS_TRANSPORT) dns_transport="$value" ;;
            PACKETS_IPV4) packets_ipv4="$value" ;;
            PACKETS_IPV6) packets_ipv6="$value" ;;
        esac
    done <<< "$status_output"

    echo "=== CARRIER BYPASS STATUS ==="
    echo ""

    if [[ "$status" == "ACTIVE" ]]; then
        echo -e "${GREEN}Status: ACTIVE ✅${NC}"
    elif [[ "$status" == "PARTIAL" ]]; then
        echo -e "${YELLOW}Status: PARTIAL ⚠️${NC}"
    else
        echo -e "${RED}Status: INACTIVE ❌${NC}"
    fi

    echo ""
    echo "IPv4 TTL Modification: $ttl_ipv4"
    echo "IPv6 Hop Limit:        $hl_ipv6"
    echo ""
    echo "IPv4 DNS Redirection:  $dns_ipv4"
    echo "IPv6 DNS Redirection:  $dns_ipv6"
    echo "DNS Config:            $dns_config"
    echo "DNS Lock:              ${dns_lock:-Unknown}"
    echo "DNS Transport:         ${dns_transport:-Unknown}"

    if [[ "$status" == "ACTIVE" || "$status" == "PARTIAL" ]]; then
        echo ""
        if [[ "$packets_ipv4" != "N/A" ]]; then
            echo "IPv4 Packets Modified: $packets_ipv4"
        fi
        if [[ "$packets_ipv6" != "N/A" && "$packets_ipv6" != "0 packets, 0" ]]; then
            echo "IPv6 Packets Modified: $packets_ipv6"
        fi
    fi

    # Show connection info
    local connection
    connection=$(ip route | grep default | awk '{print $3, "via", $5}' || echo "No connection")
    echo ""
    echo "Connection: $connection"
}

# Run speed test using curl
run_speed_test() {
    log_info "Running speed test..."
    echo "=== SPEED TEST ==="
    echo ""
    echo "Testing download speed from Cloudflare..."
    echo ""

    # Download 10MB file and measure speed
    local result
    result=$(curl -o /dev/null -w "Speed: %{speed_download} bytes/sec\nTime: %{time_total} sec\n" \
        https://speed.cloudflare.com/__down?bytes=10000000 2>/dev/null)

    # Extract speed in bytes/sec
    local speed_bytes
    speed_bytes=$(echo "$result" | grep "Speed:" | awk '{print $2}')

    # Convert to Mbps
    local speed_mbps
    speed_mbps=$(echo "scale=2; $speed_bytes * 8 / 1000000" | bc)

    echo "$result"
    echo ""
    echo -e "${GREEN}Download Speed: ${speed_mbps} Mbps${NC}"
    echo ""

    # Show interpretation
    if (( $(echo "$speed_mbps > 20" | bc -l) )); then
        echo -e "${GREEN}✅ Bypass is working! Speed is excellent.${NC}"
    elif (( $(echo "$speed_mbps > 5" | bc -l) )); then
        echo -e "${YELLOW}⚠️  Bypass is working, but speed could be better.${NC}"
    else
        echo -e "${RED}❌ Speed is slow - bypass may not be active.${NC}"
    fi
}

# Preset management commands
show_presets() {
    echo "=== CONFIGURATION PRESETS ==="
    echo ""
    list_presets || true
    echo ""
    echo "Current configuration:"
    echo "  TTL: ${CONFIG[TTL_VALUE]}"
    echo "  HL: ${CONFIG[HL_VALUE]:-${CONFIG[TTL_VALUE]}}"
    echo "  DNS: ${CONFIG[DNS_SERVER]}"
}

save_current_preset() {
    local name=$1
    save_preset "$name"
}

load_saved_preset() {
    local name=$1
    load_preset "$name"
}
