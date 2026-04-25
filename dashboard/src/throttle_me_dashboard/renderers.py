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
    return Group(status, "\n", top, "\n", net, "\n", daemon, "\n", card("WARNINGS", warn_text, "yellow" if warnings else "green"))


def render_control(snapshot: Snapshot, command_output: str) -> Group:
    shortcuts = Text()
    shortcuts.append("e", style="bold green")
    shortcuts.append(" enable  ")
    shortcuts.append("d", style="bold red")
    shortcuts.append(" disable  ")
    shortcuts.append("s", style="bold cyan")
    shortcuts.append(" daemon start  ")
    shortcuts.append("x", style="bold yellow")
    shortcuts.append(" daemon stop  ")
    shortcuts.append("t", style="bold magenta")
    shortcuts.append(" speed test\n\n")
    shortcuts.append("Actions use the existing throttle-me CLI and stream the last command result here.", style="dim")
    output = command_output or "No command run yet."
    return Group(
        card("COMMANDS", shortcuts, "green"),
        "\n",
        card("LAST COMMAND OUTPUT", Text(output[-4000:], style="white"), "cyan"),
        "\n",
        card("CURRENT STATE", kv_table([("Overall", snapshot.overall, STATUS_STYLE.get(snapshot.overall)), ("Sudo", "ready" if snapshot.sudo_ready else "not cached", "green" if snapshot.sudo_ready else "yellow")]), "cyan"),
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
    note = Text(f"Config source: {snapshot.config_path}\nPress ctrl+s to save current dashboard config defaults.", style="dim")
    return Group(card("SETTINGS", kv_table(rows), "cyan"), "\n", card("SAVE POLICY", note, "yellow"))


def render_logs(snapshot: Snapshot) -> Group:
    app = "\n".join(snapshot.app_log_tail) or "No app log entries found."
    daemon = "\n".join(snapshot.daemon_log_tail) or "No daemon journal entries found."
    return Group(card("APP LOG", Text(app[-3000:], style="white"), "cyan"), "\n", card("DAEMON JOURNAL", Text(daemon[-3000:], style="white"), "magenta"))
