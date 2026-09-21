<#
.SYNOPSIS
  Download the matched WSABuilds asset (does NOT auto-install).
.EXAMPLE
  .\Update-Wsa.ps1 -DownloadOnly
#>
[CmdletBinding()]
param(
    [switch]$DownloadOnly,
    [string]$ConfigPath,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WsaUpdater.psm1') -Force
$config = Read-WsaUpdaterConfig -Path $ConfigPath
$result = Invoke-WsaUpdateCheck -Config $config
if (-not $result.ok) {
    Write-Error $result.error
    exit 3
}
if (-not $result.asset_url) {
    Write-Error 'No download URL available.'
    exit 3
}
$dir = if ($OutDir) { $OutDir } else { $config.download_dir }
Write-Host "Release: $($result.release_tag)"
Write-Host "Asset  : $($result.asset_name)"
$dest = Start-WsaAssetDownload -Result $result -DownloadDir $dir
Write-Host "Saved: $dest"
if ($DownloadOnly) {
    Write-Host "Download-only mode: install manually by extracting into $($config.wsa_install_dir) and re-registering Appx (admin)."
}
exit 0
