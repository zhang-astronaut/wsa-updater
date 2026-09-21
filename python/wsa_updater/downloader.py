from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.request import Request, urlopen


def download_asset(result: Dict[str, Any], download_dir: Optional[str] = None) -> Path:
    url = result.get("asset_url")
    name = result.get("asset_name")
    if not url or not name:
        raise ValueError("result missing asset_url/asset_name")
    out_dir = Path(download_dir or result.get("download_dir") or r"C:\WSA\_download")
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / str(name)
    partial = Path(str(dest) + ".partial")

    # Prefer curl for resume on Windows.
    curl = None
    for candidate in ("curl.exe", "curl"):
        from shutil import which

        curl = which(candidate)
        if curl:
            break
    if curl:
        proc = subprocess.run(
            [curl, "-L", "--fail", "--retry", "4", "--retry-delay", "3", "-C", "-", "-o", str(partial), str(url)],
            check=False,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"curl download failed exit={proc.returncode}")
    else:
        headers = {"User-Agent": "wsa-updater"}
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        resume_from = partial.stat().st_size if partial.exists() else 0
        if resume_from > 0:
            headers["Range"] = f"bytes={resume_from}-"
        try:
            req = Request(str(url), headers=headers, method="GET")
            with urlopen(req, timeout=120) as resp:
                status = getattr(resp, "status", None) or resp.getcode()
                content_range = resp.headers.get("Content-Range") if resp.headers else None
                if resume_from > 0:
                    if status != 206 and not content_range:
                        # Full body despite Range — restart from zero
                        resume_from = 0
                        headers.pop("Range", None)
                        resp.close()
                        req2 = Request(str(url), headers=headers, method="GET")
                        with urlopen(req2, timeout=120) as resp2, open(partial, "wb") as fh:
                            while True:
                                chunk = resp2.read(1024 * 256)
                                if not chunk:
                                    break
                                fh.write(chunk)
                    else:
                        with open(partial, "ab") as fh:
                            while True:
                                chunk = resp.read(1024 * 256)
                                if not chunk:
                                    break
                                fh.write(chunk)
                else:
                    with open(partial, "wb") as fh:
                        while True:
                            chunk = resp.read(1024 * 256)
                            if not chunk:
                                break
                            fh.write(chunk)
        except Exception:
            if partial.exists():
                try:
                    partial.unlink()
                except OSError:
                    pass
            req = Request(str(url), headers={"User-Agent": "wsa-updater"}, method="GET")
            if token:
                req.add_header("Authorization", f"Bearer {token}")
            with urlopen(req, timeout=120) as resp, open(partial, "wb") as fh:
                while True:
                    chunk = resp.read(1024 * 256)
                    if not chunk:
                        break
                    fh.write(chunk)

    partial.replace(dest)
    return dest
