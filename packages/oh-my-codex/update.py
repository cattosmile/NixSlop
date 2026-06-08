#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nodejs --command python3

"""Update script for the oh-my-codex package.

npm is the stable release authority for oh-my-codex, while the Nix build uses
matching GitHub tags so package-lock.json and Cargo.lock are available for
reproducible npm and Rust dependency builds.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (  # noqa: E402
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_npm_version,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import DUMMY_SHA256_HASH  # noqa: E402
from updater.nix import NixCommandError  # noqa: E402

HASHES_FILE = Path(__file__).parent / "hashes.json"
CARGO_LOCK_FILE = Path(__file__).parent / "Cargo.lock"


def main() -> None:
    """Update oh-my-codex source and npm dependency hashes."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_npm_version("oh-my-codex")

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    url = f"https://github.com/Yeachan-Heo/oh-my-codex/archive/refs/tags/v{latest}.tar.gz"

    print("Calculating source hash...")
    source_hash = calculate_url_hash(url, unpack=True)

    print("Refreshing Cargo.lock...")
    cargo_lock = fetch_text(
        f"https://raw.githubusercontent.com/Yeachan-Heo/oh-my-codex/v{latest}/Cargo.lock"
    )
    if CARGO_LOCK_FILE.exists():
        CARGO_LOCK_FILE.chmod(0o644)
    CARGO_LOCK_FILE.write_text(cargo_lock)

    data = {
        "version": latest,
        "hash": source_hash,
        "npmDepsHash": DUMMY_SHA256_HASH,
    }
    save_hashes(HASHES_FILE, data)

    try:
        npm_deps_hash = calculate_dependency_hash(
            ".#oh-my-codex", "npmDepsHash", HASHES_FILE, data
        )
        data["npmDepsHash"] = npm_deps_hash
        save_hashes(HASHES_FILE, data)
    except (ValueError, NixCommandError) as e:
        print(f"Error: {e}")
        raise SystemExit(1) from e

    print(f"Updated oh-my-codex to {latest}")


if __name__ == "__main__":
    main()
