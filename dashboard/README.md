# throttle-me Command Center

This directory contains the Textual dashboard that launches by default from `throttle-me`.

Run from the repository:

```bash
uv run --project dashboard throttle-me-dashboard
```

Non-interactive smoke check:

```bash
uv run --project dashboard throttle-me-dashboard --smoke
```

The dashboard diagnostics are read-only. Enable/disable and daemon controls still call the existing `throttle-me` CLI actions and show command output in the Control view.
