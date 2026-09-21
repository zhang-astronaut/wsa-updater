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


def test_decision_no_false_positive_when_versions_match(monkeypatch=None):
    """Installed version equal to asset version must be up_to_date even on first check."""
    from wsa_updater import checker as c

    rel = select_release(SAMPLE_RELEASES, prefer_lts=True)
    assert rel is not None
    cfg = default_config()
    asset = select_asset(rel, cfg["asset_pattern"], cfg["fallback_patterns"])
    assert asset is not None
    ver = version_from_asset_name(asset["name"])

    orig_fetch = c.fetch_releases
    orig_installed = c.get_installed_wsa_version

    def fake_fetch(repo, per_page=30):
        return SAMPLE_RELEASES

    def fake_installed(install_dir):
        return {"version": ver, "package_full_name": "x", "source": "manifest"}

    c.fetch_releases = fake_fetch
    c.get_installed_wsa_version = fake_installed
    try:
        cfg = default_config()
        cfg["last_release_tag"] = ""
        cfg["last_asset_name"] = ""
        result = c.check_updates(cfg)
    finally:
        c.fetch_releases = orig_fetch
        c.get_installed_wsa_version = orig_installed

    assert result["ok"] is True
    assert result["installed_version"] == ver
    assert result["asset_version"] == ver
    assert result["has_update"] is False
    assert result["reason"] == "up_to_date"
    assert result["should_notify"] is False


def test_decision_version_mismatch_notifies_once():
    from wsa_updater import checker as c

    cfg = default_config()
    rel = select_release(SAMPLE_RELEASES, prefer_lts=True)
    asset = select_asset(rel, cfg["asset_pattern"], cfg["fallback_patterns"])
    ver = version_from_asset_name(asset["name"])
    older = "2305.40000.5.0"

    orig_fetch = c.fetch_releases
    orig_installed = c.get_installed_wsa_version
    c.fetch_releases = lambda repo, per_page=30: SAMPLE_RELEASES
    c.get_installed_wsa_version = lambda install_dir: {
        "version": older,
        "package_full_name": "",
        "source": "appx",
    }
    try:
        cfg1 = default_config()
        cfg1["last_release_tag"] = ""
        cfg1["last_asset_name"] = ""
        r1 = c.check_updates(cfg1)
        assert r1["has_update"] is True
        assert r1["reason"] == "version_mismatch"
        assert r1["should_notify"] is True
        assert r1["asset_version"] == ver

        cfg2 = default_config()
        cfg2["last_release_tag"] = r1["release_tag"]
        cfg2["last_asset_name"] = r1["asset_name"]
        r2 = c.check_updates(cfg2)
        assert r2["has_update"] is True
        assert r2["should_notify"] is False
        assert r2["reason"] == "version_mismatch"
    finally:
        c.fetch_releases = orig_fetch
        c.get_installed_wsa_version = orig_installed


def test_decision_no_local_wsa():
    from wsa_updater import checker as c

    orig_fetch = c.fetch_releases
    orig_installed = c.get_installed_wsa_version
    c.fetch_releases = lambda repo, per_page=30: SAMPLE_RELEASES
    c.get_installed_wsa_version = lambda install_dir: {
        "version": None,
        "package_full_name": "",
        "source": "none",
    }
    try:
        cfg = default_config()
        cfg["last_release_tag"] = ""
        result = c.check_updates(cfg)
        assert result["ok"] is True
        assert result["has_update"] is True
        assert result["reason"] == "no_local_wsa"
        assert result["should_notify"] is True
    finally:
        c.fetch_releases = orig_fetch
        c.get_installed_wsa_version = orig_installed


def test_notifier_body_uses_real_newlines():
    import inspect

    from wsa_updater import notifier

    src = inspect.getsource(notifier)
    assert 'body = "\\n".join(lines)' in src or 'body = "\\n".join' in src
    # Ensure we did not leave the broken double-escaped join
    assert '\\\\n' not in src
