# WsaUpdater PowerShell helpers for WSABuilds update checks.
# Compatible with Windows PowerShell 5.1+ and PowerShell 7+.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WsaUpdaterConfigPath {
    if ($env:WSA_UPDATER_CONFIG -and (Test-Path -LiteralPath $env:WSA_UPDATER_CONFIG)) {
        return $env:WSA_UPDATER_CONFIG
    }
    if ($env:WSA_UPDATER_CONFIG) {
        return $env:WSA_UPDATER_CONFIG
    }
    $dir = Join-Path $env:APPDATA 'WsaUpdater'
    return (Join-Path $dir 'config.json')
}

function Get-WsaUpdaterDefaultConfig {
    return [ordered]@{
        repo               = 'MustardChef/WSABuilds'
        prefer_lts         = $true
        asset_pattern      = '(?i)WSA_.*_x64_.*GApps.*NoAmazon.*\.7z$'
        fallback_patterns  = @(
            '(?i)WSA_.*_x64_.*GApps.*\.7z$',
            '(?i)WSA_.*_x64_.*\.7z$'
        )
        wsa_install_dir    = 'C:\WSA'
        download_dir       = 'C:\WSA\_download'
        check_on_logon     = $true
        notify_on_up_to_date = $false
        last_release_tag   = ''
        last_asset_name    = ''
        last_check_utc     = ''
    }
}

function Read-WsaUpdaterConfig {
    param([string]$Path)
    if (-not $Path) { $Path = Get-WsaUpdaterConfigPath }
    $defaults = Get-WsaUpdaterDefaultConfig
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$defaults
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]$defaults
    }
    $obj = $raw | ConvertFrom-Json
    foreach ($k in $defaults.Keys) {
        if ($null -eq $obj.PSObject.Properties[$k]) {
            $obj | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k] -Force
        }
    }
    return $obj
}

function Save-WsaUpdaterConfig {
    param(
        [Parameter(Mandatory)]$Config,
        [string]$Path
    )
    if (-not $Path) { $Path = Get-WsaUpdaterConfigPath }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-GitHubApiHeaders {
    $headers = @{
        'User-Agent' = 'wsa-updater'
        'Accept'     = 'application/vnd.github+json'
    }
    if ($env:GITHUB_TOKEN) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }
    return $headers
}

function Get-WsabuildsReleases {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [int]$PerPage = 30
    )
    $uri = "https://api.github.com/repos/$Repo/releases?per_page=$PerPage"
    $headers = Get-GitHubApiHeaders
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '403|rate limit') {
            throw "GitHub API rate limited. Set GITHUB_TOKEN and retry. ($msg)"
        }
        throw "Failed to query GitHub releases for ${Repo}: $msg"
    }
    if ($resp -isnot [System.Array]) { $resp = @($resp) }
    return $resp
}

function Select-WsaRelease {
    param(
        [Parameter(Mandatory)][array]$Releases,
        [bool]$PreferLts = $true
    )
    $live = @($Releases | Where-Object { -not $_.draft })
    if (-not $live -or $live.Count -eq 0) { return $null }
    if ($PreferLts) {
        $lts = @($live | Where-Object {
            ($_.tag_name -match '(?i)lts') -or ($_.name -match '(?i)lts')
        })
        if ($lts.Count -gt 0) {
            return ($lts | Sort-Object { [datetime]$_.published_at } -Descending)[0]
        }
    }
    return ($live | Sort-Object { [datetime]$_.published_at } -Descending)[0]
}

function Select-WsaAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [string]$PrimaryPattern,
        [string[]]$FallbackPatterns = @()
    )
    $assets = @($Release.assets)
    if (-not $assets -or $assets.Count -eq 0) { return $null }
    $patterns = @()
    if ($PrimaryPattern) { $patterns += $PrimaryPattern }
    if ($FallbackPatterns) { $patterns += $FallbackPatterns }
    foreach ($pat in $patterns) {
        $hit = @($assets | Where-Object { $_.name -match $pat })
        if ($hit.Count -eq 0) { continue }
        $stable = @($hit | Where-Object { $_.name -notmatch '(?i)canary' })
        if ($stable.Count -gt 0) { $hit = $stable }
        return ($hit | Sort-Object size -Descending)[0]
    }
    return $null
}

