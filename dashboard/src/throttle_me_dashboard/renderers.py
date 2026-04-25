from __future__ import annotations

from datetime import datetime

from rich import box
from rich.console import Group
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from .collectors import Snapshot


STATUS_STYLE = {
    "ACTIVE": "bold green",
    "PARTIAL": "bold yellow",
    "INACTIVE": "bold red",
    "UNKNOWN": "bold magenta",
    "active": "green",
    "inactive": "red",
    "unknown": "magenta",
    "ok": "green",
    "warn": "yellow",
    "critical": "red",
}


def human_bytes(value: float) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    amount = float(value)
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.1f} {unit}"
        amount /= 1024
    return f"{amount:.1f} TB"


def spark(value: float) -> str:
    bars = "▁▂▃▄▅▆▇█"
    index = min(int(value / 2048), len(bars) - 1)
    return bars[index] * 24


def card(title: str, body, border_style: str = "cyan") -> Panel:
    return Panel(body, title=title, border_style=border_style, box=box.ROUNDED, padding=(1, 2))


def kv_table(rows: list[tuple[str, str, str | None]]) -> Table:
    table = Table.grid(expand=True)
    table.add_column(ratio=1, style="dim")
    table.add_column(ratio=2)
    for key, value, style in rows:
        table.add_row(key, Text(str(value), style=style or "white"))
    return table


def next_action(snapshot: Snapshot) -> tuple[str, str]:
    critical = [item for item in snapshot.diagnostics if item.state == "critical"]
    warnings = [item for item in snapshot.diagnostics if item.state == "warn"]
    if critical:
        return ("Fix diagnostics", f"{critical[0].name}: {critical[0].detail}")
    if snapshot.overall == "PARTIAL":
        return ("Inspect partial state", "Open Diagnostics before toggling; one layer is active without the full path.")
    if snapshot.overall == "UNKNOWN":
        return ("Unlock visibility", "sudo is not cached, so firewall status is unknown. Use a confirmed action or run sudo -v.")
    if snapshot.overall == "ACTIVE":
        if warnings:
            return ("Monitor and verify", f"Bypass is active. Watch {warnings[0].name.lower()} when you have a minute.")
        return ("Stay on monitor", "Bypass looks active. Watch traffic and session counters.")
    if warnings:
        return ("Review warnings", f"Inactive with warning: {warnings[0].name}. Diagnostics has the details.")
    return ("Enable when ready", "Press e or click Enable after connecting to the hotspot.")


def readiness_score(snapshot: Snapshot) -> tuple[int, str]:
    score = 100
    if snapshot.overall == "ACTIVE":
        score -= 0
    elif snapshot.overall == "PARTIAL":
        score -= 35
    elif snapshot.overall == "UNKNOWN":
        score -= 45
    else:
        score -= 20

    for item in snapshot.diagnostics:
        if item.state == "critical":
            score -= 18
        elif item.state == "warn":
            score -= 7

    score = max(0, min(score, 100))
    if score >= 85:
        return score, "ready"
    if score >= 60:
        return score, "watch"
    if score >= 35:
        return score, "risky"
    return score, "blocked"


def recommended_profile(snapshot: Snapshot) -> tuple[str, str]:
    ssid = snapshot.ssid.lower()
    if "iphone" in ssid or "ipad" in ssid:
        return ("iPhone", "TTL/HL 65 with Cloudflare DNS")
    if "android" in ssid or "galaxy" in ssid or "pixel" in ssid:
        return ("Android", "TTL/HL 64 with Cloudflare DNS")
    if snapshot.overall == "PARTIAL":
        return ("Repair", "Keep current profile, inspect the partial firewall layer first")
    return ("Standard", "TTL/HL 65 with Cloudflare DNS")


