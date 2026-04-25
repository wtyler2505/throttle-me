#!/bin/bash
# lib/ui-dialog.sh - Dialog-based TUI for throttle-me
# shellcheck disable=SC2154,SC2310

set -euo pipefail

# Confirmation dialog
confirm_action() {
    local message=$1
    dialog --clear --backtitle "throttle-me v${THROTTLE_ME_VERSION}" \
        --title "Confirm Action" \
        --yesno "${message}" 10 60
    
    local result=$?
    clear
    return "${result}"
}

# Enable bypass with confirmation
ui_enable_bypass() {
    # Check if confirmation is enabled
    if [[ "${CONFIG[CONFIRM_ENABLE]}" == "true" ]]; then
        if ! confirm_action "Enable carrier bypass?\n\nThis will:\n- Set TTL to ${CONFIG[TTL_VALUE]}\n- Redirect DNS to ${CONFIG[DNS_SERVER]}\n- Modify iptables rules"; then
            log_info "Enable cancelled by user"
            return 0
        fi
    fi
    
    clear
    show_section_header "ENABLING BYPASS"
    echo ""
    
    # Show loading animation
    loading_animation "Applying iptables rules" 1 &
    local pid=$!
    enable_bypass >/dev/null 2>&1
    wait "${pid}"
    
    show_success "Bypass enabled successfully!"
    echo ""
    echo -e "${T_NEON_CYAN}TTL:${T_RESET} ${CONFIG[TTL_VALUE]}  ${T_NEON_CYAN}DNS:${T_RESET} ${CONFIG[DNS_SERVER]}"
    echo ""
    sleep 2
}

