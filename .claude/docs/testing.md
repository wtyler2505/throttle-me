# Testing Strategy (v2.0)

## Overview

throttle-me v2.0 testing focuses on **modular unit testing** of library functions, **integration testing** of the bypass mechanism, and **CLI/TUI functional testing**.

## Testing Tools

**Available (from CLI tools scan):**
- **shellcheck** - Bash linting (MANDATORY for all commits)
- **bash -n** - Syntax validation
- **bash -x** - Execution tracing for debugging
- **hyperfine** (1.19.0) - Performance benchmarking
- **scc** (3.4.0) - Code metrics and complexity
- **lizard** (1.19.0) - Cyclomatic complexity analysis
- **ast-grep** (0.39.6) - Structural code search for test verification

## Pre-Commit Checklist

**MANDATORY before every commit:**

```bash
# 1. Syntax check ALL bash files
bash -n throttle-me
bash -n throttle-me-daemon
for f in lib/*.sh; do 
  bash -n "$f" || { echo "Syntax error in $f"; exit 1; }
done

# 2. Shellcheck linting (CRITICAL - catches bugs)
shellcheck throttle-me lib/*.sh

# 3. Check complexity stays reasonable
lizard lib/*.sh | grep -E "^Total|NLOC|CCN"
# Ensure no single function exceeds CCN 20

# 4. Functional smoke test
./throttle-me -e    # Enable
./throttle-me -s    # Verify active
./throttle-me -d    # Disable
./throttle-me -s    # Verify inactive
```

## Module Unit Testing

### Testing Individual Library Functions

**Pattern: Source module + test specific function**

```bash
# Test config.sh
bash -c '
  source lib/logging.sh
  source lib/config.sh
  initialize_logging
  load_config
  echo "AUTO_ENABLE: $(get_config AUTO_ENABLE)"
  echo "Test passed: Config loaded"
'

# Test network.sh
bash -c '
  source lib/logging.sh
  source lib/network.sh
  initialize_logging
  interface=$(detect_wireless_interface)
  echo "Detected interface: $interface"
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

### Automated Module Testing Script

```bash
#!/bin/bash
# tests/unit-test-modules.sh

set -e

echo "=== Module Unit Tests ==="

# Test 1: config.sh can load and retrieve values
echo -n "Testing config.sh... "
bash -c '
  source lib/logging.sh
  source lib/config.sh
  initialize_logging
  load_config
  [[ -n "$(get_config AUTO_ENABLE)" ]] || exit 1
' && echo "✓ PASS" || echo "✗ FAIL"

# Test 2: network.sh detects interface
echo -n "Testing network.sh... "
bash -c '
  source lib/logging.sh
  source lib/network.sh
  initialize_logging
  interface=$(detect_wireless_interface)
  [[ -n "$interface" ]] || exit 1
' && echo "✓ PASS" || echo "✗ FAIL"

# Test 3: iptables.sh status checks work
echo -n "Testing iptables.sh... "
bash -c '
  source lib/logging.sh
  source lib/network.sh
  source lib/iptables.sh
  initialize_logging
  # Just verify functions are callable
  is_bypass_active || true
  is_ttl_active || true
  is_dns_active || true
' && echo "✓ PASS" || echo "✗ FAIL"

# Test 4: logging.sh creates log entries
echo -n "Testing logging.sh... "
bash -c '
  source lib/logging.sh
  initialize_logging
  log_info "Test message"
  [[ -f ~/.local/share/throttle-me/throttle-me.log ]] || exit 1
' && echo "✓ PASS" || echo "✗ FAIL"

echo "=== All module tests complete ==="
```

## Integration Testing

### Test 1: Complete Enable/Disable Cycle

**Objective:** Verify full bypass lifecycle

```bash
#!/bin/bash
# tests/integration-bypass-cycle.sh

echo "=== Integration Test: Bypass Cycle ==="

# Initial state - ensure bypass is off
./throttle-me -d &>/dev/null || true

# Verify starting state is clean
if sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65"; then
  echo "✗ FAIL: TTL rules exist before enable"
  exit 1
fi
echo "✓ Initial state clean"

# Enable bypass
echo "Enabling bypass..."
./throttle-me -e || { echo "✗ FAIL: Enable failed"; exit 1; }

# Verify TTL rule exists
if ! sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65"; then
  echo "✗ FAIL: TTL rule not applied"
  exit 1
fi
echo "✓ TTL rule applied"

# Verify DNS rule exists
if ! sudo iptables -t nat -L OUTPUT -n | grep -q "1.1.1.1:53"; then
  echo "✗ FAIL: DNS rule not applied"
  exit 1
fi
echo "✓ DNS rule applied"

