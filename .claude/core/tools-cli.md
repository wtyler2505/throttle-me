# System CLI Tools

## Detected Tools (9 total)

### Core Development Tools

**bash** (v5.2.21)
```bash
# Main scripting language for this project
bash throttle-me          # Run TUI application
bash -n script.sh         # Syntax check
bash -x script.sh         # Debug mode (trace execution)
```

**dialog** (v1.3-20240101)
```bash
# TUI framework used by throttle-me
dialog --msgbox "Hello" 10 40
dialog --menu "Choose:" 15 60 4 1 "Option 1" 2 "Option 2"
dialog --yesno "Continue?" 10 40
```

**iptables** (v1.8.10 nf_tables)
```bash
# Packet filtering and NAT (core to bypass functionality)
sudo iptables -t mangle -L POSTROUTING -n        # List TTL rules
sudo iptables -t nat -L OUTPUT -n                # List DNS rules
sudo iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65
sudo iptables -t nat -F                          # Flush NAT rules
```

---

### Version Control

**git** (v2.43.0)
```bash
git init                  # Initialize repository
git add .                 # Stage all changes
git commit -m "message"   # Commit changes
git status                # Check status
git log --oneline         # View history
git diff                  # Show changes
```

---

### Node.js Ecosystem

**node** (v20.19.5)
```bash
node script.js            # Run JavaScript
node -i                   # Interactive REPL
node --version            # Check version
```

**npm** (v10.8.2)
```bash
npm install               # Install dependencies
npm install -g package    # Global install
npm list -g --depth=0     # List global packages
npm outdated              # Check for updates
```

---

### Python

**python3** (v3.12.3)
```bash
python3 script.py         # Run Python script
python3 -i                # Interactive REPL
python3 -m pip install    # Install packages
python3 --version         # Check version
```

---

### Text Processing (GNU Coreutils)

**grep** - Pattern matching
```bash
grep "pattern" file.txt             # Search file
grep -r "pattern" .                 # Recursive search
grep -n "pattern" file.txt          # Show line numbers
iptables -L | grep "TTL"            # Filter iptables output
```

**awk** - Text processing
```bash
awk '{print $1}' file.txt           # Print first column
ip route | awk '/default/ {print $3}'  # Extract gateway IP
iptables -L -n -v | awk '{print $1, "packets"}'
```

**sed** - Stream editor
```bash
sed 's/old/new/g' file.txt          # Replace text
sed -n '1,10p' file.txt             # Print lines 1-10
sed -i 's/TTL 64/TTL 65/g' script.sh  # In-place edit
```

---

### Network Tools

**ip** (from iproute2)
```bash
ip route                  # Show routing table
ip route | grep default   # Get default gateway
ip addr show              # Show network interfaces
ip link show wlo1         # Show specific interface
```

---

### System Tools

**sudo** - Privileged execution
```bash
sudo iptables -L          # Run as root
sudo -k                   # Clear cached password
sudo -v                   # Refresh sudo timestamp
```

**chattr** - File attributes
```bash
sudo chattr +i file       # Make immutable (used for resolv.conf)
sudo chattr -i file       # Remove immutable
lsattr file               # List attributes
```

---

## Tool Selection Guide

**For file operations:** Use Desktop Commander MCP (not cat/echo/sed)
**For searching:** Use Desktop Commander search (not grep/find)
**For network status:** Use `ip route`, `iptables -L`
**For text processing:** Only when necessary (prefer Read tool)
**For iptables:** Direct CLI usage (no MCP alternative)
**For dialog TUI:** Must be run by user in external terminal

---

## Critical Reminders

**ALWAYS use 30-minute timeout (1800000ms) for bash commands**
```bash
# Correct
Bash({command: "npm install", timeout: 1800000})

# Wrong (will timeout after 2 minutes)
Bash({command: "npm install"})
```

**NEVER launch TUI applications from this terminal**
- dialog-based apps must run in user's terminal
- Tell user to run: `./throttle-me` manually
