# Product Analysis: throttle-me

Date: 2026-04-25
Scope: feature gap analysis, competitive comparison, UX evaluation, tech debt audit, and roadmap proposals for the Bash TUI in this repository.

## Executive Summary

`throttle-me` has a clear, useful product wedge: make a fragile Linux hotspot-bypass workflow understandable, observable, and reversible from a TUI/CLI. The modular Bash structure is small enough to keep moving quickly, and the product already has a stronger operations surface than a one-off script: status, daemon controls, presets, session history, retention, and docs.

Implementation progress started after this analysis:

- Added a new Textual command-center dashboard as the default `throttle-me` no-arg UI, with `--classic` retaining the old dialog UI.
- Added a Python read/diagnostic layer that reports active/partial/inactive/unknown state without mutating firewall or DNS state.
- Added repo-shipped `scripts/bypass-tethering` and `scripts/disable-bypass-tethering` so fresh installs have concrete script sources.
- Updated config loading so script paths and dashboard/daemon settings are honored.
- Passed config values through to the shipped bypass scripts via `TTL_VALUE`, `HL_VALUE`, and `DNS_SERVER`.
- Relabeled DNS behavior as public DNS redirection rather than encrypted DoH/DoT.
- Aligned installer and daemon docs around command-scoped sudoers guidance.
- Expanded the dashboard through three tmux-verified iteration rounds: callback-safe confirmations, native Textual command palette, smart inspector, live config editor, profiles, doctor report, command history, repeat-last, command-in-flight guard, and responsive side-panel behavior.
- Cleaned the shellcheck findings for the expanded shell surface.

The biggest remaining gaps are now safety and product-truth gaps, not basic UI polish:

1. The shipped bypass scripts still flush shared `POSTROUTING` chains. That is the largest safety risk because unrelated firewall rules can be removed.
2. Existing installs may still point at older local bypass scripts because the installer does not overwrite user-owned copies. The dashboard can detect mismatched script TTL/DNS, but migration needs a first-class path.
3. Enable/disable is not transactional. The product can diagnose partial state, but the rule application path does not yet snapshot, verify, and roll back.
4. DNS language is now honest, but the product only implements public resolver redirection. There is no encrypted local resolver mode yet.
5. The daemon is promising but still needs a clearer privilege model, first-run prerequisite checks, and event-driven NetworkManager integration.

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
   - Status: mostly done. The repo now includes `scripts/bypass-tethering` and `scripts/disable-bypass-tethering`, and `install.sh` installs them when the user does not already have local copies.
   - Remaining gap: existing hardcoded local copies are preserved, so the dashboard should offer an explicit "replace with managed script" migration.

2. Make config actually drive behavior.
   - Status: partially done. `lib/config.sh` now honors script paths and dashboard/daemon settings, and `lib/core.sh` passes `TTL_VALUE`, `HL_VALUE`, and `DNS_SERVER` into the shipped scripts.
   - Remaining gap: the live dashboard profiles save config, but legacy/local scripts can still disagree with config unless migrated.

3. Correct the DNS privacy claim.
   - Status: done for current wording. The dashboard and shipped scripts now describe this as public DNS redirection on port 53, not DoH/DoT.
   - Evidence: the iptables man page documents DNAT as destination address rewriting, not encryption: https://people.netfilter.org/kadlec/ipset/iptables.man.html
   - Recommendation: add a separate encrypted local resolver mode only if transport verification can prove it.

4. Fix status semantics.
   - Status: mostly done. CLI/dashboard now expose `ACTIVE`, `PARTIAL`, `INACTIVE`, and `UNKNOWN`, plus IPv4 TTL, IPv4 DNS, IPv6 HL, IPv6 DNS, DNS config, DNS lock, and packet counters where sudo permits.
   - Remaining gap: add wire-level TTL verification and nftables backend detection.

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
- The command-center dashboard now organizes the right mental model: evidence, commands, diagnostics, traffic, sessions, settings, logs, and live config.
- Native command palette support gives keyboard-first operation without hunting through buttons.
- Confirmation prompts now use Textual callbacks instead of `push_screen_wait`, avoiding the `NoActiveWorker` crash.
- The smart inspector answers the next-action question and shows readiness, warning counts, profile hints, and recent command history.

Main UX risks:

- Normal empty state can look like failure. `./throttle-me -p` prints "No saved presets found" and exits through the error trap with "Script exited with code 1".
- Version output is noisy. `./throttle-me -v` logs config loading before printing version.
- Some destructive actions still depend on external scripts and sudo behavior; the dashboard surfaces output, but the product needs transactional verification.
- Existing local scripts can disagree with dashboard config; this is visible in diagnostics but not yet one-click repair.
- Dense terminal layouts remain sensitive to very narrow widths, though the right rail now hides below 140 columns.

Recommended UX principle: every screen should answer three questions clearly: "What is active?", "How do we know?", and "What will be changed if I continue?"

## Tech Debt Audit

### scc

Command:

```bash
scc throttle-me throttle-me-daemon install.sh test-theme.sh lib config docs PRD.md dashboard --no-cocomo
```

Result:

| Language | Files | Lines | Code | Comments | Complexity |
|---|---:|---:|---:|---:|---:|
| Shell | 15 | 2823 | 2054 | 320 | 273 |
| Python | 7 | 1441 | 1228 | 1 | 285 |
| Markdown | 5 | 3258 | 2459 | 0 | 0 |
| BASH | 2 | 440 | 356 | 40 | 37 |
| Systemd | 1 | 24 | 20 | 0 | 0 |
| TOML | 1 | 26 | 22 | 0 | 1 |
| Total | 31 | 8012 | 6139 | 361 | 596 |

