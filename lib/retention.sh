#!/bin/bash
# lib/retention.sh - Statistics retention policy for throttle-me
# shellcheck disable=SC2154

set -euo pipefail

# Apply retention policy to session history
apply_retention_policy() {
    ensure_stats_dir

    if [[ ! -f "${STATS_FILE}" ]]; then
        log_debug "No stats file to apply retention policy"
        return 0
    fi

    local max_sessions=${CONFIG[MAX_SESSIONS]:-100}
    local max_age_days=${CONFIG[MAX_AGE_DAYS]:-30}
    local initial_count current_count

    initial_count=$(wc -l < "${STATS_FILE}")

    log_debug "Applying retention policy: max_sessions=${max_sessions}, max_age_days=${max_age_days}"

    # Step 1: Keep only last N sessions
    if [[ ${initial_count} -gt ${max_sessions} ]]; then
        log_debug "Session count (${initial_count}) exceeds max (${max_sessions}), trimming..."
        tail -n "${max_sessions}" "${STATS_FILE}" > "${STATS_FILE}.tmp"
        mv "${STATS_FILE}.tmp" "${STATS_FILE}"
    fi

    # Step 2: Delete sessions older than N days
    local cutoff_date
    cutoff_date=$(date -d "${max_age_days} days ago" '+%Y-%m-%d' 2>/dev/null || date -v-"${max_age_days}d" '+%Y-%m-%d' 2>/dev/null)

    if [[ -n "${cutoff_date}" ]]; then
        log_debug "Removing sessions older than ${cutoff_date}"
        awk -v cutoff="${cutoff_date}" -F'|' '$1 >= cutoff || NR==1' "${STATS_FILE}" > "${STATS_FILE}.tmp"
        mv "${STATS_FILE}.tmp" "${STATS_FILE}"
    fi

    current_count=$(wc -l < "${STATS_FILE}")

    if [[ ${initial_count} -gt ${current_count} ]]; then
        local removed=$((initial_count - current_count))
        log_info "Retention policy applied: removed ${removed} old sessions"
    else
        log_debug "Retention policy: no sessions removed"
    fi
}

# Get session count
get_session_count() {
    if [[ ! -f "${STATS_FILE}" ]]; then
        echo "0"
        return 0
    fi

    wc -l < "${STATS_FILE}"
}

# Get oldest session date
get_oldest_session_date() {
    if [[ ! -f "${STATS_FILE}" ]]; then
        echo "N/A"
        return 1
    fi

    head -1 "${STATS_FILE}" | cut -d'|' -f1 | xargs
}

# Get newest session date
get_newest_session_date() {
    if [[ ! -f "${STATS_FILE}" ]]; then
        echo "N/A"
        return 1
    fi

    tail -1 "${STATS_FILE}" | cut -d'|' -f1 | xargs
}

# Show retention policy info
show_retention_info() {
    echo "=== RETENTION POLICY ==="
    echo ""
    echo "Current Settings:"
    echo "  Max Sessions: ${CONFIG[MAX_SESSIONS]:-100}"
    echo "  Max Age: ${CONFIG[MAX_AGE_DAYS]:-30} days"
    echo ""
    echo "Current Status:"
    local total_sessions oldest_session newest_session
    total_sessions=$(get_session_count)
    oldest_session=$(get_oldest_session_date)
    newest_session=$(get_newest_session_date)

    echo "  Total Sessions: ${total_sessions}"
    echo "  Oldest Session: ${oldest_session}"
    echo "  Newest Session: ${newest_session}"
    echo ""

    local max_sessions=${CONFIG[MAX_SESSIONS]:-100}
    local current_count
    current_count=$(get_session_count)

    if [[ ${current_count} -ge ${max_sessions} ]]; then
        echo "⚠️  Session limit reached - next cleanup will remove oldest sessions"
    else
        local remaining=$((max_sessions - current_count))
        echo "✅ ${remaining} sessions remaining before cleanup"
    fi
}

# Manual cleanup
manual_cleanup() {
    log_info "Running manual retention cleanup..."
    apply_retention_policy
}

# Archive old sessions before deletion
archive_sessions() {
    local archive_file
    archive_file="${STATS_DIR}/archive_$(date +%Y%m%d_%H%M%S).log"

    if [[ ! -f "${STATS_FILE}" ]]; then
        log_warn "No stats file to archive"
        return 1
    fi

    cp "${STATS_FILE}" "${archive_file}"
    log_info "✅ Sessions archived to ${archive_file}"
}
