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
    title = "WSA update available" if result.get("has_update") else "WSA update check"
    inst = result.get("installed_version") or "No local WSA detected"
    lines: list[str] = []
    lines.append(f"Current: {inst}")
    lines.append(f"New: {result.get('release_tag')}")
    if result.get("asset_version"):
        lines.append(f"Asset ver: {result.get('asset_version')}")
    lines.append(f"Asset: {result.get('asset_name')}")
    body = "\n".join(lines)

    body_ps = body.replace("`", "``").replace("'", "''")
    title_ps = title.replace("'", "''")
    body_oneline = body.replace("\n", " | ").replace("'", "''")

    ps = f"""
$title = '{title_ps}'
$body = '{body_oneline}'
try {{
  $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $xml = "<toast><visual><binding template='ToastGeneric'><text>$title</text><text>$body</text></binding></visual></toast>"
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
        print(body)
        return False
    proc = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps],
        check=False,
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0