Interpretation: code volume is still manageable, but the new Python dashboard roughly doubles measured complexity. The highest-risk complexity now lives in collectors/renderers plus the older shell status/daemon/rule checks.

### lizard

Command:

```bash
lizard -C 8 -L 50 throttle-me throttle-me-daemon install.sh test-theme.sh lib/*.sh dashboard/src/throttle_me_dashboard/*.py
```

Result: 177 functions, average CCN 3.1, 14 warnings under tightened thresholds. `lizard` exits non-zero because these threshold warnings are intentionally strict.

Hotspots:

- `dashboard/src/throttle_me_dashboard/collectors.py:373` `collect_snapshot` - CCN 21, length 70
- `dashboard/src/throttle_me_dashboard/collectors.py:232` `network_info` - CCN 17
- `dashboard/src/throttle_me_dashboard/collectors.py:351` `diagnostics` - CCN 15
- `dashboard/src/throttle_me_dashboard/renderers.py:155` `render_inspector` - CCN 13
- `dashboard/src/throttle_me_dashboard/renderers.py:185` `render_overview` - CCN 9, length 57
- `lib/iptables.sh:60` `get_bypass_status` - CCN 11, length 60
- `lib/core.sh:76` `show_status` - CCN 10, length 59
- `lib/daemon.sh:108` `daemon_status` - CCN 10, length 61
- `lib/utils.sh:60` `launch_dashboard` - CCN 10

### shellcheck

Required command:

```bash
shellcheck throttle-me throttle-me-daemon install.sh test-theme.sh lib/*.sh scripts/*
```

Result: passed with no findings.

### Syntax and smoke checks

Passed:

```bash
bash -n throttle-me
bash -n throttle-me-daemon
for f in lib/*.sh; do bash -n "$f"; done
bash -n install.sh
./throttle-me -v
./throttle-me -D status
uv run --project dashboard --extra test pytest -q
uv run --project dashboard throttle-me-dashboard --smoke
python3 -m compileall dashboard/src dashboard/tests
```

Not run:

- `./throttle-me -e`, `./throttle-me -d`, and `./throttle-me -s`, because they can invoke sudo/firewall/DNS operations and status can prompt for sudo in non-interactive contexts.

## Prioritized Roadmap

### Milestone 1: Trustworthy Core

- Add managed-script migration for existing installs that still point at older local bypass/disable scripts.
- Use owned iptables/nftables chains instead of flushing shared chains.
- Add transactional enable/disable with snapshot, verify, and rollback.
- Add wire-level TTL verification and nftables backend detection.
- Add a real encrypted DNS mode only if transport verification can prove DoH/DoT.

### Milestone 2: Reliable Automation

- Normalize daemon sudoers docs and installer output.
- Remove duplicate daemon code.
- Add first-run prerequisite checks and dashboard repair flows.
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

## Dashboard Research Notes

The new dashboard direction borrows from current terminal command-center patterns:

- Textual's native command palette supports discoverable app commands without building a fragile custom search modal. That became the `p`/`ctrl+p` palette with view, action, profile, doctor, save, and repeat commands.
- Textual workers support keeping long-running commands off the UI loop. That shaped the command-in-flight guard and worker-backed CLI execution.
- K9s/lazygit-style operation favors command search, dense keyboard navigation, and immediate context over wizard-like menu hopping.
- btop-style dashboards emphasize compact evidence panels and live state, which informed the status strip, readiness meter, traffic panel, and smart inspector.

## Product Health Scorecard

| Area | Score | Rationale |
|---|---:|---|
| Value proposition | 8/10 | Clear personal workflow and real pain point. |
| Installability | 6/10 | Fresh installs now get managed scripts and dashboard files, but existing local scripts need migration. |
| Configuration integrity | 6/10 | Dashboard saves config and shipped scripts accept TTL/HL/DNS, but legacy scripts can still drift. |
| Observability | 7/10 | Dashboard shows partial/unknown states, diagnostics, inspector, logs, and sessions; wire-level proof still missing. |
| Automation | 5/10 | Daemon exists but needs privilege, prerequisite, and event-driven hardening. |
| UX clarity | 8/10 | Command-center dashboard is now keyboard-first, diagnostic, responsive, and much more understandable. |
| Maintainability | 6/10 | Shellcheck is clean, but complexity moved into collectors/renderers and still needs tests around dangerous paths. |
| Testability | 5/10 | Dashboard has automated smoke/regression tests; firewall/DNS behavior still lacks safe integration tests. |

Overall: promising early-stage product, but not yet trustworthy enough to call production-ready.

## Sources

- PairVPN hotspot page: https://pairvpn.com/hotspot
- PdaNet+/FoxFi usage guidance: https://pdanet.co/help/devices.php
- EasyTether Google Play listing: https://play.google.com/store/apps/details?id=com.mstream.easytether_beta
- GL.iNet tethering docs: https://docs.gl-inet.com/router/en/4/interface_guide/internet_tethering/
- GL.iNet EasyTether docs: https://docs.gl-inet.com/router/en/2/app/tether/
- iptables man page mirror: https://people.netfilter.org/kadlec/ipset/iptables.man.html
- Textual command palette docs: https://textual.textualize.io/guide/command_palette/
- Textual worker docs: https://textual.textualize.io/guide/workers/
- K9s command-mode docs: https://k9scli.io/topics/commands/
- LazyGit project reference: https://github.com/jesseduffield/lazygit
- btop project reference: https://github.com/aristocratos/btop
