# Development Workflow (v2.0)

## Overview

throttle-me v2.0 is a **modular Bash application** with 13 library modules in `lib/`. Development requires understanding the module architecture and using mandatory quality tools (shellcheck, syntax validation, complexity analysis).

## Daily Development Setup

```bash
cd /home/wtyler/throttle-me

# Verify environment
bash --version  # Should be 5.2+
which shellcheck  # Mandatory linter
which scc  # Code statistics
which lizard  # Complexity analysis
```

---

## Working with Modules (v2.0 Architecture)

### Module Overview

```
lib/
├── config.sh           # Configuration file management (93 LOC, complexity: 13)
├── core.sh             # Enable/disable bypass logic (180 LOC, complexity: 20)
├── daemon.sh           # systemd daemon control (229 LOC, complexity: 26)
├── detection.sh        # Mobile hotspot auto-detection (143 LOC, complexity: 20)
├── iptables.sh         # iptables wrapper (97 LOC, complexity: 11)
├── logging.sh          # Logging and error handling (100 LOC, complexity: 8)
├── network.sh          # Network interface detection (121 LOC, complexity: 20)
├── presets.sh          # Configuration presets (158 LOC, complexity: 8)
├── retention.sh        # Session data retention (129 LOC, complexity: 11)
├── stats.sh            # Session statistics (216 LOC, complexity: 18)
├── ui-dialog.sh        # Dialog TUI menus (495 LOC, complexity: 41)
├── ui-theme.sh         # NSA theme (256 LOC, complexity: 8)
└── utils.sh            # Common utilities (78 LOC, complexity: 13)
```

### Module Dependency Rules

**Core Dependencies (Required First):**
1. `logging.sh` - Always source first (error handling)
2. `utils.sh` - Sudo caching, common helpers
3. `config.sh` - Configuration loading

**Feature Modules (Source After Core):**
4. `network.sh` → depends on logging.sh
5. `iptables.sh` → depends on logging.sh, network.sh
6. `core.sh` → depends on iptables.sh, stats.sh, logging.sh
7. All other modules → depend on core modules

### Module Development Workflow

**1. Read Module:**
```bash
# Use Desktop Commander for file operations
mcp__desktop-commander__read_file({path: "/home/wtyler/throttle-me/lib/core.sh"})

# Or use bat for syntax highlighting
bat lib/core.sh
```

**2. Edit Module:**
```bash
# Use Desktop Commander edit_block for surgical changes
mcp__desktop-commander__edit_block({
  filePath: "/home/wtyler/throttle-me/lib/core.sh",
  oldString: "old function code",
  newString: "new function code"
})
```

**3. Test Module in Isolation:**
```bash
# Test single module by sourcing dependencies
bash -c '
  source lib/logging.sh
  source lib/config.sh
  source lib/network.sh
  initialize_logging
  load_config
  interface=$(detect_wireless_interface)
  echo "Detected: $interface"
  [[ -n "$interface" ]] && echo "✓ PASS" || echo "✗ FAIL"
'
```

**4. Check Complexity After Changes:**
```bash
# Check module complexity (should stay under CCN 20 per function)
lizard lib/core.sh

# Check total project complexity (budget: <250)
lizard lib/*.sh | grep "^Total"
```

---

## Pre-Commit Checklist (MANDATORY)

**Run BEFORE every commit:**

```bash
# 1. Syntax check ALL bash files (CRITICAL)
bash -n throttle-me || { echo "Syntax error in main"; exit 1; }
bash -n throttle-me-daemon || { echo "Syntax error in daemon"; exit 1; }
for f in lib/*.sh; do 
  bash -n "$f" || { echo "Syntax error in $f"; exit 1; }
done

# 2. Shellcheck linting (MANDATORY - catches bugs)
shellcheck throttle-me lib/*.sh || { echo "Shellcheck failed"; exit 1; }

# 3. Check complexity budget (total should be <250)
total_complexity=$(lizard lib/*.sh | grep "^Total" | awk '{print $4}')
if [[ $total_complexity -gt 250 ]]; then
  echo "✗ Complexity too high: $total_complexity > 250"
  exit 1
fi
echo "✓ Complexity budget OK: $total_complexity/250"

# 4. Functional smoke test (CRITICAL)
./throttle-me -e    # Enable bypass
./throttle-me -s    # Check status shows ACTIVE
./throttle-me -d    # Disable bypass
./throttle-me -s    # Check status shows INACTIVE
```

**Expected time:** ~30 seconds (fast feedback loop)

---

## Testing Workflows

### Unit Testing Individual Modules