function Get-InstalledWsaVersion {
    param([string]$InstallDir)
    try {
        $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
        if ($pkg) {
            return [pscustomobject]@{
                Version        = [string]$pkg.Version
                PackageFullName = [string]$pkg.PackageFullName
                Source         = 'appx'
            }
        }
    } catch { }

    if ($InstallDir -and (Test-Path -LiteralPath $InstallDir)) {
        $manifest = Join-Path $InstallDir 'AppxManifest.xml'
        if (Test-Path -LiteralPath $manifest) {
            try {
                [xml]$xml = Get-Content -LiteralPath $manifest -Encoding UTF8
                $ver = [string]$xml.Package.Identity.Version
                if ($ver) {
                    return [pscustomobject]@{
                        Version         = $ver
                        PackageFullName = ''
                        Source          = 'manifest'
                    }
                }
            } catch { }
        }
    }
    return [pscustomobject]@{ Version = $null; PackageFullName = ''; Source = 'none' }
}

function Get-WsaVersionFromAssetName {
    param([string]$Name)
    if ($Name -match 'WSA_(\d+\.\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Invoke-WsaUpdateCheck {
    param(
        $Config,
        [switch]$Quiet
    )
    if (-not $Config) { $Config = Read-WsaUpdaterConfig }

    $releases = Get-WsabuildsReleases -Repo $Config.repo
    $release = Select-WsaRelease -Releases $releases -PreferLts ([bool]$Config.prefer_lts)
    if (-not $release) {
        return [pscustomobject]@{
            ok              = $false
            error           = 'No published releases found'
            exit_code       = 3
            has_update      = $false
            release_tag     = $null
            asset_name      = $null
            asset_url       = $null
            asset_size      = $null
            asset_version   = $null
            installed_version = $null
            install_source  = 'none'
        }
    }

    $fallback = @()
    if ($Config.PSObject.Properties['fallback_patterns'] -and $Config.fallback_patterns) {
        $fallback = @($Config.fallback_patterns)
    }
    $asset = Select-WsaAsset -Release $release -PrimaryPattern $Config.asset_pattern -FallbackPatterns $fallback
    if (-not $asset) {
        $names = @($release.assets | ForEach-Object { $_.name }) -join ', '
        return [pscustomobject]@{
            ok                = $false
            error             = "No asset matched patterns. Available: $names"
            exit_code         = 3
            has_update        = $false
            release_tag       = [string]$release.tag_name
            asset_name        = $null
            asset_url         = $null
            asset_size        = $null
            asset_version     = $null
            installed_version = $null
            install_source    = 'none'
        }
    }

    $installed = Get-InstalledWsaVersion -InstallDir $Config.wsa_install_dir
    $assetVer = Get-WsaVersionFromAssetName -Name $asset.name
    $tag = [string]$release.tag_name

    $hasUpdate = $false
    $reason = 'up_to_date'
    $notify = $false

    if (-not $installed.Version) {
        $hasUpdate = $true
        $reason = 'no_local_wsa'
        $notify = -not ($Config.last_release_tag -eq $tag -and $Config.last_asset_name -eq $asset.name)
    } elseif ($assetVer -and ($installed.Version -eq $assetVer)) {
        # Already on this WSA build — never a false-positive "first seen" update.
        $hasUpdate = $false
        $reason = 'up_to_date'
        $notify = $false
    } elseif ($assetVer -and ($installed.Version -ne $assetVer)) {
        $hasUpdate = $true
        $reason = 'version_mismatch'
        # Notify once per release+asset until user installs that build.
        $notify = -not ($Config.last_release_tag -eq $tag -and $Config.last_asset_name -eq $asset.name)
    } elseif (-not $assetVer) {
        $hasUpdate = $true
        if ($Config.last_release_tag -eq $tag -and $Config.last_asset_name -eq $asset.name) {
            $reason = 'already_notified'
            $notify = $false
        } else {
            $reason = 'first_seen_release'
            $notify = $true
        }
    }

    $result = [pscustomobject]@{
        ok                = $true
        error             = $null
        exit_code         = 0
        has_update        = $hasUpdate
        should_notify     = $notify
        reason            = $reason
        release_tag       = $tag
        release_name      = [string]$release.name
        release_url       = [string]$release.html_url
        published_at      = [string]$release.published_at
        asset_name        = [string]$asset.name
        asset_url         = [string]$asset.browser_download_url
        asset_size        = [long]$asset.size
        asset_version     = $assetVer
        installed_version = $installed.Version
        install_source    = $installed.Source
        wsa_install_dir   = [string]$Config.wsa_install_dir
        download_dir      = [string]$Config.download_dir
    }
    return $result
}

function Show-WsaUpdateToast {
    param(
        [Parameter(Mandatory)]$Result
    )
    $title = if ($Result.has_update) { 'WSA update available' } else { 'WSA update check' }
    $lines = @()
    if ($Result.installed_version) {
        $lines += "Current: $($Result.installed_version)"
    } else {
        $lines += 'Current: No local WSA detected'
    }
    $lines += "New: $($Result.release_tag)"
    if ($Result.asset_version) { $lines += "Asset ver: $($Result.asset_version)" }
    $lines += "Asset: $($Result.asset_name)"
    $body = ($lines -join [Environment]::NewLine)
    $titleXml = [System.Security.SecurityElement]::Escape($title)
    $bodyXml = [System.Security.SecurityElement]::Escape($body)
    $urlXml = [System.Security.SecurityElement]::Escape([string]$Result.release_url)

    $shown = $false
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$titleXml</text>
      <text>$bodyXml</text>
    </binding>
  </visual>
  <actions>
    <action content="Open Releases" activationType="protocol" arguments="$urlXml"/>
  </actions>
</toast>
"@
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Windows PowerShell')
        $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
        $notifier.Show($toast)
        $shown = $true
    } catch {
        Write-Verbose "Toast failed: $($_.Exception.Message)"
    }

    if (-not $shown) {
        $caption = $title
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show($body, $caption, 'OK', 'Information') | Out-Null
        } catch {
            Write-Host "[$title]"
            Write-Host $body
        }
    }
}