# Disable bypass with confirmation
ui_disable_bypass() {
    # Check if confirmation is enabled
    if [[ "${CONFIG[CONFIRM_DISABLE]}" == "true" ]]; then
        if ! confirm_action "Disable carrier bypass?\n\nThis will:\n- Remove TTL modification\n- Remove DNS redirection\n- Restore normal network settings"; then
            log_info "Disable cancelled by user"
            return 0
        fi
    fi
    
    clear
    show_section_header "DISABLING BYPASS"
    echo ""
    
    # Show loading animation
    loading_animation "Removing iptables rules" 1 &
    local pid=$!
    disable_bypass >/dev/null 2>&1
    wait "${pid}"
    
    show_success "Bypass disabled successfully!"
    echo ""
    sleep 2
}
# Show status in TUI
ui_show_status() {
    clear
    show_section_header "SYSTEM STATUS"
    
    # Network information
    echo -e "${T_NEON_CYAN}╔═══════════════════ ${T_NEON_YELLOW}NETWORK INFO${T_NEON_CYAN} ═══════════════════╗${T_RESET}"
    show_network_info | while IFS= read -r line; do
        printf "${T_NEON_CYAN}║${T_RESET} %-56s ${T_NEON_CYAN}║${T_RESET}\n" "${line}"
    done
    echo -e "${T_NEON_CYAN}╚═══════════════════════════════════════════════════════════╝${T_RESET}"
    echo ""
    
    # Bypass status with neon styling
    echo -e "${T_NEON_CYAN}╔═══════════════════ ${T_NEON_YELLOW}BYPASS STATUS${T_NEON_CYAN} ══════════════════╗${T_RESET}"
    show_status | while IFS= read -r line; do
        # Color-code status indicators
        if [[ "${line}" =~ "INACTIVE" ]]; then
            line=${line//INACTIVE/${T_NEON_RED}INACTIVE${T_RESET}}
        elif [[ "${line}" =~ "ACTIVE" ]]; then
            line=${line//ACTIVE/${T_NEON_GREEN}ACTIVE${T_RESET}}
        fi
        printf "${T_NEON_CYAN}║${T_RESET} %-56s ${T_NEON_CYAN}║${T_RESET}\n" "${line}"
    done
    echo -e "${T_NEON_CYAN}╚═══════════════════════════════════════════════════════════╝${T_RESET}"
    echo ""
    
    # Current session info (if bypass is active)
    if [[ -f "${CURRENT_SESSION_FILE}" ]]; then
        source "${CURRENT_SESSION_FILE}"
        
        local current_time
        current_time=$(date '+%Y-%m-%d %H:%M:%S')
        
        local start_epoch current_epoch duration
        start_epoch=$(date -d "${START_TIME}" '+%s' 2>/dev/null || echo "0")
        current_epoch=$(date -d "${current_time}" '+%s' 2>/dev/null || echo "0")
        duration=$((current_epoch - start_epoch))
        
        local hours minutes seconds
        hours=$((duration / 3600))
        minutes=$(((duration % 3600) / 60))
        seconds=$((duration % 60))
        
        echo -e "${T_NEON_CYAN}╔═══════════════════ ${T_NEON_YELLOW}ACTIVE SESSION${T_NEON_CYAN} ═══════════════════╗${T_RESET}"
        printf "${T_NEON_CYAN}║${T_RESET} ${T_BRIGHT_WHITE}Started:${T_RESET}  %-45s ${T_NEON_CYAN}║${T_RESET}\n" "${START_TIME}"
        printf "${T_NEON_CYAN}║${T_RESET} ${T_BRIGHT_WHITE}Duration:${T_RESET} ${T_NEON_GREEN}%-45s${T_RESET} ${T_NEON_CYAN}║${T_RESET}\n" "${hours}h ${minutes}m ${seconds}s"
        printf "${T_NEON_CYAN}║${T_RESET} ${T_BRIGHT_WHITE}TTL:${T_RESET}      %-45s ${T_NEON_CYAN}║${T_RESET}\n" "${TTL}"
        printf "${T_NEON_CYAN}║${T_RESET} ${T_BRIGHT_WHITE}DNS:${T_RESET}      %-45s ${T_NEON_CYAN}║${T_RESET}\n" "${DNS}"
        echo -e "${T_NEON_CYAN}╚═══════════════════════════════════════════════════════════╝${T_RESET}"
        echo ""
    fi
    
    echo -e "${T_DIM}Press Enter to continue...${T_RESET}"
    read -r
}

# Real-time network monitor
ui_monitor() {
    clear
    local iface
    iface=$(detect_wireless_interface) || {
        echo "Error: No wireless interface detected"
        sleep 2
        return 1
    }

    echo "=== REAL-TIME NETWORK MONITOR ==="
    echo ""
    echo "Interface: ${iface}"
    echo "Starting bmon (press 'q' to quit)..."
    echo ""
    sleep 1

    # Run bmon with detected interface
    bmon -p "${iface}" -o curses:rxlist=1:txlist=1

    clear
}

# Speed test
ui_speed_test() {
    clear
    run_speed_test
    echo ""
    read -rp "Press Enter to continue..."
}

# Statistics menu
ui_statistics() {
    while true; do
        choice=$(dialog --clear \
            --backtitle "throttle-me v${THROTTLE_ME_VERSION} - Statistics" \
            --title "Statistics & History" \
            --menu "Choose an option:" 18 60 5 \
            1 "Current Session" \
            2 "Session History" \
            3 "Data Usage Stats" \
            4 "Export to CSV" \
            5 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        exit_status=$?

        if [[ ${exit_status} -ne 0 ]] || [[ ${choice} -eq 5 ]]; then
            return 0
        fi

        case ${choice} in
            1)
                clear
                get_current_session || echo "No active session"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                clear
                get_session_stats
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                clear
                show_data_stats
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                clear
                read -rp "Export to file (default: ~/throttle-me-stats.csv): " export_file
                export_stats_csv "${export_file:-${HOME}/throttle-me-stats.csv}"
                sleep 2
                ;;
            *)
                ;;
        esac
    done
}

# Preset management menu
ui_presets() {
    while true; do
        choice=$(dialog --clear \
            --backtitle "throttle-me v${THROTTLE_ME_VERSION} - Preset Manager" \
            --title "Preset Management" \
            --menu "Choose an option:" 18 60 5 \
            1 "List Presets" \
            2 "Load Preset" \
            3 "Save Current as Preset" \
            4 "Create Default Presets" \
            5 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        exit_status=$?

        if [[ ${exit_status} -ne 0 ]] || [[ ${choice} -eq 5 ]]; then
            return 0
        fi

        case ${choice} in
            1)
                clear
                show_presets
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                clear
                echo "Available presets:"
                list_presets
                echo ""
                read -rp "Enter preset name to load: " preset_name
                if [[ -n "${preset_name}" ]]; then
                    load_saved_preset "${preset_name}"
                    sleep 2
                fi
                ;;
            3)
                clear
                read -rp "Enter name for new preset: " preset_name
                if [[ -n "${preset_name}" ]]; then
                    save_current_preset "${preset_name}"
                    sleep 2
                fi
                ;;
            4)
                clear
                create_default_presets
                sleep 2
                ;;
            *)
                ;;
        esac
    done
}