```bash
# Test config.sh
bash -c '
  source lib/logging.sh
  source lib/config.sh
  initialize_logging
  load_config
  echo "AUTO_ENABLE: $(get_config AUTO_ENABLE)"
  [[ -n "$(get_config AUTO_ENABLE)" ]] && echo "✓ PASS" || echo "✗ FAIL"
'

# Test network.sh
bash -c '
  source lib/logging.sh
  source lib/network.sh
  initialize_logging
  interface=$(detect_wireless_interface)
  echo "Interface: $interface"
  [[ -n "$interface" ]] && echo "✓ PASS" || echo "✗ FAIL"
'

# Test iptables.sh status functions
bash -c '
  source lib/logging.sh
  source lib/network.sh
  source lib/iptables.sh
  initialize_logging
  if is_bypass_active; then
    echo "✓ Bypass active"
  else
    echo "✓ Bypass inactive"
  fi
'
```

### Integration Testing (Full Bypass Cycle)

```bash
# Complete enable/disable cycle test
./throttle-me -d  # Ensure clean state

# Verify starting state clean
sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65" && {
  echo "✗ FAIL: Rules exist before enable"
  exit 1
}
echo "✓ Initial state clean"

# Enable bypass
./throttle-me -e || { echo "✗ FAIL: Enable failed"; exit 1; }

# Verify TTL rule applied
sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65" || {
  echo "✗ FAIL: TTL rule not applied"
  exit 1
}
echo "✓ TTL rule applied"

# Verify DNS rule applied
sudo iptables -t nat -L OUTPUT -n | grep -q "1.1.1.1:53" || {
  echo "✗ FAIL: DNS rule not applied"
  exit 1
}
echo "✓ DNS rule applied"

# Check status shows active
./throttle-me -s | grep -q "ACTIVE" || {
  echo "✗ FAIL: Status not showing active"
  exit 1
}
echo "✓ Status shows active"

# Disable bypass
./throttle-me -d || { echo "✗ FAIL: Disable failed"; exit 1; }

# Verify rules removed
sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65" && {
  echo "✗ FAIL: TTL rule still exists"
  exit 1
}
echo "✓ TTL rule removed"

echo "=== ✓ Integration test PASSED ==="
```

### Performance Benchmarking

```bash
# Benchmark enable/disable operations (requires hyperfine)
hyperfine \
  --warmup 3 \
  --runs 10 \
  './throttle-me -e && ./throttle-me -d' \
  --export-markdown benchmark-results.md

# Expected: <2 seconds per cycle, <100ms variance
```

---

## CLI Tools in Development

### Code Statistics (scc)

```bash
# Overall codebase statistics
scc lib/

# Per-file breakdown
scc --by-file lib/

# Compare against baseline after changes
scc lib/ > /tmp/current-stats.txt
diff /tmp/baseline-stats.txt /tmp/current-stats.txt
```

**Expected baseline (v2.0):**
- Total Lines: 2,295
- Code Lines: 1,650
- Complexity: 217

### Complexity Analysis (lizard)

```bash
# Check all modules
lizard lib/*.sh

# Find functions exceeding complexity threshold
lizard lib/*.sh --CCN 20

# Sort by complexity
lizard lib/*.sh --sort cyclomatic_complexity
```

**Complexity Guidelines:**
- Individual function: CCN <20
- Module average: CCN <15
- Total project: CCN <250

### Function Discovery (ast-grep)

```bash
# Find all function definitions
ast-grep --pattern '$FUNC() {
  $$$
}' --lang bash lib/*.sh

# Find specific function usage
ast-grep --pattern 'enable_bypass()' --lang bash

# Find iptables command calls
ast-grep --pattern 'sudo iptables $$$' --lang bash lib/iptables.sh
```

### Code Search (ripgrep)

```bash
# Find function calls across modules
rg "^[a-z_]+\(\)" lib/*.sh  # All function definitions

# Find TODO/FIXME comments
rg "TODO|FIXME" lib/*.sh

# Find specific pattern with context
rg -A 5 "enable_bypass" lib/core.sh  # 5 lines after match
```

---

## Daemon Development Workflow

### Testing Daemon Locally

```bash
# Start daemon in foreground (for debugging)
./throttle-me-daemon

# Check daemon status via systemd
./throttle-me -D status

# View daemon logs in real-time
./throttle-me -D logs-follow

# Test auto-detection
# 1. Connect to mobile hotspot
# 2. Wait up to 30 seconds
# 3. Verify bypass auto-enabled: ./throttle-me -s
```

### Daemon Development Cycle

1. Edit `lib/daemon.sh` or `lib/detection.sh`
2. Test in foreground mode: `./throttle-me-daemon`
3. Verify detection logic: Check logs for hotspot detection
4. Test systemd integration: `./throttle-me -D restart`
5. Verify auto-enable/disable works

