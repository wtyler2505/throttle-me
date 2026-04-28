# uninstall.ps1 — reverse of install.ps1.
#
# Run from an ELEVATED PowerShell:
#   cd windows
#   .\uninstall.ps1
#
# By default it preserves the registry config tree (HKLM\SOFTWARE\throttle-me)
# so reinstalling later picks up your settings. Pass -Purge to wipe everything.

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'throttle-me'),
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'
$ServiceName = 'ThrottleMeHelper'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "uninstall.ps1 must be run from an elevated PowerShell."
    exit 1
}

Write-Host "==> stopping service"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
    & sc.exe delete $ServiceName | Out-Null
    Write-Host "  service removed"
} else {
    Write-Host "  service not present"
}

Write-Host "==> removing files"
if (Test-Path $InstallDir) {
    Remove-Item -Recurse -Force $InstallDir
    Write-Host "  $InstallDir removed"
} else {
    Write-Host "  $InstallDir not present"
}

Write-Host "==> cleaning PATH"
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$cleaned = ($machinePath -split ';' | Where-Object { $_ -and $_ -ne $InstallDir }) -join ';'
if ($cleaned -ne $machinePath) {
    [Environment]::SetEnvironmentVariable('Path', $cleaned, 'Machine')
    Write-Host "  removed from system PATH"
}

if ($Purge) {
    Write-Host "==> purging registry config"
    Remove-Item -Recurse -Force 'HKLM:\SOFTWARE\throttle-me' -ErrorAction SilentlyContinue
    Write-Host "  registry tree removed"
} else {
    Write-Host "==> registry config preserved (pass -Purge to wipe)"
}

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Green
