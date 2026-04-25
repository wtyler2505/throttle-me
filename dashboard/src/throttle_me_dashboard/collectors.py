from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

import psutil


HOME = Path.home()
DEFAULT_CONFIG = {
    "TTL_VALUE": "65",
    "HL_VALUE": "65",
    "DNS_SERVER": "1.1.1.1",
    "LOG_LEVEL": "3",
    "LOG_FILE": "/tmp/throttle-me.log",
    "CONFIRM_ENABLE": "true",
    "CONFIRM_DISABLE": "true",
    "BYPASS_SCRIPT": str(HOME / ".local/bin/bypass-tethering"),
    "DISABLE_SCRIPT": str(HOME / ".local/bin/disable-bypass-tethering"),
    "AUTO_ENABLE": "false",
    "MAX_SESSIONS": "100",
    "MAX_AGE_DAYS": "30",
    "INTERFACE_OVERRIDE": "",
    "POLL_INTERVAL": "5",
    "HOTSPOT_PATTERNS": "iPhone* AndroidAP* *Galaxy*",
    "SPEED_TEST_TIMEOUT": "30",
    "NOTIFICATION_URGENCY": "normal",
}

CONFIG_PATHS = [
    HOME / ".config/throttle-me/config",
    HOME / ".throttle-me.conf",
    Path("/etc/throttle-me.conf"),
]
STATS_DIR = HOME / ".config/throttle-me/stats"
SESSIONS_FILE = STATS_DIR / "sessions.log"
CURRENT_SESSION_FILE = STATS_DIR / "current_session.tmp"
DAEMON_STATE_FILE = HOME / ".config/throttle-me/daemon.state"
DAEMON_LOCK_FILE = HOME / ".cache/throttle-me/daemon.lock"
DAEMON_SERVICE = "throttle-me-daemon.service"


@dataclass
class CommandResult:
    args: list[str]
    exit_code: int
    stdout: str
    stderr: str
    timed_out: bool = False

    @property
    def ok(self) -> bool:
        return self.exit_code == 0 and not self.timed_out


@dataclass
class CheckItem:
    name: str
    state: str
    detail: str


@dataclass
class Snapshot:
    timestamp: float
    config: dict[str, str]
    config_path: str
    overall: str
    bypass_script: str
    disable_script: str
    bypass_script_exists: bool
    disable_script_exists: bool
    script_ttl: str
    script_dns: str
    sudo_ready: bool
    ipv4_ttl: str
    ipv4_dns: str
    ipv6_hl: str
    ipv6_dns: str
    dns_config: str
    dns_lock: str
    resolv_target: str
    dns_transport: str
    ipv4_packets: str
    ipv6_packets: str
    interface: str
    ssid: str
    gateway: str
    rx_rate: float
    tx_rate: float
    rx_total: int
    tx_total: int
    daemon_state: str
    daemon_autostart: str
    daemon_pid: str
    daemon_last_ssid: str
    daemon_bypass_active: str
    current_session: dict[str, str]
    recent_sessions: list[str]
    app_log_tail: list[str]
    daemon_log_tail: list[str]
    dependencies: dict[str, bool]
    diagnostics: list[CheckItem] = field(default_factory=list)


_LAST_IO: tuple[float, dict[str, tuple[int, int]]] | None = None


def run(args: list[str], timeout: float = 2.5) -> CommandResult:
    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return CommandResult(args, completed.returncode, completed.stdout.strip(), completed.stderr.strip())
    except subprocess.TimeoutExpired as exc:
        return CommandResult(args, 124, exc.stdout or "", exc.stderr or "", timed_out=True)
    except FileNotFoundError as exc:
        return CommandResult(args, 127, "", str(exc))
    except Exception as exc:  # defensive collector: dashboards should not crash on host oddities
        return CommandResult(args, 1, "", str(exc))


def load_config() -> tuple[dict[str, str], str]:
    config = dict(DEFAULT_CONFIG)
    config_path = ""
    for path in CONFIG_PATHS:
        if path.exists():
            config_path = str(path)
            for raw in path.read_text(errors="ignore").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
                    continue
                try:
                    parsed = shlex.split(value, posix=True)
                    value = parsed[0] if parsed else ""
                except ValueError:
                    value = value.strip().strip("\"'")
                config[key] = os.path.expanduser(os.path.expandvars(value))
            break
    return config, config_path


def repo_root() -> Path:
    env_root = os.environ.get("THROTTLE_ME_ROOT")
    if env_root:
        return Path(env_root)
    return Path(__file__).resolve().parents[3]


def throttle_cmd() -> list[str]:
    root = repo_root()
    script = root / "throttle-me"
    if script.exists():
        return [str(script)]
    installed = HOME / ".local/bin/throttle-me"
    return [str(installed)] if installed.exists() else ["throttle-me"]


