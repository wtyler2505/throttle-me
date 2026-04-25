# Quick Start Guide

Get throttle-me running in under 5 minutes!

---

## Prerequisites

**Check you have these installed:**

```bash
# Bash 4.0+
bash --version

# iptables
sudo iptables --version

# dialog (for TUI)
dialog --version

# Git (for installation)
git --version
```

**Missing something?**
```bash
# Ubuntu/Debian/Mint
sudo apt-get update
sudo apt-get install dialog iptables git python3 python3-venv

# Optional but recommended for the new command-center dashboard
curl -LsSf https://astral.sh/uv/install.sh | sh

# Other distros: adjust package manager accordingly
```

---

## Installation

**Option 1: Automated (Recommended)**
```bash
# Clone repository
git clone https://github.com/wtyler/throttle-me.git
cd throttle-me

# Run installer
./install.sh
```

**Option 2: Manual**
```bash
# Clone repository
git clone https://github.com/wtyler/throttle-me.git
cd throttle-me

# Copy main script
cp throttle-me ~/.local/bin/
chmod +x ~/.local/bin/throttle-me

# Copy bypass scripts (must be in ~/.local/bin/)
cp scripts/bypass-tethering scripts/disable-bypass-tethering ~/.local/bin/
chmod +x ~/.local/bin/bypass-tethering ~/.local/bin/disable-bypass-tethering

# Install daemon (optional)
cp throttle-me-daemon ~/.local/bin/
chmod +x ~/.local/bin/throttle-me-daemon
mkdir -p ~/.config/systemd/user
cp config/throttle-me-daemon.service ~/.config/systemd/user/
systemctl --user daemon-reload

# Install command-center dashboard
mkdir -p ~/.local/share/throttle-me
cp -r dashboard ~/.local/share/throttle-me/

# Verify installation
throttle-me -v
```

---

## First Bypass (< 5 minutes)

### Step 1: Check Status
```bash
throttle-me -s
```

**Expected:** Shows bypass is currently INACTIVE

### Step 2: Enable Bypass
```bash
throttle-me -e
```

**What happens:**
- Sets TTL to 65 (bypasses carrier detection)
- Redirects DNS to Cloudflare 1.1.1.1 using public DNS on port 53
- Locks DNS configuration
- Shows success message

### Step 3: Test Your Speed
```bash
throttle-me -t
```

**Expected:** Should see 10x+ speed improvement on mobile hotspot

### Step 4: Disable Bypass (When Done)
```bash
throttle-me -d
```

**What happens:**
- Restores normal TTL
- Restores original DNS
- Unlocks DNS configuration

**That's it! You've completed your first bypass!** 🎉

---

## Common Tasks

### Launch Interactive TUI
```bash
throttle-me
```

By default this opens the full command-center dashboard. Use `throttle-me --classic` for the legacy dialog UI.

**Main features:**
- Enable/Disable bypass
- Check detailed status and diagnostics
- Run speed test
- View statistics & history
- Manage configuration presets
- Control background daemon

---

### Use Background Daemon (Auto-Enable)

**First-Time Setup (Required):**
```bash
# Configure passwordless sudo
sudo visudo -f /etc/sudoers.d/throttle-me
```

Add command-scoped passwordless sudo entries:
```
wtyler ALL=(ALL) NOPASSWD: /usr/sbin/iptables
wtyler ALL=(ALL) NOPASSWD: /usr/sbin/ip6tables
wtyler ALL=(ALL) NOPASSWD: /usr/bin/tee
wtyler ALL=(ALL) NOPASSWD: /usr/bin/chattr
wtyler ALL=(ALL) NOPASSWD: /usr/bin/cp
wtyler ALL=(ALL) NOPASSWD: /usr/bin/rm
```

Save and exit.

**Start Daemon:**
```bash
# Option 1: CLI
throttle-me -D start

# Option 2: TUI
throttle-me
# Navigate to: Settings → Daemon Control → Start Daemon
```

**Enable Auto-Start on Login:**
```bash
throttle-me -D enable
```

Now bypass will automatically enable when you connect to mobile hotspots!

---

### Save/Load Presets

**Save current config:**
```bash
# Via TUI
throttle-me
# Navigate to: Manage Presets → Save Current Configuration

# Name it: "my-iphone" or "android-setup"
```

**Load preset:**
```bash
# Via CLI
throttle-me -l my-iphone

# Via TUI
throttle-me
# Navigate to: Manage Presets → Load Preset → Select preset
```

