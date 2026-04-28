# SpeedTest.ps1 — Cloudflare 10MB download timing.
#
# Mirrors the -t flag on Linux (which uses speedtest-cli or a curl download).
# Kept dependency-free so it works out of the box on Windows PowerShell 5.1.

function Invoke-SpeedTest {
    [CmdletBinding()]
    param(
        [int]$Bytes = 10000000,
        [int]$TimeoutSec = 30
    )
    $url = "https://speed.cloudflare.com/__down?bytes=$Bytes"
    $tmp = New-TemporaryFile
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri $url -OutFile $tmp.FullName -UseBasicParsing -TimeoutSec $TimeoutSec | Out-Null
        $sw.Stop()
        $size = (Get-Item $tmp.FullName).Length
        $seconds = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $mbps = ($size * 8) / 1000000.0 / $seconds

        return [pscustomobject]@{
            BytesDownloaded = $size
            Seconds         = [math]::Round($seconds, 2)
            Mbps            = [math]::Round($mbps, 2)
        }
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $tmp.FullName
    }
}