def script_facts(path: str) -> tuple[str, str]:
    file_path = Path(path)
    if not file_path.exists():
        return "unknown", "unknown"
    text = file_path.read_text(errors="ignore")
    ttl_match = re.search(r"--ttl-set\s+([0-9]+)", text)
    if not ttl_match:
        ttl_match = re.search(r"TTL_VALUE=.*?([0-9]+)", text)
    dns_values = re.findall(r"(?:nameserver\s+|--to-destination\s+)([0-9]+(?:\.[0-9]+){3})", text)
    dns_values.extend(re.findall(r"DNS_SERVER=.*?([0-9]+(?:\.[0-9]+){3})", text))
    ttl = ttl_match.group(1) if ttl_match else "unknown"
    dns = ", ".join(dict.fromkeys(dns_values)) if dns_values else "unknown"
    return ttl, dns


def sudo_ready() -> bool:
    return run(["sudo", "-n", "true"], timeout=1.0).ok


def sudo_table(tool: str, table: str, chain: str) -> CommandResult:
    return run(["sudo", "-n", tool, "-t", table, "-L", chain, "-n", "-v"], timeout=2.0)


def contains_rule(output: str, pattern: str) -> bool:
    return re.search(pattern, output, re.IGNORECASE) is not None


def packet_count(output: str, pattern: str) -> str:
    for line in output.splitlines():
        if re.search(pattern, line, re.IGNORECASE):
            parts = line.split()
            if len(parts) >= 2 and parts[0].isdigit():
                return f"{parts[0]} packets, {parts[1]} bytes"
    return "0 packets, 0 bytes"


def dns_config(config: dict[str, str]) -> tuple[str, str, str]:
    resolv = Path("/etc/resolv.conf")
    target = str(resolv)
    if resolv.is_symlink():
        try:
            target = f"{resolv} -> {resolv.resolve()}"
        except OSError:
            target = f"{resolv} -> broken symlink"
    try:
        text = resolv.read_text(errors="ignore")
    except OSError:
        text = ""
    server = config["DNS_SERVER"]
    state = server if server in text else "system resolver"
    attr = run(["lsattr", "-L", str(resolv)], timeout=1.0)
    if attr.ok:
        first = attr.stdout.split(maxsplit=1)[0] if attr.stdout else ""
        lock = "immutable" if "i" in first else "not locked"
    else:
        lock = "unknown"
    return state, lock, target


def network_info(config: dict[str, str]) -> tuple[str, str, str, float, float, int, int]:
    iface = config.get("INTERFACE_OVERRIDE") or ""
    if not iface:
        ip_link = run(["ip", "-brief", "link", "show"], timeout=1.0)
        for line in ip_link.stdout.splitlines():
            cols = line.split()
            if cols and cols[0].startswith("wl") and "UP" in cols:
                iface = cols[0]
                break
    if not iface:
        iface = "unknown"

    ssid = "not connected"
    if iface != "unknown":
        iw = run(["iwgetid", iface, "-r"], timeout=1.0)
        if iw.ok and iw.stdout:
            ssid = iw.stdout
        else:
            nmcli = run(["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"], timeout=1.0)
            for line in nmcli.stdout.splitlines():
                if line.startswith("yes:"):
                    ssid = line.split(":", 1)[1] or "not connected"
                    break

    gateway = "unknown"
    route = run(["ip", "route"], timeout=1.0)
    for line in route.stdout.splitlines():
        if line.startswith("default"):
            parts = line.split()
            if "via" in parts:
                gateway = parts[parts.index("via") + 1]
            break

    rx_rate, tx_rate, rx_total, tx_total = interface_rates(iface)
    return iface, ssid, gateway, rx_rate, tx_rate, rx_total, tx_total


def interface_rates(iface: str) -> tuple[float, float, int, int]:
    global _LAST_IO
    counters = psutil.net_io_counters(pernic=True)
    now = time.time()
    current = {name: (data.bytes_recv, data.bytes_sent) for name, data in counters.items()}
    data = current.get(iface)
    if data is None and counters:
        name, stats = next(iter(counters.items()))
        data = (stats.bytes_recv, stats.bytes_sent)
        iface = name
    if data is None:
        return 0.0, 0.0, 0, 0

    rx_rate = tx_rate = 0.0
    if _LAST_IO is not None:
        last_time, last_values = _LAST_IO
        elapsed = max(now - last_time, 0.1)
        previous = last_values.get(iface)
        if previous:
            rx_rate = max(data[0] - previous[0], 0) / elapsed
            tx_rate = max(data[1] - previous[1], 0) / elapsed
    _LAST_IO = (now, current)
    return rx_rate, tx_rate, data[0], data[1]


