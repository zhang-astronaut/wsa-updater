"""WSA updater: check WSABuilds releases on Windows."""

from .checker import (
    check_updates,
    default_config,
    load_config,
    save_config,
)
from .downloader import download_asset
from .notifier import notify

__all__ = [
    "check_updates",
    "default_config",
    "load_config",
    "save_config",
    "download_asset",
    "notify",
]
__version__ = "0.1.0"
