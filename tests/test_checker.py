from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from wsa_updater.checker import (  # noqa: E402
    default_config,
    select_asset,
    select_release,
    version_from_asset_name,
)


SAMPLE_RELEASES = [
    {
        "draft": False,
        "tag_name": "Windows_11_2407.40000.4.0_LTS_8",
        "name": "WSABuilds LTS Build #8",
        "published_at": "2026-09-04T11:30:29Z",
        "html_url": "https://example.invalid/lts8",
        "assets": [
            {
                "name": "WSA_2407.40000.4.0_x64_Release-Nightly-NoGApps-NoAmazon.7z",
                "browser_download_url": "https://example.invalid/nogapps.7z",
                "size": 554029377,
            },
            {
                "name": "WSA_2407.40000.4.0_x64_Release-Nightly-GApps-13.0-NoAmazon.7z",
                "browser_download_url": "https://example.invalid/gapps.7z",
                "size": 747382721,
            },
            {
                "name": "WSA_2407.40000.4.0_x64_Release-Nightly-GApps-13.0.7z",
                "browser_download_url": "https://example.invalid/gapps-amz.7z",
                "size": 776269963,
            },
        ],
    },
    {
        "draft": False,
        "tag_name": "Windows_11_something",
        "name": "Non-LTS older",
        "published_at": "2025-06-02T00:00:00Z",
        "html_url": "https://example.invalid/old",
        "assets": [
            {
                "name": "WSA_2300.0.0_x64_Release-Nightly-GApps-13.0-NoAmazon.7z",
                "browser_download_url": "https://example.invalid/old-gapps.7z",
                "size": 1,
            }
        ],
    },
]


def test_prefer_lts_release():
    rel = select_release(SAMPLE_RELEASES, prefer_lts=True)
    assert rel is not None
    assert "LTS" in rel["tag_name"]


def test_select_gapps_noamazon_asset():
    rel = select_release(SAMPLE_RELEASES, prefer_lts=True)
    assert rel is not None
    cfg = default_config()
    asset = select_asset(rel, cfg["asset_pattern"], cfg["fallback_patterns"])
    assert asset is not None
    assert "GApps" in asset["name"]
    assert "NoAmazon" in asset["name"]


def test_fallback_to_any_gapps_when_pattern_missing_noamazon():
    rel = {
        "assets": [
            {
                "name": "WSA_2407.40000.4.0_x64_Release-Nightly-GApps-13.0.7z",
                "browser_download_url": "u",
                "size": 10,
            }
        ]
    }
    cfg = default_config()
    asset = select_asset(rel, cfg["asset_pattern"], cfg["fallback_patterns"])
    assert asset is not None
    assert "GApps" in asset["name"]


def test_version_from_asset_name():
    assert (
        version_from_asset_name("WSA_2407.40000.4.0_x64_Release-Nightly-GApps-13.0-NoAmazon.7z")
        == "2407.40000.4.0"
    )
    assert version_from_asset_name("not-a-wsa.zip") is None


def test_default_config_json_roundtrip():
    cfg = default_config()
    text = json.dumps(cfg)
    data = json.loads(text)
    assert data["repo"] == "MustardChef/WSABuilds"
    assert "GApps" in data["asset_pattern"]
