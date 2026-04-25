# Product Analysis: throttle-me

Date: 2026-04-25
Scope: feature gap analysis, competitive comparison, UX evaluation, tech debt audit, and roadmap proposals for the Bash TUI in this repository.

## Executive Summary

`throttle-me` has a clear, useful product wedge: make a fragile Linux hotspot-bypass workflow understandable, observable, and reversible from a TUI/CLI. The modular Bash structure is small enough to keep moving quickly, and the product already has a stronger operations surface than a one-off script: status, daemon controls, presets, session history, retention, and docs.

The biggest gaps are product-truth gaps, not missing polish:

1. Installability is broken for a fresh clone. The docs tell users to copy `bypass-tethering` and `disable-bypass-tethering`, but those scripts are not in the repo, and `install.sh` does not install them. `lib/core.sh` still depends on the external scripts.
2. Config and presets are mostly advisory. `TTL_VALUE` and `DNS_SERVER` update status text and saved presets, but the actual external bypass script hardcodes TTL 65 and Cloudflare DNS.
3. The DNS claim is overstated. The product and script describe "encrypted DNS" and "Cloudflare DoH", but the implementation writes `nameserver 1.1.1.1` and DNATs port 53 to `1.1.1.1:53`, which is normal DNS transport, not DoH.
4. Status can over-report safety. It does not verify `resolv.conf` immutability through symlinks, partial IPv4/IPv6 failure modes, nftables compatibility, or whether the configured preset actually affected packet rules.
5. The daemon is promising but brittle. It has duplicated header/init code, a default `AUTO_ENABLE=false`, ignored template settings, hardcoded polling, and sudoers documentation that conflicts with installer guidance.

Best next product move: build a "truthful core" milestone before adding new bypass techniques. Make install, config, status, and daemon behavior accurately reflect the machine state. That will compound into trust.

## Product Positioning

Primary job-to-be-done:

> "When I am working from a mobile hotspot on Linux, help me enable the known bypass, prove what is active, and get back to normal WiFi safely."

Current differentiator:

- Linux-native CLI/TUI for a personal power-user workflow.
- No phone app, desktop app, router admin panel, or paid service required.
- Direct visibility into local rules, sessions, and daemon status.

Current weakness:

- The product wraps a private/local script dependency rather than shipping a complete bypass engine.
- It claims more privacy/security than the implementation currently delivers.
- It has no automated safety tests around firewall and DNS behavior.

## Competitive Comparison

| Product/category | What it does well | Relevant source | throttle-me advantage | throttle-me gap |
|---|---|---|---|---|
| PairVPN | Runs a local VPN between phone and client so traffic appears as phone data; official docs state one-device support and iOS foreground limits. | https://pairvpn.com/hotspot | No mobile app or VPN pairing; native Linux terminal workflow. | PairVPN has a clearer end-to-end product story and cross-device packaging. throttle-me needs stronger proof/status to compete on trust. |
| PdaNet+/FoxFi | Mature Android tethering product with USB/Bluetooth modes and "Hide Tether Usage" guidance for some carriers. | https://pdanet.co/help/devices.php | Linux host script can be lighter than a phone+desktop client. | PdaNet has a user-facing support matrix and mode guidance. throttle-me lacks compatibility guidance by carrier/device/mode. |
| EasyTether | Android app supports Linux/OpenWrt and does not require root or special tethering plans, but full functionality is paid and the lite version blocks HTTPS. | https://play.google.com/store/apps/details?id=com.mstream.easytether_beta | No phone-side app purchase; simpler for Tyler's known setup. | EasyTether supports more host/router targets and has clearer packaging. |
| GL.iNet/OpenWrt router tethering | Router UI supports phone tethering, and current GL.iNet docs expose advanced TTL, HL, and MTU settings. | https://docs.gl-inet.com/router/en/4/interface_guide/internet_tethering/ | No extra router hardware; direct laptop use. | Router products provide multi-device sharing, visual network state, and hardware isolation. |

Market implication: do not try to out-feature phone apps or routers broadly. Win the "single Linux laptop, fast reversible control, honest diagnostics" niche.

## Feature Gap Analysis

### P0 - Product must be truthful and installable

