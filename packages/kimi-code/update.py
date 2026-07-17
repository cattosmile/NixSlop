#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update the packaged Kimi Code release binaries."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    fetch_npm_version,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"
PLATFORMS = {
    "x86_64-linux": "linux-x64",
    "aarch64-linux": "linux-arm64",
}


def main() -> None:
    """Update Kimi Code to the latest stable npm release."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_npm_version("@moonshot-ai/kimi-code")

    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    hashes = calculate_platform_hashes(
        "https://github.com/MoonshotAI/kimi-code/releases/download/"
        "%40moonshot-ai/kimi-code%40{version}/kimi-code-{platform}.zip",
        PLATFORMS,
        version=latest,
    )
    save_hashes(
        HASHES_FILE,
        {
            "version": latest,
            "hashes": {platform: hashes[platform] for platform in PLATFORMS},
        },
    )
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
