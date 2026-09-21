---
feature: wsa-updater
status: designed
updated: 2026-09-21
branch: feat/initial-wsa-updater
commits: 
---

# WSA Updater（可分发更新检查器）

## Report

## [S1] Problem

用户在 Windows 上通过 **WSABuilds（LTS）** 侧载安装了真正的 WSA（默认 **GApps + NoAmazon** 变体，目录常为 `C:\WSA`）。官方 Store 已 EOL，WSA 更新只能靠盯 GitHub Releases。需要一款 **换机可用** 的工具：

1. **每次开机自动检查**是否有更新的 WSABuilds 构建；
2. **有更新时弹窗提醒**（Windows Toast / 对话框）；
3. **不静默改动 WSA**；用户确认后 **一键下载** 对应资源包；
4. 可 **克隆到另一台 Windows 机器** 即用（配置可移植）。

## [S2] Design

### 2.1 产品形态（已定）

| 层 | 内容 |
|---|---|
| PowerShell | 主实现：检查、通知、下载、注册 Scheduled Task、配置管理 |
| Python | 同等核心 CLI：`python -m wsa_updater check|download|install-task`，便于脚本化/打包 exe |
| 分发 | 公开 GitHub 仓库 `zhang-astronaut/wsa-updater`，解压/克隆即可用 |

### 2.2 更新源契约

- 仓库：`MustardChef/WSABuilds`
- API：`GET https://api.github.com/repos/MustardChef/WSABuilds/releases`（或 `/releases/latest`）
- 选择规则（可配置）：
  1. 优先 tag/name 含 `LTS` 的 release（按 published_at 最新）；
  2. 否则最新非 draft release；
  3. 在 assets 中按 **正则** 匹配包，默认偏好：  
     `(?i)WSA_.*_x64_.*GApps.*NoAmazon.*\.7z$`  
     （不匹配则回退 `(?i)WSA_.*_x64_.*GApps.*\.7z$`，再回退 `(?i)WSA_.*_x64_.*\.7z$`）
- 比较字段：release 的 `name`/`tag_name` 与本地记录的 `last_seen` / 已安装版本字符串；无本地 WSA 时仅提示「发现可用构建」。

### 2.3 本地状态

配置文件（JSON，默认 `%APPDATA%\WsaUpdater\config.json`，可用 `WSA_UPDATER_CONFIG` 覆盖）：

```json
{
  "repo": "MustardChef/WSABuilds",
  "prefer_lts": true,
  "asset_pattern": "(?i)WSA_.*_x64_.*GApps.*NoAmazon.*\\.7z$",
  "fallback_patterns": ["(?i)WSA_.*_x64_.*GApps.*\\.7z$", "(?i)WSA_.*_x64_.*\\.7z$"],
  "wsa_install_dir": "C:\\WSA",
  "download_dir": "C:\\WSA\\_download",
  "check_on_logon": true,
  "notify_on_up_to_date": false,
  "last_release_tag": "",
  "last_asset_name": "",
  "last_check_utc": ""
}
```

### 2.4 版本探测

优先级：

1. `Get-AppxPackage MicrosoftCorporationII.WindowsSubsystemForAndroid` → `Version` / `PackageFullName`；
2. 否则读 `wsa_install_dir` 下 `AppxManifest.xml` 的 `Identity@Version`；
3. 否则 `installed = null`。

与 GitHub 上 asset/release 标签比较时：允许「tag 相同但用户未确认下载」仍提醒一次（以 `last_release_tag` 去重）；`installed` 版本与 release 中 WSA 版本号（从 asset 名解析 `WSA_(\d+\.\d+\.\d+\.\d+)`）比较。

### 2.5 通知

1. **Toast**（Windows 10/11）：`Windows.UI.Notifications.ToastNotificationManager` + 简单 XML toast，AppId 使用注册表/协议回退 `Windows PowerShell` 或自定义 AUMID；
2. 失败则 **WPF/WinForms MessageBox** 或 `msg` 回退；
3. 文案：当前版本 / 新版本 tag / 目标 asset 名 / 操作指引。

Toast 按钮或弹窗后的下一步由 CLI 提供：

```powershell
Check-WsaUpdate.ps1          # 检查+通知
Update-Wsa.ps1 -DownloadOnly # 一键下载到 download_dir
```

**默认不自动安装。** `-DownloadOnly` 为推荐交付行为。

### 2.6 开机检查

`Install-WsaUpdater.ps1` 创建计划任务：

- 名称：`WsaUpdater-CheckOnLogon`
- 触发：用户登录（`AtLogOn`）
- 操作：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File <repo>\powershell\Check-WsaUpdate.ps1 -Quiet`
- 可用 `Uninstall-WsaUpdater.ps1` 删除。

### 2.7 可移植性

- 不在安装路径写死盘符以外的机器特定内容；`wsa_install_dir`/`download_dir` 可改；
- GitHub API 匿名访问即可（可选 `GITHUB_TOKEN` 提高限流）；
- 依赖：Windows PowerShell 5.1+ 或 pwsh；Python 3.9+（仅使用 stdlib：`urllib`/`json`/`re`/`subprocess`）；
- 仓库内含 `config.sample.json`、`README.md`（中英可中文为主）。

### 2.8 错误行为

| 情况 | 行为 |
|---|---|
| 网络失败 | 退出码 2，stderr 说明；`-Quiet` 时不弹窗 |
| API 限流 | 提示可选设置 `GITHUB_TOKEN` |
| 无匹配 asset | 退出码 3，列出该 release assets 供排查 |
| 下载中断 | 保留 `.partial`，重试续传（curl `-C -` 或 Python Range） |
| 本机无 WSA | 仍可检查并提醒「可安装构建」 |

## [S3] Out of Scope

- 不自动 `Add-AppxPackage` 注册 / 不自动覆盖 `C:\WSA`（避免静默弄坏运行中的 WSA）；
- 不抓取非 WSABuilds 的第三方镜像；
- 不做完整 GUI 设置中心；
- 不支持 macOS/Linux 宿主机（目标是 Windows 上的 WSA 用户）。

## Tasks

- [ ] T1: 初始化仓库结构与 README/config.sample — acceptance: 目录与示例配置存在（covers: S2.1; S2.3; S2.7）
- [ ] T2: PowerShell 核心：读配置、查 GitHub、匹配 asset、比较版本 — acceptance: `Check-WsaUpdate.ps1` 在本机跑通并输出 JSON 结果（covers: S2.2; S2.4）
- [ ] T3: PowerShell 通知 + 一键下载 — acceptance: 有更新时可 toast/回退弹窗；`Update-Wsa.ps1 -DownloadOnly` 可下载 asset（covers: S2.5）
- [ ] T4: 计划任务安装/卸载脚本 — acceptance: Install/Uninstall 脚本语法正确，文档说明注册步骤（covers: S2.6）
- [ ] T5: Python CLI 对等实现 — acceptance: `python -m wsa_updater check` 与 PowerShell 同源规则可运行（covers: S2.1; S2.2）
- [ ] T6: 测试与本机验证 — acceptance: pytest/语法检查通过；本机 check 有真实输出（covers: S2.2; S2.4; S2.8）
- [ ] T7: 独立复核 — acceptance: 无 critical；major 已修（covers: S2）
- [ ] T8: 创建 GitHub 公开仓库并推送 — acceptance: `zhang-astronaut/wsa-updater` 可访问（covers: S2.1）
