#!/bin/bash
# lib/ui-theme.sh - NSA-style dark theme for throttle-me
# Neon colors, ASCII art, cyberpunk aesthetic

set -euo pipefail

# ============================================================================
# ANSI COLOR CODES (Theme-specific, prefixed with T_ to avoid conflicts)
# ============================================================================

# Reset
export T_RESET='\033[0m'

# Regular colors
export T_BLACK='\033[0;30m'
export T_WHITE='\033[0;37m'

# Bright/Neon colors (use these for the cyberpunk look)
export T_NEON_RED='\033[1;31m'
export T_NEON_GREEN='\033[1;32m'
export T_NEON_YELLOW='\033[1;33m'
export T_NEON_BLUE='\033[1;34m'
export T_NEON_MAGENTA='\033[1;35m'
export T_NEON_CYAN='\033[1;36m'
export T_BRIGHT_WHITE='\033[1;37m'

# Background colors
export T_BG_BLACK='\033[40m'

# Text styles
export T_BOLD='\033[1m'
export T_DIM='\033[2m'
export T_UNDERLINE='\033[4m'
export T_BLINK='\033[5m'

# ============================================================================
# DIALOG THEME CONFIGURATION
# ============================================================================

export DIALOGRC="${HOME}/.config/throttle-me/dialogrc"

create_dialog_theme() {
    local config_dir="${HOME}/.config/throttle-me"
    mkdir -p "${config_dir}"
    
    cat > "${DIALOGRC}" <<'DIALOGRC_EOF'
# throttle-me NSA Dark Theme
# Pure black background with neon cyan accents

use_shadow = ON
use_colors = ON

# Screen (terminal background)
screen_color = (BLACK,BLACK,ON)

# Shadow effect
shadow_color = (BLACK,BLACK,ON)

# Main dialog box
dialog_color = (WHITE,BLACK,OFF)

# Dialog borders (NEON CYAN)
border_color = (CYAN,BLACK,ON)
border2_color = (CYAN,BLACK,ON)

# Dialog title (NEON CYAN)
title_color = (CYAN,BLACK,ON)

# Buttons (inactive)
button_inactive_color = (WHITE,BLACK,OFF)

# Buttons (active/selected) - BLACK on CYAN for neon invert effect
button_active_color = (BLACK,CYAN,ON)

# Button shortcut keys
button_key_inactive_color = (YELLOW,BLACK,ON)
button_key_active_color = (YELLOW,CYAN,ON)

# Menu box
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (CYAN,BLACK,ON)
menubox_border2_color = (CYAN,BLACK,ON)

# Menu items (inactive)
item_color = (WHITE,BLACK,OFF)

# Menu items (selected) - BLACK on CYAN
item_selected_color = (BLACK,CYAN,ON)

# Menu tags
tag_color = (CYAN,BLACK,ON)
tag_key_color = (YELLOW,BLACK,ON)
tag_selected_color = (YELLOW,CYAN,ON)

# Checkboxes
check_color = (WHITE,BLACK,OFF)
check_selected_color = (BLACK,CYAN,ON)

# Input boxes
inputbox_color = (WHITE,BLACK,OFF)
inputbox_border_color = (CYAN,BLACK,ON)
inputbox_border2_color = (CYAN,BLACK,ON)

# Search boxes
searchbox_color = (WHITE,BLACK,OFF)
searchbox_title_color = (CYAN,BLACK,ON)
searchbox_border_color = (CYAN,BLACK,ON)
searchbox_border2_color = (CYAN,BLACK,ON)

# Position indicator
position_indicator_color = (CYAN,BLACK,ON)
DIALOGRC_EOF
}

# ============================================================================
# ASCII ART BANNERS
# ============================================================================

# Main title banner (shown at TUI start)
show_banner() {
    clear
    echo -e "${T_NEON_GREEN}"
    figlet -f big "THROTTLE-ME" | sed 's/^/  /'
    echo -e "${T_RESET}"
    echo -e "${T_NEON_CYAN}  ═══════════════════════════════════════════════════════════════════════${T_RESET}"
    echo -e "${T_NEON_MAGENTA}              [●] CARRIER BYPASS COMMAND CENTER [●]       v3.0.0${T_RESET}"
    echo -e "${T_NEON_CYAN}  ═══════════════════════════════════════════════════════════════════════${T_RESET}"
    echo ""
    sleep 0.3
}

