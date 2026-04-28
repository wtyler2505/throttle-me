# throttle-me

Modular Bash TUI for bypassing carrier hotspot throttling on Linux.

Most US carriers throttle tethered traffic once a hotspot allowance is hit (often to sub-1 Mbps). `throttle-me` rewrites outbound packet headers and redirects DNS so tethered traffic looks like phone traffic, restoring full speed.

> **Disclaimer.** This tool modifies how your machine presents traffic to your carrier. Whether that violates your carrier's terms of service is between you and them. It is provided for personal/educational use. No warranty.

---

## How it works

Two-layer bypass, both implemented with `iptables`:

1. **TTL normalization (`-t mangle -A POSTROUTING -j TTL --ttl-set 65`).** Phones send packets with TTL=64; by the time tethered packets leave your laptop their TTL is 63. Carriers fingerprint that gap. Forcing TTL to 65 (so it arrives at 64) defeats the heuristic. IPv6 hop-limit gets the same treatment.
2. **DNS redirection (`-t nat -A OUTPUT --dport 53 -j DNAT --to 1.1.1.1:53`).** Carriers also fingerprint via their own DNS resolvers. All port-53 traffic is rewritten to Cloudflare, `/etc/resolv.conf` is pointed at `1.1.1.1`, and (best-effort) marked immutable.

The mechanics live in two small scripts under `scripts/`. Everything else in this repo is a TUI/daemon/config layer wrapped around them.

---

## Features

- **TUI** — `dialog`-based menu with NSA-green theme and `figlet` banner
- **CLI** — every TUI action also exposed as a flag (`-e`, `-d`, `-s`, `-t`, …)
- **Auto-detection** — detects your wireless interface (`wlo1` → `wlan0` → `wlp*`) and prompts when a known hotspot SSID appears
- **Presets** — named bypass configs you can load on demand
- **Sessions & stats** — per-session usage tracking with 30-day auto-cleanup
- **Speed test** — built-in before/after speedtest harness
- **Live monitor** — wraps `bmon` for real-time throughput
- **systemd daemon** — optional user-unit that auto-toggles bypass when known hotspot SSIDs come and go
- **Python dashboard** — optional Textual-based command center under `dashboard/`

---

## Quick start

Five steps. Five minutes. Run them in order; don't skip the `sudo -v` in step 5.

### 1. Install the dependencies

On Ubuntu, Debian, or Linux Mint:

```bash
sudo apt-get update
sudo apt-get install -y bash iptables dialog figlet git
```

Optional but recommended:

```bash
sudo apt-get install -y bmon speedtest-cli
```

On Fedora/Arch, swap in `dnf install` / `pacman -S` with the same package names.

### 2. Download the repo

```bash
git clone https://github.com/wtyler2505/throttle-me.git
cd throttle-me
```

### 3. Run the installer

```bash
./install.sh
```

The installer copies four scripts into `~/.local/bin/`:

| Script | What it does |
|--------|--------------|
| `throttle-me` | The TUI/CLI you actually use |
| `throttle-me-daemon` | Optional auto-toggle when known hotspots appear |
| `bypass-tethering` | The script that actually adds the iptables rules |
| `disable-bypass-tethering` | Tears those rules back down |

It also drops a systemd user unit at `~/.config/systemd/user/throttle-me-daemon.service` and seeds a config at `~/.config/throttle-me/config`.

### 4. Make sure `~/.local/bin` is on your PATH

```bash
which throttle-me
```

If that prints nothing, add this line to `~/.bashrc` (or `~/.zshrc`) and reload your shell:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 5. Turn the bypass on

```bash
sudo -v          # cache your sudo password — see "Known silent-failure modes" #3
throttle-me -e   # enable bypass
throttle-me -s   # check it's active
```

To run a speed test, then turn it off when you're done:

```bash
throttle-me -t   # before/after speed test
throttle-me -d   # disable bypass
```

That's the whole loop. The rest of this README is reference.

---

## Windows

