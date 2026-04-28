# throttle-me - Agent Development Guide

Modular Bash TUI for carrier hotspot throttling bypass on Linux. Two-layer mechanism: TTL=65 (mimic iPhone) + DNS DNAT to 1.1.1.1.
**Stack:** Bash 5.x | **Lint:** shellcheck (all checks enabled, SC1090/SC1091 disabled) | **Last validated:** 2026-04-24

---

## CRITICAL RULES (NON-NEGOTIABLE)

1. **Critical: Repo has zero commits.** All files untracked. `git log` fails with *"your current branch 'main' does not have any commits yet"*. Don't assume any history exists; don't reference past commits.
2. **Critical: Bypass depends on external scripts.** `lib/core.sh` invokes `${CONFIG[BYPASS_SCRIPT]}` and `${CONFIG[DISABLE_SCRIPT]}`. Defaults set in `lib/config.sh:14-15` to `~/.local/bin/bypass-tethering` and `~/.local/bin/disable-bypass-tethering` (overridable via `~/.config/throttle-me/config`). The actual iptables work lives in those external scripts; lib/ is a wrapper.
3. **Critical: Disable script needs a TTY for sudo.** `disable-bypass-tethering` calls bare `sudo` with no `-S`. Over non-TTY pipes (Desktop Commander background, `ssh -T`, daemon contexts) it hangs forever waiting for password. Pre-cache sudo: `sudo -v` first.
4. **Critical: `chattr +i /etc/resolv.conf` is a silent no-op.** On systems with systemd-resolved, `/etc/resolv.conf` is a symlink to the stub. The lock command in `bypass-tethering` swallows errors and "succeeds" without doing anything. Don't trust DNS-locked status without verifying with `lsattr -L /etc/resolv.conf`.
5. **Critical: IPv6 DNS NAT silently fails.** `bypass-tethering` lines 46-47 hide ip6tables errors with `2>/dev/null`. If `nf_nat_ipv6` kernel module isn't loaded, IPv6 DNS leaks past the bypass. IPv4 still works. Verify with `sudo ip6tables -t nat -L OUTPUT -n -v`.
6. **Critical: Run shellcheck before declaring done.** `shellcheck throttle-me lib/*.sh`. The repo's `.shellcheckrc` enables ALL checks. Style warnings (SC2250 brace style) are noise; correctness warnings (SC2034 unused var, SC2155 declare-and-assign) are real.
7. **Critical: Do not edit `throttle-me.original`.** It's the 145-line pre-modular v1, kept as a reference snapshot. All work goes in `throttle-me` + `lib/*.sh`.

---

## CONTEXT TRIGGERS

**STOP. Before changing the bypass mechanism or DNS handling:**
→ Read `~/.local/bin/bypass-tethering` (external, not in repo) — actual iptables logic lives there
→ Read `PRD.md` for v1 requirements (only relevant sections; full file is large)

**STOP. Before working on daemon/systemd integration:**
→ Read `docs/DAEMON.md`

**STOP. Before adding a new CLI flag:**
→ Update three places in `throttle-me`: getopts string at line 35, case branch in the `while` block, help text in the `\?)` branch

---

## QUICK WORKFLOWS

**Run TUI:** `./throttle-me`

**CLI options (full list — most aren't in QUICKSTART.md):**
| Flag | Action | | Flag | Action |
|------|--------|--|------|--------|
| `-e` | Enable bypass | | `-S` | Current session stats |
| `-d` | Disable bypass | | `-H` | Session history |
| `-s` | Show status | | `-a` | Auto-detection prompt |
| `-t` | Speed test | | `-c` | Manual retention cleanup |
| `-m` | Real-time monitor (bmon) | | `-p` | Show presets |
| `-i <iface>` | Override interface | | `-l <name>` | Load preset |
| `-D start\|stop\|status` | Daemon | | `-v` | Version |

**Syntax check:** `bash -n throttle-me && for f in lib/*.sh; do bash -n "$f"; done`
**Lint:** `shellcheck throttle-me lib/*.sh`
**Trace:** `bash -x ./throttle-me -s`
**Verify TTL on wire:** `timeout 5 sudo tcpdump -v -i wlo1 -c 5 'tcp port 443' | grep ttl`
**A/B test bypass effectiveness:** `/bypass-diag` (project skill — captures iptables, runs ON/OFF speed tests, restores state)
**Verify the 3 known silent failures:** `/bypass-gap-check` (project skill — checks chattr no-op, v6 NAT module, MSS clamping)
**Inspect rules:** `sudo iptables -t mangle -L POSTROUTING -n -v && sudo iptables -t nat -L OUTPUT -n -v`
**Logs:** `cat ~/.local/share/throttle-me/throttle-me.log` (app), `journalctl --user -u throttle-me-daemon -f` (daemon)

---

## KEY LOCATIONS

| Need | Location |
|------|----------|
| Main entry (sources all lib/) | `throttle-me` |
| Daemon entry | `throttle-me-daemon` |
| Pre-modular reference (do not edit) | `throttle-me.original` |
| User config | `~/.config/throttle-me/config` |
| Config defaults | `lib/config.sh` |
| Config template | `config/throttle-me.conf`, `config/config.template` |
| External enable script | `~/.local/bin/bypass-tethering` |
| External disable script | `~/.local/bin/disable-bypass-tethering` |
| systemd unit template | `config/throttle-me-daemon.service` |
| App logs | `~/.local/share/throttle-me/throttle-me.log` |
| Sessions (30-day auto-cleanup) | `~/.local/share/throttle-me/sessions/` |
| Phase notes (work history, untracked) | `PHASE*.md`, `THEME-FIXED.md`, `OPTION-C-COMPLETE.md`, `NSA-THEME-COMPLETE.md` |
| Plans | `docs/plans/` |
| Empty placeholders | `tests/`, `data/` |

---

## ARCHITECTURE

**Bypass:** `core.sh` (orchestration) → `iptables.sh` (rule check/count) + external scripts (actual iptables work)
**Detection:** `network.sh` (interface auto-detect: wlo1 → wlan0 → wlp*) + `detection.sh` (SSID match against `KNOWN_HOTSPOT_SSIDS`)
**UI:** `ui-dialog.sh` (dialog menus) + `ui-theme.sh` (NSA green/black + figlet)
**Data:** `config.sh` + `presets.sh` + `stats.sh` + `retention.sh`
**System:** `daemon.sh` (systemd) + `logging.sh` + `utils.sh`

**Bypass mechanism:**
- L1 (TTL): `iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65`
- L2 (DNS): `iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 1.1.1.1:53` + write `nameserver 1.1.1.1` to `/etc/resolv.conf`

The `.claude/` subdirectory contains agents/commands/skills/scripts and `settings.json` — actively used, not stale.

---

## BANNED

- ❌ **Don't run `./throttle-me -d` over non-TTY contexts** — bare sudo prompt hangs (rule #3)
- ❌ **Don't trust `chattr +i` succeeded** on `/etc/resolv.conf` — silent no-op on symlinks (rule #4)
- ❌ **Don't `git log` expecting history** — repo has no commits (rule #1)
- ❌ **Don't edit `throttle-me.original`** — reference snapshot only (rule #7)
- ❌ **Don't duplicate global CLI tool docs here** — `rg`, `fd`, `scc`, `lizard`, `bat`, `jq`, `tree`, `ast-grep`, `fzf`, etc. are documented in `~/.claude/CLAUDE.md`. Project-specific tooling only goes here.