# Compact section header (shown before each menu)
show_section_header() {
    local title="$1"
    echo -e "\n${T_NEON_CYAN}━━━ ${T_NEON_YELLOW}${title}${T_NEON_CYAN} ━━━${T_RESET}\n"
}

# Status box with neon styling
show_status_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo -e "\n${T_NEON_CYAN}╔════════════════════════════════════════════════════════════╗${T_RESET}"
    printf "${T_NEON_CYAN}║${T_RESET} ${T_NEON_YELLOW}%-58s${T_NEON_CYAN}║${T_RESET}\n" "${title}"
    echo -e "${T_NEON_CYAN}╠════════════════════════════════════════════════════════════╣${T_RESET}"
    
    for line in "${lines[@]}"; do
        printf "${T_NEON_CYAN}║${T_RESET} %-58s ${T_NEON_CYAN}║${T_RESET}\n" "${line}"
    done
    
    echo -e "${T_NEON_CYAN}╚════════════════════════════════════════════════════════════╝${T_RESET}\n"
}

# Success message with neon green
show_success() {
    local message="$1"
    echo -e "\n${T_NEON_GREEN}✓${T_RESET} ${T_BRIGHT_WHITE}${message}${T_RESET}\n"
}

# Error message with neon red
show_error() {
    local message="$1"
    echo -e "\n${T_NEON_RED}✗${T_RESET} ${T_BRIGHT_WHITE}${message}${T_RESET}\n"
}

# Warning message with neon yellow
show_warning() {
    local message="$1"
    echo -e "\n${T_NEON_YELLOW}⚠${T_RESET} ${T_BRIGHT_WHITE}${message}${T_RESET}\n"
}

# Info message with neon cyan
show_info() {
    local message="$1"
    echo -e "\n${T_NEON_CYAN}ℹ${T_RESET} ${T_BRIGHT_WHITE}${message}${T_RESET}\n"
}

# Loading animation (spinner)
loading_animation() {
    local message="$1"
    local duration="${2:-2}"  # Default 2 seconds
    
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local temp
    
    echo -ne "${T_NEON_CYAN}"
    
    for ((i=0; i<duration*10; i++)); do
        temp=${spinstr#?}
        printf "\r[%c] %s" "${spinstr}" "${message}"
        spinstr=${temp}${spinstr%"${temp}"}
        sleep 0.1
    done
    
    printf "\r${T_NEON_GREEN}[✓]${T_RESET} %s\n" "${message}"
}

# Progress bar
show_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Processing}"
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    
    printf '%b' "\r${T_NEON_CYAN}[${T_NEON_GREEN}"
    printf "%${filled}s" | tr ' ' '█'
    printf '%b' "${T_DIM}"
    printf "%${empty}s" | tr ' ' '░'
    printf "${T_RESET}${T_NEON_CYAN}]${T_RESET} %3d%% %s" "${percent}" "${message}"
}

# Separator line
show_separator() {
    echo -e "${T_NEON_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${T_RESET}"
}

# ============================================================================
# STATUS INDICATORS
# ============================================================================

# Bypass status indicator
show_bypass_status() {
    local active="$1"
    
    if [[ "${active}" == "true" ]]; then
        echo -e "${T_NEON_GREEN}[●]${T_RESET} ${T_BRIGHT_WHITE}ACTIVE${T_RESET}"
    else
        echo -e "${T_NEON_RED}[○]${T_RESET} ${T_DIM}INACTIVE${T_RESET}"
    fi
}

# Network status indicator
show_network_status() {
    local connected="$1"
    
    if [[ "${connected}" == "true" ]]; then
        echo -e "${T_NEON_GREEN}[▲]${T_RESET} ${T_BRIGHT_WHITE}CONNECTED${T_RESET}"
    else
        echo -e "${T_NEON_RED}[▼]${T_RESET} ${T_DIM}DISCONNECTED${T_RESET}"
    fi
}

# Daemon status indicator
show_daemon_status() {
    local running="$1"
    
    if [[ "${running}" == "true" ]]; then
        echo -e "${T_NEON_GREEN}[▶]${T_RESET} ${T_BRIGHT_WHITE}RUNNING${T_RESET}"
    else
        echo -e "${T_NEON_YELLOW}[■]${T_RESET} ${T_DIM}STOPPED${T_RESET}"
    fi
}