Same two-layer mechanism (TTL=65 + DNS DNAT to 1.1.1.1), built on [WinDivert](https://reqrypt.org/windivert.html) instead of `iptables` — bypass toggles instantly with no reboot, matching the Linux UX.

**For non-technical users:** download `throttle-me-setup.exe` from the [latest release](https://github.com/wtyler2505/throttle-me/releases/latest), double-click, click through the wizard. After install, use the **Throttle Me — Turn ON / Turn OFF** shortcuts in the Start Menu. No command line involved.

**For developers / from source:** see [`windows/README.md`](windows/README.md) for the build/install walkthrough (Go + WinDivert + PowerShell CLI parity with the Linux flags).

---

## Requirements

- Linux (developed on Linux Mint 22.2 / Ubuntu)
- `bash` 4+, `iptables`, `ip6tables`, `dialog`, `figlet`
- `sudo` (the bypass needs root for `iptables`)
- Optional: `bmon` (live monitor), `speedtest-cli` (`-t`), `python3` + `uv` (dashboard)

For a manual (non-installer) walkthrough, see `docs/QUICKSTART.md`.

---

## Usage

### TUI

```bash
throttle-me
```

Arrow keys + Enter to navigate, Esc to back out.

### CLI

| Flag | Action |
|------|--------|
| `-e` | Enable bypass |
| `-d` | Disable bypass |
| `-s` | Show status |
| `-t` | Speed test |
| `-m` | Real-time monitor (`bmon`) |
| `-S` | Current session stats |
| `-H` | Session history |
| `-a` | Auto-detection prompt |
| `-c` | Manual retention cleanup |
| `-p` | Show presets |
| `-l <name>` | Load preset |
| `-i <iface>` | Override interface |
| `-D start\|stop\|status` | Daemon control |
| `-v` | Version |

### Verify the bypass is actually working

```bash
# TTL on the wire (should be 65 leaving the box; replace wlo1 with your interface)
sudo tcpdump -v -i wlo1 -c 5 'tcp port 443' | grep ttl

# Active iptables rules
sudo iptables -t mangle -L POSTROUTING -n -v
sudo iptables -t nat -L OUTPUT -n -v
```

The repo also ships two diagnostic skills under `.claude/skills/`:
- `bypass-diag/` — A/B speed test with bypass on/off, restores prior state
- `bypass-gap-check/` — checks the three known silent-failure modes below

---

## Using the bypass scripts on their own

`throttle-me` is a wrapper. The actual `iptables` work lives in two small standalone scripts under `scripts/`:

- `scripts/bypass-tethering` — sets `TTL=65`, DNATs port 53 to `1.1.1.1`, points `/etc/resolv.conf` at Cloudflare, and (best-effort) locks it
- `scripts/disable-bypass-tethering` — undoes all of the above

If you don't want the TUI, daemon, presets, or session tracking, skip `install.sh` and use just the scripts:

```bash
# Copy them onto your PATH
cp scripts/bypass-tethering scripts/disable-bypass-tethering ~/.local/bin/
chmod +x ~/.local/bin/bypass-tethering ~/.local/bin/disable-bypass-tethering

# Cache sudo first — the disable script does NOT prompt for a password and will
# hang forever in a non-TTY shell otherwise. (See "Known silent-failure modes" #3.)
sudo -v

# Turn on
sudo bypass-tethering

# Turn off
sudo disable-bypass-tethering
```

Both scripts read env-var overrides (`TTL_VALUE`, `DNS_SERVER`, the interface name, etc.). Open `scripts/bypass-tethering` to see the full list — they're declared at the top.

---

## Known silent-failure modes

Verified gaps in the v1 bypass. Read these before relying on it.

1. **`chattr +i /etc/resolv.conf` is a no-op when `systemd-resolved` is active.** The path is a symlink to the stub resolver; `chattr` swallows the error and "succeeds." Verify: `lsattr -L /etc/resolv.conf`.
2. **IPv6 DNS NAT silently fails if `nf_nat_ipv6` isn't loaded.** Errors are redirected to `/dev/null`. IPv4 still works; v6 leaks. Verify: `sudo ip6tables -t nat -L OUTPUT -n -v`.
3. **`disable-bypass-tethering` calls bare `sudo` with no `-S`.** Over a non-TTY context (background agent, `ssh -T`, daemon) it hangs forever waiting on a password prompt. Pre-cache with `sudo -v` first.

A fourth thing worth knowing: TCP MSS isn't clamped, so DF-set packets that would have been fragmented before the TTL change can blackhole on some paths. Not yet observed in practice.

---

## Architecture

```
throttle-me                         entry point, sources lib/*.sh
throttle-me-daemon                  systemd-driven SSID watcher
throttle-me.original                pre-modular v1 reference (do not edit)
lib/
  core.sh         orchestration: enable/disable/status
  iptables.sh     rule check + count
  network.sh      interface auto-detect
  detection.sh    SSID match against KNOWN_HOTSPOT_SSIDS
  ui-dialog.sh    dialog menus
  ui-theme.sh     NSA green/black theme + figlet
  config.sh       defaults, ~/.config/throttle-me/config loader
  presets.sh      named configs
  stats.sh        session metrics
  retention.sh    30-day cleanup
  daemon.sh       systemd integration
  logging.sh      structured logs to ~/.local/share/throttle-me/throttle-me.log
  utils.sh        small helpers
scripts/
  bypass-tethering              refactored, env-var-parameterized
  disable-bypass-tethering      same
  bypass-tethering.installed    snapshot of the version actually running at ~/.local/bin/
  disable-bypass-tethering.installed
config/
  throttle-me.conf              template config
  config.template               same, alt name
  throttle-me-daemon.service    systemd user unit
dashboard/                       optional Python/Textual command center
docs/
  QUICKSTART.md
  DAEMON.md
  plans/
```

Bypass orchestration: `lib/core.sh` invokes `${CONFIG[BYPASS_SCRIPT]}` and `${CONFIG[DISABLE_SCRIPT]}` (default `~/.local/bin/bypass-tethering` / `~/.local/bin/disable-bypass-tethering`). The actual `iptables` calls live in those scripts, not in `lib/`.

---

## Configuration

User config lives at `~/.config/throttle-me/config`. Defaults are in `lib/config.sh`. Override anything by setting it there:

```bash
TTL_VALUE=65
DNS_SERVER=1.1.1.1
KNOWN_HOTSPOT_SSIDS=("MyiPhone" "Pixel-Hotspot")
BYPASS_SCRIPT=~/.local/bin/bypass-tethering
DISABLE_SCRIPT=~/.local/bin/disable-bypass-tethering
```

---

## Files & paths

| What | Where |
|------|-------|
| User config | `~/.config/throttle-me/config` |
| App logs | `~/.local/share/throttle-me/throttle-me.log` |
| Sessions (auto-cleaned at 30d) | `~/.local/share/throttle-me/sessions/` |
| systemd unit | `~/.config/systemd/user/throttle-me-daemon.service` |
| External bypass scripts | `~/.local/bin/{bypass,disable-bypass}-tethering` |

---

## Development

```bash
# Syntax check everything
bash -n throttle-me
for f in lib/*.sh; do bash -n "$f"; done

# Lint (all checks enabled, SC1090/SC1091 disabled)
shellcheck throttle-me lib/*.sh

# Trace
bash -x ./throttle-me -s
```

`CLAUDE.md` documents repo-specific rules and pitfalls for AI assistants and human contributors alike.

---

## License

Personal use. No warranty.
