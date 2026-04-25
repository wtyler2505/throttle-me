from __future__ import annotations

import argparse
import sys

from .app import CommandCenterApp
from .collectors import collect_snapshot
from .renderers import render_control, render_diagnostics, render_logs, render_monitor, render_overview, render_sessions, render_settings


def smoke() -> int:
    snapshot = collect_snapshot()
    render_overview(snapshot)
    render_control(snapshot, "")
    render_diagnostics(snapshot)
    render_monitor(snapshot)
    render_sessions(snapshot)
    render_settings(snapshot)
    render_logs(snapshot)
    print("dashboard smoke ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="throttle-me Textual dashboard")
    parser.add_argument("--smoke", action="store_true", help="run a non-interactive dashboard smoke check")
    args = parser.parse_args(argv)

    if args.smoke:
        return smoke()

    app = CommandCenterApp()
    app.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
