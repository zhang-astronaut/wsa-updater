<#
.SYNOPSIS
  Apply a downloaded WSABuilds archive to WsaInstallDir after explicit confirmation.
.DESCRIPTION
  Stops WSA, backs up userdata.vhdx when present, extracts the archive,
  merges into InstallDir, re-applies VC++ *_APP.dll helpers if available,
  then registers Appx (self-elevates). Does not run unless -Confirm:$true
  or the caller already confirmed.
.EXAMPLE
  .\Install-WsaBuild.ps1 -ArchivePath C:\WSA\_download\....7z -InstallDir C:\WSA -Confirm
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [string]$InstallDir = 'C:\WSA',
    [switch]$Confirm,
    [string]$BackupDir = 'C:\WSA\_backup',
    [switch]$SkipRegister
)

$ErrorActionPreference = 'Stop'
$log = Join-Path $InstallDir '_install_apply_log.txt'
$dir = Split-Path -Parent $InstallDir
if ($dir -and -not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format o), $msg
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

if (-not $Confirm) {
    Write-Log 'Refusing to install without -Confirm (user confirmation required).'
    exit 1
}
if (-not (Test-Path -LiteralPath $ArchivePath)) {
    Write-Log "Archive not found: $ArchivePath"
    exit 2
}

Write-Log "Apply start archive=$ArchivePath installDir=$InstallDir"

# Self-elevate for Appx register + feature ops
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $SkipRegister) {
    Write-Log 'Not elevated; relaunching self as administrator...'
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ArchivePath `"$ArchivePath`" -InstallDir `"$InstallDir`" -Confirm -BackupDir `"$BackupDir`" -SkipRegister:`$$($SkipRegister.IsPresent)"
    # Simpler elevation args:
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-ArchivePath',$ArchivePath,'-InstallDir',$InstallDir,'-Confirm','-BackupDir',$BackupDir)
    if ($SkipRegister) { $argList += '-SkipRegister' }
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList $argList
    if ($p) { $p.WaitForExit(); exit $p.ExitCode }
    Write-Log 'Elevation failed or was cancelled.'
    exit 3
}

Start-Transcript -Path ($log + '.transcript') -Append -ErrorAction SilentlyContinue | Out-Null

# Stop WSA
Write-Log 'Stopping WSA processes...'
Get-Process WsaClient,WsaService,WsaSettings,WsaProxy,WSACrashUploader -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Get-Service -Name 'WsaService','Windows Subsystem for Android*' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue

# Backup userdata
$pkgLocal = Join-Path $env:LOCALAPPDATA 'Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\LocalCache'
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
Get-ChildItem $pkgLocal -Filter 'userdata*.vhdx' -ErrorAction SilentlyContinue | ForEach-Object {
    $dest = Join-Path $BackupDir ('userdata_{0}_{1}' -f (Get-Date -Format yyyyMMdd_HHmmss), $_.Name)
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    Write-Log "Backed up $($_.Name) -> $dest"
}

# Unregister existing package (preserve data)
$Name = 'MicrosoftCorporationII.WindowsSubsystemForAndroid'
$existing = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
if ($existing -and -not $SkipRegister) {
    Write-Log "Unregister $($existing.PackageFullName)"
    try {
        Remove-AppxPackage -Package $existing.PackageFullName -PreserveApplicationData -ErrorAction Stop
        Write-Log 'Unregister preserve: OK'
    } catch {
        Write-Log "Preserve unregister failed: $($_.Exception.Message)"
        try { Remove-AppxPackage -Package $existing.PackageFullName -ErrorAction Stop; Write-Log 'Full unregister: OK' }
        catch { Write-Log "Unregister failed: $($_.Exception.Message)" }
    }
}

# Extract archive
$seven = $null
foreach ($c in @('C:\Users\zhang\AppData\Local\Microsoft\WindowsApps\7z.exe','C:\Program Files\7-Zip\7z.exe','C:\Program Files (x86)\7-Zip\7z.exe')) {
    if (Test-Path $c) { $seven = $c; break }
}
if (-not $seven) {
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { $seven = $cmd.Source }
}
if (-not $seven) {
    Write-Log '7z.exe not found. Install 7-Zip/NanaZip or put 7z on PATH.'
    exit 4
}

$stage = Join-Path $InstallDir '_apply_stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Write-Log "Extracting with $seven ..."
& $seven x $ArchivePath "-o$stage" -y
if ($LASTEXITCODE -ne 0) { Write-Log "7z extract failed exit=$LASTEXITCODE"; exit 5 }
$pkgDir = Get-ChildItem $stage -Directory | Select-Object -First 1
if (-not $pkgDir) { Write-Log 'No package folder in archive'; exit 5 }
Write-Log "Merging $($pkgDir.FullName) -> $InstallDir"
$exclude = @('_download','_backup','_gapps_stage','_apply_stage','platform-tools')
Get-ChildItem -Path $pkgDir.FullName -Force | ForEach-Object {
    if ($exclude -contains $_.Name) { return }
    $dest = Join-Path $InstallDir $_.Name
    Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
}

# Re-apply APP DLLs if VCLibs extract exists
$vclibsDir = Join-Path $InstallDir '_download\vclibs_extract\Microsoft.VCLibs.140.00_x64.appx'
if (Test-Path $vclibsDir) {
    Get-ChildItem $vclibsDir -Filter '*_APP.dll' -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $InstallDir $_.Name) -Force
    }
    $hostDirs = @('WsaClient','WsaService','WsaSettingsBroker','WsaProxy','WSACrashUploader','amd64')
    foreach ($d in $hostDirs) {
        $p = Join-Path $InstallDir $d
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $InstallDir -File -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $p $_.Name) -Force -ErrorAction SilentlyContinue
        }
        Get-ChildItem $vclibsDir -Filter '*_APP.dll' | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $p $_.Name) -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log 'Re-applied *_APP.dll helpers'
}

if ($SkipRegister) {
    Write-Log 'SkipRegister set; files merged only.'
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 0
}

Set-Location $InstallDir
[xml]$Xml = Get-Content -LiteralPath (Join-Path $InstallDir 'AppxManifest.xml')
Write-Log "Register $($Xml.Package.Identity.Name) $($Xml.Package.Identity.Version)"
$arch = $Xml.Package.Identity.ProcessorArchitecture
foreach ($dep in $Xml.Package.Dependencies.PackageDependency) {
    $inst = Get-AppxPackage -Name $dep.Name -ErrorAction SilentlyContinue |
        Where-Object { $_.Architecture -eq $arch } | Sort-Object Version | Select-Object -Last 1
    if (-not $inst -or ([version]$inst.Version -lt [version]$dep.MinVersion)) {
        $appx = Join-Path $InstallDir ("{0}_{1}.appx" -f $dep.Name, $arch)
        if (Test-Path $appx) {
            Write-Log "Install dep $appx"
            Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Path $appx
        }
    }
}

Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register (Join-Path $InstallDir 'AppxManifest.xml')
Write-Log "Register result: $?"
$pkg = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
Write-Log "Package: $($pkg.PackageFullName) Status=$($pkg.Status) DevMode=$($pkg.IsDevelopmentMode)"
Write-Log 'Apply done.'
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
exit 0