def meter(value: int) -> str:
    filled = max(0, min(value // 5, 20))
    return "█" * filled + "░" * (20 - filled)


def clip(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return f"{value[: max(limit - 1, 0)]}…"


def doctor_report(snapshot: Snapshot) -> str:
    score, label = readiness_score(snapshot)
    lines = [
        f"Readiness: {score}/100 ({label})",
        f"State: {snapshot.overall}",
        f"Network: {snapshot.interface} / {snapshot.ssid}",
        f"DNS: {snapshot.dns_config}; lock={snapshot.dns_lock}; transport={snapshot.dns_transport}",
        "",
        "Priority findings:",
    ]
    findings = [item for item in snapshot.diagnostics if item.state != "ok"]
    if findings:
        lines.extend(f"- {item.state.upper()} {item.name}: {item.detail}" for item in findings[:10])
    else:
        lines.append("- OK no diagnostic warnings")
    return "\n".join(lines)


def render_status_strip(snapshot: Snapshot):
    action, detail = next_action(snapshot)
    line = Text()
    line.append(f"STATE {snapshot.overall}", style=STATUS_STYLE.get(snapshot.overall, "white"))
    line.append("  |  ", style="dim")
    line.append(f"SSID {clip(snapshot.ssid, 18)}", style="white")
    line.append("  |  ", style="dim")
    line.append(f"SUDO {'READY' if snapshot.sudo_ready else 'LOCKED'}", style="green" if snapshot.sudo_ready else "yellow")
    line.append("  |  ", style="dim")
    line.append(f"{action}: {clip(detail, 74)}", style="cyan")
    return Panel(line, border_style=STATUS_STYLE.get(snapshot.overall, "cyan").split()[-1], box=box.HEAVY, padding=(0, 1))


def render_inspector(snapshot: Snapshot, command_output: str, command_history: list[str] | None = None):
    action, detail = next_action(snapshot)
    score, label = readiness_score(snapshot)
    profile, profile_detail = recommended_profile(snapshot)
    score_style = "green" if score >= 85 else "yellow" if score >= 60 else "red"
    critical = sum(1 for item in snapshot.diagnostics if item.state == "critical")
    warns = sum(1 for item in snapshot.diagnostics if item.state == "warn")
    installed = sum(1 for present in snapshot.dependencies.values() if present)
    total_deps = len(snapshot.dependencies)

    body = Text()
    body.append(f"{score:03d}/100 {label.upper()}\n", style=f"bold {score_style}")
    body.append(f"{meter(score)}\n\n", style=score_style)
    body.append("Next move\n", style="bold cyan")
    body.append(f"{action}\n", style="white")
    body.append(f"{detail}\n\n", style="dim")
    body.append(f"Signals  critical={critical}  warn={warns}  deps={installed}/{total_deps}\n", style="white")
    body.append(f"Profile  {profile}: {profile_detail}\n", style="white")
    body.append(f"Rules    ttl={snapshot.ipv4_ttl} dns={snapshot.ipv4_dns} v6={snapshot.ipv6_hl}/{snapshot.ipv6_dns}\n", style="white")
    body.append(f"Traffic  rx={human_bytes(snapshot.rx_rate)}/s tx={human_bytes(snapshot.tx_rate)}/s\n", style="white")
    history = command_history or []
    if history:
        body.append("\nHistory\n", style="bold cyan")
        for entry in history[:3]:
            body.append(f"{clip(entry, 34)}\n", style="dim")
    elif command_output.strip():
        body.append("\nLast command captured in Control view.\n", style="dim")
    return card("SMART INSPECTOR", body, score_style)


def render_overview(snapshot: Snapshot) -> Group:
    status = Text(snapshot.overall, style=STATUS_STYLE.get(snapshot.overall, "white"))
    status.append(f"  {datetime.fromtimestamp(snapshot.timestamp).strftime('%H:%M:%S')}", style="dim")
    top = card(
        "BYPASS STATE",
        kv_table(
            [
                ("Overall", snapshot.overall, STATUS_STYLE.get(snapshot.overall)),
                ("IPv4 TTL", snapshot.ipv4_ttl, STATUS_STYLE.get(snapshot.ipv4_ttl)),
                ("IPv4 DNS", snapshot.ipv4_dns, STATUS_STYLE.get(snapshot.ipv4_dns)),
                ("IPv6 HL", snapshot.ipv6_hl, STATUS_STYLE.get(snapshot.ipv6_hl)),
                ("IPv6 DNS", snapshot.ipv6_dns, STATUS_STYLE.get(snapshot.ipv6_dns)),
                ("DNS config", snapshot.dns_config, None),
                ("DNS lock", snapshot.dns_lock, "green" if snapshot.dns_lock == "immutable" else "yellow"),
            ]
        ),
        STATUS_STYLE.get(snapshot.overall, "cyan").split()[-1],
    )
    net = card(
        "NETWORK",
        kv_table(
            [
                ("Interface", snapshot.interface, None),
                ("SSID", snapshot.ssid, None),
                ("Gateway", snapshot.gateway, None),
                ("RX", f"{human_bytes(snapshot.rx_rate)}/s {spark(snapshot.rx_rate)}", "green"),
                ("TX", f"{human_bytes(snapshot.tx_rate)}/s {spark(snapshot.tx_rate)}", "cyan"),
                ("Total RX", human_bytes(snapshot.rx_total), None),
                ("Total TX", human_bytes(snapshot.tx_total), None),
            ]
        ),
    )
    daemon = card(
        "DAEMON",
        kv_table(
            [
                ("State", snapshot.daemon_state, "green" if snapshot.daemon_state == "active" else "yellow"),
                ("Autostart", snapshot.daemon_autostart, None),
                ("PID", snapshot.daemon_pid or "none", None),
                ("Last SSID", snapshot.daemon_last_ssid, None),
                ("Bypass flag", snapshot.daemon_bypass_active, None),
            ]
        ),
    )
    warnings = [item for item in snapshot.diagnostics if item.state != "ok"][:8]
    warn_text = Text()
    if warnings:
        for item in warnings:
            warn_text.append(f"{item.name}: ", style=STATUS_STYLE.get(item.state, "yellow"))
            warn_text.append(f"{item.detail}\n", style="white")
    else:
        warn_text.append("No warnings detected in read-only diagnostics.", style="green")
    action, detail = next_action(snapshot)
    brief = Text()
    brief.append(f"{action}\n", style="bold cyan")
    brief.append(detail, style="white")
    return Group(status, "\n", card("OPERATOR BRIEF", brief, "cyan"), "\n", top, "\n", net, "\n", daemon, "\n", card("WARNINGS", warn_text, "yellow" if warnings else "green"))


def render_control(snapshot: Snapshot, command_output: str) -> Group:
    shortcuts = Text()
    shortcuts.append("e", style="bold green")
    shortcuts.append(" enable  ")
    shortcuts.append("d", style="bold red")
    shortcuts.append(" disable  ")
    shortcuts.append("u", style="bold white")
    shortcuts.append(" cli status  ")
    shortcuts.append("s", style="bold cyan")
    shortcuts.append(" daemon start  ")
    shortcuts.append("x", style="bold yellow")
    shortcuts.append(" daemon stop  ")
    shortcuts.append("t", style="bold magenta")
    shortcuts.append(" speed test  ")
    shortcuts.append("a", style="bold blue")
    shortcuts.append(" toggle auto\n\n")
    shortcuts.append("Click the left rail buttons or use hotkeys. Confirmed actions call the existing throttle-me CLI and report here.", style="dim")
    output = command_output or "No command run yet."
    runbook = Table.grid(expand=True)
    runbook.add_column(ratio=1, style="dim")
    runbook.add_column(ratio=2)
    runbook.add_row("1 Detect", f"{snapshot.interface} / {snapshot.ssid}")
    runbook.add_row("2 Prepare", "sudo ready" if snapshot.sudo_ready else "sudo locked")
    runbook.add_row("3 Apply", snapshot.overall)
    runbook.add_row("4 Verify", f"TTL {snapshot.ipv4_ttl}, DNS {snapshot.ipv4_dns}, lock {snapshot.dns_lock}")
    runbook.add_row("5 Monitor", f"RX {human_bytes(snapshot.rx_rate)}/s, TX {human_bytes(snapshot.tx_rate)}/s")
    return Group(
        card("COMMANDS", shortcuts, "green"),
        "\n",
        card("RUNBOOK", runbook, "magenta"),
        "\n",
        card("LAST COMMAND OUTPUT", Text(output[-4000:], style="white"), "cyan"),
        "\n",
        card(
            "CURRENT STATE",
            kv_table(
                [
                    ("Overall", snapshot.overall, STATUS_STYLE.get(snapshot.overall)),
                    ("Sudo", "ready" if snapshot.sudo_ready else "not cached", "green" if snapshot.sudo_ready else "yellow"),
                    ("Auto-enable", snapshot.config.get("AUTO_ENABLE", "false"), "green" if snapshot.config.get("AUTO_ENABLE") == "true" else "yellow"),
                ]
            ),
            "cyan",
        ),
    )


def render_diagnostics(snapshot: Snapshot) -> Group:
    table = Table(title="READ-ONLY DIAGNOSTICS", box=box.SIMPLE_HEAVY, expand=True)
    table.add_column("Check", ratio=1)
    table.add_column("State", ratio=1)
    table.add_column("Detail", ratio=3)
    for item in snapshot.diagnostics:
        table.add_row(item.name, Text(item.state.upper(), style=STATUS_STYLE.get(item.state, "white")), item.detail)
    return Group(table)


def render_monitor(snapshot: Snapshot) -> Group:
    body = kv_table(
        [
            ("Interface", snapshot.interface, None),
            ("RX rate", f"{human_bytes(snapshot.rx_rate)}/s", "green"),
            ("RX graph", spark(snapshot.rx_rate), "green"),
            ("TX rate", f"{human_bytes(snapshot.tx_rate)}/s", "cyan"),
            ("TX graph", spark(snapshot.tx_rate), "cyan"),
            ("IPv4 packets", snapshot.ipv4_packets, None),
            ("IPv6 packets", snapshot.ipv6_packets, None),
        ]
    )
    tools = ", ".join(name for name in ["bmon", "iftop", "nethogs"] if snapshot.dependencies.get(name)) or "none installed"
    return Group(card("LIVE TRAFFIC", body, "green"), "\n", card("EXTERNAL MONITORS", Text(f"Available: {tools}\nUse the existing -m CLI path for bmon today.", style="white"), "cyan"))


def render_sessions(snapshot: Snapshot) -> Group:
    session_rows = [(key, value, None) for key, value in snapshot.current_session.items()] or [("Current", "No active session", "yellow")]
    table = Table(title="RECENT SESSIONS", box=box.SIMPLE, expand=True)
    table.add_column("#", width=4)
    table.add_column("Record")
    if snapshot.recent_sessions:
        for index, record in enumerate(snapshot.recent_sessions, 1):
            table.add_row(str(index), record)
    else:
        table.add_row("-", "No session history available")
    return Group(card("CURRENT SESSION", kv_table(session_rows), "cyan"), "\n", table)


def render_settings(snapshot: Snapshot) -> Group:
    rows = []
    for key in ["TTL_VALUE", "HL_VALUE", "DNS_SERVER", "AUTO_ENABLE", "INTERFACE_OVERRIDE", "MAX_SESSIONS", "MAX_AGE_DAYS", "BYPASS_SCRIPT", "DISABLE_SCRIPT"]:
        rows.append((key, snapshot.config.get(key, ""), None))
    note = Text(f"Config source: {snapshot.config_path}\nPress a to toggle AUTO_ENABLE. Press ctrl+s to save current dashboard config defaults.", style="dim")
    return Group(card("SETTINGS", kv_table(rows), "cyan"), "\n", card("SAVE POLICY", note, "yellow"))


def render_logs(snapshot: Snapshot) -> Group:
    app = "\n".join(snapshot.app_log_tail) or "No app log entries found."
    daemon = "\n".join(snapshot.daemon_log_tail) or "No daemon journal entries found."
    return Group(card("APP LOG", Text(app[-3000:], style="white"), "cyan"), "\n", card("DAEMON JOURNAL", Text(daemon[-3000:], style="white"), "magenta"))
