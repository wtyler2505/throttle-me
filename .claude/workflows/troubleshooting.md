# Troubleshooting Guide

## Common Issues

### Issue 1: Dialog Menu Doesn't Display

**Symptoms:**
- Script runs but no menu appears
- Terminal shows errors about dialog

**Diagnosis:**
```bash
# Check if dialog is installed
command -v dialog || echo "Dialog not installed"

# Check dialog version
dialog --version
```

**Solutions:**
```bash
# Manual install
sudo apt-get update && sudo apt-get install -y dialog

# Verify installation
which dialog  # Should show /usr/bin/dialog
```

---

### Issue 2: Bypass Not Working (Speed Still Slow)

**Symptoms:**
- Enable bypass completes successfully
- Speed test still shows throttled speeds (~0.6 Mbps)

**Diagnosis:**
```bash
# Check TTL rule
sudo iptables -t mangle -L POSTROUTING -n | grep "TTL set to 65"
# Should show rule if active

# Check DNS redirection
sudo iptables -t nat -L OUTPUT -n | grep "1.1.1.1:53"
# Should show DNAT rule

# Check DNS config
cat /etc/resolv.conf
# Should show nameserver 1.1.1.1

# Test DNS resolution
nslookup google.com 1.1.1.1
# Should resolve successfully
```

**Solutions:**
```bash
# Flush and re-apply rules
./throttle-me → Disable Bypass
./throttle-me → Enable Bypass

# Check bypass scripts are correct
cat ~/.local/bin/bypass-tethering
cat ~/.local/bin/disable-bypass-tethering

# Verify iptables modules loaded
lsmod | grep iptable
sudo modprobe iptable_mangle
sudo modprobe iptable_nat
```

---

### Issue 3: "Permission Denied" Errors

**Symptoms:**
- iptables commands fail
- Cannot modify /etc/resolv.conf
- chattr commands fail

**Diagnosis:**
```bash
# Check sudo access
sudo -v  # Should prompt for password

# Check if user is in sudo group
groups | grep sudo

# Check sudo logs
journalctl -xe | grep sudo
```

**Solutions:**
```bash
# Add user to sudo group (requires root)
sudo usermod -aG sudo $USER

# Re-login for group changes to take effect
# Or use: newgrp sudo

# Verify sudo works
sudo echo "test"  # Should print "test"
```

---

### Issue 4: DNS Not Working After Disable

**Symptoms:**
- Disabled bypass but DNS still not working
- Cannot access captive portals
- Local network resources unreachable

**Diagnosis:**
```bash
# Check if resolv.conf is still locked
lsattr /etc/resolv.conf | grep "i"
# "i" flag means still immutable

# Check DNS servers
cat /etc/resolv.conf
# Should NOT be 1.1.1.1 after disable

# Check NetworkManager status
systemctl status NetworkManager
```

**Solutions:**
```bash
# Manually unlock resolv.conf
sudo chattr -i /etc/resolv.conf

# Restore DNS with NetworkManager
sudo systemctl restart NetworkManager

# Or manually configure DNS
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# Verify DNS works
ping google.com  # Should resolve and ping
```

---

### Issue 5: Status Check Shows Incorrect State

**Symptoms:**
- Status shows ACTIVE but bypass not working
- Status shows INACTIVE but rules exist

**Diagnosis:**
```bash
# Manually check iptables
sudo iptables -t mangle -L POSTROUTING -n -v
sudo iptables -t nat -L OUTPUT -n -v

# Compare with status check logic in script
grep -A 10 "check_bypass_status" throttle-me
```

**Solutions:**
```bash
# Update status check function if grep patterns wrong
# Look for exact iptables rule output

# Temporary workaround: Check manually
sudo iptables -t mangle -L | grep "TTL set to 65" && echo "ACTIVE" || echo "INACTIVE"
```

---

### Issue 6: Script Not Found in PATH

**Symptoms:**
- `throttle-me` command not found
- Must use `./throttle-me` from specific directory

**Diagnosis:**
```bash
# Check if ~/.local/bin is in PATH
echo $PATH | grep ".local/bin"

# Check if file exists
ls -la ~/.local/bin/throttle-me

# Check if executable
test -x ~/.local/bin/throttle-me && echo "Executable" || echo "Not executable"
```

**Solutions:**
```bash
# Add ~/.local/bin to PATH in ~/.bashrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Reload bashrc
source ~/.bashrc

# Verify PATH updated
echo $PATH | grep ".local/bin"

# Make script executable
chmod +x ~/.local/bin/throttle-me

# Test
throttle-me  # Should work from any directory
```

