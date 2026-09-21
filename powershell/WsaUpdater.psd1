@{
    RootModule        = 'WsaUpdater.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7c2e1a4-9f3d-4e2a-8c1b-5d6a7e8f9012'
    Author            = 'zhang-astronaut'
    CompanyName       = 'community'
    Copyright         = '(c) 2026 wsa-updater contributors'
    Description       = 'Check WSABuilds (WSA) updates on Windows, notify on logon, download assets on demand.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('WSA', 'WSABuilds', 'Android', 'Windows', 'Updater')
            ProjectUri = 'https://github.com/zhang-astronaut/wsa-updater'
        }
    }
}
