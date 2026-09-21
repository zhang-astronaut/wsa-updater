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
$who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if (-not $who) { $who = "$env:USERDOMAIN\$env:USERNAME" }
# Avoid SYSTEM / unmapped SIDs; fall back to current user logon without explicit UserId
try {
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $who
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'WSA/WSABuilds update check on logon (wsa-updater)' -Force | Out-Null
} catch {
    Write-Host "Primary principal failed ($who): $($_.Exception.Message); trying current-user default principal"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'WSA/WSABuilds update check on logon (wsa-updater)' -Force | Out-Null
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) {
    throw "Failed to register scheduled task $taskName"
}
Write-Host "Registered scheduled task: $taskName (State=$($task.State))"
Write-Host "It runs: $check -Quiet"
exit 0
