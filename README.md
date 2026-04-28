# throttle-me

Bypass carrier hotspot throttling on **Linux** or **Windows**.

Most US carriers throttle tethered traffic once a hotspot allowance is hit (often to sub-1 Mbps). `throttle-me` rewrites outbound packet headers and redirects DNS so tethered traffic looks like phone traffic, restoring full speed.

> **Disclaimer.** This tool modifies how your machine presents traffic to your carrier. Whether that violates your carrier's terms of service is between you and them. Provided for personal/educational use. No warranty.

---

## How it works

Two-layer bypass — the same idea on both platforms, just different plumbing.

1. **TTL normalization.** Phones send packets with `TTL=64`; by the time tethered packets leave your laptop their TTL is 63. Carriers fingerprint that gap. Forcing TTL to 65 (so it arrives at 64) defeats the heuristic. IPv6 hop-limit gets the same treatment.
2. **DNS redirection.** Carriers also fingerprint via their own DNS resolvers. All port-53 traffic is redirected to Cloudflare (`1.1.1.1`); the active adapter's DNS is overridden too.

| Platform | TTL rewrite | DNS redirect | Toggles instantly? |
|----------|-------------|--------------|--------------------|
| Linux    | `iptables -t mangle -j TTL --ttl-set 65` | `iptables -t nat -j DNAT --to 1.1.1.1:53` + `/etc/resolv.conf` | Yes |
| Windows  | [WinDivert](https://reqrypt.org/windivert.html) kernel filter, TTL field rewrite | WinDivert port-53 DNAT + `netsh` adapter override | Yes |

Both paths are toggle-on / toggle-off, no reboot.

---

## Get it running

### Windows — non-technical user (≤ 2 clicks)

1. Download **`throttle-me-setup.exe`** from the [latest release](https://github.com/wtyler2505/throttle-me/releases/latest).
2. Double-click it. Click **More info → Run anyway** on the SmartScreen warning, then **Yes** on the UAC prompt, then **Next → Install** through the wizard.

After install, open the Start Menu and type **"Throttle"**. You'll see three shortcuts:

| Shortcut | What it does |
|----------|--------------|
| **Throttle Me — Turn ON**  | Enables the bypass. Brief auto-dismissing popup confirms it. |
| **Throttle Me — Turn OFF** | Disables the bypass. Same brief popup. |
| **Throttle Me — Status**   | Shows whether the bypass is currently ON or OFF. |

No command line ever needed. Day-to-day use is one click.

### Windows — developer / from source

See [`windows/README.md`](windows/README.md). Builds the Go helper, downloads WinDivert, runs Inno Setup. There's also a CLI (`throttle-me.ps1`) with flag parity to the Linux version.

### Linux — five steps

Run them in order; don't skip the `sudo -v` in step 5.

#### 1. Install the dependencies

Ubuntu / Debian / Linux Mint:

```bash
sudo apt-get update
sudo apt-get install -y bash iptables dialog figlet git
```

Optional but recommended: `sudo apt-get install -y bmon speedtest-cli`

On Fedora/Arch swap in `dnf install` / `pacman -S` with the same package names.

#### 2. Download the repo

```bash
git clone https://github.com/wtyler2505/throttle-me.git
cd throttle-me
```

#### 3. Run the installer

```bash
./install.sh
```

The installer copies four scripts into `~/.local/bin/`:

| Script | What it does |
|--------|--------------|
| `throttle-me`               | The TUI/CLI you actually use |
| `throttle-me-daemon`        | Optional auto-toggle when known hotspots appear |
| `bypass-tethering`          | The script that actually adds the iptables rules |
| `disable-bypass-tethering`  | Tears those rules back down |

It also drops a systemd user unit at `~/.config/systemd/user/throttle-me-daemon.service` and seeds a config at `~/.config/throttle-me/config`.

#### 4. Make sure `~/.local/bin` is on your `PATH`

```bash
which throttle-me
```

If that prints nothing, add this line to `~/.bashrc` (or `~/.zshrc`) and reload your shell:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

#### 5. Turn the bypass on

```bash
sudo -v          # cache your sudo password — see "Known silent-failure modes" #3
throttle-me -e   # enable bypass
throttle-me -s   # check it's active
```

Speed test, then turn it off when done:

```bash
throttle-me -t   # before/after speed test
throttle-me -d   # disable bypass
```

---

## Features

Linux is where the bulk of the project lives. The Windows port is intentionally CLI-only for v1.

| | Linux | Windows |
|---|:---:|:---:|
| Toggle on/off (CLI) | ✅ | ✅ |
| Toggle on/off (Start Menu / desktop) | — | ✅ |
| Status check                           | ✅ | ✅ |
| Speed test                             | ✅ | ✅ |
| Wireless interface auto-detection      | ✅ | ✅ |
| Hotspot SSID auto-detection prompt     | ✅ | ✅ |
| `dialog`-based TUI menu                | ✅ | — |
| Named presets                          | ✅ | — |
| Per-session usage stats + retention    | ✅ | — |
| Live throughput monitor (`bmon`)       | ✅ | — |
| Auto-toggle daemon (systemd)           | ✅ | — |
| Python/Textual command-center dashboard| ✅ | — |

The Windows surface will grow over time. Right now it's deliberately small.

---

## Linux: requirements

- Linux (developed on Linux Mint 22.2 / Ubuntu)
- `bash` 4+, `iptables`, `ip6tables`, `dialog`, `figlet`
- `sudo` (the bypass needs root for `iptables`)
- Optional: `bmon` (live monitor), `speedtest-cli` (`-t`), `python3` + `uv` (dashboard)

For a manual (non-installer) walkthrough, see [`docs/QUICKSTART.md`](docs/QUICKSTART.md).

---

## Linux: usage

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

## Linux: using the bypass scripts on their own

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

## Linux: known silent-failure modes

Verified gaps in the v1 bypass. Read these before relying on it.

1. **`chattr +i /etc/resolv.conf` is a no-op when `systemd-resolved` is active.** The path is a symlink to the stub resolver; `chattr` swallows the error and "succeeds." Verify: `lsattr -L /etc/resolv.conf`.
2. **IPv6 DNS NAT silently fails if `nf_nat_ipv6` isn't loaded.** Errors are redirected to `/dev/null`. IPv4 still works; v6 leaks. Verify: `sudo ip6tables -t nat -L OUTPUT -n -v`.
3. **`disable-bypass-tethering` calls bare `sudo` with no `-S`.** Over a non-TTY context (background agent, `ssh -T`, daemon) it hangs forever waiting on a password prompt. Pre-cache with `sudo -v` first.

A fourth thing worth knowing: TCP MSS isn't clamped, so DF-set packets that would have been fragmented before the TTL change can blackhole on some paths. Not yet observed in practice.

The Windows port has its own troubleshooting section in [`windows/README.md`](windows/README.md#troubleshooting).

---

## Architecture

### Linux

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
  bypass-tethering              env-var-parameterized
  disable-bypass-tethering      same
  *.installed                   snapshots of versions actually running at ~/.local/bin/
config/
  throttle-me.conf              template config
  throttle-me-daemon.service    systemd user unit
dashboard/                       optional Python/Textual command center
docs/QUICKSTART.md, docs/DAEMON.md
```

Bypass orchestration: `lib/core.sh` invokes `${CONFIG[BYPASS_SCRIPT]}` and `${CONFIG[DISABLE_SCRIPT]}` (default `~/.local/bin/bypass-tethering` / `~/.local/bin/disable-bypass-tethering`). The actual `iptables` calls live in those scripts, not in `lib/`.

### Windows

```
windows/
  throttle-me.ps1               PowerShell CLI (mirrors Linux flags)
  throttle-me.cmd               cmd shim
  install.ps1 / uninstall.ps1   from-source installer
  lib/                          Bypass.ps1, Network.ps1, Config.ps1, SpeedTest.ps1
  helper/                       Go service: TTL + DNS WinDivert filters
  installer/                    Inno Setup script + Toggle-Bypass.ps1 popup wrapper
  vendor/windivert/             where WinDivert.dll / .sys are dropped
.github/workflows/
  build-windows-installer.yml   tag push → throttle-me-setup.exe on Releases
```

Service architecture: an unelevated PowerShell CLI (or a Start Menu shortcut) drives the elevated `ThrottleMeHelper` Windows service via `Start-Service` / `Stop-Service`. The service opens two WinDivert handles (TTL rewrite + DNS DNAT) and overrides adapter DNS via `netsh`.

---

## Configuration

### Linux

User config lives at `~/.config/throttle-me/config`. Defaults are in `lib/config.sh`. Override anything by setting it there:

```bash
TTL_VALUE=65
DNS_SERVER=1.1.1.1
KNOWN_HOTSPOT_SSIDS=("MyiPhone" "Pixel-Hotspot")
BYPASS_SCRIPT=~/.local/bin/bypass-tethering
DISABLE_SCRIPT=~/.local/bin/disable-bypass-tethering
```

### Windows

Config lives in the registry under `HKLM\SOFTWARE\throttle-me`:

```
TTL              DWORD   65
HL               DWORD   65
DNS              SZ      1.1.1.1
Interface        SZ      ""    (empty = auto-detect)
HotspotPatterns  SZ      "iPhone*;AndroidAP*;*Galaxy*;Mobile Hotspot;*'s iPhone"
```

Edit via PowerShell:

```powershell
Set-ItemProperty 'HKLM:\SOFTWARE\throttle-me' -Name TTL -Value 70 -Type DWord
```

Changes take effect on the next enable.

---

## Files & paths

### Linux

| What | Where |
|------|-------|
| User config                      | `~/.config/throttle-me/config` |
| App logs                         | `~/.local/share/throttle-me/throttle-me.log` |
| Sessions (auto-cleaned at 30 d)  | `~/.local/share/throttle-me/sessions/` |
| systemd unit                     | `~/.config/systemd/user/throttle-me-daemon.service` |
| External bypass scripts          | `~/.local/bin/{bypass,disable-bypass}-tethering` |

### Windows

| What | Where |
|------|-------|
| Install dir                      | `C:\Program Files\throttle-me\` |
| Helper service binary            | `C:\Program Files\throttle-me\helper\throttle-me-helper.exe` |
| Service name                     | `ThrottleMeHelper` |
| Config (registry)                | `HKLM\SOFTWARE\throttle-me` |
| Service logs                     | Event Viewer → Windows Logs → Application |

---

## Development

### Linux

```bash
# Syntax check everything
bash -n throttle-me
for f in lib/*.sh; do bash -n "$f"; done

# Lint (all checks enabled, SC1090/SC1091 disabled)
shellcheck throttle-me lib/*.sh

# Trace
bash -x ./throttle-me -s
```

### Windows

```powershell
# Helper (cross-compiles cleanly from Linux too)
cd windows\helper
go vet ./...
$env:GOOS='windows'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
go build -trimpath -ldflags '-s -w' -o bin\throttle-me-helper.exe .

# PowerShell parse check (any platform with pwsh)
pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('windows/throttle-me.ps1', [ref]\$null, [ref]\$null)"

# Build the .exe installer (Windows only, needs Inno Setup 6)
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" windows\installer\throttle-me.iss
```

CI (`.github/workflows/build-windows-installer.yml`) runs the full Windows build — helper compile + WinDivert download + Inno Setup — on every tag push and every PR that touches `windows/`. Tagged releases get `throttle-me-setup.exe` attached automatically.

[`CLAUDE.md`](CLAUDE.md) documents repo-specific rules and pitfalls for AI assistants and human contributors.

---

## License

Personal use. No warranty. Bundled WinDivert binaries (Windows only, not committed) are LGPLv3 / GPLv2 dual-licensed by Reqrypt.