# Daemon control submenu
ui_daemon_control() {
    while true; do
        # Get current daemon status for display
        local daemon_status_text
        if is_daemon_running; then
            daemon_status_text="RUNNING ✅"
        else
            daemon_status_text="STOPPED ❌"
        fi
        
        local autostart_text
        if systemctl --user is-enabled throttle-me-daemon.service &>/dev/null; then
            autostart_text="ENABLED ✅"
        else
            autostart_text="DISABLED ❌"
        fi
        
        choice=$(dialog --clear \
            --backtitle "throttle-me - Daemon Control" \
            --title "Daemon Control (Status: ${daemon_status_text})" \
            --menu "Manage background daemon:" 20 70 7 \
            1 "Start Daemon" \
            2 "Stop Daemon" \
            3 "Restart Daemon" \
            4 "Enable Auto-Start (Currently: ${autostart_text})" \
            5 "Disable Auto-Start" \
            6 "View Daemon Status & Logs" \
            7 "Back to Settings" \
            3>&1 1>&2 2>&3)
        
        exit_status=$?
        
        if [[ ${exit_status} -ne 0 ]]; then
            return 0
        fi
        
        case ${choice} in
            1)
                # Start daemon
                clear
                daemon_start
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                # Stop daemon
                clear
                daemon_stop
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                # Restart daemon
                clear
                daemon_restart
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                # Enable auto-start
                clear
                daemon_enable
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5)
                # Disable auto-start
                clear
                daemon_disable
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            6)
                # View status and logs
                clear
                daemon_status
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            7)
                return 0
                ;;
            *)
                ;;
        esac
    done
}

