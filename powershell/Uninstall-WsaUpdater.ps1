<#
.SYNOPSIS
  Remove the WsaUpdater logon scheduled task.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$taskName = 'WsaUpdater-CheckOnLogon'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host "Task '$taskName' not found."
    exit 0
}
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
Write-Host "Removed scheduled task: $taskName"
exit 0
