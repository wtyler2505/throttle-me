#!/bin/bash
# lib/stats.sh - Statistics tracking for throttle-me
# shellcheck disable=SC2154

set -euo pipefail

# Statistics directory
STATS_DIR="${HOME}/.config/throttle-me/stats"
STATS_FILE="${STATS_DIR}/sessions.log"
CURRENT_SESSION_FILE="${STATS_DIR}/current_session.tmp"

# Ensure stats directory exists
ensure_stats_dir() {
    if [[ ! -d "${STATS_DIR}" ]]; then
        mkdir -p "${STATS_DIR}"
        log_debug "Created stats directory: ${STATS_DIR}"
    fi
}

# Start new session
start_session() {
    ensure_stats_dir

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Get initial packet counts
    local ipv4_packets ipv6_packets
    ipv4_packets=$(sudo iptables -t mangle -L POSTROUTING -n -v 2>/dev/null | grep "TTL set to" | awk '{print $1}' | head -1 || echo "0")
    ipv6_packets=$(sudo ip6tables -t mangle -L POSTROUTING -n -v 2>/dev/null | grep "HL set to" | awk '{print $1}' | head -1 || echo "0")

    # Store session start info
    cat > "${CURRENT_SESSION_FILE}" << EOF
START_TIME=${timestamp}
START_IPV4_PACKETS=${ipv4_packets}
START_IPV6_PACKETS=${ipv6_packets}
TTL=${CONFIG[TTL_VALUE]}
DNS=${CONFIG[DNS_SERVER]}
EOF

    log_debug "Session started at ${timestamp}"
}

# End current session
end_session() {
    if [[ ! -f "${CURRENT_SESSION_FILE}" ]]; then
        log_warn "No active session to end"
        return 1
    fi

    ensure_stats_dir

    # Load session start info
    source "${CURRENT_SESSION_FILE}"

    local end_time
    end_time=$(date '+%Y-%m-%d %H:%M:%S')

    # Get final packet counts
    local ipv4_packets_end ipv6_packets_end
    ipv4_packets_end=$(sudo iptables -t mangle -L POSTROUTING -n -v 2>/dev/null | grep "TTL set to" | awk '{print $1}' | head -1 || echo "0")
    ipv6_packets_end=$(sudo ip6tables -t mangle -L POSTROUTING -n -v 2>/dev/null | grep "HL set to" | awk '{print $1}' | head -1 || echo "0")

    # Calculate session totals
    local ipv4_total ipv6_total
    ipv4_total=$((ipv4_packets_end - START_IPV4_PACKETS))
    ipv6_total=$((ipv6_packets_end - START_IPV6_PACKETS))

    # Calculate duration
    local start_epoch end_epoch duration
    start_epoch=$(date -d "${START_TIME}" '+%s' 2>/dev/null || echo "0")
    end_epoch=$(date -d "${end_time}" '+%s' 2>/dev/null || echo "0")
    duration=$((end_epoch - start_epoch))

    # Log session to file
    echo "${START_TIME} | ${end_time} | ${duration}s | IPv4: ${ipv4_total} packets | IPv6: ${ipv6_total} packets | TTL: ${TTL} | DNS: ${DNS}" >> "${STATS_FILE}"

    # Apply retention policy
    apply_retention_policy

    # Clean up current session
    rm "${CURRENT_SESSION_FILE}"

    log_info "Session ended: ${duration}s, IPv4: ${ipv4_total} packets, IPv6: ${ipv6_total} packets"
}

# Get session statistics
get_session_stats() {
    ensure_stats_dir

    if [[ ! -f "${STATS_FILE}" ]]; then
        echo "No session history available"
        return 1
    fi

    local total_sessions
    total_sessions=$(wc -l < "${STATS_FILE}")

    echo "=== SESSION STATISTICS ==="
    echo ""
    echo "Total Sessions: ${total_sessions}"
    echo ""
    echo "Recent Sessions:"
    echo "----------------"
    tail -10 "${STATS_FILE}" | nl -w2 -s'. '
}