def daemon_info() -> tuple[str, str, str, str, str]:
    active = run(["systemctl", "--user", "is-active", DAEMON_SERVICE], timeout=1.0)
    enabled = run(["systemctl", "--user", "is-enabled", DAEMON_SERVICE], timeout=1.0)
    pid = DAEMON_LOCK_FILE.read_text(errors="ignore").strip() if DAEMON_LOCK_FILE.exists() else ""
    state = parse_state_file(DAEMON_STATE_FILE)
    return (
        active.stdout or "unknown",
        enabled.stdout or "disabled",
        pid,
        state.get("LAST_SSID", "none"),
        state.get("BYPASS_ACTIVE", "unknown"),
    )


def parse_state_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(errors="ignore").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def tail(path: Path, lines: int = 8) -> list[str]:
    if not path.exists():
        return []
    data = path.read_text(errors="ignore").splitlines()
    return data[-lines:]


def daemon_logs() -> list[str]:
    result = run(["journalctl", "--user", "-u", DAEMON_SERVICE, "-n", "8", "--no-pager"], timeout=2.0)
    if not result.ok and not result.stdout:
        return []
    return result.stdout.splitlines()[-8:]


def dependencies() -> dict[str, bool]:
    names = ["python3", "uv", "iptables", "ip6tables", "sudo", "curl", "bc", "bmon", "iftop", "nethogs", "iwgetid", "nmcli", "systemctl", "lsattr"]
    return {name: shutil.which(name) is not None for name in names}


def compute_overall(ipv4_ttl: str, ipv4_dns: str, ipv6_hl: str, ipv6_dns: str) -> str:
    active = [ipv4_ttl == "active", ipv4_dns == "active", ipv6_hl == "active", ipv6_dns == "active"]
    unknown = [ipv4_ttl == "unknown", ipv4_dns == "unknown", ipv6_hl == "unknown", ipv6_dns == "unknown"]
    if active[0] and active[1] and (active[2] or ipv6_hl in {"inactive", "unknown"}) and (active[3] or ipv6_dns in {"inactive", "unknown"}):
        return "ACTIVE"
    if any(active):
        return "PARTIAL"
    if all(unknown):
        return "UNKNOWN"
    return "INACTIVE"


def diagnostics(snapshot: Snapshot) -> list[CheckItem]:
    items = [
        CheckItem("Bypass script", "ok" if snapshot.bypass_script_exists else "critical", snapshot.bypass_script),
        CheckItem("Disable script", "ok" if snapshot.disable_script_exists else "critical", snapshot.disable_script),
        CheckItem("Passwordless sudo", "ok" if snapshot.sudo_ready else "warn", "ready" if snapshot.sudo_ready else "sudo -n is not available"),
        CheckItem("DNS transport", "warn", snapshot.dns_transport),
        CheckItem("DNS lock", "ok" if snapshot.dns_lock == "immutable" else "warn", snapshot.dns_lock),
        CheckItem("Daemon", "ok" if snapshot.daemon_state == "active" else "warn", f"{snapshot.daemon_state}, autostart {snapshot.daemon_autostart}"),
    ]
    if snapshot.script_ttl not in {"unknown", snapshot.config["TTL_VALUE"]}:
        items.append(CheckItem("TTL config mismatch", "warn", f"config {snapshot.config['TTL_VALUE']} vs script {snapshot.script_ttl}"))
    if snapshot.script_dns != "unknown" and snapshot.config["DNS_SERVER"] not in snapshot.script_dns:
        items.append(CheckItem("DNS config mismatch", "warn", f"config {snapshot.config['DNS_SERVER']} vs script {snapshot.script_dns}"))
    for name, present in snapshot.dependencies.items():
        if name in {"bmon", "iftop", "nethogs"}:
            state = "ok" if present else "warn"
        else:
            state = "ok" if present else "critical"
        items.append(CheckItem(f"dependency:{name}", state, "installed" if present else "missing"))
    return items


