# Config.ps1 — read/write HKLM\SOFTWARE\throttle-me.
#
# Mirrors lib/config.sh on Linux. The helper service reads the same registry
# keys at startup, so any change here is picked up on the next Start-Service.

$Script:ConfigKey = 'HKLM:\SOFTWARE\throttle-me'

$Script:ConfigDefaults = @{
    TTL              = 65
    HL               = 65
    DNS              = '1.1.1.1'
    Interface        = ''
    HotspotPatterns  = 'iPhone*;AndroidAP*;*Galaxy*;Mobile Hotspot;*''s iPhone'
}

function Get-BypassConfig {
    $cfg = $Script:ConfigDefaults.Clone()
    if (Test-Path $Script:ConfigKey) {
        $item = Get-ItemProperty -Path $Script:ConfigKey -ErrorAction SilentlyContinue
        foreach ($name in @($cfg.Keys)) {
            if ($null -ne $item.$name) { $cfg[$name] = $item.$name }
        }
    }
    return [pscustomobject]$cfg
}

function Set-BypassConfigValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )
    if (-not (Test-Path $Script:ConfigKey)) {
        New-Item -Path $Script:ConfigKey -Force | Out-Null
    }
    $kind = if ($Value -is [int]) { 'DWord' } else { 'String' }
    Set-ItemProperty -Path $Script:ConfigKey -Name $Name -Value $Value -Type $kind
}

function Initialize-BypassConfig {
    if (-not (Test-Path $Script:ConfigKey)) {
        New-Item -Path $Script:ConfigKey -Force | Out-Null
    }
    foreach ($name in $Script:ConfigDefaults.Keys) {
        $existing = (Get-ItemProperty -Path $Script:ConfigKey -Name $name -ErrorAction SilentlyContinue).$name
        if ($null -eq $existing) {
            Set-BypassConfigValue -Name $name -Value $Script:ConfigDefaults[$name]
        }
    }
}
