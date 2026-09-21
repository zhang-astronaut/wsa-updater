---
feature: wsa-updater
status: delivered
updated: 2026-09-21
branch: main
commits: 8b03787..2523105
---

# WSA Updater (portable WSABuilds update checker)

## Report

**What was built** - Multi-machine Windows tool to check **WSABuilds / WSA** updates (PowerShell module + equivalent Python CLI). Default preference: **x64 + GApps + NoAmazon**, prefer **LTS** releases. Logon scheduled task `WsaUpdater-CheckOnLogon` auto-checks; **Toast / MessageBox** notifies on update (once per release+asset); **one-click download only** - never silently overwrites or registers WSA. Portable config (`%APPDATA%\WsaUpdater\config.json` or `WSA_UPDATER_CONFIG`).

**Verification** - PowerShell 5.1 parse all scripts PASS; `tests/run_tests.py` **9/9 PASS** (version-equal never false-positives; mismatch notifies once; no-local-WSA path). Live on this PC: installed `2407.40000.4.0`, asset `WSA_...GApps-13.0-NoAmazon.7z`, empty `last_*` -> `has_update=false reason=up_to_date should_notify=false`. Two review rounds: critical false-positive fixed; non-curl resume majors fixed (PS Range via sidecar+append; Python requires 206/Content-Range else full redownload).

**Journey log**
- PS 5.1 needs UTF-8 **BOM** or parsers fail on non-ASCII.
- Equal installed/asset version must be `up_to_date` even when `last_release_tag` is empty.
- `Invoke-WebRequest -OutFile` never Range-appends; write sidecar then concatenate.
- Prefer `GApps-*NoAmazon` but exclude **canary** names when multiple match.
- Updating WSA still requires admin Appx register; this tool only detects and downloads.

## [S1] Problem

User installs real WSA via **WSABuilds LTS** (default **GApps + NoAmazon**, often `C:\WSA`). Official Store WSA is EOL (2025-03-05). Need a **portable** tool that: (1) checks for newer WSABuilds on every logon; (2) **popup-notifies** when an update exists; (3) does **not** silently change WSA; (4) supports **one-click download** after user confirms; (5) works when cloned to another Windows PC.

## [S2] Design

### 2.1 Product shape (settled)

| Layer | Content |
|---|---|
| PowerShell | Primary: check, notify, download, scheduled task, config |
| Python | Peer CLI: `python -m wsa_updater check|download|install-task` |
| Distribution | Public GitHub `zhang-astronaut/wsa-updater` |

### 2.2 Update source contract

- Repo: `MustardChef/WSABuilds`
- API: `GET https://api.github.com/repos/MustardChef/WSABuilds/releases`
- Prefer LTS tag/name; else newest non-draft
- Asset regex default: `(?i)WSA_.*_x64_.*GApps.*NoAmazon.*\.7z$` with fallbacks for GApps then any x64 `.7z`
- Prefer non-canary names among matches; then largest size
- Compare installed Appx/manifest version to version parsed from asset `WSA_(\d+\.\d+\.\d+\.\d+)`
- Notify once per release+asset via `last_release_tag` + `last_asset_name`

### 2.3 Local state

Config JSON default `%APPDATA%\WsaUpdater\config.json`; override `WSA_UPDATER_CONFIG`. Keys: `repo`, `prefer_lts`, `asset_pattern`, `fallback_patterns`, `wsa_install_dir`, `download_dir`, `check_on_logon`, `notify_on_up_to_date`, `last_release_tag`, `last_asset_name`, `last_check_utc`.

### 2.4 Version probe

1. `Get-AppxPackage MicrosoftCorporationII.WindowsSubsystemForAndroid` (PS) / AppModel package registry (Python)
2. Else `wsa_install_dir\AppxManifest.xml` Identity Version
3. Else null

Decision: equal versions -> `up_to_date` (never first-seen false positive); mismatch -> `has_update` + `should_notify` unless already notified; no local WSA -> update available once per tag+asset.

### 2.5 Notification

Toast via Windows.UI.Notifications; MessageBox/console fallback. Body: current version, release tag, asset version/name. **Default never auto-installs.**

### 2.6 Logon check

Task `WsaUpdater-CheckOnLogon`, AtLogOn, runs `Check-WsaUpdate.ps1 -Quiet`. Respects `check_on_logon=false` at install time. `Uninstall-WsaUpdater.ps1` removes it.

### 2.7 Portability

Config-driven paths; optional `GITHUB_TOKEN`; Python 3.9+ stdlib only; PS 5.1+ / pwsh.

### 2.8 Errors

Network/API -> exit 2 + token hint; no matching asset -> exit 3 + asset list; download uses curl `-C -` or Range sidecar/206-safe urllib fallback.

## [S3] Out of Scope

- No silent install: apply only after explicit `-ConfirmInstall` + user confirm/`-Yes`
- No non-WSABuilds mirrors
- No full GUI settings app
- Host OS target is Windows (WSA users)

## Tasks

- [x] T1: Repo layout + README/config.sample — acceptance: structure and sample config exist (covers: S2.1; S2.3; S2.7)
- [x] T2: PowerShell check core — acceptance: live JSON from `Check-WsaUpdate.ps1` (covers: S2.2; S2.4)
- [x] T3: PowerShell notify + download-only — acceptance: toast path; `Update-Wsa.ps1 -DownloadOnly` (covers: S2.5)
- [x] T4: Scheduled task install/uninstall — acceptance: scripts parse; documented (covers: S2.6)
- [x] T5: Python CLI peer — acceptance: `python -m wsa_updater check` works (covers: S2.1; S2.2)
- [x] T6: Tests + live verify — acceptance: `tests/run_tests.py` pass; live check output (covers: S2.2; S2.4; S2.8)
- [x] T7: Independent review — acceptance: no critical; majors fixed (covers: S2)
- [x] T8: Public GitHub push — acceptance: https://github.com/zhang-astronaut/wsa-updater accessible (covers: S2.1)