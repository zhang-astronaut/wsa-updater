from __future__ import annotations

import json
import os
import re
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_CONFIG: Dict[str, Any] = {
    "repo": "MustardChef/WSABuilds",
    "prefer_lts": True,
    "asset_pattern": r"(?i)WSA_.*_x64_.*GApps.*NoAmazon.*\.7z$",
    "fallback_patterns": [
        r"(?i)WSA_.*_x64_.*GApps.*\.7z$",
        r"(?i)WSA_.*_x64_.*\.7z$",
    ],
    "wsa_install_dir": r"C:\WSA",
    "download_dir": r"C:\WSA\_download",
    "check_on_logon": True,
    "notify_on_up_to_date": False,
    "last_release_tag": "",
    "last_asset_name": "",
    "last_check_utc": "",
}


def config_path() -> Path:
    env = os.environ.get("WSA_UPDATER_CONFIG")
    if env:
        return Path(env)
    appdata = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
    return Path(appdata) / "WsaUpdater" / "config.json"


def default_config() -> Dict[str, Any]:
    return deepcopy(DEFAULT_CONFIG)


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    path = path or config_path()
    cfg = default_config()
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                cfg.update(data)
        except (OSError, json.JSONDecodeError):
            pass
    return cfg


def save_config(cfg: Dict[str, Any], path: Optional[Path] = None) -> Path:
    path = path or config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def _github_headers() -> Dict[str, str]:
    headers = {
        "User-Agent": "wsa-updater",
        "Accept": "application/vnd.github+json",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def fetch_releases(repo: str, per_page: int = 30) -> List[Dict[str, Any]]:
    url = f"https://api.github.com/repos/{repo}/releases?per_page={per_page}"
    req = Request(url, headers=_github_headers(), method="GET")
    try:
        with urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except HTTPError as exc:
        if exc.code == 403:
            raise RuntimeError("GitHub API rate limited. Set GITHUB_TOKEN and retry.") from exc
        raise RuntimeError(f"GitHub API HTTP {exc.code}: {exc.reason}") from exc
    except URLError as exc:
        raise RuntimeError(f"Network error querying GitHub: {exc.reason}") from exc
    if not isinstance(payload, list):
        payload = [payload]
    return payload


def select_release(releases: List[Dict[str, Any]], prefer_lts: bool = True) -> Optional[Dict[str, Any]]:
    live = [r for r in releases if not r.get("draft")]
    if not live:
        return None

    def _ts(r: Dict[str, Any]) -> str:
        return str(r.get("published_at") or "")

    if prefer_lts:
        lts = [
            r
            for r in live
            if re.search(r"lts", str(r.get("tag_name") or ""), re.I)
            or re.search(r"lts", str(r.get("name") or ""), re.I)
        ]
        if lts:
            return sorted(lts, key=_ts, reverse=True)[0]
    return sorted(live, key=_ts, reverse=True)[0]


def select_asset(
    release: Dict[str, Any],
    primary_pattern: str,
    fallback_patterns: Optional[List[str]] = None,
) -> Optional[Dict[str, Any]]:
    assets = list(release.get("assets") or [])
    if not assets:
        return None
    patterns: List[str] = []
    if primary_pattern:
        patterns.append(primary_pattern)
    if fallback_patterns:
        patterns.extend(fallback_patterns)
    for pat in patterns:
        hits = [a for a in assets if re.search(pat, str(a.get("name") or ""))]
        if not hits:
            continue
        stable = [a for a in hits if not re.search(r"canary", str(a.get("name") or ""), re.I)]
        if stable:
            hits = stable
        return sorted(hits, key=lambda a: int(a.get("size") or 0), reverse=True)[0]
    return None


def version_from_asset_name(name: str) -> Optional[str]:
    m = re.search(r"WSA_(\d+\.\d+\.\d+\.\d+)", name or "")
    return m.group(1) if m else None


def _read_manifest_version(install_dir: str) -> Optional[str]:
    if not install_dir:
        return None
    manifest = Path(install_dir) / "AppxManifest.xml"
    if not manifest.is_file():
        return None
    try:
        text = manifest.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    m = re.search(r'Version\s*=\s*"(\d+\.\d+\.\d+\.\d+)"', text)
    return m.group(1) if m else None


def get_installed_wsa_version(install_dir: str) -> Dict[str, Any]:
    pkg_name = "MicrosoftCorporationII.WindowsSubsystemForAndroid"
    if os.name == "nt":
        try:
            import winreg

            key_path = r"SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages"
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key_path) as key:
                i = 0
                while True:
                    try:
                        name = winreg.EnumKey(key, i)
                    except OSError:
                        break
                    i += 1
                    if name.startswith(pkg_name + "_"):
                        parts = name.split("_")
                        if len(parts) >= 2:
                            return {"version": parts[1], "package_full_name": name, "source": "appx"}
        except Exception:
            pass

    ver = _read_manifest_version(install_dir)
    if ver:
        return {"version": ver, "package_full_name": "", "source": "manifest"}
    return {"version": None, "package_full_name": "", "source": "none"}


