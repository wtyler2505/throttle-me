from __future__ import annotations

import asyncio
import subprocess

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Footer, Header, Label, Static

from .collectors import collect_snapshot, save_config, throttle_cmd
from .renderers import render_control, render_diagnostics, render_logs, render_monitor, render_overview, render_sessions, render_settings


class ConfirmScreen(ModalScreen[bool]):
    def __init__(self, message: str) -> None:
        super().__init__()
        self.message = message

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-dialog"):
            yield Label(self.message, id="confirm-message")
            with Horizontal(id="confirm-actions"):
                yield Button("Confirm", variant="success", id="confirm")
                yield Button("Cancel", variant="default", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "confirm")


class CommandCenterApp(App):
    CSS_PATH = "styles.tcss"
    TITLE = "throttle-me command center"
    SUB_TITLE = "operator console"

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
        ("ctrl+s", "save_settings", "Save"),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.current_view = "overview"
        self.snapshot = collect_snapshot()
        self.command_output = ""

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="layout"):
            with Vertical(id="sidebar"):
                yield Static("THROTTLE-ME", id="brand")
                yield Static("1 Overview\n2 Control\n3 Diagnostics\n4 Monitor\n5 Sessions\n6 Settings\n7 Logs", classes="nav")
                yield Static("e enable\nd disable\ns daemon start\nx daemon stop\nt speed test\nr refresh\nq quit", classes="keys")
            with Vertical(id="main"):
                yield Static("", id="view-title")
                yield Static("", id="content")
        yield Footer()

    def on_mount(self) -> None:
        self.set_interval(2.0, self.refresh_snapshot)
        self.render_current()

    def refresh_snapshot(self) -> None:
        self.snapshot = collect_snapshot()
        self.render_current()

    def render_current(self) -> None:
        title = self.query_one("#view-title", Static)
        content = self.query_one("#content", Static)
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

    def action_refresh(self) -> None:
        self.refresh_snapshot()
        self.notify("Dashboard refreshed")

    def action_view(self, view_name: str) -> None:
        self.current_view = view_name
        self.render_current()

    async def run_throttle(self, args: list[str], label: str) -> None:
        self.current_view = "control"
        self.command_output = f"Running {label}..."
        self.render_current()

        def invoke() -> subprocess.CompletedProcess[str]:
            return subprocess.run(throttle_cmd() + args, capture_output=True, text=True, check=False, timeout=120)

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
        except subprocess.TimeoutExpired:
            output = f"$ {' '.join(throttle_cmd() + args)}\nTimed out after 120 seconds"

        self.command_output = output
        self.refresh_snapshot()

    async def confirm(self, message: str) -> bool:
        return await self.push_screen_wait(ConfirmScreen(message))

    async def action_enable_bypass(self) -> None:
        if await self.confirm("Enable carrier bypass? This may prompt for sudo and modify firewall/DNS state."):
            await self.run_throttle(["-e"], "enable bypass")

    async def action_disable_bypass(self) -> None:
        if await self.confirm("Disable carrier bypass and restore normal network settings?"):
            await self.run_throttle(["-d"], "disable bypass")

    async def action_daemon_start(self) -> None:
        if await self.confirm("Start throttle-me daemon?"):
            await self.run_throttle(["-D", "start"], "daemon start")

    async def action_daemon_stop(self) -> None:
        if await self.confirm("Stop throttle-me daemon?"):
            await self.run_throttle(["-D", "stop"], "daemon stop")

    async def action_speed_test(self) -> None:
        await self.run_throttle(["-t"], "speed test")

    def action_save_settings(self) -> None:
        path = save_config(self.snapshot.config)
        self.notify(f"Saved config to {path}")
        self.refresh_snapshot()
