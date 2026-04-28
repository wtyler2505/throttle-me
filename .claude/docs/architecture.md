# System Architecture (v2.0)

## Overview

throttle-me v2.0 is built on a **modular library architecture** with 13 specialized Bash modules totaling 2,295 lines of code. The application supports both interactive TUI and comprehensive CLI modes.

## Project Structure

```
throttle-me/
├── throttle-me              # Main executable - CLI arg parser + TUI launcher
├── throttle-me-daemon       # Background daemon with auto-detection
├── install.sh               # Automated installation script
│
├── lib/                     # 13 modular libraries (2,295 LOC)
│   ├── config.sh           # Configuration file management
│   ├── core.sh             # Core bypass enable/disable logic
│   ├── daemon.sh           # systemd daemon control
│   ├── detection.sh        # Mobile hotspot auto-detection
│   ├── iptables.sh         # iptables wrapper with status queries
│   ├── logging.sh          # Centralized logging and error handling
│   ├── network.sh          # Network interface detection
│   ├── presets.sh          # Configuration preset management
│   ├── retention.sh        # Session data retention policy
│   ├── stats.sh            # Session statistics tracking
│   ├── ui-dialog.sh        # Dialog-based TUI menus (495 LOC)
│   ├── ui-theme.sh         # NSA-inspired theme (ASCII art, colors)
│   └── utils.sh            # Common utilities (sudo caching, etc.)
│
├── config/                  # Configuration templates
│   ├── throttle-me.conf    # Default configuration
│   └── throttle-me-daemon.service  # systemd user service
│
├── docs/                    # User documentation
│   ├── DAEMON.md           # Daemon setup and usage (522 lines)
│   └── QUICKSTART.md       # Quick start guide
│
└── tests/                   # Test directory (future)
```

## Module Dependency Graph

```
throttle-me (main)
    │
    ├─→ logging.sh (error handling, log functions)
    ├─→ utils.sh (sudo caching, common helpers)
    ├─→ config.sh (load/get/set config values)
    │
    ├─→ network.sh (detect wireless interface)
    │     └─→ logging.sh
    │
    ├─→ iptables.sh (iptables operations)
    │     ├─→ logging.sh
    │     └─→ network.sh
    │
    ├─→ core.sh (enable/disable bypass)
    │     ├─→ iptables.sh
    │     ├─→ stats.sh
    │     └─→ logging.sh
    │
    ├─→ detection.sh (hotspot detection)
    │     ├─→ network.sh
    │     ├─→ config.sh
    │     └─→ core.sh
    │
    ├─→ presets.sh (save/load configs)
    │     ├─→ config.sh
    │     └─→ core.sh
    │
    ├─→ stats.sh (session tracking)
    │     ├─→ iptables.sh
    │     └─→ retention.sh
    │
    ├─→ retention.sh (cleanup old data)
    │     └─→ config.sh
    │
    ├─→ daemon.sh (daemon management)
    │     ├─→ logging.sh
    │     └─→ utils.sh
    │
    ├─→ ui-theme.sh (create theme, banner)
    │     └─→ config.sh
    │
    └─→ ui-dialog.sh (TUI menus)
          ├─→ ui-theme.sh
          ├─→ core.sh
          ├─→ stats.sh
          ├─→ presets.sh
          ├─→ daemon.sh
          └─→ detection.sh
```

## Application Flow

