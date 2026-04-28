#!/bin/bash
# verify-env.sh - Check and guide user through throttle-me daemon prerequisites

set -euo pipefail

echo "=== throttle-me Environment Verification ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_passed=0
check_failed=0

# Check 1: Daemon script installed
echo -n "Checking daemon script... "
if [[ -x "$HOME/.local/bin/throttle-me-daemon" ]]; then
    echo -e "${GREEN}✓ Found${NC}"
    ((check_passed++))
else
    echo -e "${RED}✗ Missing${NC}"
    echo "  Install with: cp throttle-me-daemon ~/.local/bin/ && chmod +x ~/.local/bin/throttle-me-daemon"
    ((check_failed++))
fi

# Check 2: Systemd service installed
echo -n "Checking systemd service... "
if [[ -f "$HOME/.config/systemd/user/throttle-me-daemon.service" ]]; then
    echo -e "${GREEN}✓ Found${NC}"
    ((check_passed++))
else
    echo -e "${RED}✗ Missing${NC}"
    echo "  Install with: cp config/throttle-me-daemon.service ~/.config/systemd/user/ && systemctl --user daemon-reload"
    ((check_failed++))
fi

# Check 3: bypass-tethering script
echo -n "Checking bypass-tethering script... "
if [[ -x "$HOME/.local/bin/bypass-tethering" ]]; then
    echo -e "${GREEN}✓ Found${NC}"
    ((check_passed++))
else
    echo -e "${RED}✗ Missing${NC}"
    echo "  This script is required for bypass functionality"
    ((check_failed++))
fi

# Check 4: disable-bypass-tethering script
echo -n "Checking disable-bypass-tethering script... "
if [[ -x "$HOME/.local/bin/disable-bypass-tethering" ]]; then
    echo -e "${GREEN}✓ Found${NC}"
    ((check_passed++))
else
    echo -e "${RED}✗ Missing${NC}"
    echo "  This script is required for bypass functionality"
    ((check_failed++))
fi

# Check 5: sudoers passwordless access
echo -n "Checking sudoers configuration... "
if sudo -n "$HOME/.local/bin/bypass-tethering" --version &>/dev/null 2>&1; then
    echo -e "${GREEN}✓ Configured${NC}"
    ((check_passed++))
else
    echo -e "${YELLOW}✗ Not configured${NC}"
    echo ""
    echo -e "${YELLOW}  ⚠️  REQUIRED: Daemon needs passwordless sudo access${NC}"
    echo ""
    echo "  Run this command to configure:"
    echo -e "    ${GREEN}sudo visudo -f /etc/sudoers.d/throttle-me${NC}"
    echo ""
    echo "  Add these two lines:"
    echo -e "    ${GREEN}$USER ALL=(ALL) NOPASSWD: $HOME/.local/bin/bypass-tethering${NC}"
    echo -e "    ${GREEN}$USER ALL=(ALL) NOPASSWD: $HOME/.local/bin/disable-bypass-tethering${NC}"
    echo ""
    echo "  Save and exit (Ctrl+O, Enter, Ctrl+X)"
    echo ""
    ((check_failed++))
fi

# Check 6: notify-send (optional)
echo -n "Checking notify-send (optional)... "
if command -v notify-send &>/dev/null; then
    echo -e "${GREEN}✓ Found${NC}"
    ((check_passed++))
else
    echo -e "${YELLOW}⚠ Not found${NC}"
    echo "  Desktop notifications won't work, but daemon will still function"
    echo "  Install with: sudo apt-get install libnotify-bin"
fi

echo ""
echo "=== SUMMARY ==="
echo -e "Passed: ${GREEN}$check_passed${NC}"
echo -e "Failed: ${RED}$check_failed${NC}"
echo ""

if [[ $check_failed -eq 0 ]]; then
    echo -e "${GREEN}✅ All checks passed! Daemon is ready to use.${NC}"
    echo ""
    echo "Start daemon with:"
    echo "  ./throttle-me -D start"
    exit 0
else
    echo -e "${RED}❌ Some checks failed. Fix the issues above before starting daemon.${NC}"
    exit 1
fi
