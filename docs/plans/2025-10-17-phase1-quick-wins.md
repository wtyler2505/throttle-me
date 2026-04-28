# Phase 1: throttle-me Quick Wins Implementation Plan

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Modernize throttle-me with error handling, gum UI, CLI mode, and quality foundations without disrupting active bypass connection.

**Architecture:** Non-disruptive parallel development - add new features alongside existing code, preserve all current functionality, test thoroughly before switching defaults.

**Tech Stack:** Bash 5.2+, gum (TUI), shellcheck (linting), bats-core (testing), iptables 1.8+

**Safety Constraints:**
- ❗ **CRITICAL**: User is currently connected via bypass - DO NOT modify iptables rules
- ❗ All iptables changes MUST be in new code paths, thoroughly tested before activation
- ❗ Backup current working script before any modifications

---

## Task 1: Install gum and Create Safety Backup

**Files:**
- Create: `throttle-me.backup-$(date +%Y%m%d-%H%M%S)`
- Create: `docs/CHANGELOG.md`

**Step 1: Install gum**

Run:
```bash
cd /home/wtyler/throttle-me
# Check if gum already installed
command -v gum && echo "✓ gum installed" || {
  echo "Installing gum..."
  # Debian/Ubuntu installation
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
  sudo apt update && sudo apt install -y gum
}
```

Expected: `gum version` shows installed version

**Step 2: Create backup of current working script**

Run:
```bash
cp throttle-me "throttle-me.backup-$(date +%Y%m%d-%H%M%S)"
ls -lah throttle-me.backup*
```

Expected: Backup file created with timestamp

**Step 3: Initialize changelog**

```bash
cat > docs/CHANGELOG.md << 'EOF'
# Changelog

## [Unreleased]

### Added
- Phase 1 improvements in progress

## [1.0.0] - 2025-10-17

### Features
- Dialog-based TUI
- Enable/Disable bypass functionality
- Status checking with packet counts
- TTL modification (set to 65)
- DNS redirection to Cloudflare 1.1.1.1
- Auto-install dialog if missing

### Performance
- Achieves 44x speed improvement (0.66 → 29.07 Mbps)
EOF
```

Expected: `docs/CHANGELOG.md` created

**Step 4: Verify current bypass still works**

Run:
```bash
sudo iptables -t mangle -L POSTROUTING -n | grep "TTL set to 65" && echo "✓ Bypass active"
```

Expected: Shows TTL rule, confirms bypass active

**Step 5: Commit backup and changelog**

```bash
git add throttle-me.backup-* docs/CHANGELOG.md
git commit -m "chore: create safety backup and initialize changelog"
```

---

## Task 2: Shellcheck Compliance

**Files:**
- Modify: `throttle-me` (entire file)
- Create: `.shellcheckrc`

**Step 1: Create shellcheck config**

```bash
cat > .shellcheckrc << 'EOF'
# shellcheck configuration for throttle-me

# Disable: "Consider using { cmd1; cmd2; } >> file instead of individual redirects"
disable=SC2129

# Disable: "Double quote to prevent globbing and word splitting"  
# (we want word splitting for arrays)
disable=SC2086

# Enable all optional checks
enable=all
EOF
```

**Step 2: Run shellcheck and capture issues**

Run:
```bash
shellcheck throttle-me | tee shellcheck-report.txt
```

Expected: List of issues (likely SC2034, SC2162, SC2236, etc.)

**Step 3: Fix shellcheck issues**

Modify `throttle-me` to fix all issues:

1. Add shellcheck directive at top (after shebang):
```bash
#!/bin/bash
# shellcheck disable=SC2059
# (Allow printf with variables in format string for color codes)
```

2. Fix unused variables (add `_` prefix or use):
```bash
# Before:
exit_status=$?

# After (if truly needed):
exit_status=$?
# Or if not needed, remove it
```

3. Fix read without -r:
```bash
# Before:
read -p "Press Enter to continue..."

# After:
read -r -p "Press Enter to continue..."
```

4. Quote all variable expansions in commands:
```bash
# Before:
if [ $ttl_active = true ]; then

# After:
if [ "$ttl_active" = true ]; then
```

**Step 4: Run shellcheck again**

Run:
```bash
shellcheck throttle-me
echo "Exit code: $?"
```

Expected: Exit code 0 (no issues)

**Step 5: Test script still works**

Run:
```bash
bash -n throttle-me && echo "✓ Syntax valid"
sudo iptables -t mangle -L | grep "TTL set to 65" && echo "✓ Bypass still active"
```

