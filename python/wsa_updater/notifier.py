from __future__ import annotations

import subprocess
import sys
from typing import Any, Dict


def _ps_quote(s: str) -> str:
    return "'" + str(s).replace("'", "''") + "'"


def notify(result: Dict[str, Any]) -> bool:
    """Show toast via PowerShell helper; fall back to console."""
    if not result.get("ok"):
        return False
    title = "WSA 有可用更新" if result.get("has_update") else "WSA 更新检查"
    lines = []
    inst = result.get("installed_version") or "未检测到已安装 WSA"
    lines.append(f"当前: {inst}")
    lines.append(f"新版本: {result.get('release_tag')}")
    if result.get("asset_version"):
        lines.append(f"包版本: {result.get('asset_version')}")
    lines.append(f"资源: {result.get('asset_name')}")
    body = "\\n".join(lines)

    ps = f"""
$title = {_ps_quote(title)}
$body = {_ps_quote(body)}
try {{
  $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $xml = "<toast><visual><binding template='ToastGeneric'><text>$title</text><text>$($body -replace "`n", ' | ')</text></binding></visual></toast>"
  $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
  $doc.LoadXml($xml)
  $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Windows PowerShell')
  $notifier.Show([Windows.UI.Notifications.ToastNotification]::new($doc))
}} catch {{
  Write-Host $title
  Write-Host $body
}}
"""
    if sys.platform != "win32":
        print(title)
        print(body.replace("\\n", "\n"))
        return False
    proc = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps],
        check=False,
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0
