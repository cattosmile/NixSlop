#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update the native CC Switch source build to the latest GitHub release."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (  # noqa: E402
    fetch_github_latest_release,
    file_transaction,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.nix import nix_command  # noqa: E402

HASHES_FILE = Path(__file__).parent / "hashes.json"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
HASH_MISMATCH = re.compile(r"got:\s+(sha256-[A-Za-z0-9+/=]+)")


def prefetch_source(version: str) -> str:
    """Return the unpacked NAR hash used by fetchFromGitHub."""
    url = (
        "https://github.com/farion1231/cc-switch/archive/refs/tags/"
        f"v{version}.tar.gz"
    )
    result = nix_command(
        ["store", "prefetch-file", "--json", "--unpack", url],
    )
    data = json.loads(result.stdout)
    source_hash = data.get("hash")
    if not isinstance(source_hash, str) or not source_hash.startswith("sha256-"):
        raise RuntimeError("nix store prefetch-file returned no SRI source hash")
    return source_hash


def calculate_fixed_output_hash(installable: str) -> str:
    """Build a fake-hashed dependency derivation and return Nix's real hash."""
    result = nix_command(
        ["build", "--no-link", installable],
        check=False,
    )
    output = result.stdout + result.stderr
    matches = HASH_MISMATCH.findall(output)
    if result.returncode == 0:
        raise RuntimeError(f"fake-hashed derivation unexpectedly built: {installable}")
    if len(matches) != 1:
        raise RuntimeError(
            f"could not determine exactly one hash for {installable}:\n{output}"
        )
    return matches[0]


def main() -> None:
    """Update source, Cargo vendor, and pnpm dependency hashes atomically."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release("farion1231", "cc-switch")

    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    with file_transaction(HASHES_FILE):
        save_hashes(
            HASHES_FILE,
            {
                "version": latest,
                "sourceHash": prefetch_source(latest),
                "cargoHash": FAKE_HASH,
                "pnpmHash": FAKE_HASH,
            },
        )

        pnpm_hash = calculate_fixed_output_hash(
            ".#cc-switch.nativeApp.pnpmDeps"
        )
        data = load_hashes(HASHES_FILE)
        data["pnpmHash"] = pnpm_hash
        save_hashes(HASHES_FILE, data)

        cargo_hash = calculate_fixed_output_hash(
            ".#cc-switch.nativeApp.cargoDeps"
        )
        data = load_hashes(HASHES_FILE)
        data["cargoHash"] = cargo_hash
        save_hashes(HASHES_FILE, data)

    print(f"Updated native source build to {latest}")


if __name__ == "__main__":
    main()