# Verify resolv.conf locked
if ! grep -q "nameserver 1.1.1.1" /etc/resolv.conf; then
  echo "✗ FAIL: resolv.conf not set"
  exit 1
fi
echo "✓ resolv.conf configured"

# Check status reports active
if ! ./throttle-me -s | grep -q "ACTIVE"; then
  echo "✗ FAIL: Status not showing active"
  exit 1
fi
echo "✓ Status shows active"

# Disable bypass
echo "Disabling bypass..."
./throttle-me -d || { echo "✗ FAIL: Disable failed"; exit 1; }

# Verify TTL rule removed
if sudo iptables -t mangle -L POSTROUTING -n | grep -q "TTL set to 65"; then
  echo "✗ FAIL: TTL rule still exists"
  exit 1
fi
echo "✓ TTL rule removed"

# Verify DNS rule removed
if sudo iptables -t nat -L OUTPUT -n | grep -q "1.1.1.1:53"; then
  echo "✗ FAIL: DNS rule still exists"
  exit 1
fi
echo "✓ DNS rule removed"

echo "=== ✓ All integration tests PASSED ==="
```

### Test 2: Daemon Auto-Detection

**Prerequisites:** Connected to mobile hotspot

```bash
#!/bin/bash
# tests/integration-daemon.sh

echo "=== Integration Test: Daemon Auto-Detection ==="

# Check if on hotspot
ssid=$(iwgetid -r)
if [[ "$ssid" != *"iPhone"* ]] && [[ "$ssid" != "ADE-H4YK3F130DXP" ]]; then
  echo "⚠ WARNING: Not connected to known hotspot, skipping test"
  exit 0
fi
echo "✓ Connected to hotspot: $ssid"

# Start daemon
./throttle-me -D start || { echo "✗ FAIL: Daemon start failed"; exit 1; }
echo "✓ Daemon started"

# Wait for auto-detection (max 30 seconds)
echo "Waiting for auto-enable..."
for i in {1..30}; do
  if sudo iptables -t mangle -L | grep -q "TTL set to 65"; then
    echo "✓ Auto-enable triggered in ${i} seconds"
    break
  fi
  sleep 1
done

# Verify bypass is active
if ! ./throttle-me -s | grep -q "ACTIVE"; then
  echo "✗ FAIL: Bypass not auto-enabled"
  exit 1
fi
echo "✓ Bypass auto-enabled successfully"

# Check daemon logs
./throttle-me -D logs | tail -20 | grep -q "Bypass enabled" || {
  echo "⚠ WARNING: No enable message in logs"
}

# Stop daemon
./throttle-me -D stop
echo "✓ Daemon stopped"

echo "=== ✓ Daemon test PASSED ==="
```

### Test 3: Preset Save/Load

```bash
#!/bin/bash  
# tests/integration-presets.sh

echo "=== Integration Test: Presets ==="

# Enable bypass with custom config
./throttle-me -e

# Save as preset
echo "Saving preset 'test-preset'..."
bash -c '
  source lib/logging.sh
  source lib/config.sh
  source lib/core.sh
  initialize_logging
  load_config
  save_current_preset "test-preset" "Test configuration"
'

# Verify preset file exists
if [[ ! -f ~/.config/throttle-me/presets/test-preset.conf ]]; then
  echo "✗ FAIL: Preset file not created"
  exit 1
fi
echo "✓ Preset saved"

# Disable bypass
./throttle-me -d

# Load preset
echo "Loading preset 'test-preset'..."
./throttle-me -l test-preset

# Verify bypass re-enabled
if ! ./throttle-me -s | grep -q "ACTIVE"; then
  echo "✗ FAIL: Preset did not re-enable bypass"
  exit 1
fi
echo "✓ Preset loaded and applied"

# Cleanup
./throttle-me -d
rm ~/.config/throttle-me/presets/test-preset.conf

echo "=== ✓ Preset test PASSED ==="
```

## Performance Testing

### Benchmark with hyperfine

```bash
# Benchmark enable/disable operations
hyperfine \
  --warmup 3 \
  --runs 10 \
  './throttle-me -e && ./throttle-me -d' \
  --export-markdown results.md