def check_updates(cfg: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    if cfg is None:
        cfg = load_config()
    releases = fetch_releases(str(cfg.get("repo") or "MustardChef/WSABuilds"))
    release = select_release(releases, prefer_lts=bool(cfg.get("prefer_lts", True)))
    if not release:
        return {
            "ok": False,
            "error": "No published releases found",
            "exit_code": 3,
            "has_update": False,
        }

    fallback = list(cfg.get("fallback_patterns") or [])
    asset = select_asset(release, str(cfg.get("asset_pattern") or ""), fallback)
    if not asset:
        names = ", ".join(str(a.get("name") or "") for a in (release.get("assets") or []))
        return {
            "ok": False,
            "error": f"No asset matched patterns. Available: {names}",
            "exit_code": 3,
            "has_update": False,
            "release_tag": release.get("tag_name"),
        }

    installed = get_installed_wsa_version(str(cfg.get("wsa_install_dir") or ""))
    asset_ver = version_from_asset_name(str(asset.get("name") or ""))
    tag = str(release.get("tag_name") or "")

    has_update = False
    should_notify = False
    reason = "up_to_date"
    if not installed.get("version"):
        has_update = True
        reason = "no_local_wsa"
        should_notify = not (
            str(cfg.get("last_release_tag") or "") == tag
            and str(cfg.get("last_asset_name") or "") == str(asset.get("name") or "")
        )
    elif asset_ver and installed.get("version") == asset_ver:
        has_update = False
        reason = "up_to_date"
        should_notify = False
    elif asset_ver and installed.get("version") != asset_ver:
        has_update = True
        reason = "version_mismatch"
        should_notify = not (
            str(cfg.get("last_release_tag") or "") == tag
            and str(cfg.get("last_asset_name") or "") == str(asset.get("name") or "")
        )
    else:
        has_update = True
        if (
            str(cfg.get("last_release_tag") or "") == tag
            and str(cfg.get("last_asset_name") or "") == str(asset.get("name") or "")
        ):
            reason = "already_notified"
            should_notify = False
        else:
            reason = "first_seen_release"
            should_notify = True

    return {
        "ok": True,
        "error": None,
        "exit_code": 0,
        "has_update": has_update,
        "should_notify": should_notify,
        "reason": reason,
        "release_tag": tag,
        "release_name": release.get("name"),
        "release_url": release.get("html_url"),
        "published_at": release.get("published_at"),
        "asset_name": asset.get("name"),
        "asset_url": asset.get("browser_download_url"),
        "asset_size": asset.get("size"),
        "asset_version": asset_ver,
        "installed_version": installed.get("version"),
        "install_source": installed.get("source"),
        "wsa_install_dir": cfg.get("wsa_install_dir"),
        "download_dir": cfg.get("download_dir"),
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
    }


def persist_check_result(cfg: Dict[str, Any], result: Dict[str, Any]) -> Dict[str, Any]:
    cfg = dict(cfg)
    cfg["last_check_utc"] = datetime.now(timezone.utc).isoformat()
    if result.get("ok"):
        cfg["last_release_tag"] = result.get("release_tag") or cfg.get("last_release_tag") or ""
        if result.get("asset_name"):
            cfg["last_asset_name"] = result.get("asset_name")
    return cfg