1. Ship or explicitly generate the external bypass scripts.
   - Evidence: `lib/core.sh` executes `${CONFIG[BYPASS_SCRIPT]}` and `${CONFIG[DISABLE_SCRIPT]}`.
   - Evidence: `docs/QUICKSTART.md` lines 58-60 instruct users to copy `bypass-tethering` files from the repo, but `rg --files -g 'bypass-tethering' -g 'disable-bypass-tethering'` found none.
   - Evidence: `install.sh` installs `throttle-me`, `throttle-me-daemon`, and `lib/`, but not the external scripts.
   - Recommendation: either vendor the scripts into `bin/`, generate them from templates, or make the first-run setup detect and import existing local scripts with explicit warnings.

2. Make config actually drive behavior.
   - Evidence: `lib/config.sh` loads `TTL_VALUE`, `DNS_SERVER`, `LOG_LEVEL`, and related settings, but does not load `BYPASS_SCRIPT` or `DISABLE_SCRIPT` from config despite `config/throttle-me.conf` defining them.
   - Evidence: external `/home/wtyler/.local/bin/bypass-tethering` hardcodes TTL 65 and DNS `1.1.1.1`/`1.0.0.1`.
   - Evidence: presets in `lib/presets.sh` set `TTL_VALUE` and `DNS_SERVER`, but loading a preset does not persist settings and does not change the hardcoded external script.
   - Recommendation: replace hardcoded external script values with generated/app-owned rule application, or pass config through environment/flags to a parameterized engine.

3. Correct the DNS privacy claim.
   - Evidence: `/home/wtyler/.local/bin/bypass-tethering` lines 33-47 write plain `nameserver` entries and DNAT port 53 to `1.1.1.1:53`.
   - Evidence: the iptables man page documents DNAT as destination address rewriting, not encryption: https://people.netfilter.org/kadlec/ipset/iptables.man.html
   - Recommendation: either relabel this as "public DNS redirection" or add a real local DoH/DoT resolver path and verify it.

4. Fix status semantics.
   - Evidence: `lib/iptables.sh` marks overall status `ACTIVE` if IPv4 bypass is active or IPv6 hop-limit is active.
   - Evidence: PRD defines partial states where TTL and DNS can differ, but current CLI collapses this into active/inactive.
   - Recommendation: report `ACTIVE`, `PARTIAL`, `INACTIVE`, and `UNKNOWN`, with explicit rows for IPv4 TTL, IPv4 DNS, IPv6 HL, IPv6 DNS, DNS config, DNS lock, and wire-level packet counters.

### P1 - Safety, daemon reliability, and supportability

5. Stop flushing shared firewall chains.
   - Evidence: external enable/disable scripts run `iptables -t mangle -F POSTROUTING` and `ip6tables -t mangle -F POSTROUTING`.
   - Risk: this removes unrelated user or system rules.
   - Recommendation: manage a dedicated chain, insert a single jump, and remove only owned rules.

6. Make daemon defaults and docs line up.
   - Evidence: `config/config.template` defaults `AUTO_ENABLE=false`, while `docs/DAEMON.md` markets "No manual intervention required."
   - Evidence: `throttle-me-daemon` contains duplicated initialization lines 1-56.
   - Evidence: docs recommend sudoers entries for external scripts; installer suggests entries for `throttle-me`, `iptables`, `ip6tables`, `tee`, and `chattr`.
   - Recommendation: decide on one daemon privilege model, add `throttle-me -D doctor`, and make the daemon refuse to start auto-management until prerequisites pass.

7. Persist settings changed in the TUI.
   - Evidence: `ui_settings` mutates `CONFIG[...]` values in memory only.
   - Recommendation: add `save_config`, show "session only" vs "saved" states, and write atomically.

8. Add dependency checks for all invoked commands.
   - Evidence: `install.sh` checks `dialog`, `iptables`, `ip6tables`, and `sudo` only.
   - Additional commands used: `curl`, `bc`, `bmon`, `figlet`, `iwgetid`, `nmcli`, `iwconfig`, `systemctl`, `logger`, and `flock`.
   - Recommendation: split dependencies into required, feature-specific, and optional, then degrade gracefully in the UI.