function Start-WsaAssetDownload {
    param(
        [Parameter(Mandatory)]$Result,
        [string]$DownloadDir
    )
    if (-not $DownloadDir) { $DownloadDir = $Result.download_dir }
    if (-not $DownloadDir) { $DownloadDir = 'C:\WSA\_download' }
    if (-not (Test-Path -LiteralPath $DownloadDir)) {
        New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    }
    $dest = Join-Path $DownloadDir $Result.asset_name
    $partial = "$dest.partial"
    $url = $Result.asset_url

    Write-Host "Downloading $($Result.asset_name) ..."
    Write-Host "  -> $dest"
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source -L --fail --retry 4 --retry-delay 3 -C - -o $partial $url
        if ($LASTEXITCODE -ne 0) {
            throw "curl download failed with exit $LASTEXITCODE"
        }
    } else {
        $ProgressPreference = 'SilentlyContinue'
        $resumeFrom = 0
        if (Test-Path -LiteralPath $partial) {
            $resumeFrom = (Get-Item -LiteralPath $partial).Length
        }
        $headers = @{ 'User-Agent' = 'wsa-updater' }
        if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
        if ($resumeFrom -gt 0) {
            $headers['Range'] = "bytes=$resumeFrom-"
            try {
                Invoke-WebRequest -Uri $url -OutFile $partial -Headers $headers -UseBasicParsing -MaximumRedirection 10
            } catch {
                # Server may not honor Range; restart full download.
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                Invoke-WebRequest -Uri $url -OutFile $partial -Headers @{ 'User-Agent' = 'wsa-updater' } -UseBasicParsing
            }
        } else {
            Invoke-WebRequest -Uri $url -OutFile $partial -Headers $headers -UseBasicParsing
        }
    }
    Move-Item -LiteralPath $partial -Destination $dest -Force
    $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower()
    Write-Host "SHA256: $hash"
    Write-Host "Done. Extract and merge into your WSA install dir manually (or follow README update steps)."
    return $dest
}

Export-ModuleMember -Function @(
    'Get-WsaUpdaterConfigPath',
    'Get-WsaUpdaterDefaultConfig',
    'Read-WsaUpdaterConfig',
    'Save-WsaUpdaterConfig',
    'Get-WsabuildsReleases',
    'Select-WsaRelease',
    'Select-WsaAsset',
    'Get-InstalledWsaVersion',
    'Get-WsaVersionFromAssetName',
    'Invoke-WsaUpdateCheck',
    'Show-WsaUpdateToast',
    'Start-WsaAssetDownload'
)
