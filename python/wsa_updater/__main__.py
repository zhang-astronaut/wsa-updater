from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow `python -m wsa_updater` from repo/python
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from wsa_updater.checker import (  # type: ignore
        check_updates,
        default_config,
        load_config,
        persist_check_result,
        save_config,
    )
    from wsa_updater.downloader import download_asset  # type: ignore
    from wsa_updater.notifier import notify  # type: ignore
else:
    from .checker import (
        check_updates,
        default_config,
        load_config,
        persist_check_result,
        save_config,
    )
    from .downloader import download_asset
    from .notifier import notify

TASK_NAME = "WsaUpdater-CheckOnLogon"


def cmd_check(args: argparse.Namespace) -> int:
    cfg = load_config(Path(args.config) if args.config else None)
    try:
        result = check_updates(cfg)
    except Exception as exc:  # noqa: BLE001 - CLI boundary
        msg = f"WsaUpdater check failed: {exc}"
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc), "exit_code": 2}, ensure_ascii=False))
        else:
            print(msg, file=sys.stderr)
        return 2

    cfg = persist_check_result(cfg, result)
    if not args.dry_run:
        try:
            save_config(cfg, Path(args.config) if args.config else None)
        except OSError:
            pass

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif not args.quiet:
        print(f"Release : {result.get('release_tag')}")
        print(f"Asset   : {result.get('asset_name')}")
        print(f"Local   : {result.get('installed_version')} ({result.get('install_source')})")
        print(f"Update  : {result.get('has_update')} ({result.get('reason')})")

    should_notify = False
    if result.get("ok") and result.get("should_notify"):
        should_notify = True
    elif args.notify and result.get("ok"):
        should_notify = True
    elif result.get("ok") and cfg.get("notify_on_up_to_date") and not args.quiet and not args.json:
        should_notify = True
    if should_notify and not args.json:
        notify(result)

    return int(result.get("exit_code") or 0)


def cmd_download(args: argparse.Namespace) -> int:
    cfg = load_config(Path(args.config) if args.config else None)
    result = check_updates(cfg)
    if not result.get("ok") or not result.get("asset_url"):
        print(result.get("error") or "No asset", file=sys.stderr)
        return 3
    dest = download_asset(result, args.out or cfg.get("download_dir"))
    print(f"Saved: {dest}")
    print(
        "Install is always manual: extract into "
        f"{cfg.get('wsa_install_dir')} and re-register Appx as admin."
    )
    return 0


def cmd_init_config(args: argparse.Namespace) -> int:
    path = Path(args.config) if args.config else None
    cfg = default_config()
    saved = save_config(cfg, path)
    print(f"Wrote {saved}")
    return 0


def cmd_install_task(args: argparse.Namespace) -> int:
    """Register logon task by invoking the PowerShell installer in this repo."""
    root = Path(__file__).resolve().parents[2]
    script = root / "powershell" / "Install-WsaUpdater.ps1"
    if not script.is_file():
        print(f"Missing {script}", file=sys.stderr)
        return 2
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
    ]
    if args.force:
        cmd.append("-Force")
    proc = subprocess_run(cmd)
    return proc.returncode


def cmd_uninstall_task(args: argparse.Namespace) -> int:
    root = Path(__file__).resolve().parents[2]
    script = root / "powershell" / "Uninstall-WsaUpdater.ps1"
    if not script.is_file():
        print(f"Missing {script}", file=sys.stderr)
        return 2
    proc = subprocess_run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    )
    return proc.returncode


def subprocess_run(cmd: list) -> "subprocess.CompletedProcess":  # type: ignore[valid-type]
    import subprocess

    return subprocess.run(cmd, check=False)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="wsa-updater", description="WSABuilds WSA update checker")
    sub = p.add_subparsers(dest="command", required=True)

    c = sub.add_parser("check", help="Check GitHub for a newer WSABuilds asset")
    c.add_argument("--config", help="Path to config.json")
    c.add_argument("--json", action="store_true", help="Print JSON result")
    c.add_argument("--quiet", action="store_true", help="Do not print human summary")
    c.add_argument("--notify", action="store_true", help="Force notify even if -Quiet")
    c.add_argument("--dry-run", action="store_true", help="Do not write config state")
    c.set_defaults(func=cmd_check)

    d = sub.add_parser("download", help="Download matched asset (no auto-install)")
    d.add_argument("--config", help="Path to config.json")
    d.add_argument("--out", help="Download directory override")
    d.add_argument(
        "--download-only",
        action="store_true",
        default=False,
        help="Print install reminder (default behavior never auto-installs)",
    )
    d.set_defaults(func=cmd_download)

    i = sub.add_parser("init-config", help="Write default config.json")
    i.add_argument("--config", help="Path to config.json")
    i.set_defaults(func=cmd_init_config)

    t = sub.add_parser("install-task", help="Register logon scheduled task (PowerShell)")
    t.add_argument("--force", action="store_true")
    t.set_defaults(func=cmd_install_task)

    u = sub.add_parser("uninstall-task", help="Remove logon scheduled task")
    u.set_defaults(func=cmd_uninstall_task)

    return p


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
