# throttle-me — Windows port

Same bypass mechanism (TTL=65 + DNS DNAT to 1.1.1.1) as the Linux version,
re-implemented for Windows on top of [WinDivert](https://reqrypt.org/windivert.html)
instead of `iptables`.

> **Status:** v0.1, x64 only, Windows 10 1809+ / 11 / Server 2019+.
> CLI parity only — no TUI, daemon, presets, or stats yet.

---

## I just want to use it (no command line, no Go, no nothing)

This is the path for a non-technical user. Two clicks to install, one click
per use.

### 1. Download

Go to **[Releases](https://github.com/wtyler2505/throttle-me/releases/latest)**
and download `throttle-me-setup.exe`.

### 2. Install

Double-click `throttle-me-setup.exe`. Windows will:

- Show a SmartScreen warning the first time (not yet code-signed).
  Click **More info → Run anyway**.
- Show a UAC prompt asking for admin. Click **Yes**.
- Walk you through a normal Windows installer wizard. Click **Next**, **Install**.

Optional: tick **"Create desktop shortcuts"** on the Tasks page if you want
big easy buttons on your desktop.

### 3. Use it

Open the Start Menu and type **"Throttle"**. You'll see three shortcuts:

| Shortcut | What it does |
|----------|--------------|
| **Throttle Me — Turn ON** | Enables the bypass. A small popup appears and disappears on its own. |
| **Throttle Me — Turn OFF** | Disables the bypass. Same brief popup. |
| **Throttle Me — Status** | Shows whether the bypass is currently ON or OFF. |

Click **Turn ON** when you connect to your hotspot. Click **Turn OFF** when
you're done. That's the whole thing — no command line ever needed.

> **Why no popup notification?** Modern Windows toast notifications need an
> app identity that we don't have yet. The popup shown here is a small system
> message box that auto-closes after 2 seconds — it's intentional, not a bug.

---

## I want the CLI / I want to build from source

Everything below is for developers and power users. Skip this section if
you used the installer above.

### 1. Install the prereqs

| Tool | Why | Get it |
|------|-----|--------|
| Go 1.22+ | Build the helper service | https://go.dev/dl/ |
| PowerShell 5.1+ | Run the CLI and installer | Built-in on Windows 10/11 |
| WinDivert 2.x | Kernel packet filter | https://reqrypt.org/windivert.html |
| Inno Setup 6 (optional) | Build the .exe installer | https://jrsoftware.org/isdl.php |

### 2. Drop the WinDivert binaries in place

Download `WinDivert-2.2.X-A.zip` from the link above. Extract these three
files from `x64/` in the zip into `windows\vendor\windivert\x64\`:

```
WinDivert.dll
WinDivert64.sys
WinDivert.lib
```

(Full instructions in `vendor/windivert/README.md`.)

### 3. Build the helper

In a normal (non-admin) PowerShell:

```powershell
cd windows\helper
.\build.ps1
```

This produces `helper\bin\throttle-me-helper.exe` plus the WinDivert runtime
files copied next to it.

### 4a. Build the .exe installer (optional, lets you make a release)

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" windows\installer\throttle-me.iss
```

Output: `windows\installer\Output\throttle-me-setup.exe`. This is exactly
what the CI workflow under `.github/workflows/build-windows-installer.yml`
produces for tagged releases.

### 4b. Or install from source (no .exe installer)

Open an **elevated** PowerShell:

```powershell
cd windows
.\install.ps1
```

This:
- copies everything to `C:\Program Files\throttle-me\`
- registers a Windows service called `ThrottleMeHelper` (StartupType = Manual)
- grants Authenticated Users start/stop rights on the service so the CLI
  doesn't need UAC
- adds `C:\Program Files\throttle-me` to the system `PATH`
- seeds default config under `HKLM\SOFTWARE\throttle-me`

### 5. Use it from the CLI

Open a **fresh** cmd or PowerShell (so it picks up the new PATH):

```powershell
throttle-me -e        # enable bypass
throttle-me -s        # show status
throttle-me -t        # speed test
throttle-me -d        # disable bypass
```

That's the whole loop.

---

## CLI reference

| Flag | What it does |
|------|--------------|
| `-e` / `-Enable` | Start the helper service; bypass takes effect instantly |
| `-d` / `-Disable` | Stop the service; DNS reverts; TTL rewriting stops |
| `-s` / `-Status` | Show ACTIVE / PARTIAL / INACTIVE plus service + DNS state |
| `-t` / `-SpeedTest` | Cloudflare 10 MB download, reports Mbps |
| `-a` / `-AutoDetect` | Read current Wi-Fi SSID; if it matches a hotspot pattern, prompt to enable |
| `-i` / `-Interface <name>` | Override the adapter alias (e.g. `Wi-Fi`, `Ethernet`) |
| `-TTL <n>` | One-shot override of the TTL value (also persists to registry) |
| `-DNS <ip>` | One-shot override of the DNS server (also persists to registry) |
| `-v` / `-Version` | Print version |

---

## How it works

Two kernel-level filters, opened by the helper service via WinDivert:

1. **TTL rewrite** — filter `outbound and (ip or ipv6) and not loopback`,
   sets `IPv4.TTL = 65` (or `IPv6.HopLimit = 65`) on every outbound packet
   and reinjects. Mirrors Linux `iptables -t mangle -A POSTROUTING -j TTL`.

2. **DNS DNAT** — filter `outbound and (udp.DstPort == 53 or tcp.DstPort == 53)
   and not loopback`, rewrites the destination IP to `1.1.1.1`, recomputes
   checksums, reinjects. Mirrors Linux `iptables -t nat -A OUTPUT -p udp/tcp
   --dport 53 -j DNAT --to-destination 1.1.1.1:53`.

Plus, on enable, the service sets the active adapter's DNS to `1.1.1.1`
via `netsh`, captures the previous setting, and restores it on stop.

The bypass toggles instantly with no reboot — same UX as Linux.

---

## Verifying it actually works

```powershell
# Service running?
Get-Service ThrottleMeHelper

# Adapter DNS set?
Get-DnsClientServerAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4

# TTL on the wire (needs Wireshark or pktmon):
pktmon start --etw -p 0 -c
# ...generate some traffic...
pktmon stop
pktmon format PktMon.etl   # outbound IPv4 should show TTL=65
```

A speed test on a throttled hotspot (`throttle-me -t` before vs after enable)
is the practical end-to-end check.

---

## Configuration

The helper reads config from the Windows registry:

```
HKEY_LOCAL_MACHINE\SOFTWARE\throttle-me
  TTL              DWORD   65
  HL               DWORD   65
  DNS              SZ      1.1.1.1
  Interface        SZ      ""    (empty = auto-detect)
  HotspotPatterns  SZ      "iPhone*;AndroidAP*;*Galaxy*;Mobile Hotspot;*'s iPhone"
```

Edit via:

```powershell
Set-ItemProperty 'HKLM:\SOFTWARE\throttle-me' -Name TTL -Value 70 -Type DWord
```

Or via the CLI (writes to registry then enables):

```powershell
throttle-me -e -TTL 70 -DNS 9.9.9.9
```

Changes take effect on the next `throttle-me -e` (the service reads config
at startup, not on the fly).

See `config\throttle-me.conf.template` for a full reference.

---

## Uninstall

Elevated PowerShell:

```powershell
cd windows
.\uninstall.ps1            # removes service, files, PATH entry
.\uninstall.ps1 -Purge     # also wipes HKLM\SOFTWARE\throttle-me
```

---

## What's not in v1

Deliberately deferred to keep the port small:

- TUI dashboard (Linux `--dashboard` / `--classic`)
- Auto-toggle daemon (Linux `-D start/stop/...`) — would map to a Scheduled Task
- Presets (Linux `-p`, `-l`)
- Session stats / retention (Linux `-S`, `-H`, `-c`)
- Real-time bandwidth monitor (Linux `-m`)
- ARM64 build (x64 only)
- Code-signing the helper exe (Windows SmartScreen will warn the first run;
  click "More info → Run anyway" once)

---

## Troubleshooting

**"Service did not reach Running state within 5s"**
Check Event Viewer → Windows Logs → Application for entries from
`ThrottleMeHelper`. Most common cause: WinDivert64.sys not next to the exe,
or the driver was blocked by Windows because the signature is too old. Try
re-downloading the latest WinDivert release.

**`throttle-me: command not found` after install**
The PATH change only applies to *new* shells. Open a fresh cmd / PowerShell.

**Bypass enabled but speed didn't improve**
- Confirm with Wireshark that outbound TTL is actually 65 (not 64 or 128).
  If it's still your default (64 or 128), the helper isn't intercepting —
  check the service is actually running.
- Some browsers (Firefox, Chrome with DoH on) bypass system DNS entirely.
  Disable DoH in the browser to force traffic through the DNAT rule.
- Carriers also fingerprint via SNI and TLS handshakes. TTL+DNS catches
  most heuristics but not all.

**SmartScreen blocks the helper exe on first run**
Expected — the binary isn't code-signed. Click "More info → Run anyway".
If you want to avoid this, you can sign it yourself with a personal cert.

---

## Architecture, in one diagram

```
┌──────────────────────────────────────────┐
│ throttle-me.ps1 (user space, unelevated) │
└────────────────┬─────────────────────────┘
                 │ Start-Service / Stop-Service / registry writes
                 ▼
┌──────────────────────────────────────────┐
│ ThrottleMeHelper service (LocalSystem)   │
│   - Go binary                            │
│   - opens 2 WinDivert handles            │
│   - sets adapter DNS via netsh           │
└────────────────┬─────────────────────────┘
                 │ WinDivert API
                 ▼
┌──────────────────────────────────────────┐
│ WinDivert64.sys (signed kernel driver)   │
│   - intercepts at network layer          │
└────────────────┬─────────────────────────┘
                 │
                 ▼
       Windows TCP/IP stack
```

The CLI never touches the network stack directly — it just controls the
service, which is the only thing that talks to WinDivert.