```
┌────────────────────────────────────────────────────────┐
│                  throttle-me (main)                    │
│                                                        │
│  1. Parse CLI arguments (getopts)                     │
│  2. Initialize logging                                │
│  3. Load configuration                                │
│  4. Set up error handlers                             │
│                                                        │
│  ┌──────────────────┬──────────────────┐              │
│  │   CLI Mode       │    TUI Mode      │              │
│  │   (-e,-d,-s,etc) │    (default)     │              │
│  └────────┬─────────┴────────┬─────────┘              │
└───────────┼──────────────────┼────────────────────────┘
            │                  │
    ┌───────▼────────┐  ┌──────▼──────────┐
    │  Execute flag  │  │  ui-dialog.sh   │
    │  function      │  │  Main Menu Loop │
    │  and exit      │  └──────┬──────────┘
    └────────────────┘         │
                               │
            ┌──────────────────┴──────────────────┐
            │                                     │
    ┌───────▼────────┐                   ┌───────▼────────┐
    │  User selects  │                   │  Settings      │
    │  bypass action │                   │  submenu       │
    └───────┬────────┘                   └───────┬────────┘
            │                                     │
    ┌───────▼────────┐                   ┌───────▼────────┐
    │  core.sh       │                   │  daemon.sh     │
    │  enable_bypass │                   │  presets.sh    │
    │  disable_bypass│                   │  detection.sh  │
    └───────┬────────┘                   └────────────────┘
            │
    ┌───────▼────────┐
    │  iptables.sh   │
    │  Set TTL=65    │
    │  DNS→1.1.1.1   │
    └───────┬────────┘
            │
    ┌───────▼────────┐
    │  stats.sh      │
    │  Track session │
    └────────────────┘
```

## Core Modules

### 1. config.sh (93 lines, complexity: 13)

**Purpose:** Configuration file management

**Key Functions:**
- `load_config()` - Read from ~/.config/throttle-me/config
- `get_config(key)` - Retrieve config value
- `set_config(key, value)` - Set config value (runtime only)
- `show_config()` - Display current configuration

**Config File Format:**
```bash
# ~/.config/throttle-me/config
AUTO_ENABLE=true
KNOWN_HOTSPOT_SSIDS="Tyler's iPhone,ADE-H4YK3F130DXP"
RETENTION_DAYS=30
DEFAULT_TTL=65
DNS_SERVER="1.1.1.1"
```

### 2. core.sh (180 lines, complexity: 20)

**Purpose:** Core bypass enable/disable logic

**Key Functions:**
- `enable_bypass()` - Activate TTL modification + DNS encryption
- `disable_bypass()` - Restore normal network settings
- `show_status()` - Display current bypass state
- `run_speed_test()` - Integrated speed testing
- `save_current_preset()` - Save current config as preset
- `load_saved_preset(name)` - Load preset configuration

**Bypass Workflow:**
```
enable_bypass()
    │
    ├─→ detect_wireless_interface() [network.sh]
    ├─→ apply_ttl_rules() [iptables.sh]
    ├─→ apply_dns_rules() [iptables.sh]
    ├─→ lock_resolv_conf() [iptables.sh]
    └─→ start_session_tracking() [stats.sh]
```

### 3. iptables.sh (97 lines, complexity: 11)

**Purpose:** iptables/ip6tables operations wrapper

**Key Functions:**
- `is_bypass_active()` - Check if ANY bypass rules exist
- `is_ttl_active()` - Check TTL modification rules
- `is_dns_active()` - Check DNS redirection rules
- `get_bypass_status()` - Detailed status with packet counts
- `get_ttl_packet_count()` - Count packets modified

**iptables Rules Applied:**
```bash
# TTL Modification (Layer 1)
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65
ip6tables -t mangle -A POSTROUTING -j HL --hl-set 65

# DNS Redirection (Layer 2)
iptables -t nat -A OUTPUT -p udp --dport 53 \
  -j DNAT --to-destination 1.1.1.1:53
ip6tables -t nat -A OUTPUT -p udp --dport 53 \
  -j DNAT --to-destination 2606:4700:4700::1111:53

# resolv.conf lock (Layer 3)
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf
```

### 4. network.sh (121 lines, complexity: 20)

**Purpose:** Network interface detection

**Key Functions:**
- `detect_wireless_interface()` - Auto-detect wlo1, wlan0, wlp*, etc.
- `get_gateway_ip()` - Extract default gateway
- `get_current_ssid()` - Get connected WiFi SSID
- `show_network_info()` - Display network details

