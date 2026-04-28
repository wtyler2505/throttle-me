# Toggle-Bypass.ps1 — invoked by Start Menu / desktop shortcuts.
#
# Runs the requested action against the helper service and shows a 2-second
# auto-dismissing native Windows popup so the user sees the result without
# having to look at a console window.
#
# Examples:
#   powershell -NoProfile -WindowStyle Hidden -File Toggle-Bypass.ps1 -Action Enable
#   powershell -NoProfile -WindowStyle Hidden -File Toggle-Bypass.ps1 -Action Disable
#   powershell -NoProfile -WindowStyle Hidden -File Toggle-Bypass.ps1 -Action Status

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Enable', 'Disable', 'Status')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Config.ps1')
. (Join-Path $PSScriptRoot 'lib\Network.ps1')
. (Join-Path $PSScriptRoot 'lib\Bypass.ps1')

# WScript.Shell.Popup buttonset/icon flags we use:
#   0  = OK button
#   16 = stop icon (red X)
#   48 = warning icon (yellow !)
#   64 = info icon (blue i)
function Show-AutoPopup {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [int]$Seconds = 2,
        [int]$IconFlag = 64
    )
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.Popup($Message, $Seconds, $Title, $IconFlag)
}

try {
    switch ($Action) {
        'Enable' {
            Enable-Bypass
            Show-AutoPopup -Title 'Throttle Me' -Message "Bypass is now ON.`n`nTraffic is being routed through the bypass." -IconFlag 64
        }
        'Disable' {
            Disable-Bypass
            Show-AutoPopup -Title 'Throttle Me' -Message "Bypass is now OFF.`n`nNormal carrier behavior restored." -IconFlag 64
        }
        'Status' {
            $s = Get-BypassStatus
            $body = "State: {0}`nService: {1}`nDNS overridden: {2}`nDNS server: {3}" -f `
                $s.State, $(if ($s.ServiceRunning) { 'Running' } else { 'Stopped' }), $s.DnsOverridden, $s.Config.DNS
            Show-AutoPopup -Title 'Throttle Me — Status' -Message $body -Seconds 5 -IconFlag 64
        }
    }
}
catch {
    Show-AutoPopup -Title 'Throttle Me — Error' -Message ("Something went wrong:`n`n{0}" -f $_.Exception.Message) -Seconds 8 -IconFlag 16
    exit 1
}
