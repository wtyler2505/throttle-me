# Essential Project Information

## Project Overview

**Name:** throttle-me  
**Version:** 2.0  
**Type:** Modular Bash TUI Application  
**Purpose:** Terminal-based UI for managing carrier hotspot throttling bypass on Linux

## User Preferences

**User:** Tyler (wtyler)  
**Sudo Password:** 8520  
**Communication Style:** Direct, concise, technical  

**Critical Rules:**
- NEVER launch TUI applications from this terminal
- Use 30-minute timeout (1800000ms) for ALL bash commands
- Use Desktop Commander for file operations
- Verify before reporting completion
- ALWAYS use shellcheck before committing bash code

## Tech Stack

**Primary:**
- Bash 5.2.21 (scripting language)
- dialog 1.3 (TUI framework)
- iptables 1.8.10 (packet filtering)
- GNU coreutils (grep, awk, sed)

**Development Tools:**
- shellcheck - Mandatory bash linting
- scc (3.4.0) - Code statistics
- lizard (1.19.0) - Complexity analysis
- ast-grep (0.39.6) - Structural code search

**Runtime Dependencies:**
- Node.js v20.19.5
- Python 3.12.3
- Git 2.43.0

## Project Structure (v2.0)

```
throttle-me/
├── throttle-me              # Main executable (246 lines)
├── throttle-me-daemon       # Background daemon
├── install.sh               # Installation script (257 lines)
├── lib/                     # Modular library system (13 modules, 2,295 lines total)
│   ├── config.sh           # Configuration management (93 lines, complexity: 13)
│   ├── core.sh             # Enable/disable bypass logic (180 lines, complexity: 20)
│   ├── daemon.sh           # Daemon management (229 lines, complexity: 26)
│   ├── detection.sh        # Hotspot auto-detection (143 lines, complexity: 20)
│   ├── iptables.sh         # iptables operations (97 lines, complexity: 11)
│   ├── logging.sh          # Logging and error handling (100 lines, complexity: 8)
│   ├── network.sh          # Network interface detection (121 lines, complexity: 20)
│   ├── presets.sh          # Configuration presets (158 lines, complexity: 8)
│   ├── retention.sh        # Statistics retention (129 lines, complexity: 11)
│   ├── stats.sh            # Statistics tracking (216 lines, complexity: 18)
│   ├── ui-dialog.sh        # Dialog TUI menus (495 lines, complexity: 41)
│   ├── ui-theme.sh         # NSA-style theming (256 lines, complexity: 8)
│   └── utils.sh            # Common utilities (78 lines, complexity: 13)
├── config/                  # Configuration templates
│   ├── throttle-me.conf    # Default config
│   └── throttle-me-daemon.service  # systemd unit
├── docs/                    # User documentation
│   ├── DAEMON.md           # Daemon usage guide
│   └── QUICKSTART.md       # Quick start guide
└── tests/                   # Test directory
```

**Codebase Statistics (scc v3.4.0):**
- Total Lines: 2,295 (lib modules only)
- Code Lines: 1,650
- Comment Lines: 270
- Blank Lines: 375
- Total Complexity: 217
- Estimated Development Cost: $45,703
- Estimated Schedule: 4.26 months

**Most Complex Modules:**
1. ui-dialog.sh (407 lines, complexity: 41) - TUI menu system
2. daemon.sh (179 lines, complexity: 26) - Daemon management
3. core.sh (131 lines, complexity: 20) - Bypass logic
4. detection.sh (104 lines, complexity: 20) - Auto-detection
5. network.sh (81 lines, complexity: 20) - Interface detection

## Key Features (v2.0)

**Core Functionality:**
1. **Enable Bypass** - TTL=65 + DNS to 1.1.1.1
2. **Disable Bypass** - Restore normal network
3. **Status Check** - Real-time iptables/DNS status
4. **Speed Test** - Integrated bandwidth testing

**Advanced Features:**
5. **Daemon Mode** - Auto-detection of mobile hotspots
6. **Presets** - Save/load bypass configurations
7. **Statistics** - Session tracking with packet counts
8. **Retention Policy** - Auto-cleanup old session data
9. **CLI Mode** - All functions accessible via flags
10. **NSA Theme** - Cyberpunk-style TUI

## Architecture Changes from v1.0 → v2.0

**What Changed:**
- ❌ **Removed:** External scripts (bypass-tethering, disable-bypass-tethering in ~/.local/bin/)
- ✅ **Added:** 13 modular libraries in lib/
- ✅ **Added:** CLI mode with extensive flags (-e, -d, -s, -t, -m, -p, -D, etc.)
- ✅ **Added:** Daemon with auto-detection
- ✅ **Added:** Session statistics and history
- ✅ **Added:** Configuration preset system
- ✅ **Added:** NSA-inspired UI theme

**What Stayed the Same:**
- Core bypass mechanism (TTL modification + DNS encryption)
- iptables rules (mangle table TTL=65, nat table DNS redirect)
- dialog-based TUI interface
- Installation to ~/.local/bin/

## Development Workflow

**Before Committing:**
```bash
# 1. Syntax check
bash -n throttle-me
for f in lib/*.sh; do bash -n "$f"; done

# 2. Shellcheck linting (MANDATORY)
shellcheck throttle-me lib/*.sh

# 3. Functional test
./throttle-me -e && ./throttle-me -s && ./throttle-me -d
```

**Code Statistics:**
```bash
scc lib/                    # Overall stats
scc --by-file lib/         # Per-file breakdown
lizard lib/*.sh            # Complexity analysis
```

**Finding Functions:**
```bash
# All function definitions
rg "^[a-z_]+\(\)" lib/*.sh

# Specific function usage
ast-grep --pattern 'enable_bypass()' --lang bash
```

## Performance Budget (v2.0)

- **Speed Improvement:** 10-15x (0.6 Mbps → 7+ Mbps)
- **CPU Overhead:** <0.1% (iptables in kernel)
- **Memory Usage:** ~5MB RSS (Bash + dialog)
- **Startup Time:** <500ms (TUI launch)
- **Enable/Disable:** <2 seconds (iptables operations)

## Common Pitfalls

1. **Dialog not installed** → Auto-installs via apt-get
2. **Sudo timeout** → Use start_sudo_cache() from utils.sh
3. **Network interface detection fails** → Use -i flag to specify interface
4. **Bypass doesn't work** → Check with -s flag, verify TTL=65 in iptables
5. **Daemon won't start** → Check sudoers configuration in docs/DAEMON.md

## Quick CLI Reference

```bash
./throttle-me              # Interactive TUI
./throttle-me -e           # Enable bypass
./throttle-me -d           # Disable bypass
./throttle-me -s           # Show status
./throttle-me -t           # Run speed test
./throttle-me -m           # Real-time monitor (bmon)
./throttle-me -p           # List presets
./throttle-me -l <preset>  # Load preset
./throttle-me -D start     # Start daemon
./throttle-me -D status    # Daemon status
./throttle-me -a           # Auto-detect and enable
./throttle-me -i wlan0     # Specify interface
```

## Related Documentation

- **Architecture:** `.claude/docs/architecture.md` - v2.0 modular design
- **Testing:** `.claude/docs/testing.md` - Testing strategies
- **Development:** `.claude/workflows/development.md` - Development workflow
- **Deployment:** `.claude/docs/deployment.md` - Installation procedures
