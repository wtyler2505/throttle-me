# Deployment Guide

## Installation

### Prerequisites

**System Requirements:**
- Linux (Debian/Ubuntu/Mint recommended)
- Bash 4.0+
- sudo access
- iptables support in kernel

**User Scripts Required:**
Must be installed to `~/.local/bin/` with execute permissions:
- `bypass-tethering`
- `disable-bypass-tethering`

### Step 1: Verify Prerequisites

```bash
# Check bash version
bash --version  # Should be 4.0+

# Check sudo access
sudo -v  # Enter password to verify

# Check iptables
sudo iptables -L  # Should list tables without error

# Verify user scripts exist
ls -la ~/.local/bin/bypass-tethering
ls -la ~/.local/bin/disable-bypass-tethering
```

### Step 2: Install throttle-me

```bash
# Copy to user bin directory
cp throttle-me ~/.local/bin/

# Make executable
chmod +x ~/.local/bin/throttle-me

# Verify installation
which throttle-me  # Should show ~/.local/bin/throttle-me
```

### Step 3: First Run

```bash
# Run from anywhere
throttle-me

# Dialog will auto-install if missing
# Enter sudo password when prompted
```

---

## Updating

### Update throttle-me Script

```bash
# Pull latest from development directory
cd /home/wtyler/throttle-me
git pull  # (if using git)

# Copy to installed location
cp throttle-me ~/.local/bin/

# Verify version (if version info added)
throttle-me --version
```

### Update Documentation

```bash
# Documentation lives in .claude/
# No installation needed - Claude reads from source
```

---

## Uninstallation

### Remove throttle-me

```bash
# Remove installed script
rm ~/.local/bin/throttle-me

# Optionally remove dependency scripts
rm ~/.local/bin/bypass-tethering
rm ~/.local/bin/disable-bypass-tethering

# Remove dialog (if desired)
sudo apt-get remove dialog
```

### Clean Up Network Settings

```bash
# Disable any active bypass
sudo iptables -t mangle -F POSTROUTING
sudo iptables -t nat -F OUTPUT
sudo chattr -i /etc/resolv.conf

# Restore DNS (restart NetworkManager)
sudo systemctl restart NetworkManager
```

---

## Distribution

### As Standalone Script

```bash
# Single file distribution
# Just copy throttle-me to target system
scp throttle-me user@host:~/.local/bin/

# SSH and make executable
ssh user@host 'chmod +x ~/.local/bin/throttle-me'
```

### As .deb Package (Future)

```bash
# Package structure
throttle-me_1.0.0/
├── DEBIAN/
│   ├── control
│   └── postinst
└── usr/
    └── local/
        └── bin/
            └── throttle-me

# Build package
dpkg-deb --build throttle-me_1.0.0

# Install
sudo dpkg -i throttle-me_1.0.0.deb
```

---

## Environments

### Development
**Location:** `/home/wtyler/throttle-me/`
**Purpose:** Active development, testing changes
**Git:** Not initialized (future)

### Production
**Location:** `~/.local/bin/throttle-me`
**Purpose:** Daily use by Tyler
**Update Process:** Manual copy from development

---

## Security Considerations

### Sudo Requirements
- throttle-me itself doesn't need sudo
- Calls scripts (bypass-tethering) that require sudo
- User will be prompted for password
- Password cached by sudo for 15 minutes

### File Permissions
```bash
# throttle-me should be executable by user
-rwxr-xr-x  1 wtyler wtyler  throttle-me

# Bypass scripts should be executable
-rwxrwxr-x  1 wtyler wtyler  bypass-tethering
-rwxrwxr-x  1 wtyler wtyler  disable-bypass-tethering
```

### Network Impact
- Modifies kernel iptables rules (requires root)
- Changes system DNS configuration
- Does NOT modify network interfaces
- Does NOT create new network connections

---

## Monitoring

### Check if Bypass is Active
```bash
# Quick check
sudo iptables -t mangle -L | grep "TTL set to 65" && echo "ACTIVE" || echo "INACTIVE"

# Detailed check
throttle-me  # Use menu option 3: Check Status
```

### Monitor Data Usage
```bash
# Check packet counts
sudo iptables -t mangle -L POSTROUTING -n -v

# Check byte counts
sudo iptables -t mangle -L POSTROUTING -n -v | awk '/TTL/{print $2}'
```

### Logs
- throttle-me doesn't create logs
- Check system logs for iptables errors:
```bash
journalctl -xe | grep iptables
dmesg | grep iptables
```

---

## Troubleshooting Deployment

### Error: "dialog: command not found"
**Solution:** Auto-install should trigger, but if not:
```bash
sudo apt-get update && sudo apt-get install -y dialog
```

### Error: "bypass-tethering: No such file"
**Solution:** Install dependency scripts first
```bash
# Verify scripts are in correct location
ls -la ~/.local/bin/bypass-tethering
ls -la ~/.local/bin/disable-bypass-tethering

# Check PATH includes ~/.local/bin
echo $PATH | grep ".local/bin"
```

### Error: "Operation not permitted" (iptables)
**Solution:** Need sudo access or kernel module
```bash
# Check sudo access
sudo -v

# Load iptables modules
sudo modprobe iptable_mangle
sudo modprobe iptable_nat
```

### Error: "chattr: Operation not permitted"
**Solution:** File already locked or filesystem doesn't support chattr
```bash
# Unlock first
sudo chattr -i /etc/resolv.conf

# Check filesystem support
lsattr /etc/resolv.conf
```