**Detection Strategy:**
1. Check for user-specified interface (-i flag)
2. Try common interface names (wlo1, wlan0)
3. Use `ip link` to find wireless interfaces
4. Validate interface is UP and has IP address

### 5. detection.sh (143 lines, complexity: 20)

**Purpose:** Mobile hotspot auto-detection

**Key Functions:**
- `is_mobile_hotspot(ssid)` - Check if SSID matches known hotspots
- `detect_hotspot_connection()` - Detect current hotspot connection
- `auto_enable_if_hotspot()` - Enable bypass if hotspot detected
- `monitor_connection_changes()` - Watch for network changes (daemon mode)

**Detection Logic:**
```bash
# Check SSID against known patterns
KNOWN_HOTSPOT_SSIDS="Tyler's iPhone,ADE-H4YK3F130DXP"

# Also check device MAC address patterns (iPhone, Android)
# iPhone: MAC starts with specific OUIs
```

### 6. daemon.sh (229 lines, complexity: 26)

**Purpose:** systemd daemon management

**Key Functions:**
- `daemon_start()` - Start background daemon
- `daemon_stop()` - Stop daemon
- `daemon_restart()` - Restart daemon
- `daemon_status()` - Show daemon state
- `daemon_enable()` - Enable auto-start on boot
- `daemon_disable()` - Disable auto-start
- `daemon_logs()` - View daemon logs
- `daemon_logs_follow()` - Follow logs in real-time
- `is_daemon_running()` - Check if daemon is active

**Daemon Workflow:**
```
throttle-me-daemon
    │
    ├─→ Loop every 5 seconds:
    │     ├─→ detect_hotspot_connection()
    │     ├─→ If hotspot && bypass off → enable_bypass()
    │     └─→ If not hotspot && bypass on → disable_bypass()
    │
    └─→ Log state changes via journalctl
```

### 7. stats.sh (216 lines, complexity: 18)

**Purpose:** Session statistics tracking

**Key Functions:**
- `start_session_tracking()` - Begin new session
- `update_session_stats()` - Update current session
- `end_session_tracking()` - Finalize session
- `show_session_stats()` - Display current stats
- `show_session_history()` - Show all past sessions
- `get_total_data_saved()` - Calculate total data processed

**Session Data Stored:**
```json
{
  "session_id": "20251224_032156",
  "start_time": "2025-12-24 03:21:56",
  "end_time": "2025-12-24 05:45:32",
  "duration_seconds": 8616,
  "packets_modified": 46700,
  "bytes_processed": 3458921,
  "interface": "wlo1",
  "ssid": "Tyler's iPhone"
}
```

**Storage:** `~/.local/share/throttle-me/sessions/YYYYMMDD_HHMMSS.json`

### 8. ui-dialog.sh (495 lines, complexity: 41)

**Purpose:** Dialog-based TUI menus - **Most complex module**

**Key Functions:**
- `ui_main_menu()` - Main menu with 8 options
- `ui_enable_bypass()` - Enable bypass with confirmation
- `ui_disable_bypass()` - Disable bypass with confirmation
- `ui_show_status()` - Status display with real-time data
- `ui_settings_menu()` - Settings submenu
- `ui_daemon_control()` - Daemon control submenu (7 options)
- `ui_presets_menu()` - Preset management submenu
- `ui_stats_menu()` - Statistics display

**Menu Structure:**
```
Main Menu
├── 1. Enable Bypass
├── 2. Disable Bypass
├── 3. Check Status
├── 4. Run Speed Test
├── 5. Show Statistics
│     ├── Current Session
│     └── Session History
├── 6. Network Monitor (bmon)
├── 7. Presets
│     ├── List Presets
│     ├── Save Current
│     ├── Load Preset
│     └── Delete Preset
├── 8. Settings
│     ├── Show Configuration
│     ├── Auto-Detection Info
│     ├── Session Retention Policy
│     └── Daemon Control
│           ├── Start/Stop/Restart
│           ├── Enable/Disable Auto-start
│           └── View Logs
└── 9. Exit
```

### 9. ui-theme.sh (256 lines, complexity: 8)

