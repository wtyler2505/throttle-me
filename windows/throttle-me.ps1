# throttle-me.ps1 — Windows CLI for the throttle-me bypass.
#
# Mirrors the Linux throttle-me CLI surface (subset; v1 = CLI + auto-detect).
# Run unelevated; admin is only needed for install.ps1 / uninstall.ps1.
#
# Usage examples (each is also exposed via short-flag aliases):
#   throttle-me -e                  enable bypass
#   throttle-me -d                  disable bypass
#   throttle-me -s                  show status
#   throttle-me -t                  speed test (Cloudflare 10MB)
#   throttle-me -a                  auto-detect hotspot SSID, prompt to enable
#   throttle-me -i "Wi-Fi"          override active adapter
#   throttle-me -e -TTL 70 -DNS 9.9.9.9
#   throttle-me -v                  print version

[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Enable')][Alias('e')][switch]$Enable,
    [Parameter(ParameterSetName = 'Disable')][Alias('d')][switch]$Disable,
    [Parameter(ParameterSetName = 'Status')][Alias('s')][switch]$Status,
    [Parameter(ParameterSetName = 'SpeedTest')][Alias('t')][switch]$SpeedTest,
    [Parameter(ParameterSetName = 'AutoDetect')][Alias('a')][switch]$AutoDetect,
    [Parameter(ParameterSetName = 'Version')][Alias('v')][switch]$Version,

    [Alias('i')][string]$Interface,
    [int]$TTL,
    [string]$DNS
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Config.ps1')
. (Join-Path $PSScriptRoot 'lib\Network.ps1')
. (Join-Path $PSScriptRoot 'lib\Bypass.ps1')
. (Join-Path $PSScriptRoot 'lib\SpeedTest.ps1')

function Show-Status {
    $s = Get-BypassStatus
    $color = switch ($s.State) {
        'ACTIVE'   { 'Green' }
        'PARTIAL'  { 'Yellow' }
        default    { 'Red' }
    }
    Write-Host "throttle-me: " -NoNewline
    Write-Host $s.State -ForegroundColor $color
    Write-Host ("  service:  {0}" -f $(if ($s.ServiceRunning) { 'Running' } else { 'Stopped' }))
    Write-Host ("  DNS set:  {0}" -f $s.DnsOverridden)
    if ($s.Adapter) {
        Write-Host ("  adapter:  {0} ({1})" -f $s.Adapter.Name, $s.Adapter.PhysicalMediaType)
    }
    Write-Host ("  TTL:      {0}" -f $s.Config.TTL)
    Write-Host ("  DNS:      {0}" -f $s.Config.DNS)
}

function Show-Version {
    $vfile = Join-Path $PSScriptRoot 'VERSION'
    if (Test-Path $vfile) {
        Write-Host "throttle-me $(Get-Content $vfile -Raw)" -NoNewline
    } else {
        Write-Host "throttle-me (unknown version)"
    }
}

function Invoke-AutoDetect {
    $ssid = Get-CurrentSsid
    if (-not $ssid) {
        Write-Host "No Wi-Fi SSID detected." -ForegroundColor Yellow
        return
    }
    Write-Host "Connected to: $ssid"
    if (-not (Test-HotspotSsid -Ssid $ssid)) {
        Write-Host "  not a known hotspot pattern; nothing to do." -ForegroundColor Yellow
        return
    }
    $resp = Read-Host "Enable bypass for '$ssid'? (y/N)"
    if ($resp -match '^[Yy]') {
        Invoke-EnableWithArgs
    }
}

function Invoke-EnableWithArgs {
    $params = @{}
    if ($PSBoundParameters.ContainsKey('TTL'))       { $params.TTL       = $TTL }
    if ($PSBoundParameters.ContainsKey('DNS'))       { $params.DNS       = $DNS }
    if ($PSBoundParameters.ContainsKey('Interface')) { $params.Interface = $Interface }
    Enable-Bypass @params
    Write-Host "Bypass ENABLED" -ForegroundColor Green
    Show-Status
}

# Dispatch
switch ($PSCmdlet.ParameterSetName) {
    'Enable'     { Invoke-EnableWithArgs }
    'Disable'    {
        Disable-Bypass
        Write-Host "Bypass DISABLED" -ForegroundColor Green
    }
    'Status'     { Show-Status }
    'SpeedTest'  {
        Write-Host "Running speed test (Cloudflare 10MB download)..."
        $r = Invoke-SpeedTest
        Write-Host ("  {0} bytes in {1}s = {2} Mbps" -f $r.BytesDownloaded, $r.Seconds, $r.Mbps) -ForegroundColor Cyan
    }
    'AutoDetect' { Invoke-AutoDetect }
    'Version'    { Show-Version }
}