# Get current session info
get_current_session() {
    if [[ ! -f "${CURRENT_SESSION_FILE}" ]]; then
        echo "No active session"
        return 1
    fi

    source "${CURRENT_SESSION_FILE}"

    local current_time duration
    current_time=$(date '+%Y-%m-%d %H:%M:%S')

    local start_epoch current_epoch
    start_epoch=$(date -d "${START_TIME}" '+%s' 2>/dev/null || echo "0")
    current_epoch=$(date -d "${current_time}" '+%s' 2>/dev/null || echo "0")
    duration=$((current_epoch - start_epoch))

    # Get current packet counts
    local ipv4_now ipv6_now
    ipv4_now=$(sudo iptables -t mangle -L POSTROUTING -n -v 2>/dev/null | grep "TTL set to" | awk '{print $1}' | head -1 || echo "0")
    ipv6_now=$(sudo ip6tables -t mangle -L POSTROUTING -n -v 2>/dev/null | grep "HL set to" | awk '{print $1}' | head -1 || echo "0")

    local ipv4_session ipv6_session
    ipv4_session=$((ipv4_now - START_IPV4_PACKETS))
    ipv6_session=$((ipv6_now - START_IPV6_PACKETS))

    echo "=== CURRENT SESSION ==="
    echo ""
    echo "Started: ${START_TIME}"
    echo "Duration: ${duration}s ($(printf '%d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60))))"
    echo ""
    echo "Packets This Session:"
    echo "  IPv4: ${ipv4_session} packets"
    echo "  IPv6: ${ipv6_session} packets"
    echo ""
    echo "Configuration:"
    echo "  TTL: ${TTL}"
    echo "  DNS: ${DNS}"
}

# Show data usage statistics
show_data_stats() {
    ensure_stats_dir

    if [[ ! -f "${STATS_FILE}" ]]; then
        echo "No statistics available yet"
        return 1
    fi

    echo "=== DATA USAGE STATISTICS ==="
    echo ""

    # Total packets across all sessions
    local total_ipv4 total_ipv6
    total_ipv4=$(grep -oP 'IPv4: \K[0-9]+' "${STATS_FILE}" | awk '{s+=$1} END {print s}')
    total_ipv6=$(grep -oP 'IPv6: \K[0-9]+' "${STATS_FILE}" | awk '{s+=$1} END {print s}')

    echo "All-Time Total Packets Modified:"
    echo "  IPv4: ${total_ipv4:-0} packets"
    echo "  IPv6: ${total_ipv6:-0} packets"
    echo ""

    # Average session duration
    local total_duration session_count avg_duration
    total_duration=$(grep -oP '\| \K[0-9]+(?=s \|)' "${STATS_FILE}" | awk '{s+=$1} END {print s}')
    session_count=$(wc -l < "${STATS_FILE}")
    avg_duration=$((total_duration / session_count))

    echo "Average Session Duration: ${avg_duration}s ($(printf '%d:%02d:%02d' $((avg_duration/3600)) $((avg_duration%3600/60)) $((avg_duration%60))))"
    echo "Total Sessions: ${session_count}"
}

# Reset statistics
reset_stats() {
    ensure_stats_dir

    if [[ -f "${STATS_FILE}" ]]; then
        local backup_file
        backup_file="${STATS_FILE}.backup.$(date +%s)"
        mv "${STATS_FILE}" "${backup_file}"
        log_info "✅ Statistics reset (backup created)"
    else
        log_warn "No statistics to reset"
    fi
}

# Export statistics to CSV
export_stats_csv() {
    local output_file=${1:-${HOME}/throttle-me-stats.csv}

    if [[ ! -f "${STATS_FILE}" ]]; then
        log_error "No statistics to export"
        return 1
    fi

    echo "Start Time,End Time,Duration (s),IPv4 Packets,IPv6 Packets,TTL,DNS" > "${output_file}"

    while IFS='|' read -r start end duration ipv4 ipv6 ttl dns; do
        # Clean up whitespace
        start=$(echo "${start}" | xargs)
        end=$(echo "${end}" | xargs)
        duration=$(echo "${duration}" | sed 's/s//' | xargs)
        ipv4=$(echo "${ipv4}" | grep -oP '[0-9]+')
        ipv6=$(echo "${ipv6}" | grep -oP '[0-9]+')
        ttl=$(echo "${ttl}" | grep -oP '[0-9]+')
        dns=$(echo "${dns}" | xargs)

        echo "${start},${end},${duration},${ipv4},${ipv6},${ttl},${dns}" >> "${output_file}"
    done < "${STATS_FILE}"

    log_info "✅ Statistics exported to ${output_file}"
}