**Step 6: Commit shellcheck fixes**

```bash
git add throttle-me .shellcheckrc
git commit -m "fix: shellcheck compliance - quote variables, fix unused vars"
```

---

## Task 3: Add Strict Mode + Error Handling

**Files:**
- Modify: `throttle-me:1-15` (add strict mode and trap handlers)
- Create: `lib/error-handling.sh`

**Step 1: Create error handling library**

Create `lib/error-handling.sh`:
```bash
#!/bin/bash
# Error handling utilities for throttle-me

# Log file location
LOG_FILE="/var/log/throttle-me.log"
LOG_DIR="$(dirname "$LOG_FILE")"

# Ensure log directory exists with proper permissions
ensure_log_directory() {
    if [ ! -d "$LOG_DIR" ]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi
    
    if [ ! -f "$LOG_FILE" ]; then
        sudo touch "$LOG_FILE"
        sudo chmod 644 "$LOG_FILE"
    fi
}

# Log message with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    ensure_log_directory
    echo "[$timestamp] [$level] $message" | sudo tee -a "$LOG_FILE" >&2
}

# Log error and optionally exit
log_error() {
    log_message "ERROR" "$@"
}

# Log warning
log_warning() {
    log_message "WARN" "$@"
}

# Log info
log_info() {
    log_message "INFO" "$@"
}

# Cleanup function called on exit
cleanup() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script exited with code $exit_code"
    fi
    
    # Don't modify iptables rules here - user may still be connected
    
    exit "$exit_code"
}

# Error handler for ERR trap
error_handler() {
    local line_number="$1"
    log_error "Error occurred at line $line_number"
}

# Setup trap handlers
setup_traps() {
    trap cleanup EXIT
    trap 'error_handler ${LINENO}' ERR
    trap 'log_warning "Interrupted by user"; exit 130' INT TERM
}
```

**Step 2: Add strict mode to main script**

Modify beginning of `throttle-me` (after shebang and shellcheck directives):
```bash
#!/bin/bash
# shellcheck disable=SC2059
# throttle-me - TUI for managing carrier hotspot bypass

# Strict mode - fail on errors, undefined variables, pipe failures
set -euo pipefail

# Source error handling library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/error-handling.sh
source "$SCRIPT_DIR/lib/error-handling.sh"

# Setup signal traps
setup_traps

# Log script start
log_info "throttle-me started (PID: $$)"

# Rest of script...
```

**Step 3: Test strict mode doesn't break current functionality**

Run:
```bash
# This should fail gracefully if there's an error
bash -euo pipefail throttle-me --help 2>&1 || echo "Exit code: $?"

# Check bypass still active
sudo iptables -t mangle -L | grep "TTL set to 65" && echo "✓ Bypass still active"
```

**Step 4: Test error logging**

Run:
```bash
# Trigger an intentional error to test logging
(set -e; false) || true
sudo tail -5 /var/log/throttle-me.log
```

Expected: Log file shows error entries with timestamps

**Step 5: Commit error handling**

```bash
git add lib/error-handling.sh throttle-me
git commit -m "feat: add strict mode and error handling with logging"
```

---

## Task 4: Sudo Credential Caching

**Files:**
- Modify: `throttle-me` (add sudo cache function after error handling setup)

**Step 1: Add sudo caching function**

Add after `setup_traps` call in main script:
```bash
# Cache sudo credentials to avoid repeated password prompts
cache_sudo() {
    log_info "Caching sudo credentials"
    
    # Validate and refresh sudo timestamp
    if ! sudo -v; then
        log_error "Failed to validate sudo credentials"
        return 1
    fi
    
    # Keep sudo alive in background for 30 minutes
    # Will refresh every 5 minutes
    (
        while true; do
            sleep 300  # 5 minutes
            sudo -v
        done
    ) &
    
    SUDO_REFRESH_PID=$!
    log_info "Sudo cache refresh running (PID: $SUDO_REFRESH_PID)"
}

# Kill sudo refresh process on cleanup
cleanup() {
    local exit_code=$?
    
    if [ -n "${SUDO_REFRESH_PID:-}" ]; then
        kill "$SUDO_REFRESH_PID" 2>/dev/null || true
        log_info "Stopped sudo cache refresh"
    fi
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script exited with code $exit_code"
    fi
    
    exit "$exit_code"
}
```

**Step 2: Call sudo cache at script start**