### P2 - Feature depth

9. Replace packet-count "data usage" with real byte accounting.
   - Evidence: `lib/stats.sh` stores packet deltas, not bytes. Product/docs call this data usage.
   - Recommendation: record bytes from iptables counters or an owned nftables/iptables chain.

10. Add compatibility profiles.
   - Evidence: config has ignored `HL_VALUE`, `HOTSPOT_PATTERNS`, and `POLL_INTERVAL` fields.
   - Recommendation: profiles should include TTL/HL, DNS mode, interface selector, OS/device notes, and verification recipes.

11. Add a non-mutating diagnostics mode.
   - Recommendation: `throttle-me doctor` should check tools, sudo mode, scripts, config consistency, active rules, resolv.conf symlink/lock state, IPv6 NAT support, nftables backend, captive-portal risk, and daemon prerequisites.

## UX Evaluation

What works:

- The CLI surface is compact and useful: `-e`, `-d`, `-s`, `-t`, `-D`, presets, and stats.
- The TUI organizes the right mental model: enable, disable, status, speed, monitor, statistics, presets, settings.
- Confirmation prompts reduce accidental state changes.

Main UX risks:

- Normal empty state can look like failure. `./throttle-me -p` prints "No saved presets found" and exits through the error trap with "Script exited with code 1".
- Version output is noisy. `./throttle-me -v` logs config loading before printing version.
- TUI enable/disable suppresses underlying script output. If a dependency or sudo condition fails, the user may lose useful context.
- Settings feel persistent but are runtime-only.
- The theme is expressive, but fixed-width boxes and ANSI escape sequences make status text fragile when lines are long or colorized.

Recommended UX principle: every screen should answer three questions clearly: "What is active?", "How do we know?", and "What will be changed if I continue?"

## Tech Debt Audit

### scc

Command:

```bash
scc throttle-me throttle-me-daemon install.sh test-theme.sh lib config docs PRD.md --no-cocomo
```

Result:

| Language | Files | Lines | Code | Comments | Complexity |
|---|---:|---:|---:|---:|---:|
| Shell | 15 | 2660 | 1918 | 307 | 236 |
| BASH | 2 | 432 | 339 | 45 | 38 |
| Markdown | 4 | 3225 | 2434 | 0 | 0 |
| Systemd | 1 | 24 | 20 | 0 | 0 |
| Total | 22 | 6341 | 4711 | 352 | 274 |

Interpretation: code volume is manageable. Complexity is concentrated in UI/daemon/status functions, not the core wrapper.

### lizard

Command:

```bash
lizard -C 8 -L 50 throttle-me throttle-me-daemon install.sh test-theme.sh lib/*.sh
```

Result: 101 functions, average CCN 2.9, 9 warnings under tightened thresholds.

Hotspots:

- `lib/ui-dialog.sh:349` `ui_settings` - CCN 12, length 98
- `lib/daemon.sh:107` `daemon_status` - CCN 10, length 61
- `lib/core.sh:72` `show_status` - CCN 9, length 52
- `lib/iptables.sh:46` `get_bypass_status` - CCN 8, length 52
- `lib/retention.sh:7` `apply_retention_policy` - length 78
- `lib/ui-dialog.sh:262` `ui_daemon_control` - length 85
- `lib/ui-theme.sh:42` `create_dialog_theme` - length 72

### shellcheck

Required command:

```bash
shellcheck throttle-me lib/*.sh
```

Result: failed with 32 warnings, 55 info findings, and 429 style findings. The style bulk is mostly SC2250 brace style. Correctness warnings cluster around cross-file globals, sourced state files, unused variables, and one declare-and-assign warning.

Expanded command:

```bash
shellcheck throttle-me throttle-me-daemon install.sh lib/*.sh
```

Result: 34 warnings, 64 info findings, and 524 style findings.

High-signal warning themes:

- SC2154 cross-module globals: `CONFIG`, colors, session variables, `STATS_FILE`, and sourced session values.
- SC2034 unused state: `DAEMON_SCRIPT`, `has_active_session`, `LAST_CHECK`.
- SC2155 masked return values in `lib/retention.sh` and `install.sh`.

