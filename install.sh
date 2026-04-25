#!/bin/bash
# throttle-me Installation Script
# Automated installation with dependency checks and configuration
# shellcheck disable=SC2310

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation paths
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/throttle-me"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
SHARE_DIR="${HOME}/.local/share/throttle-me"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
print_header() {
    echo ""
    echo "=========================================="
    echo "  throttle-me Installer"
echo "  v2.0"
echo "=========================================="
    echo ""
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo "ℹ️  $1"; }

check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        missing_deps+=("bash 4.0+")
    fi
    
    # Check required commands
    for cmd in dialog iptables ip6tables sudo python3; do
        if ! command -v "${cmd}" &>/dev/null; then
            missing_deps+=("${cmd}")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Install with: sudo apt-get install ${missing_deps[*]}"
        return 1
    fi
    
    print_success "All dependencies satisfied"
    return 0
}

create_directories() {
    print_info "Creating directories..."
    
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${CONFIG_DIR}/presets"
    mkdir -p "${CONFIG_DIR}/sessions"
    mkdir -p "${SYSTEMD_DIR}"
    mkdir -p "${SHARE_DIR}"
    
    print_success "Directories created"
}

install_scripts() {
    print_info "Installing scripts..."
    
    # Main script
    cp "${SCRIPT_DIR}/throttle-me" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/throttle-me"
    print_success "Installed throttle-me"
    
    # Daemon script
    cp "${SCRIPT_DIR}/throttle-me-daemon" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/throttle-me-daemon"
    print_success "Installed throttle-me-daemon"
    
    # Library modules
    if [[ -d "${SCRIPT_DIR}/lib" ]]; then
        cp -r "${SCRIPT_DIR}/lib" "${INSTALL_DIR}/"
        print_success "Installed library modules"
    fi

    # Textual dashboard package
    if [[ -d "${SCRIPT_DIR}/dashboard" ]]; then
        rm -rf "${SHARE_DIR}/dashboard"
        mkdir -p "${SHARE_DIR}/dashboard"
        cp "${SCRIPT_DIR}/dashboard/pyproject.toml" "${SHARE_DIR}/dashboard/"
        [[ -f "${SCRIPT_DIR}/dashboard/uv.lock" ]] && cp "${SCRIPT_DIR}/dashboard/uv.lock" "${SHARE_DIR}/dashboard/"
        [[ -f "${SCRIPT_DIR}/dashboard/README.md" ]] && cp "${SCRIPT_DIR}/dashboard/README.md" "${SHARE_DIR}/dashboard/"
        cp -r "${SCRIPT_DIR}/dashboard/src" "${SHARE_DIR}/dashboard/"
        [[ -d "${SCRIPT_DIR}/dashboard/tests" ]] && cp -r "${SCRIPT_DIR}/dashboard/tests" "${SHARE_DIR}/dashboard/"
        print_success "Installed command-center dashboard"
    fi

    # External bypass scripts, installed only when the user does not already have them.
    if [[ -f "${SCRIPT_DIR}/scripts/bypass-tethering" && ! -f "${INSTALL_DIR}/bypass-tethering" ]]; then
        cp "${SCRIPT_DIR}/scripts/bypass-tethering" "${INSTALL_DIR}/"
        chmod +x "${INSTALL_DIR}/bypass-tethering"
        print_success "Installed bypass-tethering"
    fi

    if [[ -f "${SCRIPT_DIR}/scripts/disable-bypass-tethering" && ! -f "${INSTALL_DIR}/disable-bypass-tethering" ]]; then
        cp "${SCRIPT_DIR}/scripts/disable-bypass-tethering" "${INSTALL_DIR}/"
        chmod +x "${INSTALL_DIR}/disable-bypass-tethering"
        print_success "Installed disable-bypass-tethering"
    fi
}

install_systemd_service() {
    print_info "Installing systemd service..."
    
    cp "${SCRIPT_DIR}/config/throttle-me-daemon.service" "${SYSTEMD_DIR}/"
    
    # Reload systemd to recognize new service
    systemctl --user daemon-reload
    
    print_success "Systemd service installed"
}

install_config() {
    print_info "Installing configuration..."
    
    if [[ ! -f "${CONFIG_DIR}/config" ]]; then
        if [[ -f "${SCRIPT_DIR}/config/config.template" ]]; then
            cp "${SCRIPT_DIR}/config/config.template" "${CONFIG_DIR}/config"
            print_success "Installed default configuration"
        else
            print_warning "config.template not found, skipping config installation"
        fi
    else
        print_info "Configuration already exists, skipping"
    fi
}