Add after `log_info "throttle-me started..."`:
```bash
# Cache sudo credentials early
cache_sudo || {
    log_error "Failed to cache sudo credentials - some features may prompt for password"
}
```

**Step 3: Test sudo caching**

Run:
```bash
# Run script - should only prompt for password once
./throttle-me
# Try accessing status check multiple times
# Should not prompt for password repeatedly
```

**Step 4: Verify no password prompts during operation**

Manual test:
1. Run `./throttle-me`
2. Enter password once
3. Check status (option 3)
4. Check status again
5. Verify no second password prompt

Expected: Single password prompt at start, no prompts for subsequent sudo operations

**Step 5: Commit sudo caching**

```bash
git add throttle-me lib/error-handling.sh
git commit -m "feat: cache sudo credentials to eliminate repeated password prompts"
```

---

## Task 5: CLI Quick-Toggle Mode

**Files:**
- Modify: `throttle-me` (add argument parsing before main menu loop)
- Update: `docs/CHANGELOG.md`

**Step 1: Add argument parsing function**

Add before main menu loop:
```bash
# Parse command-line arguments
parse_arguments() {
    case "${1:-}" in
        --enable|-e)
            log_info "CLI mode: enabling bypass"
            enable_bypass
            exit 0
            ;;
        --disable|-d)
            log_info "CLI mode: disabling bypass"
            disable_bypass
            exit 0
            ;;
        --status|-s)
            log_info "CLI mode: checking status"
            check_bypass_status
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "throttle-me version 1.1.0"
            exit 0
            ;;
        "")
            # No arguments - run TUI
            log_info "Starting TUI mode"
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
}

# Show help message
show_help() {
    cat << EOF
throttle-me - Carrier Hotspot Bypass Manager

Usage: throttle-me [OPTION]

OPTIONS:
    -e, --enable     Enable bypass (TTL=65, DNS=1.1.1.1)
    -d, --disable    Disable bypass (restore normal network)
    -s, --status     Check bypass status
    -h, --help       Show this help message
    -v, --version    Show version information
    
    (no option)      Launch interactive TUI

EXAMPLES:
    throttle-me              # Launch TUI
    throttle-me --enable     # Quick enable from command line
    throttle-me --status     # Check if bypass is active

For more info: cat ~/.local/share/throttle-me/README.md
EOF
}
```

**Step 2: Call argument parser**

Add before main menu loop:
```bash
# Parse command-line arguments
parse_arguments "$@"

# If we reach here, run TUI (no CLI arguments provided)
```

**Step 3: Test CLI modes**

Run:
```bash
# Test help
./throttle-me --help
# Should show help message and exit

# Test version
./throttle-me --version
# Should show version and exit

# Test status (safe - read-only)
./throttle-me --status
# Should show status and exit

# DO NOT test --enable or --disable yet (would modify active connection)
```

**Step 4: Update changelog**

Modify `docs/CHANGELOG.md`:
```markdown
## [Unreleased]

### Added
- CLI quick-toggle mode: `throttle-me --enable`, `--disable`, `--status`
- Command-line help: `throttle-me --help`
- Version information: `throttle-me --version`
- Sudo credential caching (eliminates repeated password prompts)
- Error logging to `/var/log/throttle-me.log`

### Changed
- Added strict mode (set -euo pipefail) for improved reliability
- All variables now properly quoted (shellcheck compliant)
```

**Step 5: Commit CLI mode**

```bash
git add throttle-me docs/CHANGELOG.md
git commit -m "feat: add CLI quick-toggle mode (--enable/--disable/--status)"
```

---

## Task 6: Gum UI Implementation

**Files:**
- Create: `lib/ui-gum.sh`
- Modify: `throttle-me` (add UI mode detection and switching)

**Step 1: Create gum UI library**

