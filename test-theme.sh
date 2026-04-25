#!/bin/bash
# Test script to preview the new NSA-style dark theme

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the theme
source "${SCRIPT_DIR}/lib/ui-theme.sh"

# Create the dialog theme
create_dialog_theme

clear

echo -e "${T_NEON_YELLOW}╔════════════════════════════════════════════════════════════════════╗${T_RESET}"
echo -e "${T_NEON_YELLOW}║${T_RESET}  ${T_BRIGHT_WHITE}THROTTLE-ME THEME PREVIEW${T_RESET}                                      ${T_NEON_YELLOW}║${T_RESET}"
echo -e "${T_NEON_YELLOW}╚════════════════════════════════════════════════════════════════════╝${T_RESET}"
echo ""

# Show the main banner
show_banner

echo ""
echo -e "${T_NEON_YELLOW}Theme Preview:${T_RESET}"
echo ""

# Show section header
show_section_header "TEST SECTION"

# Show various status indicators
echo -e "${T_BRIGHT_WHITE}Status Indicators:${T_RESET}"
echo -n "  Bypass (Active):    "
show_bypass_status "true"
echo -n "  Bypass (Inactive):  "
show_bypass_status "false"
echo -n "  Network (Connected):    "
show_network_status "true"
echo -n "  Network (Disconnected): "
show_network_status "false"
echo -n "  Daemon (Running): "
show_daemon_status "true"
echo -n "  Daemon (Stopped): "
show_daemon_status "false"

echo ""
show_separator
echo ""

# Show message types
show_success "This is a success message!"
show_error "This is an error message!"
show_warning "This is a warning message!"
show_info "This is an info message!"

echo ""
show_separator
echo ""

# Show status box example
show_status_box "NETWORK STATUS" \
    "Interface: wlo1" \
    "SSID: Tyler's iPhone" \
    "IP: 192.168.1.100" \
    "Gateway: 192.168.1.1" \
    "Status: Connected"

echo ""

# Show loading animation demo
echo -e "${T_NEON_YELLOW}Loading Animation Demo:${T_RESET}"
loading_animation "Initializing bypass system" 2

echo ""

# Show progress bar demo
echo -e "${T_NEON_YELLOW}Progress Bar Demo:${T_RESET}"
for i in {1..20}; do
    show_progress "${i}" 20 "Processing packets"
    sleep 0.1
done
echo ""

echo ""
show_separator
echo ""

echo -e "${T_NEON_CYAN}Dialog Theme Preview:${T_RESET}"
echo -e "${T_DIM}The dialog boxes will use neon cyan borders, black background,"
echo -e "and cyan-on-black color scheme when you launch the TUI.${T_RESET}"
echo ""

# Test a simple dialog
dialog --clear \
    --backtitle "throttle-me - Theme Preview" \
    --title "SAMPLE MENU" \
    --menu "This is how the new theme looks:" 15 70 4 \
    1 "Option with neon cyan border" \
    2 "Black background (not gray!)" \
    3 "Active selection shows black-on-cyan" \
    4 "Exit Preview" \
    3>&1 1>&2 2>&3

clear

echo ""
show_success "Theme preview complete!"
echo ""
echo -e "${T_NEON_CYAN}To see the full themed TUI, run:${T_RESET} ${T_BRIGHT_WHITE}./throttle-me${T_RESET}"
echo ""
