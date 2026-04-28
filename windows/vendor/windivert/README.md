# WinDivert vendored binaries

The Windows port depends on **WinDivert 2.x** by Reqrypt — a userspace packet
filter library that ships its own signed kernel-mode driver. The binaries are
**not** committed to git (LGPLv3 compatibility is fine, but signed `.sys` files
churn between point releases and bloat the repo).

## What you need

Three files under `x64/`:

| File | What |
|------|------|
| `WinDivert.dll` | Userspace API the helper exe calls |
| `WinDivert64.sys` | Signed kernel driver, loaded on first use |
| `WinDivert.lib` | Import library (only needed if you cgo-link; optional for the Go binding) |

## How to get them

1. Download the latest **WinDivert 2.x** release from the official source:
   https://reqrypt.org/windivert.html
   (or the GitHub mirror at https://github.com/basil00/WinDivert/releases —
   look for `WinDivert-2.2.X-A.zip`).

2. Verify the SHA-256 against the value listed on the release page.

3. Extract `WinDivert.dll`, `WinDivert64.sys`, and (optionally) `WinDivert.lib`
   from `x64/` in the zip, and drop them in this directory:

   ```
   windows/vendor/windivert/x64/WinDivert.dll
   windows/vendor/windivert/x64/WinDivert64.sys
   windows/vendor/windivert/x64/WinDivert.lib
   ```

4. Run `..\..\helper\build.ps1` — it copies these next to the helper exe.

## License

WinDivert 2.x is dual-licensed under LGPLv3 and GPLv2. Personal use is fine.
A copy of the LGPL text should live alongside the binaries (drop `LICENSE`
from the WinDivert zip into this directory).

## Why not commit them

- The `.sys` driver is signed by Reqrypt; redistributing the signed binary
  is allowed by the license but pinning a copy here tangles us up in
  signature lifetimes if Reqrypt ever rotates keys.
- `git clone` without binaries stays small.
- Keeps the source repo clean of large binary blobs.

If you'd rather commit them anyway for offline-friendly clones, that's
permitted by the license — just drop them in `x64/` and `git add` them.