**Purpose:** NSA-inspired dark theme

**Features:**
- `create_dialog_theme()` - Generate dialogrc theme file
- `show_banner()` - ASCII art banner with figlet
- Green/black color scheme
- Neon accents
- Cyberpunk aesthetic

**Theme Colors:**
- Background: Black (#000000)
- Text: Bright Green (#00FF00)
- Borders: Neon Green (#39FF14)
- Highlights: Matrix Green

### 10. logging.sh (100 lines, complexity: 8)

**Purpose:** Centralized logging and error handling

**Key Functions:**
- `initialize_logging()` - Set up log file
- `log_info(message)` - Info level
- `log_warn(message)` - Warning level
- `log_error(message)` - Error level
- `log_debug(message)` - Debug level (if enabled)
- `error_handler(code, line, command)` - Trap errors

**Log Format:**
```
[2025-12-24 03:21:56] [INFO] Bypass enabled successfully
[2025-12-24 03:22:01] [WARN] High packet count detected: 45000
[2025-12-24 03:22:15] [ERROR] iptables command failed: exit code 1
```

**Log Location:** `~/.local/share/throttle-me/throttle-me.log`

### 11-13. Minor Modules

**presets.sh** (158 lines) - Save/load bypass configurations
**retention.sh** (129 lines) - Auto-cleanup session data after 30 days
**utils.sh** (78 lines) - Sudo caching, common helpers

## Data Flow

### Enable Bypass Flow

```
User: ./throttle-me -e
    │
    ├─→ Parse CLI args (main)
    ├─→ initialize_logging()
    ├─→ load_config()
    │
    ├─→ enable_bypass() [core.sh]
    │     ├─→ detect_wireless_interface() [network.sh]
    │     ├─→ sudo cache started [utils.sh]
    │     │
    │     ├─→ Apply iptables rules [iptables.sh]
    │     │     ├─→ iptables -t mangle TTL=65
    │     │     ├─→ iptables -t nat DNS→1.1.1.1
    │     │     └─→ chattr +i /etc/resolv.conf
    │     │
    │     ├─→ start_session_tracking() [stats.sh]
    │     │     └─→ Create session file
    │     │
    │     └─→ log_info("Bypass enabled")
    │
    └─→ Exit 0
```

### Daemon Auto-Detection Flow

```
throttle-me-daemon (background)
    │
    ├─→ Loop: sleep 5
    │     │
    │     ├─→ get_current_ssid() [network.sh]
    │     ├─→ is_mobile_hotspot(ssid) [detection.sh]
    │     │
    │     ├─→ If mobile hotspot detected:
    │     │     ├─→ is_bypass_active() [iptables.sh]
    │     │     └─→ If not active:
    │     │           └─→ enable_bypass() [core.sh]
    │     │
    │     └─→ If not mobile hotspot:
    │           ├─→ is_bypass_active()
    │           └─→ If active:
    │                 └─→ disable_bypass() [core.sh]
    │
    └─→ Log to journalctl
```

## Performance Characteristics

**Module Load Time:** <100ms (sourcing all 13 libraries)
**Memory Footprint:** ~5MB RSS (Bash + dialog + sourced libraries)
**iptables Operation:** <50ms (kernel space, very fast)
**Session Tracking:** <10ms (simple JSON write)
**Complexity Budget:** 217 total (well within maintainability threshold)

## Security Considerations

**Sudo Requirements:**
- iptables modifications
- /etc/resolv.conf writes
- chattr immutability flag

**Recommended:** Passwordless sudo for specific commands (see docs/DAEMON.md)

**Data Privacy:**
- Session logs stored locally only
- No telemetry or external reporting
- All stats stay in ~/.local/share/throttle-me/

## References

- **Testing:** `.claude/docs/testing.md`
- **Development:** `.claude/workflows/development.md`
- **Deployment:** `.claude/docs/deployment.md`
- **User Guide:** `docs/DAEMON.md`, `docs/QUICKSTART.md`