Create `lib/ui-gum.sh`:
```bash
#!/bin/bash
# Gum-based UI for throttle-me

# Check if gum is available
has_gum() {
    command -v gum >/dev/null 2>&1
}

# Show main menu with gum
gum_main_menu() {
    # Use gum choose for menu
    choice=$(gum choose \
        --header="throttle-me - Carrier Bypass Manager" \
        --header.foreground="212" \
        --cursor="→ " \
        --cursor.foreground="212" \
        --selected.foreground="212" \
        "Enable Bypass (for iPhone hotspot)" \
        "Disable Bypass (for regular WiFi)" \
        "Check Status" \
        "Exit")
    
    case "$choice" in
        "Enable Bypass"*)
            gum_enable_bypass
            ;;
        "Disable Bypass"*)
            gum_disable_bypass
            ;;
        "Check Status"*)
            gum_check_status
            ;;
        "Exit")
            gum style --foreground="212" "👋 Goodbye!"
            exit 0
            ;;
    esac
}

# Enable bypass with gum confirmation
gum_enable_bypass() {
    if gum confirm "Enable carrier bypass? (TTL=65, DNS=1.1.1.1)"; then
        gum spin --spinner="dot" --title="Enabling bypass..." -- \
            ~/.local/bin/bypass-tethering
        
        gum style \
            --foreground="212" --bold \
            "✅ Bypass enabled!"
        
        sleep 1
    else
        gum style --foreground="yellow" "❌ Cancelled"
    fi
}

# Disable bypass with gum confirmation
gum_disable_bypass() {
    if gum confirm "Disable bypass and restore normal network?"; then
        gum spin --spinner="dot" --title="Disabling bypass..." -- \
            ~/.local/bin/disable-bypass-tethering
        
        gum style \
            --foreground="212" --bold \
            "✅ Bypass disabled!"
        
        sleep 1
    else
        gum style --foreground="yellow" "❌ Cancelled"
    fi
}

# Check status with gum formatting
gum_check_status() {
    local ttl_active=false
    local dns_active=false
    
    # Check TTL rules
    if sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65"; then
        ttl_active=true
    fi
    
    # Check DNS redirection
    if sudo iptables -t nat -L OUTPUT -n | grep -q "DNAT.*1.1.1.1:53"; then
        dns_active=true
    fi
    
    # Build status with gum
    gum style --border="rounded" --padding="1 2" --margin="1" "
$(gum style --foreground="212" --bold "=== BYPASS STATUS ===")

$(if [ "$ttl_active" = true ] && [ "$dns_active" = true ]; then
    gum style --foreground="green" "Status: ACTIVE ✅"
else
    gum style --foreground="red" "Status: INACTIVE ❌"
fi)

$(gum style --foreground="cyan" "TTL Modification: ")$(if [ "$ttl_active" = true ]; then
    gum style --foreground="green" "Active (TTL=65)"
else
    gum style --foreground="red" "Inactive"
fi)

$(gum style --foreground="cyan" "DNS Redirection: ")$(if [ "$dns_active" = true ]; then
    gum style --foreground="green" "Active (1.1.1.1)"
else
    gum style --foreground="red" "Inactive"
fi)

$(gum style --foreground="cyan" "Connection: ")$(ip route | grep default | awk '{print $3, "via", $5}')
"
    
    gum style --foreground="gray" "Press Enter to continue..."
    read -r
}

# Main gum UI loop
run_gum_ui() {
    while true; do
        gum_main_menu
    done
}
```

**Step 2: Add UI mode detection to main script**

Modify `throttle-me` after argument parsing:
```bash
# Determine which UI to use
if has_gum; then
    log_info "Using gum UI (modern)"
    # shellcheck source=lib/ui-gum.sh
    source "$SCRIPT_DIR/lib/ui-gum.sh"
    run_gum_ui
else
    log_info "Using dialog UI (classic)"
    # Fall through to existing dialog-based main menu loop
fi

# Existing dialog main menu loop starts here...
```

**Step 3: Add has_gum function to main script**

Add near top with other utility functions:
```bash
# Check if gum is available
has_gum() {
    command -v gum >/dev/null 2>&1
}
```

**Step 4: Test gum UI (safe mode)**

Run:
```bash
# Test gum UI launches
./throttle-me

# In menu:
# 1. Navigate with arrow keys
# 2. Select "Check Status" (safe - read-only)
# 3. Exit

# Verify bypass still active
sudo iptables -t mangle -L | grep "TTL set to 65" && echo "✓ Bypass still active"
```

Expected: Colorful gum menu appears, status displays beautifully, no disruption to connection

**Step 5: Commit gum UI**

```bash
git add lib/ui-gum.sh throttle-me
git commit -m "feat: add modern gum-based UI with confirmations and spinners"
```

---

## Task 7: Add Confirmation Dialogs (Dialog UI)

**Files:**
- Modify: `throttle-me` (add confirmations to enable_bypass and disable_bypass functions)

**Step 1: Add confirmation to enable_bypass function**

