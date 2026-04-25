#!/bin/bash
# lib/iptables.sh - iptables/ip6tables operations wrapper for throttle-me

set -euo pipefail

# Check if IPv4 TTL bypass rule is active
is_ttl_active() {
    sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to ${CONFIG[TTL_VALUE]}"
}

# Check if IPv6 Hop Limit bypass rule is active
is_ipv6_hl_active() {
    sudo ip6tables -t mangle -L POSTROUTING -n 2>/dev/null | grep -q "HL set to ${CONFIG[HL_VALUE]:-${CONFIG[TTL_VALUE]}}" || return 1
}

# Check if IPv4 DNS redirection is active
is_dns_active() {
    sudo iptables -t nat -L OUTPUT -n | grep -q "DNAT.*${CONFIG[DNS_SERVER]}:53"
}

# Check if IPv6 DNS redirection is active
is_ipv6_dns_active() {
    sudo ip6tables -t nat -L OUTPUT -n 2>/dev/null | grep -q "DNAT.*${CONFIG[DNS_SERVER]}:53" || return 1
}

# Get packet count for IPv4 TTL rule
get_ttl_packet_count() {
    sudo iptables -t mangle -L POSTROUTING -n -v | \
        grep "TTL set to ${CONFIG[TTL_VALUE]}" | \
        awk '{print $1, "packets,", $2}'
}

# Get packet count for IPv6 HL rule
get_ipv6_hl_packet_count() {
    sudo ip6tables -t mangle -L POSTROUTING -n -v 2>/dev/null | \
        grep "HL set to ${CONFIG[HL_VALUE]:-${CONFIG[TTL_VALUE]}}" | \
        awk '{print $1, "packets,", $2}' || echo "0 packets, 0"
}

# Check if bypass is fully active
is_bypass_active() {
    is_ttl_active && is_dns_active
}

# Check whether /etc/resolv.conf is immutable. Use -L so symlink targets are tested.
get_dns_lock_status() {
    local attrs
    attrs=$(lsattr -L /etc/resolv.conf 2>/dev/null | awk '{print $1}' || true)
    if [[ -z "$attrs" ]]; then
        echo "Unknown"
    elif [[ "$attrs" == *i* ]]; then
        echo "Immutable"
    else
        echo "Not locked"
    fi
}

# Get detailed bypass status (IPv4 and IPv6)
get_bypass_status() {
    local status="INACTIVE"
    local ttl_status="Inactive"
    local ipv6_hl_status="Inactive"
    local dns_status="Inactive"
    local ipv6_dns_status="Inactive"
    local dns_config="System DNS"
    local dns_lock="Unknown"
    local dns_transport="Public DNS redirection (port 53), not DoH/DoT"
    local packets="N/A"
    local ipv6_packets="N/A"

    # Check IPv4 TTL
    if is_ttl_active; then
        ttl_status="Active (TTL=${CONFIG[TTL_VALUE]})"
        packets=$(get_ttl_packet_count)
    fi

    # Check IPv6 Hop Limit
    if is_ipv6_hl_active; then
        ipv6_hl_status="Active (HL=${CONFIG[HL_VALUE]:-${CONFIG[TTL_VALUE]}})"
        ipv6_packets=$(get_ipv6_hl_packet_count)
    fi

    # Check IPv4 DNS redirection
    if is_dns_active; then
        dns_status="Active"
    fi

    # Check IPv6 DNS redirection
    if is_ipv6_dns_active; then
        ipv6_dns_status="Active"
    fi

    # Check DNS config file
    if grep -q "${CONFIG[DNS_SERVER]}" /etc/resolv.conf 2>/dev/null; then
        dns_config="${CONFIG[DNS_SERVER]}"
    fi

    dns_lock=$(get_dns_lock_status)

    # Overall status: active only when the IPv4 minimum viable path is complete.
    if [[ "$ttl_status" == Active* && "$dns_status" == "Active" ]]; then
        status="ACTIVE"
    elif [[ "$ttl_status" == Active* || "$dns_status" == "Active" || "$ipv6_hl_status" == Active* || "$ipv6_dns_status" == "Active" ]]; then
        status="PARTIAL"
    fi

    # Return status as key=value pairs
    echo "STATUS=$status"
    echo "TTL_IPV4=$ttl_status"
    echo "HL_IPV6=$ipv6_hl_status"
    echo "DNS_IPV4=$dns_status"
    echo "DNS_IPV6=$ipv6_dns_status"
    echo "DNS_CONFIG=$dns_config"
    echo "DNS_LOCK=$dns_lock"
    echo "DNS_TRANSPORT=$dns_transport"
    echo "PACKETS_IPV4=$packets"
    echo "PACKETS_IPV6=$ipv6_packets"
}