---

## Common Development Tasks

### Add New CLI Flag

**Example: Add `-r` flag for session report**

1. Add to getopts in main script:
```bash
while getopts "edstmplaDvhi:r" opt; do
  case $opt in
    r) show_session_report; exit 0 ;;
    # ... existing cases
  esac
done
```

2. Implement function (likely in lib/stats.sh):
```bash
show_session_report() {
  source lib/stats.sh
  show_session_history | tail -20
}
```

3. Update help text:
```bash
show_help() {
  echo "  -r           Show session report"
}
```

4. Test:
```bash
bash -n throttle-me
./throttle-me -r
```

### Add New TUI Menu Option

**Example: Add "Session Report" to main menu**

1. Edit `lib/ui-dialog.sh` → `ui_main_menu()`
2. Increase option count in dialog command
3. Add menu item with unique ID
4. Add case in switch statement
5. Create new UI function (e.g., `ui_session_report()`)
6. Test TUI manually (must run in external terminal)

### Modify Bypass Behavior

**Example: Change default TTL from 65 to 64**

1. Edit `lib/iptables.sh` → `apply_ttl_rules()` function
2. Change `--ttl-set 65` to `--ttl-set 64`
3. Update `config/throttle-me.conf` → `DEFAULT_TTL=64`
4. Test: Enable bypass, verify new TTL with `sudo iptables -t mangle -L -n -v`
5. Update documentation in `.claude/docs/architecture.md`

### Add New Module

**Example: Add `lib/backup.sh` for preset backups**

1. Create file structure:
```bash
cat > lib/backup.sh << 'EOF'
#!/bin/bash
# lib/backup.sh - Preset backup management

backup_preset() {
  local preset_name="$1"
  # implementation
}

restore_preset() {
  local backup_file="$1"
  # implementation
}
EOF
```

2. Add to main sourcing order:
```bash
source lib/logging.sh
source lib/utils.sh
source lib/config.sh
source lib/backup.sh  # NEW
```

3. Test module in isolation:
```bash
bash -c '
  source lib/logging.sh
  source lib/config.sh
  source lib/backup.sh
  initialize_logging
  backup_preset "test-preset"
'
```

4. Run pre-commit checks

---

## Debugging Workflows

### Enable Bash Tracing

```bash
# Run main script with trace
bash -x throttle-me -e

# Trace specific module
bash -x -c '
  source lib/logging.sh
  source lib/network.sh
  set -x
  detect_wireless_interface
'
```

### Check Module Sourcing Order

```bash
# Verify dependencies are met
bash -c '
  set -e
  echo "1. Loading logging.sh"
  source lib/logging.sh
  echo "2. Loading config.sh"
  source lib/config.sh
  echo "3. Loading network.sh"
  source lib/network.sh
  echo "✓ All modules loaded successfully"
'
```

### Debug iptables Rules

```bash
# Verbose iptables listing
sudo iptables -t mangle -L POSTROUTING -n -v
sudo iptables -t nat -L OUTPUT -n -v

# Check packet counts (should increase with traffic)
watch -n 1 'sudo iptables -t mangle -L POSTROUTING -n -v'

# Test rule matching
sudo iptables -t mangle -I POSTROUTING -j LOG --log-prefix "TTL: " --log-level 4
dmesg | grep "TTL:"
```

### Debug Dialog TUI Issues

```bash
# Test dialog command syntax
dialog --msgbox "Test message" 10 40
echo $?  # Should be 0

# Check theme file
cat ~/.config/throttle-me/dialogrc

# Test menu structure
dialog --menu "Test Menu" 15 60 3 \
  1 "Option 1" \
  2 "Option 2" \
  3 "Exit"
```

---

## Git Workflow (v2.0)

### Repository Initialization

```bash
cd /home/wtyler/throttle-me
git init

# Initial commit with v2.0 structure
git add throttle-me throttle-me-daemon install.sh
git add lib/ config/ docs/
git add .claude/ PRD.md .gitignore
git commit -m "Initial commit: throttle-me v2.0 modular architecture

- 13 lib/ modules totaling 2,295 lines
- Complexity: 217 (well within budget)
- CLI mode + TUI mode
- Daemon with auto-detection
- Session statistics tracking
- Configuration presets
- NSA-themed dialog interface"
```

### Feature Branch Workflow