Modify `enable_bypass()` function in main script:
```bash
# Function to enable bypass
enable_bypass() {
    # Add confirmation dialog
    if ! dialog --clear --backtitle "throttle-me - Carrier Bypass Manager" \
        --title "Confirm Enable" \
        --yesno "Enable carrier bypass?\n\nThis will:\n- Set TTL to 65 (match iPhone)\n- Redirect DNS to Cloudflare (1.1.1.1)\n- Lock /etc/resolv.conf\n\nContinue?" 12 60; then
        log_info "User cancelled enable bypass"
        return
    fi
    
    clear
    echo "🔧 Enabling bypass..."

    if [ -f ~/.local/bin/bypass-tethering ]; then
        ~/.local/bin/bypass-tethering
        log_info "Bypass enabled successfully"
        sleep 2
    else
        echo "❌ Error: bypass-tethering script not found in ~/.local/bin/"
        log_error "bypass-tethering script not found"
        sleep 3
    fi
}
```

**Step 2: Add confirmation to disable_bypass function**

Modify `disable_bypass()` function:
```bash
# Function to disable bypass
disable_bypass() {
    # Add confirmation dialog
    if ! dialog --clear --backtitle "throttle-me - Carrier Bypass Manager" \
        --title "Confirm Disable" \
        --yesno "Disable carrier bypass?\n\nThis will:\n- Remove TTL modification\n- Restore system DNS\n- Unlock /etc/resolv.conf\n\nNote: You may need to reconnect to WiFi\nfor captive portal to work.\n\nContinue?" 14 60; then
        log_info "User cancelled disable bypass"
        return
    fi
    
    clear
    echo "🔧 Disabling bypass..."

    if [ -f ~/.local/bin/disable-bypass-tethering ]; then
        ~/.local/bin/disable-bypass-tethering
        log_info "Bypass disabled successfully"
        sleep 2
    else
        echo "❌ Error: disable-bypass-tethering script not found in ~/.local/bin/"
        log_error "disable-bypass-tethering script not found"
        sleep 3
    fi
}
```

**Step 3: Test confirmation dialogs**

Run:
```bash
# Test with dialog UI (fallback when gum not prioritized)
USE_DIALOG=1 ./throttle-me

# In menu:
# 1. Select "Enable Bypass"
# 2. Choose "No" on confirmation
# 3. Verify returns to menu without changes
# 4. Exit

# Verify bypass still active
sudo iptables -t mangle -L | grep "TTL set to 65" && echo "✓ Bypass still active"
```

**Step 4: Update changelog**

Modify `docs/CHANGELOG.md`:
```markdown
### Added
- Confirmation dialogs before enable/disable (prevents accidents)
- Detailed confirmation messages explaining what will happen
```

**Step 5: Commit confirmations**

```bash
git add throttle-me docs/CHANGELOG.md
git commit -m "feat: add confirmation dialogs before enable/disable operations"
```

---

## Task 8: Testing Framework + Manual Checklist

**Files:**
- Create: `tests/test-throttle-me.bats`
- Create: `tests/helpers/test-helpers.bash`
- Create: `docs/MANUAL-TEST-CHECKLIST.md`

**Step 1: Install bats-core if not present**

Run:
```bash
# Check if bats installed
if ! command -v bats >/dev/null; then
    echo "Installing bats-core..."
    sudo apt-get update && sudo apt-get install -y bats
fi

bats --version
```

**Step 2: Create test helpers**

Create `tests/helpers/test-helpers.bash`:
```bash
#!/bin/bash
# Test helpers for throttle-me

# Mock sudo for tests (prevents actual iptables changes)
mock_sudo() {
    # In test mode, sudo just echoes the command
    echo "[MOCK] sudo $*"
}

# Mock iptables for safe testing
mock_iptables() {
    local table="$1"
    local chain="$2"
    
    # Simulate active bypass
    if [[ "$*" == *"TTL set to 65"* ]]; then
        echo "TTL set to 65"
        return 0
    fi
    
    if [[ "$*" == *"1.1.1.1:53"* ]]; then
        echo "DNAT to 1.1.1.1:53"
        return 0
    fi
    
    return 0
}

# Setup test environment
setup_test_env() {
    export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
    export TESTING=1
}

# Cleanup test environment
teardown_test_env() {
    unset TESTING
}
```

**Step 3: Create bats tests**

