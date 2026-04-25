#!/bin/bash
# lib/presets.sh - Configuration preset management for throttle-me

set -euo pipefail

# Preset directory
PRESET_DIR="${HOME}/.config/throttle-me/presets"

# Ensure preset directory exists
ensure_preset_dir() {
    if [[ ! -d "${PRESET_DIR}" ]]; then
        mkdir -p "${PRESET_DIR}"
        log_debug "Created preset directory: ${PRESET_DIR}"
    fi
}

# List all available presets
list_presets() {
    ensure_preset_dir

    local preset_count
    preset_count=$(find "${PRESET_DIR}" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | wc -l)
    if [[ "${preset_count}" -eq 0 ]]; then
        echo "No saved presets found"
        return 1
    fi

    echo "Available presets:"
    local i=1
    for preset in "${PRESET_DIR}"/*.conf; do
        if [[ -f "${preset}" ]]; then
            local name
            name=$(basename "${preset}" .conf)
            echo "  ${i}) ${name}"
            ((i++))
        fi
    done
}

# Save current configuration as preset
save_preset() {
    local preset_name=$1
    ensure_preset_dir

    local preset_file="${PRESET_DIR}/${preset_name}.conf"
    local created_at
    created_at=$(date)

    # Check if preset already exists
    if [[ -f "${preset_file}" ]]; then
        log_warn "Preset '${preset_name}' already exists - overwriting"
    fi

    # Save current CONFIG values
    cat > "${preset_file}" << EOF
# Preset: ${preset_name}
# Created: ${created_at}

TTL_VALUE=${CONFIG[TTL_VALUE]}
DNS_SERVER="${CONFIG[DNS_SERVER]}"
BYPASS_SCRIPT="${CONFIG[BYPASS_SCRIPT]}"
DISABLE_SCRIPT="${CONFIG[DISABLE_SCRIPT]}"
CONFIRM_ENABLE=${CONFIG[CONFIRM_ENABLE]}
CONFIRM_DISABLE=${CONFIG[CONFIRM_DISABLE]}
EOF

    log_info "✅ Preset '${preset_name}' saved to ${preset_file}"
}

# Load preset configuration
load_preset() {
    local preset_name=$1
    local preset_file="${PRESET_DIR}/${preset_name}.conf"

    if [[ ! -f "${preset_file}" ]]; then
        log_error "Preset '${preset_name}' not found"
        return 1
    fi

    # Source the preset file to override CONFIG values
    source "${preset_file}"

    # Update CONFIG array with new values
    CONFIG[TTL_VALUE]=${TTL_VALUE:-65}
    CONFIG[DNS_SERVER]=${DNS_SERVER:-1.1.1.1}
    CONFIG[BYPASS_SCRIPT]=${BYPASS_SCRIPT:-${HOME}/.local/bin/bypass-tethering}
    CONFIG[DISABLE_SCRIPT]=${DISABLE_SCRIPT:-${HOME}/.local/bin/disable-bypass-tethering}
    CONFIG[CONFIRM_ENABLE]=${CONFIRM_ENABLE:-true}
    CONFIG[CONFIRM_DISABLE]=${CONFIRM_DISABLE:-true}

    log_info "✅ Preset '${preset_name}' loaded"
    log_info "TTL=${CONFIG[TTL_VALUE]}, DNS=${CONFIG[DNS_SERVER]}"
}

# Delete preset
delete_preset() {
    local preset_name=$1
    local preset_file="${PRESET_DIR}/${preset_name}.conf"

    if [[ ! -f "${preset_file}" ]]; then
        log_error "Preset '${preset_name}' not found"
        return 1
    fi

    rm "${preset_file}"
    log_info "✅ Preset '${preset_name}' deleted"
}

# Show preset details
show_preset() {
    local preset_name=$1
    local preset_file="${PRESET_DIR}/${preset_name}.conf"

    if [[ ! -f "${preset_file}" ]]; then
        log_error "Preset '${preset_name}' not found"
        return 1
    fi

    echo "=== PRESET: ${preset_name} ==="
    echo ""
    grep -v "^#" "${preset_file}" | grep -v "^$"
}

# Create default presets
create_default_presets() {
    ensure_preset_dir

    # iPhone preset (TTL=65)
    cat > "${PRESET_DIR}/iphone.conf" << 'EOF'
# iPhone Preset - Standard TTL for iOS devices
TTL_VALUE=65
DNS_SERVER="1.1.1.1"
BYPASS_SCRIPT="$HOME/.local/bin/bypass-tethering"
DISABLE_SCRIPT="$HOME/.local/bin/disable-bypass-tethering"
CONFIRM_ENABLE=true
CONFIRM_DISABLE=true
EOF

    # Android preset (TTL=64)
    cat > "${PRESET_DIR}/android.conf" << 'EOF'
# Android Preset - Standard TTL for Android devices
TTL_VALUE=64
DNS_SERVER="1.1.1.1"
BYPASS_SCRIPT="$HOME/.local/bin/bypass-tethering"
DISABLE_SCRIPT="$HOME/.local/bin/disable-bypass-tethering"
CONFIRM_ENABLE=true
CONFIRM_DISABLE=true
EOF

    # Stealth preset (TTL=128, Google DNS)
    cat > "${PRESET_DIR}/stealth.conf" << 'EOF'
# Stealth Preset - Higher TTL, alternative DNS
TTL_VALUE=128
DNS_SERVER="8.8.8.8"
BYPASS_SCRIPT="$HOME/.local/bin/bypass-tethering"
DISABLE_SCRIPT="$HOME/.local/bin/disable-bypass-tethering"
CONFIRM_ENABLE=false
CONFIRM_DISABLE=false
EOF

    log_info "✅ Default presets created (iphone, android, stealth)"
}
