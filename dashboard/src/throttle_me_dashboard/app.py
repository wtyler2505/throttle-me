from __future__ import annotations

import asyncio
import ipaddress
import subprocess
from collections.abc import Iterable
from datetime import datetime

from textual.app import App, ComposeResult, SystemCommand
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Footer, Header, Input, Label, Static, Switch

from .collectors import collect_snapshot, save_config, throttle_cmd
from .renderers import doctor_report, render_control, render_diagnostics, render_inspector, render_logs, render_monitor, render_overview, render_sessions, render_settings, render_status_strip


class ConfirmScreen(ModalScreen[bool]):
    BINDINGS = [
        ("escape", "cancel", "Cancel"),
        ("n", "cancel", "Cancel"),
        ("y", "confirm", "Confirm"),
        ("enter", "confirm", "Confirm"),
    ]

    def __init__(self, message: str) -> None:
        super().__init__()
        self.message = message

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-dialog"):
            yield Label(self.message, id="confirm-message")
            with Horizontal(id="confirm-actions"):
                yield Button("Confirm", variant="success", id="confirm", compact=True, flat=True)
                yield Button("Cancel", variant="default", id="cancel", compact=True, flat=True)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        event.stop()
        self.dismiss(event.button.id == "confirm")

    def action_cancel(self) -> None:
        self.dismiss(False)

    def action_confirm(self) -> None:
        self.dismiss(True)