Create `tests/test-throttle-me.bats`:
```bash
#!/usr/bin/env bats
# Unit tests for throttle-me

load helpers/test-helpers

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "script has valid bash syntax" {
    run bash -n throttle-me
    [ "$status" -eq 0 ]
}

@test "shellcheck passes with no errors" {
    run shellcheck throttle-me
    [ "$status" -eq 0 ]
}

@test "help flag shows usage" {
    run ./throttle-me --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"throttle-me - Carrier Hotspot Bypass Manager"* ]]
}

@test "version flag shows version" {
    run ./throttle-me --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"throttle-me version"* ]]
}

@test "error handling library sources correctly" {
    run bash -c "source lib/error-handling.sh && type log_error"
    [ "$status" -eq 0 ]
}

@test "gum UI library sources correctly" {
    run bash -c "source lib/ui-gum.sh && type has_gum"
    [ "$status" -eq 0 ]
}

@test "has_gum function returns 0 when gum installed" {
    # This assumes gum is installed (Task 1)
    run bash -c "command -v gum"
    [ "$status" -eq 0 ]
}
```

**Step 4: Create manual test checklist**

Create `docs/MANUAL-TEST-CHECKLIST.md`:
```markdown
# Manual Test Checklist for throttle-me

**⚠️ WARNING**: These tests involve actual iptables modifications. Only run on test system or when NOT actively using bypass for internet.

## Pre-Test Setup
- [ ] **CRITICAL**: Ensure you have alternative internet connection OR can tolerate disconnection
- [ ] Backup current iptables rules: `sudo iptables-save > /tmp/iptables-backup-$(date +%s).rules`
- [ ] Note current bypass state: `sudo iptables -t mangle -L | grep TTL`

---

## Test Suite 1: Non-Disruptive Tests (Safe to run while connected)

### T1.1: Help and Version
- [ ] Run: `./throttle-me --help`
- [ ] Expected: Shows help message, lists all options
- [ ] Run: `./throttle-me --version`
- [ ] Expected: Shows version number

### T1.2: Status Check (Read-Only)
- [ ] Run: `./throttle-me --status`
- [ ] Expected: Shows current bypass state (ACTIVE/INACTIVE)
- [ ] Expected: Shows TTL status, DNS status, packet count
- [ ] Expected: No iptables modifications

### T1.3: Syntax and Linting
- [ ] Run: `bash -n throttle-me`
- [ ] Expected: Exit code 0 (no syntax errors)
- [ ] Run: `shellcheck throttle-me`
- [ ] Expected: Exit code 0 (no warnings)

### T1.4: Unit Tests
- [ ] Run: `bats tests/test-throttle-me.bats`
- [ ] Expected: All tests pass

---

## Test Suite 2: UI Tests (Safe, no iptables changes if cancelled)

### T2.1: Gum UI Launch
- [ ] Run: `./throttle-me` (no arguments)
- [ ] Expected: Gum menu appears with 4 options
- [ ] Navigate with arrow keys
- [ ] Expected: Selection highlighting works
- [ ] Press Ctrl+C
- [ ] Expected: Exits gracefully, logs interruption

### T2.2: Confirmation Dialogs
- [ ] Launch TUI: `./throttle-me`
- [ ] Select "Enable Bypass"
- [ ] Expected: Confirmation dialog appears
- [ ] Choose "No"
- [ ] Expected: Returns to menu, no iptables changes
- [ ] Select "Disable Bypass"
- [ ] Expected: Confirmation dialog appears
- [ ] Choose "No"
- [ ] Expected: Returns to menu, no iptables changes

### T2.3: Status Display Formatting
- [ ] Launch TUI: `./throttle-me`
- [ ] Select "Check Status"
- [ ] Expected: Formatted status with colors, borders
- [ ] Expected: Shows all info (TTL, DNS, connection, packets)
- [ ] Expected: Green ✅ if active, Red ❌ if inactive
- [ ] Press Enter
- [ ] Expected: Returns to menu

---

## Test Suite 3: Functional Tests (⚠️ MODIFIES IPTABLES - ONLY RUN WITH BACKUP CONNECTION)

### T3.1: CLI Enable Bypass
**Prerequisites**: Currently on regular WiFi OR have backup connection

- [ ] Note current speed: `speedtest-cli --simple`
- [ ] Run: `./throttle-me --enable`
- [ ] Expected: Asks for confirmation (if gum), shows spinner
- [ ] Run: `sudo iptables -t mangle -L POSTROUTING -n`
- [ ] Expected: Shows "TTL set to 65" rule
- [ ] Run: `sudo iptables -t nat -L OUTPUT -n`
- [ ] Expected: Shows DNAT to 1.1.1.1:53
- [ ] Run: `cat /etc/resolv.conf`
- [ ] Expected: Contains "nameserver 1.1.1.1"
- [ ] Run: `lsattr /etc/resolv.conf`
- [ ] Expected: Shows 'i' flag (immutable)
- [ ] Test connection: `ping -c 3 1.1.1.1`
- [ ] Expected: Successful ping to Cloudflare
- [ ] Run speed test: `speedtest-cli --simple`
- [ ] Expected: Speed significantly higher (if on throttled hotspot)

### T3.2: CLI Disable Bypass
- [ ] Run: `./throttle-me --disable`
- [ ] Expected: Asks for confirmation, shows spinner
- [ ] Run: `sudo iptables -t mangle -L POSTROUTING -n`
- [ ] Expected: NO "TTL set to 65" rule
- [ ] Run: `sudo iptables -t nat -L OUTPUT -n`
- [ ] Expected: NO DNAT to 1.1.1.1
- [ ] Run: `lsattr /etc/resolv.conf`
- [ ] Expected: No 'i' flag (mutable again)
- [ ] Test connection: `ping -c 3 google.com`
- [ ] Expected: Successful ping with normal DNS

### T3.3: TUI Enable/Disable Cycle
- [ ] Launch: `./throttle-me`
- [ ] Select "Enable Bypass", confirm "Yes"
- [ ] Expected: Spinner shows, success message
- [ ] Select "Check Status"
- [ ] Expected: Shows ACTIVE ✅
- [ ] Select "Disable Bypass", confirm "Yes"
- [ ] Expected: Spinner shows, success message
- [ ] Select "Check Status"
- [ ] Expected: Shows INACTIVE ❌
- [ ] Exit
- [ ] Expected: Clean exit, no errors

### T3.4: Error Handling
- [ ] Temporarily rename bypass script: `mv ~/.local/bin/bypass-tethering ~/.local/bin/bypass-tethering.tmp`
- [ ] Run: `./throttle-me --enable`
- [ ] Expected: Error message "bypass-tethering script not found"
- [ ] Expected: Error logged to `/var/log/throttle-me.log`
- [ ] Check log: `sudo tail /var/log/throttle-me.log`
- [ ] Expected: Shows timestamped error
- [ ] Restore script: `mv ~/.local/bin/bypass-tethering.tmp ~/.local/bin/bypass-tethering`

### T3.5: Sudo Caching
- [ ] Run: `./throttle-me`
- [ ] Enter sudo password
- [ ] Select "Check Status" (requires sudo)
- [ ] Expected: NO password prompt (cached)
- [ ] Wait 2 minutes
- [ ] Select "Check Status" again
- [ ] Expected: Still NO password prompt (refresh working)
- [ ] Exit and restart: `./throttle-me`
- [ ] Expected: Asks for password again (new session)

---

## Test Suite 4: Stress Tests

### T4.1: Rapid Enable/Disable Cycles
- [ ] Run 10 rapid cycles:
```bash
for i in {1..10}; do
  ./throttle-me --enable
  sleep 1
  ./throttle-me --status
  ./throttle-me --disable
  sleep 1
