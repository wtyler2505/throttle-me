# Bypass.ps1 — enable / disable / status orchestration.
#
# Mirrors lib/core.sh on Linux. Status logic mirrors lib/iptables.sh:
# ACTIVE if both signals (service running + DNS overridden) are present,
# PARTIAL if only one, INACTIVE otherwise.

$Script:ServiceName = 'ThrottleMeHelper'

function Test-HelperInstalled {
    $svc = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    return $null -ne $svc
}

function Enable-Bypass {
    [CmdletBinding()]
    param(
        [int]$TTL,
        [string]$DNS,
        [string]$Interface
    )
    if (-not (Test-HelperInstalled)) {
        throw "Helper service '$Script:ServiceName' not installed. Run install.ps1 first."
    }

    if ($PSBoundParameters.ContainsKey('TTL'))       { Set-BypassConfigValue -Name 'TTL' -Value $TTL }
    if ($PSBoundParameters.ContainsKey('DNS'))       { Set-BypassConfigValue -Name 'DNS' -Value $DNS }
    if ($PSBoundParameters.ContainsKey('Interface')) { Set-BypassConfigValue -Name 'Interface' -Value $Interface }

    Start-Service -Name $Script:ServiceName
    # Wait briefly so subsequent status calls are accurate.
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Service -Name $Script:ServiceName).Status -ne 'Running' -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if ((Get-Service -Name $Script:ServiceName).Status -ne 'Running') {
        throw "Service did not reach Running state within 5s. Check Event Viewer (Windows Logs > Application)."
    }
}

function Disable-Bypass {
    if (-not (Test-HelperInstalled)) {
        # Already in a clean state.
        return
    }
    $svc = Get-Service -Name $Script:ServiceName
    if ($svc.Status -eq 'Stopped') { return }
    Stop-Service -Name $Script:ServiceName -Force
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Service -Name $Script:ServiceName).Status -ne 'Stopped' -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
}

function Get-BypassStatus {
    $cfg = Get-BypassConfig
    $svc = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue

    $running = $svc -and $svc.Status -eq 'Running'

    $dnsMatch = $false
    try {
        $adapter = Get-ActiveAdapter -Override $cfg.Interface
        $servers = Get-AdapterDns -Adapter $adapter
        if ($servers -and $servers[0] -eq $cfg.DNS) { $dnsMatch = $true }
    } catch {
        # No active adapter — treat as DNS not overridden.
    }

    $state = switch ("$running/$dnsMatch") {
        'True/True'   { 'ACTIVE' }
        'True/False'  { 'PARTIAL' }
        'False/True'  { 'PARTIAL' }
        default       { 'INACTIVE' }
    }

    return [pscustomobject]@{
        State          = $state
        ServiceRunning = $running
        DnsOverridden  = $dnsMatch
        Config         = $cfg
        Adapter        = $adapter
    }
}