### Syntax and smoke checks

Passed:

```bash
bash -n throttle-me
bash -n throttle-me-daemon
for f in lib/*.sh; do bash -n "$f"; done
bash -n install.sh
./throttle-me -v
./throttle-me -D status
```

Not run:

- `./throttle-me -e`, `./throttle-me -d`, and `./throttle-me -s`, because they can invoke sudo/firewall/DNS operations and status can prompt for sudo in non-interactive contexts.

## Prioritized Roadmap

### Milestone 1: Trustworthy Core

- Vendor or generate bypass/disable scripts.
- Parameterize TTL, HL, DNS, and interface.
- Use owned iptables/nftables chains instead of flushing shared chains.
- Add `ACTIVE/PARTIAL/INACTIVE/UNKNOWN` status.
- Fix DNS language or implement actual encrypted DNS.
- Add `doctor` with no state mutation.

### Milestone 2: Reliable Automation

- Normalize daemon sudoers docs and installer output.
- Remove duplicate daemon code.
- Persist TUI settings to config.
- Make `AUTO_ENABLE` state explicit during daemon start.
- Add NetworkManager event support as an optional faster path, with polling fallback.

### Milestone 3: Productized Proof

- Add before/after speed history with confidence labels.
- Track byte counters from owned chains.
- Add DNS leak and IPv6 leak checks.
- Add exportable diagnostics bundle for Claude/Tyler handoff.

### Milestone 4: Profile Ecosystem

- Add carrier/device profiles as data files.
- Add a profile wizard that asks for phone OS, connection mode, interface, and DNS preference.
- Add compatibility notes for "Linux laptop direct", "Linux via phone USB", and "router/OpenWrt".

## Innovation Proposals

1. Truth Meter
   - A single status panel that scores the bypass from evidence, not assumptions: TTL observed, DNS route observed, IPv6 state, owned rules present, DNS lock verified, and recent packet/byte movement.

2. Safe Switch
   - An enable/disable transaction that snapshots owned rules and DNS state, applies changes, verifies, and rolls back if the machine ends in partial/broken state.

3. Profile Doctor
   - Given a selected profile, run non-mutating checks and tell the user exactly what will not work before they enable anything.

4. Session Replay
   - Store anonymized event timelines: connected SSID, enabled, verified, speed test, disabled, restored DNS. This helps debug daemon behavior without dumping sensitive browsing data.

5. Honest DNS Modes
   - Offer explicit modes: "system DNS", "public resolver only", and "encrypted local resolver". Do not call a mode encrypted unless transport verification confirms it.

6. Claude/Codex Handoff Pack
   - Generate a markdown diagnostics artifact with command outputs, status evidence, config, shellcheck summary, and suggested next action. This fits the repo's multi-agent workflow.

## Product Health Scorecard

| Area | Score | Rationale |
|---|---:|---|
| Value proposition | 8/10 | Clear personal workflow and real pain point. |
| Installability | 3/10 | Missing external scripts block fresh users. |
| Configuration integrity | 4/10 | Many settings do not affect actual rule behavior. |
| Observability | 6/10 | Good start, but partial/silent failures are under-reported. |
| Automation | 5/10 | Daemon exists but needs privilege, config, and state hardening. |
| UX clarity | 6/10 | Strong menu shape; empty states/noisy logs need cleanup. |
| Maintainability | 6/10 | Small modular Bash, but shellcheck warning debt and cross-file globals need work. |
| Testability | 3/10 | No automated tests around the dangerous paths yet. |

Overall: promising alpha, but not yet trustworthy enough to call production-ready.

## Sources

- PairVPN hotspot page: https://pairvpn.com/hotspot
- PdaNet+/FoxFi usage guidance: https://pdanet.co/help/devices.php
- EasyTether Google Play listing: https://play.google.com/store/apps/details?id=com.mstream.easytether_beta
- GL.iNet tethering docs: https://docs.gl-inet.com/router/en/4/interface_guide/internet_tethering/
- GL.iNet EasyTether docs: https://docs.gl-inet.com/router/en/2/app/tether/
- iptables man page mirror: https://people.netfilter.org/kadlec/ipset/iptables.man.html
