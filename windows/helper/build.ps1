# Build the throttle-me-helper.exe service binary.
#
# Requirements:
#   - Go 1.22+ in PATH
#   - WinDivert binaries vendored under ../vendor/windivert/x64/
#
# Output: ./bin/throttle-me-helper.exe + WinDivert.dll + WinDivert64.sys

$ErrorActionPreference = 'Stop'

$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin    = Join-Path $here 'bin'
$vendor = Resolve-Path (Join-Path $here '..\vendor\windivert\x64')

if (-not (Test-Path $bin)) { New-Item -ItemType Directory -Path $bin | Out-Null }

Write-Host "==> building throttle-me-helper.exe"
$env:GOOS   = 'windows'
$env:GOARCH = 'amd64'
$env:CGO_ENABLED = '0'
Push-Location $here
try {
    go build -trimpath -ldflags '-s -w' -o (Join-Path $bin 'throttle-me-helper.exe') .
} finally {
    Pop-Location
}

Write-Host "==> copying WinDivert runtime from $vendor"
foreach ($f in 'WinDivert.dll', 'WinDivert64.sys') {
    $src = Join-Path $vendor $f
    if (-not (Test-Path $src)) {
        throw "missing $src — see ../vendor/windivert/README.md for download instructions"
    }
    Copy-Item -Force $src $bin
}

Write-Host "==> done; output in $bin"
Get-ChildItem $bin
