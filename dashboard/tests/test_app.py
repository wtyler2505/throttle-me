from __future__ import annotations

import asyncio
from pathlib import Path

from textual.widgets import Input

import throttle_me_dashboard.app as app_module
from throttle_me_dashboard.app import CommandCenterApp, ConfirmScreen


def run_async(coro):
    return asyncio.run(coro)


def test_confirm_screen_can_cancel_without_worker() -> None:
    async def scenario() -> None:
        app = CommandCenterApp()
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.press("s")
            assert isinstance(app.screen, ConfirmScreen)
            await pilot.press("escape")
            assert not isinstance(app.screen, ConfirmScreen)

    run_async(scenario())


def test_command_dispatch_supports_views_and_profiles(monkeypatch, tmp_path: Path) -> None:
    saved: dict[str, str] = {}

    def fake_save_config(config: dict[str, str]) -> Path:
        saved.update(config)
        return tmp_path / "config"

    monkeypatch.setattr(app_module, "save_config", fake_save_config)

    async def scenario() -> None:
        app = CommandCenterApp()
        async with app.run_test(size=(130, 42)):
            app.execute_command("view:diagnostics")
            assert app.current_view == "diagnostics"

            app.execute_command("profile:stealth")
            assert saved["TTL_VALUE"] == "128"
            assert saved["HL_VALUE"] == "128"
            assert saved["DNS_SERVER"] == "8.8.8.8"

    run_async(scenario())


def test_config_editor_rejects_invalid_hop_and_dns() -> None:
    async def scenario() -> None:
        app = CommandCenterApp()
        async with app.run_test(size=(130, 42)):
            app.query_one("#setting-ttl", Input).value = "0"
            app.query_one("#setting-hl", Input).value = "65"
            app.query_one("#setting-dns", Input).value = "1.1.1.1"
            assert app.config_from_editor() is None

            app.query_one("#setting-ttl", Input).value = "65"
            app.query_one("#setting-dns", Input).value = "not-dns"
            assert app.config_from_editor() is None

    run_async(scenario())


def test_responsive_layout_hides_rightbar_on_narrow_terminal() -> None:
    async def scenario() -> None:
        app = CommandCenterApp()
        async with app.run_test(size=(120, 36)):
            app.render_current()
            assert app.query_one("#rightbar").display is False
            assert app.query_one("#sidebar").display is True

    run_async(scenario())


def test_busy_command_is_blocked_without_starting_worker() -> None:
    async def scenario() -> None:
        app = CommandCenterApp()
        async with app.run_test(size=(130, 42)):
            app.command_running = True
            assert app.start_command(["-s"], "cli status") is False
            assert "blocked cli status" in app.command_history[0]

    run_async(scenario())


def test_repeat_last_dispatches_safe_command() -> None:
    calls: list[tuple[list[str], str]] = []

    async def scenario() -> None:
        app = CommandCenterApp()
        async with app.run_test(size=(130, 42)):
            app.last_command = (["-s"], "cli status")

            def fake_start(args: list[str], label: str) -> bool:
                calls.append((args, label))
                return True

            app.start_command = fake_start  # type: ignore[method-assign]
            app.action_repeat_last()

    run_async(scenario())
    assert calls == [(["-s"], "cli status")]
