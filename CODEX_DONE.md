# Codex Completion Report

**Task:** Fix plain `throttle-me` still showing/loading the old `v2.0.0-alpha` experience.
**Status:** done

## Changes Made

- `lib/utils.sh` - Updated CLI version output to `v3.0.0 (2026-04-25)` and renamed the product line to command center.
- `lib/ui-theme.sh` - Updated the classic banner to `v3.0.0` command-center wording.
- `throttle-me` - Updated file header from v2 TUI wording to v3 command-center wording.
- `install.sh` - Updated installer header to `v3.0`.
- `PRODUCT_ANALYSIS.md` - Removed the remaining stale "alpha" wording.
- Installed runtime - Synced `throttle-me`, `throttle-me-daemon`, `lib/*.sh`, and the dashboard package into `~/.local/bin` / `~/.local/share/throttle-me`.

## Commands Run

```bash
type -a throttle-me
throttle-me -v
./throttle-me -v
rg -n "2\\.0\\.0-alpha|v2\\.0|alpha" throttle-me throttle-me-daemon lib dashboard install.sh docs config CODEX_DONE.md PRODUCT_ANALYSIS.md
bash -n throttle-me throttle-me-daemon install.sh test-theme.sh scripts/bypass-tethering scripts/disable-bypass-tethering
for f in lib/*.sh; do bash -n "$f"; done
shellcheck throttle-me throttle-me-daemon install.sh test-theme.sh lib/*.sh scripts/*
throttle-me --dashboard-smoke
throttle-me -p
git diff --check -- throttle-me lib/utils.sh lib/ui-theme.sh install.sh PRODUCT_ANALYSIS.md CODEX_DONE.md
```

## Next Steps

- Use plain `throttle-me` to open the installed command-center dashboard.

## Blockers (if any)

- None.

## Handoff Notes

Plain `throttle-me -v` now resolves through `/home/wtyler/.local/bin/throttle-me` and prints `throttle-me v3.0.0 (2026-04-25)`. `throttle-me --dashboard-smoke` also passes from the installed command.
