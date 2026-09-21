<#
.SYNOPSIS
  Register a logon scheduled task to check WSABuilds updates.
.EXAMPLE
  .\Install-WsaUpdater.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$taskName = 'WsaUpdater-CheckOnLogon'
$check = Join-Path $PSScriptRoot 'Check-WsaUpdate.ps1'
if (-not (Test-Path -LiteralPath $check)) {
    throw "Missing $check"
}

# Optional: honor config.check_on_logon when explicitly false
Import-Module (Join-Path $PSScriptRoot 'WsaUpdater.psm1') -Force
$cfg = Read-WsaUpdaterConfig
if ($cfg.PSObject.Properties['check_on_logon'] -and ($cfg.check_on_logon -eq $false)) {
    Write-Host "check_on_logon is false in config; not registering task."
    exit 0
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    if (-not $Force) {
        Write-Host "Task '$taskName' already exists. Use -Force to recreate."
        exit 0
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$check`" -Quiet"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'WSA/WSABuilds update check on logon (wsa-updater)' | Out-Null
Write-Host "Registered scheduled task: $taskName"
Write-Host "It runs: $check -Quiet"
exit 0