# Settings submenu
ui_settings() {
    while true; do
        choice=$(dialog --clear \
            --backtitle "throttle-me - Settings" \
            --title "Settings" \
            --menu "Configure throttle-me:" 22 70 7 \
            1 "Toggle Auto-Enable Hotspot (Currently: ${CONFIG[AUTO_ENABLE]})" \
            2 "Configure Retention Policy" \
            3 "Set Interface Override" \
            4 "Daemon Control" \
            5 "View Current Configuration" \
            6 "Network Detection Info" \
            7 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        exit_status=$?
        
        if [[ ${exit_status} -ne 0 ]]; then
            return 0
        fi
        
        case ${choice} in
            1)
                # Toggle auto-enable
                if [[ "${CONFIG[AUTO_ENABLE]}" == "true" ]]; then
                    CONFIG[AUTO_ENABLE]=false
                    dialog --msgbox "Auto-enable disabled.\n\nBypass will NOT automatically enable when connecting to mobile hotspots." 10 60
                else
                    CONFIG[AUTO_ENABLE]=true
                    dialog --msgbox "Auto-enable enabled.\n\nBypass will automatically enable when connecting to detected mobile hotspots." 10 60
                fi
                ;;
            2)
                # Configure retention
                retention_choice=$(dialog --clear \
                    --title "Retention Policy" \
                    --menu "Choose setting:" 15 60 3 \
                    1 "Set Max Sessions (Current: ${CONFIG[MAX_SESSIONS]})" \
                    2 "Set Max Age Days (Current: ${CONFIG[MAX_AGE_DAYS]})" \
                    3 "View Current Policy" \
                    3>&1 1>&2 2>&3)
                
                case ${retention_choice} in
                    1)
                        max_sessions=$(dialog --inputbox "Enter max number of sessions to keep:" 10 50 "${CONFIG[MAX_SESSIONS]}" 3>&1 1>&2 2>&3)
                        if [[ -n "${max_sessions}" ]] && [[ "${max_sessions}" =~ ^[0-9]+$ ]]; then
                            CONFIG[MAX_SESSIONS]=${max_sessions}
                            dialog --msgbox "Max sessions set to: ${max_sessions}" 8 50
                        fi
                        ;;
                    2)
                        max_age=$(dialog --inputbox "Enter max age in days:" 10 50 "${CONFIG[MAX_AGE_DAYS]}" 3>&1 1>&2 2>&3)
                        if [[ -n "${max_age}" ]] && [[ "${max_age}" =~ ^[0-9]+$ ]]; then
                            CONFIG[MAX_AGE_DAYS]=${max_age}
                            dialog --msgbox "Max age set to: ${max_age} days" 8 50
                        fi
                        ;;
                    3)
                        clear
                        show_retention_info
                        read -rp "Press Enter to continue..."
                        ;;
                    *)
                        ;;
                esac
                ;;
            3)
                # Interface override
                if iface_input=$(dialog --inputbox "Enter wireless interface name (leave blank for auto-detect):" 10 60 "${CONFIG[INTERFACE_OVERRIDE]}" 3>&1 1>&2 2>&3); then
                    CONFIG[INTERFACE_OVERRIDE]="${iface_input}"
                    if [[ -n "${iface_input}" ]]; then
                        dialog --msgbox "Interface override set to: ${iface_input}" 8 50
                    else
                        dialog --msgbox "Interface override cleared.\nUsing auto-detection." 8 50
                    fi
                fi
                ;;
            4)
                # Daemon control submenu
                ui_daemon_control
                ;;
            5)
                # View config
                clear
                show_config
                read -rp "Press Enter to continue..."
                ;;
            6)
                # Network detection info
                clear
                show_detection_info
                read -rp "Press Enter to continue..."
                ;;
            7)
                return 0
                ;;
            *)
                ;;
        esac
    done
}

# Main TUI menu
start_tui() {
    ensure_dialog || return 1
    
    # Create dark theme config
    create_dialog_theme
    
    # Show main banner once
    show_banner
    sleep 1
    
    while true; do
        choice=$(dialog --clear \
            --backtitle "throttle-me v${THROTTLE_ME_VERSION} - Carrier Bypass Manager" \
            --title "MAIN MENU" \
            --menu "Choose an option:" 26 75 9 \
            1 "Enable Bypass (Mobile Hotspot)" \
            2 "Disable Bypass (Regular WiFi)" \
            3 "Check Status" \
            4 "Run Speed Test" \
            5 "Real-Time Network Monitor" \
            6 "Statistics & History" \
            7 "Manage Presets" \
            8 "Settings" \
            9 "Exit" \
            3>&1 1>&2 2>&3)

        exit_status=$?

        # Handle ESC or Cancel
        if [[ ${exit_status} -ne 0 ]]; then
            clear
            return 0
        fi

        case ${choice} in
            1) ui_enable_bypass ;;
            2) ui_disable_bypass ;;
            3) ui_show_status ;;
            4) ui_speed_test ;;
            5) ui_monitor ;;
            6) ui_statistics ;;
            7) ui_presets ;;
            8) ui_settings ;;
            9) clear; return 0 ;;
            *) ;;
        esac
    done
}