```bash
# Create feature branch for new module
git checkout -b feature/usage-analytics

# Make changes to lib/stats.sh
# Add new analytics functions

# Test changes
./throttle-me -e && ./throttle-me -s && ./throttle-me -d

# Run pre-commit checks
shellcheck lib/stats.sh
bash -n lib/stats.sh
lizard lib/stats.sh

# Commit with detailed message
git add lib/stats.sh
git commit -m "Add usage analytics to stats module

- New function: generate_usage_report()
- Tracks bytes transferred, session duration
- Integrates with retention policy
- Complexity: Added 5 CCN, total now 23/20 (acceptable)
- Tested with 3-day session history"

# Merge back to main
git checkout main
git merge feature/usage-analytics
```

### Commit Message Format

```
<type>: <short summary> (max 50 chars)

<detailed description>
- Bullet points for changes
- Include complexity impact
- Note any breaking changes
- Reference test results

Refs: #issue-number (if applicable)
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `refactor:` Code restructuring
- `docs:` Documentation
- `test:` Test improvements
- `perf:` Performance optimization
- `chore:` Maintenance

---

## Deployment Workflow

### Copy to Production

```bash
# From development to installed location
cp throttle-me ~/.local/bin/
cp throttle-me-daemon ~/.local/bin/

# Ensure executable
chmod +x ~/.local/bin/throttle-me
chmod +x ~/.local/bin/throttle-me-daemon

# Verify installation
which throttle-me  # Should show ~/.local/bin/throttle-me
throttle-me -v     # Check version
```

### Update Daemon Service

```bash
# Copy updated service file
cp config/throttle-me-daemon.service ~/.config/systemd/user/

# Reload systemd
systemctl --user daemon-reload

# Restart daemon if running
./throttle-me -D restart

# Check daemon status
./throttle-me -D status
```

---

## Code Style Conventions (v2.0)

### Module Structure

```bash
#!/bin/bash
# lib/module_name.sh - Brief description
#
# Dependencies: logging.sh, config.sh
# Complexity: X functions, CCN Y

# Global variables (minimize)
MODULE_VAR=""

# Public functions (documented)
public_function() {
  # Description: What this function does
  # Args: $1 - parameter description
  # Returns: 0 on success, 1 on error
  
  local param="$1"
  # implementation
}

# Private functions (prefix with _)
_private_helper() {
  # implementation
}
```

### Function Naming

- **Public API:** `verb_noun()` (e.g., `enable_bypass`, `get_status`)
- **Internal helpers:** `_verb_noun()` (e.g., `_validate_config`)
- **Query functions:** `is_*()` or `has_*()` (return 0/1)
- **Get functions:** `get_*()` (output to stdout)

### Error Handling

```bash
# Check command success
if ! command -v dialog &>/dev/null; then
  log_error "dialog not found"
  return 1
fi

# Use errexit for critical errors
set -e
critical_operation
set +e

# Validate parameters
if [[ -z "$1" ]]; then
  log_error "Missing required parameter"
  return 1
fi
```

---

## Documentation Maintenance

### After Module Changes

1. Update `.claude/docs/architecture.md` if dependency graph changed
2. Update `.claude/docs/testing.md` if new test cases added
3. Update `.claude/core/essential.md` if complexity budget changed
4. Keep `CLAUDE.md` using @ references only

### Regenerate Statistics

```bash
# Update codebase statistics in essential.md
scc lib/ --format json > /tmp/throttle-me-stats.json

# Update complexity metrics
lizard lib/*.sh | grep "^Total"

# Update function count
rg "^[a-z_]+\(\)" lib/*.sh | wc -l
```

---

## Performance Optimization

### Profiling Bash Scripts

```bash
# Time script execution
time ./throttle-me -e

# Profile with bash built-in
PS4='+ $(date "+%s.%N")\011 ' bash -x ./throttle-me -e 2>&1 | tee /tmp/profile.log

# Analyze hotspots
grep -E "^\+ [0-9]+" /tmp/profile.log | head -20
```

### Reduce iptables Query Time

```bash
# Cache status instead of querying repeatedly
BYPASS_STATUS=$(is_bypass_active && echo "ACTIVE" || echo "INACTIVE")

# Use grep -q for boolean checks (faster)
if sudo iptables -t mangle -L | grep -q "TTL set to 65"; then
  # ...
fi
```

### Optimize Module Loading

```bash
# Only source required modules for CLI operations
case "$1" in
  -e)
    source lib/logging.sh lib/core.sh lib/iptables.sh
    enable_bypass
    ;;
  -s)
    source lib/logging.sh lib/iptables.sh
    show_status
    ;;
esac
```

---

## References

- **Architecture:** `.claude/docs/architecture.md` - Module dependency graph, data flows
- **Testing:** `.claude/docs/testing.md` - Comprehensive testing strategy
- **Troubleshooting:** `.claude/workflows/troubleshooting.md` - Debugging procedures
- **Deployment:** `.claude/docs/deployment.md` - Installation and distribution
