# wsa-updater

在 Windows 上检查 **WSABuilds**（真正的 Windows Subsystem for Android 构建）是否有更新：**开机自动检查 + 弹窗提醒 + 一键下载**。默认偏好 **GApps / NoAmazon** 变体。

> 官方 Microsoft Store 的 WSA 已于 2025-03-05 停止支持。本工具盯的是社区维护的 [MustardChef/WSABuilds](https://github.com/MustardChef/WSABuilds) Releases。

## 功能

| 功能 | 说明 |
|------|------|
| 检查更新 | 读取 GitHub Releases，优先 **LTS**，按正则匹配 x64 GApps 包 |
| 弹窗提醒 | Windows Toast；失败时回退 MessageBox |
| 开机检查 | 计划任务 `WsaUpdater-CheckOnLogon`，登录时运行 |
| 一键下载 | 只下载 `.7z` 到指定目录，**不静默覆盖/注册 WSA** |
| 可分发 | 克隆到另一台 Windows 机器即可；配置在 `%APPDATA%\WsaUpdater\config.json` |

## 快速开始（PowerShell）

```powershell
git clone https://github.com/zhang-astronaut/wsa-updater.git
cd wsa-updater\powershell

# 生成配置（可选，首次运行会自动用默认值）
# 可复制仓库根目录 config.sample.json 到 %APPDATA%\WsaUpdater\config.json

# 手动检查（有更新会 Toast）
.\Check-WsaUpdate.ps1

# 机器可读输出
.\Check-WsaUpdate.ps1 -Json

# 注册开机登录检查
.\Install-WsaUpdater.ps1

# 发现更新后：仅下载
.\Update-Wsa.ps1 -DownloadOnly
```

卸载计划任务：

```powershell
.\Uninstall-WsaUpdater.ps1
```

## 快速开始（Python）

```powershell
cd wsa-updater\python
# 可选：pip install -e .
$env:PYTHONPATH = "$PWD"
python -m wsa_updater init-config
python -m wsa_updater check
python -m wsa_updater check --json
python -m wsa_updater download --download-only
python -m wsa_updater install-task
python -m wsa_updater uninstall-task
```

Python 3.9+，**仅标准库**。可选 `GITHUB_TOKEN` 环境变量避免 API 限流。

## 配置

默认路径：`%APPDATA%\WsaUpdater\config.json`  
也可用环境变量 `WSA_UPDATER_CONFIG` 指向其它文件（便于多机同步同一配置）。

见仓库根目录 [`config.sample.json`](config.sample.json)。

常用字段：

- `asset_pattern`：默认匹配 GApps + NoAmazon + x64 + `.7z`
- `wsa_install_dir`：本机 WSA 解压注册目录（默认 `C:\WSA`）
- `download_dir`：下载保存位置
- `prefer_lts`：优先 LTS release
- `notify_on_up_to_date`：已是最新时是否也弹窗

## 更新 WSA 时请手动完成（本工具不自动装）

1. 运行 `Update-Wsa.ps1 -DownloadOnly` 得到 `.7z`
2. 备份 `%LOCALAPPDATA%\Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\LocalCache\userdata*.vhdx`
3. 停止 WSA 进程
4. 解压并**合并覆盖**到 `wsa_install_dir`（务必更新 `Tools\initrd.img` 等）
5. 管理员运行目录中的 `Run.bat` / `Install.ps1` 重新注册
6. `adb connect 127.0.0.1:58526` 验收，确认 `com.android.vending` 仍在（GApps 构建）

## 测试

```powershell
cd wsa-updater
# PowerShell 语法
powershell -NoProfile -Command "Get-ChildItem powershell\*.ps1,powershell\*.psm1 | ForEach-Object { $errs=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$errs); if($errs){$errs; exit 1} }; 'PS_PARSE_OK'"

# Python 单测（无需 pytest）
$py = $env:MIMO_PYTHON; if (-not $py) { $py = 'python' }
$env:PYTHONPATH = "$PWD\python"
& $py tests\run_tests.py
```

可选：`pip install pytest` 后也可用 `pytest tests -q`。

## 换机使用

1. 克隆或下载本仓库到新机器
2. 按需修改 `config.json`（安装目录、下载目录、asset 正则）
3. `Install-WsaUpdater.ps1` 注册开机检查
4. 需要时设置 `GITHUB_TOKEN`

## 免责声明

- WSABuilds / WSA 已无微软官方支持，自行承担侧载与 Root 风险。
- 本工具默认**不**自动改系统上的 WSA 包。

## License

MIT