def collect_snapshot() -> Snapshot:
    config, config_path = load_config()
    bypass_script = os.path.expandvars(config["BYPASS_SCRIPT"])
    disable_script = os.path.expandvars(config["DISABLE_SCRIPT"])
    script_ttl, script_dns = script_facts(bypass_script)
    sudo_ok = sudo_ready()

    ttl_out = sudo_table("iptables", "mangle", "POSTROUTING") if sudo_ok else CommandResult([], 1, "", "sudo unavailable")
    nat_out = sudo_table("iptables", "nat", "OUTPUT") if sudo_ok else CommandResult([], 1, "", "sudo unavailable")
    hl_out = sudo_table("ip6tables", "mangle", "POSTROUTING") if sudo_ok else CommandResult([], 1, "", "sudo unavailable")
    v6nat_out = sudo_table("ip6tables", "nat", "OUTPUT") if sudo_ok else CommandResult([], 1, "", "sudo unavailable")

    ttl_pattern = rf"TTL set to {re.escape(config['TTL_VALUE'])}"
    hl_value = config.get("HL_VALUE") or config["TTL_VALUE"]
    hl_pattern = rf"HL set to {re.escape(hl_value)}"
    dns_pattern = rf"DNAT.*{re.escape(config['DNS_SERVER'])}:53"
    ipv4_ttl = "active" if ttl_out.ok and contains_rule(ttl_out.stdout, ttl_pattern) else ("unknown" if not ttl_out.ok else "inactive")
    ipv4_dns = "active" if nat_out.ok and contains_rule(nat_out.stdout, dns_pattern) else ("unknown" if not nat_out.ok else "inactive")
    ipv6_hl = "active" if hl_out.ok and contains_rule(hl_out.stdout, hl_pattern) else ("unknown" if not hl_out.ok else "inactive")
    ipv6_dns = "active" if v6nat_out.ok and contains_rule(v6nat_out.stdout, dns_pattern) else ("unknown" if not v6nat_out.ok else "inactive")

    dns_state, dns_lock, resolv_target = dns_config(config)
    iface, ssid, gateway, rx_rate, tx_rate, rx_total, tx_total = network_info(config)
    daemon_state, daemon_autostart, daemon_pid, last_ssid, daemon_bypass = daemon_info()
    current_session = parse_state_file(CURRENT_SESSION_FILE)
    recent_sessions = tail(SESSIONS_FILE, 8)
    deps = dependencies()

    snapshot = Snapshot(
        timestamp=time.time(),
        config=config,
        config_path=config_path or "defaults",
        overall=compute_overall(ipv4_ttl, ipv4_dns, ipv6_hl, ipv6_dns),
        bypass_script=bypass_script,
        disable_script=disable_script,
        bypass_script_exists=Path(bypass_script).exists(),
        disable_script_exists=Path(disable_script).exists(),
        script_ttl=script_ttl,
        script_dns=script_dns,
        sudo_ready=sudo_ok,
        ipv4_ttl=ipv4_ttl,
        ipv4_dns=ipv4_dns,
        ipv6_hl=ipv6_hl,
        ipv6_dns=ipv6_dns,
        dns_config=dns_state,
        dns_lock=dns_lock,
        resolv_target=resolv_target,
        dns_transport="public DNS redirection on port 53; not DoH/DoT",
        ipv4_packets=packet_count(ttl_out.stdout, ttl_pattern) if ttl_out.ok else "unknown",
        ipv6_packets=packet_count(hl_out.stdout, hl_pattern) if hl_out.ok else "unknown",
        interface=iface,
        ssid=ssid,
        gateway=gateway,
        rx_rate=rx_rate,
        tx_rate=tx_rate,
        rx_total=rx_total,
        tx_total=tx_total,
        daemon_state=daemon_state,
        daemon_autostart=daemon_autostart,
        daemon_pid=daemon_pid,
        daemon_last_ssid=last_ssid,
        daemon_bypass_active=daemon_bypass,
        current_session=current_session,
        recent_sessions=recent_sessions,
        app_log_tail=tail(Path(config.get("LOG_FILE", "/tmp/throttle-me.log")), 8),
        daemon_log_tail=daemon_logs(),
        dependencies=deps,
    )
    snapshot.diagnostics = diagnostics(snapshot)
    return snapshot


def save_config(config: dict[str, str]) -> Path:
    target = CONFIG_PATHS[0]
    target.parent.mkdir(parents=True, exist_ok=True)
    keys = [
        "TTL_VALUE",
        "HL_VALUE",
        "DNS_SERVER",
        "LOG_LEVEL",
        "LOG_FILE",
        "CONFIRM_ENABLE",
        "CONFIRM_DISABLE",
        "BYPASS_SCRIPT",
        "DISABLE_SCRIPT",
        "AUTO_ENABLE",
        "MAX_SESSIONS",
        "MAX_AGE_DAYS",
        "INTERFACE_OVERRIDE",
        "POLL_INTERVAL",
        "HOTSPOT_PATTERNS",
        "SPEED_TEST_TIMEOUT",
        "NOTIFICATION_URGENCY",
    ]
    lines = ["# throttle-me configuration", "# Saved by throttle-me dashboard", ""]
    for key in keys:
        value = str(config.get(key, DEFAULT_CONFIG.get(key, "")))
        if re.match(r"^(true|false|[0-9]+)$", value):
            lines.append(f"{key}={value}")
        else:
            escaped = value.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'{key}="{escaped}"')
    temp = target.with_suffix(".tmp")
    temp.write_text("\n".join(lines) + "\n")
    temp.replace(target)
    return target
