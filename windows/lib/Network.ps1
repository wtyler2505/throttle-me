# Network.ps1 — adapter and SSID detection.
#
# Mirrors lib/network.sh + lib/detection.sh on Linux. Auto-detect prefers
# Wi-Fi over Ethernet (since the bypass exists for tethered hotspots), and
# falls back to whichever adapter is up.

function Get-ActiveAdapter {
    [CmdletBinding()]
    param(
        [string]$Override
    )
    if ($Override) {
        $a = Get-NetAdapter -Name $Override -ErrorAction SilentlyContinue
        if ($a) { return $a }
        throw "Adapter '$Override' not found."
    }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    if (-not $adapters) { throw "No 'Up' network adapters found." }

    $wifi = $adapters | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' } |
        Sort-Object -Property LinkSpeed -Descending | Select-Object -First 1
    if ($wifi) { return $wifi }

    return $adapters | Sort-Object -Property LinkSpeed -Descending | Select-Object -First 1
}

function Get-CurrentSsid {
    $output = (& netsh wlan show interfaces) 2>$null
    if (-not $output) { return $null }
    foreach ($line in $output) {
        if ($line -match '^\s+SSID\s+:\s+(.+?)\s*$') {
            $ssid = $Matches[1].Trim()
            if ($ssid -and $ssid -ne 'BSSID') { return $ssid }
        }
    }
    return $null
}

function Test-HotspotSsid {
    param(
        [Parameter(Mandatory)][string]$Ssid,
        [string]$Patterns
    )
    if (-not $Patterns) {
        $cfg = Get-BypassConfig
        $Patterns = $cfg.HotspotPatterns
    }
    foreach ($pat in $Patterns -split ';') {
        $pat = $pat.Trim()
        if (-not $pat) { continue }
        if ($Ssid -like $pat) { return $true }
    }
    return $false
}

function Get-AdapterDns {
    param([Parameter(Mandatory)]$Adapter)
    $servers = (Get-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    if ($null -eq $servers) { return @() }
    return @($servers)
}
