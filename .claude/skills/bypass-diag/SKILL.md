---
name: bypass-diag
description: Run a structured A/B test of throttle-me bypass effectiveness. Captures iptables baseline, runs 3 speed tests with bypass ON then OFF, restores initial state, and reports mean/min/max plus TTL-on-wire verification. Use when bypass appears not to be working ("speeds feel throttled even with bypass on"), after iptables/network changes, or before deciding which of the 3 known gaps to fix.
disable-model-invocation: true
---

# Bypass Diagnostic A/B Test

Structured before/after comparison of carrier bypass effectiveness with proper baseline capture and state restoration.

## When to use

- Bypass appears not to be working ("speeds feel throttled even with bypass on")
- Verifying bypass mechanism after kernel updates or iptables changes
- Documenting effectiveness for a new carrier/network
- Before deciding whether to invest time in v6 NAT fix, chattr fix, or MSS clamping

## Prerequisites

- Cwd: `/home/wtyler/throttle-me`
- Sudo cached (the disable script needs a TTY): run `sudo -v` first
- Network connection active
- `tcpdump`, `iptables`, `curl`, `bc` available
- Wireless interface auto-detection working (or pass `-i wlan0`)

## Workflow

### Step 1 — Capture initial state

```bash
cd /home/wtyler/throttle-me
INITIAL_STATE="off"
./throttle-me -s 2>&1 | grep -q "ACTIVE" && INITIAL_STATE="on"
echo "Initial bypass state: ${INITIAL_STATE}"

sudo iptables  -t mangle -L POSTROUTING -n -v > /tmp/td-mangle-before.txt
sudo iptables  -t nat    -L OUTPUT      -n -v > /tmp/td-nat-before.txt
sudo ip6tables -t mangle -L POSTROUTING -n -v > /tmp/td-mangle6-before.txt 2>/dev/null
sudo ip6tables -t nat    -L OUTPUT      -n -v > /tmp/td-nat6-before.txt    2>/dev/null
echo "Baseline captured."
```

### Step 2 — Test ON (bypass enabled)

```bash
[[ "${INITIAL_STATE}" == "off" ]] && ./throttle-me -e

# Verify TTL=65 on wire (foreground; needs an active connection)
echo "Wire TTL check (5 packets):"
timeout 5 sudo tcpdump -v -i any -c 5 'tcp port 443' 2>&1 | grep -oP 'ttl \d+' | sort -u

# 3 speed tests, 5s gap between each
on_results=()
for i in 1 2 3; do
    speed=$(./throttle-me -t 2>&1 | grep -oP 'Download Speed: \K[\d.]+' || echo "0")
    on_results+=("${speed}")
    echo "ON test ${i}: ${speed} Mbps"
    sleep 5
done
```

### Step 3 — Test OFF (bypass disabled)

```bash
./throttle-me -d

off_results=()
for i in 1 2 3; do
    speed=$(./throttle-me -t 2>&1 | grep -oP 'Download Speed: \K[\d.]+' || echo "0")
    off_results+=("${speed}")
    echo "OFF test ${i}: ${speed} Mbps"
    sleep 5
done
```

### Step 4 — Restore initial state

```bash
[[ "${INITIAL_STATE}" == "on" ]] && ./throttle-me -e
echo "Initial state restored: ${INITIAL_STATE}"
```

### Step 5 — Report

Compute mean / min / max for each phase. Render a table:

```
| Phase | Samples (Mbps)        | Mean  | Min   | Max   |
|-------|-----------------------|-------|-------|-------|
| ON    | s1, s2, s3            | μ_on  | min   | max   |
| OFF   | s1, s2, s3            | μ_off | min   | max   |

Δ = mean_on − mean_off
ratio = mean_on / mean_off
```

Interpretation guidance:
- **ratio > 3×** — Bypass clearly effective. TTL detection is real on this carrier.
- **1.3× ≤ ratio ≤ 3×** — Bypass possibly effective but within noise. Run a second round to confirm.
- **ratio < 1.3×** — Indistinguishable from noise. Either bypass not working, OR carrier doesn't gate on TTL anymore. Run `/bypass-gap-check` to verify mechanism, then check carrier behavior separately.

Confirm wire TTL = 65 (Step 2 output). If wire shows 64 or 128, the iptables rule isn't applying — investigate iptables.sh / external bypass-tethering script.

## Known caveats

- Carrier variance can be 5-10× within a single session (last session saw 2.82 → 25.77 Mbps with no toggle change). A single A/B is rarely conclusive — repeat or accept inconclusive.
- Speedtest server (Cloudflare) may rate-limit consecutive tests
- TTL=65 on wire only proves Layer 1 (TTL) is working, not Layer 2 (DNS DNAT) — for Layer 2 use `/bypass-gap-check`
- Same network conditions both phases: don't move, don't run other downloads, don't switch APs
- Disable script needs a TTY for sudo (CLAUDE.md rule #3) — pre-cache with `sudo -v`

## Cleanup

Baseline files at `/tmp/td-*-before.txt` are kept for post-mortem. Delete with `rm /tmp/td-*-before.txt` when done.