setup_sudoers() {
    print_info "Checking sudoers configuration..."
    
    local sudoers_file="/etc/sudoers.d/throttle-me"
    local user
    user="$(whoami)"
    
    if [[ -f "${sudoers_file}" ]]; then
        print_success "Sudoers configuration already exists"
        return 0
    fi
    
    print_warning "Sudoers configuration not found"
    print_info "The daemon requires passwordless sudo for bypass scripts"
    echo ""
    read -rp "Would you like to configure it now? (y/n): " response
    if [[ "${response}" =~ ^[Yy]$ ]]; then
        print_info "Creating sudoers configuration..."
        echo ""
        echo "Run the following command:"
        echo "  sudo visudo -f /etc/sudoers.d/throttle-me"
        echo ""
        echo "Then add these lines:"
        echo "  ${user} ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/throttle-me"
        echo "  ${user} ALL=(ALL) NOPASSWD: /usr/sbin/iptables"
        echo "  ${user} ALL=(ALL) NOPASSWD: /usr/sbin/ip6tables"
        echo "  ${user} ALL=(ALL) NOPASSWD: /usr/bin/tee"
        echo "  ${user} ALL=(ALL) NOPASSWD: /usr/bin/chattr"
        echo "  ${user} ALL=(ALL) NOPASSWD: /usr/bin/cp"
        echo "  ${user} ALL=(ALL) NOPASSWD: /usr/bin/rm"
        echo ""
        read -rp "Press Enter when done..."
    else
        print_warning "Skipping sudoers setup - daemon will not work without it"
    fi
}

verify_installation() {
    print_info "Verifying installation..."
    
    local errors=0
    
    # Check main script
    if [[ ! -x "${INSTALL_DIR}/throttle-me" ]]; then
        print_error "throttle-me not found or not executable"
        ((errors++))
    else
        print_success "throttle-me installed"
    fi
    
    # Check daemon script
    if [[ ! -x "${INSTALL_DIR}/throttle-me-daemon" ]]; then
        print_error "throttle-me-daemon not found or not executable"
        ((errors++))
    else
        print_success "throttle-me-daemon installed"
    fi
    
    # Check systemd service
    if [[ ! -f "${SYSTEMD_DIR}/throttle-me-daemon.service" ]]; then
        print_error "systemd service not found"
        ((errors++))
    else
        print_success "systemd service installed"
    fi

    if [[ ! -f "${SHARE_DIR}/dashboard/pyproject.toml" ]]; then
        print_error "command-center dashboard not installed"
        ((errors++))
    else
        print_success "command-center dashboard installed"
    fi
    
    # Check configuration
    if [[ ! -f "${CONFIG_DIR}/config" ]]; then
        print_warning "Configuration file not created"
    else
        print_success "Configuration file exists"
    fi
    
    # Check PATH
    if ! echo "${PATH}" | grep -q "${INSTALL_DIR}"; then
        print_warning "${INSTALL_DIR} not in PATH - you may need to add it"
        print_info "Add to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
    else
        print_success "${INSTALL_DIR} is in PATH"
    fi
    
    return "${errors}"
}

show_next_steps() {
    echo ""
    print_header
    print_success "Installation complete!"
    echo ""
    print_info "Next steps:"
    echo "  1. Run 'throttle-me' to launch the command center"
    echo "  2. Or use CLI: 'throttle-me -e' to enable bypass"
    echo "  3. Configure daemon: 'throttle-me -D start'"
    echo ""
    print_info "Documentation:"
    echo "  - Quick Start: docs/QUICKSTART.md"
    echo "  - Daemon Guide: docs/DAEMON.md"
    echo "  - Full PRD: PRD.md"
    echo ""
    print_info "Verify environment:"
    echo "  - Run: .claude/scripts/verify-env.sh"
    echo ""
}

# Main installation flow
main() {
    print_header
    
    # Check dependencies
    if ! check_dependencies; then
        print_error "Installation aborted due to missing dependencies"
        exit 1
    fi
    
    # Create directories
    create_directories
    
    # Install scripts
    install_scripts
    
    # Install systemd service
    install_systemd_service
    
    # Install configuration
    install_config
    
    # Setup sudoers
    setup_sudoers
    
    # Verify installation
    if ! verify_installation; then
        print_error "Installation completed with errors"
        exit 1
    fi
    
    # Show next steps
    show_next_steps
}

# Run main
main "$@"