class CommandCenterApp(App):
    CSS_PATH = "styles.tcss"
    TITLE = "throttle-me command center"
    SUB_TITLE = "operator console"
    COMMAND_PALETTE_BINDING = "p"

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("r", "refresh", "Refresh"),
        ("1", "view('overview')", "Overview"),
        ("2", "view('control')", "Control"),
        ("3", "view('diagnostics')", "Diagnostics"),
        ("4", "view('monitor')", "Monitor"),
        ("5", "view('sessions')", "Sessions"),
        ("6", "view('settings')", "Settings"),
        ("7", "view('logs')", "Logs"),
        ("e", "enable_bypass", "Enable"),
        ("d", "disable_bypass", "Disable"),
        ("s", "daemon_start", "Daemon start"),
        ("x", "daemon_stop", "Daemon stop"),
        ("t", "speed_test", "Speed"),
        ("u", "cli_status", "CLI status"),
        ("a", "toggle_auto_enable", "Auto"),
        ("?", "doctor", "Doctor"),
        (".", "repeat_last", "Repeat"),
        ("ctrl+p", "app.toggle_command_palette", "Palette"),
        ("ctrl+s", "save_settings", "Save"),
    ]

    NAV_ITEMS = [
        ("overview", "1  Overview"),
        ("control", "2  Control"),
        ("diagnostics", "3  Diagnostics"),
        ("monitor", "4  Monitor"),
        ("sessions", "5  Sessions"),
        ("settings", "6  Settings"),
        ("logs", "7  Logs"),
    ]

    PALETTE_COMMANDS = [
        ("view:overview", "View: Overview", "Open the operator summary."),
        ("view:control", "View: Control", "Open command output and runbook."),
        ("view:diagnostics", "View: Diagnostics", "Open read-only bypass diagnostics."),
        ("view:monitor", "View: Monitor", "Open traffic and interface telemetry."),
        ("view:sessions", "View: Sessions", "Open current and recent session data."),
        ("view:settings", "View: Settings", "Open saved configuration values."),
        ("view:logs", "View: Logs", "Open app and daemon log tails."),
        ("action:enable", "Bypass: Enable", "Confirm then enable TTL/DNS bypass."),
        ("action:disable", "Bypass: Disable", "Confirm then disable the bypass."),
        ("action:status", "CLI: Status", "Run throttle-me -s and show output."),
        ("action:speed", "CLI: Speed Test", "Run the existing speed-test path."),
        ("action:daemon-start", "Daemon: Start", "Confirm then start the user daemon."),
        ("action:daemon-stop", "Daemon: Stop", "Confirm then stop the user daemon."),
        ("action:doctor", "Doctor: Diagnose", "Refresh the smart diagnostic report."),
        ("action:refresh", "Dashboard: Refresh", "Refresh all read-only collectors."),
        ("action:save", "Config: Save Editor", "Validate and save right-panel config values."),
        ("action:auto", "Config: Toggle Auto", "Toggle AUTO_ENABLE and save it."),
        ("action:repeat", "Command: Repeat Last", "Repeat the last CLI command, with confirmation for state changes."),
        ("profile:iphone", "Profile: iPhone 65", "Save TTL/HL 65 with Cloudflare DNS."),
        ("profile:android", "Profile: Android 64", "Save TTL/HL 64 with Cloudflare DNS."),
        ("profile:stealth", "Profile: Stealth 128", "Save TTL/HL 128 with Google DNS."),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.current_view = "overview"
        self.snapshot = collect_snapshot()
        self.command_output = ""
        self.command_history: list[str] = []
        self.last_command: tuple[list[str], str] | None = None
        self.command_running = False
        self._syncing_settings = False

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="layout"):
            with Vertical(id="sidebar"):
                yield Static("THROTTLE-ME", id="brand")
                yield Static("COMMAND CENTER", id="subtitle")
                with Vertical(classes="nav"):
                    for view_name, label in self.NAV_ITEMS:
                        yield Button(label, id=f"nav-{view_name}", classes="nav-button", compact=True, flat=True)
                with Vertical(classes="actions"):
                    yield Static("ACTIONS", classes="section-label")
                    yield Button("Enable", id="action-enable", variant="success", compact=True, flat=True)
                    yield Button("Disable", id="action-disable", variant="error", compact=True, flat=True)
                    yield Button("CLI Status", id="action-status", compact=True, flat=True)
                    yield Button("Speed Test", id="action-speed", compact=True, flat=True)
                    yield Button("Daemon Start", id="action-daemon-start", compact=True, flat=True)
                    yield Button("Daemon Stop", id="action-daemon-stop", variant="warning", compact=True, flat=True)
                    yield Button("Toggle Auto", id="action-auto", compact=True, flat=True)
                    yield Button("Refresh", id="action-refresh", compact=True, flat=True)
                yield Static("p palette | . repeat | e/d bypass | ? doctor | ctrl+s save", classes="keys")
            with Vertical(id="main"):
                yield Static("", id="status-strip")
                yield Static("", id="view-title")
                yield Static("", id="content")
            with Vertical(id="rightbar"):
                yield Static("", id="inspector")
                yield Static("LIVE CONFIG", classes="section-label")
                yield Label("TTL", classes="field-label")
                yield Input(id="setting-ttl", compact=True)
                yield Label("IPv6 HL", classes="field-label")
                yield Input(id="setting-hl", compact=True)
                yield Label("DNS", classes="field-label")
                yield Input(id="setting-dns", compact=True)
                yield Label("Interface", classes="field-label")
                yield Input(id="setting-iface", compact=True)
                with Horizontal(classes="switch-row"):
                    yield Label("AUTO", classes="field-label")
                    yield Switch(id="setting-auto")
                yield Button("Save Config", id="action-save-config", variant="success", compact=True, flat=True)
                yield Button("Doctor", id="action-doctor", compact=True, flat=True)
                yield Static("PROFILES", classes="section-label")
                yield Button("iPhone 65", id="profile-iphone", compact=True, flat=True)
                yield Button("Android 64", id="profile-android", compact=True, flat=True)
                yield Button("Stealth 128", id="profile-stealth", compact=True, flat=True)
        yield Footer()

    def on_mount(self) -> None:
        self.set_interval(2.0, self.refresh_snapshot)
        self.render_current()

    def refresh_snapshot(self) -> None:
        self.snapshot = collect_snapshot()
        self.render_current()

    def render_current(self) -> None:
        self.apply_responsive_layout()
        status_strip = self.query_one("#status-strip", Static)
        inspector = self.query_one("#inspector", Static)
        title = self.query_one("#view-title", Static)
        content = self.query_one("#content", Static)
        status_strip.update(render_status_strip(self.snapshot))
        inspector.update(render_inspector(self.snapshot, self.command_output, self.command_history))
        title.update(f"{self.current_view.upper()} :: {self.snapshot.overall}")
        renderable = {
            "overview": render_overview(self.snapshot),
            "control": render_control(self.snapshot, self.command_output),
            "diagnostics": render_diagnostics(self.snapshot),
            "monitor": render_monitor(self.snapshot),
            "sessions": render_sessions(self.snapshot),
            "settings": render_settings(self.snapshot),
            "logs": render_logs(self.snapshot),
        }.get(self.current_view, render_overview(self.snapshot))
        content.update(renderable)
        self.update_nav_buttons()
        self.sync_settings_inputs()

    def update_nav_buttons(self) -> None:
        for view_name, _label in self.NAV_ITEMS:
            button = self.query_one(f"#nav-{view_name}", Button)
            button.set_class(view_name == self.current_view, "active")

    def apply_responsive_layout(self) -> None:
        width = self.size.width
        self.query_one("#rightbar", Vertical).display = width >= 140
        self.query_one("#sidebar", Vertical).display = width >= 96

    def on_button_pressed(self, event: Button.Pressed) -> None:
        button_id = event.button.id or ""
        if button_id.startswith("nav-"):
            self.action_view(button_id.removeprefix("nav-"))
            return
        actions = {
            "action-enable": self.action_enable_bypass,
            "action-disable": self.action_disable_bypass,
            "action-status": self.action_cli_status,
            "action-speed": self.action_speed_test,
            "action-daemon-start": self.action_daemon_start,
            "action-daemon-stop": self.action_daemon_stop,
            "action-auto": self.action_toggle_auto_enable,
            "action-refresh": self.action_refresh,
            "action-save-config": self.action_save_settings,
            "action-doctor": self.action_doctor,
            "profile-iphone": lambda: self.apply_profile("iphone"),
            "profile-android": lambda: self.apply_profile("android"),
            "profile-stealth": lambda: self.apply_profile("stealth"),
        }
        if button_id in actions:
            actions[button_id]()

    def get_system_commands(self, screen) -> Iterable[SystemCommand]:
        yield from super().get_system_commands(screen)
        for command_id, title, help_text in self.PALETTE_COMMANDS:
            yield SystemCommand(
                title=title,
                help=help_text,
                callback=lambda command_id=command_id: self.execute_command(command_id),
                discover=True,
            )

    def execute_command(self, command_id: str) -> None:
        if command_id.startswith("view:"):
            self.action_view(command_id.removeprefix("view:"))
            return
        if command_id.startswith("profile:"):
            self.apply_profile(command_id.removeprefix("profile:"))
            return
        actions = {
            "action:enable": self.action_enable_bypass,
            "action:disable": self.action_disable_bypass,
            "action:status": self.action_cli_status,
            "action:speed": self.action_speed_test,
            "action:daemon-start": self.action_daemon_start,
            "action:daemon-stop": self.action_daemon_stop,
            "action:doctor": self.action_doctor,
            "action:refresh": self.action_refresh,
            "action:save": self.action_save_settings,
            "action:auto": self.action_toggle_auto_enable,
            "action:repeat": self.action_repeat_last,
        }
        action = actions.get(command_id)
        if action is None:
            self.notify(f"Unknown command: {command_id}", severity="error")
            return
        action()

    def action_refresh(self) -> None:
        self.refresh_snapshot()
        self.notify("Dashboard refreshed")

    def action_view(self, view_name: str) -> None:
        self.current_view = view_name
        self.render_current()

    def sync_settings_inputs(self) -> None:
        widgets = [
            self.query_one("#setting-ttl", Input),
            self.query_one("#setting-hl", Input),
            self.query_one("#setting-dns", Input),
            self.query_one("#setting-iface", Input),
        ]
        auto_switch = self.query_one("#setting-auto", Switch)
        if any(widget.has_focus for widget in widgets) or auto_switch.has_focus:
            return
        self._syncing_settings = True
        widgets[0].value = self.snapshot.config.get("TTL_VALUE", "")
        widgets[1].value = self.snapshot.config.get("HL_VALUE", "")
        widgets[2].value = self.snapshot.config.get("DNS_SERVER", "")
        widgets[3].value = self.snapshot.config.get("INTERFACE_OVERRIDE", "")
        auto_switch.value = self.snapshot.config.get("AUTO_ENABLE", "false").lower() == "true"
        self._syncing_settings = False

    def config_from_editor(self) -> dict[str, str] | None:
        config = dict(self.snapshot.config)
        ttl = self.query_one("#setting-ttl", Input).value.strip()
        hl = self.query_one("#setting-hl", Input).value.strip()
        dns = self.query_one("#setting-dns", Input).value.strip()
        iface = self.query_one("#setting-iface", Input).value.strip()
        auto = self.query_one("#setting-auto", Switch).value
        for label, value in [("TTL", ttl), ("HL", hl)]:
            if not value.isdigit():
                self.notify(f"{label} must be numeric", severity="error")
                return None
            if not 1 <= int(value) <= 255:
                self.notify(f"{label} must be between 1 and 255", severity="error")
                return None
        if not dns:
            self.notify("DNS server cannot be empty", severity="error")
            return None
        try:
            ipaddress.ip_address(dns)
        except ValueError:
            self.notify("DNS server must be a valid IP address", severity="error")
            return None
        config["TTL_VALUE"] = ttl
        config["HL_VALUE"] = hl
        config["DNS_SERVER"] = dns
        config["INTERFACE_OVERRIDE"] = iface
        config["AUTO_ENABLE"] = "true" if auto else "false"
        return config

    def add_history(self, entry: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        self.command_history.insert(0, f"{stamp}  {entry}")
        del self.command_history[8:]

    def start_command(self, args: list[str], label: str) -> bool:
        if self.command_running:
            self.notify(f"Command already running: {label}", severity="warning")
            self.add_history(f"blocked {label}: another command is running")
            self.render_current()
            return False
        self.command_running = True
        self.last_command = (list(args), label)
        self.add_history(f"started {label}")
        self.run_worker(self.run_throttle(args, label), name=f"command:{label}", group="commands", exclusive=True)
        return True

    async def run_throttle(self, args: list[str], label: str) -> None:
        self.current_view = "control"
        self.command_output = f"Running {label}..."
        self.render_current()

        def invoke() -> subprocess.CompletedProcess[str]:
            return subprocess.run(throttle_cmd() + args, capture_output=True, text=True, check=False, timeout=120)

        try:
            try:
                result = await asyncio.to_thread(invoke)
                output = "\n".join(
                    part for part in [
                        f"$ {' '.join(throttle_cmd() + args)}",
                        result.stdout.strip(),
                        result.stderr.strip(),
                        f"exit_code={result.returncode}",
                    ] if part
                )
                self.add_history(f"finished {label}: exit={result.returncode}")
            except subprocess.TimeoutExpired:
                output = f"$ {' '.join(throttle_cmd() + args)}\nTimed out after 120 seconds"
                self.add_history(f"timed out {label}")
            except Exception as exc:
                output = f"$ {' '.join(throttle_cmd() + args)}\nFailed: {exc}"
                self.add_history(f"failed {label}: {exc}")
            self.command_output = output
        finally:
            self.command_running = False
            self.refresh_snapshot()

    def confirm_then_run(self, message: str, args: list[str], label: str) -> None:
        def callback(confirmed: bool | None) -> None:
            if confirmed:
                self.start_command(args, label)

        self.push_screen(ConfirmScreen(message), callback)

    def action_enable_bypass(self) -> None:
        self.confirm_then_run("Enable carrier bypass? This may prompt for sudo and modify firewall/DNS state.", ["-e"], "enable bypass")

    def action_disable_bypass(self) -> None:
        self.confirm_then_run("Disable carrier bypass and restore normal network settings?", ["-d"], "disable bypass")

    def action_daemon_start(self) -> None:
        self.confirm_then_run("Start throttle-me daemon?", ["-D", "start"], "daemon start")

    def action_daemon_stop(self) -> None:
        self.confirm_then_run("Stop throttle-me daemon?", ["-D", "stop"], "daemon stop")

    def action_speed_test(self) -> None:
        self.start_command(["-t"], "speed test")

    def action_cli_status(self) -> None:
        self.start_command(["-s"], "cli status")

    def action_repeat_last(self) -> None:
        if self.last_command is None:
            self.notify("No command has been run yet", severity="warning")
            return
        args, label = self.last_command
        if args in (["-e"], ["-d"], ["-D", "start"], ["-D", "stop"]):
            self.confirm_then_run(f"Repeat {label}?", list(args), label)
            return
        self.start_command(list(args), label)

    def action_toggle_auto_enable(self) -> None:
        current = self.snapshot.config.get("AUTO_ENABLE", "false").lower() == "true"
        self.snapshot.config["AUTO_ENABLE"] = "false" if current else "true"
        self.query_one("#setting-auto", Switch).value = not current
        path = save_config(self.snapshot.config)
        self.notify(f"AUTO_ENABLE={self.snapshot.config['AUTO_ENABLE']} saved to {path}")
        self.refresh_snapshot()

    def action_save_settings(self) -> None:
        config = self.config_from_editor()
        if config is None:
            return
        path = save_config(config)
        self.notify(f"Saved config to {path}")
        self.refresh_snapshot()

    def action_doctor(self) -> None:
        self.current_view = "diagnostics"
        self.command_output = doctor_report(self.snapshot)
        self.render_current()
        self.notify("Doctor report refreshed")

    def apply_profile(self, profile: str) -> None:
        profiles = {
            "iphone": {"TTL_VALUE": "65", "HL_VALUE": "65", "DNS_SERVER": "1.1.1.1"},
            "android": {"TTL_VALUE": "64", "HL_VALUE": "64", "DNS_SERVER": "1.1.1.1"},
            "stealth": {"TTL_VALUE": "128", "HL_VALUE": "128", "DNS_SERVER": "8.8.8.8"},
        }
        config = dict(self.snapshot.config)
        config.update(profiles[profile])
        path = save_config(config)
        self.notify(f"{profile} profile saved to {path}")
        self.refresh_snapshot()