# Expected results:
# Time: < 2 seconds for full cycle
# Variance: < 100ms
```

### Complexity Analysis

```bash
# Check module complexity stays under control
lizard lib/*.sh --CCN 20

# Expected results:
# All functions: CCN < 20
# Module average: CCN < 15
# Total complexity: < 250
```

### Memory Profiling

```bash
# Check memory usage
/usr/bin/time -v ./throttle-me -s 2>&1 | grep "Maximum resident"

# Expected: < 10MB RSS
```

## TUI Testing

**Manual TUI Testing Checklist:**

```
□ Main menu displays correctly
□ NSA theme loads (green on black)
□ Banner displays (ASCII art)
□ All 9 menu options accessible

Enable Bypass (Option 1):
□ Confirmation dialog appears
□ Progress messages display
□ Success message shows
□ Returns to main menu

Disable Bypass (Option 2):
□ Confirmation dialog appears
□ Cleanup messages display
□ Success message shows

Check Status (Option 3):
□ TTL status shown (ACTIVE/INACTIVE)
□ DNS status shown
□ Packet count displayed
□ Interface information shown
□ Gateway IP displayed

Settings → Daemon Control (Option 8 → 4):
□ Daemon status displayed in title
□ All 7 daemon options accessible
□ Start/Stop/Restart work correctly
□ Log viewing works

Presets (Option 7):
□ List shows saved presets
□ Save creates new preset file
□ Load applies preset configuration
□ Delete removes preset file
```

## Regression Testing

**After any code changes, verify:**

```bash
# 1. Shellcheck passes
shellcheck throttle-me lib/*.sh

# 2. All modules source without error
for f in lib/*.sh; do
  bash -c "source $f" || { echo "Error sourcing $f"; exit 1; }
done

# 3. CLI flags work
./throttle-me -h  # Help
./throttle-me -v  # Version
./throttle-me -e  # Enable
./throttle-me -s  # Status
./throttle-me -d  # Disable
./throttle-me -p  # Presets
./throttle-me -D status  # Daemon

# 4. TUI launches without error
timeout 2 ./throttle-me || [[ $? == 124 ]] # Exits after 2 sec

# 5. Complexity hasn't increased
scc lib/ | grep "Total"
# Compare against baseline: 2,295 lines, complexity 217
```

## Speed Test Validation

**Test bypass effectiveness:**

```bash
# Before bypass (should be throttled)
./throttle-me -d
speedtest-cli --simple | tee before.txt

# After bypass
./throttle-me -e
sleep 30  # Wait for rules to propagate
speedtest-cli --simple | tee after.txt

# Compare results
echo "Expected: 10-15x improvement"
# Download: 0.6 Mbps → 7+ Mbps
# Upload: 0.68 Mbps → 5+ Mbps
```

## Known Issues & Edge Cases

### Issue 1: Dialog Not Installed
**Test:** Remove dialog, run throttle-me
**Expected:** Auto-install triggers
**Command:**
```bash
sudo apt-get remove dialog -y
./throttle-me
# Should auto-install and continue
```

### Issue 2: Network Interface Detection Failure
**Test:** Disable wireless interface
**Expected:** Clear error message
**Command:**
```bash
sudo ip link set wlo1 down
./throttle-me -e
# Should show error: "No wireless interface detected"
```

### Issue 3: Sudo Timeout
**Test:** Let sudo timeout expire
**Expected:** Re-prompt for password
**Command:**
```bash
sudo -k  # Kill sudo cache
./throttle-me -e
# Should prompt for password
```

### Issue 4: Bypass Already Active
**Test:** Enable twice
**Expected:** Skip or warn
**Command:**
```bash
./throttle-me -e
./throttle-me -e
# Should detect already active
```

## Continuous Testing

**Add to git pre-commit hook:**

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running pre-commit tests..."

# Shellcheck all bash files
if ! shellcheck throttle-me lib/*.sh; then
  echo "✗ Shellcheck failed - commit rejected"
  exit 1
fi

# Syntax check all bash files
for f in throttle-me lib/*.sh; do
  if ! bash -n "$f"; then
    echo "✗ Syntax error in $f - commit rejected"
    exit 1
  fi
done

# Check complexity budget
total_complexity=$(lizard lib/*.sh | grep "^Total" | awk '{print $4}')
if [[ $total_complexity -gt 250 ]]; then
  echo "✗ Complexity too high: $total_complexity > 250"
  exit 1
fi

echo "✓ All pre-commit checks passed"
```

## Test Coverage Goals

**Current Coverage (v2.0):**
- ✅ Module syntax: 100% (automated)
- ✅ Shellcheck linting: 100% (automated)
- ✅ Core bypass: 100% (manual functional tests)
- ⚠️  Unit tests: ~40% (manual bash -c tests)
- ⚠️  TUI menus: ~60% (manual checklist)
- ❌ Automated integration tests: 0% (scripts written, not CI)

**Future Goals:**
- [ ] Automated unit test framework (bats or shunit2)
- [ ] CI/CD with GitHub Actions
- [ ] Automated TUI testing (expect or tmux scripting)
- [ ] Performance regression tracking
- [ ] Security scanning (shellcheck --severity=error)

## References

- **Architecture:** `.claude/docs/architecture.md` - Module structure
- **Development:** `.claude/workflows/development.md` - Dev workflow
- **Deployment:** `.claude/docs/deployment.md` - Installation testing
