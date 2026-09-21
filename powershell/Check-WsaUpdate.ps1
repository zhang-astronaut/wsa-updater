<#
.SYNOPSIS
  Check WSABuilds for WSA updates and optionally notify.
.EXAMPLE
  .\Check-WsaUpdate.ps1
.EXAMPLE
  .\Check-WsaUpdate.ps1 -Quiet -Json
#>
[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Json,
    [switch]$Notify,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'WsaUpdater.psm1'
Import-Module $module -Force

$config = Read-WsaUpdaterConfig -Path $ConfigPath
try {
    $result = Invoke-WsaUpdateCheck -Config $config
} catch {
    $err = $_.Exception.Message
    if (-not $Quiet) {
        Write-Error $err
    } else {
        Write-Host "WsaUpdater check failed: $err"
    }
    exit 2
}

# persist last check (honor -ConfigPath)
$config.last_check_utc = (get-date).ToUniversalTime().ToString('o')
if ($result.ok) {
    $config.last_release_tag = $result.release_tag
    if ($result.asset_name) { $config.last_asset_name = $result.asset_name }
    $saveTo = if ($ConfigPath) { $ConfigPath } else { Get-WsaUpdaterConfigPath }
    try { Save-WsaUpdaterConfig -Config $config -Path $saveTo } catch { }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} elseif (-not $Quiet) {
    Write-Host "Release : $($result.release_tag)"
    Write-Host "Asset   : $($result.asset_name)"
    Write-Host "Local   : $($result.installed_version) ($($result.install_source))"
    Write-Host "Update  : $($result.has_update) ($($result.reason))"
}

$shouldNotify = $false
if ($result.ok -and $result.PSObject.Properties['should_notify'] -and $result.should_notify) {
    $shouldNotify = $true
} elseif ($result.ok -and $result.has_update -and -not ($result.PSObject.Properties['should_notify'])) {
    $shouldNotify = $true
}
if ($result.ok -and $config.notify_on_up_to_date -and -not $Quiet -and -not $Json) {
    $shouldNotify = $true
}
if ($Notify -and $result.ok -and -not $Json) { $shouldNotify = $true }

if ($shouldNotify -and -not $Json) {
    try {
        Show-WsaUpdateToast -Result $result
    } catch {
        Write-Host "Notify failed: $($_.Exception.Message)"
    }
}

if (-not $result.ok) { exit 3 }
# Exit 0 whether or not an update exists; has_update is informational.
exit 0
