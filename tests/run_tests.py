"""Minimal test runner (no pytest required): python tests/run_tests.py"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


def main() -> int:
    path = Path(__file__).resolve().parent / "test_checker.py"
    spec = importlib.util.spec_from_file_location("test_checker", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    failed = 0
    for name in dir(mod):
        if not name.startswith("test_"):
            continue
        try:
            getattr(mod, name)()
            print("PASS", name)
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print("FAIL", name, exc)
    print("FAILED", failed)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