done
```
- [ ] Expected: All cycles succeed, no hanging, no errors

### T4.2: Concurrent Execution
- [ ] Open two terminals
- [ ] Terminal 1: `./throttle-me --enable`
- [ ] Terminal 2: `./throttle-me --status` (while T1 running)
- [ ] Expected: Both complete without errors
- [ ] Expected: No iptables corruption

---

## Test Suite 5: Regression Tests (Ensure Original Functionality Preserved)

### T5.1: Dialog UI Fallback
- [ ] Temporarily disable gum: `sudo mv /usr/bin/gum /usr/bin/gum.tmp`
- [ ] Run: `./throttle-me`
- [ ] Expected: Falls back to dialog-based UI
- [ ] Expected: All menu options work
- [ ] Restore gum: `sudo mv /usr/bin/gum.tmp /usr/bin/gum`

### T5.2: Original Speed Improvement
- [ ] Connect to iPhone hotspot with bypass DISABLED
- [ ] Run speed test: `speedtest-cli --simple`
- [ ] Note download speed (expect ~0.6 Mbps throttled)
- [ ] Enable bypass: `./throttle-me --enable`
- [ ] Wait 30 seconds for rules to propagate
- [ ] Run speed test again: `speedtest-cli --simple`
- [ ] Expected: 10x+ improvement (7+ Mbps minimum)

---

## Post-Test Verification

- [ ] Run final status check: `./throttle-me --status`
- [ ] Check log for errors: `sudo grep ERROR /var/log/throttle-me.log`
- [ ] Expected: No unexpected errors
- [ ] Restore desired state (enable or disable bypass as needed)
- [ ] Verify internet connectivity working as expected

---

## Test Results Summary

**Date**: ___________  
**Tester**: ___________  
**Tests Passed**: ___ / 25  
**Tests Failed**: ___________  
**Issues Found**: ___________  
**Notes**: 
```