---

### Issue 7: Bypass Works But Breaks After Reboot

**Symptoms:**
- Bypass works until system reboot
- After reboot, rules are gone

**Diagnosis:**
```bash
# iptables rules are NOT persistent by default
# They clear on reboot

# Check if iptables-persistent is installed
dpkg -l | grep iptables-persistent
```

**Solutions:**
```bash
# Option 1: Re-enable manually after each reboot
throttle-me → Enable Bypass

# Option 2: Install iptables-persistent (makes rules survive reboot)
sudo apt-get install iptables-persistent

# Save current rules
sudo netfilter-persistent save

# Rules will now persist across reboots
```

---

### Issue 8: Carrier Still Detecting Tethering

**Symptoms:**
- Bypass enabled with correct rules
- Speed still throttled
- Hotspot counter still increasing

**Diagnosis:**
```bash
# Check all bypass layers are active
sudo iptables -t mangle -L | grep "TTL set to 65"  # Layer 1: TTL
sudo iptables -t nat -L | grep "1.1.1.1"          # Layer 2: DNS
cat /etc/resolv.conf | grep "1.1.1.1"             # Layer 3: DNS lock
```

**Possible Causes:**
1. **Advanced DPI:** Carrier using deep packet inspection beyond TTL
2. **IPv6 Leakage:** IPv6 traffic not being modified (we only modify IPv4)
3. **User-Agent:** Browser still sending desktop User-Agent
4. **Traffic Patterns:** ML-based detection of desktop vs mobile patterns

**Solutions:**
```bash
# Disable IPv6 (prevents leakage)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

# Verify IPv6 disabled
ping -6 google.com  # Should fail

# Enable User-Agent spoofing
~/.local/bin/spoof-user-agent-firefox
~/.local/bin/spoof-user-agent-chrome

# Avoid obvious desktop protocols
# Don't use: torrents, RDP, SMB while on hotspot
```

---

## Debugging Techniques

### Enable Verbose iptables Logging
```bash
# Log all packets matching TTL rule
sudo iptables -t mangle -I POSTROUTING -j LOG --log-prefix "TTL: " --log-level 4

# Check kernel logs
dmesg | grep "TTL:"
journalctl -f | grep "TTL:"

# Remove logging when done
sudo iptables -t mangle -D POSTROUTING -j LOG --log-prefix "TTL: " --log-level 4
```

### Test DNS Redirection
```bash
# Direct query to Cloudflare (should work)
nslookup google.com 1.1.1.1

# System DNS query (should be redirected)
nslookup google.com

# Check if both resolve the same
# Both should use 1.1.1.1
```

### Monitor Packet Modification
```bash
# Watch packet counters in real-time
watch -n 1 'sudo iptables -t mangle -L POSTROUTING -n -v'

# Generate traffic and watch counters increase
curl https://example.com
```

---

## Recovery Procedures

### Emergency Reset (Nuclear Option)
```bash
# Stop all network services
sudo systemctl stop NetworkManager

# Flush ALL iptables rules
sudo iptables -t mangle -F
sudo iptables -t nat -F
sudo iptables -t filter -F

# Unlock resolv.conf
sudo chattr -i /etc/resolv.conf

# Restart networking
sudo systemctl start NetworkManager

# Verify internet works
ping google.com
```

### Restore From Backup (If Created)
```bash
# Restore resolv.conf
sudo chattr -i /etc/resolv.conf
sudo cp /etc/resolv.conf.backup /etc/resolv.conf

# Restore iptables (if saved)
sudo iptables-restore < /etc/iptables/rules.v4.backup
```

---

## Getting Help

### Gather Diagnostic Info
```bash
# System info
uname -a
cat /etc/os-release

# Network info
ip addr show
ip route show
cat /etc/resolv.conf

# iptables rules
sudo iptables -t mangle -L -n -v
sudo iptables -t nat -L -n -v

# Script location and permissions
ls -la ~/.local/bin/throttle-me
ls -la ~/.local/bin/bypass-tethering

# Save to file
{
  echo "=== System Info ==="
  uname -a
  echo ""
  echo "=== Network Info ==="
  ip addr show
  echo ""
  echo "=== iptables Rules ==="
  sudo iptables -t mangle -L -n -v
  sudo iptables -t nat -L -n -v
} > ~/throttle-me-debug.txt
```

### Contact Information
- Project repo: (future - add GitHub URL)
- User: Tyler (wtyler@localhost)
