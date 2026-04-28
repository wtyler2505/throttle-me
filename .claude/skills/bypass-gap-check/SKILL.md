---
name: bypass-gap-check
description: Verify the 3 documented silent failure modes in throttle-me's bypass mechanism — chattr no-op on /etc/resolv.conf symlink, IPv6 DNS NAT silent failure (kernel module not loaded), and missing TCP MSS clamping. Reports PASS/FAIL/N/A for each with specific remediation. Run before assuming the bypass is fully effective, especially after kernel updates.
disable-model-invocation: true
---

# Bypass Gap Check

Verify documented silent-failure modes in throttle-me are not hiding a partially-broken bypass. These three checks correspond directly to CLAUDE.md rules #4, #5, and the "Known Gaps" finding from 2026-04-24 diagnostics.

## When to use

- Bypass appears active but speeds suggest carrier detection
- After a kernel update (modules may have unloaded)
- After `apt upgrade` / system update
- Before claiming the bypass is "fully working" in any report
- Routinely, before each `/bypass-diag` A/B run

## Checks

### Gap 1: chattr +i no-op on /etc/resolv.conf symlink

The `bypass-tethering` script runs `chattr +i /etc/resolv.conf` to lock DNS settings. On systems with systemd-resolved, `/etc/resolv.conf` is a symlink to `/run/systemd/resolve/stub-resolv.conf`. `chattr +i` on a symlink follows the link to the target — but if the target is on a tmpfs (which `/run` is), chattr fails silently.

```bash
RESOLV_TARGET=$(readlink -f /etc/resolv.conf)
echo "Resolv target: ${RESOLV_TARGET}"

if [[ "${RESOLV_TARGET}" != "/etc/resolv.conf" ]]; then
    # It's a symlink. Check if target is on tmpfs.
    FS=$(stat -f -c '%T' "${RESOLV_TARGET}" 2>/dev/null || echo unknown)
    echo "Target filesystem: ${FS}"
    if [[ "${FS}" == "tmpfs" ]]; then
        echo "FAIL — Gap 1: /etc/resolv.conf → ${RESOLV_TARGET} (tmpfs). chattr +i is a silent no-op."
        echo "  → Remediation: replace symlink with real file, OR remove the misleading lock attempt from bypass-tethering"
    else
        if lsattr "${RESOLV_TARGET}" 2>/dev/null | grep -q '^....i'; then
            echo "PASS — Gap 1: chattr +i set on ${RESOLV_TARGET}"
        else
            echo "FAIL — Gap 1: chattr +i not set on ${RESOLV_TARGET}"
        fi
    fi
else
    if lsattr /etc/resolv.conf 2>/dev/null | grep -q '^....i'; then
        echo "PASS — Gap 1: chattr +i set on real /etc/resolv.conf"
    else
        echo "FAIL — Gap 1: chattr +i not set"
    fi
fi
```

### Gap 2: IPv6 DNS NAT kernel module + rule presence

`bypass-tethering` lines 46-47 attempt `ip6tables -t nat -A OUTPUT ... DNAT ... 1.1.1.1:53` with `2>/dev/null`. If `nf_nat_ipv6` (or modern `nft_nat`) isn't loaded, the rule fails to install but the error is swallowed. IPv6 DNS then leaks past the bypass.

```bash
# Modern kernels use nft_nat / xt_nat; older kernels use nf_nat_ipv6.
if lsmod | grep -qE 'nf_nat_ipv6|nft_nat|xt_nat'; then
    MODULE_OK=1
    LOADED=$(lsmod | grep -oE 'nf_nat_ipv6|nft_nat|xt_nat' | sort -u | tr '\n' ' ')
    echo "Kernel modules loaded: ${LOADED}"
else
    MODULE_OK=0
    echo "FAIL — Gap 2a: no NAT-related kernel module loaded"
    echo "  → Remediation: sudo modprobe nf_nat (auto-loads dependencies on modern kernels)"
fi

if [[ "${MODULE_OK}" == "1" ]]; then
    if sudo ip6tables -t nat -L OUTPUT -n 2>/dev/null | grep -q "DNAT.*1.1.1.1:53"; then
        echo "PASS — Gap 2: IPv6 DNS DNAT rule active"
    else
        echo "FAIL — Gap 2b: NAT module loaded but no IPv6 DNAT rule found"
        echo "  → bypass-tethering line 46-47 either ran while module was unloaded, or rule was flushed"
        echo "  → Remediation: re-run ./throttle-me -d && ./throttle-me -e"
    fi
fi
```

### Gap 3: TCP MSS clamping (defense-in-depth, not currently a break)

Carriers can fingerprint via TCP MSS values that differ between desktop OS and iPhone. throttle-me does not currently clamp MSS. This is a defense-in-depth gap, NOT a current break. Report N/A if not present.

```bash
if sudo iptables -t mangle -L POSTROUTING -n 2>/dev/null | grep -q "TCPMSS"; then
    echo "PASS — Gap 3: TCP MSS clamping rule present"
else
    echo "N/A — Gap 3: No TCP MSS clamping (defense-in-depth gap)"
    echo "  → If carrier detection moves beyond TTL, consider:"
    echo "    sudo iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
fi
```

## Output format

After running all three checks, emit a 3-line summary table:

```
| Gap                          | Status | Action                       |
|------------------------------|--------|------------------------------|
| 1. chattr no-op on resolv    | ?      | <action>                     |
| 2. IPv6 NAT silent fail      | ?      | <action>                     |
| 3. TCP MSS not clamped       | ?      | <action>                     |
```

Then a one-line verdict:
- **All PASS / N/A** → "Mechanism integrity OK. Speed issues are not due to known gaps."
- **Any FAIL** → "Mechanism has gaps. Address before assuming bypass is effective."

## Related

- `/bypass-diag` — A/B test bypass effectiveness (use AFTER this skill verifies mechanism)
- CLAUDE.md rules #4, #5 — define these gaps as critical
- `~/.local/bin/bypass-tethering` — external script where the silent failures live (lines 46-47, ~line 50ish for chattr)