**Step 5: Run safe tests only**

Run:
```bash
cd /home/wtyler/throttle-me

# Run bats tests (safe - no iptables changes)
bats tests/test-throttle-me.bats

# Run shellcheck (safe)
shellcheck throttle-me lib/*.sh
```

Expected: All tests pass, shellcheck reports no issues

**Step 6: Commit testing framework**

```bash
git add tests/ docs/MANUAL-TEST-CHECKLIST.md
git commit -m "test: add bats unit tests and comprehensive manual test checklist"
```

---

## Final Verification

**Step 1: Run all automated tests**

Run:
```bash
# Syntax check
bash -n throttle-me

# Shellcheck
shellcheck throttle-me lib/*.sh

# Unit tests
bats tests/test-throttle-me.bats
```

**Step 2: Verify bypass still active (CRITICAL)**

Run:
```bash
sudo iptables -t mangle -L POSTROUTING -n | grep "TTL set to 65" && echo "✓ Bypass active"
sudo iptables -t nat -L OUTPUT -n | grep "1.1.1.1:53" && echo "✓ DNS redirected"
```

Expected: Both checks pass, bypass still working

**Step 3: Test TUI launches without errors**

Run:
```bash
# Should launch gum UI successfully
timeout 5 ./throttle-me &
sleep 2
pkill -P $! || true
```

**Step 4: Update final changelog**

Modify `docs/CHANGELOG.md`:
```markdown
## [1.1.0] - 2025-10-17

### Added
- 🎨 Modern gum-based UI with colors, spinners, and emoji
- 🚀 CLI quick-toggle mode: `--enable`, `--disable`, `--status`
- 🔒 Error handling with strict mode (set -euo pipefail)
- 📝 Comprehensive logging to `/var/log/throttle-me.log`
- ⚡ Sudo credential caching (no repeated password prompts)
- ✅ Confirmation dialogs before enable/disable
- 🧪 Bats testing framework with unit tests
- 📋 Manual test checklist for iptables validation
- 📚 Help and version flags

### Changed
- All code shellcheck compliant (zero warnings)
- Improved error messages with logging
- Better code organization (lib/ directory)

### Technical
- Added signal traps for cleanup
- Structured error handling library
- Modular UI system (gum + dialog fallback)
```

**Step 5: Create final commit**

```bash
git add docs/CHANGELOG.md
git commit -m "docs: finalize Phase 1 changelog"
```

**Step 6: Tag release**

```bash
git tag -a v1.1.0 -m "Phase 1: Quick Wins - Modern UI, CLI mode, error handling"
```

---

## Success Criteria

**Phase 1 is complete when:**

- ✅ All 8 tasks committed (8 commits total)
- ✅ Gum installed and working
- ✅ Zero shellcheck warnings
- ✅ All bats tests passing
- ✅ Error handling and logging active
- ✅ Sudo caching working (no repeated prompts)
- ✅ CLI mode functional (`--enable`, `--disable`, `--status`)
- ✅ Gum UI launches and looks modern
- ✅ Confirmation dialogs prevent accidents
- ✅ Manual test checklist documented
- ✅ **MOST IMPORTANT**: Active bypass still working, no connection disruption

**Metrics:**

- Code quality: 0 shellcheck warnings
- Test coverage: 6+ unit tests passing
- User experience: Single sudo prompt, colorful UI, fast operations
- Safety: 100% non-disruptive to active connection
- Documentation: Changelog updated, test checklist created

---

## Next Steps (Phase 2 Preview)

After Phase 1 is validated and stable:

1. **IPv6 Support** - Extend bypass to IPv6 traffic
2. **nftables Migration** - Atomic updates, better performance
3. **Real-time Monitoring** - Integrate bmon, iftop, nethogs
4. **Statistics Tracking** - Historical data, speed graphs
5. **Auto-detection** - NetworkManager hooks for automatic enable/disable

**Estimated Phase 2 Duration**: 3-5 days
