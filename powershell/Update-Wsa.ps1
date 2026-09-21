<#
.SYNOPSIS
  Check for WSABuilds update, download, then optionally auto-install after confirmation.
.EXAMPLE
  .\Update-Wsa.ps1 -DownloadOnly
.EXAMPLE
  .\Update-Wsa.ps1 -ConfirmInstall
.EXAMPLE
  .\Update-Wsa.ps1 -ConfirmInstall -Force   # reinstall even if versions match
#>
[CmdletBinding()]
param(
    [switch]$DownloadOnly,
    [switch]$ConfirmInstall,
    [switch]$Force,
    [string]$ConfigPath,
    [string]$OutDir,
    [switch]$Yes   # skip MessageBox; still requires -ConfirmInstall intent
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WsaUpdater.psm1') -Force
$config = Read-WsaUpdaterConfig -Path $ConfigPath
$result = Invoke-WsaUpdateCheck -Config $config
if (-not $result.ok) {
    Write-Error $result.error
    exit 3
}

Write-Host "Installed : $($result.installed_version) ($($result.install_source))"
Write-Host "Remote    : $($result.release_tag) / $($result.asset_name) ver=$($result.asset_version)"
Write-Host "HasUpdate : $($result.has_update) ($($result.reason))"

if (-not $result.has_update -and -not $Force) {
    Write-Host 'Already up to date. Use -Force to re-download/reinstall the preferred asset.'
    if (-not $ConfirmInstall) { exit 0 }
}

if (-not $result.asset_url) {
    Write-Error 'No download URL available.'
    exit 3
}

$dir = if ($OutDir) { $OutDir } else { $config.download_dir }
$dest = Join-Path $dir $result.asset_name
if ($Force -or $result.has_update -or -not (Test-Path -LiteralPath $dest)) {
    Write-Host "Downloading $($result.asset_name) ..."
    $dest = Start-WsaAssetDownload -Result $result -DownloadDir $dir
} else {
    Write-Host "Using existing archive: $dest"
}

if ($DownloadOnly -and -not $ConfirmInstall) {
    Write-Host "Saved: $dest"
    Write-Host "Next: re-run with -ConfirmInstall to apply after confirmation."
    exit 0
}

if (-not $ConfirmInstall) {
    Write-Host "Saved: $dest (not applying; pass -ConfirmInstall to auto-upgrade after confirm)"
    exit 0
}

# Confirmation gate
$msg = @(
    "WSA update package ready."
    ""
    "Asset: $($result.asset_name)"
    "Version: $($result.asset_version)"
    "Install dir: $($result.wsa_install_dir)"
    ""
    "This will STOP WSA, backup userdata, merge files, and re-register Appx (admin)."
    "Continue?"
) -join [Environment]::NewLine

$confirmed = $false
if ($Yes) {
    $confirmed = $true
    Write-Host 'Confirmed via -Yes'
} else {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $r = [System.Windows.Forms.MessageBox]::Show($msg, 'WSA Updater - Confirm install', 'YesNo', 'Warning')
        $confirmed = ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        $ans = Read-Host "$msg [y/N]"
        $confirmed = ($ans -match '^(y|yes)$')
    }
}

if (-not $confirmed) {
    Write-Host 'User cancelled install. Archive left at:'
    Write-Host $dest
    exit 0
}

$installer = Join-Path $PSScriptRoot 'Install-WsaBuild.ps1'
Write-Host "Running installer: $installer"
& $installer -ArchivePath $dest -InstallDir $result.wsa_install_dir -Confirm
exit $LASTEXITCODE