**Built-in presets:**
- `iphone` - TTL=65 (iPhone hotspots)
- `android` - TTL=64 (Android hotspots)
- `stealth` - TTL=128 (maximum stealth)

---

### View Statistics

**Current session:**
```bash
throttle-me -S
```

**Session history:**
```bash
throttle-me -H
```

**Export to CSV:**
```bash
# Via TUI
throttle-me
# Navigate to: Statistics & History → Export to CSV
```

---

## Troubleshooting

### "bypass-tethering: command not found"

**Fix:**
```bash
# Ensure scripts are in ~/.local/bin/
ls -la ~/.local/bin/bypass-tethering

# If missing, copy from project directory
cp bypass-tethering ~/.local/bin/
chmod +x ~/.local/bin/bypass-tethering
```

---

### "sudo: a password is required"

**Fix:**
```bash
# Configure sudoers (required for daemon)
sudo visudo -f /etc/sudoers.d/throttle-me

# Add these lines:
wtyler ALL=(ALL) NOPASSWD: /home/wtyler/.local/bin/bypass-tethering
wtyler ALL=(ALL) NOPASSWD: /home/wtyler/.local/bin/disable-bypass-tethering
```

---

### Bypass Doesn't Work

**Check iptables rules:**
```bash
sudo iptables -t mangle -L POSTROUTING -n
# Should show: TTL set to 65

sudo iptables -t nat -L OUTPUT -n
# Should show: DNAT to 1.1.1.1:53
```

**Verify DNS lock:**
```bash
lsattr /etc/resolv.conf
# Should show: ----i--------
# The 'i' means immutable (locked)

cat /etc/resolv.conf
# Should show: nameserver 1.1.1.1
```

**Still not working?**
- Wait 30 seconds after enabling (iptables rules take effect)
- Disconnect and reconnect to hotspot
- Try speed test again: `throttle-me -t`

---

### Daemon Won't Start

**Verify environment:**
```bash
./.claude/scripts/verify-env.sh
```

This checks all prerequisites and shows exactly what's missing.

**Check daemon logs:**
```bash
journalctl --user -u throttle-me-daemon -n 20
```

---

## Next Steps

### Learn More

**For detailed daemon usage:**
- [Daemon Guide](DAEMON.md) - Complete background daemon documentation

**For architecture details:**
- See phase completion docs (PHASE*.md files)
- Review library modules in `lib/` directory

**For configuration:**
- Copy `config/config.template` to `~/.config/throttle-me/config`
- Customize settings (TTL, DNS, auto-enable, retention policy)

---

### Advanced Usage

**Override wireless interface:**
```bash
throttle-me -i wlan0
```

**Manual retention cleanup:**
```bash
throttle-me -c
```

**Auto-detect hotspot and enable:**
```bash
throttle-me -a
```

**View daemon logs in real-time:**
```bash
throttle-me -D follow
# Or: journalctl --user -u throttle-me-daemon -f
```

---

## Configuration

**Create config file:**
```bash
mkdir -p ~/.config/throttle-me
cp config/config.template ~/.config/throttle-me/config
nano ~/.config/throttle-me/config
```

**Key settings:**
- `TTL_VALUE=65` - Carrier bypass TTL (65=iPhone, 64=Android)
- `DNS_SERVER="1.1.1.1"` - DNS server for redirection
- `AUTO_ENABLE=true` - Auto-enable daemon on hotspots
- `MAX_SESSIONS=100` - Session history limit
- `MAX_AGE_DAYS=30` - Session age limit

---

## Uninstallation

```bash
# Stop daemon
throttle-me -D stop
throttle-me -D disable

# Remove files
rm ~/.local/bin/throttle-me
rm ~/.local/bin/throttle-me-daemon
rm ~/.local/bin/bypass-tethering
rm ~/.local/bin/disable-bypass-tethering
rm ~/.config/systemd/user/throttle-me-daemon.service
systemctl --user daemon-reload

# Remove config and data
rm -rf ~/.config/throttle-me
rm -rf ~/.cache/throttle-me

# Remove sudoers entry
sudo rm /etc/sudoers.d/throttle-me
```

---

## Getting Help

**View all options:**
```bash
throttle-me --help
```

**Check version:**
```bash
throttle-me -v
```

**Report issues:**
- GitHub: https://github.com/wtyler/throttle-me/issues
- Email: wtyler@localhost

---

**Happy bypassing! 🚀**

*For detailed documentation, see `docs/DAEMON.md` and other docs in the `docs/` directory.*
