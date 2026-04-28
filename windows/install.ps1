# install.ps1 — one-shot installer for the throttle-me Windows port.
#
# Run from an ELEVATED PowerShell:
#   cd windows
#   .\install.ps1
#
# This is the only step that needs admin. Day-to-day use of throttle-me runs
# unelevated because the helper service ACL grants Authenticated Users the
# right to start/stop it.

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'throttle-me'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ServiceName = 'ThrottleMeHelper'
$here        = Split-Path -Parent $MyInvocation.MyCommand.Path
$helperBin   = Join-Path $here 'helper\bin'

. (Join-Path $here 'lib\Config.ps1')

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Prerequisites {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.1+ required (have $($PSVersionTable.PSVersion))."
    }
    $exe = Join-Path $helperBin 'throttle-me-helper.exe'
    if (-not (Test-Path $exe)) {
        throw @"
Helper binary not built.

Run this first:
  cd $here\helper
  .\build.ps1

You also need the WinDivert binaries vendored — see:
  $here\vendor\windivert\README.md
"@
    }
    foreach ($f in 'throttle-me-helper.exe', 'WinDivert.dll', 'WinDivert64.sys') {
        if (-not (Test-Path (Join-Path $helperBin $f))) {
            throw "Missing $f under $helperBin. Re-run helper\build.ps1."
        }
    }
}

function Install-Files {
    if (Test-Path $InstallDir) {
        if (-not $Force) {
            Write-Host "Install dir exists: $InstallDir (re-using; pass -Force to wipe)"
        } else {
            Write-Host "Wiping existing install dir: $InstallDir"
            Remove-Item -Recurse -Force $InstallDir
        }
    }
    New-Item -ItemType Directory -Force -Path $InstallDir, (Join-Path $InstallDir 'lib'), (Join-Path $InstallDir 'helper') | Out-Null

    Copy-Item -Force (Join-Path $here 'throttle-me.ps1')  $InstallDir
    Copy-Item -Force (Join-Path $here 'throttle-me.cmd')  $InstallDir
    Copy-Item -Force (Join-Path $here 'VERSION')          $InstallDir
    Copy-Item -Force (Join-Path $here 'lib\*.ps1')        (Join-Path $InstallDir 'lib')
    Copy-Item -Force (Join-Path $helperBin '*')           (Join-Path $InstallDir 'helper')

    Write-Host "  files installed to $InstallDir"
}

function Install-Service {
    $exe = Join-Path $InstallDir 'helper\throttle-me-helper.exe'

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force
        }
        & sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Milliseconds 500
    }

    & sc.exe create $ServiceName binPath= "`"$exe`"" start= demand DisplayName= "throttle-me bypass helper" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sc create failed (exit $LASTEXITCODE)" }
    & sc.exe description $ServiceName "TTL + DNS bypass for tethered hotspots. See https://github.com/wtyler2505/throttle-me" | Out-Null

    # Grant Authenticated Users the right to start/stop and query the service.
    # Default SDDL plus an extra ACE: A;;RPWPDTLOCRRC;;;AU
    $sddl = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)(A;;RPWPDTLOCRRC;;;AU)'
    & sc.exe sdset $ServiceName $sddl | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "sc sdset returned $LASTEXITCODE — non-admin start/stop may not work." }

    Write-Host "  service '$ServiceName' registered (StartupType=Manual)"
}

function Install-RegistryDefaults {
    Initialize-BypassConfig
    Write-Host "  registry defaults seeded under HKLM\SOFTWARE\throttle-me"
}

function Add-ToPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -split ';' -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$InstallDir", 'Machine')
        Write-Host "  added to system PATH (open a new shell to pick it up)"
    } else {
        Write-Host "  already on system PATH"
    }
}

function Verify-Install {
    $cmd = Join-Path $InstallDir 'throttle-me.cmd'
    if (-not (Test-Path $cmd)) { throw "verification failed: $cmd missing" }
    & $cmd -v
}

# ---- main ----

if (-not (Test-Admin)) {
    Write-Error "install.ps1 must be run from an elevated PowerShell."
    exit 1
}

Write-Host "==> checking prerequisites"
Test-Prerequisites

Write-Host "==> installing files"
Install-Files

Write-Host "==> registering service"
Install-Service

Write-Host "==> seeding registry defaults"
Install-RegistryDefaults

Write-Host "==> updating PATH"
Add-ToPath

Write-Host "==> verifying"
Verify-Install

Write-Host ""
Write-Host "Install complete." -ForegroundColor Green
Write-Host "Open a new cmd or PowerShell window and run:" -ForegroundColor Green
Write-Host "  throttle-me -e        # enable" -ForegroundColor Green
Write-Host "  throttle-me -s        # status" -ForegroundColor Green
Write-Host "  throttle-me -d        # disable" -ForegroundColor Green
